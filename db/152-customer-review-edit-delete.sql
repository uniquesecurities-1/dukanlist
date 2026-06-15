-- ============================================================
-- db/152 — Customer-controlled review edit + soft delete
-- ============================================================
-- User feedback: Customer should be able to (a) UPDATE their review if the
-- business resolved the issue, and (b) DELETE their review if they made
-- a mistake. Industry standard (Google, Justdial, Yelp all allow this);
-- legally appropriate (DPDP Act 2023 right to rectification + customer's
-- own data).
--
-- DESIGN:
--   1. UPDATE keeps history — original_rating + original_text preserved on
--      first edit. Customers can update max 3 times, 30-day cooldown.
--      Public listing shows "Updated X ago" tag with collapsible "View
--      original" — full transparency, no silent rewrites.
--   2. DELETE is soft — status flips to 'removed' (already in CHECK
--      constraint). Audit trail preserved. Rating-avg auto-recalculates
--      via existing trg_review_rating trigger which filters by
--      status='active'.
--   3. Both RPCs identify the customer via phone-hash: caller passes their
--      phone, server hashes it (SHA-256 of '+91XXXXXXXXXX' to match the
--      same format submit_review uses), compares to review's stored hash.
--      Only original submitter can edit/delete.
--   4. Anti-abuse: max 3 updates, 30-day cooldown between updates,
--      no rate-limit on delete (delete is rarer + lower abuse vector).
--
-- SAFE: Schema ADDs only (no drops/changes). RPCs are SECURITY DEFINER
-- with strict input validation. Re-runnable.
-- ============================================================

BEGIN;

-- ============================================================
-- PART 0: Ensure pgcrypto extension (needed by digest() in RPCs)
-- ============================================================
-- Without this, the RPC bodies create cleanly but FAIL at runtime
-- with 'function digest(text, unknown) does not exist'. This is the
-- most common reason for db/152 deploy failures on fresh Supabase
-- projects. Safe to re-run; CREATE IF NOT EXISTS is idempotent.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================
-- PART 1: New columns on reviews table
-- ============================================================
ALTER TABLE reviews
  ADD COLUMN IF NOT EXISTS original_rating   SMALLINT,           -- preserved on first edit
  ADD COLUMN IF NOT EXISTS original_text     TEXT,               -- preserved on first edit
  ADD COLUMN IF NOT EXISTS update_count      SMALLINT DEFAULT 0, -- 0..3
  ADD COLUMN IF NOT EXISTS last_updated_at   TIMESTAMPTZ,        -- for cooldown + display
  ADD COLUMN IF NOT EXISTS deleted_at        TIMESTAMPTZ,        -- soft-delete timestamp
  ADD COLUMN IF NOT EXISTS deleted_by_customer BOOLEAN DEFAULT FALSE;

-- Index for "my reviews" lookups (admin debugging)
CREATE INDEX IF NOT EXISTS idx_reviews_updated_at ON reviews(last_updated_at) WHERE last_updated_at IS NOT NULL;

-- ============================================================
-- PART 2: RPC — update_my_review (with history preservation)
-- ============================================================
CREATE OR REPLACE FUNCTION update_my_review(
  p_phone      TEXT,        -- 10 digits OR with +91 prefix
  p_review_id  UUID,
  p_new_rating SMALLINT,
  p_new_text   TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hash        TEXT;
  v_review      reviews%ROWTYPE;
  v_normalised  TEXT;
BEGIN
  -- Validate rating
  IF p_new_rating < 1 OR p_new_rating > 5 THEN
    RAISE EXCEPTION 'Rating must be 1-5';
  END IF;

  -- Normalise phone to '+91XXXXXXXXXX' format (same as submit_review)
  v_normalised := regexp_replace(COALESCE(p_phone, ''), '\D', '', 'g');
  IF LENGTH(v_normalised) > 10 THEN
    v_normalised := RIGHT(v_normalised, 10);
  END IF;
  IF LENGTH(v_normalised) <> 10 THEN
    RAISE EXCEPTION 'Invalid phone number (must be 10 digits)';
  END IF;
  v_hash := encode(digest('+91' || v_normalised, 'sha256'), 'hex');

  -- Fetch review and verify ownership
  SELECT * INTO v_review
  FROM reviews
  WHERE id = p_review_id
    AND customer_phone_hash = v_hash
    AND status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Review not found, already deleted, or not owned by this phone';
  END IF;

  -- Anti-abuse: max 3 updates
  IF v_review.update_count >= 3 THEN
    RAISE EXCEPTION 'You have updated this review the maximum of 3 times';
  END IF;

  -- Anti-abuse: 30-day cooldown between updates (skipped on first edit)
  IF v_review.last_updated_at IS NOT NULL
     AND v_review.last_updated_at > NOW() - INTERVAL '30 days' THEN
    RAISE EXCEPTION 'Please wait 30 days between updates (last: %)', v_review.last_updated_at;
  END IF;

  -- On FIRST edit: preserve original. On subsequent: just overwrite (history
  -- chain is still preserved as the very-first original_*).
  IF v_review.update_count = 0 THEN
    UPDATE reviews
    SET original_rating   = rating,
        original_text     = text,
        rating            = p_new_rating,
        text              = p_new_text,
        update_count      = 1,
        last_updated_at   = NOW()
    WHERE id = p_review_id;
  ELSE
    UPDATE reviews
    SET rating            = p_new_rating,
        text              = p_new_text,
        update_count      = update_count + 1,
        last_updated_at   = NOW()
    WHERE id = p_review_id;
  END IF;

  -- Recompute rating-avg via the existing trigger (fires on UPDATE)
  -- (no manual call needed; trg_review_rating handles it)

  RETURN jsonb_build_object(
    'success', TRUE,
    'review_id', p_review_id,
    'update_count', v_review.update_count + 1,
    'updates_remaining', 3 - (v_review.update_count + 1)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION update_my_review(TEXT, UUID, SMALLINT, TEXT) TO anon, authenticated;

-- ============================================================
-- PART 3: RPC — delete_my_review (soft delete)
-- ============================================================
CREATE OR REPLACE FUNCTION delete_my_review(
  p_phone     TEXT,
  p_review_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hash       TEXT;
  v_normalised TEXT;
  v_biz_id     UUID;
BEGIN
  -- Normalise phone identically to submit_review / update_my_review
  v_normalised := regexp_replace(COALESCE(p_phone, ''), '\D', '', 'g');
  IF LENGTH(v_normalised) > 10 THEN
    v_normalised := RIGHT(v_normalised, 10);
  END IF;
  IF LENGTH(v_normalised) <> 10 THEN
    RAISE EXCEPTION 'Invalid phone number (must be 10 digits)';
  END IF;
  v_hash := encode(digest('+91' || v_normalised, 'sha256'), 'hex');

  -- Verify ownership then soft-delete
  UPDATE reviews
  SET status              = 'removed',
      deleted_at          = NOW(),
      deleted_by_customer = TRUE
  WHERE id = p_review_id
    AND customer_phone_hash = v_hash
    AND status = 'active'
  RETURNING business_id INTO v_biz_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Review not found, already deleted, or not owned by this phone';
  END IF;

  -- Trigger trg_review_rating handles rating_avg recomputation automatically

  RETURN jsonb_build_object(
    'success', TRUE,
    'review_id', p_review_id,
    'business_id', v_biz_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION delete_my_review(TEXT, UUID) TO anon, authenticated;

-- ============================================================
-- PART 4: Helper RPC — verify_my_review_ownership (for UI gating)
-- ============================================================
-- The UI needs to know which reviews on the current page belong to the
-- viewer (based on phone stored in localStorage). Returns the IDs of all
-- reviews on a given business whose phone-hash matches.
CREATE OR REPLACE FUNCTION my_reviews_for_business(
  p_phone       TEXT,
  p_business_id UUID
)
RETURNS TABLE (
  review_id        UUID,
  rating           SMALLINT,
  text             TEXT,
  original_rating  SMALLINT,
  original_text    TEXT,
  update_count     SMALLINT,
  last_updated_at  TIMESTAMPTZ,
  created_at       TIMESTAMPTZ
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hash       TEXT;
  v_normalised TEXT;
BEGIN
  v_normalised := regexp_replace(COALESCE(p_phone, ''), '\D', '', 'g');
  IF LENGTH(v_normalised) > 10 THEN
    v_normalised := RIGHT(v_normalised, 10);
  END IF;
  IF LENGTH(v_normalised) <> 10 THEN
    RETURN;  -- empty result on invalid phone
  END IF;
  v_hash := encode(digest('+91' || v_normalised, 'sha256'), 'hex');

  RETURN QUERY
  SELECT r.id, r.rating, r.text, r.original_rating, r.original_text,
         r.update_count, r.last_updated_at, r.created_at
  FROM reviews r
  WHERE r.business_id = p_business_id
    AND r.customer_phone_hash = v_hash
    AND r.status = 'active';
END;
$$;

GRANT EXECUTE ON FUNCTION my_reviews_for_business(TEXT, UUID) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/152 installed.';
  RAISE NOTICE '  Schema: 6 new columns on reviews (history + soft-delete)';
  RAISE NOTICE '  RPC update_my_review(phone, id, rating, text) — max 3, 30-day cooldown';
  RAISE NOTICE '  RPC delete_my_review(phone, id) — soft-delete to status=removed';
  RAISE NOTICE '  RPC my_reviews_for_business(phone, biz_id) — UI ownership lookup';
END $$;
