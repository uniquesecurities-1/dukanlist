-- ============================================================
-- db/159 — Hotfix: admin_list_admins "auth_user_id is ambiguous"
-- ============================================================
-- Problem:
--   db/158 re-created admin_list_admins() with RETURNS TABLE that
--   includes an `auth_user_id` OUT column. Inside the function body,
--   the pre-flight check did:
--     IF NOT EXISTS (
--       SELECT 1 FROM admin_users
--       WHERE auth_user_id = auth.uid()
--           ^^^ unqualified — collides with the OUT column name
--           AND role = 'super_admin'
--     ) THEN ...
--   PL/pgSQL parser couldn't decide whether `auth_user_id` referred
--   to the RETURNS TABLE column or the admin_users table column →
--   400 "column reference 'auth_user_id' is ambiguous" on every
--   /admin/admins page load. Same risk on `role`.
--
-- Fix:
--   Qualify every reference inside the function body with a table
--   alias (`au.auth_user_id`, `au.role`). RETURNS TABLE signature is
--   IDENTICAL to db/158 so frontend code remains compatible.
--
-- Also: defensively wrap `permissions` column reference with table
-- qualification — same potential ambiguity once that column name is
-- both an OUT param and a table column.
--
-- SAFE: CREATE OR REPLACE. No schema changes. Zero impact on existing
-- callers — signature unchanged.
-- ============================================================

BEGIN;

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
  permissions       JSONB,
  added_at          TIMESTAMPTZ,
  last_login_at     TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- ⚠ FULLY QUALIFY every column with table alias `au` to avoid
  -- collision with the RETURNS TABLE column names of the same name.
  IF NOT EXISTS (
    SELECT 1 FROM admin_users au
    WHERE au.auth_user_id = auth.uid()
      AND au.role = 'super_admin'
  ) THEN
    RAISE EXCEPTION 'Super admin only';
  END IF;

  RETURN QUERY
  SELECT
    au.auth_user_id,
    au.role,
    au.email,
    au.display_name,
    COALESCE(au.assigned_city_ids, ARRAY[]::INT[]),
    COALESCE(
      ARRAY(SELECT gc.name FROM geo_cities gc
              WHERE gc.id = ANY(COALESCE(au.assigned_city_ids, ARRAY[]::INT[]))
              ORDER BY gc.name),
      ARRAY[]::TEXT[]
    ),
    COALESCE(au.disabled, FALSE),
    COALESCE(au.permissions, '{}'::jsonb),
    au.added_at,
    au.last_login_at
  FROM admin_users au
  ORDER BY au.added_at DESC NULLS LAST;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_list_admins() TO authenticated;

-- Same defensive fix for my_admin_permissions() — its SELECT didn't
-- have OUT-param ambiguity (RETURNS JSONB, no TABLE), but the DECLARE
-- variables `v_role` etc. are clearly distinct, so this is just a
-- belt-and-suspenders re-alias.
CREATE OR REPLACE FUNCTION my_admin_permissions()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_role        TEXT;
  v_disabled    BOOLEAN;
  v_perms       JSONB;
  v_super_perms JSONB;
BEGIN
  SELECT au.role, COALESCE(au.disabled, FALSE), COALESCE(au.permissions, '{}'::jsonb)
    INTO v_role, v_disabled, v_perms
  FROM admin_users au
  WHERE au.auth_user_id = auth.uid();

  IF v_role IS NULL THEN
    RETURN jsonb_build_object('is_admin', FALSE, 'is_super', FALSE, 'role', NULL);
  END IF;

  IF v_disabled THEN
    RETURN jsonb_build_object('is_admin', FALSE, 'is_super', FALSE, 'disabled', TRUE, 'role', v_role);
  END IF;

  IF v_role = 'super_admin' THEN
    v_super_perms := jsonb_build_object(
      'moderation', TRUE, 'bulk_upload', TRUE, 'announcements', TRUE,
      'featured', TRUE, 'deals', TRUE, 'activity', TRUE,
      'suspicious', TRUE, 'pucho_moderation', TRUE, 'reviews', TRUE,
      'categories', TRUE, 'cities', TRUE, 'settings', TRUE,
      'professional_verify', TRUE, 'pro_legal_notify', TRUE,
      'health', TRUE, 'monitoring', TRUE, 'duplicates', TRUE,
      'incomplete_shops', TRUE, 'broadcast', TRUE, 'spotlight', TRUE,
      'verification', TRUE, 'quick_approve', TRUE,
      'admins', TRUE, 'test_cleanup', TRUE
    );
    RETURN jsonb_build_object('is_admin', TRUE, 'is_super', TRUE, 'role', v_role) || v_super_perms;
  END IF;

  RETURN jsonb_build_object('is_admin', TRUE, 'is_super', FALSE, 'role', v_role) || v_perms;
END;
$$;

GRANT EXECUTE ON FUNCTION my_admin_permissions() TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/159 hotfix applied. admin_list_admins + my_admin_permissions fully qualified.';
END $$;
