-- =========================================================================
-- Migration 193: FIX for db/192 — array append syntax error
-- Created: 2026-07-15
--
-- BUG in db/192:
--   `v_fields_updated || 'whatsapp'` was interpreted by PostgreSQL as
--   an array-to-array concat, causing:
--     ERROR: malformed array literal: "whatsapp"
--
-- FIX:
--   Use ARRAY_APPEND(...) explicitly OR cast '||' operand to TEXT[]:
--     v_fields_updated || ARRAY['whatsapp']::TEXT[]
--
-- This migration replaces the RPC with the CORRECT array-append syntax.
-- SAFE TO RE-RUN.
-- =========================================================================

BEGIN;

DROP FUNCTION IF EXISTS update_my_business(JSONB);

CREATE OR REPLACE FUNCTION update_my_business(p_patch JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id        UUID := auth.uid();
  v_business_id    UUID;
  v_old            businesses%ROWTYPE;
  v_fields_updated TEXT[] := ARRAY[]::TEXT[];
  v_new_val        TEXT;
  v_old_val        TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'login required';
  END IF;

  SELECT bo.business_id INTO v_business_id
    FROM business_owners bo
   WHERE bo.auth_user_id = v_user_id
   LIMIT 1;

  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'no business linked to this account';
  END IF;

  SELECT * INTO v_old FROM businesses WHERE id = v_business_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'business not found';
  END IF;

  -- ===== WHATSAPP (newly editable) =====
  IF p_patch ? 'whatsapp' THEN
    v_new_val := NULLIF(trim(p_patch->>'whatsapp'), '');
    v_old_val := v_old.whatsapp;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old_val,'') THEN
      v_new_val := regexp_replace(v_new_val, '\D', '', 'g');
      IF v_new_val IS NOT NULL AND length(v_new_val) NOT IN (10, 12) THEN
        RAISE EXCEPTION 'WhatsApp number must be 10 digits';
      END IF;
      IF v_new_val IS NOT NULL AND length(v_new_val) = 12 THEN
        v_new_val := substring(v_new_val FROM 3);
      END IF;
      UPDATE businesses SET whatsapp = v_new_val WHERE id = v_business_id;
      v_fields_updated := ARRAY_APPEND(v_fields_updated, 'whatsapp');
    END IF;
  END IF;

  IF p_patch ? 'owner_name' THEN
    v_new_val := NULLIF(trim(p_patch->>'owner_name'), '');
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old.owner_name,'') THEN
      UPDATE businesses SET owner_name = v_new_val WHERE id = v_business_id;
      v_fields_updated := ARRAY_APPEND(v_fields_updated, 'owner_name');
    END IF;
  END IF;

  IF p_patch ? 'name_hi' THEN
    v_new_val := NULLIF(trim(p_patch->>'name_hi'), '');
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old.name_hi,'') THEN
      UPDATE businesses SET name_hi = v_new_val WHERE id = v_business_id;
      v_fields_updated := ARRAY_APPEND(v_fields_updated, 'name_hi');
    END IF;
  END IF;

  IF p_patch ? 'usp_text' THEN
    v_new_val := NULLIF(trim(p_patch->>'usp_text'), '');
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old.usp_text,'') THEN
      UPDATE businesses SET usp_text = v_new_val WHERE id = v_business_id;
      v_fields_updated := ARRAY_APPEND(v_fields_updated, 'usp_text');
    END IF;
  END IF;

  IF p_patch ? 'usp_hi' THEN
    v_new_val := NULLIF(trim(p_patch->>'usp_hi'), '');
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old.usp_hi,'') THEN
      UPDATE businesses SET usp_hi = v_new_val WHERE id = v_business_id;
      v_fields_updated := ARRAY_APPEND(v_fields_updated, 'usp_hi');
    END IF;
  END IF;

  IF p_patch ? 'about_text' THEN
    v_new_val := NULLIF(trim(p_patch->>'about_text'), '');
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old.about_text,'') THEN
      UPDATE businesses SET about_text = v_new_val WHERE id = v_business_id;
      v_fields_updated := ARRAY_APPEND(v_fields_updated, 'about_text');
    END IF;
  END IF;

  IF p_patch ? 'hours_json' THEN
    UPDATE businesses SET hours_json = p_patch->'hours_json' WHERE id = v_business_id;
    v_fields_updated := ARRAY_APPEND(v_fields_updated, 'hours_json');
  END IF;

  IF p_patch ? 'services_json' THEN
    UPDATE businesses SET services_json = p_patch->'services_json' WHERE id = v_business_id;
    v_fields_updated := ARRAY_APPEND(v_fields_updated, 'services_json');
  END IF;

  IF p_patch ? 'faqs_json' THEN
    UPDATE businesses SET faqs_json = p_patch->'faqs_json' WHERE id = v_business_id;
    v_fields_updated := ARRAY_APPEND(v_fields_updated, 'faqs_json');
  END IF;

  IF p_patch ? 'established_year' THEN
    v_new_val := NULLIF(trim(p_patch->>'established_year'), '');
    IF v_new_val IS NULL THEN
      UPDATE businesses SET established_year = NULL WHERE id = v_business_id;
    ELSE
      UPDATE businesses SET established_year = v_new_val::INT WHERE id = v_business_id;
    END IF;
    v_fields_updated := ARRAY_APPEND(v_fields_updated, 'established_year');
  END IF;

  IF p_patch ? 'payment_methods' THEN
    UPDATE businesses SET payment_methods = ARRAY(SELECT jsonb_array_elements_text(p_patch->'payment_methods'))
      WHERE id = v_business_id;
    v_fields_updated := ARRAY_APPEND(v_fields_updated, 'payment_methods');
  END IF;

  IF p_patch ? 'special_features' THEN
    UPDATE businesses SET special_features = ARRAY(SELECT jsonb_array_elements_text(p_patch->'special_features'))
      WHERE id = v_business_id;
    v_fields_updated := ARRAY_APPEND(v_fields_updated, 'special_features');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'status', 'active',
    'fields_updated', to_jsonb(v_fields_updated),
    'pending_fields', to_jsonb(ARRAY[]::TEXT[]),
    'violations', '[]'::jsonb
  );
END;
$$;

GRANT EXECUTE ON FUNCTION update_my_business(JSONB) TO authenticated;

COMMIT;
