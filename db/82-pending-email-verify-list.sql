-- =====================================================
-- db/82-pending-email-verify-list.sql
-- =====================================================
-- USER REQUEST (2026-05-28):
--   "Jo pending approvals me un logo ka data hai jonhone abhi email
--    verify nahi kiya hai unka kuch details partialy to mujhe alag se
--    dikhao taki mai unhe reminder bhej saku ki bhai pehle email
--    verify kro fir mai approve kar paunga."
--
-- WHAT THIS ADDS:
--   admin_pending_awaiting_email_list() — returns the actual rows for
--   the count we already surface via admin_pending_awaiting_email_count().
--   Admin can see who they are and send WhatsApp reminders manually.
--
-- COLUMNS RETURNED:
--   business_id, business_name, owner_name, mobile, email,
--   owner_user_email (the auth account's email, may differ from biz.email),
--   created_at, days_since_signup, last_email_sent_at (auth.users)
--
-- SECURITY:
--   - is_admin() gate
--   - Scope-aware (city_moderator only sees their cities)
-- =====================================================

BEGIN;

CREATE OR REPLACE FUNCTION admin_pending_awaiting_email_list(
  p_limit  INT DEFAULT 50,
  p_offset INT DEFAULT 0
)
RETURNS TABLE (
  business_id        UUID,
  business_name      TEXT,
  owner_name         TEXT,
  mobile             TEXT,
  whatsapp           TEXT,
  business_email     TEXT,
  login_email        TEXT,
  city_name          TEXT,
  primary_cat        TEXT,
  created_at         TIMESTAMPTZ,
  days_since_signup  INT,
  auth_created_at    TIMESTAMPTZ
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

  -- Fetch scope (super_admin sees all; city_moderator sees only theirs)
  SELECT role, assigned_city_ids INTO v_role, v_cities
  FROM admin_users WHERE auth_user_id = auth.uid();

  RETURN QUERY
  SELECT
    b.id                                                          AS business_id,
    b.name::TEXT                                                  AS business_name,
    b.owner_name::TEXT                                            AS owner_name,
    b.mobile::TEXT                                                AS mobile,
    b.whatsapp::TEXT                                              AS whatsapp,
    b.email::TEXT                                                 AS business_email,
    au.email::TEXT                                                AS login_email,
    gc.name::TEXT                                                 AS city_name,
    COALESCE(pc.name, fc.name)::TEXT                              AS primary_cat,
    b.created_at                                                  AS created_at,
    GREATEST(0, EXTRACT(DAY FROM NOW() - b.created_at)::INT)      AS days_since_signup,
    au.created_at                                                 AS auth_created_at
  FROM businesses b
  JOIN business_owners bo ON bo.business_id = b.id
  JOIN auth.users au       ON au.id = bo.auth_user_id
  LEFT JOIN geo_cities  gc ON gc.id = b.city_id
  LEFT JOIN business_categories bcp ON bcp.business_id = b.id AND bcp.is_primary = TRUE
  LEFT JOIN categories pc  ON pc.id = bcp.category_id
  LEFT JOIN categories fc  ON fc.id = b.sub_category_id
  WHERE b.status::TEXT = 'pending'
    AND b.email_gate_at_signup = TRUE
    AND au.email_confirmed_at IS NULL          -- THE filter — email unverified
    AND (v_role = 'super_admin' OR v_cities IS NULL OR v_cities = '{}' OR b.city_id = ANY(v_cities))
  ORDER BY b.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_pending_awaiting_email_list(INT, INT) TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- VERIFY
-- =====================================================
DO $$
DECLARE
  v_rpc INT;
BEGIN
  SELECT COUNT(*) INTO v_rpc FROM pg_proc
    WHERE proname = 'admin_pending_awaiting_email_list';
  RAISE NOTICE '✅ admin_pending_awaiting_email_list: % of 1', v_rpc;
END $$;
