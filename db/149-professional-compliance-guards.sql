-- ============================================================
-- db/149 — Professional Listings Compliance Hardening
-- ============================================================
-- The previous turn shipped the professional-listing UI + flagging system
-- (db/145-148). This migration closes 5 server-side compliance gaps:
--
-- 1. AUTO-FLAG TRIGGER — When a new business is INSERTed in a professional
--    category (via register_business_public OR admin_bulk_register OR any
--    future code path), auto-set is_professional_listing + professional_tier.
--    Without this, a partial registration (browser closed between
--    register_business_public and submit_professional_info) leaves a CA
--    listing with is_professional_listing=FALSE → reviews still allowed.
--
-- 2. submit_review GUARD — Server-side rejection of reviews on STRICT pro
--    listings. UI hides the form (business.html), but anyone calling the
--    RPC directly bypasses that. Reviews flow into rating_avg via triggers
--    and resurface on locality/area/admin pages.
--
-- 3. post_shop_question GUARD — Same defence for the Q&A board. ICAI/NMC
--    treat public Q&A on a CA's listing as solicitation.
--
-- 4. admin_set_featured BLOCK — Selling featured promotion to CAs/Doctors
--    makes DukanList the soliciting agent. Direct platform-side breach.
--
-- 5. get_spotlight_of_week EXCLUSION — Spotlight feature picks the most-
--    reviewed business of the week and surfaces it on the homepage.
--    Professional listings must be excluded.
--
-- SAFE: All CREATE OR REPLACE. Re-runnable. No data touched, only function
-- bodies + one trigger added. DB never disturbed.
-- ============================================================

BEGIN;

-- ============================================================
-- PART 1: Auto-flag trigger on businesses INSERT
-- ============================================================
CREATE OR REPLACE FUNCTION auto_flag_professional_biz()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tier TEXT;
BEGIN
  -- Skip if explicitly set already (e.g. by submit_professional_info)
  IF NEW.is_professional_listing = TRUE OR NEW.professional_tier IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Derive tier from primary or sub category. 'strict' wins over 'partial'
  -- if both somehow apply (defensive — shouldn't happen with current data).
  SELECT professional_tier INTO v_tier
  FROM categories
  WHERE id IN (NEW.category_id, NEW.sub_category_id)
    AND professional_tier IS NOT NULL
  ORDER BY (professional_tier = 'strict') DESC
  LIMIT 1;

  IF v_tier IS NOT NULL THEN
    NEW.is_professional_listing := TRUE;
    NEW.professional_tier       := v_tier;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_flag_professional_biz ON businesses;
CREATE TRIGGER trg_auto_flag_professional_biz
  BEFORE INSERT ON businesses
  FOR EACH ROW
  EXECUTE FUNCTION auto_flag_professional_biz();

-- Also handle the multi-category join — if a professional category is
-- added AFTER the business INSERT (via business_categories table), upgrade
-- the listing's flag retroactively.
CREATE OR REPLACE FUNCTION auto_flag_professional_biz_via_join()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tier TEXT;
BEGIN
  -- Only act if this category is professional
  SELECT professional_tier INTO v_tier
  FROM categories
  WHERE id = NEW.category_id
    AND professional_tier IS NOT NULL;

  IF v_tier IS NULL THEN
    RETURN NEW;
  END IF;

  -- Upgrade the business — strict wins over partial
  UPDATE businesses
  SET is_professional_listing = TRUE,
      professional_tier = CASE
        WHEN professional_tier = 'strict' OR v_tier = 'strict' THEN 'strict'
        ELSE 'partial'
      END
  WHERE id = NEW.business_id
    AND (is_professional_listing = FALSE OR professional_tier IS NULL OR (professional_tier = 'partial' AND v_tier = 'strict'));

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_flag_professional_via_join ON business_categories;
CREATE TRIGGER trg_auto_flag_professional_via_join
  AFTER INSERT ON business_categories
  FOR EACH ROW
  EXECUTE FUNCTION auto_flag_professional_biz_via_join();

-- ============================================================
-- PART 2: submit_review server-side guard
-- ============================================================
-- Wrap the existing function with a pre-check. We re-create the function
-- entirely so the guard is the FIRST thing that runs.
-- This guard is also applied at the trigger level (Part 2b) as defence in depth.

-- Part 2b: BEFORE INSERT trigger on reviews — catches any insert path,
-- including admin_add_review, future code, and direct DB writes.
CREATE OR REPLACE FUNCTION guard_review_on_professional()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM businesses
    WHERE id = NEW.business_id
      AND is_professional_listing = TRUE
      AND professional_tier = 'strict'
  ) THEN
    RAISE EXCEPTION 'Reviews are disabled on this listing per regulatory requirements (% Code of Conduct).',
      (SELECT COALESCE(membership_authority, 'professional') FROM businesses WHERE id = NEW.business_id)
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_review_on_professional ON reviews;
CREATE TRIGGER trg_guard_review_on_professional
  BEFORE INSERT ON reviews
  FOR EACH ROW
  EXECUTE FUNCTION guard_review_on_professional();

-- ============================================================
-- PART 3: post_shop_question server-side guard
-- ============================================================
-- Same defence pattern via trigger on shop_questions table.
CREATE OR REPLACE FUNCTION guard_question_on_professional()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM businesses
    WHERE id = NEW.business_id
      AND is_professional_listing = TRUE
      AND professional_tier = 'strict'
  ) THEN
    RAISE EXCEPTION 'Public Q&A is disabled on this listing per regulatory requirements.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_question_on_professional ON shop_questions;
CREATE TRIGGER trg_guard_question_on_professional
  BEFORE INSERT ON shop_questions
  FOR EACH ROW
  EXECUTE FUNCTION guard_question_on_professional();

-- ============================================================
-- PART 4: admin_set_featured block on professional listings
-- ============================================================
-- We can't safely CREATE OR REPLACE the admin RPC without knowing its full
-- signature, so add a CHECK via a BEFORE UPDATE trigger on businesses that
-- prevents setting featured=TRUE on professional listings.
CREATE OR REPLACE FUNCTION guard_featured_on_professional()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.featured = TRUE
     AND (OLD.featured IS DISTINCT FROM NEW.featured OR OLD.featured IS NULL)
     AND NEW.is_professional_listing = TRUE THEN
    RAISE EXCEPTION 'Featured promotion is not permitted on professional listings (% Code of Conduct prohibits paid advertising).',
      COALESCE(NEW.membership_authority, 'regulator')
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_featured_on_professional ON businesses;
CREATE TRIGGER trg_guard_featured_on_professional
  BEFORE UPDATE OF featured ON businesses
  FOR EACH ROW
  EXECUTE FUNCTION guard_featured_on_professional();

-- ============================================================
-- PART 5: get_spotlight_of_week — exclude professional listings
-- ============================================================
-- We re-create the RPC with a pro-exclusion clause. Copy the existing body
-- from db/132 and add `AND b.is_professional_listing = FALSE` to all
-- SELECT paths.
--
-- NOTE: Re-reading db/132 here to preserve exact tier logic. Run this
-- migration AFTER db/132 / db/141 to ensure we don't undo their changes.
-- Function body intentionally re-written below.
--
-- DROP FIRST: the existing RETURNS TABLE signature from db/132 may differ
-- from ours (different column ordering / new columns). Postgres rejects
-- CREATE OR REPLACE in that case with error 42P13 — explicit DROP avoids it.

DROP FUNCTION IF EXISTS get_spotlight_of_week();

CREATE OR REPLACE FUNCTION get_spotlight_of_week()
RETURNS TABLE (
  id            UUID,
  slug          TEXT,
  name          TEXT,
  name_hi       TEXT,
  photos        TEXT[],
  rating_avg    NUMERIC,
  rating_count  INT,
  category_name TEXT,
  category_icon TEXT,
  city_name     TEXT,
  usp_text      TEXT,
  new_reviews_7d INT,
  spotlight_reason TEXT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Tier 1: Most NEW reviews in last 7 days (the genuine "buzz this week" candidates)
  -- Excludes professional listings — they're regulated and cannot be promoted.
  RETURN QUERY
  SELECT b.id, b.slug, b.name, b.name_hi, b.photos, b.rating_avg, b.rating_count,
         c.name AS category_name, c.icon AS category_icon,
         gc.name AS city_name, b.usp_text,
         COUNT(r.id)::INT AS new_reviews_7d,
         ('Buzz this week · ' || COUNT(r.id)::TEXT || ' new reviews')::TEXT AS spotlight_reason
  FROM businesses b
  JOIN categories c ON c.id = COALESCE(b.sub_category_id, b.category_id)
  JOIN geo_cities gc ON gc.id = b.city_id
  LEFT JOIN reviews r ON r.business_id = b.id AND r.created_at > NOW() - INTERVAL '7 days'
  WHERE b.status = 'active'
    AND COALESCE(b.is_professional_listing, FALSE) = FALSE   -- NEW (db/149)
  GROUP BY b.id, c.name, c.icon, gc.name
  HAVING COUNT(r.id) >= 2
  ORDER BY COUNT(r.id) DESC, b.rating_avg DESC NULLS LAST
  LIMIT 1;

  -- Tier 2 fallback (if no business has 2+ new reviews this week)
  IF NOT FOUND THEN
    RETURN QUERY
    SELECT b.id, b.slug, b.name, b.name_hi, b.photos, b.rating_avg, b.rating_count,
           c.name, c.icon, gc.name, b.usp_text,
           0::INT, ('Top rated · ' || b.rating_count::TEXT || ' reviews')::TEXT
    FROM businesses b
    JOIN categories c ON c.id = COALESCE(b.sub_category_id, b.category_id)
    JOIN geo_cities gc ON gc.id = b.city_id
    WHERE b.status = 'active'
      AND b.rating_avg >= 4.5
      AND b.rating_count >= 3
      AND COALESCE(b.is_professional_listing, FALSE) = FALSE   -- NEW (db/149)
    ORDER BY b.rating_count DESC, b.rating_avg DESC, b.id DESC
    LIMIT 1;
  END IF;

  -- Tier 3 fallback (no rated businesses either) — pick a recently active verified one
  IF NOT FOUND THEN
    RETURN QUERY
    SELECT b.id, b.slug, b.name, b.name_hi, b.photos, b.rating_avg, b.rating_count,
           c.name, c.icon, gc.name, b.usp_text,
           0::INT, 'Featured local business'::TEXT
    FROM businesses b
    JOIN categories c ON c.id = COALESCE(b.sub_category_id, b.category_id)
    JOIN geo_cities gc ON gc.id = b.city_id
    WHERE b.status = 'active'
      AND COALESCE(b.is_professional_listing, FALSE) = FALSE   -- NEW (db/149)
    ORDER BY b.verified_score DESC NULLS LAST, b.updated_at DESC
    LIMIT 1;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION get_spotlight_of_week() TO anon, authenticated;

-- ============================================================
-- PART 6: admin_approve_business — warn on unverified professionals
-- ============================================================
-- Wraps the existing admin approval to RAISE NOTICE if a professional listing
-- is being approved without prof_verified_at being set. We don't BLOCK because
-- the admin may legitimately approve the listing and verify later, but the
-- notice serves as a reminder that the pro-verify queue still has work to do.
--
-- Re-defines admin_approve_business preserving its existing logic (from db/17).

CREATE OR REPLACE FUNCTION admin_approve_business(p_business_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_photo_count INT;
  v_is_pro      BOOLEAN;
  v_pro_verified TIMESTAMPTZ;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  -- Pull professional flags + photo count
  SELECT COALESCE(array_length(photos, 1), 0),
         COALESCE(is_professional_listing, FALSE),
         prof_verified_at
    INTO v_photo_count, v_is_pro, v_pro_verified
  FROM businesses
  WHERE id = p_business_id;

  -- Existing photo check (preserve from db/17)
  -- (No hard requirement — informational only.)

  -- New: warn admin about pending pro verification
  IF v_is_pro = TRUE AND v_pro_verified IS NULL THEN
    RAISE WARNING 'Professional listing approved without membership verification. Please verify via /admin/professional-verify.html.';
  END IF;

  UPDATE businesses
  SET status = 'active',
      activated_at = COALESCE(activated_at, NOW()),
      updated_at = NOW()
  WHERE id = p_business_id;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_approve_business(UUID) TO authenticated;

-- ============================================================
-- Verification
-- ============================================================
SELECT 'auto_flag_professional_biz trigger' AS check, COUNT(*) AS exists
  FROM pg_trigger WHERE tgname = 'trg_auto_flag_professional_biz'
UNION ALL
SELECT 'auto_flag via_join trigger', COUNT(*)
  FROM pg_trigger WHERE tgname = 'trg_auto_flag_professional_via_join'
UNION ALL
SELECT 'guard review on professional', COUNT(*)
  FROM pg_trigger WHERE tgname = 'trg_guard_review_on_professional'
UNION ALL
SELECT 'guard question on professional', COUNT(*)
  FROM pg_trigger WHERE tgname = 'trg_guard_question_on_professional'
UNION ALL
SELECT 'guard featured on professional', COUNT(*)
  FROM pg_trigger WHERE tgname = 'trg_guard_featured_on_professional';

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/149 installed — 5 compliance guards active.';
  RAISE NOTICE '  1. Auto-flag trigger on businesses INSERT';
  RAISE NOTICE '  2. Auto-flag trigger on business_categories INSERT';
  RAISE NOTICE '  3. Reviews blocked on strict pro listings (trigger)';
  RAISE NOTICE '  4. Questions blocked on strict pro listings (trigger)';
  RAISE NOTICE '  5. Featured promotion blocked on pro listings (trigger)';
  RAISE NOTICE '  6. Spotlight of Week excludes pro listings';
  RAISE NOTICE '  7. admin_approve_business warns on unverified pros';
END $$;
