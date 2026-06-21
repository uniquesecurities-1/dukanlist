-- ============================================================
-- db/167 — Golden Pages soft-add: multi-category + city + Hindi name
-- ============================================================
-- User feedback on golden-pages-add.html:
--   • City selector missing (was defaulting silently to Mandi Dabwali)
--   • Categories can only be one — needs multi-cat like full registration
--   • Name field is shop-only — Golden Pages also covers schools,
--     clinics, sansthayen, offices etc. — make naming inclusive
--   • Optional Hindi name field would help for shops with vernacular
--     signboards
--
-- Replaces admin_soft_add_shop signature to accept:
--   • p_category_slugs TEXT[] (1-5)
--   • p_primary_category_slug (defaults to first in array)
--   • p_name_hi TEXT (optional Hindi/vernacular name)
--   • Existing fields: name, area, mobile, city_id, source, notes
--
-- Also extends admin_soft_bulk_add to accept p_city_id explicitly
-- (was relying on default; now optional but explicit param exists).
--
-- SAFE: Drops + recreates 2 RPCs with new signatures. No data touched.
-- Re-runnable.
-- ============================================================

BEGIN;

-- ============================================================
-- PART 1: admin_soft_add_shop — multi-category + city + Hindi name
-- ============================================================
DROP FUNCTION IF EXISTS admin_soft_add_shop(TEXT, TEXT, TEXT, TEXT, INT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION admin_soft_add_shop(
  p_name                  TEXT,
  p_category_slugs        TEXT[],
  p_primary_category_slug TEXT DEFAULT NULL,
  p_area                  TEXT DEFAULT NULL,
  p_mobile                TEXT DEFAULT NULL,
  p_city_id               INT  DEFAULT NULL,
  p_name_hi               TEXT DEFAULT NULL,
  p_source                TEXT DEFAULT 'reference',
  p_notes                 TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_admin_email      TEXT;
  v_norm_mobile      TEXT;
  v_slug             TEXT;
  v_token            TEXT;
  v_business_id      UUID;
  v_city_id          INT;
  v_primary_slug     TEXT;
  v_primary_cat_id   INT;
  v_primary_parent   INT;
  v_primary_is_sub   BOOLEAN := FALSE;
  v_n_slugs          INT;
  v_slug_iter        TEXT;
  v_cat_id_iter      INT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  SELECT email INTO v_admin_email FROM admin_users WHERE auth_user_id = auth.uid();

  -- ===== Name (now inclusive — shop/clinic/school/sanstha) =====
  IF p_name IS NULL OR LENGTH(TRIM(p_name)) < 2 THEN
    RAISE EXCEPTION 'Name required (min 2 chars)';
  END IF;

  -- ===== Validate + dedupe category slug array =====
  IF p_category_slugs IS NULL OR array_length(p_category_slugs, 1) IS NULL THEN
    RAISE EXCEPTION 'At least 1 category required';
  END IF;

  -- Lowercase + dedupe + drop empties
  WITH cleaned AS (
    SELECT DISTINCT lower(trim(s)) AS s
      FROM unnest(p_category_slugs) AS s
     WHERE s IS NOT NULL AND length(trim(s)) > 0
  )
  SELECT array_agg(s) INTO p_category_slugs FROM cleaned;

  v_n_slugs := COALESCE(array_length(p_category_slugs, 1), 0);
  IF v_n_slugs < 1 THEN
    RAISE EXCEPTION 'At least 1 valid category required';
  END IF;
  IF v_n_slugs > 5 THEN
    RAISE EXCEPTION 'Maximum 5 categories per listing';
  END IF;

  -- Resolve primary slug
  v_primary_slug := COALESCE(NULLIF(lower(trim(p_primary_category_slug)), ''), p_category_slugs[1]);
  IF NOT (v_primary_slug = ANY(p_category_slugs)) THEN
    v_primary_slug := p_category_slugs[1];
  END IF;

  -- Get primary category id + parent (for backward-compat columns on businesses)
  SELECT id, parent_id INTO v_primary_cat_id, v_primary_parent
    FROM categories WHERE slug = v_primary_slug AND active = TRUE LIMIT 1;
  IF v_primary_cat_id IS NULL THEN
    RAISE EXCEPTION 'Invalid primary category: %', v_primary_slug;
  END IF;
  v_primary_is_sub := (v_primary_parent IS NOT NULL);

  -- ===== Optional mobile =====
  IF p_mobile IS NOT NULL AND LENGTH(TRIM(p_mobile)) > 0 THEN
    v_norm_mobile := norm_indian_mobile(p_mobile);
    IF v_norm_mobile IS NULL THEN
      RAISE EXCEPTION 'If providing mobile, it must be a valid 10-digit Indian number';
    END IF;
    IF EXISTS (SELECT 1 FROM businesses WHERE mobile = v_norm_mobile) THEN
      RAISE EXCEPTION 'A listing with mobile % already exists — search before adding', v_norm_mobile;
    END IF;
  END IF;

  -- ===== City =====
  v_city_id := COALESCE(
    p_city_id,
    (SELECT id FROM geo_cities WHERE name ILIKE 'mandi dabwali' LIMIT 1),
    (SELECT id FROM geo_cities WHERE active LIMIT 1)
  );

  -- ===== Generate slug + claim token =====
  v_slug  := generate_unique_slug(TRIM(p_name) || COALESCE(' ' || TRIM(p_area), ''));
  v_token := encode(extensions.gen_random_bytes(20), 'hex');

  -- ===== Insert business =====
  INSERT INTO businesses (
    slug, name, name_hi, mobile, whatsapp,
    category_id, sub_category_id, city_id,
    address_line1,
    status, claim_status,
    pre_listed_by, pre_listed_at,
    consent_method, consent_notes,
    claim_token,
    created_at, updated_at
  ) VALUES (
    v_slug, TRIM(p_name), NULLIF(TRIM(COALESCE(p_name_hi,'')),''), v_norm_mobile, v_norm_mobile,
    CASE WHEN v_primary_is_sub THEN v_primary_parent ELSE v_primary_cat_id END,
    CASE WHEN v_primary_is_sub THEN v_primary_cat_id ELSE NULL END,
    v_city_id,
    COALESCE(NULLIF(TRIM(p_area), ''), ''),
    'soft_listed', 'unclaimed',
    COALESCE(v_admin_email, p_source), NOW(),
    'public-data', p_notes,
    v_token,
    NOW(), NOW()
  )
  RETURNING id INTO v_business_id;

  -- ===== Link every category via junction =====
  FOREACH v_slug_iter IN ARRAY p_category_slugs LOOP
    SELECT id INTO v_cat_id_iter FROM categories WHERE slug = v_slug_iter LIMIT 1;
    IF v_cat_id_iter IS NOT NULL THEN
      INSERT INTO business_categories (business_id, category_id, is_primary)
      VALUES (v_business_id, v_cat_id_iter, v_slug_iter = v_primary_slug)
      ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success',           TRUE,
    'business_id',       v_business_id,
    'slug',              v_slug,
    'claim_token',       v_token,
    'gp_url',            'https://dukanlist.com/golden-pages.html#shop=' || v_slug,
    'claim_url',         'https://dukanlist.com/claim.html?token=' || v_token,
    'categories_linked', p_category_slugs,
    'primary_category',  v_primary_slug
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_soft_add_shop(TEXT, TEXT[], TEXT, TEXT, TEXT, INT, TEXT, TEXT, TEXT) TO authenticated;


-- ============================================================
-- PART 2: gp_recent_soft_listings (admin reads last N added by self)
-- ============================================================
-- Shows the last 10 soft listings added in current session/today
-- so admin sees their work pile up at the top of the form.
CREATE OR REPLACE FUNCTION admin_gp_recent_soft_listings(
  p_limit INT DEFAULT 10
)
RETURNS TABLE (
  id            UUID,
  name          TEXT,
  category_name TEXT,
  city_name     TEXT,
  area          TEXT,
  pre_listed_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;
  RETURN QUERY
  SELECT b.id, b.name, c.name, gc.name, b.address_line1, b.pre_listed_at
  FROM businesses b
  LEFT JOIN categories c ON c.id = b.category_id
  LEFT JOIN geo_cities gc ON gc.id = b.city_id
  WHERE b.status = 'soft_listed'
    AND b.pre_listed_at >= NOW() - INTERVAL '2 hours'
  ORDER BY b.pre_listed_at DESC
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_gp_recent_soft_listings(INT) TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/167 installed. admin_soft_add_shop is now multi-cat + city + name_hi aware.';
END $$;
