-- ============================================================
-- db/209 — Fully-qualify is_admin() calls in admin RPCs
-- ============================================================
-- Despite db/207 + db/208 restoring is_admin() with correct
-- search_path and permissions (verified: postgres owner,
-- authenticated + service_role + anon all have EXECUTE, public
-- schema USAGE granted), calls from admin_approve_business etc
-- were still returning:
--   {"code":"42883", "message":"function is_admin() does not exist"}
--
-- Root cause: PostgREST-set session role interfering with
-- search_path resolution for the unqualified `is_admin()` call
-- inside SECURITY DEFINER functions. Fully-qualifying the call
-- as `public.is_admin()` bypasses search_path entirely.
--
-- This migration recreates the 3 admin write-RPCs used by the
-- /admin/moderation page with fully-qualified schema references.
--
-- SAFE: CREATE OR REPLACE. Idempotent. Re-runnable.
-- ============================================================

BEGIN;

-- admin_approve_business
CREATE OR REPLACE FUNCTION public.admin_approve_business(p_business_id UUID)
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
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT name,
         COALESCE(is_professional_listing, FALSE),
         prof_verified_at
    INTO v_name, v_is_pro, v_pro_verified
  FROM public.businesses
  WHERE id = p_business_id;

  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Business not found';
  END IF;

  IF v_is_pro = TRUE AND v_pro_verified IS NULL THEN
    RAISE WARNING 'Professional listing % approved without verification.', v_name;
  END IF;

  UPDATE public.businesses SET status = 'active' WHERE id = p_business_id;
END;
$$;

-- admin_reject_business
CREATE OR REPLACE FUNCTION public.admin_reject_business(p_business_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE v_name TEXT;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  SELECT name INTO v_name FROM public.businesses WHERE id = p_business_id;
  IF v_name IS NULL THEN RAISE EXCEPTION 'Business not found'; END IF;
  UPDATE public.businesses SET status = 'banned' WHERE id = p_business_id;
  BEGIN
    PERFORM public.log_admin_action('reject_business', 'business', p_business_id::TEXT, v_name, jsonb_build_object('reason', p_reason));
  EXCEPTION WHEN OTHERS THEN NULL; END;
END;
$$;

-- admin_delete_business
CREATE OR REPLACE FUNCTION public.admin_delete_business(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE v_biz_name TEXT; v_biz_slug TEXT; v_photos TEXT[]; v_rc INT; v_lc INT; v_cc INT;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  SELECT name, slug, COALESCE(photos, ARRAY[]::TEXT[]) INTO v_biz_name, v_biz_slug, v_photos
  FROM public.businesses WHERE id = p_business_id;
  IF v_biz_name IS NULL THEN RAISE EXCEPTION 'Business not found'; END IF;
  SELECT COUNT(*)::INT INTO v_rc FROM public.reviews WHERE business_id = p_business_id;
  SELECT COUNT(*)::INT INTO v_lc FROM public.leads_log WHERE business_id = p_business_id;
  SELECT COUNT(*)::INT INTO v_cc FROM public.business_categories WHERE business_id = p_business_id;
  BEGIN
    PERFORM public.log_admin_action('delete_business', 'business', p_business_id::TEXT, v_biz_name,
      jsonb_build_object('slug', v_biz_slug, 'photo_count', COALESCE(array_length(v_photos,1),0),
        'review_count', v_rc, 'lead_count', v_lc, 'category_count', v_cc));
  EXCEPTION WHEN OTHERS THEN NULL; END;
  DELETE FROM public.businesses WHERE id = p_business_id;
  RETURN jsonb_build_object('success', true, 'business_id', p_business_id, 'business_name', v_biz_name,
    'business_slug', v_biz_slug, 'photos_to_cleanup', COALESCE(to_jsonb(v_photos), '[]'::jsonb),
    'photo_count', COALESCE(array_length(v_photos,1),0), 'review_count', v_rc, 'lead_count', v_lc,
    'category_count', v_cc, 'deleted_at', NOW());
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE '✓ db/209 installed. Admin RPCs now use fully-qualified public.is_admin() calls.';
END $$;
