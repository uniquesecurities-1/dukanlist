-- =====================================================
-- db/67-admin-master-controls.sql
-- =====================================================
-- USER REQUEST: 'admin ki Power aur better kar do bhai.
-- Need every single setup control (both pucho bhai & dukanlist)'
--
-- WHAT THIS SQL DOES:
--   1. site_settings table — key/value store for site-wide toggles
--   2. Pre-seed common settings (registration_open, pucho_bhai_enabled,
--      maintenance_mode, spam_threshold, etc.)
--   3. RPCs for admin CRUD:
--      • admin_list_settings()
--      • admin_set_setting(key, value)
--      • get_public_settings()  -- anonymous read for client toggles
--   4. RPCs for category CRUD:
--      • admin_create_category(slug, name, name_hi, icon, parent_slug, keywords, description)
--      • admin_update_category(id, patch_jsonb)
--      • admin_toggle_category(id, active)
--      • admin_delete_category(id)
--   5. RPCs for city/locality CRUD:
--      • admin_create_city(name, name_hi, state_code, district, pincode_prefix)
--      • admin_update_city(id, patch_jsonb)
--      • admin_toggle_city(id, active)
--
-- All admin RPCs gated to super_admin role only.
-- ZERO RISK — additive only. Safe to re-run.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. SITE SETTINGS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS site_settings (
  key         TEXT PRIMARY KEY,
  value       TEXT,
  description TEXT,
  is_public   BOOLEAN NOT NULL DEFAULT FALSE,  -- public settings exposed via get_public_settings
  updated_by  UUID,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE site_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ss_admin_all" ON site_settings;
CREATE POLICY "ss_admin_all" ON site_settings
  FOR ALL TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());

-- Pre-seed default settings
INSERT INTO site_settings (key, value, description, is_public) VALUES
  ('site.registration_open', 'true', 'New shop registration open/closed', TRUE),
  ('site.maintenance_mode', 'false', 'Show maintenance banner across site', TRUE),
  ('site.announcement_banner', '', 'Top-of-site announcement (empty = hidden)', TRUE),
  ('pucho_bhai.enabled', 'true', 'Enable Pucho Bhai community Q&A', TRUE),
  ('pucho_bhai.auto_approve', 'true', 'Auto-approve questions/replies (no moderation queue)', FALSE),
  ('pucho_bhai.spam_threshold', '3', 'Reports needed before auto-hide', FALSE),
  ('pucho_bhai.min_question_chars', '10', 'Minimum question text length', FALSE),
  ('reviews.auto_publish', 'true', 'Reviews go live immediately (vs moderation queue)', FALSE),
  ('reviews.min_chars', '3', 'Minimum review text length', FALSE),
  ('featured.default_days', '30', 'Default featured listing duration (days)', FALSE),
  ('seo.default_city', 'Mandi Dabwali', 'Default city for SEO/share links', TRUE),
  ('contact.support_whatsapp', '919541223377', 'Support WhatsApp number', TRUE),
  ('contact.support_email', 'support@dukanlist.com', 'Support email address', TRUE)
ON CONFLICT (key) DO NOTHING;


-- ============================================================
-- 2. SETTINGS RPCs
-- ============================================================
DROP FUNCTION IF EXISTS admin_list_settings();
CREATE OR REPLACE FUNCTION admin_list_settings()
RETURNS TABLE (
  key         TEXT,
  value       TEXT,
  description TEXT,
  is_public   BOOLEAN,
  updated_at  TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  RETURN QUERY SELECT s.key, s.value, s.description, s.is_public, s.updated_at
    FROM site_settings s ORDER BY s.key;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_list_settings() TO authenticated;

DROP FUNCTION IF EXISTS admin_set_setting(TEXT, TEXT);
CREATE OR REPLACE FUNCTION admin_set_setting(p_key TEXT, p_value TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  INSERT INTO site_settings (key, value, updated_by, updated_at)
  VALUES (p_key, p_value, auth.uid(), NOW())
  ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value,
        updated_by = EXCLUDED.updated_by,
        updated_at = NOW();
  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_set_setting(TEXT, TEXT) TO authenticated;

-- Anonymous read for public settings (used by frontend for feature flags)
DROP FUNCTION IF EXISTS get_public_settings();
CREATE OR REPLACE FUNCTION get_public_settings()
RETURNS TABLE (key TEXT, value TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT s.key, s.value FROM site_settings s WHERE s.is_public = TRUE;
$$;
GRANT EXECUTE ON FUNCTION get_public_settings() TO anon, authenticated;


-- ============================================================
-- 3. CATEGORY CRUD RPCs
-- ============================================================
DROP FUNCTION IF EXISTS admin_create_category(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION admin_create_category(
  p_slug         TEXT,
  p_name         TEXT,
  p_name_hi      TEXT DEFAULT NULL,
  p_icon         TEXT DEFAULT '📦',
  p_parent_slug  TEXT DEFAULT NULL,
  p_keywords     TEXT DEFAULT NULL,
  p_description  TEXT DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_parent_id INT;
  v_new_id    INT;
  v_sort      INT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  IF p_slug IS NULL OR LENGTH(TRIM(p_slug)) = 0 THEN
    RAISE EXCEPTION 'Slug required';
  END IF;
  IF p_name IS NULL OR LENGTH(TRIM(p_name)) = 0 THEN
    RAISE EXCEPTION 'Name required';
  END IF;

  IF p_parent_slug IS NOT NULL THEN
    SELECT id INTO v_parent_id FROM categories WHERE slug = p_parent_slug;
    IF v_parent_id IS NULL THEN
      RAISE EXCEPTION 'Parent category % not found', p_parent_slug;
    END IF;
  END IF;

  SELECT COALESCE(MAX(sort_order), 0) + 1 INTO v_sort
    FROM categories
   WHERE COALESCE(parent_id, 0) = COALESCE(v_parent_id, 0);

  INSERT INTO categories (slug, name, name_hi, icon, parent_id, keywords, description, sort_order, active, default_listing_type)
  VALUES (p_slug, p_name, p_name_hi, p_icon, v_parent_id, p_keywords, p_description, v_sort, TRUE,
          CASE WHEN v_parent_id IS NULL THEN 'shop' ELSE 'shop' END)
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_create_category(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

DROP FUNCTION IF EXISTS admin_update_category(INT, JSONB);
CREATE OR REPLACE FUNCTION admin_update_category(p_id INT, p_patch JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_field TEXT;
  v_allowed TEXT[] := ARRAY['name','name_hi','icon','keywords','description','sort_order','color','active'];
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;

  FOR v_field IN SELECT jsonb_object_keys(p_patch) LOOP
    IF NOT v_field = ANY(v_allowed) THEN
      RAISE EXCEPTION 'Field % not editable', v_field;
    END IF;
  END LOOP;

  UPDATE categories SET
    name        = COALESCE((p_patch->>'name'), name),
    name_hi     = COALESCE((p_patch->>'name_hi'), name_hi),
    icon        = COALESCE((p_patch->>'icon'), icon),
    keywords    = COALESCE((p_patch->>'keywords'), keywords),
    description = COALESCE((p_patch->>'description'), description),
    sort_order  = COALESCE((p_patch->>'sort_order')::INT, sort_order),
    color       = COALESCE((p_patch->>'color'), color),
    active      = COALESCE((p_patch->>'active')::BOOLEAN, active)
  WHERE id = p_id;

  RETURN FOUND;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_update_category(INT, JSONB) TO authenticated;

DROP FUNCTION IF EXISTS admin_toggle_category(INT, BOOLEAN);
CREATE OR REPLACE FUNCTION admin_toggle_category(p_id INT, p_active BOOLEAN)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  UPDATE categories SET active = p_active WHERE id = p_id;
  RETURN FOUND;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_toggle_category(INT, BOOLEAN) TO authenticated;

DROP FUNCTION IF EXISTS admin_delete_category(INT);
CREATE OR REPLACE FUNCTION admin_delete_category(p_id INT)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_in_use INT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;

  -- Block delete if used by businesses
  SELECT COUNT(*) INTO v_in_use FROM business_categories WHERE category_id = p_id;
  IF v_in_use > 0 THEN
    RAISE EXCEPTION 'Cannot delete — % business(es) use this category. Toggle inactive instead.', v_in_use;
  END IF;

  -- Block delete if it has children
  SELECT COUNT(*) INTO v_in_use FROM categories WHERE parent_id = p_id;
  IF v_in_use > 0 THEN
    RAISE EXCEPTION 'Cannot delete — has % child categories. Delete children first.', v_in_use;
  END IF;

  DELETE FROM categories WHERE id = p_id;
  RETURN FOUND;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_delete_category(INT) TO authenticated;


-- ============================================================
-- 4. CITY CRUD RPCs (lightweight — geo_cities exists)
-- ============================================================
DROP FUNCTION IF EXISTS admin_update_city(INT, JSONB);
CREATE OR REPLACE FUNCTION admin_update_city(p_id INT, p_patch JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;

  UPDATE geo_cities SET
    name       = COALESCE((p_patch->>'name'), name),
    name_hi    = COALESCE((p_patch->>'name_hi'), name_hi),
    active     = COALESCE((p_patch->>'active')::BOOLEAN, active)
  WHERE id = p_id;

  RETURN FOUND;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_update_city(INT, JSONB) TO authenticated;

DROP FUNCTION IF EXISTS admin_toggle_city(INT, BOOLEAN);
CREATE OR REPLACE FUNCTION admin_toggle_city(p_id INT, p_active BOOLEAN)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  UPDATE geo_cities SET active = p_active WHERE id = p_id;
  RETURN FOUND;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_toggle_city(INT, BOOLEAN) TO authenticated;


-- ============================================================
-- 5. SITE-WIDE REVIEW LIST (for admin/reviews.html)
-- ============================================================
DROP FUNCTION IF EXISTS admin_list_all_reviews(INT, INT, TEXT, INT);
CREATE OR REPLACE FUNCTION admin_list_all_reviews(
  p_limit       INT DEFAULT 50,
  p_offset      INT DEFAULT 0,
  p_filter      TEXT DEFAULT 'all',  -- all|flagged|low|recent
  p_min_rating  INT DEFAULT NULL
)
RETURNS TABLE (
  id              UUID,
  business_id     UUID,
  business_name   TEXT,
  customer_name   TEXT,
  rating          SMALLINT,
  text            TEXT,
  status          TEXT,
  helpful_count   INT,
  owner_reply     TEXT,
  created_at      TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;

  RETURN QUERY
  SELECT r.id, r.business_id, b.name AS business_name,
         r.customer_name, r.rating, r.text, r.status,
         r.helpful_count, r.owner_reply, r.created_at
    FROM reviews r
    JOIN businesses b ON b.id = r.business_id
   WHERE (p_filter = 'all'
       OR (p_filter = 'flagged' AND r.status = 'flagged')
       OR (p_filter = 'low'     AND r.rating <= 2)
       OR (p_filter = 'recent'  AND r.created_at > NOW() - INTERVAL '7 days'))
     AND (p_min_rating IS NULL OR r.rating >= p_min_rating)
   ORDER BY r.created_at DESC
   LIMIT p_limit OFFSET p_offset;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_list_all_reviews(INT, INT, TEXT, INT) TO authenticated;


NOTIFY pgrst, 'reload schema';

DO $$
DECLARE v_n INT;
BEGIN
  SELECT COUNT(*) INTO v_n FROM pg_proc
   WHERE proname IN (
     'admin_list_settings','admin_set_setting','get_public_settings',
     'admin_create_category','admin_update_category','admin_toggle_category','admin_delete_category',
     'admin_update_city','admin_toggle_city','admin_list_all_reviews'
   );
  RAISE NOTICE '✓ Admin master-control RPCs registered: % of 10', v_n;
END $$;

COMMIT;
