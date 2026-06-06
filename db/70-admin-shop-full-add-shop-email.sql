-- =====================================================
-- db/70-admin-shop-full-add-shop-email.sql
-- =====================================================
-- USER ISSUE: 'same account but admin shows different emails.
-- client login nhi ho pa raha, pankajgarg936@yahoo.com is correct'
--
-- ROOT CAUSE: Two separate emails per shop, both surfaced in admin:
--   • businesses.email      — shop's public contact email (display only)
--   • auth.users.email      — owner's LOGIN email (via business_owners)
-- These can diverge over time. Admin/shop view only shows the auth one
-- but Recent Registrations table shows the businesses.email. Admin can't
-- tell which is which → can't fix login mismatch confidently.
--
-- THIS PATCH: admin_get_shop_full now returns:
--   • 'owner_email'  — auth.users.email (LOGIN email)   [unchanged]
--   • 'shop_email'   — businesses.email (public)        [NEW]
--   • 'email'        — same as shop_email (legacy compat) [NEW]
--
-- Zero schema change. Pure RPC swap.
-- =====================================================

BEGIN;

DROP FUNCTION IF EXISTS admin_get_shop_full(UUID);

CREATE OR REPLACE FUNCTION admin_get_shop_full(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_row         businesses%ROWTYPE;
  v_owner_uid   UUID;
  v_login_email TEXT;
  v_cat         JSONB;
  v_city        JSONB;
  v_loc         JSONB;
  v_city_name   TEXT;
  v_state_code  TEXT;
  v_lead7       INT := 0;
  v_lead30      INT := 0;
  v_rev         INT := 0;
  v_flags       INT := 0;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT * INTO v_row FROM businesses WHERE id = p_business_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'shop not found';
  END IF;

  -- Owner: from business_owners join to auth.users
  SELECT bo.auth_user_id, au.email
    INTO v_owner_uid, v_login_email
  FROM business_owners bo
  LEFT JOIN auth.users au ON au.id = bo.auth_user_id
  WHERE bo.business_id = p_business_id
  LIMIT 1;

  -- Category info
  SELECT jsonb_build_object('id', id, 'name', name, 'slug', slug, 'icon', icon)
    INTO v_cat
  FROM categories WHERE id = COALESCE(v_row.sub_category_id, v_row.category_id);

  -- City / state
  SELECT name INTO v_city_name FROM geo_cities WHERE id = v_row.city_id;
  SELECT code INTO v_state_code FROM geo_states WHERE id = v_row.state_id;
  v_city := jsonb_build_object(
    'id', v_row.city_id,
    'name', COALESCE(v_city_name, '—'),
    'state_code', COALESCE(v_state_code, '')
  );

  IF v_row.locality_id IS NOT NULL THEN
    SELECT jsonb_build_object('id', id, 'name', name)
      INTO v_loc FROM geo_localities WHERE id = v_row.locality_id;
  END IF;

  -- Counts (defensive)
  BEGIN
    SELECT COUNT(*) INTO v_lead7  FROM leads_log
      WHERE business_id = p_business_id AND created_at >= NOW() - INTERVAL '7 days';
    SELECT COUNT(*) INTO v_lead30 FROM leads_log
      WHERE business_id = p_business_id AND created_at >= NOW() - INTERVAL '30 days';
  EXCEPTION WHEN OTHERS THEN NULL; END;

  BEGIN
    SELECT COUNT(*) INTO v_rev FROM reviews WHERE business_id = p_business_id;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  BEGIN
    SELECT COUNT(*) INTO v_flags FROM flags
      WHERE business_id = p_business_id AND status = 'pending';
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object(
    'id',             v_row.id,
    'slug',           v_row.slug,
    'name',           v_row.name,
    'status',         v_row.status,
    'featured',       COALESCE(v_row.featured, FALSE),
    'owner_name',     v_row.owner_name,

    -- TWO email fields — disambiguated:
    'owner_email',    v_login_email,    -- LOGIN email (auth.users)
    'shop_email',     v_row.email,      -- public shop email (businesses.email)
    'email',          v_row.email,      -- legacy alias for shop_email

    'owner_user_id',  v_owner_uid,
    'mobile',         v_row.mobile,
    'whatsapp',       v_row.whatsapp,
    'category',       v_cat,
    'category_id',    v_row.category_id,
    'sub_category_id',v_row.sub_category_id,
    'city',           v_city,
    'locality',       v_loc,
    'pincode',        v_row.pincode,
    'address_line1',  v_row.address_line1,
    'address_line2',  v_row.address_line2,
    'lat',            v_row.lat,
    'lng',            v_row.lng,
    'usp_text',       v_row.usp_text,
    'usp_hi',         v_row.usp_hi,
    'about_text',     v_row.about_text,
    'hours_json',     v_row.hours_json,
    'photos',         v_row.photos,
    'video_url',      v_row.video_url,
    'services_json',  v_row.services_json,
    'established_year', v_row.established_year,
    'payment_methods',  v_row.payment_methods,
    'special_features', v_row.special_features,
    'verified_mobile',  COALESCE(v_row.verified_mobile,  FALSE),
    'verified_address', COALESCE(v_row.verified_address, FALSE),
    'verified_photo',   COALESCE(v_row.verified_photo,   FALSE),
    'verified_visit',   COALESCE(v_row.verified_visit,   FALSE),
    'verified_score',   COALESCE(v_row.verified_score,   0),
    'rating_avg',     COALESCE(v_row.rating_avg, 0),
    'rating_count',   COALESCE(v_row.rating_count, 0),
    'view_count',     COALESCE(v_row.view_count, 0),
    'lead_count',     COALESCE(v_row.lead_count, 0),
    'leads_7d',       v_lead7,
    'leads_30d',      v_lead30,
    'reviews_total',  v_rev,
    'flags_pending',  v_flags,
    'admin_notes',    v_row.admin_notes,
    'created_at',     v_row.created_at,
    'updated_at',     v_row.updated_at
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_get_shop_full(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
