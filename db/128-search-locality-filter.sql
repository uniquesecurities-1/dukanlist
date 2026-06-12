-- ============================================================
-- db/128 — Add p_locality_slug parameter to search_businesses
-- ============================================================
-- Extends search_businesses to accept an optional locality filter.
-- Keeps ALL existing logic (new-shop boost, multi-category, etc.).
-- Backward compatible: callers that omit p_locality_slug see no change.
--
-- IDEMPOTENT: replaces function. Existing grants preserved by re-grant.
-- DB never disturbed: forward-only migration.
-- ============================================================

BEGIN;

DROP FUNCTION IF EXISTS search_businesses(
  TEXT, TEXT, INT, SMALLINT, INT, INT, TEXT
);
DROP FUNCTION IF EXISTS search_businesses(
  TEXT, TEXT, INT, SMALLINT, INT, INT, TEXT, TEXT
);

CREATE OR REPLACE FUNCTION search_businesses(
  p_query         TEXT     DEFAULT NULL,
  p_category      TEXT     DEFAULT NULL,
  p_city_id       INT      DEFAULT NULL,
  p_state_id      SMALLINT DEFAULT NULL,
  p_limit         INT      DEFAULT 20,
  p_offset        INT      DEFAULT 0,
  p_pincode       TEXT     DEFAULT NULL,
  p_locality_slug TEXT     DEFAULT NULL    -- NEW: hyperlocal filter
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
  locality_name   TEXT,         -- NEW: surface locality in results
  locality_slug   TEXT,         -- NEW: for landing-page links
  pincode         TEXT,
  whatsapp        TEXT,
  mobile          TEXT,
  usp_text        TEXT,
  photos          TEXT[],
  hours_json      JSONB,
  rating_avg      NUMERIC,
  rating_count    INT,
  verified_score  SMALLINT,
  verified_visit  BOOLEAN,
  match_rank      REAL
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_cat_id   INT;
  v_pin_norm TEXT;
  v_q_lc     TEXT;
  v_loc_lc   TEXT;
BEGIN
  IF p_category IS NOT NULL THEN
    SELECT c.id INTO v_cat_id FROM categories c WHERE c.slug = p_category;
  END IF;

  IF p_pincode IS NOT NULL THEN
    v_pin_norm := regexp_replace(p_pincode, '\D', '', 'g');
    IF LENGTH(v_pin_norm) <> 6 THEN v_pin_norm := NULL; END IF;
  END IF;

  v_q_lc   := LOWER(TRIM(COALESCE(p_query, '')));
  v_loc_lc := LOWER(TRIM(COALESCE(p_locality_slug, '')));

  RETURN QUERY
  SELECT
    b.id, b.slug, b.name, b.name_hi,
    COALESCE(pc.slug, fc.slug)  AS category_slug,
    COALESCE(pc.name, fc.name)  AS category_name,
    COALESCE(pc.icon, fc.icon)  AS category_icon,
    b.address_line1, gc.name AS city_name,
    gl.name AS locality_name,
    gl.slug AS locality_slug,
    b.pincode,
    b.whatsapp, b.mobile,
    b.usp_text, b.photos,
    b.hours_json,
    b.rating_avg, b.rating_count,
    b.verified_score,
    COALESCE(b.verified_visit, FALSE) AS verified_visit,
    CASE
      WHEN p_query IS NULL THEN 1::REAL
      ELSE similarity(
        b.name || ' ' || COALESCE(b.usp_text,'') || ' ' || COALESCE(pc.name, fc.name, ''),
        p_query
      )
    END AS match_rank
  FROM businesses b
  JOIN geo_cities gc ON gc.id = b.city_id
  LEFT JOIN geo_localities gl ON gl.id = b.locality_id
  LEFT JOIN business_categories bcp ON bcp.business_id = b.id AND bcp.is_primary = TRUE
  LEFT JOIN categories pc ON pc.id = bcp.category_id
  LEFT JOIN categories fc ON fc.id = b.category_id
  WHERE b.status = 'active'
    AND (p_city_id  IS NULL OR b.city_id  = p_city_id)
    AND (p_state_id IS NULL OR b.state_id = p_state_id)
    AND (v_pin_norm IS NULL OR b.pincode = v_pin_norm)
    AND (v_loc_lc = '' OR gl.slug = v_loc_lc)
    AND (p_query IS NULL OR v_q_lc = '' OR (
         b.name           ILIKE '%' || p_query || '%'
      OR b.usp_text       ILIKE '%' || p_query || '%'
      OR COALESCE(b.about_text,'')   ILIKE '%' || p_query || '%'
      OR COALESCE(b.address_line1,'') ILIKE '%' || p_query || '%'
      OR LOWER(COALESCE(pc.name,''))     LIKE '%' || v_q_lc || '%'
      OR LOWER(COALESCE(pc.name_hi,''))  LIKE '%' || v_q_lc || '%'
      OR LOWER(COALESCE(pc.keywords,'')) LIKE '%' || v_q_lc || '%'
      OR LOWER(COALESCE(fc.name,''))     LIKE '%' || v_q_lc || '%'
      OR LOWER(COALESCE(fc.name_hi,''))  LIKE '%' || v_q_lc || '%'
      OR LOWER(COALESCE(fc.keywords,'')) LIKE '%' || v_q_lc || '%'
      OR EXISTS (
        SELECT 1 FROM business_categories bcx
        JOIN categories cx ON cx.id = bcx.category_id
        WHERE bcx.business_id = b.id
          AND (
            LOWER(COALESCE(cx.name,''))     LIKE '%' || v_q_lc || '%'
            OR LOWER(COALESCE(cx.name_hi,''))  LIKE '%' || v_q_lc || '%'
            OR LOWER(COALESCE(cx.keywords,'')) LIKE '%' || v_q_lc || '%'
          )
      )
    ))
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
  ORDER BY
    match_rank DESC NULLS LAST,
    COALESCE(b.verified_visit, FALSE) DESC,
    (COALESCE(b.verified_score, 0)
      + CASE WHEN b.created_at > NOW() - INTERVAL '14 days' THEN 2 ELSE 0 END
    ) DESC,
    b.rating_avg DESC NULLS LAST,
    b.name
  LIMIT GREATEST(1, LEAST(p_limit, 60))
  OFFSET GREATEST(0, p_offset);
END;
$$;

GRANT EXECUTE ON FUNCTION search_businesses(TEXT, TEXT, INT, SMALLINT, INT, INT, TEXT, TEXT)
  TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/128 installed.';
  RAISE NOTICE '  search_businesses now accepts p_locality_slug (optional).';
  RAISE NOTICE '  Result rows now include locality_name + locality_slug.';
END $$;
