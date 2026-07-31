-- =========================================================================
-- Migration 205: Add name_hi + alt_mobile to admin_update_shop whitelist
-- Created: 2026-07-31
--
-- BUG:
--   Admin panel (admin/shop.html) can edit "Shop Name (Hindi)" and
--   "Alternative Mobile" — form fields exist and are collected — BUT the
--   admin_update_shop RPC's whitelist (from db/135) does NOT include these
--   fields, so they get silently dropped. User's Hindi name / alt mobile
--   can never be corrected from admin panel.
--
-- FIX:
--   Add 'name_hi' and 'alt_mobile' to the v_allowed whitelist array.
--   Same RPC structure as db/135, just with additional allowed fields.
--
-- SAFE TO RE-RUN.
-- =========================================================================

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
    'name','name_hi','usp_text','usp_hi','about_text',
    'mobile','whatsapp','alt_mobile','owner_name','email',
    'category_id','sub_category_id',
    'address_line1','address_line2','pincode',
    'hours_json','services_json',
    'photos','video_url',
    'verified_mobile','verified_address','verified_photo','verified_visit',
    'featured','admin_notes',
    'status',
    -- From db/68: trust-signal fields
    'payment_methods','special_features','established_year',
    -- From db/129: location reassignment
    'city_id','locality_id',
    -- From db/204: UPI ID
    'upi_id'
  ];
  v_array_cols TEXT[] := ARRAY['photos','payment_methods','special_features'];
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  v_admin_id := auth.uid();

  FOR v_key IN SELECT jsonb_object_keys(p_patch)
  LOOP
    IF v_key = ANY(v_allowed) THEN
      IF v_key = ANY(v_array_cols) THEN
        -- ARRAY COLUMNS: unpack JSON array → PG array via jsonb_array_elements_text.
        IF p_patch->v_key IS NULL OR jsonb_typeof(p_patch->v_key) = 'null' THEN
          EXECUTE format('UPDATE businesses SET %I = NULL WHERE id = $1', v_key)
            USING p_business_id;
        ELSE
          EXECUTE format(
            'UPDATE businesses SET %I = ARRAY(SELECT jsonb_array_elements_text($1->%L)) WHERE id = $2',
            v_key, v_key
          ) USING p_patch, p_business_id;
        END IF;
      ELSIF v_key IN ('hours_json','services_json') THEN
        EXECUTE format('UPDATE businesses SET %I = $1 WHERE id = $2', v_key)
          USING p_patch->v_key, p_business_id;
      ELSIF v_key = 'established_year' THEN
        IF p_patch->v_key IS NULL OR jsonb_typeof(p_patch->v_key) = 'null' THEN
          UPDATE businesses SET established_year = NULL WHERE id = p_business_id;
        ELSE
          UPDATE businesses SET established_year = (p_patch->>v_key)::INT WHERE id = p_business_id;
        END IF;
      ELSIF v_key IN ('verified_mobile','verified_address','verified_photo','verified_visit','featured') THEN
        EXECUTE format('UPDATE businesses SET %I = ($1)::BOOLEAN WHERE id = $2', v_key)
          USING (p_patch->>v_key)::TEXT, p_business_id;
      ELSIF v_key IN ('category_id','sub_category_id','city_id','locality_id') THEN
        IF p_patch->v_key IS NULL OR jsonb_typeof(p_patch->v_key) = 'null' OR (p_patch->>v_key) = '' THEN
          EXECUTE format('UPDATE businesses SET %I = NULL WHERE id = $1', v_key)
            USING p_business_id;
        ELSE
          EXECUTE format('UPDATE businesses SET %I = ($1)::UUID WHERE id = $2', v_key)
            USING p_patch->>v_key, p_business_id;
        END IF;
      ELSE
        -- Plain TEXT columns
        EXECUTE format('UPDATE businesses SET %I = NULLIF(TRIM($1), '''') WHERE id = $2', v_key)
          USING (p_patch->>v_key), p_business_id;
      END IF;

      v_changed := v_changed || to_jsonb(v_key);
    END IF;
  END LOOP;

  UPDATE businesses SET updated_at = NOW() WHERE id = p_business_id;

  -- Audit log (best-effort; failures don't block save)
  BEGIN
    INSERT INTO admin_audit_log (admin_id, action, target_id, target_type, meta)
    VALUES (v_admin_id, 'admin_update_shop', p_business_id, 'business',
            jsonb_build_object('fields_updated', v_changed, 'patch_keys', jsonb_object_keys(p_patch)));
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object('ok', true, 'fields_updated', v_changed);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_update_shop(UUID, JSONB) TO authenticated;

COMMIT;

DO $$
BEGIN
  RAISE NOTICE '✓ db/205 — admin_update_shop now accepts name_hi + alt_mobile + upi_id';
END $$;
