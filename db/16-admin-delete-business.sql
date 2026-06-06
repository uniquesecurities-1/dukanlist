-- =====================================================
-- 16-admin-delete-business.sql
-- Hard delete a business with cascade + photo URL return
-- =====================================================
-- WHAT THIS DOES:
--   1. admin_delete_business(business_id)
--      - Verifies caller is admin (via is_admin())
--      - Captures stats + photo URLs BEFORE delete
--      - Hard-deletes from `businesses` table
--      - CASCADE handles: business_categories, business_owners,
--        leads_log, reviews, flags (all have ON DELETE CASCADE)
--      - Returns photo URLs so client can clean Supabase Storage
--   2. admin_list_all_businesses(search, status, limit, offset)
--      - Optional helper for an "All Businesses" admin view
--        (not strictly needed but useful for cleanup work)
--
-- PREREQUISITES: 01-15 SQL files executed
-- HOW TO RUN: Paste in Supabase SQL Editor → Run
-- IDEMPOTENT: CREATE OR REPLACE, safe to re-run
-- =====================================================


-- =====================================================
-- SECTION 1: admin_delete_business()
-- =====================================================
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
  v_photos        TEXT[];
  v_review_count  INT;
  v_lead_count    INT;
  v_category_count INT;
BEGIN
  -- ===== Admin check =====
  SELECT is_admin() INTO v_admin;
  IF NOT v_admin THEN
    RAISE EXCEPTION 'Admin only — only administrators can delete businesses';
  END IF;

  -- ===== Sanity =====
  SELECT name, slug, COALESCE(photos, ARRAY[]::TEXT[])
    INTO v_biz_name, v_biz_slug, v_photos
  FROM businesses
  WHERE id = p_business_id;

  IF v_biz_name IS NULL THEN
    RAISE EXCEPTION 'Business not found (id: %)', p_business_id;
  END IF;

  -- ===== Capture related counts (for return / audit) =====
  SELECT COUNT(*)::INT INTO v_review_count
  FROM reviews WHERE business_id = p_business_id;

  SELECT COUNT(*)::INT INTO v_lead_count
  FROM leads_log WHERE business_id = p_business_id;

  SELECT COUNT(*)::INT INTO v_category_count
  FROM business_categories WHERE business_id = p_business_id;

  -- ===== Hard delete =====
  -- CASCADE on FKs handles:
  --   business_categories (junction)
  --   business_owners
  --   leads_log
  --   reviews
  --   flags
  -- And trg_update_cat_count trigger decrements category business_count.
  DELETE FROM businesses WHERE id = p_business_id;

  -- ===== Return everything client needs =====
  RETURN jsonb_build_object(
    'success',         true,
    'business_id',     p_business_id,
    'business_name',   v_biz_name,
    'business_slug',   v_biz_slug,
    'photos_to_cleanup', COALESCE(to_jsonb(v_photos), '[]'::jsonb),
    'photo_count',     COALESCE(array_length(v_photos, 1), 0),
    'review_count',    v_review_count,
    'lead_count',      v_lead_count,
    'category_count',  v_category_count,
    'deleted_at',      NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_delete_business(UUID) TO authenticated;


-- =====================================================
-- SECTION 2: admin_list_all_businesses() — helper view
-- =====================================================
-- Returns ALL businesses (any status) — useful for cleanup
-- =====================================================
CREATE OR REPLACE FUNCTION admin_list_all_businesses(
  p_search TEXT   DEFAULT NULL,
  p_status TEXT   DEFAULT NULL,   -- 'pending' / 'active' / 'banned' / NULL=all
  p_limit  INT    DEFAULT 50,
  p_offset INT    DEFAULT 0
)
RETURNS TABLE (
  id              UUID,
  slug            TEXT,
  name            TEXT,
  owner_name      TEXT,
  mobile          TEXT,
  status          TEXT,
  city_name       TEXT,
  pincode         TEXT,
  created_at      TIMESTAMPTZ,
  view_count      INT,
  lead_count      INT,
  rating_avg      NUMERIC,
  flagged_count   INT,
  photos_count    INT,
  primary_cat     TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_admin BOOLEAN;
BEGIN
  SELECT is_admin() INTO v_admin;
  IF NOT v_admin THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  RETURN QUERY
  SELECT
    b.id, b.slug, b.name, b.owner_name, b.mobile,
    b.status::TEXT,
    gc.name AS city_name,
    b.pincode,
    b.created_at,
    COALESCE(b.view_count, 0)        AS view_count,
    COALESCE(b.lead_count, 0)        AS lead_count,
    b.rating_avg,
    COALESCE(b.flagged_count, 0)     AS flagged_count,
    COALESCE(array_length(b.photos, 1), 0) AS photos_count,
    COALESCE(pc.name, fc.name)       AS primary_cat
  FROM businesses b
  LEFT JOIN geo_cities gc ON gc.id = b.city_id
  LEFT JOIN business_categories bcp ON bcp.business_id = b.id AND bcp.is_primary = TRUE
  LEFT JOIN categories pc ON pc.id = bcp.category_id
  LEFT JOIN categories fc ON fc.id = b.category_id
  WHERE (p_status IS NULL OR b.status::TEXT = p_status)
    AND (
      p_search IS NULL
      OR b.name      ILIKE '%' || p_search || '%'
      OR b.mobile    ILIKE '%' || p_search || '%'
      OR b.owner_name ILIKE '%' || p_search || '%'
      OR b.slug       ILIKE '%' || p_search || '%'
    )
  ORDER BY b.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_list_all_businesses(TEXT, TEXT, INT, INT) TO authenticated;


-- =====================================================
-- Reload PostgREST schema cache
-- =====================================================
NOTIFY pgrst, 'reload schema';


-- =====================================================
-- VERIFICATION
-- =====================================================
-- 1) Functions exist:
--    SELECT proname FROM pg_proc WHERE proname IN
--      ('admin_delete_business','admin_list_all_businesses');
--    (expect 2 rows)
--
-- 2) Test delete (REPLACE with a real test business UUID):
--    SELECT admin_delete_business('YOUR-TEST-UUID-HERE'::uuid);
--    Expected output:
--    {
--      "success": true,
--      "business_name": "...",
--      "photos_to_cleanup": ["url1", "url2", ...],
--      "photo_count": 2,
--      "review_count": 0,
--      "lead_count": 5,
--      "category_count": 1,
--      "deleted_at": "..."
--    }
--
-- 3) List all (admin only):
--    SELECT * FROM admin_list_all_businesses(NULL, NULL, 20, 0);
-- =====================================================
