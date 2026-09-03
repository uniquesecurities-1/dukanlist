-- ============================================================
-- db/214 — HOTFIX: add `extensions` schema to function search_paths
-- ============================================================
-- BUG: "function unaccent(text) does not exist" on registration.
--
-- Root cause: Supabase installs extensions (unaccent, pg_trgm, etc.)
-- in the `extensions` schema. Sessions normally resolve them via the
-- default search_path which includes `extensions`. But db/206 and
-- db/210 pinned search_path = public[, auth], pg_temp on hundreds of
-- functions — dropping `extensions` — so any pinned function calling
-- unaccent() / similarity() / other extension functions now fails.
-- Registration (slug generation) and duplicate detection both hit this.
--
-- FIX: every public-schema function that has a pinned search_path
-- WITHOUT `extensions` gets it appended.
--
-- SAFE: Idempotent. Re-runnable.
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
      AND EXISTS (
        SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) cfg
        WHERE cfg LIKE 'search_path=%'
          AND cfg NOT LIKE '%extensions%'
      )
  LOOP
    BEGIN
      EXECUTE format(
        'ALTER FUNCTION %I.%I(%s) SET search_path = public, extensions, auth, pg_temp',
        fn.schema_name, fn.fn_name, fn.args
      );
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE '  skip %.%(%): %', fn.schema_name, fn.fn_name, fn.args, SQLERRM;
    END;
  END LOOP;
  RAISE NOTICE '✓ extensions schema added to search_path of % function(s)', v_count;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- Verify (run separately):
-- 1. Extensions live where we think:
--    SELECT e.extname, n.nspname FROM pg_extension e
--    JOIN pg_namespace n ON n.oid = e.extnamespace
--    WHERE e.extname IN ('unaccent','pg_trgm');
-- 2. No pinned function is missing extensions anymore:
--    SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
--    WHERE n.nspname='public' AND EXISTS (
--      SELECT 1 FROM unnest(coalesce(p.proconfig,'{}')) cfg
--      WHERE cfg LIKE 'search_path=%' AND cfg NOT LIKE '%extensions%');
--    -- expect: 0

DO $$ BEGIN
  RAISE NOTICE '✓ db/214 installed. Registration slug generation + duplicate detection restored.';
END $$;
