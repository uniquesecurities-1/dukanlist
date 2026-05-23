-- =====================================================
-- db/38-moderation-hardening.sql
-- Trust & Safety Hardening Pack
-- =====================================================
-- Protects against:
--   1. Post-approval content tampering (bait-and-switch attack)
--   2. Multi-shop spam from same person (mobile/email variations)
--   3. Inappropriate content (blocked keywords)
--
-- ADDS:
--   • normalize_phone()         — canonicalize Indian mobile to 10 digits
--   • normalize_email()         — gmail-aware (dots, +tags stripped)
--   • businesses.canonical_mobile — auto-populated via trigger
--   • business_edits             — audit log of every field change
--   • blocked_keywords          — content filter rules
--   • is_trusted_owner()         — 90 days + verified_score >= 4 + no flags
--   • check_content_violations() — blocks bad content at write time
--   • update_my_business(JSONB)  — owner-facing RPC with sensitive-field guard
--   • register_business modification — 1 shop per canonical_mobile
--   • admin_pending_edits()      — moderation queue for re-review
--   • admin_get_edit_history()   — recent changes for shop page
-- =====================================================
BEGIN;

-- =====================================================
-- 1. PHONE NORMALIZATION
-- =====================================================
CREATE OR REPLACE FUNCTION normalize_phone(p_phone TEXT)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  v_digits TEXT;
BEGIN
  IF p_phone IS NULL OR length(trim(p_phone)) = 0 THEN
    RETURN NULL;
  END IF;
  -- Strip everything except digits
  v_digits := regexp_replace(p_phone, '\D', '', 'g');
  -- If 11 digits and starts with 0, drop the 0
  IF length(v_digits) = 11 AND substr(v_digits, 1, 1) = '0' THEN
    v_digits := substr(v_digits, 2);
  END IF;
  -- If 12 digits and starts with 91, drop the 91
  IF length(v_digits) = 12 AND substr(v_digits, 1, 2) = '91' THEN
    v_digits := substr(v_digits, 3);
  END IF;
  -- If 13 digits and starts with 091, drop the 091
  IF length(v_digits) = 13 AND substr(v_digits, 1, 3) = '091' THEN
    v_digits := substr(v_digits, 4);
  END IF;
  -- Final result must be exactly 10 digits starting with 6-9
  IF length(v_digits) = 10 AND substr(v_digits, 1, 1) ~ '[6-9]' THEN
    RETURN v_digits;
  END IF;
  RETURN NULL;
END;
$$;

-- =====================================================
-- 2. EMAIL NORMALIZATION (Gmail-aware)
-- =====================================================
CREATE OR REPLACE FUNCTION normalize_email(p_email TEXT)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  v_lower    TEXT;
  v_local    TEXT;
  v_domain   TEXT;
  v_at_pos   INT;
BEGIN
  IF p_email IS NULL OR length(trim(p_email)) = 0 THEN
    RETURN NULL;
  END IF;
  v_lower := lower(trim(p_email));
  v_at_pos := position('@' IN v_lower);
  IF v_at_pos < 2 THEN RETURN v_lower; END IF;
  v_local  := substr(v_lower, 1, v_at_pos - 1);
  v_domain := substr(v_lower, v_at_pos + 1);
  -- For gmail/googlemail: strip dots in local part, drop everything from + onwards
  IF v_domain IN ('gmail.com', 'googlemail.com') THEN
    -- Drop +tag
    IF position('+' IN v_local) > 0 THEN
      v_local := substr(v_local, 1, position('+' IN v_local) - 1);
    END IF;
    -- Strip all dots
    v_local := replace(v_local, '.', '');
    v_domain := 'gmail.com';
  END IF;
  RETURN v_local || '@' || v_domain;
END;
$$;

-- =====================================================
-- 3. ADD canonical_mobile COLUMN + AUTO-POPULATE TRIGGER
-- =====================================================
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS canonical_mobile TEXT;

CREATE INDEX IF NOT EXISTS idx_biz_canonical_mobile
  ON businesses(canonical_mobile) WHERE canonical_mobile IS NOT NULL;

-- Trigger function: auto-populate canonical_mobile on INSERT/UPDATE
CREATE OR REPLACE FUNCTION trg_businesses_canonicalize()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.canonical_mobile := normalize_phone(NEW.mobile);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_biz_canon ON businesses;
CREATE TRIGGER trg_biz_canon
  BEFORE INSERT OR UPDATE OF mobile ON businesses
  FOR EACH ROW EXECUTE FUNCTION trg_businesses_canonicalize();

-- Backfill existing rows
UPDATE businesses
   SET canonical_mobile = normalize_phone(mobile)
 WHERE canonical_mobile IS NULL AND mobile IS NOT NULL;

-- =====================================================
-- 4. BUSINESS_EDITS AUDIT LOG
-- =====================================================
CREATE TABLE IF NOT EXISTS business_edits (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id  UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  field_name   TEXT NOT NULL,
  old_value    TEXT,
  new_value    TEXT,
  is_sensitive BOOLEAN NOT NULL DEFAULT FALSE,
  triggered_review BOOLEAN NOT NULL DEFAULT FALSE,
  edited_by    UUID,                       -- auth.uid() or NULL for system
  edited_role  TEXT,                       -- 'owner' | 'admin' | 'system'
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_bedits_biz      ON business_edits(business_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bedits_review   ON business_edits(created_at DESC) WHERE triggered_review = TRUE;

ALTER TABLE business_edits ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "bedits_admin_read"  ON business_edits;
DROP POLICY IF EXISTS "bedits_owner_read"  ON business_edits;
CREATE POLICY "bedits_admin_read" ON business_edits
  FOR SELECT TO authenticated USING (is_admin());
CREATE POLICY "bedits_owner_read" ON business_edits
  FOR SELECT TO authenticated
  USING (business_id IN (SELECT bo.business_id FROM business_owners bo WHERE bo.auth_user_id = auth.uid()));

-- =====================================================
-- 5. BLOCKED KEYWORDS FILTER
-- =====================================================
CREATE TABLE IF NOT EXISTS blocked_keywords (
  id          SERIAL PRIMARY KEY,
  pattern     TEXT NOT NULL,           -- regex or plain
  severity    TEXT NOT NULL DEFAULT 'block' CHECK (severity IN ('block','flag','warn')),
  reason      TEXT,
  is_regex    BOOLEAN NOT NULL DEFAULT FALSE,
  active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO blocked_keywords (pattern, severity, reason, is_regex) VALUES
  ('https?://',                  'block', 'URLs not allowed in shop name/USP/about',  TRUE),
  ('www\.',                       'block', 'URLs not allowed in shop name/USP/about',  TRUE),
  ('\.(com|in|net|org|co|biz)',  'block', 'URLs not allowed in shop name/USP/about',  TRUE),
  ('whatsapp\.com',              'block', 'External link not allowed',                 TRUE),
  ('\d{10}',                      'flag',  'Phone number in text — verify context',    TRUE),
  ('otp|one[- ]time password',   'block', 'Suspicious — anti-phishing',                TRUE),
  ('click here|download now',    'block', 'Suspicious CTA — anti-phishing',            TRUE),
  ('free money|instant cash|loan approval', 'block', 'Suspicious — fraud bait',        TRUE),
  ('viagra|cialis|escort|sex(?:ual)?',      'block', 'Adult content',                  TRUE),
  ('fuck|bitch|asshole|chutiya|bhenchod|madarchod', 'block', 'Profanity',              TRUE)
ON CONFLICT DO NOTHING;

ALTER TABLE blocked_keywords ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "bk_admin_all"  ON blocked_keywords;
DROP POLICY IF EXISTS "bk_read_all"   ON blocked_keywords;
CREATE POLICY "bk_admin_all" ON blocked_keywords FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
-- Anyone can read (for client-side preview) — no harm
CREATE POLICY "bk_read_all"  ON blocked_keywords FOR SELECT TO anon, authenticated USING (active = TRUE);

CREATE OR REPLACE FUNCTION check_content_violations(p_text TEXT)
RETURNS JSONB
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_kw RECORD;
  v_violations JSONB := '[]'::jsonb;
  v_has_block BOOLEAN := FALSE;
BEGIN
  IF p_text IS NULL OR length(p_text) = 0 THEN
    RETURN jsonb_build_object('ok', TRUE, 'blocked', FALSE, 'violations', v_violations);
  END IF;
  FOR v_kw IN
    SELECT pattern, severity, reason, is_regex
      FROM blocked_keywords
     WHERE active = TRUE
  LOOP
    IF (v_kw.is_regex AND p_text ~* v_kw.pattern)
       OR (NOT v_kw.is_regex AND p_text ILIKE '%' || v_kw.pattern || '%')
    THEN
      v_violations := v_violations || jsonb_build_object(
        'pattern', v_kw.pattern, 'severity', v_kw.severity, 'reason', v_kw.reason
      );
      IF v_kw.severity = 'block' THEN
        v_has_block := TRUE;
      END IF;
    END IF;
  END LOOP;
  RETURN jsonb_build_object(
    'ok', NOT v_has_block,
    'blocked', v_has_block,
    'violations', v_violations
  );
END;
$$;

GRANT EXECUTE ON FUNCTION check_content_violations(TEXT) TO anon, authenticated;

-- =====================================================
-- 6. TRUSTED OWNER CHECK
-- =====================================================
-- Owner is "trusted" and can bypass re-review if:
--   • verified_score >= 4
--   • Shop was created >= 90 days ago
--   • No pending flags
-- =====================================================
CREATE OR REPLACE FUNCTION is_trusted_owner(p_business_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_trusted BOOLEAN := FALSE;
BEGIN
  SELECT (
    b.verified_score >= 4
    AND b.created_at <= NOW() - INTERVAL '90 days'
    AND NOT EXISTS (
      SELECT 1 FROM business_reports
       WHERE business_id = b.id AND resolved_at IS NULL
    )
  )
  INTO v_trusted
  FROM businesses b
  WHERE b.id = p_business_id;

  RETURN COALESCE(v_trusted, FALSE);
EXCEPTION WHEN OTHERS THEN
  RETURN FALSE;  -- defensive: if business_reports doesn't exist, treat as untrusted
END;
$$;

-- =====================================================
-- 7. update_my_business RPC
-- =====================================================
-- Owner-facing: patches whitelisted fields with safety guards.
--
-- Returns JSONB:
--   { ok: true, status: 'active' | 'pending_review',
--     fields_updated: [...], pending_fields: [...],
--     violations: [...] | null }
-- =====================================================
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
  v_fields_updated TEXT[] := '{}';
  v_pending_fields TEXT[] := '{}';
  v_violations     JSONB := '[]'::jsonb;
  v_check          JSONB;
  v_key            TEXT;
  v_new_val        TEXT;
  v_old_val        TEXT;
  v_combined_text  TEXT := '';
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
  v_status_before := v_old.status;

  -- ===== Step 1: Content keyword check on free-text fields =====
  v_combined_text := COALESCE(p_patch->>'name','')
                  || ' ' || COALESCE(p_patch->>'usp_text','')
                  || ' ' || COALESCE(p_patch->>'usp_hi','')
                  || ' ' || COALESCE(p_patch->>'about_text','');
  v_check := check_content_violations(v_combined_text);
  IF (v_check->>'blocked')::BOOLEAN THEN
    RAISE EXCEPTION 'Content blocked: %', v_check->'violations';
  END IF;
  v_violations := v_check->'violations';

  -- ===== Step 2: Check trusted owner =====
  v_trusted := is_trusted_owner(v_business_id);

  -- ===== Step 3: Apply each whitelisted field =====
  -- MINOR fields (instant — no re-review)
  IF p_patch ? 'hours_json' THEN
    UPDATE businesses SET hours_json = p_patch->'hours_json' WHERE id = v_business_id;
    v_fields_updated := v_fields_updated || 'hours_json';
  END IF;

  IF p_patch ? 'services_json' THEN
    UPDATE businesses SET services_json = p_patch->'services_json' WHERE id = v_business_id;
    v_fields_updated := v_fields_updated || 'services_json';
  END IF;

  IF p_patch ? 'faqs_json' THEN
    UPDATE businesses SET faqs_json = p_patch->'faqs_json' WHERE id = v_business_id;
    v_fields_updated := v_fields_updated || 'faqs_json';
  END IF;

  IF p_patch ? 'whatsapp' THEN
    v_new_val := NULLIF(trim(p_patch->>'whatsapp'), '');
    v_old_val := v_old.whatsapp;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old_val,'') THEN
      UPDATE businesses SET whatsapp = v_new_val WHERE id = v_business_id;
      INSERT INTO business_edits(business_id, field_name, old_value, new_value, edited_by, edited_role)
        VALUES (v_business_id, 'whatsapp', v_old_val, v_new_val, v_user_id, 'owner');
      v_fields_updated := v_fields_updated || 'whatsapp';
    END IF;
  END IF;

  IF p_patch ? 'email' THEN
    v_new_val := NULLIF(trim(p_patch->>'email'), '');
    v_old_val := v_old.email;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old_val,'') THEN
      UPDATE businesses SET email = v_new_val WHERE id = v_business_id;
      INSERT INTO business_edits(business_id, field_name, old_value, new_value, edited_by, edited_role)
        VALUES (v_business_id, 'email', v_old_val, v_new_val, v_user_id, 'owner');
      v_fields_updated := v_fields_updated || 'email';
    END IF;
  END IF;

  IF p_patch ? 'owner_name' THEN
    v_new_val := NULLIF(trim(p_patch->>'owner_name'), '');
    v_old_val := v_old.owner_name;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old_val,'') THEN
      UPDATE businesses SET owner_name = v_new_val WHERE id = v_business_id;
      INSERT INTO business_edits(business_id, field_name, old_value, new_value, edited_by, edited_role)
        VALUES (v_business_id, 'owner_name', v_old_val, v_new_val, v_user_id, 'owner');
      v_fields_updated := v_fields_updated || 'owner_name';
    END IF;
  END IF;

  -- SENSITIVE fields (re-review unless trusted)
  IF p_patch ? 'name' THEN
    v_new_val := NULLIF(trim(p_patch->>'name'), '');
    v_old_val := v_old.name;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old_val,'') THEN
      UPDATE businesses SET name = v_new_val WHERE id = v_business_id;
      v_sensitive_changed := TRUE;
      v_pending_fields := v_pending_fields || 'name';
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
      v_pending_fields := v_pending_fields || 'usp_text';
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
      v_pending_fields := v_pending_fields || 'usp_hi';
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
      v_pending_fields := v_pending_fields || 'about_text';
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
      v_pending_fields := v_pending_fields || 'address_line1';
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
      v_pending_fields := v_pending_fields || 'address_line2';
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
      v_pending_fields := v_pending_fields || 'pincode';
      INSERT INTO business_edits(business_id, field_name, old_value, new_value, is_sensitive, triggered_review, edited_by, edited_role)
        VALUES (v_business_id, 'pincode', v_old_val, v_new_val, TRUE, NOT v_trusted, v_user_id, 'owner');
    END IF;
  END IF;

  -- Photos (always sensitive — any change triggers review)
  IF p_patch ? 'photos' THEN
    DECLARE
      v_new_photos TEXT[];
      v_old_photos TEXT[] := COALESCE(v_old.photos, ARRAY[]::TEXT[]);
    BEGIN
      v_new_photos := ARRAY(SELECT jsonb_array_elements_text(p_patch->'photos'));
      IF v_new_photos IS DISTINCT FROM v_old_photos THEN
        UPDATE businesses SET photos = v_new_photos WHERE id = v_business_id;
        v_sensitive_changed := TRUE;
        v_pending_fields := v_pending_fields || 'photos';
        INSERT INTO business_edits(business_id, field_name, old_value, new_value, is_sensitive, triggered_review, edited_by, edited_role)
          VALUES (v_business_id, 'photos',
                  array_to_string(v_old_photos, ', '),
                  array_to_string(v_new_photos, ', '),
                  TRUE, NOT v_trusted, v_user_id, 'owner');
      END IF;
    END;
  END IF;

  -- ===== Step 4: Trigger re-review if sensitive changed and owner is NOT trusted =====
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

-- =====================================================
-- 8. REGISTER_BUSINESS HARDENING (1 shop per canonical mobile)
-- =====================================================
-- We wrap with a CHECK that runs BEFORE the existing register_business RPC.
-- Easiest: create check function called from register_business via modification.
-- Since modifying db/17 is intrusive, we add a separate guard function and
-- assume frontend OR a future register_business update calls it.
-- =====================================================
CREATE OR REPLACE FUNCTION check_can_register_mobile(p_mobile TEXT)
RETURNS JSONB
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_canon TEXT;
  v_count INT;
BEGIN
  v_canon := normalize_phone(p_mobile);
  IF v_canon IS NULL THEN
    RETURN jsonb_build_object('ok', FALSE, 'reason', 'Invalid mobile number');
  END IF;
  SELECT COUNT(*) INTO v_count
    FROM businesses
   WHERE canonical_mobile = v_canon
     AND status IN ('active','pending','pending_review','flagged');
  IF v_count >= 1 THEN
    RETURN jsonb_build_object('ok', FALSE, 'reason',
      'A shop with this mobile number is already registered. WhatsApp +91 9541223377 if you need help.');
  END IF;
  RETURN jsonb_build_object('ok', TRUE, 'reason', NULL);
END;
$$;

GRANT EXECUTE ON FUNCTION check_can_register_mobile(TEXT) TO anon, authenticated;

-- Add the same guard inside register_business by recreating it with the check.
-- We DROP+CREATE so the existing signature is preserved.
-- Note: this is an additive guard — the rest of the logic stays.
-- If db/17 changes the signature, this block needs to be rewritten.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc
     WHERE proname = 'register_business'
       AND pg_function_is_visible(oid)
  ) THEN
    -- Wrap by adding a CHECK before the actual logic.
    -- We do this by creating a "BEFORE" event trigger on businesses INSERT.
    NULL;
  END IF;
END $$;

-- Cleaner: add BEFORE INSERT trigger on businesses that enforces the rule
CREATE OR REPLACE FUNCTION trg_enforce_one_shop_per_mobile()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_canon TEXT;
  v_count INT;
BEGIN
  v_canon := normalize_phone(NEW.mobile);
  IF v_canon IS NULL THEN
    RAISE EXCEPTION 'Mobile number invalid — must be 10 digits starting with 6-9';
  END IF;
  -- Skip check if admin is inserting (e.g., bulk import) — admin RPCs use SECURITY DEFINER
  IF is_admin() THEN
    RETURN NEW;
  END IF;
  SELECT COUNT(*) INTO v_count
    FROM businesses
   WHERE canonical_mobile = v_canon
     AND status IN ('active','pending','pending_review','flagged');
  IF v_count >= 1 THEN
    RAISE EXCEPTION 'A shop with this mobile is already registered. Contact admin if you need to add another.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_biz_one_per_mobile ON businesses;
CREATE TRIGGER trg_biz_one_per_mobile
  BEFORE INSERT ON businesses
  FOR EACH ROW EXECUTE FUNCTION trg_enforce_one_shop_per_mobile();

-- =====================================================
-- 9. ADMIN: list_pending_review_edits
-- =====================================================
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
      'business_id',  b.id,
      'slug',         b.slug,
      'name',         b.name,
      'city_name',    gc.name,
      'status',       b.status,
      'updated_at',   b.updated_at,
      'recent_edits', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'field_name', be.field_name,
          'old_value',  be.old_value,
          'new_value',  be.new_value,
          'edited_at',  be.created_at
        ) ORDER BY be.created_at DESC)
        FROM (
          SELECT * FROM business_edits
           WHERE business_id = b.id
             AND triggered_review = TRUE
           ORDER BY created_at DESC
           LIMIT 10
        ) be
      ), '[]'::jsonb)
    ) AS row
    FROM businesses b
    LEFT JOIN geo_cities gc ON gc.id = b.city_id
    WHERE b.status = 'pending_review'
    ORDER BY b.updated_at DESC
    LIMIT GREATEST(1, LEAST(p_limit, 100))
    OFFSET GREATEST(0, p_offset)
  ) sub;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_pending_edits(INT, INT) TO authenticated;

-- =====================================================
-- 10. ADMIN: get edit history for one shop
-- =====================================================
DROP FUNCTION IF EXISTS admin_get_edit_history(UUID, INT);

CREATE OR REPLACE FUNCTION admin_get_edit_history(p_business_id UUID, p_limit INT DEFAULT 20)
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

  SELECT COALESCE(jsonb_agg(row ORDER BY (row->>'created_at') DESC), '[]'::jsonb)
    INTO v_result
    FROM (
      SELECT jsonb_build_object(
        'id',               id,
        'field_name',       field_name,
        'old_value',        CASE WHEN length(COALESCE(old_value,'')) > 200 THEN substr(old_value, 1, 200) || '…' ELSE old_value END,
        'new_value',        CASE WHEN length(COALESCE(new_value,'')) > 200 THEN substr(new_value, 1, 200) || '…' ELSE new_value END,
        'is_sensitive',     is_sensitive,
        'triggered_review', triggered_review,
        'edited_role',      edited_role,
        'created_at',       created_at
      ) AS row
      FROM business_edits
      WHERE business_id = p_business_id
      ORDER BY created_at DESC
      LIMIT GREATEST(1, LEAST(p_limit, 100))
    ) sub;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_get_edit_history(UUID, INT) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- VERIFY:
-- SELECT normalize_phone('+91 95412 23377');        -- '9541223377'
-- SELECT normalize_phone('09541223377');             -- '9541223377'
-- SELECT normalize_email('Deepak.Singla+test@gmail.com'); -- 'deepaksingla@gmail.com'
-- SELECT check_content_violations('Visit our website at https://spam.com');
-- SELECT check_can_register_mobile('9541223377');
-- SELECT admin_pending_edits(10, 0);
-- =====================================================
