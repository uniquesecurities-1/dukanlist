-- =====================================================
-- db/81-stop-admin-bypass.sql
-- =====================================================
-- USER REPORT (2026-05-28):
--   "Singla CSC ki profile maine abhi tak approve nahi ki hai... lekin
--    user ka login bhi ho raha hai aur poori ki poori profile 100%
--    working hai. Poora ka Poora Admin Bypass!"
--
-- ROOT CAUSE:
--   Function activate_business_after_photos() (db/05-rpc-functions.sql:126)
--   was auto-flipping businesses.status from 'pending' → 'active' as soon
--   as the owner uploaded a single photo. No admin involvement. This was
--   probably added for early bootstrap speed but is now a bypass.
--
-- THIS PATCH:
--   1. Replaces activate_business_after_photos() to ONLY set verified_photo=TRUE.
--      Status stays 'pending' until an admin explicitly approves via
--      admin_approve_business(). This restores the admin gate.
--   2. Extends update_my_business() moderation to include services_json
--      and faqs_json — these are rich JSON fields that can carry spam
--      text. For untrusted owners they now go to pending_edits (admin
--      must approve) instead of applying directly.
--
-- ROLLBACK (optional): if you want to bulk-revert all auto-approved shops
-- back to 'pending' for re-review, the last section has a commented-out
-- query — run it manually only if you want a full re-audit.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. Remove auto-activation from photo upload
-- ============================================================
CREATE OR REPLACE FUNCTION activate_business_after_photos(p_business_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_ok    BOOLEAN;
  v_photo_count INT;
BEGIN
  -- Verify caller is owner of this business
  SELECT EXISTS(
    SELECT 1 FROM business_owners
    WHERE business_id = p_business_id AND auth_user_id = auth.uid()
  ) INTO v_owner_ok;

  IF NOT v_owner_ok THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Count uploaded photos
  SELECT array_length(photos, 1) INTO v_photo_count
  FROM businesses WHERE id = p_business_id;

  IF COALESCE(v_photo_count, 0) >= 1 THEN
    -- 🚨 SECURITY: only mark verified_photo flag — DO NOT auto-flip status.
    -- Admin must explicitly approve via admin_approve_business() before the
    -- listing goes live to the public. This restores the admin gate that
    -- was previously bypassed.
    UPDATE businesses
    SET verified_photo = TRUE
    WHERE id = p_business_id;
  ELSE
    RAISE EXCEPTION 'At least 1 photo required';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION activate_business_after_photos(UUID) TO authenticated;


-- ============================================================
-- 2. Extend update_my_business() to moderate services_json + faqs_json
-- ============================================================
-- These fields carry rich user content (service names, prices, FAQ
-- answers) that can be used to inject spam. For untrusted owners (less
-- than 90 days old, verified_score < 4, or has flags), staging them in
-- pending_edits keeps the live listing clean until admin reviews.
--
-- For trusted owners, they continue to apply directly (no friction).
-- ============================================================

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
  v_pending        JSONB;
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

  v_pending := COALESCE(v_old.pending_edits, '{}'::jsonb);

  -- Content keyword check — also flatten services + faqs into the scan
  v_combined_text := COALESCE(p_patch->>'name','')
                  || ' ' || COALESCE(p_patch->>'usp_text','')
                  || ' ' || COALESCE(p_patch->>'usp_hi','')
                  || ' ' || COALESCE(p_patch->>'about_text','')
                  || ' ' || COALESCE(p_patch->>'services_json','')
                  || ' ' || COALESCE(p_patch->>'faqs_json','');
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

  -- ===== SENSITIVE fields — TRUSTED applies directly; UNTRUSTED stages =====

  -- services_json (NEW: now moderated)
  IF p_patch ? 'services_json' THEN
    IF v_trusted THEN
      UPDATE businesses SET services_json = p_patch->'services_json' WHERE id = v_business_id;
      v_fields_updated := array_append(v_fields_updated, 'services_json');
    ELSE
      v_pending := v_pending || jsonb_build_object('services_json', p_patch->'services_json');
      v_sensitive_changed := TRUE;
      v_pending_fields := array_append(v_pending_fields, 'services_json');
    END IF;
    INSERT INTO business_edits(business_id, field_name, old_value, new_value, is_sensitive, triggered_review, edited_by, edited_role)
      VALUES (v_business_id, 'services_json',
              substr(v_old.services_json::TEXT, 1, 400),
              substr((p_patch->'services_json')::TEXT, 1, 400),
              TRUE, NOT v_trusted, v_user_id, 'owner');
  END IF;

  -- faqs_json (NEW: now moderated)
  IF p_patch ? 'faqs_json' THEN
    IF v_trusted THEN
      UPDATE businesses SET faqs_json = p_patch->'faqs_json' WHERE id = v_business_id;
      v_fields_updated := array_append(v_fields_updated, 'faqs_json');
    ELSE
      v_pending := v_pending || jsonb_build_object('faqs_json', p_patch->'faqs_json');
      v_sensitive_changed := TRUE;
      v_pending_fields := array_append(v_pending_fields, 'faqs_json');
    END IF;
    INSERT INTO business_edits(business_id, field_name, old_value, new_value, is_sensitive, triggered_review, edited_by, edited_role)
      VALUES (v_business_id, 'faqs_json',
              substr(v_old.faqs_json::TEXT, 1, 400),
              substr((p_patch->'faqs_json')::TEXT, 1, 400),
              TRUE, NOT v_trusted, v_user_id, 'owner');
  END IF;

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

  -- Save pending_edits + flip status to pending_review if any sensitive changes
  IF v_sensitive_changed AND NOT v_trusted THEN
    UPDATE businesses
       SET pending_edits = v_pending,
           status = CASE WHEN status = 'active' THEN 'pending_review' ELSE status END
     WHERE id = v_business_id;
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'applied_fields', v_fields_updated,
    'pending_review_fields', v_pending_fields,
    'is_trusted', v_trusted,
    'violations', v_violations
  );
END;
$$;

GRANT EXECUTE ON FUNCTION update_my_business(JSONB) TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- VERIFY
-- =====================================================
DO $$
DECLARE
  v_rpc1 INT;
  v_rpc2 INT;
BEGIN
  SELECT COUNT(*) INTO v_rpc1 FROM pg_proc
    WHERE proname = 'activate_business_after_photos';
  SELECT COUNT(*) INTO v_rpc2 FROM pg_proc
    WHERE proname = 'update_my_business';

  RAISE NOTICE '✅ activate_business_after_photos: % (status auto-flip REMOVED)', v_rpc1;
  RAISE NOTICE '✅ update_my_business: % (now moderates services_json + faqs_json)', v_rpc2;
END $$;

-- =====================================================
-- OPTIONAL — REVERT auto-approved shops back to pending review
-- =====================================================
-- If you want to bulk-revert all shops that were auto-activated by the
-- old bug back to 'pending' so you can re-review them, uncomment the
-- block below and run it manually. WARNING: this will make some shops
-- temporarily invisible to public until you re-approve.
--
-- This identifies suspect shops: status='active' but no admin_audit_log
-- entry for an approve_business action. Adjust the filter as needed.
-- =====================================================
-- UPDATE businesses b
--    SET status = 'pending'
--  WHERE b.status = 'active'
--    AND b.created_at > '2026-01-01'      -- only recent ones
--    AND NOT EXISTS (
--      SELECT 1 FROM admin_audit_log a
--      WHERE a.action = 'approve_business'
--        AND a.target_id = b.id::TEXT
--    );
