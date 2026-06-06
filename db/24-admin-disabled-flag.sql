-- =====================================================
-- 24-admin-disabled-flag.sql
-- Add disabled flag + RPC to enable/disable admin users
-- =====================================================
-- WHY:
--   Right now removing an admin = DELETE from admin_users.
--   We want a soft "block / unblock" toggle so super-admin can
--   freeze a city moderator's access without losing audit history.
--
-- WHAT THIS DOES:
--   1. Adds `disabled BOOLEAN DEFAULT FALSE` to admin_users.
--   2. Updates is_admin() + is_super_admin() to ignore disabled rows.
--   3. Updates get_admin_scope() to honour the flag.
--   4. Adds admin_set_disabled(p_auth_user_id UUID, p_disabled BOOLEAN)
--      (super_admin only) — toggles flag + logs to admin_audit_log.
--   5. Updates admin_list_admins() to return the disabled flag.
--
-- PREREQUISITES: 01..23 executed.
-- HOW TO RUN: paste in Supabase SQL Editor → Run.
-- IDEMPOTENT: yes (IF NOT EXISTS / CREATE OR REPLACE).
-- =====================================================

-- ---- 1. column -----------------------------------------------------------
ALTER TABLE admin_users
  ADD COLUMN IF NOT EXISTS disabled BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_admin_users_disabled ON admin_users(disabled);


-- ---- 2. is_admin() honours disabled --------------------------------------
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN
LANGUAGE sql STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM admin_users
    WHERE auth_user_id = auth.uid()
      AND disabled = FALSE
  );
$$;


-- ---- 3. is_super_admin() honours disabled --------------------------------
CREATE OR REPLACE FUNCTION is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM admin_users
    WHERE auth_user_id = auth.uid()
      AND role = 'super_admin'
      AND disabled = FALSE
  );
$$;


-- ---- 4. get_admin_scope() returns disabled flag --------------------------
CREATE OR REPLACE FUNCTION get_admin_scope()
RETURNS JSONB
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role     TEXT;
  v_cities   INT[];
  v_display  TEXT;
  v_email    TEXT;
  v_disabled BOOLEAN;
BEGIN
  SELECT role, assigned_city_ids, display_name, email, disabled
    INTO v_role, v_cities, v_display, v_email, v_disabled
  FROM admin_users
  WHERE auth_user_id = auth.uid();

  IF v_role IS NULL THEN
    RETURN jsonb_build_object('is_admin', false);
  END IF;

  IF v_disabled THEN
    RETURN jsonb_build_object(
      'is_admin', false,
      'disabled', true,
      'message',  'Your admin access has been disabled. Contact super-admin.'
    );
  END IF;

  RETURN jsonb_build_object(
    'is_admin',     true,
    'is_super',     v_role = 'super_admin',
    'role',         v_role,
    'all_cities',   v_role = 'super_admin' OR v_cities IS NULL OR array_length(v_cities, 1) IS NULL,
    'city_ids',     COALESCE(to_jsonb(v_cities), '[]'::jsonb),
    'display_name', v_display,
    'email',        v_email,
    'disabled',     false
  );
END;
$$;
GRANT EXECUTE ON FUNCTION get_admin_scope() TO authenticated;


-- ---- 5. _admin_has_city_access() honours disabled ------------------------
CREATE OR REPLACE FUNCTION _admin_has_city_access(p_city_id INT)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role   TEXT;
  v_cities INT[];
BEGIN
  SELECT role, assigned_city_ids INTO v_role, v_cities
  FROM admin_users WHERE auth_user_id = auth.uid() AND disabled = FALSE;

  IF v_role IS NULL THEN RETURN FALSE; END IF;
  IF v_role = 'super_admin' THEN RETURN TRUE; END IF;
  IF v_role = 'admin' AND (v_cities IS NULL OR array_length(v_cities, 1) IS NULL) THEN
    RETURN TRUE;
  END IF;
  RETURN p_city_id = ANY(v_cities);
END;
$$;


-- ---- 6. admin_set_disabled(p_auth_user_id, p_disabled) -------------------
CREATE OR REPLACE FUNCTION admin_set_disabled(
  p_auth_user_id UUID,
  p_disabled     BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_self  UUID;
  v_email TEXT;
  v_name  TEXT;
  v_role  TEXT;
BEGIN
  IF NOT is_super_admin() THEN
    RAISE EXCEPTION 'Super admin only';
  END IF;

  v_self := auth.uid();
  IF v_self = p_auth_user_id THEN
    RAISE EXCEPTION 'Cannot disable yourself.';
  END IF;

  SELECT email, display_name, role INTO v_email, v_name, v_role
  FROM admin_users WHERE auth_user_id = p_auth_user_id;
  IF v_email IS NULL THEN
    RAISE EXCEPTION 'Admin not found';
  END IF;

  -- Prevent disabling the LAST active super-admin
  IF p_disabled AND v_role = 'super_admin' THEN
    IF (SELECT COUNT(*) FROM admin_users
         WHERE role = 'super_admin' AND disabled = FALSE) <= 1 THEN
      RAISE EXCEPTION 'Cannot disable the last active super-admin';
    END IF;
  END IF;

  UPDATE admin_users SET disabled = p_disabled
   WHERE auth_user_id = p_auth_user_id;

  PERFORM log_admin_action(
    CASE WHEN p_disabled THEN 'disable_admin' ELSE 'enable_admin' END,
    'admin_user', p_auth_user_id::TEXT, v_name,
    jsonb_build_object('email', v_email, 'disabled', p_disabled)
  );

  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_set_disabled(UUID, BOOLEAN) TO authenticated;


-- ---- 7. admin_list_admins() returns disabled flag ------------------------
DROP FUNCTION IF EXISTS admin_list_admins();
CREATE OR REPLACE FUNCTION admin_list_admins()
RETURNS TABLE (
  auth_user_id      UUID,
  role              TEXT,
  email             TEXT,
  display_name      TEXT,
  assigned_city_ids INT[],
  city_names        TEXT[],
  disabled          BOOLEAN,
  added_at          TIMESTAMPTZ,
  last_login_at     TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_super_admin() THEN
    RAISE EXCEPTION 'Super admin only';
  END IF;

  RETURN QUERY
  SELECT
    a.auth_user_id,
    a.role::TEXT,
    a.email, a.display_name,
    a.assigned_city_ids,
    (
      SELECT array_agg(c.name ORDER BY c.name)
      FROM geo_cities c
      WHERE c.id = ANY(COALESCE(a.assigned_city_ids, ARRAY[]::INT[]))
    ) AS city_names,
    a.disabled,
    a.added_at, a.last_login_at
  FROM admin_users a
  ORDER BY a.disabled ASC, a.added_at DESC NULLS LAST;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_list_admins() TO authenticated;


-- ---- 8. Reload PostgREST schema cache ------------------------------------
NOTIFY pgrst, 'reload schema';

-- =====================================================
-- VERIFICATION
-- =====================================================
-- SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_name = 'admin_users' AND column_name = 'disabled';
--
-- SELECT email, role, disabled FROM admin_users;
-- =====================================================
