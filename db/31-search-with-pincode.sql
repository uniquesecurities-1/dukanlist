-- =====================================================
-- db/31-search-with-pincode.sql
-- Add p_pincode param to search_businesses() RPC.
-- =====================================================
-- ADDITIVE: drops the old signature and creates a new one with an extra
-- optional parameter. Existing callers (search.html, index.html, browse.html)
-- that don't pass p_pincode get NULL by default = no filter = same behavior.
-- =====================================================
BEGIN;

DROP FUNCTION IF EXISTS search_businesses(TEXT, TEXT, INT, SMALLINT, INT, INT);
DROP FUNCTION IF EXISTS search_businesses(TEXT, TEXT, INT, SMALLINT, INT, INT, TEXT);

CREATE OR REPLACE FUNCTION search_businesses(
  p_query     TEXT     DEFAULT NULL,
  p_category  TEXT     DEFAULT NULL,
  p_city_id   INT      DEFAULT NULL,
  p_state_id  SMALLINT DEFAULT NULL,
  p_limit     INT      DEFAULT 20,
  p_offset    INT      DEFAULT 0,
  p_pincode   TEXT     DEFAULT NULL
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
  hours_json      JSONB,
  rating_avg      NUMERIC,
  rating_count    INT,
  verified_score  SMALLINT,
  match_rank      REAL
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_cat_id   INT;
  v_pin_norm TEXT;
BEGIN
  IF p_category IS NOT NULL THEN
    SELECT cat.id INTO v_cat_id FROM categories cat
    WHERE cat.slug = p_category AND cat.active = TRUE;
  END IF;

  -- Normalise pincode: strip spaces, only keep digits
  IF p_pincode IS NOT NULL AND length(trim(p_pincode)) > 0 THEN
    v_pin_norm := regexp_replace(p_pincode, '\D', '', 'g');
    IF length(v_pin_norm) = 0 THEN v_pin_norm := NULL; END IF;
  END IF;

  RETURN QUERY
  SELECT
    b.id, b.slug, b.name, b.name_hi,
    COALESCE(pc.slug, fc.slug)  AS category_slug,
    COALESCE(pc.name, fc.name)  AS category_name,
    COALESCE(pc.icon, fc.icon)  AS category_icon,
    b.address_line1, gc.name AS city_name, b.pincode,
    b.whatsapp, b.mobile,
    b.usp_text, b.photos,
    b.hours_json,
    b.rating_avg, b.rating_count, b.verified_score,
    CASE
      WHEN p_query IS NULL THEN 1::REAL
      ELSE similarity(b.name || ' ' || COALESCE(b.usp_text,''), p_query)
    END AS match_rank
  FROM businesses b
  JOIN geo_cities gc ON gc.id = b.city_id
  LEFT JOIN business_categories bcp ON bcp.business_id = b.id AND bcp.is_primary = TRUE
  LEFT JOIN categories pc ON pc.id = bcp.category_id
  LEFT JOIN categories fc ON fc.id = b.category_id
  WHERE b.status = 'active'
    AND (p_city_id  IS NULL OR b.city_id  = p_city_id)
    AND (p_state_id IS NULL OR b.state_id = p_state_id)
    AND (v_pin_norm IS NULL OR b.pincode = v_pin_norm)
    AND (p_query    IS NULL OR (b.name ILIKE '%' || p_query || '%' OR b.usp_text ILIKE '%' || p_query || '%'))
    AND (
      p_category IS NULL
      OR EXISTS (
        SELECT 1 FROM business_categories bc
        WHERE bc.business_id = b.id
          AND (
            bc.category_id = v_cat_id
            OR bc.category_id IN (SELECT categories.id FROM categories WHERE categories.parent_id = v_cat_id)
          )
      )
      OR (
        NOT EXISTS (SELECT 1 FROM business_categories bc2 WHERE bc2.business_id = b.id)
        AND (b.category_id = v_cat_id OR b.sub_category_id = v_cat_id)
      )
    )
  ORDER BY match_rank DESC NULLS LAST, b.verified_score DESC NULLS LAST, b.rating_avg DESC NULLS LAST, b.name
  LIMIT GREATEST(1, LEAST(p_limit, 60))
  OFFSET GREATEST(0, p_offset);
END;
$$;

GRANT EXECUTE ON FUNCTION search_businesses(TEXT, TEXT, INT, SMALLINT, INT, INT, TEXT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- VERIFY:
-- SELECT id, name, pincode, city_name
--   FROM search_businesses(NULL, NULL, NULL, NULL, 10, 0, '125104');
-- (Returns only Mandi Dabwali shops with that pincode.)
-- =====================================================
