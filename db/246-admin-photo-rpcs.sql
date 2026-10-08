-- ============================================================
-- db/246 — admin adds / removes / features a shop's photos
-- ============================================================
-- v331 put a Shop Photos card on admin/shop.html that wrote straight
-- to business_photos. Deepak, 8 Oct: "0 uploaded · 1 failed". The
-- Cloudinary half was re-tested live and works; the row insert is
-- what failed. Direct table writes from the admin page depend on
-- is_admin() (not SECURITY DEFINER, reads admin_users under its own
-- RLS) and on the photos[] sync trigger updating businesses under the
-- admin's rights — too many places to fail quietly. These three
-- functions do the same work as the table owner, after one admin
-- check, and say exactly what went wrong when they refuse.
-- Safe to re-run.
-- ============================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.admin_add_business_photo(
  p_business_id UUID, p_url TEXT, p_public_id TEXT DEFAULT NULL, p_delete_token TEXT DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp
AS $$
DECLARE v_id UUID; v_has_main BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'login required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND COALESCE(disabled, FALSE) = FALSE) THEN
    RAISE EXCEPTION 'admin only';
  END IF;
  IF p_url IS NULL OR p_url !~ '^https://res\.cloudinary\.com/' THEN
    RAISE EXCEPTION 'not a Cloudinary URL';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM businesses WHERE id = p_business_id) THEN
    RAISE EXCEPTION 'business not found';
  END IF;
  SELECT EXISTS (SELECT 1 FROM business_photos WHERE business_id = p_business_id AND is_featured) INTO v_has_main;
  INSERT INTO business_photos (business_id, uploaded_by, cloudinary_url, cloudinary_public_id, delete_token, is_featured)
  VALUES (p_business_id, auth.uid(), p_url, p_public_id, p_delete_token, NOT v_has_main)
  RETURNING id INTO v_id;            -- enforce_photo_limit (8) still applies
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_delete_business_photo(p_photo_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp
AS $$
DECLARE v_biz UUID; v_was_main BOOLEAN;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND COALESCE(disabled, FALSE) = FALSE) THEN
    RAISE EXCEPTION 'admin only';
  END IF;
  DELETE FROM business_photos WHERE id = p_photo_id RETURNING business_id, is_featured INTO v_biz, v_was_main;
  IF v_biz IS NULL THEN RETURN FALSE; END IF;
  IF v_was_main THEN   -- promote the oldest remaining photo so the cards keep a picture
    UPDATE business_photos SET is_featured = TRUE
     WHERE id = (SELECT id FROM business_photos WHERE business_id = v_biz ORDER BY uploaded_at LIMIT 1);
  END IF;
  RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_main_photo(p_photo_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp
AS $$
DECLARE v_biz UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND COALESCE(disabled, FALSE) = FALSE) THEN
    RAISE EXCEPTION 'admin only';
  END IF;
  SELECT business_id INTO v_biz FROM business_photos WHERE id = p_photo_id;
  IF v_biz IS NULL THEN RETURN FALSE; END IF;
  UPDATE business_photos SET is_featured = (id = p_photo_id) WHERE business_id = v_biz;
  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_add_business_photo(UUID, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_delete_business_photo(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_main_photo(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_add_business_photo(UUID, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_business_photo(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_main_photo(UUID) TO authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/246-admin-photo-rpcs.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

SELECT f AS function_name,
       CASE WHEN to_regprocedure(f) IS NOT NULL THEN 'yes' ELSE 'NO' END AS exists
FROM unnest(ARRAY['public.admin_add_business_photo(uuid,text,text,text)',
                  'public.admin_delete_business_photo(uuid)',
                  'public.admin_set_main_photo(uuid)']) AS f;
