-- =====================================================
-- db/38b-fix-array-concat.sql
-- HOTFIX for db/38 — array concatenation bug
-- =====================================================
-- BUG: PostgreSQL ambiguity on `text[] || text` resolution
-- caused "malformed array literal: hours_json" on save.
-- FIX: replace `||` with array_append() everywhere in update_my_business().
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
  v_status_before  TEXT;
  v_status_after   TEXT;
  v_trusted        BOOLEAN;
  v_sensitive_changed BOOLEAN := FALSE;
  v_fields_updated TEXT[] := ARRAY[]::TEXT[];
  v_pending_fields TEXT[] := ARRAY[]::TEXT[];
  v_violations     JSONB := '[]'::jsonb;
  v_check          JSONB;
  v_new_val        TEXT;
  v_old_val        TEXT;
  v_combined_text  TEXT := '';
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
  v_status_before := v_old.status;

  -- ===== Step 1: Content keyword check =====
  v_combined_text := COALESCE(p_patch->>'name','')
                  || ' ' || COALESCE(p_patch->>'usp_text','')
                  || ' ' || COALESCE(p_patch->>'usp_hi','')
                  || ' ' || COALESCE(p_patch->>'about_text','');
  v_check := check_content_violations(v_combined_text);
  IF (v_check->>'blocked')::BOOLEAN THEN
    RAISE EXCEPTION 'Content blocked: %', v_check->'violations';
  END IF;
  v_violations := v_check->'violations';

  v_trusted := is_trusted_owner(v_business_id);

  -- ===== MINOR fields (instant — no re-review) =====
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

  IF p_patch ? 'whatsapp' THEN
    v_new_val := NULLIF(trim(p_patch->>'whatsapp'), '');
    v_old_val := v_old.whatsapp;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old_val,'') THEN
      UPDATE businesses SET whatsapp = v_new_val WHERE id = v_business_id;
      INSERT INTO business_edits(business_id, field_name, old_value, new_value, edited_by, edited_role)
        VALUES (v_business_id, 'whatsapp', v_old_val, v_new_val, v_user_id, 'owner');
      v_fields_updated := array_append(v_fields_updated, 'whatsapp');
    END IF;
  END IF;

  IF p_patch ? 'email' THEN
    v_new_val := NULLIF(trim(p_patch->>'email'), '');
    v_old_val := v_old.email;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old_val,'') THEN
      UPDATE businesses SET email = v_new_val WHERE id = v_business_id;
      INSERT INTO business_edits(business_id, field_name, old_value, new_value, edited_by, edited_role)
        VALUES (v_business_id, 'email', v_old_val, v_new_val, v_user_id, 'owner');
      v_fields_updated := array_append(v_fields_updated, 'email');
    END IF;
  END IF;

  IF p_patch ? 'owner_name' THEN
    v_new_val := NULLIF(trim(p_patch->>'owner_name'), '');
    v_old_val := v_old.owner_name;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old_val,'') THEN
      UPDATE businesses SET owner_name = v_new_val WHERE id = v_business_id;
      INSERT INTO business_edits(business_id, field_name, old_value, new_value, edited_by, edited_role)
        VALUES (v_business_id, 'owner_name', v_old_val, v_new_val, v_user_id, 'owner');
      v_fields_updated := array_append(v_fields_updated, 'owner_name');
    END IF;
  END IF;

  -- ===== SENSITIVE fields (re-review unless trusted) =====
  IF p_patch ? 'name' THEN
    v_new_val := NULLIF(trim(p_patch->>'name'), '');
    v_old_val := v_old.name;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old_val,'') THEN
      UPDATE businesses SET name = v_new_val WHERE id = v_business_id;
      v_sensitive_changed := TRUE;
      v_pending_fields := array_append(v_pending_fields, 'name');
      INSERT INTO business_edits(business_id, field_name, old_value, new_value, is_sensitive, triggered_review, edited_by, edited_role)
        VALUES (v_business_id, 'name', v_old_val, v_new_val, TRUE, NOT v_trusted, v_user_id, 'owner');
    END IF;
  END IF;

  IF p_patch ? 'usp_text' THEN
    v_new_val := NULLIF(trim(p_patch->>'usp_text'), '');
    v_old_val := v_old.usp_text;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old_val,'') THEN
      UPDATE businesses SET usp_text = v_new_val WHERE id = v_business_id;
      v_sensitive_changed := TRUE;
      v_pending_fields := array_append(v_pending_fields, 'usp_text');
      INSERT INTO business_edits(business_id, field_name, old_value, new_value, is_sensitive, triggered_review, edited_by, edited_role)
        VALUES (v_business_id, 'usp_text', v_old_val, v_new_val, TRUE, NOT v_trusted, v_user_id, 'owner');
    END IF;
  END IF;

  IF p_patch ? 'usp_hi' THEN
    v_new_val := NULLIF(trim(p_patch->>'usp_hi'), '');
    v_old_val := v_old.usp_hi;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old_val,'') THEN
      UPDATE businesses SET usp_hi = v_new_val WHERE id = v_business_id;
      v_sensitive_changed := TRUE;
      v_pending_fields := array_append(v_pending_fields, 'usp_hi');
      INSERT INTO business_edits(business_id, field_name, old_value, new_value, is_sensitive, triggered_review, edited_by, edited_role)
        VALUES (v_business_id, 'usp_hi', v_old_val, v_new_val, TRUE, NOT v_trusted, v_user_id, 'owner');
    END IF;
  END IF;

  IF p_patch ? 'about_text' THEN
    v_new_val := NULLIF(trim(p_patch->>'about_text'), '');
    v_old_val := v_old.about_text;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old_val,'') THEN
      UPDATE businesses SET about_text = v_new_val WHERE id = v_business_id;
      v_sensitive_changed := TRUE;
      v_pending_fields := array_append(v_pending_fields, 'about_text');
      INSERT INTO business_edits(business_id, field_name, old_value, new_value, is_sensitive, triggered_review, edited_by, edited_role)
        VALUES (v_business_id, 'about_text', v_old_val, v_new_val, TRUE, NOT v_trusted, v_user_id, 'owner');
    END IF;
  END IF;

  IF p_patch ? 'address_line1' THEN
    v_new_val := NULLIF(trim(p_patch->>'address_line1'), '');
    v_old_val := v_old.address_line1;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old_val,'') THEN
      UPDATE businesses SET address_line1 = v_new_val WHERE id = v_business_id;
      v_sensitive_changed := TRUE;
      v_pending_fields := array_append(v_pending_fields, 'address_line1');
      INSERT INTO business_edits(business_id, field_name, old_value, new_value, is_sensitive, triggered_review, edited_by, edited_role)
        VALUES (v_business_id, 'address_line1', v_old_val, v_new_val, TRUE, NOT v_trusted, v_user_id, 'owner');
    END IF;
  END IF;

  IF p_patch ? 'address_line2' THEN
    v_new_val := NULLIF(trim(p_patch->>'address_line2'), '');
    v_old_val := v_old.address_line2;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old_val,'') THEN
      UPDATE businesses SET address_line2 = v_new_val WHERE id = v_business_id;
      v_sensitive_changed := TRUE;
      v_pending_fields := array_append(v_pending_fields, 'address_line2');
      INSERT INTO business_edits(business_id, field_name, old_value, new_value, is_sensitive, triggered_review, edited_by, edited_role)
        VALUES (v_business_id, 'address_line2', v_old_val, v_new_val, TRUE, NOT v_trusted, v_user_id, 'owner');
    END IF;
  END IF;

  IF p_patch ? 'pincode' THEN
    v_new_val := NULLIF(trim(p_patch->>'pincode'), '');
    v_old_val := v_old.pincode;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old_val,'') THEN
      UPDATE businesses SET pincode = v_new_val WHERE id = v_business_id;
      v_sensitive_changed := TRUE;
      v_pending_fields := array_append(v_pending_fields, 'pincode');
      INSERT INTO business_edits(business_id, field_name, old_value, new_value, is_sensitive, triggered_review, edited_by, edited_role)
        VALUES (v_business_id, 'pincode', v_old_val, v_new_val, TRUE, NOT v_trusted, v_user_id, 'owner');
    END IF;
  END IF;

  IF p_patch ? 'photos' THEN
    DECLARE
      v_new_photos TEXT[];
      v_old_photos TEXT[] := COALESCE(v_old.photos, ARRAY[]::TEXT[]);
    BEGIN
      v_new_photos := ARRAY(SELECT jsonb_array_elements_text(p_patch->'photos'));
      IF v_new_photos IS DISTINCT FROM v_old_photos THEN
        UPDATE businesses SET photos = v_new_photos WHERE id = v_business_id;
        v_sensitive_changed := TRUE;
        v_pending_fields := array_append(v_pending_fields, 'photos');
        INSERT INTO business_edits(business_id, field_name, old_value, new_value, is_sensitive, triggered_review, edited_by, edited_role)
          VALUES (v_business_id, 'photos',
                  array_to_string(v_old_photos, ', '),
                  array_to_string(v_new_photos, ', '),
                  TRUE, NOT v_trusted, v_user_id, 'owner');
      END IF;
    END;
  END IF;

  -- ===== Re-review trigger =====
  v_status_after := v_status_before;
  IF v_sensitive_changed AND NOT v_trusted AND v_status_before = 'active' THEN
    UPDATE businesses
       SET status = 'pending_review',
           updated_at = NOW()
     WHERE id = v_business_id;
    v_status_after := 'pending_review';
  ELSE
    UPDATE businesses SET updated_at = NOW() WHERE id = v_business_id;
  END IF;

  RETURN jsonb_build_object(
    'ok',              TRUE,
    'business_id',     v_business_id,
    'status',          v_status_after,
    'status_changed',  v_status_after <> v_status_before,
    'trusted_owner',   v_trusted,
    'fields_updated',  v_fields_updated,
    'pending_fields',  v_pending_fields,
    'violations',      v_violations
  );
END;
$$;

GRANT EXECUTE ON FUNCTION update_my_business(JSONB) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- VERIFY: Try saving from panel/profile.html again
-- =====================================================
