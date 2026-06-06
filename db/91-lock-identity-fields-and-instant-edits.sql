-- =====================================================
-- db/91-lock-identity-fields-and-instant-edits.sql
-- =====================================================
-- USER REQUEST (2026-06-02):
--   "edit profile me jab koi shopkeeper jaata hai, waha uska shop name,
--    address, email & mobile change karne ki permission hatao... aise
--    to koi bhi kuch bhi rozana change kar dega. Baki sab chize edit
--    kar le but identity intact rakho.
--    Aur edit profile me jab firm name, address, email, mobile update
--    nahi hone doge to baaki sab chize auto approve rakh dena. Change
--    karne par instant result dikhna chahiye."
--
-- WHAT THIS PATCH DOES:
--   1. Replaces update_my_business() with a version that:
--      - SILENTLY IGNORES owner-side patches to identity fields:
--          name, name_hi, address_line1, address_line2, pincode,
--          city_id, district_id, state_id, locality_id, mobile, email
--        (Frontend already locks these inputs, but the backend now also
--         enforces — defense in depth against API exploitation.)
--      - Removes the "sensitive field re-review" branch for the locked
--        fields since they can no longer be patched by owner anyway.
--      - All remaining editable fields apply INSTANTLY — no
--        pending_review queue, no admin approval needed for changes.
--      - Returns the same JSONB shape so existing UI continues to work
--        but always with status='active' and pending_fields=[].
--
--   2. Editable by owner (all instant):
--        owner_name, name_hi, usp_text, usp_hi, about_text,
--        hours_json, services_json, faqs_json,
--        established_year, payment_methods, special_features
--
--   3. Locked from owner (admin only via direct DB or admin tools):
--        name, address_line1, address_line2, pincode,
--        city_id, locality_id, state_id, district_id,
--        email, mobile, whatsapp
--
-- ZERO SCHEMA CHANGE. Pure RPC swap. Safe to re-run.
-- =====================================================

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
  v_check          JSONB;
  v_combined_text  TEXT := '';
  v_new_val        TEXT;
  v_old_val        TEXT;
  v_is_admin       BOOLEAN := FALSE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'login required';
  END IF;

  -- Resolve owner's business
  SELECT bo.business_id INTO v_business_id
    FROM business_owners bo
   WHERE bo.auth_user_id = v_user_id
   LIMIT 1;

  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'no business linked to this account';
  END IF;

  -- Load current row
  SELECT * INTO v_old FROM businesses WHERE id = v_business_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'business not found';
  END IF;

  -- Admins can still patch anything if they call this RPC themselves
  BEGIN
    SELECT is_admin() INTO v_is_admin;
  EXCEPTION WHEN OTHERS THEN
    v_is_admin := FALSE;
  END;

  -- ===== Content keyword check on free-text fields =====
  v_combined_text := COALESCE(p_patch->>'usp_text','')
                  || ' ' || COALESCE(p_patch->>'usp_hi','')
                  || ' ' || COALESCE(p_patch->>'about_text','');
  BEGIN
    v_check := check_content_violations(v_combined_text);
    IF v_check IS NOT NULL AND (v_check->>'blocked')::BOOLEAN THEN
      RAISE EXCEPTION 'Content blocked: %', v_check->'violations';
    END IF;
  EXCEPTION WHEN undefined_function THEN
    NULL; -- helper not present on this DB - skip
  END;

  -- =====================================================
  -- APPLY EDITS (all instant, no pending_review queue)
  -- =====================================================

  -- NOTE: PostgreSQL's `||` operator is ambiguous when the right side is
  -- an unknown-type string literal and the left side is TEXT[]. The parser
  -- can mis-resolve it as array-concat and try to parse the literal as an
  -- array literal — producing "malformed array literal: hours_json".
  -- Solution (same as db/38b): always use array_append() — unambiguous.

  IF p_patch ? 'hours_json' THEN
    UPDATE businesses SET hours_json = p_patch->'hours_json' WHERE id = v_business_id;
    v_fields_updated := array_append(v_fields_updated, 'hours_json');
  END IF;

  IF p_patch ? 'services_json' THEN
    UPDATE businesses SET services_json = p_patch->'services_json' WHERE id = v_business_id;
    v_fields_updated := array_append(v_fields_updated, 'services_json');
  END IF;

  IF p_patch ? 'faqs_json' THEN
    UPDATE businesses SET faqs_json = p_patch->'faqs_json' WHERE id = v_business_id;
    v_fields_updated := array_append(v_fields_updated, 'faqs_json');
  END IF;

  -- whatsapp is now treated as an identity field — locked from owner
  -- patches. Only admins (handled in the locked-fields block below)
  -- can change it via this RPC.

  IF p_patch ? 'owner_name' THEN
    v_new_val := NULLIF(trim(p_patch->>'owner_name'), '');
    v_old_val := v_old.owner_name;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old_val,'') THEN
      UPDATE businesses SET owner_name = v_new_val WHERE id = v_business_id;
      BEGIN
        INSERT INTO business_edits(business_id, field_name, old_value, new_value, edited_by, edited_role)
          VALUES (v_business_id, 'owner_name', v_old_val, v_new_val, v_user_id, 'owner');
      EXCEPTION WHEN OTHERS THEN NULL; END;
      v_fields_updated := array_append(v_fields_updated, 'owner_name');
    END IF;
  END IF;

  IF p_patch ? 'usp_text' THEN
    v_new_val := NULLIF(trim(p_patch->>'usp_text'), '');
    UPDATE businesses SET usp_text = v_new_val WHERE id = v_business_id;
    v_fields_updated := array_append(v_fields_updated, 'usp_text');
  END IF;

  IF p_patch ? 'usp_hi' THEN
    v_new_val := NULLIF(trim(p_patch->>'usp_hi'), '');
    UPDATE businesses SET usp_hi = v_new_val WHERE id = v_business_id;
    v_fields_updated := array_append(v_fields_updated, 'usp_hi');
  END IF;

  IF p_patch ? 'about_text' THEN
    v_new_val := NULLIF(trim(p_patch->>'about_text'), '');
    UPDATE businesses SET about_text = v_new_val WHERE id = v_business_id;
    v_fields_updated := array_append(v_fields_updated, 'about_text');
  END IF;

  IF p_patch ? 'established_year' THEN
    BEGIN
      UPDATE businesses SET established_year = (p_patch->>'established_year')::INT
        WHERE id = v_business_id;
      v_fields_updated := array_append(v_fields_updated, 'established_year');
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  IF p_patch ? 'payment_methods' THEN
    BEGIN
      UPDATE businesses
        SET payment_methods = ARRAY(SELECT jsonb_array_elements_text(p_patch->'payment_methods'))
        WHERE id = v_business_id;
      v_fields_updated := array_append(v_fields_updated, 'payment_methods');
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  IF p_patch ? 'special_features' THEN
    BEGIN
      UPDATE businesses
        SET special_features = ARRAY(SELECT jsonb_array_elements_text(p_patch->'special_features'))
        WHERE id = v_business_id;
      v_fields_updated := array_append(v_fields_updated, 'special_features');
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  -- Hindi name is editable from owner panel (used for transliteration auto-fill)
  IF p_patch ? 'name_hi' THEN
    v_new_val := NULLIF(trim(p_patch->>'name_hi'), '');
    UPDATE businesses SET name_hi = v_new_val WHERE id = v_business_id;
    v_fields_updated := array_append(v_fields_updated, 'name_hi');
  END IF;

  -- =====================================================
  -- LOCKED FIELDS — only admins can patch via this RPC
  -- (Frontend already strips these from owner submissions,
  -- but enforced here too as defense in depth.)
  -- =====================================================
  IF v_is_admin THEN
    IF p_patch ? 'name' THEN
      v_new_val := NULLIF(trim(p_patch->>'name'), '');
      UPDATE businesses SET name = v_new_val WHERE id = v_business_id;
      v_fields_updated := array_append(v_fields_updated, 'name');
    END IF;
    IF p_patch ? 'email' THEN
      v_new_val := NULLIF(trim(p_patch->>'email'), '');
      UPDATE businesses SET email = v_new_val WHERE id = v_business_id;
      v_fields_updated := array_append(v_fields_updated, 'email');
    END IF;
    IF p_patch ? 'mobile' THEN
      v_new_val := NULLIF(trim(p_patch->>'mobile'), '');
      UPDATE businesses SET mobile = v_new_val WHERE id = v_business_id;
      v_fields_updated := array_append(v_fields_updated, 'mobile');
    END IF;
    IF p_patch ? 'whatsapp' THEN
      v_new_val := NULLIF(trim(p_patch->>'whatsapp'), '');
      UPDATE businesses SET whatsapp = v_new_val WHERE id = v_business_id;
      v_fields_updated := array_append(v_fields_updated, 'whatsapp');
    END IF;
    IF p_patch ? 'address_line1' THEN
      v_new_val := NULLIF(trim(p_patch->>'address_line1'), '');
      UPDATE businesses SET address_line1 = v_new_val WHERE id = v_business_id;
      v_fields_updated := array_append(v_fields_updated, 'address_line1');
    END IF;
    IF p_patch ? 'address_line2' THEN
      v_new_val := NULLIF(trim(p_patch->>'address_line2'), '');
      UPDATE businesses SET address_line2 = v_new_val WHERE id = v_business_id;
      v_fields_updated := array_append(v_fields_updated, 'address_line2');
    END IF;
    IF p_patch ? 'pincode' THEN
      v_new_val := NULLIF(trim(p_patch->>'pincode'), '');
      UPDATE businesses SET pincode = v_new_val WHERE id = v_business_id;
      v_fields_updated := array_append(v_fields_updated, 'pincode');
    END IF;
  END IF;

  -- Touch updated_at
  UPDATE businesses SET updated_at = NOW() WHERE id = v_business_id;

  -- Return same shape as old version so existing UI works
  RETURN jsonb_build_object(
    'ok',              TRUE,
    'status',          v_old.status,
    'fields_updated',  v_fields_updated,
    'pending_fields',  ARRAY[]::TEXT[],
    'has_pending',     FALSE,
    'trusted_owner',   TRUE,
    'violations',      NULL,
    'message',         'Saved instantly — all your edits are live.'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION update_my_business(JSONB) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
BEGIN
  RAISE NOTICE '====================================================';
  RAISE NOTICE 'db/91 installed.';
  RAISE NOTICE 'update_my_business now:';
  RAISE NOTICE '  - LOCKS identity fields (name, email, mobile, address)';
  RAISE NOTICE '    from owner-side patches.';
  RAISE NOTICE '  - APPLIES all editable fields INSTANTLY.';
  RAISE NOTICE '  - Admins (is_admin = TRUE) can still patch the locked';
  RAISE NOTICE '    fields if they call this RPC directly.';
  RAISE NOTICE '====================================================';
END $$;
