-- =====================================================
-- 20-fix-approve-rpc.sql
-- Fix admin_approve_business — remove invalid UPDATE on verified_score
-- =====================================================
-- WHAT THIS FIXES:
--   verified_score column is GENERATED ALWAYS — it can NOT be
--   manually UPDATEd. The previous admin_approve_business RPC was
--   trying to do COALESCE(verified_score, 0) + 1 which fails with
--   error: "column verified_score can only be updated to DEFAULT".
--
--   Since the column is generated from other verified_* flags,
--   setting verified_visit = TRUE will auto-update verified_score.
--
-- PREREQUISITES: 01-19 SQL files executed
-- HOW TO RUN: Paste in Supabase SQL Editor → Run
-- IDEMPOTENT: CREATE OR REPLACE, safe to re-run.
-- =====================================================


CREATE OR REPLACE FUNCTION admin_approve_business(p_business_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin BOOLEAN;
  v_name  TEXT;
  v_city  INT;
BEGIN
  SELECT is_admin() INTO v_admin;
  IF NOT v_admin THEN RAISE EXCEPTION 'Admin only'; END IF;

  SELECT name, city_id INTO v_name, v_city FROM businesses WHERE id = p_business_id;
  IF v_name IS NULL THEN RAISE EXCEPTION 'Business not found'; END IF;

  -- Scope check (city moderator can only approve in their cities)
  IF NOT _admin_has_city_access(v_city) THEN
    RAISE EXCEPTION 'Not authorised — this shop is outside your city scope';
  END IF;

  -- Update WITHOUT verified_score (it's GENERATED, auto-recomputed by trigger)
  UPDATE businesses
    SET status         = 'active',
        verified_visit = TRUE
    WHERE id = p_business_id;

  PERFORM log_admin_action('approve_business', 'business', p_business_id::TEXT, v_name, NULL);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_approve_business(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';


-- =====================================================
-- VERIFICATION (run AFTER above, copy each separately)
-- =====================================================
-- 1) Function recreated:
--    SELECT proname FROM pg_proc WHERE proname = 'admin_approve_business';
--
-- 2) Test approve on a real pending shop (replace UUID):
--    SELECT admin_approve_business('PASTE-UUID-HERE'::uuid);
--    SELECT id, name, status, verified_visit, verified_score
--    FROM businesses WHERE id = 'PASTE-UUID-HERE'::uuid;
--    Expected: status='active', verified_visit=TRUE
-- =====================================================
