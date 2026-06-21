-- ============================================================
-- db/168 — Make businesses.owner_name nullable
-- ============================================================
-- Bug surfaced in golden-pages-add flow:
--   `null value in column "owner_name" of relation "businesses"
--    violates not-null constraint`
--
-- The db/01 schema declared owner_name TEXT NOT NULL because the
-- original full-registration flow always collected an owner name.
-- But the newer flows we built:
--   • admin_pre_list_shop (db/162, db/165)
--   • admin_soft_add_shop (db/166, db/167)
--   • admin_soft_bulk_add (db/166)
-- legitimately have NO owner name at insert time — they're
-- reference-based directory entries where the actual owner will
-- be discovered later via the claim flow.
--
-- Options considered:
--   A) DEFAULT '' on the column — fragile, would still NOT match
--      what register_business_public expects (real owner names)
--   B) Backfill empty string in every soft-add RPC — leaks the
--      workaround across all RPCs, easy to forget for future ones
--   C) Drop NOT NULL → owner_name is semantically optional now ✓
--
-- Choice C: drop the NOT NULL constraint. Existing rows are
-- preserved as-is (their values are non-null). New inserts with
-- no owner_name will store NULL. Public-facing code already
-- handles missing owner_name (business.html shows the shop name
-- if owner_name is empty/null — see db/116 era logic).
--
-- SAFE: ALTER ... DROP NOT NULL is non-destructive, no data lost,
-- no app changes required. Re-runnable.
-- ============================================================

BEGIN;

ALTER TABLE businesses
  ALTER COLUMN owner_name DROP NOT NULL;

COMMENT ON COLUMN businesses.owner_name IS
  'Owner display name. Optional — soft-listed and pre-listed entries may not have this until claim. '
  'Full registrations (register_business_public) always supply a value.';

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/168 installed. businesses.owner_name is now nullable.';
END $$;
