-- =====================================================
-- 18-fix-view-security.sql
-- Fix Supabase Security Advisor: SECURITY DEFINER View
-- =====================================================
-- WHAT THIS DOES:
--   PostgreSQL views default to SECURITY DEFINER (run as owner).
--   This can bypass RLS and is a privilege escalation risk.
--   Supabase Advisor flags this as CRITICAL.
--
--   FIX: Switch to SECURITY INVOKER, so the view runs with
--        the calling user's privileges (and RLS is enforced).
--
-- PREREQUISITES: 07-multi-category-expansion.sql executed
-- HOW TO RUN: Paste in Supabase SQL Editor → Run
-- IDEMPOTENT: Safe to re-run
-- =====================================================

ALTER VIEW IF EXISTS business_categories_view
  SET (security_invoker = true);


-- =====================================================
-- VERIFICATION
-- =====================================================
-- After running, refresh Supabase Dashboard → Advisors page.
-- The "Security Definer View" issue should be gone.
--
-- You can also verify via SQL:
--    SELECT relname, reloptions FROM pg_class
--    WHERE relname = 'business_categories_view';
--    Expected: reloptions contains 'security_invoker=true'
-- =====================================================

NOTIFY pgrst, 'reload schema';
