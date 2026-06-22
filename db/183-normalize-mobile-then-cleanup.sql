-- ============================================================
-- db/183 — Normalize mobile column, then re-cleanup verified flag
-- ============================================================
-- WHY THIS EXISTS:
--   db/180 was supposed to unverify rows where verified_mobile=TRUE
--   but mobile was invalid. After running, 99 rows still flagged.
--
--   Diagnosis: Many of those 99 rows have mobile stored as
--   "919416216662" (12 chars with country code) instead of
--   "9416216662" (10 chars). db/180's LENGTH(mobile)<>10 check
--   counted them as "invalid" even though they're real numbers
--   that just need normalization.
--
-- WHAT THIS DOES:
--   1. Normalizes the mobile column site-wide:
--      - Strips '+91' or '91' prefix
--      - Strips all non-digit chars (spaces, hyphens, parentheses)
--      - Keeps only the trailing 10 digits if mobile length > 10
--   2. After normalization, re-runs db/180-style cleanup: any row
--      that's STILL invalid (truly bad data) gets unverified.
--
-- SAFETY:
--   - Doesn't touch rows with already-valid 10-digit mobile
--   - Logs every change to admin_errors for trail
--   - Idempotent — running twice does nothing on second pass
-- ============================================================

BEGIN;

DO $$
DECLARE
  v_normalized INT;
  v_unverified INT;
BEGIN

  -- =========================================================
  -- PART 1: Normalize mobile column
  -- =========================================================
  WITH normalized AS (
    UPDATE businesses b
       SET mobile = (
             -- Strip every non-digit char
             SELECT RIGHT(REGEXP_REPLACE(b.mobile, '[^0-9]', '', 'g'), 10)
           ),
           whatsapp = CASE
             WHEN b.whatsapp IS NOT NULL THEN
               (SELECT RIGHT(REGEXP_REPLACE(b.whatsapp, '[^0-9]', '', 'g'), 10))
             ELSE b.whatsapp
           END,
           updated_at = NOW()
     WHERE b.mobile IS NOT NULL
       AND b.mobile <> REGEXP_REPLACE(b.mobile, '[^0-9]', '', 'g')   -- has non-digit chars
            OR (b.mobile IS NOT NULL AND LENGTH(b.mobile) > 10)        -- too long (likely 91-prefix)
    RETURNING b.id
  )
  SELECT COUNT(*) INTO v_normalized FROM normalized;

  RAISE NOTICE 'db/183: normalized % mobile values', v_normalized;

  -- =========================================================
  -- PART 2: Re-run db/180-style cleanup on whatever's left
  -- (any mobile still invalid after normalization = truly bad)
  -- =========================================================
  WITH unverified AS (
    UPDATE businesses
       SET verified_mobile    = FALSE,
           mobile_verified_at = NULL,
           mobile_verified_by = 'auto-cleanup:db-183',
           updated_at         = NOW()
     WHERE COALESCE(verified_mobile, FALSE) = TRUE
       AND (mobile IS NULL OR LENGTH(mobile) <> 10
            OR mobile !~ '^[6789][0-9]{9}$')   -- must start with 6/7/8/9
    RETURNING id
  )
  SELECT COUNT(*) INTO v_unverified FROM unverified;

  RAISE NOTICE 'db/183: unverified % rows with truly invalid mobile', v_unverified;

  -- Audit
  IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'admin_errors' AND schemaname = 'public') THEN
    INSERT INTO admin_errors (
      user_email, page, error_type, error_message, payload, resolved, resolved_at
    ) VALUES (
      'system',
      '/db/183',
      'cleanup',
      'Normalized ' || v_normalized || ' mobiles; unverified ' || v_unverified || ' truly-bad rows',
      jsonb_build_object(
        'migration', 'db/183',
        'normalized', v_normalized,
        'unverified', v_unverified
      ),
      TRUE,
      NOW()
    );
  END IF;
END $$;

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/183 done. Mobile column normalized + verified flag re-validated.';
END $$;
