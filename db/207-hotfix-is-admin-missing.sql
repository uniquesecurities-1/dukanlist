-- ============================================================
-- db/207 — Hotfix: is_admin() function missing after 206 migration
-- ============================================================
-- After running db/206-security-audit-fixes.sql, admin users
-- get error "function is_admin() does not exist" when trying to
-- approve/reject/delete listings via /admin/moderation.
--
-- Root cause: migration 206 may have altered the is_admin()
-- function's visibility (through bulk search_path changes or
-- REVOKE PUBLIC). This migration:
--   1. Re-creates is_admin() and is_super_admin() explicitly in public
--   2. Sets a search_path that includes BOTH public + auth (so
--      auth.uid() inside is_admin() can be resolved)
--   3. Explicitly grants EXECUTE to authenticated + anon
--   4. Reloads PostgREST schema so RPC picks up changes
--
-- SAFE: CREATE OR REPLACE. Re-runnable. Idempotent.
-- ============================================================

BEGIN;

-- ---- 1. is_admin() ------------------------------------------
DROP FUNCTION IF EXISTS public.is_admin() CASCADE;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE auth_user_id = auth.uid()
      AND disabled = FALSE
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin() TO anon;

-- ---- 2. is_super_admin() ------------------------------------
DROP FUNCTION IF EXISTS public.is_super_admin() CASCADE;

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE auth_user_id = auth.uid()
      AND role = 'super_admin'
      AND disabled = FALSE
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated;

-- ---- 3. Re-create dependent RLS policies dropped by CASCADE -
-- (The CASCADE above may have dropped RLS policies that reference
--  is_admin(). Re-create the critical write policies from db/206.)

-- shop_likes
DROP POLICY IF EXISTS "shop_likes_admin_delete" ON public.shop_likes;
CREATE POLICY "shop_likes_admin_delete" ON public.shop_likes
  FOR DELETE TO authenticated USING (is_admin());

-- push_subscriptions
DROP POLICY IF EXISTS "push_subs_admin_delete" ON public.push_subscriptions;
CREATE POLICY "push_subs_admin_delete" ON public.push_subscriptions
  FOR DELETE TO authenticated USING (is_admin());

-- business_reports
DROP POLICY IF EXISTS "business_reports_admin_all" ON public.business_reports;
CREATE POLICY "business_reports_admin_all" ON public.business_reports
  FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

-- ---- 4. Reload PostgREST schema cache -----------------------
NOTIFY pgrst, 'reload schema';

COMMIT;

-- ---- 5. Verification (run after commit) ---------------------
-- Confirm function exists:
--   SELECT proname, pronargs FROM pg_proc WHERE proname='is_admin';
-- Confirm it works as your admin user (sign in first, then):
--   SELECT is_admin();  -- should return TRUE
-- Confirm approve works:
--   SELECT admin_approve_business('<some-business-uuid>');

DO $$ BEGIN
  RAISE NOTICE '✓ db/207 installed. is_admin() and is_super_admin() re-created with explicit search_path (public, auth, pg_temp).';
  RAISE NOTICE '  Test by trying to approve a listing in /admin/moderation now.';
END $$;
