-- =====================================================
-- db/118-pending-email-list-v2.sql
-- =====================================================
-- USER ISSUE (2026-06-07):
--   admin_pending_awaiting_email_count() returns 4,
--   but admin_pending_awaiting_email_list() returns EMPTY.
--   db/82 v1 RPC had scope filter that dropped rows.
--   v1 ALSO failed in browser: "relation 'admins' does not exist"
--   — the table is actually 'admin_users' (db/09).
--
-- THIS FILE — admin_pending_email_list_v2() — bulletproof rewrite:
--   • Uses CORRECT 'admin_users' table (not 'admins')
--   • Uses is_admin() gate from db/09
--   • Plain TEXT columns, no JSONB
--   • Any admin (admin/super_admin/moderator) sees ALL rows
--   • Filter: business with NO email_confirmed_at + status pending*
--
-- DEPLOY:
--   Open Supabase Dashboard → SQL Editor → paste this whole file → Run
-- =====================================================

BEGIN;

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
BEGIN
  -- Admin gate (uses helper from db/09-admin-schema.sql)
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  RETURN QUERY
  SELECT
    b.id                                                          AS business_id,
    COALESCE(b.name, '(unnamed)')                                  AS business_name,
    COALESCE(b.owner_name, '')                                     AS owner_name,
    COALESCE(b.mobile, '')                                         AS mobile,
    COALESCE(b.whatsapp, '')                                       AS whatsapp,
    COALESCE(u.email, '')                                          AS login_email,
    COALESCE(b.email, '')                                          AS business_email,
    COALESCE(c.name, '')                                           AS city_name,
    COALESCE(cat.name, '')                                         AS primary_cat,
    b.created_at                                                   AS created_at,
    EXTRACT(DAY FROM (NOW() - b.created_at))::INT                  AS days_since_signup
  FROM businesses b
  LEFT JOIN business_owners bo ON bo.business_id = b.id
  LEFT JOIN auth.users      u  ON u.id = bo.auth_user_id
  LEFT JOIN geo_cities      c  ON c.id = b.city_id
  LEFT JOIN categories      cat ON cat.id = COALESCE(b.sub_category_id, b.category_id)
  WHERE u.id IS NOT NULL                                  -- owner has an auth account
    AND u.email_confirmed_at IS NULL                      -- AND email not yet verified
    AND b.status IN ('pending', 'pending_approval', 'pending_email_verify', 'pending_review')
  ORDER BY b.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END $$;

GRANT EXECUTE ON FUNCTION admin_pending_email_list_v2(INT, INT) TO authenticated;

COMMIT;
