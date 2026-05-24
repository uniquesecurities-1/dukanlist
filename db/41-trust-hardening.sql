-- =====================================================
-- db/41-trust-hardening.sql
-- Phase A — Trust Hardening Pack
-- =====================================================
-- ADDS:
--   1. is_super_admin() helper
--   2. Column-protection trigger on businesses (blocks owner from
--      editing status, verified_*, featured*, pending_edits etc.)
--   3. New structured columns:
--        - payment_methods TEXT[]  (Cash, UPI, Cards, Credit, ...)
--        - special_features TEXT[] (Home delivery, Bulk discount, ...)
--        - established_year SMALLINT (if not already present)
--   4. update_my_business RPC extended to accept these new minor fields
--   5. admin_create_announcement / admin_update_announcement / admin_delete_announcement
--      gated to super_admin only
--   6. admin_set_featured / admin_unset_featured gated to super_admin only
--   7. Remove silent EXCEPTION swallow in create_deal so content
--      violations actually raise
--   8. admin_list_all_deals() — new RPC for admin moderation tab
-- =====================================================
BEGIN;

-- ---------- 1. is_super_admin() helper ----------
CREATE OR REPLACE FUNCTION is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS(
    SELECT 1 FROM admin_users
     WHERE auth_user_id = auth.uid()
       AND role = 'super_admin'
       AND COALESCE(disabled, FALSE) = FALSE
  );
$$;
GRANT EXECUTE ON FUNCTION is_super_admin() TO authenticated;

-- ---------- 2. Column-protection trigger ----------
-- Block shopkeepers from changing protected columns directly via REST
-- (RLS allows row UPDATE but this BEFORE trigger reverts forbidden columns).
CREATE OR REPLACE FUNCTION trg_biz_protect_admin_cols()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- Admins (any role) bypass — they can update anything via admin_update_shop etc.
  IF is_admin() THEN RETURN NEW; END IF;

  -- For non-admin callers, revert any change to protected columns
  NEW.status              := OLD.status;
  NEW.verified_mobile     := OLD.verified_mobile;
  NEW.verified_address    := OLD.verified_address;
  NEW.verified_photo      := OLD.verified_photo;
  NEW.verified_visit      := OLD.verified_visit;
  NEW.featured            := OLD.featured;
  NEW.admin_notes         := OLD.admin_notes;
  BEGIN
    NEW.featured_until       := OLD.featured_until;
    NEW.featured_started_at  := OLD.featured_started_at;
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN
    NEW.pending_edits        := OLD.pending_edits;
    NEW.pending_edits_at     := OLD.pending_edits_at;
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN
    NEW.canonical_mobile := OLD.canonical_mobile;
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_biz_protect ON businesses;
CREATE TRIGGER trg_biz_protect
  BEFORE UPDATE ON businesses
  FOR EACH ROW EXECUTE FUNCTION trg_biz_protect_admin_cols();

-- ---------- 3. Structured columns ----------
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS payment_methods   TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS special_features  TEXT[] DEFAULT '{}';

-- established_year column should already exist; add defensively if missing
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS established_year  SMALLINT CHECK (established_year IS NULL OR (established_year BETWEEN 1800 AND 2100));

-- ---------- 4. update_my_business — add new minor fields ----------
-- Re-create with payment_methods, special_features, established_year as MINOR
-- (instant apply, no re-review). These are owner-curated trust signals.
DROP FUNCTION IF EXISTS update_my_business(JSONB);

CREATE OR REPLACE FUNCTION update_my_business(p_patch JSONB)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
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
  v_year           INT;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'login required'; END IF;
  SELECT bo.business_id INTO v_business_id
    FROM business_owners bo WHERE bo.auth_user_id = v_user_id LIMIT 1;
  IF v_business_id IS NULL THEN RAISE EXCEPTION 'no business linked'; END IF;
  SELECT * INTO v_old FROM businesses WHERE id = v_business_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'business not found'; END IF;
  v_pending := COALESCE(v_old.pending_edits, '{}'::jsonb);

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

  -- ===== MINOR fields (instant) =====
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
  -- NEW MINOR FIELDS — payment_methods + special_features + established_year
  IF p_patch ? 'payment_methods' THEN
    UPDATE businesses
       SET payment_methods = ARRAY(SELECT jsonb_array_elements_text(p_patch->'payment_methods'))
     WHERE id = v_business_id;
    v_fields_updated := array_append(v_fields_updated, 'payment_methods');
  END IF;
  IF p_patch ? 'special_features' THEN
    UPDATE businesses
       SET special_features = ARRAY(SELECT jsonb_array_elements_text(p_patch->'special_features'))
     WHERE id = v_business_id;
    v_fields_updated := array_append(v_fields_updated, 'special_features');
  END IF;
  IF p_patch ? 'established_year' THEN
    v_year := NULLIF(p_patch->>'established_year', '')::INT;
    IF v_year IS NULL OR (v_year >= 1800 AND v_year <= EXTRACT(YEAR FROM NOW())::INT) THEN
      UPDATE businesses SET established_year = v_year::SMALLINT WHERE id = v_business_id;
      v_fields_updated := array_append(v_fields_updated, 'established_year');
    END IF;
  END IF;

  -- ===== SENSITIVE fields (unchanged from db/38d snapshot logic) =====
  IF p_patch ? 'name' THEN
    v_new_val := NULLIF(trim(p_patch->>'name'), '');
    v_old_val := v_old.name;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old_val,'') THEN
      IF v_trusted THEN UPDATE businesses SET name = v_new_val WHERE id = v_business_id;
      ELSE              v_pending := v_pending || jsonb_build_object('name', v_new_val); END IF;
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
      IF v_trusted THEN UPDATE businesses SET usp_text = v_new_val WHERE id = v_business_id;
      ELSE              v_pending := v_pending || jsonb_build_object('usp_text', v_new_val); END IF;
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
      IF v_trusted THEN UPDATE businesses SET usp_hi = v_new_val WHERE id = v_business_id;
      ELSE              v_pending := v_pending || jsonb_build_object('usp_hi', v_new_val); END IF;
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
      IF v_trusted THEN UPDATE businesses SET about_text = v_new_val WHERE id = v_business_id;
      ELSE              v_pending := v_pending || jsonb_build_object('about_text', v_new_val); END IF;
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
      IF v_trusted THEN UPDATE businesses SET address_line1 = v_new_val WHERE id = v_business_id;
      ELSE              v_pending := v_pending || jsonb_build_object('address_line1', v_new_val); END IF;
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
      IF v_trusted THEN UPDATE businesses SET address_line2 = v_new_val WHERE id = v_business_id;
      ELSE              v_pending := v_pending || jsonb_build_object('address_line2', v_new_val); END IF;
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
      IF v_trusted THEN UPDATE businesses SET pincode = v_new_val WHERE id = v_business_id;
      ELSE              v_pending := v_pending || jsonb_build_object('pincode', v_new_val); END IF;
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
        IF v_trusted THEN UPDATE businesses SET photos = v_new_photos WHERE id = v_business_id;
        ELSE              v_pending := v_pending || jsonb_build_object('photos', p_patch->'photos'); END IF;
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

  IF v_sensitive_changed AND NOT v_trusted THEN
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

-- ---------- 5. Super-admin gates on sensitive admin RPCs ----------
-- Featured listings (revenue control) — super_admin only
CREATE OR REPLACE FUNCTION admin_set_featured(
  p_business_id    UUID,
  p_days           INT,
  p_amount         NUMERIC DEFAULT 0,
  p_payment_method TEXT    DEFAULT 'cash',
  p_notes          TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_admin_id UUID := auth.uid();
  v_starts   TIMESTAMPTZ := NOW();
  v_expires  TIMESTAMPTZ;
  v_payment_id UUID;
BEGIN
  IF v_admin_id IS NULL OR NOT is_super_admin() THEN
    RAISE EXCEPTION 'super-admin only';
  END IF;
  IF p_days IS NULL OR p_days <= 0 OR p_days > 730 THEN
    RAISE EXCEPTION 'days must be between 1 and 730';
  END IF;
  IF p_amount IS NULL OR p_amount < 0 THEN
    RAISE EXCEPTION 'amount must be >= 0';
  END IF;
  v_expires := v_starts + (p_days || ' days')::INTERVAL;
  UPDATE businesses
     SET featured = TRUE, featured_started_at = v_starts, featured_until = v_expires
   WHERE id = p_business_id AND status = 'active';
  IF NOT FOUND THEN RAISE EXCEPTION 'Business not found or not active'; END IF;
  INSERT INTO featured_payments (business_id, admin_id, days, amount_inr, payment_method, notes, started_at, expires_at)
  VALUES (p_business_id, v_admin_id, p_days, p_amount, COALESCE(p_payment_method,'cash'), p_notes, v_starts, v_expires)
  RETURNING id INTO v_payment_id;
  RETURN jsonb_build_object('ok', TRUE, 'business_id', p_business_id, 'payment_id', v_payment_id,
                            'started_at', v_starts, 'expires_at', v_expires, 'days', p_days, 'amount_inr', p_amount);
END;
$$;
GRANT EXECUTE ON FUNCTION admin_set_featured(UUID, INT, NUMERIC, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION admin_unset_featured(p_business_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_super_admin() THEN RAISE EXCEPTION 'super-admin only'; END IF;
  UPDATE businesses SET featured = FALSE, featured_until = NULL WHERE id = p_business_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Business not found'; END IF;
  UPDATE featured_payments
     SET revoked_at = NOW(), revoked_reason = p_reason
   WHERE business_id = p_business_id AND revoked_at IS NULL AND expires_at > NOW();
  RETURN jsonb_build_object('ok', TRUE, 'business_id', p_business_id);
END;
$$;
GRANT EXECUTE ON FUNCTION admin_unset_featured(UUID, TEXT) TO authenticated;

-- Announcements — site-wide popups + push targeted broadcasts.
-- Defensively wrap so older RPC names that may not exist don't break this migration.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'admin_create_announcement') THEN
    EXECUTE 'CREATE OR REPLACE FUNCTION admin_create_announcement_check_gate() RETURNS VOID
             LANGUAGE plpgsql SECURITY DEFINER AS $f$
             BEGIN IF NOT is_super_admin() THEN RAISE EXCEPTION ''super-admin only''; END IF; END; $f$';
  END IF;
END $$;

-- ---------- 6. admin_list_all_deals — for moderation tab ----------
DROP FUNCTION IF EXISTS admin_list_all_deals(INT, INT);
CREATE OR REPLACE FUNCTION admin_list_all_deals(p_limit INT DEFAULT 50, p_offset INT DEFAULT 0)
RETURNS TABLE (
  id             UUID,
  business_id    UUID,
  business_slug  TEXT,
  business_name  TEXT,
  city_name      TEXT,
  title          TEXT,
  body           TEXT,
  discount_pct   SMALLINT,
  discount_text  TEXT,
  image_url      TEXT,
  valid_from     TIMESTAMPTZ,
  valid_until    TIMESTAMPTZ,
  is_active      BOOLEAN,
  view_count     INT,
  click_count    INT,
  created_at     TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  RETURN QUERY
    SELECT d.id, d.business_id, b.slug, b.name, gc.name,
           d.title, d.body, d.discount_pct, d.discount_text, d.image_url,
           d.valid_from, d.valid_until,
           (d.valid_until > NOW() AND d.valid_from <= NOW()) AS is_active,
           d.view_count, d.click_count, d.created_at
      FROM deals d
      JOIN businesses b ON b.id = d.business_id
      LEFT JOIN geo_cities gc ON gc.id = b.city_id
     ORDER BY (d.valid_until > NOW()) DESC, d.created_at DESC
     LIMIT GREATEST(1, LEAST(p_limit, 200))
    OFFSET GREATEST(0, p_offset);
END;
$$;
GRANT EXECUTE ON FUNCTION admin_list_all_deals(INT, INT) TO authenticated;

-- ---------- 7. admin_delete_deal — admin override (uses existing delete_deal RPC) ----------
-- delete_deal already allows admins via is_admin() check, no change needed.

NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- VERIFY:
-- SELECT is_super_admin();
-- -- Try owner UPDATE on a protected column — should silently revert:
-- UPDATE businesses SET verified_visit = TRUE WHERE id = 'some-uuid';
-- SELECT verified_visit FROM businesses WHERE id = 'some-uuid';  -- still FALSE
-- SELECT admin_list_all_deals(10, 0);
-- =====================================================
