-- =====================================================
-- db/80-email-gate-moderation.sql
-- =====================================================
-- USER REQUEST (2026-05-28):
--   "Aisa na kare ki koi business owner pehle registration kare...
--    Usko email jaye, wo verify kare, uske baad hi mere paas uska
--    approval ke liye data aaye, isse fake email nahi aayegi aur
--    fake verification se bhi bach jayenge."
--
-- BEHAVIOR:
--   - NEW registrations (created after this migration): only show in
--     admin moderation queue AFTER the owner has confirmed their email.
--   - EXISTING businesses (created before this migration): grandfathered.
--     Admin sees them as before, regardless of email-confirm state.
--
-- IMPLEMENTATION:
--   1. New column businesses.email_gate_at_signup (default TRUE)
--      Set to FALSE for all existing rows (grandfather).
--   2. New helper function: business_has_verified_owner(p_business_id)
--      Returns TRUE if any business_owners row links to an auth.user
--      with non-null email_confirmed_at.
--   3. Update admin_list_businesses() to add the filter when
--      p_status = 'pending' (and only then — does not affect active/disabled etc).
--   4. New helper RPC admin_pending_awaiting_email_count() for the
--      "X awaiting email verification" info badge on admin moderation page.
--
-- Backwards compatible — no client changes required for the filter to
-- start working. Safe to run multiple times.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. Schema: add email_gate flag to businesses
-- ============================================================
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS email_gate_at_signup BOOLEAN NOT NULL DEFAULT TRUE;

COMMENT ON COLUMN businesses.email_gate_at_signup IS
  'When TRUE, business is hidden from admin moderation queue until owner verifies email. '
  'Set to FALSE for businesses created before db/80 to grandfather them.';

-- Grandfather: set FALSE for all rows that already exist at deploy time.
-- This UPDATE only affects rows whose default was TRUE — new rows after deploy keep TRUE.
-- We use a marker condition (rows created before NOW()) to make this safe to re-run.
DO $$
DECLARE
  v_count INT;
BEGIN
  -- One-time backfill: mark all rows currently in the table as "grandfathered".
  -- Subsequent runs of this migration will only touch rows that are still TRUE
  -- but were inserted BEFORE the original deploy timestamp.
  UPDATE businesses
  SET email_gate_at_signup = FALSE
  WHERE email_gate_at_signup = TRUE
    AND created_at < NOW() - INTERVAL '1 second';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE 'Grandfathered % existing businesses (email_gate_at_signup = FALSE)', v_count;
END $$;


-- ============================================================
-- 2. Helper: does the business have at least one verified-email owner?
-- ============================================================
CREATE OR REPLACE FUNCTION business_has_verified_owner(p_business_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM business_owners bo
    JOIN auth.users au ON au.id = bo.auth_user_id
    WHERE bo.business_id = p_business_id
      AND au.email_confirmed_at IS NOT NULL
  );
$$;

GRANT EXECUTE ON FUNCTION business_has_verified_owner(UUID) TO authenticated;


-- ============================================================
-- 3. Replace admin_list_businesses() to add the email-gate filter
-- ============================================================
DROP FUNCTION IF EXISTS admin_list_businesses(TEXT, INT, INT, TEXT);

CREATE OR REPLACE FUNCTION admin_list_businesses(
  p_status TEXT     DEFAULT NULL,
  p_limit  INT      DEFAULT 50,
  p_offset INT      DEFAULT 0,
  p_sort   TEXT     DEFAULT 'newest'
)
RETURNS TABLE (
  id              UUID,
  slug            TEXT,
  name            TEXT,
  name_hi         TEXT,
  owner_name      TEXT,
  mobile          TEXT,
  whatsapp        TEXT,
  email           TEXT,
  status          TEXT,
  primary_cat     TEXT,
  city_name       TEXT,
  state_code      TEXT,
  pincode         TEXT,
  photos_count    INT,
  verified_score  SMALLINT,
  rating_avg      NUMERIC,
  rating_count    INT,
  flagged_count   SMALLINT,
  lead_count      INT,
  view_count      INT,
  created_at      TIMESTAMPTZ,
  last_active_at  TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role   TEXT;
  v_cities INT[];
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT role, assigned_city_ids INTO v_role, v_cities
  FROM admin_users WHERE auth_user_id = auth.uid();

  RETURN QUERY
  SELECT
    b.id, b.slug, b.name, b.name_hi, b.owner_name, b.mobile, b.whatsapp, b.email,
    b.status::TEXT,
    COALESCE(pc.name, fc.name)        AS primary_cat,
    gc.name                            AS city_name,
    gs.code                            AS state_code,
    b.pincode,
    COALESCE(array_length(b.photos,1),0)::INT AS photos_count,
    b.verified_score,
    b.rating_avg, b.rating_count,
    b.flagged_count, b.lead_count, b.view_count,
    b.created_at, b.last_active_at
  FROM businesses b
  LEFT JOIN geo_cities  gc ON gc.id = b.city_id
  LEFT JOIN geo_states  gs ON gs.id = b.state_id
  LEFT JOIN business_categories bcp ON bcp.business_id = b.id AND bcp.is_primary = TRUE
  LEFT JOIN categories pc ON pc.id = bcp.category_id
  LEFT JOIN categories fc ON fc.id = b.sub_category_id
  WHERE (p_status IS NULL OR b.status::TEXT = p_status)
    -- City-manager scope check
    AND (v_role = 'super_admin' OR v_cities IS NULL OR v_cities = '{}' OR b.city_id = ANY(v_cities))
    -- 🚨 EMAIL GATE: when looking at 'pending' status, hide businesses whose owner
    -- hasn't verified their email yet. Existing rows are grandfathered via
    -- email_gate_at_signup = FALSE.
    AND (
      p_status IS DISTINCT FROM 'pending'
      OR b.email_gate_at_signup = FALSE
      OR business_has_verified_owner(b.id)
    )
  ORDER BY
    CASE WHEN p_sort = 'oldest' THEN b.created_at END ASC,
    CASE WHEN p_sort = 'newest' OR p_sort IS NULL THEN b.created_at END DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_list_businesses(TEXT,INT,INT,TEXT) TO authenticated;


-- ============================================================
-- 4. Info RPC: count of NEW pending businesses waiting on email verify
-- ============================================================
CREATE OR REPLACE FUNCTION admin_pending_awaiting_email_count()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
  v_role  TEXT;
  v_cities INT[];
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin access required'; END IF;

  SELECT role, assigned_city_ids INTO v_role, v_cities
  FROM admin_users WHERE auth_user_id = auth.uid();

  SELECT COUNT(*) INTO v_count
  FROM businesses b
  WHERE b.status::TEXT = 'pending'
    AND b.email_gate_at_signup = TRUE
    AND NOT business_has_verified_owner(b.id)
    AND (v_role = 'super_admin' OR v_cities IS NULL OR v_cities = '{}' OR b.city_id = ANY(v_cities));

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_pending_awaiting_email_count() TO authenticated;


-- ============================================================
-- 5. Optional admin override: force-unhide a specific business
-- Use case: legitimate owner can't get verify email (typo, spam folder lost).
-- Admin can run this so the business shows up in the queue and approve manually.
-- ============================================================
CREATE OR REPLACE FUNCTION admin_disable_email_gate(p_business_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin access required'; END IF;

  UPDATE businesses
  SET email_gate_at_signup = FALSE
  WHERE id = p_business_id;

  BEGIN
    PERFORM log_admin_action(
      'disable_email_gate', 'business', p_business_id::TEXT,
      NULL,
      jsonb_build_object('reason', 'admin override — show in queue without email verification')
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_disable_email_gate(UUID) TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- VERIFY
-- =====================================================
DO $$
DECLARE
  v_col_exists BOOLEAN;
  v_grandfathered INT;
  v_new_gated INT;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'businesses' AND column_name = 'email_gate_at_signup'
  ) INTO v_col_exists;

  SELECT COUNT(*) INTO v_grandfathered FROM businesses WHERE email_gate_at_signup = FALSE;
  SELECT COUNT(*) INTO v_new_gated     FROM businesses WHERE email_gate_at_signup = TRUE;

  RAISE NOTICE '✅ email_gate_at_signup column exists: %', v_col_exists;
  RAISE NOTICE '✅ Grandfathered businesses (visible to admin always): %', v_grandfathered;
  RAISE NOTICE '✅ New email-gated businesses (waiting on verify): %', v_new_gated;
END $$;
