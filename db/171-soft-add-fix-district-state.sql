-- ============================================================
-- db/171 — admin_soft_add_shop: auto-derive district_id + state_id
-- ============================================================
-- BUG (user screenshot):
--   null value in column "district_id" of relation "businesses"
--   violates not-null constraint
--
-- ROOT CAUSE:
--   businesses.district_id is NOT NULL (db/01-schema.sql line 105),
--   but db/169's admin_soft_add_shop only set city_id and forgot to
--   look up + write district_id (and state_id) from geo_cities.
--
-- FIX:
--   After we resolve v_city_id, JOIN to geo_cities to fetch
--   district_id, then JOIN geo_districts for state_id. Insert all
--   three on the businesses row.
--
-- BONUS:
--   If somehow city not found in geo_cities, raise a clear error
--   instead of letting the NOT NULL constraint blow up cryptically.
--
-- SAFE: same 10-param signature as db/169 (no breaking changes).
-- ============================================================

BEGIN;

DROP FUNCTION IF EXISTS admin_soft_add_shop(TEXT, TEXT[], TEXT, TEXT, TEXT, INT, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION admin_soft_add_shop(
  p_name                  TEXT,
  p_category_slugs        TEXT[],
  p_primary_category_slug TEXT DEFAULT NULL,
  p_area                  TEXT DEFAULT NULL,
  p_mobile                TEXT DEFAULT NULL,
  p_city_id               INT  DEFAULT NULL,
  p_name_hi               TEXT DEFAULT NULL,
  p_owner_name            TEXT DEFAULT NULL,
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
  v_district_id      INT;
  v_state_id         SMALLINT;
  v_primary_slug     TEXT;
  v_primary_cat_id   INT;
  v_primary_parent   INT;
  v_primary_is_sub   BOOLEAN := FALSE;
  v_n_slugs          INT;
  v_slug_iter        TEXT;
  v_cat_id_iter      INT;
  v_clean_owner      TEXT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  SELECT email INTO v_admin_email FROM admin_users WHERE auth_user_id = auth.uid();

  -- Name (inclusive)
  IF p_name IS NULL OR LENGTH(TRIM(p_name)) < 2 THEN
    RAISE EXCEPTION 'Name required (min 2 chars)';
  END IF;

  -- Validate + dedupe category slug array
  IF p_category_slugs IS NULL OR array_length(p_category_slugs, 1) IS NULL THEN
    RAISE EXCEPTION 'At least 1 category required';
  END IF;

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

  v_primary_slug := COALESCE(NULLIF(lower(trim(p_primary_category_slug)), ''), p_category_slugs[1]);
  IF NOT (v_primary_slug = ANY(p_category_slugs)) THEN
    v_primary_slug := p_category_slugs[1];
  END IF;

  SELECT id, parent_id INTO v_primary_cat_id, v_primary_parent
    FROM categories WHERE slug = v_primary_slug AND active = TRUE LIMIT 1;
  IF v_primary_cat_id IS NULL THEN
    RAISE EXCEPTION 'Invalid primary category: %', v_primary_slug;
  END IF;
  v_primary_is_sub := (v_primary_parent IS NOT NULL);

  -- Optional mobile
  IF p_mobile IS NOT NULL AND LENGTH(TRIM(p_mobile)) > 0 THEN
    v_norm_mobile := norm_indian_mobile(p_mobile);
    IF v_norm_mobile IS NULL THEN
      RAISE EXCEPTION 'If providing mobile, it must be a valid 10-digit Indian number';
    END IF;
    IF EXISTS (SELECT 1 FROM businesses WHERE mobile = v_norm_mobile) THEN
      RAISE EXCEPTION 'A listing with mobile % already exists — search before adding', v_norm_mobile;
    END IF;
  END IF;

  -- Resolve city: passed-in → Mandi Dabwali → first active
  v_city_id := COALESCE(
    p_city_id,
    (SELECT id FROM geo_cities WHERE name ILIKE 'mandi dabwali' AND active LIMIT 1),
    (SELECT id FROM geo_cities WHERE active LIMIT 1)
  );

  IF v_city_id IS NULL THEN
    RAISE EXCEPTION 'No active city available in geo_cities — seed cities first';
  END IF;

  -- *** FIX: derive district_id from city, state_id from district ***
  SELECT c.district_id, d.state_id
    INTO v_district_id, v_state_id
    FROM geo_cities c
    JOIN geo_districts d ON d.id = c.district_id
   WHERE c.id = v_city_id
   LIMIT 1;

  IF v_district_id IS NULL THEN
    RAISE EXCEPTION 'City % has no district mapping in geo_cities (fix geo seed)', v_city_id;
  END IF;

  -- Owner name: trim + treat blank as NULL (db/168 made the column nullable)
  v_clean_owner := NULLIF(TRIM(COALESCE(p_owner_name, '')), '');

  v_slug  := generate_unique_slug(TRIM(p_name) || COALESCE(' ' || TRIM(p_area), ''));
  v_token := encode(extensions.gen_random_bytes(20), 'hex');

  INSERT INTO businesses (
    slug, name, name_hi, owner_name, mobile, whatsapp,
    category_id, sub_category_id,
    city_id, district_id, state_id,
    address_line1,
    status, claim_status,
    pre_listed_by, pre_listed_at,
    consent_method, consent_notes,
    claim_token,
    created_at, updated_at
  ) VALUES (
    v_slug, TRIM(p_name),
    NULLIF(TRIM(COALESCE(p_name_hi,'')),''),
    v_clean_owner,
    v_norm_mobile, v_norm_mobile,
    CASE WHEN v_primary_is_sub THEN v_primary_parent ELSE v_primary_cat_id END,
    CASE WHEN v_primary_is_sub THEN v_primary_cat_id ELSE NULL END,
    v_city_id, v_district_id, v_state_id,
    COALESCE(NULLIF(TRIM(p_area), ''), ''),
    'soft_listed', 'unclaimed',
    COALESCE(v_admin_email, p_source), NOW(),
    'public-data', p_notes,
    v_token,
    NOW(), NOW()
  )
  RETURNING id INTO v_business_id;

  -- Link every category via junction
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
    'primary_category',  v_primary_slug,
    'city_id',           v_city_id,
    'district_id',       v_district_id,
    'owner_name',        v_clean_owner
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_soft_add_shop(TEXT, TEXT[], TEXT, TEXT, TEXT, INT, TEXT, TEXT, TEXT, TEXT) TO authenticated;


-- ============================================================
-- PART 2: Same fix for admin_soft_bulk_add
-- ============================================================
-- The Bulk Paste tab on /admin/golden-pages-add.html would hit the
-- exact same district_id NOT NULL error. Patching here so both
-- entry points stay in sync.
-- ============================================================

CREATE OR REPLACE FUNCTION admin_soft_bulk_add(
  p_names          TEXT[],
  p_category_slug  TEXT,
  p_area           TEXT DEFAULT NULL,
  p_city_id        INT  DEFAULT NULL,
  p_source         TEXT DEFAULT 'bulk-reference'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_admin_email  TEXT;
  v_category_id  INT;
  v_city_id      INT;
  v_district_id  INT;
  v_state_id     SMALLINT;
  v_name         TEXT;
  v_clean_name   TEXT;
  v_slug         TEXT;
  v_token        TEXT;
  v_business_id  UUID;
  v_added        INT := 0;
  v_skipped      INT := 0;
  v_added_list   JSONB := '[]'::jsonb;
  v_skipped_list JSONB := '[]'::jsonb;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  SELECT email INTO v_admin_email FROM admin_users WHERE auth_user_id = auth.uid();

  IF p_names IS NULL OR array_length(p_names, 1) IS NULL OR array_length(p_names, 1) < 1 THEN
    RAISE EXCEPTION 'Provide at least 1 name';
  END IF;
  IF array_length(p_names, 1) > 500 THEN
    RAISE EXCEPTION 'Max 500 names per batch — split into smaller chunks';
  END IF;

  SELECT id INTO v_category_id FROM categories WHERE slug = p_category_slug AND active = TRUE LIMIT 1;
  IF v_category_id IS NULL THEN
    RAISE EXCEPTION 'Invalid category: %', p_category_slug;
  END IF;

  v_city_id := COALESCE(
    p_city_id,
    (SELECT id FROM geo_cities WHERE name ILIKE 'mandi dabwali' AND active LIMIT 1),
    (SELECT id FROM geo_cities WHERE active LIMIT 1)
  );

  IF v_city_id IS NULL THEN
    RAISE EXCEPTION 'No active city available in geo_cities';
  END IF;

  -- *** FIX: derive district + state ***
  SELECT c.district_id, d.state_id
    INTO v_district_id, v_state_id
    FROM geo_cities c
    JOIN geo_districts d ON d.id = c.district_id
   WHERE c.id = v_city_id
   LIMIT 1;

  IF v_district_id IS NULL THEN
    RAISE EXCEPTION 'City % has no district mapping', v_city_id;
  END IF;

  FOREACH v_name IN ARRAY p_names LOOP
    v_clean_name := TRIM(COALESCE(v_name, ''));
    IF v_clean_name = '' OR LENGTH(v_clean_name) < 2 THEN
      v_skipped := v_skipped + 1;
      v_skipped_list := v_skipped_list || jsonb_build_object('name', v_name, 'reason', 'too short');
      CONTINUE;
    END IF;

    v_slug := generate_unique_slug(v_clean_name || COALESCE(' ' || TRIM(p_area), ''));
    v_token := encode(extensions.gen_random_bytes(20), 'hex');

    BEGIN
      INSERT INTO businesses (
        slug, name,
        category_id,
        city_id, district_id, state_id,
        address_line1,
        status, claim_status,
        pre_listed_by, pre_listed_at,
        consent_method,
        claim_token,
        created_at, updated_at
      ) VALUES (
        v_slug, v_clean_name,
        v_category_id,
        v_city_id, v_district_id, v_state_id,
        COALESCE(NULLIF(TRIM(p_area), ''), ''),
        'soft_listed', 'unclaimed',
        COALESCE(v_admin_email, p_source), NOW(),
        'public-data',
        v_token,
        NOW(), NOW()
      )
      RETURNING id INTO v_business_id;

      INSERT INTO business_categories (business_id, category_id, is_primary)
      VALUES (v_business_id, v_category_id, TRUE)
      ON CONFLICT DO NOTHING;

      v_added := v_added + 1;
      v_added_list := v_added_list || jsonb_build_object(
        'name', v_clean_name,
        'slug', v_slug,
        'business_id', v_business_id
      );
    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      v_skipped_list := v_skipped_list || jsonb_build_object(
        'name', v_clean_name, 'reason', SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', TRUE,
    'added',   v_added,
    'skipped', v_skipped,
    'added_list',   v_added_list,
    'skipped_list', v_skipped_list
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_soft_bulk_add(TEXT[], TEXT, TEXT, INT, TEXT) TO authenticated;


-- ============================================================
-- PART 3: admin_gp_update_soft — cascade district + state when city changes
-- ============================================================
-- Manage page (db/170) lets admin change the city, but only updated
-- city_id. district_id + state_id would go stale (point to old
-- district), breaking listings if admin moves a shop from one
-- district to another. Patch the UPDATE statement to recompute both.
-- ============================================================

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
  v_new_district    INT;
  v_new_state       SMALLINT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  SELECT status INTO v_existing_status FROM businesses WHERE id = p_business_id;
  IF v_existing_status IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;
  IF v_existing_status <> 'soft_listed' THEN
    RAISE EXCEPTION 'This listing is no longer soft_listed (status=%) — use the regular admin shop editor', v_existing_status;
  END IF;

  IF p_mobile IS NOT NULL AND LENGTH(TRIM(p_mobile)) > 0 THEN
    v_norm_mobile := norm_indian_mobile(p_mobile);
    IF v_norm_mobile IS NULL THEN
      RAISE EXCEPTION 'Invalid mobile — must be 10-digit Indian (6/7/8/9 start)';
    END IF;
    IF EXISTS (SELECT 1 FROM businesses WHERE mobile = v_norm_mobile AND id <> p_business_id) THEN
      RAISE EXCEPTION 'Another listing already uses mobile %', v_norm_mobile;
    END IF;
  END IF;

  -- If admin moved city, cascade district + state to keep them in sync.
  IF p_city_id IS NOT NULL THEN
    SELECT c.district_id, d.state_id
      INTO v_new_district, v_new_state
      FROM geo_cities c
      JOIN geo_districts d ON d.id = c.district_id
     WHERE c.id = p_city_id
     LIMIT 1;
    IF v_new_district IS NULL THEN
      RAISE EXCEPTION 'City % has no district mapping', p_city_id;
    END IF;
  END IF;

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
         district_id  = COALESCE(v_new_district, district_id),
         state_id     = COALESCE(v_new_state, state_id),
         consent_notes = CASE WHEN p_notes IS NULL THEN consent_notes
                              WHEN TRIM(p_notes) = '' THEN NULL
                              ELSE TRIM(p_notes) END,
         updated_at   = NOW()
   WHERE id = p_business_id;

  -- Multi-category swap if requested
  IF p_category_slugs IS NOT NULL AND array_length(p_category_slugs, 1) IS NOT NULL THEN
    v_primary_slug := COALESCE(NULLIF(lower(trim(p_primary_category_slug)),''), p_category_slugs[1]);
    IF NOT (v_primary_slug = ANY(p_category_slugs)) THEN
      v_primary_slug := p_category_slugs[1];
    END IF;
    SELECT id, parent_id INTO v_primary_cat_id, v_primary_parent
      FROM categories WHERE slug = v_primary_slug AND active = TRUE LIMIT 1;
    IF v_primary_cat_id IS NULL THEN
      RAISE EXCEPTION 'Invalid primary category: %', v_primary_slug;
    END IF;

    UPDATE businesses
       SET category_id     = CASE WHEN v_primary_parent IS NOT NULL THEN v_primary_parent ELSE v_primary_cat_id END,
           sub_category_id = CASE WHEN v_primary_parent IS NOT NULL THEN v_primary_cat_id ELSE NULL END,
           updated_at      = NOW()
     WHERE id = p_business_id;

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


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/171 installed. Both soft-add RPCs now derive district_id + state_id from city.';
END $$;
