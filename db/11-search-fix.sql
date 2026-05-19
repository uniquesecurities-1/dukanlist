-- =====================================================
-- 11-search-fix.sql
-- Fix: "column reference 'id' is ambiguous" in search_businesses
-- =====================================================
-- Cause: unqualified `id` in nested SELECT inside the function
--        conflicted with the RETURNS TABLE 'id' OUT parameter.
-- Fix:   alias every category lookup and qualify columns explicitly.
-- Run AFTER 08-rpc-multi-cat-update.sql (replaces the function in-place)
-- =====================================================

CREATE OR REPLACE FUNCTION search_businesses(
  p_query     TEXT     DEFAULT NULL,
  p_category  TEXT     DEFAULT NULL,
  p_city_id   INT      DEFAULT NULL,
  p_state_id  SMALLINT DEFAULT NULL,
  p_limit     INT      DEFAULT 20,
  p_offset    INT      DEFAULT 0
)
RETURNS TABLE (
  id              UUID,
  slug            TEXT,
  name            TEXT,
  name_hi         TEXT,
  category_slug   TEXT,
  category_name   TEXT,
  category_icon   TEXT,
  address_line1   TEXT,
  city_name       TEXT,
  pincode         TEXT,
  whatsapp        TEXT,
  mobile          TEXT,
  usp_text        TEXT,
  photos          TEXT[],
  rating_avg      NUMERIC,
  rating_count    INT,
  verified_score  SMALLINT,
  match_rank      REAL
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_cat_id INT;
BEGIN
  -- Resolve category slug to ID
  IF p_category IS NOT NULL THEN
    SELECT cat0.id INTO v_cat_id
    FROM categories AS cat0
    WHERE cat0.slug = p_category AND cat0.active = TRUE;
  END IF;

  RETURN QUERY
  SELECT
    b.id,
    b.slug,
    b.name,
    b.name_hi,
    COALESCE(pc.slug, fc.slug)  AS category_slug,
    COALESCE(pc.name, fc.name)  AS category_name,
    COALESCE(pc.icon, fc.icon)  AS category_icon,
    b.address_line1,
    gc.name AS city_name,
    b.pincode,
    b.whatsapp,
    b.mobile,
    b.usp_text,
    b.photos,
    b.rating_avg,
    b.rating_count,
    b.verified_score,
    CASE
      WHEN p_query IS NULL THEN 1::REAL
      ELSE similarity(b.name || ' ' || COALESCE(b.usp_text,''), p_query)
    END AS match_rank
  FROM businesses AS b
  JOIN geo_cities AS gc              ON gc.id = b.city_id
  LEFT JOIN business_categories AS bcp ON bcp.business_id = b.id AND bcp.is_primary = TRUE
  LEFT JOIN categories AS pc           ON pc.id = bcp.category_id
  LEFT JOIN categories AS fc           ON fc.id = b.category_id
  WHERE b.status = 'active'
    AND (p_city_id  IS NULL OR b.city_id  = p_city_id)
    AND (p_state_id IS NULL OR b.state_id = p_state_id)
    AND (
      p_query IS NULL
      OR b.name ILIKE '%' || p_query || '%'
      OR b.usp_text ILIKE '%' || p_query || '%'
    )
    AND (
      p_category IS NULL
      OR EXISTS (
        SELECT 1
        FROM business_categories AS bc_ex
        WHERE bc_ex.business_id = b.id
          AND (
            bc_ex.category_id = v_cat_id
            OR bc_ex.category_id IN (
              SELECT cat_sub.id
              FROM categories AS cat_sub
              WHERE cat_sub.parent_id = v_cat_id
            )
          )
      )
      OR (
        NOT EXISTS (
          SELECT 1 FROM business_categories AS bc_nx WHERE bc_nx.business_id = b.id
        )
        AND (b.category_id = v_cat_id OR b.sub_category_id = v_cat_id)
      )
    )
  ORDER BY match_rank DESC, b.verified_score DESC, b.rating_avg DESC, b.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

NOTIFY pgrst, 'reload schema';


-- =====================================================
-- VERIFICATION
-- =====================================================
-- After running, test:
--   SELECT id, name, slug, category_name FROM search_businesses();
-- Should return 2 rows (Unique Securities + Sharma Clinic)
--
--   SELECT id, name FROM search_businesses(p_query := 'unique');
-- Should return Unique Securities
--
--   SELECT id, name FROM search_businesses(p_category := 'financial-services');
-- Should return Unique Securities (financial-services is parent)
--
--   SELECT id, name FROM search_businesses(p_category := 'mutual-fund-distributor');
-- Should return Unique Securities (MFD is primary sub-category in junction)
-- =====================================================
