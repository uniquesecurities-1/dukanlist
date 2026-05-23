-- =====================================================
-- db/35-announcements.sql
-- Site-wide announcements / ads / popups managed by admin
-- =====================================================
-- One admin can create rich announcements that appear to
-- all public visitors as either a top-of-page BANNER or a
-- centered MODAL popup. Each one has scheduling, dismissibility,
-- a click-through URL, an optional image, and a target audience.
--
-- 4 RPCs:
--   * list_active_announcements()       -- PUBLIC: read-only
--   * admin_create_announcement(jsonb)  -- admin only
--   * admin_list_announcements()        -- admin only
--   * admin_update_announcement(id, jsonb) -- toggle active / edit
-- =====================================================
BEGIN;

CREATE TABLE IF NOT EXISTS announcements (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title        TEXT NOT NULL,
  body         TEXT,
  image_url    TEXT,
  link_url     TEXT,
  link_label   TEXT DEFAULT 'Learn more',
  display_type TEXT NOT NULL DEFAULT 'banner'    -- 'banner' | 'modal'
               CHECK (display_type IN ('banner','modal')),
  color_scheme TEXT NOT NULL DEFAULT 'saffron'   -- 'saffron'|'indigo'|'emerald'|'amber'|'red'
               CHECK (color_scheme IN ('saffron','indigo','emerald','amber','red')),
  target       TEXT NOT NULL DEFAULT 'all'       -- 'all' | 'customer' | 'shopkeeper'
               CHECK (target IN ('all','customer','shopkeeper')),
  dismissible  BOOLEAN NOT NULL DEFAULT TRUE,
  active       BOOLEAN NOT NULL DEFAULT TRUE,
  starts_at    TIMESTAMPTZ,
  ends_at      TIMESTAMPTZ,
  priority     SMALLINT NOT NULL DEFAULT 100,    -- lower = higher priority
  created_by   UUID,                              -- admin auth_user_id
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ann_active
  ON announcements(active, priority)
  WHERE active = TRUE;

ALTER TABLE announcements ENABLE ROW LEVEL SECURITY;

-- Public read of active announcements via RPC, NOT direct table
DROP POLICY IF EXISTS "ann_admin_all"  ON announcements;
CREATE POLICY "ann_admin_all" ON announcements
  FOR ALL TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());


-- ---------- list_active_announcements (PUBLIC) ----------
DROP FUNCTION IF EXISTS list_active_announcements();

CREATE OR REPLACE FUNCTION list_active_announcements()
RETURNS TABLE (
  id           UUID,
  title        TEXT,
  body         TEXT,
  image_url    TEXT,
  link_url     TEXT,
  link_label   TEXT,
  display_type TEXT,
  color_scheme TEXT,
  target       TEXT,
  dismissible  BOOLEAN,
  priority     SMALLINT,
  created_at   TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT a.id, a.title, a.body, a.image_url, a.link_url, a.link_label,
         a.display_type, a.color_scheme, a.target, a.dismissible,
         a.priority, a.created_at
  FROM announcements a
  WHERE a.active = TRUE
    AND (a.starts_at IS NULL OR a.starts_at <= NOW())
    AND (a.ends_at   IS NULL OR a.ends_at   >  NOW())
  ORDER BY a.priority ASC, a.created_at DESC
  LIMIT 10;
$$;
GRANT EXECUTE ON FUNCTION list_active_announcements() TO anon, authenticated;


-- ---------- admin_create_announcement ----------
DROP FUNCTION IF EXISTS admin_create_announcement(JSONB);

CREATE OR REPLACE FUNCTION admin_create_announcement(p_data JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;

  INSERT INTO announcements (
    title, body, image_url, link_url, link_label,
    display_type, color_scheme, target, dismissible, active,
    starts_at, ends_at, priority, created_by
  ) VALUES (
    COALESCE(p_data->>'title', '(untitled)'),
    p_data->>'body',
    NULLIF(p_data->>'image_url',''),
    NULLIF(p_data->>'link_url',''),
    COALESCE(NULLIF(p_data->>'link_label',''), 'Learn more'),
    COALESCE(p_data->>'display_type', 'banner'),
    COALESCE(p_data->>'color_scheme', 'saffron'),
    COALESCE(p_data->>'target', 'all'),
    COALESCE((p_data->>'dismissible')::BOOLEAN, TRUE),
    COALESCE((p_data->>'active')::BOOLEAN, TRUE),
    (p_data->>'starts_at')::TIMESTAMPTZ,
    (p_data->>'ends_at')::TIMESTAMPTZ,
    COALESCE((p_data->>'priority')::SMALLINT, 100),
    auth.uid()
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_create_announcement(JSONB) TO authenticated;


-- ---------- admin_list_announcements ----------
DROP FUNCTION IF EXISTS admin_list_announcements();

CREATE OR REPLACE FUNCTION admin_list_announcements()
RETURNS SETOF announcements
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT * FROM announcements
  ORDER BY active DESC, priority ASC, created_at DESC;
$$;
GRANT EXECUTE ON FUNCTION admin_list_announcements() TO authenticated;


-- ---------- admin_update_announcement ----------
DROP FUNCTION IF EXISTS admin_update_announcement(UUID, JSONB);

CREATE OR REPLACE FUNCTION admin_update_announcement(p_id UUID, p_patch JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_key TEXT;
  v_allowed TEXT[] := ARRAY[
    'title','body','image_url','link_url','link_label',
    'display_type','color_scheme','target',
    'dismissible','active','starts_at','ends_at','priority'
  ];
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;

  FOR v_key IN SELECT jsonb_object_keys(p_patch) LOOP
    IF v_key = ANY(v_allowed) THEN
      EXECUTE format(
        'UPDATE announcements SET %I = ($1->>%L)::%s, updated_at = NOW() WHERE id = $2',
        v_key, v_key,
        CASE
          WHEN v_key IN ('dismissible','active')        THEN 'BOOLEAN'
          WHEN v_key IN ('starts_at','ends_at')         THEN 'TIMESTAMPTZ'
          WHEN v_key = 'priority'                       THEN 'SMALLINT'
          ELSE 'TEXT'
        END
      ) USING p_patch, p_id;
    END IF;
  END LOOP;

  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_update_announcement(UUID, JSONB) TO authenticated;


-- ---------- admin_delete_announcement ----------
DROP FUNCTION IF EXISTS admin_delete_announcement(UUID);

CREATE OR REPLACE FUNCTION admin_delete_announcement(p_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  DELETE FROM announcements WHERE id = p_id;
  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_delete_announcement(UUID) TO authenticated;

COMMIT;
