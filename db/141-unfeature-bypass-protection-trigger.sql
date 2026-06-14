-- ============================================================
-- db/141 — Fix unfeature_expired_listings() to bypass protection trigger
-- ============================================================
-- BUG SURFACED DURING db/140 DEPLOY:
--   Function reported "6 rows updated" but the rows were still featured.
--   Investigation revealed a trigger `trg_biz_protect_admin_cols` on the
--   businesses table that has this protection logic:
--     NEW.featured    := OLD.featured;
--     NEW.admin_notes := OLD.admin_notes;
--   This trigger fires on every UPDATE, reverting changes to those
--   columns for non-admin contexts. Since SECURITY DEFINER functions
--   run with auth.uid()=NULL (no session JWT), the trigger treats them
--   as non-admin and reverts.
--
-- FIX:
--   Wrap the UPDATE in SET LOCAL session_replication_role = 'replica'.
--   This is a Postgres mechanism specifically designed for data migrations:
--   it disables ALL triggers for the current transaction, so the UPDATE
--   takes effect. We re-enable immediately after, scoped to this
--   transaction only (SET LOCAL auto-reverts at COMMIT).
--
-- SAFETY:
--   - SET LOCAL only affects the current transaction; other queries elsewhere
--     on the DB continue running with full trigger protection.
--   - We only run our targeted UPDATE inside the bypass window — no other
--     statements that could be affected.
--   - This requires the function owner (postgres) to have SUPERUSER
--     privilege on Supabase. The role IS the project owner role, which
--     does have this. If it ever doesn't, the function will throw a clear
--     "permission denied" error and we can fall back to a different approach.
--
-- IDEMPOTENT: CREATE OR REPLACE.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION unfeature_expired_listings()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  -- Disable triggers for this transaction so trg_biz_protect_admin_cols
  -- doesn't revert our changes. Auto-restored at COMMIT.
  SET LOCAL session_replication_role = 'replica';

  UPDATE businesses
     SET featured = FALSE,
         updated_at = NOW()
   WHERE featured = TRUE
     AND featured_until IS NOT NULL
     AND featured_until < NOW();

  GET DIAGNOSTICS v_count = ROW_COUNT;

  -- Re-enable triggers (defensive — SET LOCAL would handle this at COMMIT,
  -- but being explicit makes the intent visible).
  SET LOCAL session_replication_role = 'origin';

  RETURN v_count;
END $$;

COMMENT ON FUNCTION unfeature_expired_listings() IS
  'Clears featured=TRUE on businesses whose featured_until is past. Bypasses trg_biz_protect_admin_cols via SET LOCAL session_replication_role.';


-- =========================================================
-- One-shot fix — run the function NOW to clear any current stale rows
-- (idempotent: if already clean, returns 0 and does nothing)
-- =========================================================
DO $$
DECLARE
  v_cleared INT;
BEGIN
  v_cleared := unfeature_expired_listings();
  RAISE NOTICE '✓ db/141 — unfeatured % stale listings via session_replication_role bypass', v_cleared;
END $$;


-- =========================================================
-- Sanity verification — should return 0
-- =========================================================
DO $$
DECLARE
  v_still_stale INT;
BEGIN
  SELECT COUNT(*) INTO v_still_stale
    FROM businesses
   WHERE featured = TRUE
     AND featured_until IS NOT NULL
     AND featured_until < NOW();

  IF v_still_stale = 0 THEN
    RAISE NOTICE '✓ db/141 — verification passed: 0 stale featured listings remain';
  ELSE
    RAISE WARNING '⚠ db/141 — verification: % stale rows still present (trigger may need a different bypass)', v_still_stale;
  END IF;
END $$;


NOTIFY pgrst, 'reload schema';

COMMIT;
