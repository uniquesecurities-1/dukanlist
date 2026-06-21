-- ============================================================
-- db/176 — Public self-serve Golden Pages + Report/Flag
-- ============================================================
-- USER ARCHITECTURE (clarified):
--   - DukanList main   = ADMIN-only entry (curated, email-verified)
--   - Golden Pages     = ANYONE self-serve (no email, super easy)
--   - Fake data        = handled via Report/Flag → admin review/delete
--   - Promote (GP→DL)  = admin button on contact from owner
--
-- THIS MIGRATION ADDS:
--   1. public_gp_self_add        — anyone can submit a listing to GP
--   2. gp_self_add_log table     — rate limiting + audit
--   3. gp_flag_listing           — public report endpoint
--   4. gp_flags table            — moderation queue for admin
--   5. admin_gp_review_flags     — admin view of open flags
--   6. admin_gp_dismiss_flag     — admin clears a flag
-- ============================================================

BEGIN;

-- ============================================================
-- PART 1: Rate-limit / audit table for public self-adds
-- ============================================================
CREATE TABLE IF NOT EXISTS gp_self_add_log (
  id           BIGSERIAL PRIMARY KEY,
  business_id  UUID REFERENCES businesses(id) ON DELETE SET NULL,
  ip_hash      TEXT,          -- hashed IP (privacy-friendly counter)
  mobile       TEXT,
  email        TEXT,
  user_agent   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_gp_self_add_log_ip     ON gp_self_add_log(ip_hash, created_at);
CREATE INDEX IF NOT EXISTS idx_gp_self_add_log_mobile ON gp_self_add_log(mobile);
CREATE INDEX IF NOT EXISTS idx_gp_self_add_log_when   ON gp_self_add_log(created_at DESC);

-- Lock down direct table access; only RPCs touch it
ALTER TABLE gp_self_add_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS p_gp_self_log_admin ON gp_self_add_log;
CREATE POLICY p_gp_self_log_admin ON gp_self_add_log
  FOR SELECT TO authenticated USING (is_admin());


-- ============================================================
-- PART 2: gp_flags table — public can report; admin reviews
-- ============================================================
CREATE TABLE IF NOT EXISTS gp_flags (
  id           BIGSERIAL PRIMARY KEY,
  business_id  UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  reason       TEXT NOT NULL,            -- 'fake' | 'wrong-info' | 'spam' | 'closed' | 'duplicate' | 'other'
  notes        TEXT,
  reporter_ip_hash TEXT,
  reporter_email   TEXT,
  status       TEXT NOT NULL DEFAULT 'open',  -- 'open' | 'resolved' | 'dismissed'
  resolved_by  TEXT,                      -- admin email
  resolved_at  TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_gp_flags_biz    ON gp_flags(business_id);
CREATE INDEX IF NOT EXISTS idx_gp_flags_status ON gp_flags(status, created_at DESC);

ALTER TABLE gp_flags ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS p_gp_flags_admin ON gp_flags;
CREATE POLICY p_gp_flags_admin ON gp_flags
  FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());


-- ============================================================
-- PART 3: RPC public_gp_self_add
-- ============================================================
-- Anyone (anon or authenticated) can call this. Rate-limited.
-- - Honeypot field (p_honeypot must be empty)
-- - Per-IP max 5 in last 1 hour
-- - Per-mobile uniqueness already enforced by businesses table check
-- ============================================================
CREATE OR REPLACE FUNCTION public_gp_self_add(
  p_name                  TEXT,
  p_category_slug         TEXT,
  p_city_id               INT,
  p_area                  TEXT DEFAULT NULL,
  p_mobile                TEXT DEFAULT NULL,
  p_name_hi               TEXT DEFAULT NULL,
  p_owner_name            TEXT DEFAULT NULL,
  p_email                 TEXT DEFAULT NULL,   -- optional, NOT used for auth
  p_honeypot              TEXT DEFAULT NULL,   -- must be empty (bot trap)
  p_ip_hash               TEXT DEFAULT NULL,   -- client-supplied (we hash again)
  p_user_agent            TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_norm_mobile      TEXT;
  v_slug             TEXT;
  v_token            TEXT;
  v_business_id      UUID;
  v_city_id          INT;
  v_district_id      INT;
  v_state_id         SMALLINT;
  v_pincode          TEXT;
  v_primary_cat_id   INT;
  v_primary_parent   INT;
  v_primary_is_sub   BOOLEAN := FALSE;
  v_ip_hash          TEXT;
  v_recent_count     INT;
  v_clean_owner      TEXT;
  v_clean_name       TEXT;
BEGIN
  -- HONEYPOT — bots fill all fields; humans skip the hidden one
  IF p_honeypot IS NOT NULL AND LENGTH(TRIM(p_honeypot)) > 0 THEN
    -- Pretend success to confuse the bot, but don't actually insert
    RETURN jsonb_build_object('success', TRUE, 'bot_blocked', TRUE);
  END IF;

  -- Basic validation
  v_clean_name := TRIM(COALESCE(p_name, ''));
  IF LENGTH(v_clean_name) < 2 THEN
    RAISE EXCEPTION 'Name is required (min 2 characters)';
  END IF;
  IF LENGTH(v_clean_name) > 120 THEN
    RAISE EXCEPTION 'Name too long (max 120 characters)';
  END IF;

  IF p_category_slug IS NULL OR LENGTH(TRIM(p_category_slug)) = 0 THEN
    RAISE EXCEPTION 'Please pick a category';
  END IF;

  IF p_city_id IS NULL THEN
    RAISE EXCEPTION 'Please pick a city';
  END IF;

  -- Rate limit: max 5 self-adds per IP per hour
  v_ip_hash := COALESCE(NULLIF(p_ip_hash, ''), 'anon');
  SELECT COUNT(*) INTO v_recent_count
    FROM gp_self_add_log
   WHERE ip_hash = v_ip_hash
     AND created_at > NOW() - INTERVAL '1 hour';
  IF v_recent_count >= 5 THEN
    RAISE EXCEPTION 'You have added too many listings recently. Please try again in an hour.';
  END IF;

  -- Validate mobile if provided
  IF p_mobile IS NOT NULL AND LENGTH(TRIM(p_mobile)) > 0 THEN
    v_norm_mobile := norm_indian_mobile(p_mobile);
    IF v_norm_mobile IS NULL THEN
      RAISE EXCEPTION 'Mobile must be a valid 10-digit Indian number';
    END IF;
    IF EXISTS (SELECT 1 FROM businesses WHERE mobile = v_norm_mobile) THEN
      RAISE EXCEPTION 'A listing with this mobile number already exists. Please search before adding.';
    END IF;
  END IF;

  -- Resolve category
  SELECT id, parent_id INTO v_primary_cat_id, v_primary_parent
    FROM categories WHERE slug = LOWER(TRIM(p_category_slug)) AND active = TRUE LIMIT 1;
  IF v_primary_cat_id IS NULL THEN
    RAISE EXCEPTION 'Invalid category';
  END IF;
  v_primary_is_sub := (v_primary_parent IS NOT NULL);

  -- Resolve city → district → pincode (same pattern as admin_soft_add_shop)
  v_city_id := p_city_id;
  SELECT c.district_id, d.state_id, COALESCE(c.pincodes[1], '000000')
    INTO v_district_id, v_state_id, v_pincode
    FROM geo_cities c
    JOIN geo_districts d ON d.id = c.district_id
   WHERE c.id = v_city_id AND c.active = TRUE
   LIMIT 1;
  IF v_district_id IS NULL THEN
    RAISE EXCEPTION 'Invalid city';
  END IF;

  v_clean_owner := NULLIF(TRIM(COALESCE(p_owner_name, '')), '');
  v_slug   := generate_unique_slug(v_clean_name || COALESCE(' ' || TRIM(p_area), ''));
  v_token  := encode(extensions.gen_random_bytes(20), 'hex');

  -- Insert as soft_listed (Golden Pages only) — claim_status starts unclaimed
  INSERT INTO businesses (
    slug, name, name_hi, owner_name, mobile, whatsapp,
    category_id, sub_category_id,
    city_id, district_id, state_id, pincode,
    address_line1,
    status, claim_status,
    pre_listed_by, pre_listed_at,
    consent_method, consent_notes,
    claim_token,
    created_at, updated_at
  ) VALUES (
    v_slug, v_clean_name,
    NULLIF(TRIM(COALESCE(p_name_hi,'')),''),
    v_clean_owner,
    v_norm_mobile, v_norm_mobile,
    CASE WHEN v_primary_is_sub THEN v_primary_parent ELSE v_primary_cat_id END,
    CASE WHEN v_primary_is_sub THEN v_primary_cat_id ELSE NULL END,
    v_city_id, v_district_id, v_state_id, v_pincode,
    COALESCE(NULLIF(TRIM(p_area), ''), ''),
    'soft_listed', 'unclaimed',
    'self-serve',
    NOW(),
    'self-add', LEFT(COALESCE(p_user_agent, ''), 200),
    v_token,
    NOW(), NOW()
  )
  RETURNING id INTO v_business_id;

  -- Link category in junction
  INSERT INTO business_categories (business_id, category_id, is_primary)
  VALUES (v_business_id, v_primary_cat_id, TRUE)
  ON CONFLICT DO NOTHING;

  -- Audit log
  INSERT INTO gp_self_add_log (business_id, ip_hash, mobile, email, user_agent)
  VALUES (v_business_id, v_ip_hash, v_norm_mobile, NULLIF(TRIM(LOWER(p_email)), ''), LEFT(COALESCE(p_user_agent,''),200));

  RETURN jsonb_build_object(
    'success',      TRUE,
    'business_id',  v_business_id,
    'slug',         v_slug,
    'name',         v_clean_name,
    'gp_url',       'https://dukanlist.com/golden-pages.html#shop=' || v_slug,
    'claim_token',  v_token,
    'claim_url',    'https://dukanlist.com/claim.html?token=' || v_token
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public_gp_self_add(TEXT, TEXT, INT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;


-- ============================================================
-- PART 4: RPC gp_flag_listing — public report
-- ============================================================
CREATE OR REPLACE FUNCTION gp_flag_listing(
  p_business_id UUID,
  p_reason      TEXT,
  p_notes       TEXT DEFAULT NULL,
  p_email       TEXT DEFAULT NULL,
  p_ip_hash     TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reason TEXT;
  v_count  INT;
  v_flag_id BIGINT;
BEGIN
  v_reason := LOWER(NULLIF(TRIM(COALESCE(p_reason,'')), ''));
  IF v_reason IS NULL OR v_reason NOT IN ('fake','wrong-info','spam','closed','duplicate','other') THEN
    RAISE EXCEPTION 'Invalid reason';
  END IF;

  -- Verify the listing exists
  IF NOT EXISTS (SELECT 1 FROM businesses WHERE id = p_business_id) THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  -- Light spam guard: 1 IP can't report the same listing more than 3 times
  IF p_ip_hash IS NOT NULL THEN
    SELECT COUNT(*) INTO v_count FROM gp_flags
      WHERE business_id = p_business_id
        AND reporter_ip_hash = p_ip_hash
        AND created_at > NOW() - INTERVAL '24 hours';
    IF v_count >= 3 THEN
      -- Silent OK so reporter doesn't realize they're rate-limited
      RETURN jsonb_build_object('success', TRUE, 'duplicate', TRUE);
    END IF;
  END IF;

  INSERT INTO gp_flags (business_id, reason, notes, reporter_ip_hash, reporter_email)
  VALUES (
    p_business_id, v_reason,
    NULLIF(LEFT(TRIM(COALESCE(p_notes,'')), 500), ''),
    COALESCE(NULLIF(p_ip_hash,''), 'anon'),
    NULLIF(LOWER(TRIM(COALESCE(p_email,''))), '')
  )
  RETURNING id INTO v_flag_id;

  RETURN jsonb_build_object(
    'success',  TRUE,
    'flag_id',  v_flag_id,
    'message',  'Thanks — our team will review this listing.'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION gp_flag_listing(UUID, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;


-- ============================================================
-- PART 5: Admin RPCs to review + resolve flags
-- ============================================================
CREATE OR REPLACE FUNCTION admin_gp_review_flags(
  p_status TEXT DEFAULT 'open',
  p_limit  INT  DEFAULT 100
)
RETURNS TABLE (
  flag_id          BIGINT,
  business_id      UUID,
  business_name    TEXT,
  business_slug    TEXT,
  business_status  TEXT,
  reason           TEXT,
  notes            TEXT,
  reporter_email   TEXT,
  flagged_at       TIMESTAMPTZ,
  flag_status      TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  RETURN QUERY
  SELECT
    f.id, b.id, b.name, b.slug, b.status,
    f.reason, f.notes, f.reporter_email, f.created_at, f.status
  FROM gp_flags f
  JOIN businesses b ON b.id = f.business_id
  WHERE (p_status IS NULL OR f.status = p_status)
  ORDER BY f.created_at DESC
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_gp_review_flags(TEXT, INT) TO authenticated;


CREATE OR REPLACE FUNCTION admin_gp_resolve_flag(
  p_flag_id BIGINT,
  p_action  TEXT  -- 'dismissed' | 'resolved'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_email TEXT;
  v_action      TEXT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  v_action := LOWER(TRIM(COALESCE(p_action,'')));
  IF v_action NOT IN ('dismissed','resolved') THEN
    RAISE EXCEPTION 'Invalid action: %', v_action;
  END IF;

  SELECT email INTO v_admin_email FROM admin_users WHERE auth_user_id = auth.uid();

  UPDATE gp_flags
     SET status = v_action,
         resolved_by = v_admin_email,
         resolved_at = NOW()
   WHERE id = p_flag_id;

  RETURN jsonb_build_object('success', TRUE, 'action', v_action);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_gp_resolve_flag(BIGINT, TEXT) TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/176 installed. Public self-add + flag/report ready.';
END $$;
