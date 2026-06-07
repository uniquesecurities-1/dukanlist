-- =====================================================
-- db/120b-pending-email-hotfix.sql
-- =====================================================
-- HOTFIX (2026-06-07):
--   db/120 referenced business_owners.email_at_signup which DOES NOT EXIST.
--   business_owners actual columns: business_id, auth_user_id, role,
--   added_at, id, owner_phone (no email column at all).
--
--   That caused admin_pending_awaiting_email_count() to throw at runtime
--   → 400 Bad Request on admin moderation page.
--
-- FIX:
--   Re-define helpers using ONLY columns that exist:
--     - businesses.email  (shop email)
--     - businesses.mobile (owner phone)
--     - auth.users.email + email_confirmed_at
--   Auto-heal links by matching auth.users.email → businesses.email
--   (most reliable signal we actually have).
--
-- DEPLOY:
--   Supabase Dashboard → SQL Editor → paste this whole file → Run
--   (Run AFTER db/120 — this overwrites the broken functions.)
-- =====================================================

BEGIN;

-- =====================================================
-- 1. Drop broken helpers from db/120 cleanly
-- =====================================================
DROP FUNCTION IF EXISTS business_email_verified_anywhere(UUID);
DROP FUNCTION IF EXISTS self_heal_owner_links_by_email();

-- =====================================================
-- 2. Comprehensive verification check (corrected)
-- =====================================================
CREATE OR REPLACE FUNCTION business_email_verified_anywhere(p_business_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_verified BOOLEAN := FALSE;
  v_biz_email TEXT;
BEGIN
  -- Path 1: standard auth_user_id link check
  IF business_has_verified_owner(p_business_id) THEN
    RETURN TRUE;
  END IF;

  -- Path 2: email match via businesses.email → auth.users.email
  SELECT NULLIF(LOWER(email), '') INTO v_biz_email
  FROM businesses WHERE id = p_business_id;

  IF v_biz_email IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1
      FROM auth.users u
      WHERE u.email_confirmed_at IS NOT NULL
        AND LOWER(u.email::TEXT) = v_biz_email
    ) INTO v_verified;
  END IF;

  RETURN COALESCE(v_verified, FALSE);
END $$;

GRANT EXECUTE ON FUNCTION business_email_verified_anywhere(UUID) TO anon, authenticated;


-- =====================================================
-- 3. Self-heal: populate missing auth_user_id via email match
--    (matches businesses.email → auth.users.email)
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
  WITH heal AS (
    UPDATE business_owners bo
       SET auth_user_id = u.id
      FROM businesses b, auth.users u
     WHERE bo.business_id = b.id
       AND bo.auth_user_id IS NULL
       AND u.email_confirmed_at IS NOT NULL
       AND NULLIF(LOWER(b.email), '') IS NOT NULL
       AND LOWER(u.email::TEXT) = LOWER(b.email)
    RETURNING bo.business_id
  )
  SELECT COUNT(*) INTO v_fixed FROM heal;

  RETURN v_fixed;
EXCEPTION WHEN OTHERS THEN
  -- Never let auto-heal break the calling RPC
  RETURN 0;
END $$;

GRANT EXECUTE ON FUNCTION self_heal_owner_links_by_email() TO authenticated;


-- =====================================================
-- 4. Re-define LIST RPC with the corrected helper
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
-- 5. Re-define COUNT RPC with the corrected helper
--    (DROP first so return type can change freely)
-- =====================================================
DROP FUNCTION IF EXISTS admin_pending_awaiting_email_count();

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
-- Sanity check after deploy (optional):
--
-- SELECT self_heal_owner_links_by_email();      -- returns count linked
-- SELECT admin_pending_awaiting_email_count();  -- returns INT, no error
-- SELECT business_name, login_email, business_email
--   FROM admin_pending_email_list_v2(50, 0);
-- =====================================================
