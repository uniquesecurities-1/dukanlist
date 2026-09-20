-- ============================================================
-- db/220 — repair the two SEO RPCs from db/111
--
-- WHY
-- ---
-- Both functions in db/111-seo-honeypot.sql were written against a
-- schema DukanList does not have, so neither has EVER returned a row:
--
--   get_top_for_seo       -> 42703  column b.whatsapp_mobile does not exist
--   list_seo_combinations -> 42703  column b.primary_category_id does not exist
--
-- Consequences, live on the site until now:
--   * /top  and every /top/<cat>/<city> page showed
--     "Could not load. Please refresh." — including the "Top" link
--     in the main navigation.
--   * api/sitemap.js swallowed the failure with catch(_){ return [] },
--     so /top/ contributed 0 URLs to the sitemap.
--
-- The real column names:
--   b.whatsapp_mobile      -> b.whatsapp
--   b.primary_category_id  -> b.category_id   (plus b.sub_category_id)
--   b.address              -> b.address_line1 + b.address_line2
--   categories.id          -> INTEGER, not UUID
--   geo_cities.id          -> INTEGER, not UUID
--   geo_cities.slug        -> DOES NOT EXIST; the site derives the slug
--                             from the name (lower, spaces -> hyphens),
--                             exactly as api/sitemap.js and
--                             api/locality.js already do.
--
-- Also aligned with api/locality.js: asking for a PARENT category
-- (e.g. "healthcare") now includes its sub-categories, so /top and
-- /local agree instead of disagreeing.
-- ============================================================

BEGIN;

DROP FUNCTION IF EXISTS public.get_top_for_seo(TEXT, TEXT, INT);

CREATE OR REPLACE FUNCTION public.get_top_for_seo(
  p_category_slug TEXT,
  p_city_slug     TEXT,
  p_limit         INT DEFAULT 10
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
DECLARE
  v_cat_id      INT;
  v_cat_name    TEXT;
  v_cat_ids     INT[];
  v_city_id     INT;
  v_city_name   TEXT;
  v_state_name  TEXT := '';
  v_items       JSONB := '[]'::jsonb;
  v_limit       INT;
BEGIN
  v_limit := COALESCE(p_limit, 10);
  IF v_limit < 1 OR v_limit > 50 THEN v_limit := 10; END IF;

  -- Category slug -> id, plus every child id when it is a parent.
  IF p_category_slug IS NOT NULL AND p_category_slug <> '' THEN
    SELECT c.id, c.name INTO v_cat_id, v_cat_name
    FROM categories c
    WHERE c.slug = p_category_slug AND c.active IS NOT FALSE
    LIMIT 1;

    IF v_cat_id IS NOT NULL THEN
      SELECT array_agg(x.id) INTO v_cat_ids
      FROM (
        SELECT v_cat_id AS id
        UNION
        SELECT c2.id FROM categories c2 WHERE c2.parent_id = v_cat_id
      ) x;
    END IF;
  END IF;

  -- City slug -> id. geo_cities has no slug column, so match the same
  -- derivation the rest of the site uses: lower(name) with spaces as '-'.
  IF p_city_slug IS NOT NULL AND p_city_slug <> '' THEN
    SELECT c.id, c.name, COALESCE(s.name, '')
    INTO v_city_id, v_city_name, v_state_name
    FROM geo_cities c
    LEFT JOIN geo_districts d ON d.id = c.district_id
    LEFT JOIN geo_states    s ON s.id = d.state_id
    WHERE c.active IS NOT FALSE
      AND lower(regexp_replace(c.name, '\s+', '-', 'g')) = lower(p_city_slug)
    LIMIT 1;
  END IF;

  -- Ranked list. Score: rating, review volume, verification, photos, completeness.
  WITH scored AS (
    SELECT
      b.id, b.name, b.slug, b.mobile, b.whatsapp,
      b.photos, b.usp_text, b.about_text,
      NULLIF(concat_ws(', ', NULLIF(b.address_line1, ''), NULLIF(b.address_line2, '')), '') AS address,
      b.rating_avg, b.rating_count, b.verified_score, b.established_year,
      (
        COALESCE(b.rating_avg, 0) * 20
        + LEAST(COALESCE(b.rating_count, 0), 50) * 1.5
        + COALESCE(b.verified_score, 0) * 12
        + LEAST(COALESCE(array_length(b.photos, 1), 0), 10) * 2
        + (CASE WHEN length(COALESCE(b.usp_text, ''))   > 10 THEN 5 ELSE 0 END)
        + (CASE WHEN length(COALESCE(b.about_text, '')) > 50 THEN 5 ELSE 0 END)
      ) AS score
    FROM businesses b
    WHERE b.status = 'active'
      AND (v_cat_ids IS NULL
           OR b.category_id     = ANY(v_cat_ids)
           OR b.sub_category_id = ANY(v_cat_ids))
      AND (v_city_id IS NULL OR b.city_id = v_city_id)
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id',               s.id,
      'name',             s.name,
      'slug',             s.slug,
      'mobile',           s.mobile,
      'whatsapp',         s.whatsapp,
      'photo',            s.photos[1],
      'usp',              LEFT(COALESCE(s.usp_text, ''), 140),
      'address',          LEFT(COALESCE(s.address, ''), 200),
      'rating_avg',       COALESCE(s.rating_avg, 0),
      'rating_count',     COALESCE(s.rating_count, 0),
      'verified',         COALESCE(s.verified_score, 0) >= 1,
      'verified_score',   COALESCE(s.verified_score, 0),
      'established_year', s.established_year,
      'score',            ROUND(s.score::numeric, 1)
    ) ORDER BY s.score DESC, s.rating_count DESC), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT * FROM scored
    ORDER BY score DESC, rating_count DESC
    LIMIT v_limit
  ) AS s;

  RETURN jsonb_build_object(
    'items',         v_items,
    'count',         jsonb_array_length(v_items),
    'category_name', COALESCE(v_cat_name, 'Local Businesses'),
    'category_slug', p_category_slug,
    'city_name',     COALESCE(v_city_name, ''),
    'city_slug',     p_city_slug,
    'state_name',    v_state_name,
    'computed_at',   NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_top_for_seo(TEXT, TEXT, INT) TO anon, authenticated;


-- ============================================================
-- list_seo_combinations — feeds /top/<cat>/<city> into the sitemap.
-- Threshold stays at 3+ shops: a "Top 1" page is not worth indexing.
-- ============================================================
DROP FUNCTION IF EXISTS public.list_seo_combinations(INT);

CREATE OR REPLACE FUNCTION public.list_seo_combinations(p_limit INT DEFAULT 500)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
DECLARE v_result JSONB;
BEGIN
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 5000 THEN p_limit := 500; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'category_slug', cat_slug,
    'category_name', cat_name,
    'city_slug',     city_slug,
    'city_name',     city_name,
    'shop_count',    cnt
  )), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      cat.slug AS cat_slug,
      cat.name AS cat_name,
      lower(regexp_replace(cit.name, '\s+', '-', 'g')) AS city_slug,
      cit.name AS city_name,
      COUNT(*)  AS cnt
    FROM businesses b
    JOIN categories cat ON cat.id = b.category_id
    JOIN geo_cities cit ON cit.id = b.city_id
    WHERE b.status = 'active'
    GROUP BY cat.slug, cat.name, cit.name
    HAVING COUNT(*) >= 3
    ORDER BY COUNT(*) DESC
    LIMIT p_limit
  ) AS combos;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_seo_combinations(INT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- Sanity check — both should return rows, not an error.
DO $$
DECLARE r JSONB; n INT;
BEGIN
  r := public.get_top_for_seo('healthcare', 'mandi-dabwali', 12);
  RAISE NOTICE 'get_top_for_seo(healthcare, mandi-dabwali) -> % items, category=%',
    r->>'count', r->>'category_name';

  r := public.list_seo_combinations(200);
  n := jsonb_array_length(r);
  RAISE NOTICE 'list_seo_combinations -> % combinations with 3+ shops', n;
  RAISE NOTICE 'db/220 installed. /top pages should now load.';
END $$;
