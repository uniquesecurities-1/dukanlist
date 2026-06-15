-- ============================================================
-- db/153 — Extend review guard trigger to cover UPDATEs
-- ============================================================
-- db/149 created trg_guard_review_on_professional BEFORE INSERT ON reviews
-- to block new review submissions on strict pro listings. But db/152
-- introduced update_my_review which UPDATEs existing review rows
-- (rating/text/update_count etc.). If a review was created BEFORE a
-- category was flagged strict (db/145 backfill scenario), customer
-- could still mutate rating_avg via update_my_review — defeating the
-- compliance intent.
--
-- Fix: same guard function, also fire BEFORE UPDATE.
--
-- SAFE: idempotent trigger creation. No data touched.
-- ============================================================

BEGIN;

DROP TRIGGER IF EXISTS trg_guard_review_update_on_professional ON reviews;
CREATE TRIGGER trg_guard_review_update_on_professional
  BEFORE UPDATE OF rating, text ON reviews
  FOR EACH ROW
  EXECUTE FUNCTION guard_review_on_professional();

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/153 installed. Reviews on strict pro listings now immutable.';
END $$;
