-- ============================================================
-- db/158 — Granular admin page permissions
-- ============================================================
-- Problem:
--   Until now, every non-super admin (role='admin' or 'moderator')
--   could see ALL admin pages because is_admin() returned TRUE for
--   any row in admin_users. Super admins had no way to restrict a
--   regular admin to only specific sections (e.g., let one admin
--   do moderation but not manage cities/categories).
--
-- Solution:
--   1. Add `permissions JSONB` column to admin_users.
--   2. Super admin sets the JSONB via new RPC. Object shape:
--        { "moderation": true, "reviews": true,
--          "professional_verify": false, ... }
--   3. New helper RPC my_admin_permissions() returns the effective
--      permission set for the current user. Super admins get ALL
--      keys=TRUE automatically (god mode).
--   4. admin_list_admins() extended to return the permissions JSONB
--      so the Admins UI can show + edit checkboxes.
--   5. Frontend (admin-common.js) hides nav items + redirects from
--      protected pages when permission is missing.
--
-- Permission keys map to admin pages (slug with - replaced by _):
--   moderation, bulk_upload, announcements, featured, deals,
--   activity, suspicious, pucho_moderation, reviews, categories,
--   cities, settings, professional_verify, pro_legal_notify,
--   health, monitoring, duplicates, incomplete_shops, broadcast,
--   spotlight, verification, quick_approve
--
-- SAFE: ALTER ADD COLUMN IF NOT EXISTS. Idempotent. Existing admins
-- get '{}' permissions = all false (locked down by default — admin
-- must regrant intentionally). Super admins unaffected.
-- ============================================================

BEGIN;

-- ============================================================
-- PART 1: Add permissions column
-- ============================================================
ALTER TABLE admin_users
  ADD COLUMN IF NOT EXISTS permissions JSONB DEFAULT '{}'::jsonb;


-- ============================================================
-- PART 2: my_admin_permissions() — effective permissions for caller
-- ============================================================
-- For super admins: returns the full god-mode permission set.
-- For regular admins: returns their stored JSONB + role/is_super flags.
-- For non-admins: returns empty {}.
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
  SELECT role, COALESCE(disabled, FALSE), COALESCE(permissions, '{}'::jsonb)
    INTO v_role, v_disabled, v_perms
  FROM admin_users
  WHERE auth_user_id = auth.uid();

  -- Not an admin at all
  IF v_role IS NULL THEN
    RETURN jsonb_build_object(
      'is_admin', FALSE,
      'is_super', FALSE,
      'role',     NULL
    );
  END IF;

  -- Disabled admin → no permissions even if super_admin (defense in depth)
  IF v_disabled THEN
    RETURN jsonb_build_object(
      'is_admin', FALSE,
      'is_super', FALSE,
      'disabled', TRUE,
      'role',     v_role
    );
  END IF;

  -- Super admin = god mode: every page key returns TRUE
  IF v_role = 'super_admin' THEN
    v_super_perms := jsonb_build_object(
      'moderation',          TRUE,
      'bulk_upload',         TRUE,
      'announcements',       TRUE,
      'featured',            TRUE,
      'deals',               TRUE,
      'activity',            TRUE,
      'suspicious',          TRUE,
      'pucho_moderation',    TRUE,
      'reviews',             TRUE,
      'categories',          TRUE,
      'cities',              TRUE,
      'settings',            TRUE,
      'professional_verify', TRUE,
      'pro_legal_notify',    TRUE,
      'health',              TRUE,
      'monitoring',          TRUE,
      'duplicates',          TRUE,
      'incomplete_shops',    TRUE,
      'broadcast',           TRUE,
      'spotlight',           TRUE,
      'verification',        TRUE,
      'quick_approve',       TRUE,
      'admins',              TRUE,
      'test_cleanup',        TRUE
    );
    RETURN jsonb_build_object(
      'is_admin', TRUE,
      'is_super', TRUE,
      'role',     v_role
    ) || v_super_perms;
  END IF;

  -- Regular admin / moderator / city_moderator → use stored JSONB.
  -- Default is locked down (empty {}) so admin must be explicitly
  -- granted access to each page. 'admins' and 'test_cleanup' are
  -- never grantable to non-super admins.
  RETURN jsonb_build_object(
    'is_admin', TRUE,
    'is_super', FALSE,
    'role',     v_role
  ) || v_perms;
END;
$$;

GRANT EXECUTE ON FUNCTION my_admin_permissions() TO authenticated;


-- ============================================================
-- PART 3: admin_set_admin_permissions — super admin grants/revokes
-- ============================================================
CREATE OR REPLACE FUNCTION admin_set_admin_permissions(
  p_user_id     UUID,
  p_permissions JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_role TEXT;
  v_target_role TEXT;
  v_clean_perms JSONB;
  -- Whitelisted keys — extra keys in caller's input are stripped
  v_allowed_keys TEXT[] := ARRAY[
    'moderation','bulk_upload','announcements','featured','deals',
    'activity','suspicious','pucho_moderation','reviews','categories',
    'cities','settings','professional_verify','pro_legal_notify',
    'health','monitoring','duplicates','incomplete_shops','broadcast',
    'spotlight','verification','quick_approve'
    -- NOTE: 'admins' and 'test_cleanup' intentionally OMITTED — they
    -- are super-only and cannot be granted to regular admins.
  ];
  v_key TEXT;
BEGIN
  -- Only super admin can change permissions
  SELECT role INTO v_caller_role FROM admin_users WHERE auth_user_id = auth.uid();
  IF v_caller_role IS DISTINCT FROM 'super_admin' THEN
    RAISE EXCEPTION 'Only super_admin can set permissions';
  END IF;

  -- Target must exist
  SELECT role INTO v_target_role FROM admin_users WHERE auth_user_id = p_user_id;
  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'Admin not found';
  END IF;

  -- Cannot modify another super admin's permissions (mutual respect)
  IF v_target_role = 'super_admin' THEN
    RAISE EXCEPTION 'Cannot modify super_admin permissions';
  END IF;

  -- Strip non-whitelisted keys defensively
  v_clean_perms := '{}'::jsonb;
  FOREACH v_key IN ARRAY v_allowed_keys LOOP
    IF p_permissions ? v_key AND (p_permissions->>v_key)::BOOLEAN IS TRUE THEN
      v_clean_perms := v_clean_perms || jsonb_build_object(v_key, TRUE);
    END IF;
  END LOOP;

  UPDATE admin_users
  SET permissions = v_clean_perms
  WHERE auth_user_id = p_user_id;

  RETURN jsonb_build_object(
    'success',       TRUE,
    'user_id',       p_user_id,
    'permissions',   v_clean_perms,
    'granted_count', jsonb_array_length(jsonb_path_query_array(v_clean_perms, '$.keyvalue() ? (@.value == true)'))
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_set_admin_permissions(UUID, JSONB) TO authenticated;


-- ============================================================
-- PART 4: Extend admin_list_admins to include permissions
-- ============================================================
-- Re-create the function with the existing signature + permissions
-- column. UI relies on this for the Edit modal pre-fill.
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
  -- Super admin only (matches existing pre-condition)
  IF NOT EXISTS (
    SELECT 1 FROM admin_users
    WHERE auth_user_id = auth.uid()
      AND role = 'super_admin'
  ) THEN
    RAISE EXCEPTION 'Super admin only';
  END IF;

  RETURN QUERY
  SELECT
    a.auth_user_id, a.role, a.email, a.display_name,
    COALESCE(a.assigned_city_ids, ARRAY[]::INT[]),
    COALESCE(
      ARRAY(SELECT gc.name FROM geo_cities gc
              WHERE gc.id = ANY(COALESCE(a.assigned_city_ids, ARRAY[]::INT[]))
              ORDER BY gc.name),
      ARRAY[]::TEXT[]
    ),
    COALESCE(a.disabled, FALSE),
    COALESCE(a.permissions, '{}'::jsonb),
    a.added_at,
    a.last_login_at
  FROM admin_users a
  ORDER BY a.added_at DESC NULLS LAST;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_list_admins() TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/158 installed. admin_users.permissions live + my_admin_permissions() RPC.';
END $$;
