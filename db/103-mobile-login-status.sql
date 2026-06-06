-- =====================================================
-- db/103-mobile-login-status.sql
-- =====================================================
-- USER REQUEST (audit Phase 3):
--   "Mobile-as-login silent NULL UX — distinguish 0-match from
--    2+ match cases so user gets actionable error."
--
-- DESIGN:
--   New RPC lookup_login_mobile_status(text) returns JSONB:
--     { status: 'ok',       email: 'foo@bar.com' }    — single match
--     { status: 'none',     count: 0 }                 — no match
--     { status: 'ambiguous', count: N }                — multiple shops
--     { status: 'invalid_mobile' }                     — bad input
--
--   The existing lookup_login_email_by_mobile() is kept for
--   backward compatibility.
--
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

DROP FUNCTION IF EXISTS lookup_login_mobile_status(TEXT);
CREATE OR REPLACE FUNCTION lookup_login_mobile_status(p_mobile TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clean TEXT;
  v_count INT;
  v_email TEXT;
BEGIN
  v_clean := normalize_mobile_in(p_mobile);
  IF v_clean IS NULL THEN
    RETURN jsonb_build_object('status', 'invalid_mobile');
  END IF;

  -- Match candidates (same logic as lookup_login_email_by_mobile)
  SELECT COUNT(DISTINCT au.id) INTO v_count
  FROM auth.users au
  WHERE au.email_confirmed_at IS NOT NULL
    AND au.email IS NOT NULL
    AND (
      au.raw_user_meta_data->>'mobile' = v_clean
      OR EXISTS (
        SELECT 1
        FROM business_owners bo
        JOIN businesses b ON b.id = bo.business_id
        WHERE bo.auth_user_id = au.id
          AND b.status = 'active'
          AND regexp_replace(COALESCE(b.mobile, ''), '\D', '', 'g') ~ ('^(91)?' || v_clean || '$')
      )
    );

  IF v_count = 0 THEN
    RETURN jsonb_build_object('status', 'none', 'count', 0);
  ELSIF v_count > 1 THEN
    RETURN jsonb_build_object('status', 'ambiguous', 'count', v_count);
  END IF;

  -- Exactly 1 — fetch email
  SELECT au.email INTO v_email
  FROM auth.users au
  WHERE au.email_confirmed_at IS NOT NULL
    AND au.email IS NOT NULL
    AND (
      au.raw_user_meta_data->>'mobile' = v_clean
      OR EXISTS (
        SELECT 1
        FROM business_owners bo
        JOIN businesses b ON b.id = bo.business_id
        WHERE bo.auth_user_id = au.id
          AND b.status = 'active'
          AND regexp_replace(COALESCE(b.mobile, ''), '\D', '', 'g') ~ ('^(91)?' || v_clean || '$')
      )
    )
  LIMIT 1;

  RETURN jsonb_build_object('status', 'ok', 'email', v_email);
END;
$$;

GRANT EXECUTE ON FUNCTION lookup_login_mobile_status(TEXT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'db/103 installed.';
  RAISE NOTICE '  lookup_login_mobile_status(text) returns status: ok|none|ambiguous|invalid_mobile';
END $$;
