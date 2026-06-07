-- =====================================================
-- db/118-pending-email-list-v2.sql
-- =====================================================
-- USER ISSUE (2026-06-07):
--   admin_pending_awaiting_email_count() returns 4,
--   but admin_pending_awaiting_email_list() returns EMPTY.
--
-- ROOT CAUSE:
--   The COUNT RPC (db/80) uses:
--     WHERE b.status::TEXT = 'pending'
--       AND b.email_gate_at_signup = TRUE
--       AND NOT business_has_verified_owner(b.id)
--   But the LIST RPC (db/82) used different filters/joins that
--   dropped rows. Also previous v2 attempts used wrong table name
--   (admins vs admin_users) and TEXT vs VARCHAR type mismatch.
--
-- THIS FILE — admin_pending_email_list_v2():
--   Uses EXACTLY the same filter logic as the working count RPC,
--   so list rows always match the count value.
--
-- DEPLOY:
--   Supabase Dashboard → SQL Editor → paste this whole file → Run
-- =====================================================

BEGIN;

-- Drop any prior version to avoid "structure of query does not match"
-- cache from a previous bad RETURNS TABLE signature.
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
SET search_path = public
AS $$
DECLARE
  v_role   TEXT;
  v_cities INT[];
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  -- Resolve caller's scope (same pattern as count RPC in db/80)
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
    -- EXACTLY the same filter as admin_pending_awaiting_email_count (db/80)
    b.status::TEXT = 'pending'
    AND b.email_gate_at_signup = TRUE
    AND NOT business_has_verified_owner(b.id)
    -- Scope: super_admin/admin see all; city_moderator sees their cities
    AND (
      v_role IN ('admin','super_admin')
      OR (v_cities IS NOT NULL AND b.city_id = ANY(v_cities))
    )
  ORDER BY b.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END $$;

GRANT EXECUTE ON FUNCTION admin_pending_email_list_v2(INT, INT) TO authenticated;

COMMIT;
