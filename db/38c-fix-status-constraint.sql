-- =====================================================
-- db/38c-fix-status-constraint.sql
-- HOTFIX: add 'pending_review' to businesses.status CHECK constraint
-- =====================================================
-- BUG: db/38 introduced status = 'pending_review' but original schema
-- CHECK constraint allows only ('pending','active','flagged','banned','self_hidden').
-- INSERT/UPDATE fails with: businesses_status_check violation.
--
-- FIX: drop the existing constraint and recreate it with 'pending_review' added.
-- Idempotent — safe to re-run.
-- =====================================================
BEGIN;

-- Drop the existing CHECK constraint (auto-named businesses_status_check)
ALTER TABLE businesses
  DROP CONSTRAINT IF EXISTS businesses_status_check;

-- Recreate with the new status value included
ALTER TABLE businesses
  ADD CONSTRAINT businesses_status_check
  CHECK (status IN ('pending','pending_review','active','flagged','banned','self_hidden'));

NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- VERIFY:
--   SELECT conname, pg_get_constraintdef(oid)
--     FROM pg_constraint
--    WHERE conrelid = 'businesses'::regclass
--      AND conname = 'businesses_status_check';
--
-- After running this, try saving from panel/profile.html again.
-- =====================================================
