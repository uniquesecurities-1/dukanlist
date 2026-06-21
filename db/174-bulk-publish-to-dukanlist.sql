-- ============================================================
-- db/174 — Bulk admin publish to MAIN DukanList (not just Golden Pages)
-- ============================================================
-- USER STRATEGIC PIVOT:
--   "Without email verify listing open kar dete hai aur hundreds of
--    business hm khud register kar denge... limited data ke sath, but
--    jab tak email verify nahi hogi tab tak user ka account login nahi
--    hoga. Email daalne ke liye wo hamse contact karega — taki fake
--    registration na ho."
--
--   Translation: admin bulk-publishes accountless listings to MAIN
--   DukanList. Owner has no login until they contact admin to add an
--   email + verify. This solves the supply-density problem (JustDial /
--   Google Maps model) while still preventing fake registrations.
--
-- CHANGE:
--   Both admin_soft_add_shop + admin_soft_bulk_add now accept a
--   p_target_status parameter ('soft_listed' or 'active').
--   - 'soft_listed' → lives ONLY on /golden-pages.html (current default)
--   - 'active'      → lives on MAIN DukanList (search, browse, etc.)
--
-- Listings created with target='active' have:
--   - owner_id = NULL (no account yet)
--   - claim_token set (for WhatsApp claim flow)
--   - claim_status = 'unclaimed'
--   - consent_method = 'admin-bulk-published'
--
-- When owner contacts admin to claim, admin can later add their email
-- via a follow-up RPC (db/175 will handle account creation + email
-- verification flow).
-- ============================================================

BEGIN;

-- ============================================================
-- PART 1: admin_soft_add_shop (single add) — add p_target_status
-- ============================================================

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
  p_notes                 TEXT DEFAULT NULL,
  p_target_status         TEXT DEFAULT 'soft_listed'  -- NEW: 'soft_listed' | 'active'
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
  v_pincode          TEXT;
  v_primary_slug     TEXT;
  v_primary_cat_id   INT;
  v_primary_parent   INT;
  v_primary_is_sub   BOOLEAN := FALSE;
  v_n_slugs          INT;
  v_slug_iter        TEXT;
  v_cat_id_iter      INT;
  v_clean_owner      TEXT;
  v_consent_method   TEXT;
  v_target           TEXT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  SELECT email INTO v_admin_email FROM admin_users WHERE auth_user_id = auth.uid();

  -- Target status validation
  v_target := COALESCE(LOWER(TRIM(p_target_status)), 'soft_listed');
  IF v_target NOT IN ('soft_listed', 'active') THEN
    RAISE EXCEPTION 'Invalid target status: % (use soft_listed or active)', v_target;
  END IF;

  IF p_name IS NULL OR LENGTH(TRIM(p_name)) < 2 THEN
    RAISE EXCEPTION 'Name required (min 2 chars)';
  END IF;

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

  IF p_mobile IS NOT NULL AND LENGTH(TRIM(p_mobile)) > 0 THEN
    v_norm_mobile := norm_indian_mobile(p_mobile);
    IF v_norm_mobile IS NULL THEN
      RAISE EXCEPTION 'If providing mobile, it must be a valid 10-digit Indian number';
    END IF;
    IF EXISTS (SELECT 1 FROM businesses WHERE mobile = v_norm_mobile) THEN
      RAISE EXCEPTION 'A listing with mobile % already exists', v_norm_mobile;
    END IF;
  END IF;

  v_city_id := COALESCE(
    p_city_id,
    (SELECT id FROM geo_cities WHERE name ILIKE 'mandi dabwali' AND active LIMIT 1),
    (SELECT id FROM geo_cities WHERE active LIMIT 1)
  );

  IF v_city_id IS NULL THEN
    RAISE EXCEPTION 'No active city available in geo_cities';
  END IF;

  SELECT c.district_id, d.state_id, COALESCE(c.pincodes[1], '000000')
    INTO v_district_id, v_state_id, v_pincode
    FROM geo_cities c
    JOIN geo_districts d ON d.id = c.district_id
   WHERE c.id = v_city_id
   LIMIT 1;

  IF v_district_id IS NULL THEN
    RAISE EXCEPTION 'City % has no district mapping', v_city_id;
  END IF;

  v_clean_owner := NULLIF(TRIM(COALESCE(p_owner_name, '')), '');

  v_slug  := generate_unique_slug(TRIM(p_name) || COALESCE(' ' || TRIM(p_area), ''));
  v_token := encode(extensions.gen_random_bytes(20), 'hex');

  -- Different consent_method per target so audits can tell them apart
  v_consent_method := CASE
    WHEN v_target = 'active' THEN 'admin-bulk-published'
    ELSE 'public-data'
  END;

  INSERT INTO businesses (
    slug, name, name_hi, owner_name, mobile, whatsapp,
    category_id, sub_category_id,
    city_id, district_id, state_id, pincode,
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
    v_city_id, v_district_id, v_state_id, v_pincode,
    COALESCE(NULLIF(TRIM(p_area), ''), ''),
    v_target,                                  -- 'soft_listed' OR 'active'
    'unclaimed',
    COALESCE(v_admin_email, p_source), NOW(),
    v_consent_method, p_notes,
    v_token,
    NOW(), NOW()
  )
  RETURNING id INTO v_business_id;

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
    'status',            v_target,
    'claim_token',       v_token,
    'public_url',        CASE
                           WHEN v_target = 'active'
                             THEN 'https://dukanlist.com/shop/' || v_slug
                           ELSE 'https://dukanlist.com/golden-pages.html#shop=' || v_slug
                         END,
    'claim_url',         'https://dukanlist.com/claim.html?token=' || v_token,
    'categories_linked', p_category_slugs,
    'primary_category',  v_primary_slug,
    'city_id',           v_city_id,
    'district_id',       v_district_id,
    'pincode',           v_pincode,
    'owner_name',        v_clean_owner
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_soft_add_shop(TEXT, TEXT[], TEXT, TEXT, TEXT, INT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;


-- ============================================================
-- PART 2: admin_soft_bulk_add (paste N names) — add p_target_status
-- ============================================================

CREATE OR REPLACE FUNCTION admin_soft_bulk_add(
  p_names          TEXT[],
  p_category_slug  TEXT,
  p_area           TEXT DEFAULT NULL,
  p_city_id        INT  DEFAULT NULL,
  p_source         TEXT DEFAULT 'bulk-reference',
  p_target_status  TEXT DEFAULT 'soft_listed'  -- NEW
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_admin_email    TEXT;
  v_category_id    INT;
  v_city_id        INT;
  v_district_id    INT;
  v_state_id       SMALLINT;
  v_pincode        TEXT;
  v_name           TEXT;
  v_clean_name     TEXT;
  v_slug           TEXT;
  v_token          TEXT;
  v_business_id    UUID;
  v_added          INT := 0;
  v_skipped        INT := 0;
  v_added_list     JSONB := '[]'::jsonb;
  v_skipped_list   JSONB := '[]'::jsonb;
  v_consent_method TEXT;
  v_target         TEXT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  SELECT email INTO v_admin_email FROM admin_users WHERE auth_user_id = auth.uid();

  v_target := COALESCE(LOWER(TRIM(p_target_status)), 'soft_listed');
  IF v_target NOT IN ('soft_listed', 'active') THEN
    RAISE EXCEPTION 'Invalid target status: %', v_target;
  END IF;

  v_consent_method := CASE
    WHEN v_target = 'active' THEN 'admin-bulk-published'
    ELSE 'public-data'
  END;

  IF p_names IS NULL OR array_length(p_names, 1) IS NULL OR array_length(p_names, 1) < 1 THEN
    RAISE EXCEPTION 'Provide at least 1 name';
  END IF;
  IF array_length(p_names, 1) > 500 THEN
    RAISE EXCEPTION 'Max 500 names per batch';
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
    RAISE EXCEPTION 'No active city available';
  END IF;

  SELECT c.district_id, d.state_id, COALESCE(c.pincodes[1], '000000')
    INTO v_district_id, v_state_id, v_pincode
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
        city_id, district_id, state_id, pincode,
        address_line1,
        status, claim_status,
        pre_listed_by, pre_listed_at,
        consent_method,
        claim_token,
        created_at, updated_at
      ) VALUES (
        v_slug, v_clean_name,
        v_category_id,
        v_city_id, v_district_id, v_state_id, v_pincode,
        COALESCE(NULLIF(TRIM(p_area), ''), ''),
        v_target, 'unclaimed',                  -- 'soft_listed' OR 'active'
        COALESCE(v_admin_email, p_source), NOW(),
        v_consent_method,
        v_token,
        NOW(), NOW()
      )
      RETURNING id INTO v_business_id;

      INSERT INTO business_categories (business_id, category_id, is_primary)
      VALUES (v_business_id, v_category_id, TRUE)
      ON CONFLICT DO NOTHING;

      v_added := v_added + 1;
      v_added_list := v_added_list || jsonb_build_object(
        'name', v_clean_name, 'slug', v_slug, 'business_id', v_business_id
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
    'added', v_added, 'skipped', v_skipped,
    'target_status', v_target,
    'added_list', v_added_list, 'skipped_list', v_skipped_list
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_soft_bulk_add(TEXT[], TEXT, TEXT, INT, TEXT, TEXT) TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/174 installed. Admin can now bulk-publish to MAIN DukanList (target=active) or Golden Pages (target=soft_listed).';
END $$;
