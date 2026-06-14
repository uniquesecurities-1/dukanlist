-- ============================================================
-- db/140 — Fix stale featured listings + cleanup function
-- ============================================================
-- BUG SURFACED BY HEALTH CHECK:
--   6 businesses have featured = TRUE but featured_until < NOW().
--   These leak into the homepage Featured section after expiry.
--
-- THIS MIGRATION (minimal, no pg_cron — added separately if/when needed):
--   1. ONE-SHOT FIX: clear featured flag on all currently-expired rows
--   2. FUNCTION:     unfeature_expired_listings()
--   3. RPC:          admin_unfeature_expired() — admin-only manual trigger
--
-- IDEMPOTENT: Safe to re-run.
-- DB never disturbed: forward-only, no destructive changes.
-- ============================================================

BEGIN;

-- ---- 1. ONE-SHOT FIX ----
UPDATE businesses
   SET featured = FALSE,
       updated_at = NOW()
 WHERE featured = TRUE
   AND featured_until IS NOT NULL
   AND featured_until < NOW();

-- ---- 2. Reusable cleanup function ----
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
  'Clears featured=TRUE on businesses whose featured_until is past. Returns rows affected.';

-- ---- 3. Admin-callable wrapper ----
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

NOTIFY pgrst, 'reload schema';

COMMIT;
