-- =====================================================
-- 12-admin-create-business.sql
-- Admin power tool — create businesses directly without OTP
-- =====================================================
-- For manual onboarding phase: admin (Deepak/Navneet) visits
-- shopkeepers in Mandi Dabwali, collects info, adds via admin panel.
-- Bypasses OTP requirement since admin is already authenticated.
-- =====================================================

CREATE OR REPLACE FUNCTION admin_create_business(
  p_category_ids        INT[],
  p_primary_category_id INT,
  p_name                TEXT,
  p_name_hi             TEXT,
  p_owner_name          TEXT,
  p_mobile              TEXT,
  p_whatsapp            TEXT,
  p_email               TEXT,
  p_address_line1       TEXT,
  p_address_line2       TEXT,
  p_locality_id         INT,
  p_city_id             INT,
  p_district_id         INT,
  p_state_id            SMALLINT,
  p_pincode             TEXT,
  p_usp_text            TEXT,
  p_usp_hi              TEXT,
  p_status              TEXT DEFAULT 'active'
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_user_id     UUID;
  v_city_name         TEXT;
  v_slug              TEXT;
  v_biz_id            UUID;
  v_pincode_ok        BOOLEAN;
  v_cat_id            INT;
  v_primary_parent_id INT;
  v_n_cats            INT;
  v_invalid_count     INT;
BEGIN
  -- Admin gate
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;
  v_admin_user_id := auth.uid();

  -- Validate status
  IF p_status NOT IN ('pending','active','flagged','banned','self_hidden') THEN
    RAISE EXCEPTION 'Invalid status: %', p_status;
  END IF;

  -- Validate categories
  v_n_cats := COALESCE(array_length(p_category_ids, 1), 0);
  IF v_n_cats < 1 THEN
    RAISE EXCEPTION 'At least 1 category required';
  END IF;
  IF v_n_cats > 5 THEN
    RAISE EXCEPTION 'Maximum 5 categories allowed';
  END IF;
  IF NOT (p_primary_category_id = ANY(p_category_ids)) THEN
    RAISE EXCEPTION 'Primary category must be one of the selected categories';
  END IF;

  -- All categories must exist and be active
  SELECT COUNT(*) INTO v_invalid_count
  FROM unnest(p_category_ids) AS cid
  WHERE NOT EXISTS (SELECT 1 FROM categories WHERE id = cid AND active = TRUE);
  IF v_invalid_count > 0 THEN
    RAISE EXCEPTION 'One or more category IDs are invalid or inactive';
  END IF;

  -- Pincode-city validation (warning only, admin can override)
  SELECT validate_pincode_city(p_pincode, p_city_id) INTO v_pincode_ok;

  -- Get primary's parent
  SELECT parent_id INTO v_primary_parent_id
  FROM categories WHERE id = p_primary_category_id;

  -- Generate slug
  SELECT name INTO v_city_name FROM geo_cities WHERE id = p_city_id;
  v_slug := generate_business_slug(p_name, v_city_name);

  -- Insert business
  INSERT INTO businesses (
    slug,
    category_id,
    sub_category_id,
    name, name_hi, owner_name,
    mobile, whatsapp, email,
    address_line1, address_line2,
    locality_id, city_id, district_id, state_id, pincode,
    usp_text, usp_hi,
    status,
    verified_mobile,
    verified_address,
    notes_internal
  ) VALUES (
    v_slug,
    COALESCE(v_primary_parent_id, p_primary_category_id),
    CASE WHEN v_primary_parent_id IS NOT NULL THEN p_primary_category_id ELSE NULL END,
    p_name, p_name_hi, p_owner_name,
    p_mobile, COALESCE(NULLIF(p_whatsapp,''), p_mobile), p_email,
    p_address_line1, p_address_line2,
    p_locality_id, p_city_id, p_district_id, p_state_id, p_pincode,
    p_usp_text, p_usp_hi,
    p_status,
    FALSE,            -- not OTP-verified (admin-added)
    v_pincode_ok,
    '[admin-created] by ' || COALESCE(
      (SELECT display_name FROM admin_users WHERE auth_user_id = v_admin_user_id),
      'admin'
    ) || ' on ' || NOW()::TEXT
  )
  RETURNING id INTO v_biz_id;

  -- Link owner = admin (placeholder, transferable later when shopkeeper claims)
  INSERT INTO business_owners (business_id, auth_user_id, role)
  VALUES (v_biz_id, v_admin_user_id, 'owner');

  -- Insert all category junctions
  FOREACH v_cat_id IN ARRAY p_category_ids LOOP
    INSERT INTO business_categories (business_id, category_id, is_primary)
    VALUES (v_biz_id, v_cat_id, v_cat_id = p_primary_category_id);
  END LOOP;

  RETURN v_biz_id;
END;
$$;


-- =====================================================
-- Bonus: admin_delete_business — clean up test data
-- =====================================================
CREATE OR REPLACE FUNCTION admin_delete_business(p_business_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  -- Cascade-deletes will handle business_categories, business_owners, reviews, etc.
  DELETE FROM businesses WHERE id = p_business_id;
END;
$$;


NOTIFY pgrst, 'reload schema';


-- =====================================================
-- VERIFY
-- =====================================================
-- SELECT proname FROM pg_proc WHERE proname IN
-- ('admin_create_business','admin_delete_business');
-- Expect 2 rows.
-- =====================================================
