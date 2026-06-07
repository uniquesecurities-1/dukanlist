-- =====================================================
-- db/118-pending-email-list-v2.sql
-- =====================================================
-- USER ISSUE (2026-06-07):
--   admin_pending_awaiting_email_count() returns 3,
--   but admin_pending_awaiting_email_list() returns empty.
--   db/82 implementation had a scope filter that dropped rows.
--
-- NEW: admin_pending_email_list_v2() — bulletproof
--   - Super-admins see ALL pending email-unverified registrations
--   - City moderators see ones in their cities
--   - No complex JSON aggregation, just plain columns
--   - Joins auth.users via business_owners.auth_user_id
--   - Includes BOTH cases: status='pending' AND email NOT confirmed
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
DECLARE
  v_role           TEXT;
  v_user_id        UUID;
  v_allowed_cities UUID[];
BEGIN
  v_user_id := auth.uid();

  -- Resolve caller role
  SELECT COALESCE(role, 'admin') INTO v_role
  FROM admins
  WHERE auth_user_id = v_user_id
  LIMIT 1;

  IF v_role IS NULL THEN
    RAISE EXCEPTION 'Not an admin';
  END IF;

  -- For city_moderator, gather scope; super_admin and admin see all
  IF v_role = 'city_moderator' THEN
    SELECT ARRAY_AGG(city_id) INTO v_allowed_cities
    FROM admin_city_scope
    WHERE auth_user_id = v_user_id;
    IF v_allowed_cities IS NULL THEN
      v_allowed_cities := ARRAY[]::UUID[];
    END IF;
  END IF;

  RETURN QUERY
  SELECT
    b.id                                                            AS business_id,
    b.name                                                          AS business_name,
    COALESCE(b.owner_name, '')                                       AS owner_name,
    COALESCE(b.mobile, '')                                           AS mobile,
    COALESCE(b.whatsapp, '')                                         AS whatsapp,
    COALESCE(u.email, '')                                            AS login_email,
    COALESCE(b.email, '')                                            AS business_email,
    COALESCE(c.name, '')                                             AS city_name,
    COALESCE(cat.name, '')                                           AS primary_cat,
    b.created_at                                                     AS created_at,
    EXTRACT(DAY FROM (NOW() - b.created_at))::INT                    AS days_since_signup
  FROM businesses b
  LEFT JOIN business_owners bo ON bo.business_id = b.id
  LEFT JOIN auth.users     u   ON u.id = bo.auth_user_id
  LEFT JOIN geo_cities     c   ON c.id = b.city_id
  LEFT JOIN categories     cat ON cat.id = COALESCE(b.sub_category_id, b.category_id)
  WHERE u.id IS NOT NULL                                  -- account exists
    AND u.email_confirmed_at IS NULL                      -- BUT email not yet verified
    AND b.status IN ('pending', 'pending_approval', 'pending_email_verify', 'pending_review')
    AND (
      v_role IN ('admin', 'super_admin')
      OR (b.city_id = ANY(v_allowed_cities))
    )
  ORDER BY b.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END $$;

GRANT EXECUTE ON FUNCTION admin_pending_email_list_v2(INT, INT) TO authenticated;

COMMIT;
