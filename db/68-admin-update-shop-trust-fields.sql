-- =====================================================
-- db/68-admin-update-shop-trust-fields.sql
-- =====================================================
-- USER BUG: 'Payment Mode Tick karne ke baad... Save karne ke baad tick
-- rehna chahiye, lekin wo disappear ho jaata hai'
--
-- ROOT CAUSE: The admin_update_shop() RPC (from db/27) has a whitelist
-- of allowed columns. payment_methods, special_features, established_year
-- were added later in db/41 but never added to that whitelist.
-- → Save silently DROPS those fields. UI shows empty after reload.
--
-- THIS SQL adds the 3 missing fields to the whitelist with proper types:
--   • payment_methods   TEXT[]
--   • special_features  TEXT[]
--   • established_year  INT
--
-- Idempotent: just replaces the function definition.
-- ZERO RISK — pure RPC swap.
-- =====================================================

BEGIN;

DROP FUNCTION IF EXISTS admin_update_shop(UUID, JSONB);

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
    -- NEW: trust-signal fields (from db/41)
    'payment_methods','special_features','established_year'
  ];
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  v_admin_id := auth.uid();

  FOR v_key IN SELECT jsonb_object_keys(p_patch)
  LOOP
    IF v_key = ANY(v_allowed) THEN
      -- TEXT[] arrays need special handling — jsonb array → text[]
      IF v_key IN ('payment_methods','special_features') THEN
        EXECUTE format(
          'UPDATE businesses SET %I = ARRAY(SELECT jsonb_array_elements_text($1->%L)), updated_at = NOW() WHERE id = $2',
          v_key, v_key
        ) USING p_patch, p_business_id;
      ELSIF v_key = 'photos' THEN
        EXECUTE format(
          'UPDATE businesses SET %I = ARRAY(SELECT jsonb_array_elements_text($1->%L)), updated_at = NOW() WHERE id = $2',
          v_key, v_key
        ) USING p_patch, p_business_id;
      ELSIF v_key = 'established_year' THEN
        -- Allow explicit NULL to clear
        IF p_patch ? 'established_year' AND p_patch->'established_year' = 'null'::jsonb THEN
          UPDATE businesses SET established_year = NULL, updated_at = NOW() WHERE id = p_business_id;
        ELSE
          EXECUTE format(
            'UPDATE businesses SET %I = ($1->>%L)::INT, updated_at = NOW() WHERE id = $2',
            v_key, v_key
          ) USING p_patch, p_business_id;
        END IF;
      ELSE
        EXECUTE format(
          'UPDATE businesses SET %I = ($1->>%L)::%s, updated_at = NOW() WHERE id = $2',
          v_key, v_key,
          CASE
            WHEN v_key IN ('category_id','sub_category_id') THEN 'INT'
            WHEN v_key IN ('verified_mobile','verified_address','verified_photo','verified_visit','featured') THEN 'BOOLEAN'
            WHEN v_key IN ('hours_json','services_json') THEN 'JSONB'
            ELSE 'TEXT'
          END
        ) USING p_patch, p_business_id;
      END IF;
      v_changed := v_changed || to_jsonb(v_key);
    END IF;
  END LOOP;

  -- Audit log
  BEGIN
    INSERT INTO admin_audit_log(admin_id, action, business_id, details)
    VALUES (v_admin_id, 'shop_update', p_business_id,
            jsonb_build_object('changed', v_changed, 'patch', p_patch));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', TRUE, 'changed', v_changed);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_update_shop(UUID, JSONB) TO authenticated;


-- Also ensure admin_get_shop_full returns these fields (in case schema drift)
-- We do NOT replace admin_get_shop_full here because db/26 already returns
-- the full row via to_jsonb(b.*). The fields will flow through automatically.

NOTIFY pgrst, 'reload schema';

DO $$
DECLARE v_n INT;
BEGIN
  SELECT COUNT(*) INTO v_n FROM pg_proc
   WHERE proname = 'admin_update_shop';
  RAISE NOTICE '✓ admin_update_shop updated (% definition)', v_n;
END $$;

COMMIT;
