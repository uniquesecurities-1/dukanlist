-- =====================================================
-- db/26-admin-shop-full.sql
-- Comprehensive Admin Shop View + Edit
-- =====================================================
-- Adds:
--   1. businesses.admin_notes  TEXT    — private moderator notes
--   2. businesses.featured     BOOLEAN — paid/admin-pinned boost flag
--   3. admin_get_shop_full(p_id)    — full row + owner email + counts
--   4. admin_update_shop(p_id, p_patch) — whitelisted field updater
--      (handles verification toggles, featured, admin_notes, edits)
-- =====================================================

BEGIN;

-- ---------- 1. Columns -------------------------------------------------
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS admin_notes TEXT,
  ADD COLUMN IF NOT EXISTS featured    BOOLEAN DEFAULT FALSE NOT NULL;

CREATE INDEX IF NOT EXISTS idx_businesses_featured
  ON businesses(featured) WHERE featured = TRUE;

-- ---------- 2. admin_get_shop_full -------------------------------------
DROP FUNCTION IF EXISTS admin_get_shop_full(UUID);

CREATE OR REPLACE FUNCTION admin_get_shop_full(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row    businesses%ROWTYPE;
  v_email  TEXT;
  v_cat    JSONB;
  v_city   JSONB;
  v_loc    JSONB;
  v_lead7  INT := 0;
  v_lead30 INT := 0;
  v_rev    INT := 0;
  v_flags  INT := 0;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT * INTO v_row FROM businesses WHERE id = p_business_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'shop not found';
  END IF;

  -- Owner email (from auth.users)
  IF v_row.owner_auth_user_id IS NOT NULL THEN
    SELECT email INTO v_email FROM auth.users WHERE id = v_row.owner_auth_user_id;
  END IF;

  -- Category info
  SELECT jsonb_build_object('id', id, 'name', name, 'slug', slug, 'icon', icon)
    INTO v_cat
  FROM categories WHERE id = COALESCE(v_row.sub_category_id, v_row.category_id);

  -- City + locality
  SELECT jsonb_build_object('id', id, 'name', name, 'state_code', state_code)
    INTO v_city FROM geo_cities WHERE id = v_row.city_id;
  IF v_row.locality_id IS NOT NULL THEN
    SELECT jsonb_build_object('id', id, 'name', name)
      INTO v_loc FROM geo_localities WHERE id = v_row.locality_id;
  END IF;

  -- Leads + reviews + flag counts (defensive — tables may not have data)
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
    'owner_email',    v_email,
    'owner_user_id',  v_row.owner_auth_user_id,
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
    'faqs_json',      v_row.faqs_json,
    'verified_mobile',  COALESCE(v_row.verified_mobile,  FALSE),
    'verified_address', COALESCE(v_row.verified_address, FALSE),
    'verified_photo',   COALESCE(v_row.verified_photo,   FALSE),
    'verified_visit',   COALESCE(v_row.verified_visit,   FALSE),
    'verified_score',   COALESCE(v_row.verified_score,   0),
    'rating_avg',     COALESCE(v_row.rating_avg, 0),
    'rating_count',   COALESCE(v_row.rating_count, 0),
    'view_count',     COALESCE(v_row.view_count, 0),
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


-- ---------- 3. admin_update_shop ---------------------------------------
-- Accepts a JSONB patch. Whitelisted fields only.
DROP FUNCTION IF EXISTS admin_update_shop(UUID, JSONB);

CREATE OR REPLACE FUNCTION admin_update_shop(p_business_id UUID, p_patch JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id      UUID;
  v_changed       JSONB := '[]'::jsonb;
  v_key           TEXT;
  v_allowed       TEXT[] := ARRAY[
    'name','usp_text','usp_hi','about_text',
    'mobile','whatsapp','owner_name',
    'category_id','sub_category_id',
    'address_line1','address_line2','pincode',
    'hours_json','services_json','faqs_json',
    'photos','video_url',
    'verified_mobile','verified_address','verified_photo','verified_visit',
    'featured','admin_notes',
    'status'
  ];
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  v_admin_id := auth.uid();

  -- Build dynamic UPDATE SET clauses for whitelisted keys present in patch.
  -- We use the JSONB containment approach: SET col = COALESCE(...)
  -- Simpler: iterate keys, build & execute via separate UPDATE per field.
  FOR v_key IN SELECT jsonb_object_keys(p_patch)
  LOOP
    IF v_key = ANY(v_allowed) THEN
      EXECUTE format(
        'UPDATE businesses SET %I = ($1->>%L)::%s, updated_at = NOW() WHERE id = $2',
        v_key, v_key,
        CASE
          WHEN v_key IN ('category_id','sub_category_id') THEN 'INT'
          WHEN v_key IN ('verified_mobile','verified_address','verified_photo','verified_visit','featured') THEN 'BOOLEAN'
          WHEN v_key IN ('hours_json','services_json','faqs_json','photos')                          THEN 'JSONB'
          ELSE 'TEXT'
        END
      ) USING p_patch, p_business_id;
      v_changed := v_changed || to_jsonb(v_key);
    END IF;
  END LOOP;

  -- Recompute verified_score (mobile + address + photo + visit*2)
  UPDATE businesses SET
    verified_score = COALESCE(verified_mobile::INT,0)
                   + COALESCE(verified_address::INT,0)
                   + COALESCE(verified_photo::INT,0)
                   + COALESCE(verified_visit::INT,0) * 2
    WHERE id = p_business_id;

  -- Audit log (best-effort, ignore if table missing)
  BEGIN
    INSERT INTO admin_audit_log(admin_id, action, business_id, details)
    VALUES (v_admin_id, 'shop_update', p_business_id,
            jsonb_build_object('changed', v_changed, 'patch', p_patch));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', TRUE, 'changed', v_changed);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_update_shop(UUID, JSONB) TO authenticated;


-- ---------- 4. admin_reset_owner_password ------------------------------
-- Generates a one-time recovery link (Supabase sends the email).
-- For now we just RAISE NOTICE; in practice this is done via Supabase
-- admin API from the serverless function (already supported via the
-- existing pattern). Stub left here as documentation.

COMMIT;

-- =====================================================
-- USAGE EXAMPLES
-- =====================================================
-- Get full shop:
--   SELECT admin_get_shop_full('aaeef22c-xxxx-...'::uuid);
--
-- Toggle a single verification badge:
--   SELECT admin_update_shop('aaeef22c-xxxx-...'::uuid,
--     jsonb_build_object('verified_visit', true));
--
-- Edit USP + add admin note:
--   SELECT admin_update_shop('aaeef22c-xxxx-...'::uuid,
--     jsonb_build_object(
--       'usp_text',    'Free home delivery in Mandi Dabwali',
--       'admin_notes', 'Visited 21-May-26, confirmed location.'
--     ));
--
-- Boost a shop to Featured:
--   SELECT admin_update_shop('aaeef22c-xxxx-...'::uuid,
--     jsonb_build_object('featured', true));
-- =====================================================
