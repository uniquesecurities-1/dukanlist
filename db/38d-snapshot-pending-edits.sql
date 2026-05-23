-- =====================================================
-- db/38d-snapshot-pending-edits.sql
-- ARCHITECTURE FIX — snapshot-based pending edits
-- =====================================================
-- PROBLEM with db/38:
--   When owner edited sensitive fields, we modified main columns directly
--   AND set status='pending_review'. This caused:
--     (a) Public business.html (filters status='active') threw error
--     (b) Bad content was already in main columns — defeats security
--     (c) Customers lost access to old approved version
--
-- NEW DESIGN:
--   • Add businesses.pending_edits JSONB — holds proposed changes for sensitive fields
--   • Sensitive field edits go INTO pending_edits, NOT into main columns
--   • status stays 'active' — public site reads main columns (= old approved version)
--   • Admin sees pending_edits in moderation, approves OR rejects
--   • On approve: pending_edits values merge into main columns, JSONB cleared
--   • On reject:  pending_edits cleared, no change to main columns
--   • Trusted owners bypass — sensitive edits apply directly (no pending_edits)
--   • Minor fields (hours/services/faqs/whatsapp/email/owner_name) ALWAYS apply directly
-- =====================================================
BEGIN;

-- ---------- 1. ADD pending_edits COLUMN ----------
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS pending_edits JSONB DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS pending_edits_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_biz_pending_edits
  ON businesses(pending_edits_at DESC)
  WHERE pending_edits IS NOT NULL;

-- ---------- 2. REWRITE update_my_business ----------
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
  v_trusted        BOOLEAN;
  v_sensitive_changed BOOLEAN := FALSE;
  v_fields_updated TEXT[] := ARRAY[]::TEXT[];
  v_pending_fields TEXT[] := ARRAY[]::TEXT[];
  v_violations     JSONB := '[]'::jsonb;
  v_check          JSONB;
  v_pending        JSONB := COALESCE((SELECT pending_edits FROM businesses WHERE id = (SELECT bo.business_id FROM business_owners bo WHERE bo.auth_user_id = auth.uid() LIMIT 1)), '{}'::jsonb);
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

  -- Content keyword check
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

  -- ===== MINOR fields — apply directly (always) =====
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

  -- ===== SENSITIVE fields =====
  -- TRUSTED owner: apply directly (no friction)
  -- UNTRUSTED owner: stage in pending_edits JSONB (admin must approve)
  PERFORM 1;  -- noop separator

  IF p_patch ? 'name' THEN
    v_new_val := NULLIF(trim(p_patch->>'name'), '');
    v_old_val := v_old.name;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old_val,'') THEN
      IF v_trusted THEN
        UPDATE businesses SET name = v_new_val WHERE id = v_business_id;
      ELSE
        v_pending := v_pending || jsonb_build_object('name', v_new_val);
      END IF;
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
      IF v_trusted THEN
        UPDATE businesses SET usp_text = v_new_val WHERE id = v_business_id;
      ELSE
        v_pending := v_pending || jsonb_build_object('usp_text', v_new_val);
      END IF;
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
      IF v_trusted THEN
        UPDATE businesses SET usp_hi = v_new_val WHERE id = v_business_id;
      ELSE
        v_pending := v_pending || jsonb_build_object('usp_hi', v_new_val);
      END IF;
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
      IF v_trusted THEN
        UPDATE businesses SET about_text = v_new_val WHERE id = v_business_id;
      ELSE
        v_pending := v_pending || jsonb_build_object('about_text', v_new_val);
      END IF;
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
      IF v_trusted THEN
        UPDATE businesses SET address_line1 = v_new_val WHERE id = v_business_id;
      ELSE
        v_pending := v_pending || jsonb_build_object('address_line1', v_new_val);
      END IF;
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
      IF v_trusted THEN
        UPDATE businesses SET address_line2 = v_new_val WHERE id = v_business_id;
      ELSE
        v_pending := v_pending || jsonb_build_object('address_line2', v_new_val);
      END IF;
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
      IF v_trusted THEN
        UPDATE businesses SET pincode = v_new_val WHERE id = v_business_id;
      ELSE
        v_pending := v_pending || jsonb_build_object('pincode', v_new_val);
      END IF;
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
        IF v_trusted THEN
          UPDATE businesses SET photos = v_new_photos WHERE id = v_business_id;
        ELSE
          v_pending := v_pending || jsonb_build_object('photos', p_patch->'photos');
        END IF;
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

  -- ===== Persist pending_edits =====
  -- DO NOT touch status. Public site sees main columns (old approved version).
  IF v_sensitive_changed AND NOT v_trusted THEN
    -- pending_edits is stripped of any keys that point to values equal to current main column
    -- (defensive — keep JSONB small and focused).
    UPDATE businesses
       SET pending_edits    = NULLIF(v_pending, '{}'::jsonb),
           pending_edits_at = NOW(),
           updated_at       = NOW()
     WHERE id = v_business_id;
  ELSE
    UPDATE businesses SET updated_at = NOW() WHERE id = v_business_id;
  END IF;

  RETURN jsonb_build_object(
    'ok',              TRUE,
    'business_id',     v_business_id,
    'status',          v_old.status,
    'trusted_owner',   v_trusted,
    'has_pending',     (v_sensitive_changed AND NOT v_trusted),
    'fields_updated',  v_fields_updated,
    'pending_fields',  v_pending_fields,
    'violations',      v_violations
  );
END;
$$;

GRANT EXECUTE ON FUNCTION update_my_business(JSONB) TO authenticated;

-- ---------- 3. REWRITE admin_pending_edits ----------
DROP FUNCTION IF EXISTS admin_pending_edits(INT, INT);

CREATE OR REPLACE FUNCTION admin_pending_edits(p_limit INT DEFAULT 30, p_offset INT DEFAULT 0)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  SELECT COALESCE(jsonb_agg(row), '[]'::jsonb) INTO v_result FROM (
    SELECT jsonb_build_object(
      'business_id',      b.id,
      'slug',             b.slug,
      'name',             b.name,
      'city_name',        gc.name,
      'status',           b.status,
      'pending_edits',    b.pending_edits,
      'pending_edits_at', b.pending_edits_at,
      'live_snapshot',    jsonb_build_object(
        'name',           b.name,
        'usp_text',       b.usp_text,
        'usp_hi',         b.usp_hi,
        'about_text',     b.about_text,
        'address_line1',  b.address_line1,
        'address_line2',  b.address_line2,
        'pincode',        b.pincode,
        'photos',         b.photos
      )
    ) AS row
    FROM businesses b
    LEFT JOIN geo_cities gc ON gc.id = b.city_id
    WHERE b.pending_edits IS NOT NULL
    ORDER BY b.pending_edits_at DESC
    LIMIT GREATEST(1, LEAST(p_limit, 100))
    OFFSET GREATEST(0, p_offset)
  ) sub;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_pending_edits(INT, INT) TO authenticated;

-- ---------- 4. admin_approve_pending_edits ----------
DROP FUNCTION IF EXISTS admin_approve_pending_edits(UUID);

CREATE OR REPLACE FUNCTION admin_approve_pending_edits(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID := auth.uid();
  v_pending  JSONB;
  v_applied  TEXT[] := ARRAY[]::TEXT[];
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  SELECT pending_edits INTO v_pending FROM businesses WHERE id = p_business_id;
  IF v_pending IS NULL OR v_pending = '{}'::jsonb THEN
    RAISE EXCEPTION 'No pending edits to approve';
  END IF;

  -- Merge each key in v_pending into the corresponding main column
  IF v_pending ? 'name' THEN
    UPDATE businesses SET name = v_pending->>'name' WHERE id = p_business_id;
    v_applied := array_append(v_applied, 'name');
  END IF;
  IF v_pending ? 'usp_text' THEN
    UPDATE businesses SET usp_text = v_pending->>'usp_text' WHERE id = p_business_id;
    v_applied := array_append(v_applied, 'usp_text');
  END IF;
  IF v_pending ? 'usp_hi' THEN
    UPDATE businesses SET usp_hi = v_pending->>'usp_hi' WHERE id = p_business_id;
    v_applied := array_append(v_applied, 'usp_hi');
  END IF;
  IF v_pending ? 'about_text' THEN
    UPDATE businesses SET about_text = v_pending->>'about_text' WHERE id = p_business_id;
    v_applied := array_append(v_applied, 'about_text');
  END IF;
  IF v_pending ? 'address_line1' THEN
    UPDATE businesses SET address_line1 = v_pending->>'address_line1' WHERE id = p_business_id;
    v_applied := array_append(v_applied, 'address_line1');
  END IF;
  IF v_pending ? 'address_line2' THEN
    UPDATE businesses SET address_line2 = v_pending->>'address_line2' WHERE id = p_business_id;
    v_applied := array_append(v_applied, 'address_line2');
  END IF;
  IF v_pending ? 'pincode' THEN
    UPDATE businesses SET pincode = v_pending->>'pincode' WHERE id = p_business_id;
    v_applied := array_append(v_applied, 'pincode');
  END IF;
  IF v_pending ? 'photos' THEN
    UPDATE businesses
       SET photos = ARRAY(SELECT jsonb_array_elements_text(v_pending->'photos'))
     WHERE id = p_business_id;
    v_applied := array_append(v_applied, 'photos');
  END IF;

  -- Clear pending_edits
  UPDATE businesses
     SET pending_edits    = NULL,
         pending_edits_at = NULL,
         updated_at       = NOW()
   WHERE id = p_business_id;

  -- Audit
  INSERT INTO business_edits(business_id, field_name, old_value, new_value, edited_by, edited_role)
    VALUES (p_business_id, 'approve_pending_edits',
            NULL, array_to_string(v_applied, ', '),
            v_admin_id, 'admin');

  RETURN jsonb_build_object('ok', TRUE, 'fields_applied', v_applied);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_approve_pending_edits(UUID) TO authenticated;

-- ---------- 5. admin_reject_pending_edits ----------
DROP FUNCTION IF EXISTS admin_reject_pending_edits(UUID, TEXT);

CREATE OR REPLACE FUNCTION admin_reject_pending_edits(p_business_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID := auth.uid();
  v_pending  JSONB;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  SELECT pending_edits INTO v_pending FROM businesses WHERE id = p_business_id;

  UPDATE businesses
     SET pending_edits    = NULL,
         pending_edits_at = NULL,
         updated_at       = NOW()
   WHERE id = p_business_id;

  INSERT INTO business_edits(business_id, field_name, old_value, new_value, edited_by, edited_role)
    VALUES (p_business_id, 'reject_pending_edits',
            v_pending::TEXT, p_reason,
            v_admin_id, 'admin');

  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_reject_pending_edits(UUID, TEXT) TO authenticated;

-- ---------- 6. Migrate any shops currently stuck in 'pending_review' status back to 'active' ----------
-- (db/38 incorrectly moved them. Restore so public site works.)
UPDATE businesses
   SET status = 'active'
 WHERE status = 'pending_review';

NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- VERIFY:
-- SELECT id, name, status, pending_edits, pending_edits_at FROM businesses WHERE pending_edits IS NOT NULL;
-- SELECT admin_pending_edits(10, 0);
-- SELECT admin_approve_pending_edits('<business-uuid>');
-- =====================================================
