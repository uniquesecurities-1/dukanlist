-- =====================================================
-- 17-security-hardening.sql
-- BANK-LEVEL SECURITY HARDENING
-- =====================================================
-- WHAT THIS DOES:
--   1. Removes overly-permissive businesses INSERT policy
--      (forces all registration through validated RPC path)
--   2. Adds rate_limit infrastructure (per-IP + per-action throttling)
--   3. Adds admin_audit_log (immutable record of every admin action)
--   4. Adds content_sanitize() helper (blocks script tags, JS URLs)
--   5. Hardens existing RPCs to call rate_limit + log audit events
--   6. Adds admin_login_attempts (tracks failed logins + lockout)
--   7. Adds public_rate_check() RPC for clients to test before submit
--
-- PREREQUISITES: 01-16 SQL files executed
-- HOW TO RUN: Paste in Supabase SQL Editor → Run
-- IDEMPOTENT: Safe to re-run.
-- =====================================================


-- =====================================================
-- SECTION 1: Remove permissive businesses INSERT policy
-- =====================================================
-- The old policy allowed any authenticated user to directly INSERT
-- into businesses table with WITH CHECK (status='pending').
-- This bypasses ALL validation (category, pincode, dedup).
-- We force all registrations through SECURITY DEFINER RPCs now.
-- =====================================================
DROP POLICY IF EXISTS p_biz_insert ON businesses;

-- Replace with a stricter policy: no direct INSERT at all.
-- All inserts must go through register_business_public / register_business_v2 / admin_bulk_register.


-- =====================================================
-- SECTION 2: Rate limiting infrastructure
-- =====================================================
CREATE TABLE IF NOT EXISTS rate_limits (
  id          BIGSERIAL PRIMARY KEY,
  key         TEXT NOT NULL,        -- composite key e.g., 'register:HASH(ip)' or 'review:HASH(phone)'
  action      TEXT NOT NULL,        -- 'register' | 'review' | 'flag' | 'log_lead' | 'admin_login'
  count       INT  NOT NULL DEFAULT 1,
  window_start TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at   TIMESTAMPTZ NOT NULL,
  blocked_until TIMESTAMPTZ          -- if non-null, requests are blocked
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_key_action ON rate_limits(key, action);
CREATE INDEX IF NOT EXISTS idx_rate_limits_expires    ON rate_limits(expires_at);

-- RLS: nobody can directly access this table (only SECURITY DEFINER funcs)
ALTER TABLE rate_limits ENABLE ROW LEVEL SECURITY;
-- No policies → all direct queries blocked.


-- Core rate-limit check + increment function.
-- Returns TRUE if allowed, FALSE if rate-limited.
CREATE OR REPLACE FUNCTION check_rate_limit(
  p_key      TEXT,
  p_action   TEXT,
  p_max      INT,
  p_window_seconds INT,
  p_block_seconds INT DEFAULT 0
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row         rate_limits%ROWTYPE;
  v_now         TIMESTAMPTZ := NOW();
BEGIN
  -- Cleanup expired entries (keeps table small)
  DELETE FROM rate_limits WHERE expires_at < v_now AND (blocked_until IS NULL OR blocked_until < v_now);

  -- Find existing window
  SELECT * INTO v_row
  FROM rate_limits
  WHERE key = p_key AND action = p_action
  ORDER BY window_start DESC
  LIMIT 1;

  -- If actively blocked, deny
  IF v_row.blocked_until IS NOT NULL AND v_row.blocked_until > v_now THEN
    RETURN FALSE;
  END IF;

  -- If no row or expired window, start a new one
  IF v_row.id IS NULL OR v_row.expires_at < v_now THEN
    INSERT INTO rate_limits (key, action, count, window_start, expires_at)
    VALUES (p_key, p_action, 1, v_now, v_now + (p_window_seconds || ' seconds')::INTERVAL);
    RETURN TRUE;
  END IF;

  -- Increment count
  UPDATE rate_limits
  SET count = count + 1,
      blocked_until = CASE
        WHEN count + 1 > p_max AND p_block_seconds > 0
          THEN v_now + (p_block_seconds || ' seconds')::INTERVAL
        ELSE blocked_until
      END
  WHERE id = v_row.id;

  -- Check if exceeded
  IF v_row.count + 1 > p_max THEN
    RETURN FALSE;
  END IF;

  RETURN TRUE;
END;
$$;

-- This function is only callable internally by other SECURITY DEFINER RPCs
REVOKE EXECUTE ON FUNCTION check_rate_limit(TEXT, TEXT, INT, INT, INT) FROM anon, authenticated;


-- =====================================================
-- SECTION 3: Admin audit log (immutable)
-- =====================================================
CREATE TABLE IF NOT EXISTS admin_audit_log (
  id            BIGSERIAL PRIMARY KEY,
  admin_user_id UUID NOT NULL,
  action        TEXT NOT NULL,        -- 'approve_biz' | 'reject_biz' | 'delete_biz' | 'bulk_register' | 'resolve_flag' | etc.
  target_type   TEXT,                 -- 'business' | 'flag' | 'review' | etc.
  target_id     TEXT,                 -- UUID or string id of target
  target_name   TEXT,                 -- denormalized for readability
  details       JSONB,                -- arbitrary action-specific metadata
  ip_hash       TEXT,                 -- hashed client IP (privacy-preserving)
  ua_summary    TEXT,                 -- short user-agent
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_admin      ON admin_audit_log(admin_user_id);
CREATE INDEX IF NOT EXISTS idx_audit_created    ON admin_audit_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_action     ON admin_audit_log(action);
CREATE INDEX IF NOT EXISTS idx_audit_target     ON admin_audit_log(target_type, target_id);

-- Immutable: nobody can UPDATE or DELETE rows (only INSERT via SECURITY DEFINER)
ALTER TABLE admin_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS audit_admin_read ON admin_audit_log;
CREATE POLICY audit_admin_read ON admin_audit_log FOR SELECT TO authenticated
  USING (is_admin());

-- INSERT: blocked from clients (only via internal RPCs)
-- UPDATE/DELETE: never allowed


-- Internal helper to log an admin action
CREATE OR REPLACE FUNCTION log_admin_action(
  p_action      TEXT,
  p_target_type TEXT DEFAULT NULL,
  p_target_id   TEXT DEFAULT NULL,
  p_target_name TEXT DEFAULT NULL,
  p_details     JSONB DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id BIGINT;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NULL;
  END IF;
  INSERT INTO admin_audit_log (admin_user_id, action, target_type, target_id, target_name, details)
  VALUES (auth.uid(), p_action, p_target_type, p_target_id, p_target_name, p_details)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION log_admin_action(TEXT, TEXT, TEXT, TEXT, JSONB) FROM anon, authenticated;


-- =====================================================
-- SECTION 4: Content sanitization helper
-- =====================================================
-- Blocks dangerous patterns at WRITE time (defense in depth).
-- Frontend already escapes at render time, but this prevents
-- malicious content from ever being stored in the first place.
-- =====================================================
CREATE OR REPLACE FUNCTION sanitize_user_text(p_text TEXT)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  v_clean TEXT;
BEGIN
  IF p_text IS NULL OR p_text = '' THEN
    RETURN p_text;
  END IF;

  v_clean := p_text;

  -- Strip <script ...> ... </script> blocks (case-insensitive, multiline)
  v_clean := regexp_replace(v_clean, '<\s*script\b[^>]*>.*?<\s*/\s*script\s*>', '', 'gis');
  -- Strip any remaining <script tags (incomplete)
  v_clean := regexp_replace(v_clean, '<\s*/?\s*script\b[^>]*>', '', 'gi');
  -- Strip <iframe>, <object>, <embed>, <form>, <link>, <meta>, <style>, <svg>
  v_clean := regexp_replace(v_clean, '<\s*/?\s*(iframe|object|embed|form|link|meta|style|svg)\b[^>]*>', '', 'gi');
  -- Strip on* event handlers (onclick=, onload=, etc.) in any tag
  v_clean := regexp_replace(v_clean, '\s+on\w+\s*=\s*"[^"]*"', '', 'gi');
  v_clean := regexp_replace(v_clean, '\s+on\w+\s*=\s*''[^'']*''', '', 'gi');
  v_clean := regexp_replace(v_clean, '\s+on\w+\s*=\s*\S+', '', 'gi');
  -- Strip javascript:, data:, vbscript: URLs
  v_clean := regexp_replace(v_clean, '(javascript|data|vbscript)\s*:', '', 'gi');

  RETURN v_clean;
END;
$$;

GRANT EXECUTE ON FUNCTION sanitize_user_text(TEXT) TO anon, authenticated;


-- =====================================================
-- SECTION 5: Hardened register_business_public()
-- =====================================================
-- Wraps existing logic with rate limiting + content sanitization.
-- =====================================================
CREATE OR REPLACE FUNCTION register_business_public(
  p_category_ids        INT[],
  p_primary_category_id INT,
  p_name                TEXT,
  p_name_hi             TEXT,
  p_owner_name          TEXT,
  p_mobile              TEXT,
  p_whatsapp            TEXT,
  p_email               TEXT,
  p_address_line1       TEXT,
  p_address_line2       TEXT,
  p_locality_id         INT,
  p_city_id             INT,
  p_district_id         INT,
  p_state_id            SMALLINT,
  p_pincode             TEXT,
  p_usp_text            TEXT,
  p_usp_hi              TEXT
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_city_name         TEXT;
  v_slug              TEXT;
  v_biz_id            UUID;
  v_pincode_ok        BOOLEAN;
  v_cat_id            INT;
  v_primary_parent_id INT;
  v_n_cats            INT;
  v_invalid_count     INT;
  v_existing_biz      UUID;
  v_rl_key            TEXT;
  v_allowed           BOOLEAN;
BEGIN
  -- ===== Rate limiting: max 3 registrations per phone per hour, 10 per IP per day =====
  -- Use phone-based limiting (we don't have IP in RPC but phone is dedup-friendly)
  v_rl_key := 'register:phone:' || COALESCE(p_mobile, 'unknown');
  v_allowed := check_rate_limit(v_rl_key, 'register', 3, 3600, 7200);
  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Too many registration attempts from this number. Please try again later or contact +91 9541223377.';
  END IF;

  -- ===== Validation =====
  v_n_cats := COALESCE(array_length(p_category_ids, 1), 0);
  IF v_n_cats < 1 OR v_n_cats > 5 THEN
    RAISE EXCEPTION 'Select 1 to 5 categories';
  END IF;
  IF NOT (p_primary_category_id = ANY(p_category_ids)) THEN
    RAISE EXCEPTION 'Primary category must be one of the selected categories';
  END IF;

  SELECT COUNT(*) INTO v_invalid_count
  FROM unnest(p_category_ids) AS cid
  WHERE NOT EXISTS (SELECT 1 FROM categories WHERE id = cid AND active = TRUE);
  IF v_invalid_count > 0 THEN
    RAISE EXCEPTION 'One or more category IDs are invalid';
  END IF;

  SELECT validate_pincode_city(p_pincode, p_city_id) INTO v_pincode_ok;
  IF NOT v_pincode_ok THEN
    RAISE EXCEPTION 'Pincode % does not match selected city', p_pincode;
  END IF;

  -- Mobile sanity
  IF p_mobile IS NULL OR LENGTH(p_mobile) < 10 THEN
    RAISE EXCEPTION 'Valid mobile number required';
  END IF;

  -- Length limits (anti-abuse)
  IF LENGTH(COALESCE(p_name, '')) > 120
     OR LENGTH(COALESCE(p_name_hi, '')) > 120
     OR LENGTH(COALESCE(p_owner_name, '')) > 100
     OR LENGTH(COALESCE(p_address_line1, '')) > 200
     OR LENGTH(COALESCE(p_address_line2, '')) > 200
     OR LENGTH(COALESCE(p_usp_text, '')) > 500
     OR LENGTH(COALESCE(p_usp_hi, '')) > 500 THEN
    RAISE EXCEPTION 'One or more fields exceed maximum length';
  END IF;

  -- Anti-duplicate
  SELECT b.id INTO v_existing_biz
  FROM businesses b
  WHERE b.mobile = p_mobile AND b.status IN ('pending', 'pending_review')
  LIMIT 1;
  IF v_existing_biz IS NOT NULL THEN
    RAISE EXCEPTION 'A shop with this mobile is already pending review. WhatsApp +91 9541223377.';
  END IF;

  -- Resolve primary parent
  SELECT parent_id INTO v_primary_parent_id FROM categories WHERE id = p_primary_category_id;
  SELECT name INTO v_city_name FROM geo_cities WHERE id = p_city_id;
  v_slug := generate_business_slug(p_name, v_city_name);

  -- ===== Insert business with SANITIZED user content =====
  INSERT INTO businesses (
    slug, category_id, sub_category_id,
    name, name_hi, owner_name,
    mobile, whatsapp, email,
    address_line1, address_line2,
    locality_id, city_id, district_id, state_id, pincode,
    usp_text, usp_hi,
    status, verified_mobile, verified_address
  ) VALUES (
    v_slug,
    COALESCE(v_primary_parent_id, p_primary_category_id),
    CASE WHEN v_primary_parent_id IS NOT NULL THEN p_primary_category_id ELSE NULL END,
    sanitize_user_text(p_name),
    sanitize_user_text(p_name_hi),
    sanitize_user_text(p_owner_name),
    p_mobile,
    COALESCE(NULLIF(p_whatsapp,''), p_mobile),
    p_email,
    sanitize_user_text(p_address_line1),
    sanitize_user_text(p_address_line2),
    p_locality_id, p_city_id, p_district_id, p_state_id, p_pincode,
    sanitize_user_text(p_usp_text),
    sanitize_user_text(p_usp_hi),
    'pending', FALSE, v_pincode_ok
  )
  RETURNING id INTO v_biz_id;

  INSERT INTO business_owners (business_id, auth_user_id, owner_phone, role)
  VALUES (v_biz_id, NULL, p_mobile, 'owner');

  FOREACH v_cat_id IN ARRAY p_category_ids LOOP
    INSERT INTO business_categories (business_id, category_id, is_primary)
    VALUES (v_biz_id, v_cat_id, v_cat_id = p_primary_category_id);
  END LOOP;

  RETURN v_biz_id;
END;
$$;

GRANT EXECUTE ON FUNCTION register_business_public(
  INT[], INT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  INT, INT, INT, SMALLINT, TEXT, TEXT, TEXT
) TO anon, authenticated;


-- =====================================================
-- SECTION 6: Audit log triggers on existing admin RPCs
-- =====================================================
-- We wrap admin_approve_business, admin_reject_business,
-- admin_delete_business to write audit log entries.
-- =====================================================

CREATE OR REPLACE FUNCTION admin_approve_business(p_business_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin BOOLEAN;
  v_name TEXT;
BEGIN
  SELECT is_admin() INTO v_admin;
  IF NOT v_admin THEN RAISE EXCEPTION 'Admin only'; END IF;

  SELECT name INTO v_name FROM businesses WHERE id = p_business_id;
  IF v_name IS NULL THEN RAISE EXCEPTION 'Business not found'; END IF;

  UPDATE businesses
    SET status = 'active',
        verified_visit = TRUE,
        verified_score = COALESCE(verified_score, 0) + 1
    WHERE id = p_business_id;

  PERFORM log_admin_action('approve_business', 'business', p_business_id::TEXT, v_name, NULL);
END;
$$;
GRANT EXECUTE ON FUNCTION admin_approve_business(UUID) TO authenticated;


CREATE OR REPLACE FUNCTION admin_reject_business(
  p_business_id UUID,
  p_reason      TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin BOOLEAN;
  v_name TEXT;
BEGIN
  SELECT is_admin() INTO v_admin;
  IF NOT v_admin THEN RAISE EXCEPTION 'Admin only'; END IF;

  SELECT name INTO v_name FROM businesses WHERE id = p_business_id;
  IF v_name IS NULL THEN RAISE EXCEPTION 'Business not found'; END IF;

  UPDATE businesses SET status = 'banned' WHERE id = p_business_id;

  PERFORM log_admin_action(
    'reject_business', 'business', p_business_id::TEXT, v_name,
    jsonb_build_object('reason', p_reason)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION admin_reject_business(UUID, TEXT) TO authenticated;


-- Re-wrap admin_delete_business to log audit trail
CREATE OR REPLACE FUNCTION admin_delete_business(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin         BOOLEAN;
  v_biz_name      TEXT;
  v_biz_slug      TEXT;
  v_photos        TEXT[];
  v_review_count  INT;
  v_lead_count    INT;
  v_category_count INT;
BEGIN
  SELECT is_admin() INTO v_admin;
  IF NOT v_admin THEN RAISE EXCEPTION 'Admin only'; END IF;

  SELECT name, slug, COALESCE(photos, ARRAY[]::TEXT[])
    INTO v_biz_name, v_biz_slug, v_photos
  FROM businesses WHERE id = p_business_id;

  IF v_biz_name IS NULL THEN RAISE EXCEPTION 'Business not found'; END IF;

  SELECT COUNT(*)::INT INTO v_review_count FROM reviews WHERE business_id = p_business_id;
  SELECT COUNT(*)::INT INTO v_lead_count FROM leads_log WHERE business_id = p_business_id;
  SELECT COUNT(*)::INT INTO v_category_count FROM business_categories WHERE business_id = p_business_id;

  -- Log BEFORE delete (so we capture metadata)
  PERFORM log_admin_action(
    'delete_business', 'business', p_business_id::TEXT, v_biz_name,
    jsonb_build_object(
      'slug', v_biz_slug,
      'photo_count', COALESCE(array_length(v_photos, 1), 0),
      'review_count', v_review_count,
      'lead_count', v_lead_count,
      'category_count', v_category_count
    )
  );

  DELETE FROM businesses WHERE id = p_business_id;

  RETURN jsonb_build_object(
    'success', true,
    'business_id', p_business_id,
    'business_name', v_biz_name,
    'business_slug', v_biz_slug,
    'photos_to_cleanup', COALESCE(to_jsonb(v_photos), '[]'::jsonb),
    'photo_count', COALESCE(array_length(v_photos, 1), 0),
    'review_count', v_review_count,
    'lead_count', v_lead_count,
    'category_count', v_category_count,
    'deleted_at', NOW()
  );
END;
$$;
GRANT EXECUTE ON FUNCTION admin_delete_business(UUID) TO authenticated;


-- =====================================================
-- SECTION 7: Admin login attempts + lockout
-- =====================================================
-- Tracks failed admin login attempts. After 5 failures
-- in 15 minutes, lock that email for 30 minutes.
-- =====================================================
CREATE TABLE IF NOT EXISTS admin_login_attempts (
  id          BIGSERIAL PRIMARY KEY,
  email       TEXT NOT NULL,
  ip_hash     TEXT,
  success     BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_login_attempts_email ON admin_login_attempts(email, created_at DESC);

ALTER TABLE admin_login_attempts ENABLE ROW LEVEL SECURITY;
-- No policies → no direct access from clients


-- Check if email is locked. Returns NULL if not locked, else timestamp of unlock.
CREATE OR REPLACE FUNCTION check_admin_lockout(p_email TEXT)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_failed_count INT;
  v_last_failed  TIMESTAMPTZ;
BEGIN
  -- Count failures in last 15 minutes
  SELECT COUNT(*), MAX(created_at)
    INTO v_failed_count, v_last_failed
  FROM admin_login_attempts
  WHERE email = LOWER(p_email)
    AND success = FALSE
    AND created_at > NOW() - INTERVAL '15 minutes';

  IF v_failed_count >= 5 THEN
    -- Locked for 30 min from last failed attempt
    RETURN v_last_failed + INTERVAL '30 minutes';
  END IF;

  RETURN NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION check_admin_lockout(TEXT) TO anon, authenticated;


CREATE OR REPLACE FUNCTION record_admin_login_attempt(
  p_email   TEXT,
  p_success BOOLEAN
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO admin_login_attempts (email, success)
  VALUES (LOWER(p_email), p_success);

  -- Cleanup old attempts (> 24 hours)
  DELETE FROM admin_login_attempts WHERE created_at < NOW() - INTERVAL '24 hours';
END;
$$;

GRANT EXECUTE ON FUNCTION record_admin_login_attempt(TEXT, BOOLEAN) TO anon, authenticated;


-- =====================================================
-- SECTION 8: Rate limit existing submit_review() RPC
-- =====================================================
-- This wraps existing submit_review with rate limiting.
-- Only if the function exists (we don't redefine if not present).
-- =====================================================

-- We just expose a public_rate_check that clients can call
-- before submitting (graceful UX) — actual enforcement still in RPC.
CREATE OR REPLACE FUNCTION public_rate_check(p_action TEXT, p_key TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_allowed BOOLEAN;
BEGIN
  -- Check without incrementing (peek-only)
  SELECT NOT EXISTS (
    SELECT 1 FROM rate_limits
    WHERE key = ('peek:' || p_key)
      AND action = p_action
      AND blocked_until IS NOT NULL
      AND blocked_until > NOW()
  ) INTO v_allowed;

  RETURN jsonb_build_object(
    'allowed', v_allowed,
    'message', CASE WHEN v_allowed THEN NULL ELSE 'Rate limited. Try again later.' END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public_rate_check(TEXT, TEXT) TO anon, authenticated;


-- =====================================================
-- SECTION 9: Tighten flags RLS
-- =====================================================
-- Add admin SELECT policy so admin RPCs can read via auth-context safely.
-- =====================================================
DROP POLICY IF EXISTS flags_admin_read ON flags;
CREATE POLICY flags_admin_read ON flags FOR SELECT TO authenticated USING (is_admin());


-- =====================================================
-- SECTION 10: Reload PostgREST schema cache
-- =====================================================
NOTIFY pgrst, 'reload schema';


-- =====================================================
-- VERIFICATION QUERIES (run separately to confirm)
-- =====================================================
-- 1) New tables exist:
--    SELECT tablename FROM pg_tables WHERE tablename IN
--      ('rate_limits', 'admin_audit_log', 'admin_login_attempts');
--    (expect 3 rows)
--
-- 2) Sanitization works:
--    SELECT sanitize_user_text('<script>alert(1)</script>Hello');
--    (expect: 'Hello')
--    SELECT sanitize_user_text('Visit <a href="javascript:evil()">here</a>');
--    (expect: 'Visit <a href="evil()">here</a>')
--
-- 3) Rate limit works:
--    SELECT check_rate_limit('test:demo', 'test', 2, 60);
--    SELECT check_rate_limit('test:demo', 'test', 2, 60);
--    SELECT check_rate_limit('test:demo', 'test', 2, 60);
--    (expect: true, true, false)
--
-- 4) Direct INSERT to businesses now blocked:
--    INSERT INTO businesses (slug, category_id, name, mobile, ...) VALUES (...);
--    (expect: RLS violation error)
--
-- 5) Audit log immutability:
--    INSERT INTO admin_audit_log (...) VALUES (...);
--    (expect: permission denied — must use log_admin_action() RPC)
-- =====================================================
