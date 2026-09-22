-- ============================================================
-- db/232 — "Verified mobile with invalid number: 19" -> fix or unverify
-- ============================================================
--
-- The admin health check flags rows where
--     verified_mobile = TRUE AND (mobile IS NULL OR LENGTH(mobile) <> 10)
-- i.e. a shop wearing the "✓ Mobile verified" badge on a number a
-- customer cannot dial. 19 today.
--
-- This exact cleanup ran before as db/180 (50 rows) and db/183. The
-- rows are back because new shops have been verified with badly
-- formatted numbers since. Same two-step method as db/183, on purpose:
--
--   PART 1  NORMALIZE first. Strip "+91", spaces, dashes; keep the
--           trailing 10 digits. A number like "+91 98123 45678" is a
--           GOOD number stored badly — it gets fixed and the shop
--           KEEPS its verified badge. Blanket-unverifying these would
--           punish shopkeepers for our formatting.
--
--   PART 2  UNVERIFY only what is STILL bad after that: NULL, not 10
--           digits, or not starting 6-9 (not an Indian mobile).
--           Those genuinely cannot be called, so the badge comes off.
--           They are tagged mobile_verified_by = 'auto-cleanup:db-232'
--           so they can be listed later and re-verified properly via
--           admin_set_mobile_verified once a real number is known.
--
-- Nothing is deleted. Only mobile/whatsapp formatting and the
-- verified flag change. The ONE result shown at the end is the full
-- audit: every touched shop, old value, new value, and what happened.
--
-- Idempotent: re-running finds nothing to do.
-- ============================================================

BEGIN;

-- Snapshot the flagged rows BEFORE touching anything, so the final
-- report can show before/after even though the editor only displays
-- the last result set.
CREATE TEMP TABLE _bad_before AS
SELECT id, name, mobile AS old_mobile, whatsapp AS old_whatsapp
FROM public.businesses
WHERE COALESCE(verified_mobile, FALSE) = TRUE
  AND (mobile IS NULL OR LENGTH(mobile) <> 10);

-- PART 1 — normalize formatting on every business (not just flagged
-- ones): the bug that created these will keep creating them, and a
-- "+91" whatsapp on an unverified shop is just as broken for wa.me.
UPDATE public.businesses b
   SET mobile   = RIGHT(REGEXP_REPLACE(b.mobile,   '[^0-9]', '', 'g'), 10),
       whatsapp = CASE WHEN b.whatsapp IS NOT NULL
                       THEN RIGHT(REGEXP_REPLACE(b.whatsapp, '[^0-9]', '', 'g'), 10)
                       ELSE b.whatsapp END,
       updated_at = NOW()
 WHERE (b.mobile IS NOT NULL AND (b.mobile <> REGEXP_REPLACE(b.mobile, '[^0-9]', '', 'g') OR LENGTH(b.mobile) > 10))
    OR (b.whatsapp IS NOT NULL AND (b.whatsapp <> REGEXP_REPLACE(b.whatsapp, '[^0-9]', '', 'g') OR LENGTH(b.whatsapp) > 10));

-- PART 2 — unverify what is STILL not a dialable Indian mobile.
UPDATE public.businesses
   SET verified_mobile    = FALSE,
       mobile_verified_at = NULL,
       mobile_verified_by = 'auto-cleanup:db-232',
       updated_at         = NOW()
 WHERE COALESCE(verified_mobile, FALSE) = TRUE
   AND (mobile IS NULL OR mobile !~ '^[6789][0-9]{9}$');

COMMIT;

-- Self-record in the migration register (db/233). Guarded so this file
-- also runs cleanly if 233 has not been applied yet.
DO $$ BEGIN
  IF to_regproc('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/232-unverify-bad-mobiles.sql');
  END IF;
END $$;

-- ============================================================
-- THE AUDIT — one row per shop that was flagged, with what happened.
--   action = 'fixed, still verified'  -> formatting repaired, badge kept
--   action = 'UNVERIFIED'             -> number genuinely bad, badge off;
--                                        follow up with this shopkeeper
-- Health check "Verified mobile with invalid number" should now be 0.
-- ============================================================
SELECT
  bb.name,
  bb.old_mobile,
  b.mobile                                    AS new_mobile,
  CASE WHEN COALESCE(b.verified_mobile, FALSE) THEN 'fixed, still verified'
       ELSE 'UNVERIFIED' END                  AS action,
  b.slug
FROM _bad_before bb
JOIN public.businesses b ON b.id = bb.id
ORDER BY action DESC, bb.name;
