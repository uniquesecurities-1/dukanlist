-- ============================================================
-- db/129 — Add city_id + locality_id to admin_update_shop whitelist
-- ============================================================
-- Problem: admin/shop.html had no way to change a shop's city or locality
-- assignment because the admin_update_shop RPC silently dropped these
-- fields from its allowed list. Goyal Saree Emporium was registered as
-- Sirsa but actually located in Mandi Dabwali — admin had no fix path.
--
-- This patch adds 'city_id' and 'locality_id' to the v_allowed array.
--
-- IDEMPOTENT: replaces function. Existing grants preserved by re-grant.
-- DB never disturbed: forward-only migration.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION admin_update_shop(p_business_id UUID, p_patch JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id  UUID;
  v_changed   JSONB := '[]'::jsonb;
  v_key       TEXT;
  v_allowed   TEXT[] := ARRAY[
    'name','usp_text','usp_hi','about_text',
    'mobile','whatsapp','owner_name',
    'category_id','sub_category_id',
    'address_line1','address_line2','pincode',
    'hours_json','services_json',
    'photos','video_url',
    'verified_mobile','verified_address','verified_photo','verified_visit',
    'featured','admin_notes',
    'status',
    -- From db/68: trust-signal fields
    'payment_methods','special_features','established_year',
    -- NEW from db/129: location reassignment
    'city_id','locality_id'
  ];
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  v_admin_id := auth.uid();

  FOR v_key IN SELECT jsonb_object_keys(p_patch)
  LOOP
    IF v_key = ANY(v_allowed) THEN
      EXECUTE format('UPDATE businesses SET %I = ($1->>%L)::text::%s WHERE id = $2',
                     v_key, v_key,
                     CASE
                       -- Integer columns
                       WHEN v_key IN ('category_id','sub_category_id','city_id','locality_id','established_year') THEN 'INTEGER'
                       -- Boolean columns
                       WHEN v_key LIKE 'verified_%' OR v_key = 'featured' THEN 'BOOLEAN'
                       -- JSONB columns
                       WHEN v_key LIKE '%_json' THEN 'JSONB'
                       -- Array columns
                       WHEN v_key IN ('photos','payment_methods','special_features') THEN 'TEXT[]'
                       ELSE 'TEXT'
                     END)
        USING p_patch, p_business_id;
      v_changed := v_changed || jsonb_build_array(v_key);
    END IF;
  END LOOP;

  -- Touch updated_at
  UPDATE businesses SET updated_at = NOW() WHERE id = p_business_id;

  RETURN jsonb_build_object('updated_fields', v_changed);
END $$;

GRANT EXECUTE ON FUNCTION admin_update_shop(UUID, JSONB) TO authenticated;

NOTIFY pgrst, 'reload schema';

DO $$
BEGIN
  RAISE NOTICE '✓ db/129 — admin_update_shop now accepts city_id + locality_id';
END $$;

COMMIT;
