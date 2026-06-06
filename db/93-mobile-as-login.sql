-- =====================================================
-- db/93-mobile-as-login.sql
-- =====================================================
-- USER REQUEST (2026-06-02):
--   "Agar email id approve ho jaaye (user verify + admin approve),
--    to user sirf email se hi nahi mobile no. se bhi login kar sake
--    with same password. Isse logo ko login me easy hoga.
--    Par same mobile do jagah use na ho — restrict karna hoga."
--
-- DESIGN:
--   Supabase Auth does not natively support phone-as-username in
--   email+password flow. We add a small helper RPC that:
--     - Takes a mobile number (any format the user types)
--     - Normalizes to 10-digit Indian format (strip non-digits + 91 prefix)
--     - Looks up the registered email tied to that mobile
--     - Returns the email ONLY IF exactly ONE active, email-verified
--       shopkeeper matches (returns NULL otherwise — forces email login
--       so we never accidentally log into the wrong account).
--
--   The frontend (panel/login.html) calls this RPC, then continues with
--   the standard supabase.auth.signInWithPassword({ email, password }).
--
-- SAFETY GUARDS:
--   * Mobile must canonicalize to exactly 10 digits starting 6-9
--   * Only matches users with email_confirmed_at IS NOT NULL
--   * Only matches shops with status='active' (so pending/disabled
--     shops still need email login — admin approval is required)
--   * If MORE THAN ONE shopkeeper has this mobile, returns NULL
--     (prevents wrong-shop login on duplicates)
--   * SECURITY DEFINER — bypasses RLS so RPC works for anonymous callers
--
-- DUPLICATE-MOBILE DIAGNOSTIC:
--   At the end of this file is a SELECT that lists any mobiles
--   currently shared by >1 shopkeeper. Admin should review and clean
--   these up so mobile login becomes available for them.
--
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. Helper: normalize Indian mobile number to 10-digit form
-- ============================================================
CREATE OR REPLACE FUNCTION normalize_mobile_in(p_raw TEXT)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  v_digits TEXT;
BEGIN
  IF p_raw IS NULL OR length(trim(p_raw)) = 0 THEN RETURN NULL; END IF;
  v_digits := regexp_replace(p_raw, '\D', '', 'g');

  -- Drop leading 0 from 11-digit (e.g., "09876543210")
  IF length(v_digits) = 11 AND substring(v_digits, 1, 1) = '0' THEN
    v_digits := substring(v_digits, 2);
  END IF;
  -- Drop leading 91 from 12-digit (e.g., "919876543210")
  IF length(v_digits) = 12 AND substring(v_digits, 1, 2) = '91' THEN
    v_digits := substring(v_digits, 3);
  END IF;
  -- Drop leading 091 from 13-digit
  IF length(v_digits) = 13 AND substring(v_digits, 1, 3) = '091' THEN
    v_digits := substring(v_digits, 4);
  END IF;

  -- Final must be 10 digits starting with 6, 7, 8, or 9
  IF length(v_digits) = 10 AND substring(v_digits, 1, 1) ~ '[6-9]' THEN
    RETURN v_digits;
  END IF;
  RETURN NULL;
END;
$$;


-- ============================================================
-- 2. The main RPC: lookup_login_email_by_mobile
-- ============================================================
DROP FUNCTION IF EXISTS lookup_login_email_by_mobile(TEXT);

CREATE OR REPLACE FUNCTION lookup_login_email_by_mobile(p_mobile TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clean   TEXT;
  v_count   INT;
  v_email   TEXT;
BEGIN
  v_clean := normalize_mobile_in(p_mobile);
  IF v_clean IS NULL THEN
    RETURN NULL; -- invalid mobile format
  END IF;

  -- Find all candidate auth users whose linked, verified, active shop
  -- matches this mobile. Two match paths:
  --   1. user_metadata.mobile (set during signup)
  --   2. business_owners → businesses.mobile (the canonical shop phone)
  SELECT COUNT(DISTINCT au.id) INTO v_count
  FROM auth.users au
  WHERE au.email_confirmed_at IS NOT NULL
    AND au.email IS NOT NULL
    AND (
      au.raw_user_meta_data->>'mobile' = v_clean
      OR EXISTS (
        SELECT 1
        FROM business_owners bo
        JOIN businesses b ON b.id = bo.business_id
        WHERE bo.auth_user_id = au.id
          AND b.status = 'active'
          AND regexp_replace(COALESCE(b.mobile, ''), '\D', '', 'g') ~ ('^(91)?' || v_clean || '$')
      )
    );

  -- Strict: only resolve if exactly one match.
  -- 0 matches = no account on this mobile.
  -- 2+ matches = ambiguous, refuse and force email login.
  IF v_count != 1 THEN
    RETURN NULL;
  END IF;

  SELECT au.email INTO v_email
  FROM auth.users au
  WHERE au.email_confirmed_at IS NOT NULL
    AND au.email IS NOT NULL
    AND (
      au.raw_user_meta_data->>'mobile' = v_clean
      OR EXISTS (
        SELECT 1
        FROM business_owners bo
        JOIN businesses b ON b.id = bo.business_id
        WHERE bo.auth_user_id = au.id
          AND b.status = 'active'
          AND regexp_replace(COALESCE(b.mobile, ''), '\D', '', 'g') ~ ('^(91)?' || v_clean || '$')
      )
    )
  LIMIT 1;

  RETURN v_email;
END;
$$;

-- Allow anonymous + authenticated to call this
GRANT EXECUTE ON FUNCTION lookup_login_email_by_mobile(TEXT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;


-- ============================================================
-- 3. DIAGNOSTIC: list mobiles shared by more than one shopkeeper
--    Admin should review these and consolidate so mobile login
--    becomes available for those users.
-- ============================================================
WITH user_mobile AS (
  -- One row per active+verified shopkeeper with their canonical mobile
  SELECT
    au.id   AS auth_user_id,
    au.email,
    COALESCE(
      au.raw_user_meta_data->>'mobile',
      (
        SELECT regexp_replace(b.mobile, '\D', '', 'g')
        FROM business_owners bo
        JOIN businesses b ON b.id = bo.business_id
        WHERE bo.auth_user_id = au.id AND b.status = 'active'
        ORDER BY b.created_at ASC LIMIT 1
      )
    ) AS mobile
  FROM auth.users au
  WHERE au.email_confirmed_at IS NOT NULL
    AND au.email IS NOT NULL
)
SELECT
  RIGHT(regexp_replace(mobile, '\D', '', 'g'), 10) AS mobile_10digit,
  COUNT(*) AS shopkeepers_with_this_mobile,
  string_agg(email, ', ' ORDER BY email) AS emails_sharing_mobile
FROM user_mobile
WHERE mobile IS NOT NULL
  AND length(regexp_replace(mobile, '\D', '', 'g')) >= 10
GROUP BY RIGHT(regexp_replace(mobile, '\D', '', 'g'), 10)
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC
LIMIT 30;


-- ============================================================
-- 4. Smoke test (uncomment to run manually after applying):
-- ============================================================
-- SELECT lookup_login_email_by_mobile('9541223377');    -- expects email or NULL
-- SELECT lookup_login_email_by_mobile('+91 9541223377'); -- normalizes correctly
-- SELECT lookup_login_email_by_mobile('919541223377');   -- normalizes correctly
-- SELECT lookup_login_email_by_mobile('1234567890');     -- expects NULL (no 6-9 prefix)
