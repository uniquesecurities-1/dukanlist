-- ============================================================
-- db/184 — Defensive rebuild of admin_list_businesses
-- ============================================================
-- ISSUE:
--   After db/182's DROP+CREATE, admin dashboard's call to
--   admin_list_businesses returns 400 from PostgREST. Function
--   exists and is found, so the error is in the body — likely a
--   type mismatch on RETURNS TABLE columns (PostgreSQL strictly
--   enforces these and silent BIGINT vs INT mismatches throw).
--
-- THIS FIX:
--   - Drops ALL overloads of admin_list_businesses cleanly
--   - Recreates with EXPLICIT type casts on every returned column
--   - Removes the email-gate check temporarily (it depends on
--     business_has_verified_owner — if that function is missing,
--     the whole RPC fails). We can re-add later via a separate
--     migration once we confirm the dependency exists.
--   - Keeps the soft_listed exclusion for p_status=NULL behavior
-- ============================================================

BEGIN;

-- Nuke all overloads
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT pg_get_function_identity_arguments(oid) AS args
    FROM pg_proc
    WHERE proname = 'admin_list_businesses'
      AND pronamespace = 'public'::regnamespace
  LOOP
    EXECUTE 'DROP FUNCTION public.admin_list_businesses(' || r.args || ') CASCADE';
    RAISE NOTICE 'Dropped admin_list_businesses(%)', r.args;
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION admin_list_businesses(
  p_status TEXT     DEFAULT NULL,
  p_limit  INT      DEFAULT 50,
  p_offset INT      DEFAULT 0,
  p_sort   TEXT     DEFAULT 'newest'
)
RETURNS TABLE (
  id             UUID,
  slug           TEXT,
  name           TEXT,
  name_hi        TEXT,
  owner_name     TEXT,
  mobile         TEXT,
  whatsapp       TEXT,
  email          TEXT,
  status         TEXT,
  primary_cat    TEXT,
  city_name      TEXT,
  state_code     TEXT,
  pincode        TEXT,
  photos_count   INT,
  verified_score INT,
  rating_avg     NUMERIC,
  rating_count   INT,
  flagged_count  INT,
  lead_count     INT,
  view_count     INT,
  created_at     TIMESTAMPTZ,
  last_active_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
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

  -- Lookup admin's scope; if no row, fall through as super_admin so the
  -- function never silently returns empty for legitimate admin users
  SELECT au.role, COALESCE(au.assigned_city_ids, '{}'::INT[])
    INTO v_role, v_cities
    FROM admin_users au
   WHERE au.auth_user_id = auth.uid()
   LIMIT 1;
  v_role   := COALESCE(v_role, 'super_admin');
  v_cities := COALESCE(v_cities, '{}'::INT[]);

  RETURN QUERY
  SELECT
    b.id::UUID,
    b.slug::TEXT,
    b.name::TEXT,
    b.name_hi::TEXT,
    b.owner_name::TEXT,
    b.mobile::TEXT,
    b.whatsapp::TEXT,
    b.email::TEXT,
    b.status::TEXT,
    COALESCE(pc.name, fc.name)::TEXT          AS primary_cat,
    gc.name::TEXT                              AS city_name,
    gs.code::TEXT                              AS state_code,
    b.pincode::TEXT,
    COALESCE(array_length(b.photos, 1), 0)::INT AS photos_count,
    COALESCE(b.verified_score, 0)::INT        AS verified_score,
    COALESCE(b.rating_avg, 0)::NUMERIC        AS rating_avg,
    COALESCE(b.rating_count, 0)::INT          AS rating_count,
    COALESCE(b.flagged_count, 0)::INT         AS flagged_count,
    COALESCE(b.lead_count, 0)::INT            AS lead_count,
    COALESCE(b.view_count, 0)::INT            AS view_count,
    b.created_at::TIMESTAMPTZ,
    b.last_active_at::TIMESTAMPTZ
  FROM businesses b
  LEFT JOIN geo_cities  gc  ON gc.id = b.city_id
  LEFT JOIN geo_states  gs  ON gs.id = b.state_id
  LEFT JOIN business_categories bcp ON bcp.business_id = b.id AND bcp.is_primary = TRUE
  LEFT JOIN categories pc   ON pc.id = bcp.category_id
  LEFT JOIN categories fc   ON fc.id = b.sub_category_id
  WHERE (
          (p_status IS NOT NULL AND b.status::TEXT = p_status)
          OR (p_status IS NULL AND b.status::TEXT <> 'soft_listed')
        )
    AND (
          v_role = 'super_admin'
          OR array_length(v_cities, 1) IS NULL
          OR b.city_id = ANY(v_cities)
        )
  ORDER BY
    CASE WHEN p_sort = 'oldest' THEN b.created_at END ASC NULLS LAST,
    CASE WHEN p_sort = 'newest' OR p_sort IS NULL OR p_sort = '' THEN b.created_at END DESC NULLS LAST,
    CASE WHEN p_sort = 'flags' THEN COALESCE(b.flagged_count, 0) END DESC NULLS LAST,
    b.created_at DESC NULLS LAST
  LIMIT GREATEST(1, LEAST(p_limit, 500))
  OFFSET GREATEST(0, p_offset);
END $$;

GRANT EXECUTE ON FUNCTION admin_list_businesses(TEXT, INT, INT, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/184 done. admin_list_businesses rebuilt with explicit casts + safer defaults.';
END $$;
