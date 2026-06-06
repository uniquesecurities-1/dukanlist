-- =====================================================
-- db/86-admin-shop-full-add-email-confirmed.sql
-- =====================================================
-- USER FEEDBACK (2026-06-01):
--   "Jiski email already verified hai uspar to Force Verify dikha raha hai...
--    Jiski verified nahi hai aur jaha iski jrurat hai waha dikha nahi raha."
--
-- FIX:
--   admin_get_shop_full() did NOT return whether the linked auth user has
--   confirmed their email. Without that info, the admin/shop.html UI has
--   no way to decide whether to show the "Force Verify Email" button.
--
--   This patch is a MINIMAL EXTENSION of db/70 - same structure, same
--   schema assumptions - but adds three new fields to the JSONB output:
--     * owner_email_confirmed    BOOLEAN  - TRUE if email_confirmed_at IS NOT NULL
--     * owner_email_confirmed_at TIMESTAMPTZ - for display
--     * verification_requested_at  TIMESTAMPTZ - for admin context
--
-- POSTGRES LIMIT FIX:
--   jsonb_build_object() accepts max 100 arguments (50 key-value pairs).
--   With 3 new fields, total was 51 pairs = 102 args, hitting the limit.
--   Solution: split into two jsonb_build_object() calls merged with the
--   || operator. Result is identical to client.
--
-- IDEMPOTENT - safe to re-run. Replaces db/70 + db/27 + db/26 successors.
-- =====================================================

BEGIN;

DROP FUNCTION IF EXISTS admin_get_shop_full(UUID);

CREATE OR REPLACE FUNCTION admin_get_shop_full(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_row           businesses%ROWTYPE;
  v_owner_uid     UUID;
  v_login_email   TEXT;
  v_email_conf_at TIMESTAMPTZ;
  v_cat           JSONB;
  v_city          JSONB;
  v_loc           JSONB;
  v_city_name     TEXT;
  v_state_code    TEXT;
  v_lead7         INT := 0;
  v_lead30        INT := 0;
  v_rev           INT := 0;
  v_flags         INT := 0;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT * INTO v_row FROM businesses WHERE id = p_business_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'shop not found';
  END IF;

  -- Owner: from business_owners join to auth.users
  SELECT bo.auth_user_id, au.email, au.email_confirmed_at
    INTO v_owner_uid, v_login_email, v_email_conf_at
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
    'name', COALESCE(v_city_name, '-'),
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

  -- Split into TWO jsonb_build_object calls merged with || (50 pairs max each).
  -- First half: 25 pairs (50 args)
  -- Second half: 26 pairs (52 args)
  RETURN
    jsonb_build_object(
      'id',                v_row.id,
      'slug',              v_row.slug,
      'name',              v_row.name,
      'status',            v_row.status,
      'featured',          COALESCE(v_row.featured, FALSE),
      'owner_name',        v_row.owner_name,
      'owner_email',       v_login_email,
      'owner_email_confirmed',    (v_email_conf_at IS NOT NULL),
      'owner_email_confirmed_at', v_email_conf_at,
      'shop_email',        v_row.email,
      'email',             v_row.email,
      'owner_user_id',     v_owner_uid,
      'mobile',            v_row.mobile,
      'whatsapp',          v_row.whatsapp,
      'category',          v_cat,
      'category_id',       v_row.category_id,
      'sub_category_id',   v_row.sub_category_id,
      'city',              v_city,
      'locality',          v_loc,
      'pincode',           v_row.pincode,
      'address_line1',     v_row.address_line1,
      'address_line2',     v_row.address_line2,
      'lat',               v_row.lat,
      'lng',               v_row.lng,
      'usp_text',          v_row.usp_text
    )
    ||
    jsonb_build_object(
      'usp_hi',            v_row.usp_hi,
      'about_text',        v_row.about_text,
      'hours_json',        v_row.hours_json,
      'photos',            v_row.photos,
      'video_url',         v_row.video_url,
      'services_json',     v_row.services_json,
      'established_year',  v_row.established_year,
      'payment_methods',   v_row.payment_methods,
      'special_features',  v_row.special_features,
      'verified_mobile',   COALESCE(v_row.verified_mobile,  FALSE),
      'verified_address',  COALESCE(v_row.verified_address, FALSE),
      'verified_photo',    COALESCE(v_row.verified_photo,   FALSE),
      'verified_visit',    COALESCE(v_row.verified_visit,   FALSE),
      'verified_score',    COALESCE(v_row.verified_score,   0),
      'verification_requested_at', v_row.verification_requested_at,
      'rating_avg',        COALESCE(v_row.rating_avg, 0),
      'rating_count',      COALESCE(v_row.rating_count, 0),
      'view_count',        COALESCE(v_row.view_count, 0),
      'lead_count',        COALESCE(v_row.lead_count, 0),
      'leads_7d',          v_lead7,
      'leads_30d',         v_lead30,
      'reviews_total',     v_rev,
      'flags_pending',     v_flags,
      'admin_notes',       v_row.admin_notes,
      'created_at',        v_row.created_at,
      'updated_at',        v_row.updated_at
    );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_get_shop_full(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
DECLARE v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count FROM pg_proc WHERE proname = 'admin_get_shop_full';
  RAISE NOTICE 'admin_get_shop_full installed: % (split jsonb_build_object to bypass 100-arg limit)', v_count;
END $$;
