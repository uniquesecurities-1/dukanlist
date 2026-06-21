-- ============================================================
-- db/170 — Golden Pages admin manage RPCs
-- ============================================================
-- 4 admin-only RPCs to give admin full control over soft-listed
-- entries from a dedicated /admin/golden-pages-manage.html page:
--
--   1. admin_gp_list_all()       — paginated + filterable list view
--   2. admin_gp_update_soft()    — edit a soft listing's fields
--   3. admin_gp_delete_soft()    — hard delete (reference entry, no real loss)
--   4. admin_gp_promote_to_full() — graduate a soft listing into the
--                                   main DukanList — flips status
--                                   from 'soft_listed' to 'pending'
--                                   (joins normal moderation queue)
--                                   or 'active' (admin trusts data)
--
-- All 4 RPCs gate on is_admin(). All 4 only touch businesses where
-- status='soft_listed' (so admin tools can't accidentally fall over
-- onto live listings).
-- ============================================================

BEGIN;

-- ============================================================
-- 1. admin_gp_list_all — paginated, filterable list view
-- ============================================================
CREATE OR REPLACE FUNCTION admin_gp_list_all(
  p_city_id        INT  DEFAULT NULL,
  p_category_slug  TEXT DEFAULT NULL,
  p_search         TEXT DEFAULT NULL,
  p_only_no_mobile BOOLEAN DEFAULT FALSE,
  p_only_no_owner  BOOLEAN DEFAULT FALSE,
  p_limit          INT  DEFAULT 50,
  p_offset         INT  DEFAULT 0
)
RETURNS TABLE (
  id              UUID,
  slug            TEXT,
  name            TEXT,
  name_hi         TEXT,
  owner_name      TEXT,
  mobile          TEXT,
  area            TEXT,
  category_id     INT,
  category_name   TEXT,
  category_icon   TEXT,
  category_slug   TEXT,
  city_id         INT,
  city_name       TEXT,
  pre_listed_by   TEXT,
  pre_listed_at   TIMESTAMPTZ,
  consent_notes   TEXT,
  claim_token     TEXT,
  help_request_count INT,
  total_count     BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total BIGINT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  -- Pre-compute total for pagination UI
  SELECT COUNT(*) INTO v_total
    FROM businesses b
    LEFT JOIN categories c ON c.id = b.category_id
   WHERE b.status = 'soft_listed'
     AND (p_city_id IS NULL OR b.city_id = p_city_id)
     AND (p_category_slug IS NULL OR c.slug = p_category_slug)
     AND (p_search IS NULL OR LENGTH(TRIM(p_search)) = 0 OR
          b.name ILIKE '%' || TRIM(p_search) || '%' OR
          b.address_line1 ILIKE '%' || TRIM(p_search) || '%' OR
          COALESCE(b.owner_name,'') ILIKE '%' || TRIM(p_search) || '%')
     AND (NOT p_only_no_mobile OR b.mobile IS NULL OR LENGTH(b.mobile) <> 10)
     AND (NOT p_only_no_owner  OR b.owner_name IS NULL OR LENGTH(TRIM(b.owner_name)) = 0);

  RETURN QUERY
  SELECT
    b.id, b.slug, b.name, b.name_hi, b.owner_name, b.mobile, b.address_line1,
    b.category_id, c.name, c.icon, c.slug,
    b.city_id, gc.name,
    b.pre_listed_by, b.pre_listed_at, b.consent_notes,
    b.claim_token,
    (SELECT COUNT(*)::INT FROM gp_help_reach_log l WHERE l.business_id = b.id),
    v_total
  FROM businesses b
  LEFT JOIN categories c ON c.id = b.category_id
  LEFT JOIN geo_cities gc ON gc.id = b.city_id
  WHERE b.status = 'soft_listed'
    AND (p_city_id IS NULL OR b.city_id = p_city_id)
    AND (p_category_slug IS NULL OR c.slug = p_category_slug)
    AND (p_search IS NULL OR LENGTH(TRIM(p_search)) = 0 OR
         b.name ILIKE '%' || TRIM(p_search) || '%' OR
         b.address_line1 ILIKE '%' || TRIM(p_search) || '%' OR
         COALESCE(b.owner_name,'') ILIKE '%' || TRIM(p_search) || '%')
    AND (NOT p_only_no_mobile OR b.mobile IS NULL OR LENGTH(b.mobile) <> 10)
    AND (NOT p_only_no_owner  OR b.owner_name IS NULL OR LENGTH(TRIM(b.owner_name)) = 0)
  ORDER BY b.pre_listed_at DESC NULLS LAST
  LIMIT p_limit OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_gp_list_all(INT, TEXT, TEXT, BOOLEAN, BOOLEAN, INT, INT) TO authenticated;


-- ============================================================
-- 2. admin_gp_update_soft — edit a soft listing's fields
-- ============================================================
-- Whitelist of editable fields for soft listings. Also handles
-- multi-category swap via business_categories junction.
CREATE OR REPLACE FUNCTION admin_gp_update_soft(
  p_business_id            UUID,
  p_name                   TEXT DEFAULT NULL,
  p_name_hi                TEXT DEFAULT NULL,
  p_owner_name             TEXT DEFAULT NULL,
  p_mobile                 TEXT DEFAULT NULL,
  p_area                   TEXT DEFAULT NULL,
  p_city_id                INT  DEFAULT NULL,
  p_category_slugs         TEXT[] DEFAULT NULL,
  p_primary_category_slug  TEXT DEFAULT NULL,
  p_notes                  TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_norm_mobile     TEXT;
  v_existing_status TEXT;
  v_primary_slug    TEXT;
  v_primary_cat_id  INT;
  v_primary_parent  INT;
  v_slug_iter       TEXT;
  v_cat_id_iter     INT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  -- Guard: only edit soft-listed entries through this RPC
  SELECT status INTO v_existing_status FROM businesses WHERE id = p_business_id;
  IF v_existing_status IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;
  IF v_existing_status <> 'soft_listed' THEN
    RAISE EXCEPTION 'This listing is no longer soft_listed (status=%) — use the regular admin shop editor', v_existing_status;
  END IF;

  -- Validate mobile if provided
  IF p_mobile IS NOT NULL AND LENGTH(TRIM(p_mobile)) > 0 THEN
    v_norm_mobile := norm_indian_mobile(p_mobile);
    IF v_norm_mobile IS NULL THEN
      RAISE EXCEPTION 'Invalid mobile — must be 10-digit Indian (6/7/8/9 start)';
    END IF;
    -- Guard against assigning a mobile already owned by another biz
    IF EXISTS (SELECT 1 FROM businesses WHERE mobile = v_norm_mobile AND id <> p_business_id) THEN
      RAISE EXCEPTION 'Another listing already uses mobile %', v_norm_mobile;
    END IF;
  END IF;

  -- Apply simple field updates (NULL = leave unchanged for owner_name/mobile/etc;
  -- to clear use empty string explicitly)
  UPDATE businesses
     SET name         = COALESCE(NULLIF(TRIM(COALESCE(p_name,'')), ''),       name),
         name_hi      = CASE WHEN p_name_hi IS NULL THEN name_hi
                             WHEN TRIM(p_name_hi) = '' THEN NULL
                             ELSE TRIM(p_name_hi) END,
         owner_name   = CASE WHEN p_owner_name IS NULL THEN owner_name
                             WHEN TRIM(p_owner_name) = '' THEN NULL
                             ELSE TRIM(p_owner_name) END,
         mobile       = CASE WHEN p_mobile IS NULL THEN mobile
                             WHEN TRIM(p_mobile) = '' THEN NULL
                             ELSE v_norm_mobile END,
         whatsapp     = CASE WHEN p_mobile IS NULL THEN whatsapp
                             WHEN TRIM(p_mobile) = '' THEN NULL
                             ELSE v_norm_mobile END,
         address_line1 = CASE WHEN p_area IS NULL THEN address_line1
                             ELSE TRIM(p_area) END,
         city_id      = COALESCE(p_city_id, city_id),
         consent_notes = CASE WHEN p_notes IS NULL THEN consent_notes
                              WHEN TRIM(p_notes) = '' THEN NULL
                              ELSE TRIM(p_notes) END,
         updated_at   = NOW()
   WHERE id = p_business_id;

  -- Multi-category swap if requested
  IF p_category_slugs IS NOT NULL AND array_length(p_category_slugs, 1) IS NOT NULL THEN
    -- Resolve primary
    v_primary_slug := COALESCE(NULLIF(lower(trim(p_primary_category_slug)),''), p_category_slugs[1]);
    IF NOT (v_primary_slug = ANY(p_category_slugs)) THEN
      v_primary_slug := p_category_slugs[1];
    END IF;
    SELECT id, parent_id INTO v_primary_cat_id, v_primary_parent
      FROM categories WHERE slug = v_primary_slug AND active = TRUE LIMIT 1;
    IF v_primary_cat_id IS NULL THEN
      RAISE EXCEPTION 'Invalid primary category: %', v_primary_slug;
    END IF;

    -- Update businesses.category_id / sub_category_id mirror
    UPDATE businesses
       SET category_id     = CASE WHEN v_primary_parent IS NOT NULL THEN v_primary_parent ELSE v_primary_cat_id END,
           sub_category_id = CASE WHEN v_primary_parent IS NOT NULL THEN v_primary_cat_id ELSE NULL END,
           updated_at      = NOW()
     WHERE id = p_business_id;

    -- Wipe + re-insert junction rows
    DELETE FROM business_categories WHERE business_id = p_business_id;
    FOREACH v_slug_iter IN ARRAY p_category_slugs LOOP
      SELECT id INTO v_cat_id_iter FROM categories WHERE slug = v_slug_iter LIMIT 1;
      IF v_cat_id_iter IS NOT NULL THEN
        INSERT INTO business_categories (business_id, category_id, is_primary)
        VALUES (p_business_id, v_cat_id_iter, v_slug_iter = v_primary_slug)
        ON CONFLICT DO NOTHING;
      END IF;
    END LOOP;
  END IF;

  RETURN jsonb_build_object('success', TRUE, 'business_id', p_business_id);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_gp_update_soft(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, INT, TEXT[], TEXT, TEXT) TO authenticated;


-- ============================================================
-- 3. admin_gp_delete_soft — hard delete a soft listing
-- ============================================================
-- Soft listings are reference entries — no owner data, no
-- customer reviews, no orders. Safe to hard-delete. Won't fire
-- if the listing has been promoted to active/pending.
CREATE OR REPLACE FUNCTION admin_gp_delete_soft(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
  v_name   TEXT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  SELECT status, name INTO v_status, v_name
    FROM businesses WHERE id = p_business_id;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;
  IF v_status <> 'soft_listed' THEN
    RAISE EXCEPTION 'Cannot delete via this RPC — listing has been promoted (status=%). Use admin shop editor.', v_status;
  END IF;

  DELETE FROM businesses WHERE id = p_business_id;

  RETURN jsonb_build_object('success', TRUE, 'deleted_name', v_name);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_gp_delete_soft(UUID) TO authenticated;


-- ============================================================
-- 4. admin_gp_promote_to_full — graduate to main DukanList
-- ============================================================
-- Two target statuses supported:
--   • 'pending' (default) — enters normal admin moderation queue
--     (subject to email gate). Use this when admin wants the
--     listing reviewed before going public.
--   • 'active' — direct publish on main DukanList (admin trusts
--     the data and skips moderation).
CREATE OR REPLACE FUNCTION admin_gp_promote_to_full(
  p_business_id   UUID,
  p_target_status TEXT DEFAULT 'pending'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
  v_name   TEXT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;
  IF p_target_status NOT IN ('pending','active') THEN
    RAISE EXCEPTION 'p_target_status must be ''pending'' or ''active''';
  END IF;

  SELECT status, name INTO v_status, v_name
    FROM businesses WHERE id = p_business_id;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;
  IF v_status <> 'soft_listed' THEN
    RAISE EXCEPTION 'Already promoted (current status=%)', v_status;
  END IF;

  UPDATE businesses
     SET status     = p_target_status,
         updated_at = NOW()
   WHERE id = p_business_id;

  RETURN jsonb_build_object(
    'success',        TRUE,
    'business_id',    p_business_id,
    'name',           v_name,
    'new_status',     p_target_status
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_gp_promote_to_full(UUID, TEXT) TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/170 installed. 4 admin RPCs for Golden Pages management live.';
END $$;
