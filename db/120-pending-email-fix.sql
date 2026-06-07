-- =====================================================
-- db/120-pending-email-fix.sql
-- =====================================================
-- USER ISSUE (2026-06-07):
--   Admin moderation "Pending email verification" me wahi shop dikh raha hai
--   jiska user actually email verify kar chuka hai
--   (e.g. abc / navneet.nivesheasy@gmail.com).
--
-- ROOT CAUSE:
--   business_has_verified_owner(b.id) sirf business_owners.auth_user_id link
--   ke through verify karta hai. Agar user ne mobile-first signup kiya tha
--   aur baad me email verify ki, lekin business_owners.auth_user_id update
--   nahi hua, toh function FALSE return karta hai aur shop pending list me
--   reh jaata hai.
--
-- FIX:
--   Naya helper `business_email_verified_anywhere(b.id)` jo do checks karta hai:
--     1. Standard business_has_verified_owner() (existing path)
--     2. Email-match fallback: agar auth.users me koi row hai jiska email
--        match karta hai login_email / business email / business_owners email
--        AND uska email_confirmed_at IS NOT NULL → verified maana jaye.
--
--   Phir count + list dono RPC ko update karte hain is new helper se.
--   Plus: bonus auto-heal — jab list call hoti hai, missing auth_user_id
--   ko silently fill kar diya jaata hai (idempotent).
--
-- DEPLOY:
--   Supabase Dashboard → SQL Editor → paste this whole file → Run
-- =====================================================

BEGIN;

-- =====================================================
-- 1. New comprehensive verification check
-- =====================================================
CREATE OR REPLACE FUNCTION business_email_verified_anywhere(p_business_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_verified BOOLEAN := FALSE;
BEGIN
  -- Path 1: standard auth_user_id link
  IF business_has_verified_owner(p_business_id) THEN
    RETURN TRUE;
  END IF;

  -- Path 2: email-match fallback — koi bhi auth.users row jiska email
  -- match karta hai aur confirmed hai
  SELECT EXISTS (
    SELECT 1
    FROM auth.users u
    WHERE u.email_confirmed_at IS NOT NULL
      AND LOWER(u.email::TEXT) IN (
        -- Login email from business_owners (if any)
        SELECT LOWER(NULLIF(bo.email_at_signup, '')::TEXT)
          FROM business_owners bo WHERE bo.business_id = p_business_id
        UNION
        -- Shop business email
        SELECT LOWER(NULLIF(b.email, '')::TEXT)
          FROM businesses b WHERE b.id = p_business_id
      )
  ) INTO v_verified;

  RETURN COALESCE(v_verified, FALSE);
END $$;

GRANT EXECUTE ON FUNCTION business_email_verified_anywhere(UUID) TO anon, authenticated;


-- =====================================================
-- 2. Self-heal: missing auth_user_id link populate karo
--    (idempotent — sirf NULL ko fill karta hai)
-- =====================================================
CREATE OR REPLACE FUNCTION self_heal_owner_links_by_email()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_fixed INT := 0;
BEGIN
  -- Match business_owners rows with auth.users via email_at_signup
  WITH heal AS (
    UPDATE business_owners bo
       SET auth_user_id = u.id
      FROM auth.users u
     WHERE bo.auth_user_id IS NULL
       AND u.email_confirmed_at IS NOT NULL
       AND LOWER(u.email::TEXT) = LOWER(bo.email_at_signup::TEXT)
       AND NULLIF(bo.email_at_signup, '') IS NOT NULL
    RETURNING bo.business_id
  )
  SELECT COUNT(*) INTO v_fixed FROM heal;

  RETURN v_fixed;
END $$;

GRANT EXECUTE ON FUNCTION self_heal_owner_links_by_email() TO authenticated;


-- =====================================================
-- 3. Update LIST RPC to use new helper + run self-heal first
-- =====================================================
DROP FUNCTION IF EXISTS admin_pending_email_list_v2(INT, INT);

CREATE OR REPLACE FUNCTION admin_pending_email_list_v2(
  p_limit  INT DEFAULT 100,
  p_offset INT DEFAULT 0
)
RETURNS TABLE (
  business_id        UUID,
  business_name      TEXT,
  owner_name         TEXT,
  mobile             TEXT,
  whatsapp           TEXT,
  login_email        TEXT,
  business_email     TEXT,
  city_name          TEXT,
  primary_cat        TEXT,
  created_at         TIMESTAMPTZ,
  days_since_signup  INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_role   TEXT;
  v_cities INT[];
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  -- Auto-heal links before listing (idempotent, fast)
  PERFORM self_heal_owner_links_by_email();

  SELECT role, assigned_city_ids INTO v_role, v_cities
  FROM admin_users
  WHERE auth_user_id = auth.uid()
  LIMIT 1;

  RETURN QUERY
  SELECT
    b.id                                                            AS business_id,
    COALESCE(b.name::TEXT,       '(unnamed)')                        AS business_name,
    COALESCE(b.owner_name::TEXT, '')                                 AS owner_name,
    COALESCE(b.mobile::TEXT,     '')                                 AS mobile,
    COALESCE(b.whatsapp::TEXT,   '')                                 AS whatsapp,
    COALESCE(u.email::TEXT,      '')                                 AS login_email,
    COALESCE(b.email::TEXT,      '')                                 AS business_email,
    COALESCE(c.name::TEXT,       '')                                 AS city_name,
    COALESCE(cat.name::TEXT,     '')                                 AS primary_cat,
    b.created_at                                                     AS created_at,
    EXTRACT(DAY FROM (NOW() - b.created_at))::INT                    AS days_since_signup
  FROM businesses b
  LEFT JOIN business_owners bo ON bo.business_id = b.id
  LEFT JOIN auth.users      u  ON u.id = bo.auth_user_id
  LEFT JOIN geo_cities      c  ON c.id = b.city_id
  LEFT JOIN categories      cat ON cat.id = COALESCE(b.sub_category_id, b.category_id)
  WHERE
    b.status::TEXT = 'pending'
    AND b.email_gate_at_signup = TRUE
    AND NOT business_email_verified_anywhere(b.id)
    AND (
      v_role IN ('admin','super_admin')
      OR (v_cities IS NOT NULL AND b.city_id = ANY(v_cities))
    )
  ORDER BY b.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END $$;

GRANT EXECUTE ON FUNCTION admin_pending_email_list_v2(INT, INT) TO authenticated;


-- =====================================================
-- 4. Update COUNT RPC to use the same comprehensive check
--    (taki badge count list rows ke saath consistent rahe)
-- =====================================================
CREATE OR REPLACE FUNCTION admin_pending_awaiting_email_count()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_role   TEXT;
  v_cities INT[];
  v_count  INT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  -- Auto-heal before counting (idempotent)
  PERFORM self_heal_owner_links_by_email();

  SELECT role, assigned_city_ids INTO v_role, v_cities
  FROM admin_users
  WHERE auth_user_id = auth.uid()
  LIMIT 1;

  SELECT COUNT(*) INTO v_count
  FROM businesses b
  WHERE b.status::TEXT = 'pending'
    AND b.email_gate_at_signup = TRUE
    AND NOT business_email_verified_anywhere(b.id)
    AND (
      v_role IN ('admin','super_admin')
      OR (v_cities IS NOT NULL AND b.city_id = ANY(v_cities))
    );

  RETURN COALESCE(v_count, 0);
END $$;

GRANT EXECUTE ON FUNCTION admin_pending_awaiting_email_count() TO authenticated;


COMMIT;

-- =====================================================
-- Verify (optional):
-- SELECT self_heal_owner_links_by_email();  -- run once manually
-- SELECT admin_pending_awaiting_email_count();
-- SELECT business_name, login_email, business_email
--   FROM admin_pending_email_list_v2(50, 0);
-- =====================================================
