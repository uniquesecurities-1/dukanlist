-- ============================================================
-- 189 — Enable RLS on tables flagged by Supabase Advisors
-- ------------------------------------------------------------
-- WHY THIS EXISTS:
-- Supabase sent a "rls_disabled_in_public" security alert on 23-Jun-26.
-- Two tables had no Row Level Security enabled, meaning anonymous
-- callers could query / mutate them directly via the REST API.
--
-- TABLES FIXED:
--   1. gp_help_reach_log         (db/166) — Golden Pages help-reach log
--   2. _usp_cleanup_audit_db151  (db/151) — one-off USP cleanup backup
--
-- WHY THIS DOES NOT BREAK ANYTHING:
-- All legitimate access to these tables happens inside SECURITY DEFINER
-- functions (gp_help_reach, admin_gp_help_requests, etc.). SECURITY
-- DEFINER functions run as the function owner and BYPASS row-level
-- security entirely. So enabling RLS on the table with NO policies
-- effectively means:
--   - SECURITY DEFINER RPCs        → still work (bypass RLS)
--   - direct anon/authenticated    → blocked (no policy = no access)
--   - admin SQL editor             → still works (table owner bypasses)
--
-- This is the standard Supabase pattern for "log tables" that should
-- only be touched through RPCs.
-- ============================================================

-- ─── 1. gp_help_reach_log ──────────────────────────────────────
-- Customer-driven nudge requests for unclaimed Golden Pages listings.
-- Writes happen via SECURITY DEFINER gp_help_reach() RPC.
-- Reads happen via SECURITY DEFINER admin_gp_help_requests() (admin only).
-- No direct access needed.
ALTER TABLE gp_help_reach_log ENABLE ROW LEVEL SECURITY;

-- Defensive: explicitly deny everything for anon + authenticated roles.
-- (RLS without any policies already denies, but stating it makes the
--  intent visible to anyone reading this schema.)
DROP POLICY IF EXISTS gp_help_reach_log_no_direct_access ON gp_help_reach_log;
-- We intentionally do NOT create any policy — empty policy set = deny all
-- for non-bypassing roles. SECURITY DEFINER functions still work.


-- ─── 2. _usp_cleanup_audit_db151 ───────────────────────────────
-- One-off audit table from the db/151 USP cleanup. Contains historical
-- USP text that was cleared from strict-tier professional listings.
-- Should be admin-only.
ALTER TABLE _usp_cleanup_audit_db151 ENABLE ROW LEVEL SECURITY;

-- Same approach: no policies = no direct access; only superuser/owner
-- (which is what your admin SQL editor connects as) can read.


-- ─── 3. Sanity check ───────────────────────────────────────────
-- Verify RLS is now enabled on both. This SELECT will return 0 rows
-- if everything is good; any row in the result means RLS is still off.
DO $$
DECLARE
  v_missing INT;
BEGIN
  SELECT COUNT(*) INTO v_missing
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname IN ('gp_help_reach_log', '_usp_cleanup_audit_db151')
    AND c.relkind = 'r'
    AND NOT c.relrowsecurity;

  IF v_missing > 0 THEN
    RAISE EXCEPTION 'db/189 failed — % table(s) still missing RLS', v_missing;
  END IF;

  RAISE NOTICE 'db/189 OK — RLS enabled on gp_help_reach_log + _usp_cleanup_audit_db151';
END $$;
