-- db/43-admin-pack.sql
-- Admin Completion Pack: gate announcements to super_admin + activity log helper
--
-- 1. Announcement RPCs require is_super_admin() (was is_admin())
-- 2. admin_recent_activity() — paginated audit log feed
-- 3. admin_set_deal_hidden() — admin can expire/hide any deal (RLS already permits, this just wraps it cleanly + logs)
--
-- Safe to re-run. Run AFTER db/41 (which defines is_super_admin) and db/40 (which creates deals).

BEGIN;

-- ===== 1. Gate announcement RPCs to super_admin =====
CREATE OR REPLACE FUNCTION admin_create_announcement(p_data JSONB)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT is_super_admin() THEN RAISE EXCEPTION 'super_admin only'; END IF;
  INSERT INTO announcements (
    title, body, image_url, link_url, link_label,
    display_type, color_scheme, target, dismissible, active,
    starts_at, ends_at, priority, created_by
  ) VALUES (
    p_data->>'title', p_data->>'body', p_data->>'image_url', p_data->>'link_url', p_data->>'link_label',
    COALESCE(p_data->>'display_type','banner'), COALESCE(p_data->>'color_scheme','saffron'),
    COALESCE(p_data->>'target','all'), COALESCE((p_data->>'dismissible')::BOOLEAN, TRUE),
    COALESCE((p_data->>'active')::BOOLEAN, TRUE),
    COALESCE((p_data->>'starts_at')::TIMESTAMPTZ, NOW()),
    (p_data->>'ends_at')::TIMESTAMPTZ,
    COALESCE((p_data->>'priority')::SMALLINT, 5),
    auth.uid()
  ) RETURNING id INTO v_id;
  PERFORM log_admin_action('create_announcement', 'announcement', v_id::TEXT, p_data->>'title', p_data);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION admin_update_announcement(p_id UUID, p_patch JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_key TEXT;
  v_allowed TEXT[] := ARRAY['title','body','image_url','link_url','link_label',
                            'display_type','color_scheme','target','dismissible',
                            'active','starts_at','ends_at','priority'];
BEGIN
  IF NOT is_super_admin() THEN RAISE EXCEPTION 'super_admin only'; END IF;
  FOR v_key IN SELECT jsonb_object_keys(p_patch) LOOP
    IF v_key = ANY(v_allowed) THEN
      EXECUTE format(
        'UPDATE announcements SET %I = ($1->>%L)::%s, updated_at = NOW() WHERE id = $2',
        v_key, v_key,
        CASE
          WHEN v_key IN ('dismissible','active') THEN 'BOOLEAN'
          WHEN v_key IN ('priority') THEN 'SMALLINT'
          WHEN v_key IN ('starts_at','ends_at') THEN 'TIMESTAMPTZ'
          ELSE 'TEXT'
        END
      ) USING p_patch, p_id;
    END IF;
  END LOOP;
  PERFORM log_admin_action('update_announcement', 'announcement', p_id::TEXT, NULL, p_patch);
  RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION admin_delete_announcement(p_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_super_admin() THEN RAISE EXCEPTION 'super_admin only'; END IF;
  DELETE FROM announcements WHERE id = p_id;
  PERFORM log_admin_action('delete_announcement', 'announcement', p_id::TEXT);
  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_create_announcement(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_update_announcement(UUID, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_delete_announcement(UUID) TO authenticated;


-- ===== 2. admin_recent_activity — paginated audit log feed =====
DROP FUNCTION IF EXISTS admin_recent_activity(INT, INT, TEXT, UUID);
CREATE OR REPLACE FUNCTION admin_recent_activity(
  p_limit       INT  DEFAULT 50,
  p_offset      INT  DEFAULT 0,
  p_action      TEXT DEFAULT NULL,    -- optional filter
  p_admin_id    UUID DEFAULT NULL     -- optional filter by specific admin
)
RETURNS TABLE (
  id            BIGINT,
  admin_user_id UUID,
  admin_email   TEXT,
  action        TEXT,
  target_type   TEXT,
  target_id     TEXT,
  target_name   TEXT,
  details       JSONB,
  created_at    TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  RETURN QUERY
    SELECT a.id, a.admin_user_id,
           COALESCE(au.email, '(deleted user)'),
           a.action, a.target_type, a.target_id, a.target_name, a.details, a.created_at
      FROM admin_audit_log a
      LEFT JOIN auth.users au ON au.id = a.admin_user_id
     WHERE (p_action IS NULL OR a.action = p_action)
       AND (p_admin_id IS NULL OR a.admin_user_id = p_admin_id)
     ORDER BY a.created_at DESC
     LIMIT GREATEST(1, LEAST(p_limit, 200))
     OFFSET GREATEST(0, p_offset);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_recent_activity(INT, INT, TEXT, UUID) TO authenticated;


-- ===== 3. admin_set_deal_hidden — expire any deal cleanly + log =====
DROP FUNCTION IF EXISTS admin_set_deal_hidden(UUID, BOOLEAN);
CREATE OR REPLACE FUNCTION admin_set_deal_hidden(p_deal_id UUID, p_hide BOOLEAN DEFAULT TRUE)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_title TEXT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT title INTO v_title FROM deals WHERE id = p_deal_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'deal not found'; END IF;

  IF p_hide THEN
    -- Expire NOW so it disappears from public + active queries
    UPDATE deals SET valid_until = NOW() - INTERVAL '1 second' WHERE id = p_deal_id;
    PERFORM log_admin_action('hide_deal', 'deal', p_deal_id::TEXT, v_title);
  ELSE
    -- Restore to 7 days from now
    UPDATE deals SET valid_until = NOW() + INTERVAL '7 days' WHERE id = p_deal_id AND valid_until < NOW();
    PERFORM log_admin_action('restore_deal', 'deal', p_deal_id::TEXT, v_title);
  END IF;
  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_set_deal_hidden(UUID, BOOLEAN) TO authenticated;


-- ===== 4. admin_delete_deal — permanent removal + log =====
DROP FUNCTION IF EXISTS admin_delete_deal(UUID);
CREATE OR REPLACE FUNCTION admin_delete_deal(p_deal_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_title TEXT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT title INTO v_title FROM deals WHERE id = p_deal_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'deal not found'; END IF;
  DELETE FROM deals WHERE id = p_deal_id;
  PERFORM log_admin_action('delete_deal', 'deal', p_deal_id::TEXT, v_title);
  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_delete_deal(UUID) TO authenticated;

COMMIT;
