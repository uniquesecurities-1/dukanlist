-- =====================================================
-- 10-admin-polish.sql
-- Admin UX polish: profile RPC + category fallback
-- =====================================================
-- Run AFTER 09-admin-schema.sql
-- =====================================================


-- =====================================================
-- 1. get_admin_profile — fetch own display_name + role
-- =====================================================
-- Avoids RLS issue on admin_users when reading display_name
-- =====================================================

CREATE OR REPLACE FUNCTION get_admin_profile()
RETURNS TABLE (
  display_name TEXT,
  role         TEXT,
  email        TEXT,
  added_at     TIMESTAMPTZ
)
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  RETURN QUERY
  SELECT a.display_name, a.role, a.email, a.added_at
  FROM admin_users a
  WHERE a.auth_user_id = auth.uid();
END;
$$;


-- =====================================================
-- 2. admin_list_businesses — fallback to businesses.category_id
--    when no junction entry exists (for pre-Phase 2 listings)
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
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  RETURN QUERY
  SELECT
    b.id, b.slug, b.name, b.name_hi, b.owner_name,
    b.mobile, b.whatsapp, b.email, b.status,
    -- Junction primary first, fallback to businesses.sub_category_id, then category_id
    COALESCE(pc.name, sc.name, fc.name) AS primary_cat,
    gc.name AS city_name, gs.code AS state_code, b.pincode,
    COALESCE(array_length(b.photos, 1), 0) AS photos_count,
    b.verified_score, b.rating_avg, b.rating_count,
    b.flagged_count, b.lead_count, b.view_count,
    b.created_at, b.last_active_at
  FROM businesses b
  LEFT JOIN business_categories bcp ON bcp.business_id = b.id AND bcp.is_primary = TRUE
  LEFT JOIN categories pc           ON pc.id = bcp.category_id
  LEFT JOIN categories sc           ON sc.id = b.sub_category_id
  LEFT JOIN categories fc           ON fc.id = b.category_id
  LEFT JOIN geo_cities  gc          ON gc.id = b.city_id
  LEFT JOIN geo_states  gs          ON gs.id = b.state_id
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
-- 3. Backfill business_categories for pre-Phase 2 businesses
-- =====================================================
-- If a business has businesses.sub_category_id set (or category_id) but
-- no entry in business_categories junction, add it as primary.
-- This makes search + display consistent.
-- =====================================================

INSERT INTO business_categories (business_id, category_id, is_primary)
SELECT b.id, COALESCE(b.sub_category_id, b.category_id), TRUE
FROM businesses b
WHERE NOT EXISTS (
  SELECT 1 FROM business_categories bc WHERE bc.business_id = b.id
)
AND COALESCE(b.sub_category_id, b.category_id) IS NOT NULL
ON CONFLICT (business_id, category_id) DO NOTHING;


NOTIFY pgrst, 'reload schema';


-- =====================================================
-- VERIFY
-- =====================================================
-- After running, check:
--   SELECT * FROM get_admin_profile();   -- (must be logged in via auth, won't work in SQL editor)
--   SELECT * FROM admin_list_businesses(p_limit := 5);
--   SELECT business_id, category_id, is_primary FROM business_categories;
-- =====================================================
