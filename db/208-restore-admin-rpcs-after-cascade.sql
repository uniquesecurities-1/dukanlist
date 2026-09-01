-- ============================================================
-- db/208 — CRITICAL RESTORE: admin RPCs dropped by 207's CASCADE
-- ============================================================
-- db/207 used `DROP FUNCTION is_admin() CASCADE` which ALSO dropped
-- every admin RPC that referenced is_admin(). Result: 404 errors on
-- admin_approve_business / admin_reject_business / admin_delete_business
-- from /admin/moderation.
--
-- This migration:
--   1. Re-creates is_admin() and is_super_admin() (no CASCADE this time)
--   2. Restores admin_approve_business (from db/154 latest version)
--   3. Restores admin_reject_business (from db/17)
--   4. Restores admin_delete_business (from db/17)
--   5. Restores log_admin_action helper (from db/17)
--   6. Re-grants EXECUTE + reloads PostgREST schema
--
-- If other admin functions are still 404ing after this, re-run the
-- specific migration files that created them (they all use CREATE OR
-- REPLACE, so re-running is safe).
--
-- SAFE: Idempotent. Re-runnable.
-- ============================================================

BEGIN;

-- ============================================================
-- 1. is_admin() and is_super_admin()  (NO CASCADE this time!)
-- ============================================================

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


-- ============================================================
-- 2. log_admin_action helper — SKIPPED
-- ============================================================
-- log_admin_action() already exists in DB with a different return
-- type (was not dropped by CASCADE because is_admin() is not in its
-- body). We leave it as-is — admin_reject_business + admin_delete_business
-- call it via PERFORM which discards the return value anyway.
-- ============================================================


-- ============================================================
-- 3. admin_approve_business  (from db/154, latest)
-- ============================================================

CREATE OR REPLACE FUNCTION admin_approve_business(p_business_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_is_pro       BOOLEAN;
  v_pro_verified TIMESTAMPTZ;
  v_name         TEXT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT name,
         COALESCE(is_professional_listing, FALSE),
         prof_verified_at
    INTO v_name, v_is_pro, v_pro_verified
  FROM businesses
  WHERE id = p_business_id;

  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Business not found';
  END IF;

  IF v_is_pro = TRUE AND v_pro_verified IS NULL THEN
    RAISE WARNING 'Professional listing % approved without membership verification.', v_name;
  END IF;

  UPDATE businesses
  SET status = 'active'
  WHERE id = p_business_id;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_approve_business(UUID) TO authenticated;


-- ============================================================
-- 4. admin_reject_business  (from db/17)
-- ============================================================

CREATE OR REPLACE FUNCTION admin_reject_business(
  p_business_id UUID,
  p_reason      TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_name TEXT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;

  SELECT name INTO v_name FROM businesses WHERE id = p_business_id;
  IF v_name IS NULL THEN RAISE EXCEPTION 'Business not found'; END IF;

  UPDATE businesses SET status = 'banned' WHERE id = p_business_id;

  PERFORM log_admin_action(
    'reject_business', 'business', p_business_id::TEXT, v_name,
    jsonb_build_object('reason', p_reason)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_reject_business(UUID, TEXT) TO authenticated;


-- ============================================================
-- 5. admin_delete_business  (from db/17)
-- ============================================================

CREATE OR REPLACE FUNCTION admin_delete_business(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_biz_name       TEXT;
  v_biz_slug       TEXT;
  v_photos         TEXT[];
  v_review_count   INT;
  v_lead_count     INT;
  v_category_count INT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;

  SELECT name, slug, COALESCE(photos, ARRAY[]::TEXT[])
    INTO v_biz_name, v_biz_slug, v_photos
  FROM businesses WHERE id = p_business_id;

  IF v_biz_name IS NULL THEN RAISE EXCEPTION 'Business not found'; END IF;

  SELECT COUNT(*)::INT INTO v_review_count FROM reviews WHERE business_id = p_business_id;
  SELECT COUNT(*)::INT INTO v_lead_count FROM leads_log WHERE business_id = p_business_id;
  SELECT COUNT(*)::INT INTO v_category_count FROM business_categories WHERE business_id = p_business_id;

  PERFORM log_admin_action(
    'delete_business', 'business', p_business_id::TEXT, v_biz_name,
    jsonb_build_object(
      'slug', v_biz_slug,
      'photo_count', COALESCE(array_length(v_photos, 1), 0),
      'review_count', v_review_count,
      'lead_count', v_lead_count,
      'category_count', v_category_count
    )
  );

  DELETE FROM businesses WHERE id = p_business_id;

  RETURN jsonb_build_object(
    'success', true,
    'business_id', p_business_id,
    'business_name', v_biz_name,
    'business_slug', v_biz_slug,
    'photos_to_cleanup', COALESCE(to_jsonb(v_photos), '[]'::jsonb),
    'photo_count', COALESCE(array_length(v_photos, 1), 0),
    'review_count', v_review_count,
    'lead_count', v_lead_count,
    'category_count', v_category_count,
    'deleted_at', NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_delete_business(UUID) TO authenticated;


-- ============================================================
-- 6. Restore RLS policies dropped by CASCADE
-- ============================================================

DROP POLICY IF EXISTS "shop_likes_admin_delete" ON public.shop_likes;
CREATE POLICY "shop_likes_admin_delete" ON public.shop_likes
  FOR DELETE TO authenticated USING (is_admin());

DROP POLICY IF EXISTS "push_subs_admin_delete" ON public.push_subscriptions;
CREATE POLICY "push_subs_admin_delete" ON public.push_subscriptions
  FOR DELETE TO authenticated USING (is_admin());

DROP POLICY IF EXISTS "business_reports_admin_all" ON public.business_reports;
CREATE POLICY "business_reports_admin_all" ON public.business_reports
  FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());


-- ============================================================
-- 7. Reload PostgREST schema
-- ============================================================

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE '✓ db/208 installed. Critical admin RPCs restored.';
  RAISE NOTICE '  Test: try approving a listing in /admin/moderation.';
  RAISE NOTICE '  If other admin functions still 404, re-run their original migration files.';
END $$;
