-- ============================================================
-- db/210 — FINAL FIX: Set search_path on all functions calling is_admin()
-- ============================================================
-- After db/206/207/208/209, admin panel STILL failed with:
--   {"code":"42883", "message":"function is_admin() does not exist"}
-- when calling admin_approve_business / reject / delete.
--
-- Root cause: When admin_approve_business does UPDATE businesses,
-- multiple BEFORE UPDATE triggers fire (trg_biz_protect_admin_cols,
-- trg_biz_updated, etc.) whose trigger functions call is_admin()
-- unqualified. If those trigger functions lack a proper search_path,
-- the `is_admin` name cannot be resolved and fails with error 42883.
--
-- This migration force-sets search_path = public, auth, pg_temp on
-- EVERY public schema function whose body calls unqualified is_admin(),
-- so is_admin() (in public schema) is always resolvable regardless of
-- caller's session context.
--
-- SAFE: Idempotent. Only ALTERs, no drops. Re-runnable.
-- ============================================================

BEGIN;

DO $$
DECLARE
  fn RECORD;
  v_count INT := 0;
BEGIN
  FOR fn IN
    SELECT n.nspname AS schema_name,
           p.proname AS fn_name,
           pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosrc ~* '\mis_admin\s*\('
      AND p.prosrc !~* 'public\.is_admin'
  LOOP
    BEGIN
      EXECUTE format(
        'ALTER FUNCTION %I.%I(%s) SET search_path = public, auth, pg_temp',
        fn.schema_name, fn.fn_name, fn.args
      );
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skip %.%(%): %', fn.schema_name, fn.fn_name, fn.args, SQLERRM;
    END;
  END LOOP;
  RAISE NOTICE '✓ Fixed search_path on % functions', v_count;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE '✓ db/210 installed. Admin panel approve/reject/delete should now work.';
END $$;
