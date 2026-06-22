-- ============================================================
-- db/180 — Cleanup: auto-unverify mobile when number is invalid
-- ============================================================
-- HEALTH CHECK SURFACED:
--   "Verified mobile with invalid number = 50 (FAIL)"
--
-- ROOT CAUSE:
--   businesses.verified_mobile pre-existed (db/01-schema:129). Older
--   admin tooling or seed scripts set verified_mobile=TRUE for some
--   rows where mobile is NULL or not exactly 10 digits. This was
--   silently invisible until db/179's new integrity check exposed it.
--
-- THIS MIGRATION:
--   For every row where verified_mobile=TRUE but mobile is bad,
--   flip verified_mobile to FALSE and clear the audit fields. Safe
--   because:
--     - We can always re-verify later via admin_set_mobile_verified
--     - Bad data was preventing the privacy gate (full mobile shown)
--       from working correctly on Golden Pages anyway
--     - DB never lost — just corrects a flag
--
-- Logs to admin_errors table for audit trail of how many were fixed.
-- ============================================================

BEGIN;

DO $$
DECLARE
  v_count INT;
BEGIN
  -- Count + fix in one go
  WITH fixed AS (
    UPDATE businesses
       SET verified_mobile    = FALSE,
           mobile_verified_at = NULL,
           mobile_verified_by = 'auto-cleanup:db-180',
           updated_at         = NOW()
     WHERE COALESCE(verified_mobile, FALSE) = TRUE
       AND (mobile IS NULL OR LENGTH(mobile) <> 10)
    RETURNING id
  )
  SELECT COUNT(*) INTO v_count FROM fixed;

  RAISE NOTICE 'db/180: unverified % rows that had verified_mobile=TRUE with invalid mobile', v_count;

  -- Also log to admin_errors for the dashboard trail
  IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'admin_errors' AND schemaname = 'public') THEN
    INSERT INTO admin_errors (
      user_email, page, error_type, error_message, payload, resolved, resolved_at
    ) VALUES (
      'system',
      '/db/180',
      'cleanup',
      'Auto-unverified ' || v_count || ' rows: verified_mobile=TRUE but mobile invalid',
      jsonb_build_object('migration', 'db/180', 'rows_fixed', v_count),
      TRUE,
      NOW()
    );
  END IF;
END $$;

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/180 done. Health check should now report 0 invalid verified mobiles.';
END $$;
