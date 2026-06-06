-- =====================================================
-- 19-city-manager-system.sql
-- Multi-tenant Admin System: City Managers + Super Admins
-- =====================================================
-- WHAT THIS DOES:
--   1. Adds `assigned_city_ids INT[]` to admin_users (NULL = all cities)
--   2. Adds 'city_moderator' to the role CHECK constraint
--   3. Updates is_admin() (no change), adds is_super_admin()
--   4. Updates admin_list_businesses() — filters by scope
--   5. Updates approve/reject/delete — checks scope before action
--   6. Updates admin_bulk_register() — validates city in scope
--   7. NEW super-admin-only RPCs to manage other admins:
--        - admin_list_admins()
--        - admin_upsert_admin(...)
--        - admin_remove_admin(...)
--   8. Updates admin_pending_count to be scope-aware
--
-- ROLES:
--   super_admin    → sees everything across all cities
--   city_moderator → sees only assigned cities
--   moderator      → read-only access (reserved for future)
--
-- PREREQUISITES: 01-18 SQL files executed
-- HOW TO RUN: Paste in Supabase SQL Editor → Run
-- IDEMPOTENT: Safe to re-run.
-- =====================================================


-- =====================================================
-- SECTION 1: Schema changes
-- =====================================================

-- Add the city scope column
ALTER TABLE admin_users
  ADD COLUMN IF NOT EXISTS assigned_city_ids INT[];

-- Allow 'city_moderator' role (update CHECK constraint)
DO $$
BEGIN
  -- Drop existing CHECK if present
  IF EXISTS (
    SELECT 1 FROM information_schema.check_constraints
    WHERE constraint_name LIKE 'admin_users_role_check%'
  ) THEN
    ALTER TABLE admin_users DROP CONSTRAINT IF EXISTS admin_users_role_check;
  END IF;
END $$;

ALTER TABLE admin_users
  ADD CONSTRAINT admin_users_role_check
  CHECK (role IN ('admin','super_admin','city_moderator','moderator'));

-- Index for scope queries
CREATE INDEX IF NOT EXISTS idx_admin_users_assigned_cities
  ON admin_users USING GIN (assigned_city_ids);


-- =====================================================
-- SECTION 2: Helper functions
-- =====================================================

CREATE OR REPLACE FUNCTION is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM admin_users
    WHERE auth_user_id = auth.uid()
      AND role = 'super_admin'
  );
$$;

-- Returns the calling admin's scope info as JSONB
CREATE OR REPLACE FUNCTION get_admin_scope()
RETURNS JSONB
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role   TEXT;
  v_cities INT[];
  v_display TEXT;
  v_email TEXT;
BEGIN
  SELECT role, assigned_city_ids, display_name, email
    INTO v_role, v_cities, v_display, v_email
  FROM admin_users
  WHERE auth_user_id = auth.uid();

  IF v_role IS NULL THEN
    RETURN jsonb_build_object('is_admin', false);
  END IF;

  RETURN jsonb_build_object(
    'is_admin',     true,
    'is_super',     v_role = 'super_admin',
    'role',         v_role,
    'all_cities',   v_role = 'super_admin' OR v_cities IS NULL OR array_length(v_cities, 1) IS NULL,
    'city_ids',     COALESCE(to_jsonb(v_cities), '[]'::jsonb),
    'display_name', v_display,
    'email',        v_email
  );
END;
$$;

GRANT EXECUTE ON FUNCTION is_super_admin()      TO authenticated;
GRANT EXECUTE ON FUNCTION get_admin_scope()     TO authenticated;


-- Internal helper: returns TRUE if caller has access to this city_id
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
  FROM admin_users WHERE auth_user_id = auth.uid();

  IF v_role IS NULL THEN RETURN FALSE; END IF;
  -- Super admin: full access
  IF v_role = 'super_admin' THEN RETURN TRUE; END IF;
  -- Legacy 'admin' role without scope: full access (backward compatible)
  IF v_role = 'admin' AND (v_cities IS NULL OR array_length(v_cities, 1) IS NULL) THEN
    RETURN TRUE;
  END IF;
  -- City moderator: check city_id
  RETURN p_city_id = ANY(v_cities);
END;
$$;


-- =====================================================
-- SECTION 3: Updated admin_list_businesses — scope-aware
-- =====================================================

CREATE OR REPLACE FUNCTION admin_list_businesses(
  p_status TEXT     DEFAULT NULL,
  p_limit  INT      DEFAULT 50,
  p_offset INT      DEFAULT 0,
  p_sort   TEXT     DEFAULT 'newest'
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
DECLARE
  v_role   TEXT;
  v_cities INT[];
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  -- Fetch scope
  SELECT role, assigned_city_ids INTO v_role, v_cities
  FROM admin_users WHERE auth_user_id = auth.uid();

  RETURN QUERY
  SELECT
    b.id, b.slug, b.name, b.name_hi, b.owner_name, b.mobile, b.whatsapp, b.email,
    b.status::TEXT,
    COALESCE(pc.name, fc.name)        AS primary_cat,
    gc.name                            AS city_name,
    gs.code                            AS state_code,
    b.pincode,
    COALESCE(array_length(b.photos,1),0)::INT AS photos_count,
    b.verified_score,
    b.rating_avg, b.rating_count,
    b.flagged_count, b.lead_count, b.view_count,
    b.created_at, b.last_active_at
  FROM businesses b
  LEFT JOIN geo_cities  gc ON gc.id = b.city_id
  LEFT JOIN geo_states  gs ON gs.id = b.state_id
  LEFT JOIN business_categories bcp ON bcp.business_id = b.id AND bcp.is_primary = TRUE
  LEFT JOIN categories pc ON pc.id = bcp.category_id
  LEFT JOIN categories fc ON fc.id = b.category_id
  WHERE (p_status IS NULL OR b.status::TEXT = p_status)
    -- Scope filter:
    AND (
      v_role = 'super_admin'
      OR (v_role = 'admin' AND (v_cities IS NULL OR array_length(v_cities,1) IS NULL))
      OR b.city_id = ANY(v_cities)
    )
  ORDER BY
    CASE WHEN p_sort = 'oldest' THEN b.created_at END ASC,
    CASE WHEN p_sort = 'newest' THEN b.created_at END DESC,
    CASE WHEN p_sort = 'flags'  THEN b.flagged_count END DESC,
    CASE WHEN p_sort = 'rating' THEN b.rating_avg END DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_list_businesses(TEXT,INT,INT,TEXT) TO authenticated;


-- =====================================================
-- SECTION 4: Scope-aware approve / reject / delete
-- =====================================================

CREATE OR REPLACE FUNCTION admin_approve_business(p_business_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin BOOLEAN;
  v_name TEXT;
  v_city INT;
BEGIN
  SELECT is_admin() INTO v_admin;
  IF NOT v_admin THEN RAISE EXCEPTION 'Admin only'; END IF;

  SELECT name, city_id INTO v_name, v_city FROM businesses WHERE id = p_business_id;
  IF v_name IS NULL THEN RAISE EXCEPTION 'Business not found'; END IF;

  IF NOT _admin_has_city_access(v_city) THEN
    RAISE EXCEPTION 'Not authorised — this shop is outside your city scope';
  END IF;

  UPDATE businesses
    SET status = 'active',
        verified_visit = TRUE,
        verified_score = COALESCE(verified_score, 0) + 1
    WHERE id = p_business_id;

  PERFORM log_admin_action('approve_business', 'business', p_business_id::TEXT, v_name, NULL);
END;
$$;
GRANT EXECUTE ON FUNCTION admin_approve_business(UUID) TO authenticated;


CREATE OR REPLACE FUNCTION admin_reject_business(
  p_business_id UUID,
  p_reason      TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin BOOLEAN;
  v_name TEXT;
  v_city INT;
BEGIN
  SELECT is_admin() INTO v_admin;
  IF NOT v_admin THEN RAISE EXCEPTION 'Admin only'; END IF;

  SELECT name, city_id INTO v_name, v_city FROM businesses WHERE id = p_business_id;
  IF v_name IS NULL THEN RAISE EXCEPTION 'Business not found'; END IF;

  IF NOT _admin_has_city_access(v_city) THEN
    RAISE EXCEPTION 'Not authorised — this shop is outside your city scope';
  END IF;

  UPDATE businesses SET status = 'banned' WHERE id = p_business_id;

  PERFORM log_admin_action(
    'reject_business', 'business', p_business_id::TEXT, v_name,
    jsonb_build_object('reason', p_reason)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION admin_reject_business(UUID, TEXT) TO authenticated;


CREATE OR REPLACE FUNCTION admin_delete_business(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin         BOOLEAN;
  v_biz_name      TEXT;
  v_biz_slug      TEXT;
  v_city          INT;
  v_photos        TEXT[];
  v_review_count  INT;
  v_lead_count    INT;
  v_category_count INT;
BEGIN
  SELECT is_admin() INTO v_admin;
  IF NOT v_admin THEN RAISE EXCEPTION 'Admin only'; END IF;

  SELECT name, slug, COALESCE(photos, ARRAY[]::TEXT[]), city_id
    INTO v_biz_name, v_biz_slug, v_photos, v_city
  FROM businesses WHERE id = p_business_id;

  IF v_biz_name IS NULL THEN RAISE EXCEPTION 'Business not found'; END IF;

  IF NOT _admin_has_city_access(v_city) THEN
    RAISE EXCEPTION 'Not authorised — this shop is outside your city scope';
  END IF;

  SELECT COUNT(*)::INT INTO v_review_count FROM reviews WHERE business_id = p_business_id;
  SELECT COUNT(*)::INT INTO v_lead_count FROM leads_log WHERE business_id = p_business_id;
  SELECT COUNT(*)::INT INTO v_category_count FROM business_categories WHERE business_id = p_business_id;

  PERFORM log_admin_action(
    'delete_business', 'business', p_business_id::TEXT, v_biz_name,
    jsonb_build_object(
      'slug', v_biz_slug,
      'photo_count', COALESCE(array_length(v_photos, 1), 0),
      'review_count', v_review_count,
      'lead_count', v_lead_count,
      'category_count', v_category_count
    )
  );

  DELETE FROM businesses WHERE id = p_business_id;

  RETURN jsonb_build_object(
    'success', true,
    'business_id', p_business_id,
    'business_name', v_biz_name,
    'business_slug', v_biz_slug,
    'photos_to_cleanup', COALESCE(to_jsonb(v_photos), '[]'::jsonb),
    'photo_count', COALESCE(array_length(v_photos, 1), 0),
    'review_count', v_review_count,
    'lead_count', v_lead_count,
    'category_count', v_category_count,
    'deleted_at', NOW()
  );
END;
$$;
GRANT EXECUTE ON FUNCTION admin_delete_business(UUID) TO authenticated;


-- =====================================================
-- SECTION 5: Scope-aware admin_bulk_register
-- =====================================================
CREATE OR REPLACE FUNCTION admin_bulk_register(p_shops JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin     BOOLEAN;
  v_shop      JSONB;
  v_biz_id    UUID;
  v_results   JSONB := '[]'::JSONB;
  v_success   INT := 0;
  v_failed    INT := 0;
  v_primary   INT;
  v_parent_id INT;
  v_slug      TEXT;
  v_city_name TEXT;
  v_city_id   INT;
  v_err       TEXT;
BEGIN
  SELECT is_admin() INTO v_admin;
  IF NOT v_admin THEN RAISE EXCEPTION 'Admin only'; END IF;

  FOR v_shop IN SELECT * FROM jsonb_array_elements(p_shops) LOOP
    BEGIN
      v_city_id := (v_shop->>'city_id')::INT;
      -- Scope check
      IF NOT _admin_has_city_access(v_city_id) THEN
        RAISE EXCEPTION 'Outside your city scope (city_id %)', v_city_id;
      END IF;

      v_primary := (v_shop->>'primary_category_id')::INT;
      SELECT parent_id INTO v_parent_id FROM categories WHERE id = v_primary;
      SELECT name INTO v_city_name FROM geo_cities WHERE id = v_city_id;
      v_slug := generate_business_slug(v_shop->>'name', v_city_name);

      INSERT INTO businesses (
        slug, category_id, sub_category_id,
        name, owner_name, mobile, whatsapp,
        address_line1, city_id, district_id, state_id, pincode,
        usp_text, status,
        verified_mobile, verified_address, verified_visit
      ) VALUES (
        v_slug,
        COALESCE(v_parent_id, v_primary),
        CASE WHEN v_parent_id IS NOT NULL THEN v_primary ELSE NULL END,
        v_shop->>'name', v_shop->>'owner_name', v_shop->>'mobile',
        COALESCE(v_shop->>'whatsapp', v_shop->>'mobile'),
        v_shop->>'address',
        v_city_id,
        (v_shop->>'district_id')::INT,
        (v_shop->>'state_id')::SMALLINT,
        v_shop->>'pincode',
        v_shop->>'usp',
        'active', TRUE, TRUE, TRUE
      )
      RETURNING id INTO v_biz_id;

      INSERT INTO business_owners (business_id, auth_user_id, owner_phone, role)
      VALUES (v_biz_id, NULL, v_shop->>'mobile', 'owner');

      INSERT INTO business_categories (business_id, category_id, is_primary)
      VALUES (v_biz_id, v_primary, TRUE);

      v_success := v_success + 1;
      v_results := v_results || jsonb_build_object(
        'name', v_shop->>'name', 'status', 'success', 'business_id', v_biz_id
      );
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      v_failed := v_failed + 1;
      v_results := v_results || jsonb_build_object(
        'name', v_shop->>'name', 'status', 'failed', 'error', v_err
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success_count', v_success,
    'failed_count',  v_failed,
    'results',       v_results
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_bulk_register(JSONB) TO authenticated;


-- =====================================================
-- SECTION 6: Scope-aware admin_pending_count
-- =====================================================
CREATE OR REPLACE FUNCTION admin_pending_count()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_role   TEXT;
  v_cities INT[];
  v_count  INT;
BEGIN
  IF NOT is_admin() THEN RETURN 0; END IF;

  SELECT role, assigned_city_ids INTO v_role, v_cities
  FROM admin_users WHERE auth_user_id = auth.uid();

  IF v_role = 'super_admin' OR (v_role = 'admin' AND (v_cities IS NULL OR array_length(v_cities,1) IS NULL)) THEN
    SELECT COUNT(*) INTO v_count FROM businesses
    WHERE status IN ('pending', 'pending_review');
  ELSE
    SELECT COUNT(*) INTO v_count FROM businesses
    WHERE status IN ('pending', 'pending_review')
      AND city_id = ANY(v_cities);
  END IF;

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_pending_count() TO authenticated;


-- =====================================================
-- SECTION 7: Super-admin tools — manage other admins
-- =====================================================

-- List all admins (super_admin only)
CREATE OR REPLACE FUNCTION admin_list_admins()
RETURNS TABLE (
  auth_user_id   UUID,
  role           TEXT,
  email          TEXT,
  display_name   TEXT,
  assigned_city_ids INT[],
  city_names     TEXT[],
  added_at       TIMESTAMPTZ,
  last_login_at  TIMESTAMPTZ
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
    -- Resolve city ids to names
    (
      SELECT array_agg(c.name ORDER BY c.name)
      FROM geo_cities c
      WHERE c.id = ANY(COALESCE(a.assigned_city_ids, ARRAY[]::INT[]))
    ) AS city_names,
    a.added_at, a.last_login_at
  FROM admin_users a
  ORDER BY a.added_at DESC NULLS LAST;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_list_admins() TO authenticated;


-- Upsert admin (super_admin only). Used to add/update city moderators.
CREATE OR REPLACE FUNCTION admin_upsert_admin(
  p_auth_user_id     UUID,
  p_role             TEXT,
  p_email            TEXT,
  p_display_name     TEXT,
  p_assigned_city_ids INT[] DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_super_admin() THEN
    RAISE EXCEPTION 'Super admin only';
  END IF;

  IF p_role NOT IN ('admin','super_admin','city_moderator','moderator') THEN
    RAISE EXCEPTION 'Invalid role: %', p_role;
  END IF;

  -- City moderator MUST have assigned_city_ids
  IF p_role = 'city_moderator' AND (p_assigned_city_ids IS NULL OR array_length(p_assigned_city_ids, 1) IS NULL) THEN
    RAISE EXCEPTION 'City moderator must have at least one assigned city';
  END IF;

  INSERT INTO admin_users (auth_user_id, role, email, display_name, assigned_city_ids)
  VALUES (p_auth_user_id, p_role, LOWER(p_email), p_display_name, p_assigned_city_ids)
  ON CONFLICT (auth_user_id) DO UPDATE
    SET role = EXCLUDED.role,
        email = EXCLUDED.email,
        display_name = EXCLUDED.display_name,
        assigned_city_ids = EXCLUDED.assigned_city_ids;

  PERFORM log_admin_action(
    'upsert_admin', 'admin_user', p_auth_user_id::TEXT, p_display_name,
    jsonb_build_object(
      'role', p_role,
      'email', p_email,
      'assigned_city_ids', COALESCE(to_jsonb(p_assigned_city_ids), '[]'::jsonb)
    )
  );

  RETURN p_auth_user_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_upsert_admin(UUID, TEXT, TEXT, TEXT, INT[]) TO authenticated;


-- Remove an admin (revokes panel access; doesn't delete auth.users)
CREATE OR REPLACE FUNCTION admin_remove_admin(p_auth_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_email TEXT;
  v_name  TEXT;
  v_self  UUID;
BEGIN
  IF NOT is_super_admin() THEN
    RAISE EXCEPTION 'Super admin only';
  END IF;

  v_self := auth.uid();
  IF v_self = p_auth_user_id THEN
    RAISE EXCEPTION 'Cannot remove yourself. Ask another super-admin to do this.';
  END IF;

  SELECT email, display_name INTO v_email, v_name FROM admin_users WHERE auth_user_id = p_auth_user_id;
  IF v_email IS NULL THEN
    RAISE EXCEPTION 'Admin not found';
  END IF;

  DELETE FROM admin_users WHERE auth_user_id = p_auth_user_id;

  PERFORM log_admin_action(
    'remove_admin', 'admin_user', p_auth_user_id::TEXT, v_name,
    jsonb_build_object('email', v_email)
  );

  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_remove_admin(UUID) TO authenticated;


-- List available cities — useful for the admin management UI
CREATE OR REPLACE FUNCTION admin_list_all_cities()
RETURNS TABLE (
  id           INT,
  name         TEXT,
  district_id  INT,
  district_name TEXT,
  state_id     SMALLINT,
  state_name   TEXT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  RETURN QUERY
  SELECT c.id, c.name, c.district_id, d.name, c.state_id, s.name
  FROM geo_cities c
  LEFT JOIN geo_districts d ON d.id = c.district_id
  LEFT JOIN geo_states s ON s.id = c.state_id
  WHERE c.active = TRUE
  ORDER BY s.name, d.name, c.name;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_list_all_cities() TO authenticated;


-- =====================================================
-- SECTION 8: Reload PostgREST schema cache
-- =====================================================
NOTIFY pgrst, 'reload schema';


-- =====================================================
-- VERIFICATION
-- =====================================================
-- 1) New columns + functions present:
--    SELECT column_name FROM information_schema.columns
--      WHERE table_name = 'admin_users' AND column_name = 'assigned_city_ids';
--    SELECT proname FROM pg_proc WHERE proname IN
--      ('is_super_admin','get_admin_scope','admin_list_admins',
--       'admin_upsert_admin','admin_remove_admin','admin_list_all_cities');
--    (expect 6 function rows)
--
-- 2) Verify your existing admin is super_admin:
--    SELECT * FROM admin_users;
--    (role should be 'super_admin')
--
-- 3) Test scope:
--    SELECT get_admin_scope();
--    (expect: is_super = true for you, all_cities = true)
--
-- 4) Onboard a city moderator (after creating auth user via Supabase Dashboard):
--    SELECT admin_upsert_admin(
--      'PASTE-NEW-USER-UUID-HERE'::uuid,
--      'city_moderator',
--      'manager.dabwali@example.com',
--      'Rajesh Kumar',
--      ARRAY[<city_id_for_mandi_dabwali>]
--    );
-- =====================================================
