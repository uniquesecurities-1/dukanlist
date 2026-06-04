-- =====================================================
-- db/102-hotfix-bo-added-at.sql
-- =====================================================
-- AUDIT FINDING:
--   db/79-safe-my-business-lookup.sql admin_audit_business_owners
--   references bo.created_at — the real column on business_owners is
--   `added_at`. Not currently called from any frontend, so silent
--   today, but will error if anyone calls it.
--
-- This patch replaces the function with corrected version.
--
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

DROP FUNCTION IF EXISTS admin_audit_business_owners();
CREATE OR REPLACE FUNCTION admin_audit_business_owners()
RETURNS TABLE (
  auth_user_id  UUID,
  email         TEXT,
  meta_mobile   TEXT,
  business_id   UUID,
  business_name TEXT,
  business_mobile TEXT,
  role          TEXT,
  claimed_at    TIMESTAMPTZ,
  is_suspicious BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  RETURN QUERY
  SELECT
    bo.auth_user_id,
    au.email::TEXT,
    (au.raw_user_meta_data->>'mobile')::TEXT AS meta_mobile,
    bo.business_id,
    b.name::TEXT AS business_name,
    b.mobile::TEXT AS business_mobile,
    bo.role::TEXT,
    bo.added_at AS claimed_at,             -- FIX: was bo.created_at
    (
      -- mobile mismatch
      (b.mobile IS NOT NULL
       AND au.raw_user_meta_data->>'mobile' IS NOT NULL
       AND regexp_replace(b.mobile, '^(\+?91|0)', '') <>
           regexp_replace(au.raw_user_meta_data->>'mobile', '^(\+?91|0)', ''))
      OR
      (b.mobile IS NOT NULL
       AND au.raw_user_meta_data->>'mobile' IS NOT NULL
       AND regexp_replace(b.mobile, '^(\+?91|0)', '') = regexp_replace(au.raw_user_meta_data->>'mobile', '^(\+?91|0)', ''))
    ) AS is_suspicious
  FROM business_owners bo
  JOIN auth.users au ON au.id = bo.auth_user_id
  JOIN businesses b  ON b.id  = bo.business_id
  ORDER BY is_suspicious DESC, bo.added_at DESC;   -- FIX
END;
$$;

GRANT EXECUTE ON FUNCTION admin_audit_business_owners() TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'db/102 hotfix installed.';
  RAISE NOTICE '  admin_audit_business_owners now uses bo.added_at correctly';
END $$;
