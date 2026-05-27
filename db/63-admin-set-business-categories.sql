-- =====================================================
-- db/63-admin-set-business-categories.sql
-- =====================================================
-- USER REQUEST: 'Admin ko shopkeeper ki category update karne ka
-- option chahiye — abhi koi option nazar nahi aa raha.'
--
-- This adds ONE admin RPC:
--   admin_set_business_categories(p_business_id, p_category_ids,
--                                  p_primary_category_id)
--
--   • Wipes current business_categories rows for the business
--   • Inserts new ones (up to 5)
--   • Marks p_primary_category_id as is_primary=TRUE (one only)
--   • Existing trigger trg_sync_primary_cat keeps
--     businesses.category_id in sync automatically
--   • Admin-only (is_admin() gate)
--   • Returns TRUE on success
--
-- ZERO RISK: pure ADDITIVE — only adds a new RPC.
-- HOW TO RUN: Supabase SQL Editor → paste → Run.
-- =====================================================

BEGIN;

DROP FUNCTION IF EXISTS admin_set_business_categories(UUID, INT[], INT);

CREATE OR REPLACE FUNCTION admin_set_business_categories(
  p_business_id          UUID,
  p_category_ids         INT[],
  p_primary_category_id  INT
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_cid INT;
  v_count INT;
  v_primary_in_list BOOLEAN := FALSE;
BEGIN
  -- Admin gate
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  -- Validate business exists
  IF NOT EXISTS (SELECT 1 FROM businesses WHERE id = p_business_id) THEN
    RAISE EXCEPTION 'Business not found';
  END IF;

  -- Validate input
  IF p_category_ids IS NULL OR array_length(p_category_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'At least 1 category required';
  END IF;

  v_count := array_length(p_category_ids, 1);
  IF v_count > 5 THEN
    RAISE EXCEPTION 'Maximum 5 categories allowed (got %)', v_count;
  END IF;

  -- Validate all category IDs exist + active
  FOREACH v_cid IN ARRAY p_category_ids LOOP
    IF NOT EXISTS (SELECT 1 FROM categories WHERE id = v_cid AND active = TRUE) THEN
      RAISE EXCEPTION 'Category id % not found or inactive', v_cid;
    END IF;
    IF v_cid = p_primary_category_id THEN
      v_primary_in_list := TRUE;
    END IF;
  END LOOP;

  -- Ensure primary is in the list
  IF p_primary_category_id IS NULL OR NOT v_primary_in_list THEN
    -- Default primary = first in the array
    p_primary_category_id := p_category_ids[1];
  END IF;

  -- Wipe + reinsert (transactional)
  DELETE FROM business_categories WHERE business_id = p_business_id;

  FOREACH v_cid IN ARRAY p_category_ids LOOP
    INSERT INTO business_categories (business_id, category_id, is_primary)
    VALUES (p_business_id, v_cid, (v_cid = p_primary_category_id));
  END LOOP;

  -- Trigger trg_sync_primary_cat will update businesses.category_id automatically.
  -- But also force the sync explicitly in case trigger is missing/disabled.
  UPDATE businesses
    SET category_id = p_primary_category_id,
        updated_at = NOW()
    WHERE id = p_business_id;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_set_business_categories(UUID, INT[], INT) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- Smoke test
DO $$
DECLARE v_fn INT;
BEGIN
  SELECT COUNT(*) INTO v_fn FROM pg_proc WHERE proname = 'admin_set_business_categories';
  IF v_fn < 1 THEN RAISE EXCEPTION 'RPC missing'; END IF;
  RAISE NOTICE '✓ admin_set_business_categories registered';
END $$;

COMMIT;
