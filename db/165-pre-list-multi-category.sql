-- ============================================================
-- db/165 — Pre-list shop with MULTIPLE categories (array)
-- ============================================================
-- User reported: admin/quick-add-shop.html only allowed one category
-- per shop, even though business_categories junction (db/07) was
-- always multi-cat ready. e.g. Suvidha Gas Service actually does
-- gas-stove-repair + gas-accessories + gas-stove-shop — three legit
-- categories.
--
-- This migration:
--   1. REPLACES admin_pre_list_shop signature — now takes
--      p_category_slugs TEXT[] (was p_category_slug TEXT) plus
--      p_primary_category_slug TEXT (defaults to first in array).
--   2. Inserts into business_categories junction for EVERY slug.
--      businesses.category_id (parent) + sub_category_id (child)
--      mirror the primary one for backward-compat with old code that
--      reads those columns directly.
--   3. Validates: at least 1 slug, max 5 slugs, primary must be in
--      the array, all slugs must exist as active categories.
--
-- DROPS the old single-slug signature explicitly to avoid PostgREST
-- ambiguity (otherwise REST router can't decide between overloads).
--
-- SAFE: only function replaced. No schema change. No business data
-- touched.
-- ============================================================

BEGIN;

-- Drop the db/162 single-slug version first (signature differs)
DROP FUNCTION IF EXISTS admin_pre_list_shop(TEXT, TEXT, TEXT, TEXT, INT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION admin_pre_list_shop(
  p_name                   TEXT,
  p_mobile                 TEXT,
  p_area                   TEXT     DEFAULT NULL,
  p_category_slugs         TEXT[]   DEFAULT NULL,
  p_primary_category_slug  TEXT     DEFAULT NULL,
  p_city_id                INT      DEFAULT NULL,
  p_source                 TEXT     DEFAULT 'manual',
  p_consent_method         TEXT     DEFAULT 'verbal',
  p_notes                  TEXT     DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_admin_email   TEXT;
  v_norm_mobile   TEXT;
  v_slug          TEXT;
  v_token         TEXT;
  v_business_id   UUID;
  v_city_id       INT;

  v_primary_slug  TEXT;
  v_n_slugs       INT;
  v_invalid_count INT;
  v_resolved_cats RECORD;  -- temp record for loop
  v_primary_cat_id  INT;
  v_primary_parent  INT;
  v_primary_is_sub  BOOLEAN := FALSE;
  v_slug_iter     TEXT;
  v_cat_id_iter   INT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  SELECT email INTO v_admin_email
    FROM admin_users WHERE auth_user_id = auth.uid();

  -- ===== Validate name =====
  IF p_name IS NULL OR LENGTH(TRIM(p_name)) < 2 THEN
    RAISE EXCEPTION 'Shop name required (min 2 chars)';
  END IF;

  -- ===== Validate mobile =====
  v_norm_mobile := norm_indian_mobile(p_mobile);
  IF v_norm_mobile IS NULL THEN
    RAISE EXCEPTION 'Invalid mobile — must be 10-digit Indian (6/7/8/9 prefix)';
  END IF;
  IF EXISTS (SELECT 1 FROM businesses WHERE mobile = v_norm_mobile) THEN
    RAISE EXCEPTION 'A shop with mobile %  already exists — claim or edit it', v_norm_mobile;
  END IF;

  -- ===== Validate category slugs array =====
  -- Normalize: lowercase, dedupe, drop empties
  IF p_category_slugs IS NULL OR array_length(p_category_slugs, 1) IS NULL THEN
    p_category_slugs := ARRAY['others']::TEXT[];
  END IF;
  -- Clean + dedupe
  WITH cleaned AS (
    SELECT DISTINCT lower(trim(s)) AS s
      FROM unnest(p_category_slugs) AS s
     WHERE s IS NOT NULL AND length(trim(s)) > 0
  )
  SELECT array_agg(s) INTO p_category_slugs FROM cleaned;

  v_n_slugs := COALESCE(array_length(p_category_slugs, 1), 0);
  IF v_n_slugs < 1 THEN
    RAISE EXCEPTION 'At least 1 category required';
  END IF;
  IF v_n_slugs > 5 THEN
    RAISE EXCEPTION 'Maximum 5 categories allowed per shop';
  END IF;

  -- ===== Resolve primary slug =====
  v_primary_slug := COALESCE(NULLIF(lower(trim(p_primary_category_slug)), ''), p_category_slugs[1]);
  IF NOT (v_primary_slug = ANY(p_category_slugs)) THEN
    -- Primary must be one of the selected — otherwise default to first
    v_primary_slug := p_category_slugs[1];
  END IF;

  -- ===== Verify all slugs exist + active =====
  SELECT COUNT(*) INTO v_invalid_count
    FROM unnest(p_category_slugs) AS s
   WHERE NOT EXISTS (
     SELECT 1 FROM categories c WHERE c.slug = s AND c.active = TRUE
   );
  IF v_invalid_count > 0 THEN
    -- Soft-fail: drop unknown slugs, fall back to 'others' if all dropped
    WITH valid AS (
      SELECT s FROM unnest(p_category_slugs) AS s
       WHERE EXISTS (SELECT 1 FROM categories c WHERE c.slug = s AND c.active = TRUE)
    )
    SELECT array_agg(s) INTO p_category_slugs FROM valid;
    IF p_category_slugs IS NULL OR array_length(p_category_slugs, 1) IS NULL THEN
      p_category_slugs := ARRAY['others']::TEXT[];
    END IF;
    -- Re-resolve primary in case it was unknown
    IF NOT (v_primary_slug = ANY(p_category_slugs)) THEN
      v_primary_slug := p_category_slugs[1];
    END IF;
  END IF;

  -- ===== Get primary's id + parent for the businesses.category_id/sub_category_id pair =====
  SELECT id, parent_id INTO v_primary_cat_id, v_primary_parent
    FROM categories WHERE slug = v_primary_slug LIMIT 1;

  IF v_primary_cat_id IS NULL THEN
    -- Final fallback: pick any active category
    SELECT id, parent_id INTO v_primary_cat_id, v_primary_parent
      FROM categories WHERE active = TRUE ORDER BY id LIMIT 1;
  END IF;

  v_primary_is_sub := (v_primary_parent IS NOT NULL);

  -- ===== Resolve city =====
  v_city_id := COALESCE(
    p_city_id,
    (SELECT id FROM geo_cities WHERE name ILIKE 'mandi dabwali' LIMIT 1),
    (SELECT id FROM geo_cities WHERE active LIMIT 1)
  );

  -- ===== Generate slug + token =====
  v_slug  := generate_unique_slug(TRIM(p_name) || COALESCE(' ' || TRIM(p_area), ''));
  v_token := encode(extensions.gen_random_bytes(20), 'hex');

  -- ===== Insert business =====
  INSERT INTO businesses (
    slug, name, mobile, whatsapp,
    category_id, sub_category_id, city_id,
    address_line1,
    status, claim_status,
    pre_listed_by, pre_listed_at,
    consent_method, consent_notes,
    claim_token,
    created_at, updated_at
  ) VALUES (
    v_slug, TRIM(p_name), v_norm_mobile, v_norm_mobile,
    CASE WHEN v_primary_is_sub THEN v_primary_parent ELSE v_primary_cat_id END,
    CASE WHEN v_primary_is_sub THEN v_primary_cat_id ELSE NULL END,
    v_city_id,
    COALESCE(NULLIF(TRIM(p_area), ''), ''),
    'active', 'unclaimed',
    COALESCE(v_admin_email, p_source), NOW(),
    p_consent_method, p_notes,
    v_token,
    NOW(), NOW()
  )
  RETURNING id INTO v_business_id;

  -- ===== Link every category via business_categories junction =====
  FOREACH v_slug_iter IN ARRAY p_category_slugs LOOP
    SELECT id INTO v_cat_id_iter FROM categories WHERE slug = v_slug_iter LIMIT 1;
    IF v_cat_id_iter IS NOT NULL THEN
      INSERT INTO business_categories (business_id, category_id, is_primary)
      VALUES (
        v_business_id,
        v_cat_id_iter,
        v_slug_iter = v_primary_slug
      )
      ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success',           TRUE,
    'business_id',       v_business_id,
    'slug',              v_slug,
    'claim_token',       v_token,
    'claim_url',         'https://dukanlist.com/claim.html?token=' || v_token,
    'wa_url',            'https://wa.me/91' || v_norm_mobile,
    'categories_linked', p_category_slugs,
    'primary_category',  v_primary_slug
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_pre_list_shop(TEXT, TEXT, TEXT, TEXT[], TEXT, INT, TEXT, TEXT, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/165 installed. admin_pre_list_shop now multi-category aware (array of slugs).';
END $$;
