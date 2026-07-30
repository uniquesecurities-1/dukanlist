-- =========================================================================
-- Migration 201: Fix business_photos RLS — use is_admin() helper
-- Created: 2026-07-30
--
-- BUG: The admin_all_photos policy in db/200 does a subquery on admin_users,
--      which has its own RLS. This can cause query failures (500 errors) when
--      the RLS evaluation runs into recursion/permission checks.
--
-- FIX: Use the existing is_admin() SQL function from db/09 which is defined
--      as STABLE and doesn't have this recursion issue.
--
-- Also removes any potential trigger-related permission issues on SELECT.
-- SAFE TO RE-RUN.
-- =========================================================================

BEGIN;

-- Drop old admin policy
DROP POLICY IF EXISTS "admin_all_photos" ON public.business_photos;

-- Re-create using is_admin() helper (STABLE function, no RLS recursion)
CREATE POLICY "admin_all_photos"
  ON public.business_photos
  FOR ALL
  TO authenticated
  USING (is_admin());

-- Also ensure public_read policy exists and is simple
DROP POLICY IF EXISTS "public_read_photos" ON public.business_photos;
CREATE POLICY "public_read_photos"
  ON public.business_photos
  FOR SELECT
  USING (true);

-- Grant explicit permissions to anon (public/logged-out visitors reading photos)
GRANT SELECT ON public.business_photos TO anon, authenticated;

-- Grant INSERT/UPDATE/DELETE to authenticated (RLS still filters by ownership)
GRANT INSERT, UPDATE, DELETE ON public.business_photos TO authenticated;

COMMIT;

-- Verify: after running, this should work for any logged-in user:
--   SELECT * FROM business_photos WHERE business_id = '<some-uuid>';
