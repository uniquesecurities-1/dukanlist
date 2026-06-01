-- =====================================================
-- db/85-search-include-verified-visit.sql
-- =====================================================
-- Phase 2C of approval/verification decoupling (db/84).
--
-- WHY:
--   search.html now exposes a strict "Verified" filter that needs
--   b.verified_visit on each row, but search_businesses() from db/69
--   only returns verified_score. Without verified_visit in the result
--   set, the client filter always returns 0 rows.
--
--   Additionally, we want verified shops to rank slightly higher in
--   relevance ties. The existing ORDER BY uses verified_score, which
--   was auto-bumped by mobile/photo flags and is no longer a reliable
--   trust signal. We add b.verified_visit as a higher-priority tiebreak.
--
-- THIS PATCH (zero risk, signature-preserving for callers that use
-- positional access on the original columns):
--   1. Drop + recreate search_businesses with EXACT same parameter
--      signature, EXACT same first 17 return columns, and APPENDS
--      verified_visit BOOLEAN as column #18 plus match_rank as #19.
--      ← match_rank was already last; we slot verified_visit before it.
--   2. ORDER BY now boosts verified_visit shops first within each
--      relevance bucket.
--
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

DROP FUNCTION IF EXISTS search_businesses(
  TEXT, TEXT, INT, SMALLINT, INT, INT, TEXT
);

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
  verified_visit  BOOLEAN,
  match_rank      REAL
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_cat_id   INT;
  v_pin_norm TEXT;
  v_q_lc     TEXT;
BEGIN
  -- Resolve category slug to ID
  IF p_category IS NOT NULL THEN
    SELECT c.id INTO v_cat_id FROM categories c WHERE c.slug = p_category;
  END IF;

  -- Normalise pincode
  IF p_pincode IS NOT NULL THEN
    v_pin_norm := regexp_replace(p_pincode, '\D', '', 'g');
    IF LENGTH(v_pin_norm) <> 6 THEN v_pin_norm := NULL; END IF;
  END IF;

  v_q_lc := LOWER(TRIM(COALESCE(p_query, '')));

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
  LEFT JOIN business_categories bcp ON bcp.business_id = b.id AND bcp.is_primary = TRUE
  LEFT JOIN categories pc ON pc.id = bcp.category_id
  LEFT JOIN categories fc ON fc.id = b.category_id
  WHERE b.status = 'active'
    AND (p_city_id  IS NULL OR b.city_id  = p_city_id)
    AND (p_state_id IS NULL OR b.state_id = p_state_id)
    AND (v_pin_norm IS NULL OR b.pincode = v_pin_norm)
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
  -- Sort boost: verified_visit shops surface first within each
  -- relevance / rating bucket. verified_score is kept as a softer
  -- tiebreak below it but no longer drives the badge.
  ORDER BY
    match_rank DESC NULLS LAST,
    COALESCE(b.verified_visit, FALSE) DESC,
    b.verified_score DESC NULLS LAST,
    b.rating_avg DESC NULLS LAST,
    b.name
  LIMIT GREATEST(1, LEAST(p_limit, 60))
  OFFSET GREATEST(0, p_offset);
END;
$$;

GRANT EXECUTE ON FUNCTION search_businesses(TEXT, TEXT, INT, SMALLINT, INT, INT, TEXT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- VERIFY
-- =====================================================
DO $$
DECLARE
  v_count INT;
  v_cols  INT;
BEGIN
  SELECT COUNT(*) INTO v_count FROM pg_proc WHERE proname = 'search_businesses';
  SELECT COUNT(*) INTO v_cols
    FROM information_schema.routines r
    JOIN information_schema.parameters p
      ON p.specific_name = r.specific_name
    WHERE r.routine_name = 'search_businesses'
      AND p.parameter_name = 'verified_visit';
  RAISE NOTICE 'search_businesses installed: %', v_count;
  RAISE NOTICE 'verified_visit return column wired: %', v_cols;
END $$;
