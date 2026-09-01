-- ============================================================
-- db/211 — Re-grant orphaned admin RPCs + restore approve audit logging
-- ============================================================
-- AUDIT FINDING 1: db/206 revoked PUBLIC EXECUTE from every
-- SECURITY DEFINER function, but its re-grant array missed three
-- admin RPCs that had no explicit GRANT in their original migrations
-- (they relied on Postgres's default PUBLIC grant):
--   - get_admin_profile()            (db/10)  → dashboard profile header
--   - admin_get_flags(int)           (db/09)  → moderation Flag Reports panel
--   - admin_resolve_flag(uuid,text)  (db/09)  → resolving flags
-- Same failure mode as the admin_approve_business 404 bug.
--
-- AUDIT FINDING 2: db/208/209 recreated admin_approve_business
-- WITHOUT the log_admin_action('approve_business',...) call that
-- db/17/19/20/84 had — approvals stopped being audited. Restored here.
--
-- SAFE: Idempotent. Re-runnable.
-- ============================================================

BEGIN;

-- ---- 1. Re-grant the three orphaned RPCs --------------------
DO $$
DECLARE
  fn_name TEXT;
BEGIN
  FOREACH fn_name IN ARRAY ARRAY[
    'get_admin_profile',
    'admin_get_flags',
    'admin_resolve_flag'
  ]
  LOOP
    BEGIN
      EXECUTE (
        SELECT string_agg(
                 format('GRANT EXECUTE ON FUNCTION %I.%I(%s) TO authenticated;',
                        n.nspname, p.proname,
                        pg_get_function_identity_arguments(p.oid)),
                 E'\n')
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = fn_name
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skip grant for %: %', fn_name, SQLERRM;
    END;
  END LOOP;
  RAISE NOTICE '✓ EXECUTE re-granted for get_admin_profile, admin_get_flags, admin_resolve_flag';
END $$;

-- ---- 2. Restore audit logging in admin_approve_business -----
CREATE OR REPLACE FUNCTION public.admin_approve_business(p_business_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_is_pro       BOOLEAN;
  v_pro_verified TIMESTAMPTZ;
  v_name         TEXT;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT name,
         COALESCE(is_professional_listing, FALSE),
         prof_verified_at
    INTO v_name, v_is_pro, v_pro_verified
  FROM public.businesses
  WHERE id = p_business_id;

  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Business not found';
  END IF;

  IF v_is_pro = TRUE AND v_pro_verified IS NULL THEN
    RAISE WARNING 'Professional listing % approved without verification.', v_name;
  END IF;

  UPDATE public.businesses SET status = 'active' WHERE id = p_business_id;

  -- Restored (was dropped by db/208/209): audit trail for approvals
  BEGIN
    PERFORM public.log_admin_action(
      'approve_business', 'business', p_business_id::TEXT, v_name,
      jsonb_build_object('is_professional', v_is_pro,
                         'pro_verified', v_pro_verified IS NOT NULL)
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_approve_business(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- Verify (run separately after commit):
-- SELECT p.proname, has_function_privilege('authenticated', p.oid, 'EXECUTE') AS ok
-- FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname='public'
--   AND p.proname IN ('get_admin_profile','admin_get_flags','admin_resolve_flag','admin_approve_business');

DO $$ BEGIN
  RAISE NOTICE '✓ db/211 installed. Flags panel + dashboard profile restored; approvals audited again.';
END $$;
