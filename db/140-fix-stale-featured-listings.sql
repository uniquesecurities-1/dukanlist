-- ============================================================
-- db/140 — Fix stale featured listings + auto-cleanup
-- ============================================================
-- BUG SURFACED BY HEALTH CHECK:
--   6 businesses have featured = TRUE but featured_until < NOW().
--   These are still appearing on the homepage Featured section
--   when they shouldn't be — the user paid for X days of feature,
--   the period expired, but no process cleared the flag.
--
-- ROOT CAUSE:
--   db/37 (Featured Listings) added featured_until column but no
--   trigger / cron / scheduled job to actually un-feature shops
--   when their time expires. Code paths that read featured shops
--   typically include `WHERE featured = TRUE AND (featured_until
--   IS NULL OR featured_until > NOW())` — but several reads forget
--   the second clause, leaking stale featured listings into the UI.
--
-- THIS MIGRATION:
--   1. ONE-SHOT FIX: clear featured flag on all currently-expired rows.
--   2. FUNCTION:     unfeature_expired_listings() — idempotent cleanup.
--   3. RPC:          admin_unfeature_expired() — manual trigger for admins.
--   4. SCHEDULING:   try to register a pg_cron job that runs hourly.
--                    Gracefully no-op if pg_cron extension isn't enabled.
--
-- IDEMPOTENT: Safe to re-run any number of times.
-- DB never disturbed: forward-only, no destructive changes (just clears
-- the featured boolean, no data deleted).
-- ============================================================

BEGIN;

-- =========================================================
-- 1. ONE-SHOT FIX: clear featured on all currently-expired rows
-- =========================================================
WITH stale AS (
  SELECT id, name, featured_until
  FROM businesses
  WHERE featured = TRUE
    AND featured_until IS NOT NULL
    AND featured_until < NOW()
)
UPDATE businesses
   SET featured = FALSE,
       updated_at = NOW()
 WHERE id IN (SELECT id FROM stale)
RETURNING id, name, featured_until;
-- The RETURNING is for visibility in the SQL output / logs.


-- =========================================================
-- 2. Reusable cleanup function — called by cron AND by admins manually
-- =========================================================
CREATE OR REPLACE FUNCTION unfeature_expired_listings()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  UPDATE businesses
     SET featured = FALSE,
         updated_at = NOW()
   WHERE featured = TRUE
     AND featured_until IS NOT NULL
     AND featured_until < NOW();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END $$;

COMMENT ON FUNCTION unfeature_expired_listings() IS
  'Clears featured=TRUE on businesses whose featured_until is past. Returns rows affected. Safe to call from cron or manually.';


-- =========================================================
-- 3. Admin-callable wrapper — surfaces to Health page
-- =========================================================
CREATE OR REPLACE FUNCTION admin_unfeature_expired()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  v_count := unfeature_expired_listings();
  RETURN jsonb_build_object(
    'unfeatured', v_count,
    'ran_at',     NOW()
  );
END $$;

GRANT EXECUTE ON FUNCTION admin_unfeature_expired() TO authenticated;


-- =========================================================
-- 4. Try to schedule hourly via pg_cron — graceful fallback
-- =========================================================
-- pg_cron is available on Supabase but must be enabled per project.
-- If it's not enabled, we just no-op (the admin can run the function
-- manually from /admin/health via the admin_unfeature_expired RPC).
DO $$
DECLARE
  v_has_cron BOOLEAN;
  v_existing_jobid BIGINT;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'
  ) INTO v_has_cron;

  IF v_has_cron THEN
    -- Remove any existing job by name to keep this migration idempotent
    SELECT jobid INTO v_existing_jobid
      FROM cron.job
     WHERE jobname = 'unfeature_expired_hourly';
    IF v_existing_jobid IS NOT NULL THEN
      PERFORM cron.unschedule(v_existing_jobid);
    END IF;

    -- Schedule fresh: every hour at minute 7 (avoid common load times)
    PERFORM cron.schedule(
      'unfeature_expired_hourly',
      '7 * * * *',
      'SELECT public.unfeature_expired_listings();'
    );
    RAISE NOTICE '✓ Scheduled hourly auto-cleanup via pg_cron';
  ELSE
    RAISE NOTICE 'ℹ pg_cron not enabled — auto-cleanup skipped.';
    RAISE NOTICE '   Admin can run admin_unfeature_expired() manually from /admin/health.';
    RAISE NOTICE '   To enable: Supabase Dashboard → Database → Extensions → enable pg_cron.';
  END IF;
END $$;


NOTIFY pgrst, 'reload schema';

DO $$
BEGIN
  RAISE NOTICE '✓ db/140 — stale featured listings cleared, auto-cleanup installed';
END $$;

COMMIT;
