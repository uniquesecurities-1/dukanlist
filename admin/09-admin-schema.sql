-- =====================================================
-- 09-admin-schema.sql
-- Admin Panel — schema + role check + admin RPCs
-- =====================================================
-- Prerequisites: 01–08 SQL files
-- HOW TO RUN: Paste in Supabase SQL Editor → Run
-- THEN run the BOOTSTRAP query at the bottom to make Deepak the first admin
-- =====================================================


-- =====================================================
-- SECTION 1: admin_users table
-- =====================================================

CREATE TABLE IF NOT EXISTS admin_users (
  auth_user_id   UUID PRIMARY KEY,
  role           TEXT NOT NULL DEFAULT 'admin'
                 CHECK (role IN ('admin','super_admin','moderator')),
  email          TEXT,
  display_name   TEXT,
  added_at       TIMESTAMPTZ DEFAULT NOW(),
  last_login_at  TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_admin_users_role ON admin_users(role);


-- =====================================================
-- SECTION 2: RLS for admin_users
-- =====================================================

ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_self_read ON admin_users;
CREATE POLICY admin_self_read ON admin_users FOR SELECT
  USING (auth_user_id = auth.uid());

-- Super-admins can manage admin list (inserts via Service Role only for now)
DROP POLICY IF EXISTS super_admin_manage ON admin_users;
CREATE POLICY super_admin_manage ON admin_users FOR ALL
  USING (
    EXISTS (SELECT 1 FROM admin_users a
            WHERE a.auth_user_id = auth.uid() AND a.role = 'super_admin')
  );


-- =====================================================
-- SECTION 3: is_admin() helper
-- =====================================================

CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid());
$$;


-- =====================================================
-- SECTION 4: get_admin_stats — KPI for dashboard
-- =====================================================

CREATE OR REPLACE FUNCTION get_admin_stats()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT jsonb_build_object(
    'total_businesses',     (SELECT COUNT(*) FROM businesses),
    'active',               (SELECT COUNT(*) FROM businesses WHERE status='active'),
    'pending',              (SELECT COUNT(*) FROM businesses WHERE status='pending'),
    'flagged',              (SELECT COUNT(*) FROM businesses WHERE status='flagged'),
    'banned',               (SELECT COUNT(*) FROM businesses WHERE status='banned'),
    'self_hidden',          (SELECT COUNT(*) FROM businesses WHERE status='self_hidden'),
    'total_categories',     (SELECT COUNT(*) FROM categories WHERE active),
    'parent_categories',    (SELECT COUNT(*) FROM categories WHERE active AND parent_id IS NULL),
    'sub_categories',       (SELECT COUNT(*) FROM categories WHERE active AND parent_id IS NOT NULL),
    'total_reviews',        (SELECT COUNT(*) FROM reviews WHERE status='active'),
    'avg_rating',           (SELECT COALESCE(ROUND(AVG(rating)::numeric, 2), 0)
                              FROM reviews WHERE status='active'),
    'leads_today',          (SELECT COUNT(*) FROM leads_log WHERE created_at > NOW() - INTERVAL '24 hours'),
    'leads_week',           (SELECT COUNT(*) FROM leads_log WHERE created_at > NOW() - INTERVAL '7 days'),
    'leads_total',          (SELECT COUNT(*) FROM leads_log),
    'flags_pending',        (SELECT COUNT(*) FROM flags WHERE status='pending'),
    'cities_active',        (SELECT COUNT(DISTINCT city_id) FROM businesses WHERE status='active'),
    'states_active',        (SELECT COUNT(DISTINCT state_id) FROM businesses WHERE status='active'),
    'new_today',            (SELECT COUNT(*) FROM businesses WHERE created_at > NOW() - INTERVAL '24 hours'),
    'new_week',             (SELECT COUNT(*) FROM businesses WHERE created_at > NOW() - INTERVAL '7 days')
  ) INTO v_result;

  RETURN v_result;
END;
$$;


-- =====================================================
-- SECTION 5: admin_list_businesses — pageable list
-- =====================================================

CREATE OR REPLACE FUNCTION admin_list_businesses(
  p_status TEXT     DEFAULT NULL,    -- filter by status, or NULL = all
  p_limit  INT      DEFAULT 50,
  p_offset INT      DEFAULT 0,
  p_sort   TEXT     DEFAULT 'newest'  -- 'newest' | 'oldest' | 'flags' | 'rating'
)
RETURNS TABLE (
  id              UUID,
  slug            TEXT,
  name            TEXT,
  name_hi         TEXT,
  owner_name      TEXT,
  mobile          TEXT,
  whatsapp        TEXT,
  email           TEXT,
  status          TEXT,
  primary_cat     TEXT,
  city_name       TEXT,
  state_code      TEXT,
  pincode         TEXT,
  photos_count    INT,
  verified_score  SMALLINT,
  rating_avg      NUMERIC,
  rating_count    INT,
  flagged_count   SMALLINT,
  lead_count      INT,
  view_count      INT,
  created_at      TIMESTAMPTZ,
  last_active_at  TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  RETURN QUERY
  SELECT
    b.id, b.slug, b.name, b.name_hi, b.owner_name,
    b.mobile, b.whatsapp, b.email, b.status,
    pc.name AS primary_cat,
    gc.name AS city_name, gs.code AS state_code, b.pincode,
    COALESCE(array_length(b.photos, 1), 0) AS photos_count,
    b.verified_score, b.rating_avg, b.rating_count,
    b.flagged_count, b.lead_count, b.view_count,
    b.created_at, b.last_active_at
  FROM businesses b
  LEFT JOIN business_categories bcp ON bcp.business_id = b.id AND bcp.is_primary = TRUE
  LEFT JOIN categories pc            ON pc.id = bcp.category_id
  LEFT JOIN geo_cities  gc           ON gc.id = b.city_id
  LEFT JOIN geo_states  gs           ON gs.id = b.state_id
  WHERE (p_status IS NULL OR b.status = p_status)
  ORDER BY
    CASE WHEN p_sort = 'newest'  THEN b.created_at END DESC,
    CASE WHEN p_sort = 'oldest'  THEN b.created_at END ASC,
    CASE WHEN p_sort = 'flags'   THEN b.flagged_count END DESC,
    CASE WHEN p_sort = 'rating'  THEN b.rating_avg END DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;


-- =====================================================
-- SECTION 6: admin_approve_business
-- =====================================================
-- Sets a pending business to active (forces verified flags if photo exists)
-- =====================================================

CREATE OR REPLACE FUNCTION admin_approve_business(p_business_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_photo_count INT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT COALESCE(array_length(photos, 1), 0) INTO v_photo_count
  FROM businesses WHERE id = p_business_id;

  UPDATE businesses
  SET status = 'active',
      verified_photo = (v_photo_count >= 1),
      updated_at = NOW()
  WHERE id = p_business_id;
END;
$$;


-- =====================================================
-- SECTION 7: admin_reject_business — set status banned
-- =====================================================

CREATE OR REPLACE FUNCTION admin_reject_business(p_business_id UUID, p_reason TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  UPDATE businesses
  SET status = 'banned',
      notes_internal = COALESCE(notes_internal || E'\n', '') ||
                       '[BANNED ' || NOW()::TEXT || '] ' || COALESCE(p_reason, 'No reason'),
      updated_at = NOW()
  WHERE id = p_business_id;
END;
$$;


-- =====================================================
-- SECTION 8: admin_resolve_flag — mark community flag handled
-- =====================================================

CREATE OR REPLACE FUNCTION admin_resolve_flag(
  p_flag_id  UUID,
  p_action   TEXT  -- 'resolved' or 'dismissed'
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_email TEXT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;
  IF p_action NOT IN ('resolved','dismissed') THEN
    RAISE EXCEPTION 'Invalid action';
  END IF;

  SELECT email INTO v_admin_email FROM admin_users WHERE auth_user_id = auth.uid();

  UPDATE flags
  SET status = p_action,
      resolved_by = v_admin_email,
      resolved_at = NOW()
  WHERE id = p_flag_id;
END;
$$;


-- =====================================================
-- SECTION 9: admin_get_flags — pending flags queue
-- =====================================================

CREATE OR REPLACE FUNCTION admin_get_flags(p_limit INT DEFAULT 50)
RETURNS TABLE (
  id              UUID,
  business_id     UUID,
  business_name   TEXT,
  business_slug   TEXT,
  business_status TEXT,
  reason          TEXT,
  text            TEXT,
  status          TEXT,
  created_at      TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  RETURN QUERY
  SELECT f.id, f.business_id, b.name, b.slug, b.status,
         f.reason, f.text, f.status, f.created_at
  FROM flags f
  JOIN businesses b ON b.id = f.business_id
  WHERE f.status = 'pending'
  ORDER BY f.created_at DESC
  LIMIT p_limit;
END;
$$;


-- =====================================================
-- SECTION 10: Reload schema cache
-- =====================================================

NOTIFY pgrst, 'reload schema';


-- =====================================================
-- BOOTSTRAP: Make Deepak the FIRST super_admin
-- =====================================================
-- 1) Login to dukanlist.com via OTP first (so your auth user is created in Supabase)
--    Phone: 919541223377  → OTP 123456 (test mode)
-- 2) Go to Supabase Dashboard → Authentication → Users
--    Find your user (mobile 919541223377), copy the UUID
-- 3) Paste that UUID in the query below (replace 'PASTE_YOUR_AUTH_USER_ID'), then Run:
--
-- INSERT INTO admin_users (auth_user_id, role, email, display_name)
-- VALUES (
--   'PASTE_YOUR_AUTH_USER_ID'::UUID,
--   'super_admin',
--   'singla223377@gmail.com',
--   'Deepak Singla'
-- )
-- ON CONFLICT (auth_user_id) DO UPDATE
--   SET role = EXCLUDED.role,
--       email = EXCLUDED.email,
--       display_name = EXCLUDED.display_name;
--
-- 4) Verify:
--    SELECT * FROM admin_users;
-- =====================================================
