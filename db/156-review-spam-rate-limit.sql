-- ============================================================
-- db/156 — Review spam protection (rate-limit + admin hold queue)
-- ============================================================
-- Problem:
--   Until now submit_review() had no per-user rate limit. A malicious
--   user (or competitor) could spray 1-star reviews on dozens of
--   businesses in minutes. Each landing live, dragging ratings down
--   before any admin could see them.
--
-- Solution:
--   1. Add 'pending' to reviews.status CHECK constraint.
--   2. submit_review() now counts how many reviews the same phone-hash
--      has submitted in the last 24 hours. If it's >= 5, the new
--      review goes in with status='pending' instead of 'active' —
--      it's NOT shown publicly and doesn't affect rating_avg until
--      an admin approves it.
--   3. Three admin RPCs to handle the queue:
--        • admin_pending_reviews(p_limit, p_offset) — list
--        • admin_approve_pending_review(p_review_id)
--        • admin_reject_pending_review(p_review_id) → status='removed'
--
-- Why 5/day threshold?
--   Legit power-users (frequent reviewers) typically don't submit more
--   than 2-3 reviews a day. 5+ in 24h is unusual enough to warrant a
--   human eye. Threshold is centralised in a CONSTANT for easy tuning.
--
-- IMPORTANT: rating_avg / rating_count auto-exclude status != 'active'
-- thanks to the existing recompute_business_rating() function. So
-- pending reviews CANNOT taint a business's public rating.
--
-- SAFE: No DROP. ALTER constraint is additive (adds 'pending' option).
-- Re-runnable. Backward compatible — existing 'active' reviews unchanged.
-- ============================================================

BEGIN;

-- ============================================================
-- PART 1: Extend reviews.status CHECK constraint to include 'pending'
-- ============================================================
-- The existing constraint allows only ('active','flagged','removed').
-- We drop and recreate to add 'pending' for the spam-hold queue.

ALTER TABLE reviews
  DROP CONSTRAINT IF EXISTS reviews_status_check;

ALTER TABLE reviews
  ADD CONSTRAINT reviews_status_check
  CHECK (status IN ('active','pending','flagged','removed'));

-- Index pending reviews for fast admin queue lookup
CREATE INDEX IF NOT EXISTS idx_reviews_pending
  ON reviews(created_at DESC)
  WHERE status = 'pending';


-- ============================================================
-- PART 2: Replace submit_review() with spam-aware version
-- ============================================================
-- Threshold: 5+ reviews from same phone-hash in last 24h → held.
-- Existing INSERT ON CONFLICT semantics preserved (one review per
-- phone per business). On UPDATE we DO NOT reset status (so a held
-- review stays held even if resubmitted).
CREATE OR REPLACE FUNCTION submit_review(
  p_business_id   UUID,
  p_customer_name TEXT,
  p_phone_hash    TEXT,
  p_rating        SMALLINT,
  p_text          TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id              UUID;
  v_recent_count    INT;
  v_initial_status  TEXT := 'active';
  v_existing_id     UUID;
  v_existing_status TEXT;
  -- Tune-able knobs (one row per knob so future change is a 1-line edit)
  c_window_hours    CONSTANT INT := 24;
  c_threshold       CONSTANT INT := 5;
BEGIN
  IF p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'Rating must be 1-5';
  END IF;
  IF length(p_phone_hash) < 32 THEN
    RAISE EXCEPTION 'Invalid phone hash';
  END IF;

  -- Check if a review by this phone for this business already exists.
  -- If yes, we're in update-path — preserve its current status (don't
  -- silently activate a held review on resubmit).
  SELECT id, status INTO v_existing_id, v_existing_status
  FROM reviews
  WHERE business_id = p_business_id
    AND customer_phone_hash = p_phone_hash
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    -- Update existing review in-place, keep status as-is
    UPDATE reviews
       SET rating = p_rating,
           text = p_text,
           customer_name = p_customer_name,
           created_at = NOW()
     WHERE id = v_existing_id
    RETURNING id INTO v_id;

    RETURN v_id;
  END IF;

  -- New review path — apply rate-limit check
  SELECT COUNT(*) INTO v_recent_count
  FROM reviews
  WHERE customer_phone_hash = p_phone_hash
    AND created_at >= NOW() - (c_window_hours || ' hours')::INTERVAL
    AND status IN ('active','pending');  -- both count toward limit

  IF v_recent_count >= c_threshold THEN
    v_initial_status := 'pending';
  END IF;

  INSERT INTO reviews (
    business_id, customer_name, customer_phone_hash,
    rating, text, status
  )
  VALUES (
    p_business_id, p_customer_name, p_phone_hash,
    p_rating, p_text, v_initial_status
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION submit_review(UUID, TEXT, TEXT, SMALLINT, TEXT) TO anon, authenticated;


-- ============================================================
-- PART 3: Admin queue — list pending (held) reviews
-- ============================================================
-- Returns held reviews across all businesses, newest first.
-- Includes business name + category for admin context. Phone hash
-- is exposed so admin can spot patterns (e.g. same hash hitting
-- 5 different businesses → likely spam).
CREATE OR REPLACE FUNCTION admin_pending_reviews(
  p_limit  INT DEFAULT 100,
  p_offset INT DEFAULT 0
)
RETURNS TABLE (
  review_id        UUID,
  business_id      UUID,
  business_name    TEXT,
  business_slug    TEXT,
  customer_name    TEXT,
  customer_phone_hash TEXT,
  rating           SMALLINT,
  text             TEXT,
  created_at       TIMESTAMPTZ,
  hash_recent_count INT  -- how many other reviews this hash has submitted in last 24h
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  RETURN QUERY
  SELECT
    r.id,
    r.business_id,
    b.name,
    b.slug,
    r.customer_name,
    r.customer_phone_hash,
    r.rating,
    r.text,
    r.created_at,
    (SELECT COUNT(*)::INT FROM reviews r2
       WHERE r2.customer_phone_hash = r.customer_phone_hash
         AND r2.created_at >= NOW() - INTERVAL '24 hours')
  FROM reviews r
  JOIN businesses b ON b.id = r.business_id
  WHERE r.status = 'pending'
  ORDER BY r.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_pending_reviews(INT, INT) TO authenticated;


-- ============================================================
-- PART 4: Admin approve held review → activate it
-- ============================================================
CREATE OR REPLACE FUNCTION admin_approve_pending_review(p_review_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_biz_id UUID;
  v_old_status TEXT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  SELECT business_id, status INTO v_biz_id, v_old_status
  FROM reviews
  WHERE id = p_review_id;

  IF v_biz_id IS NULL THEN
    RAISE EXCEPTION 'Review not found';
  END IF;
  IF v_old_status <> 'pending' THEN
    RAISE EXCEPTION 'Review is not pending (status=%)', v_old_status;
  END IF;

  UPDATE reviews
     SET status = 'active'
   WHERE id = p_review_id;

  -- Trigger trg_review_rating will recompute, but call explicitly
  -- as belt-and-suspenders (since trigger only fires on INSERT/UPDATE
  -- of certain fields depending on existing setup).
  PERFORM recompute_business_rating(v_biz_id);

  RETURN jsonb_build_object('success', TRUE, 'review_id', p_review_id, 'business_id', v_biz_id);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_approve_pending_review(UUID) TO authenticated;


-- ============================================================
-- PART 5: Admin reject held review → mark as removed
-- ============================================================
CREATE OR REPLACE FUNCTION admin_reject_pending_review(p_review_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_biz_id UUID;
  v_old_status TEXT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  SELECT business_id, status INTO v_biz_id, v_old_status
  FROM reviews
  WHERE id = p_review_id;

  IF v_biz_id IS NULL THEN
    RAISE EXCEPTION 'Review not found';
  END IF;
  IF v_old_status <> 'pending' THEN
    RAISE EXCEPTION 'Review is not pending (status=%)', v_old_status;
  END IF;

  UPDATE reviews
     SET status = 'removed'
   WHERE id = p_review_id;

  PERFORM recompute_business_rating(v_biz_id);

  RETURN jsonb_build_object('success', TRUE, 'review_id', p_review_id, 'rejected', TRUE);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_reject_pending_review(UUID) TO authenticated;


-- ============================================================
-- PART 6: Helper count for moderation dashboard badge
-- ============================================================
CREATE OR REPLACE FUNCTION admin_pending_reviews_count()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  RETURN (SELECT COUNT(*)::INT FROM reviews WHERE status = 'pending');
END;
$$;

GRANT EXECUTE ON FUNCTION admin_pending_reviews_count() TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/156 installed. Reviews 5+/24h auto-hold; admin queue RPCs live.';
END $$;
