-- =====================================================
-- db/111-seo-honeypot.sql
-- =====================================================
-- STRATEGIC PHASE 7 (2026-06-05):
--   SEO Honeypot — auto-generated "Top X in [city]" landing
--   pages capture high-intent organic traffic.
--
--   Target queries:
--     "best kirana store in Mandi Dabwali"
--     "top 10 medical stores Sirsa"
--     "best mobile repair shop Bathinda"
--
--   Small-town SEO has LOW competition + HIGH commercial intent.
--   Every category × city combo becomes a unique landing page.
--
-- TWO RPCs:
--
-- 1. get_top_for_seo(category_slug, city_slug, limit)
--    Returns top-N businesses for a category-city combo, ranked
--    by composite score (rating × verification × completeness).
--    Public anon — used by /top.html landing pages.
--
-- 2. list_seo_combinations(limit)
--    Returns list of (category_slug, city_slug) combinations
--    that have 3+ active shops. Used by sitemap generator to
--    decide which /top/[cat]/[city] URLs to include.
--
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

DROP FUNCTION IF EXISTS get_top_for_seo(TEXT, TEXT, INT);
CREATE OR REPLACE FUNCTION get_top_for_seo(
  p_category_slug TEXT,
  p_city_slug     TEXT,
  p_limit         INT DEFAULT 10
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_cat_id      UUID;
  v_cat_name    TEXT;
  v_cat_parent  TEXT;
  v_city_id     UUID;
  v_city_name   TEXT;
  v_state_name  TEXT;
  v_items       JSONB := '[]'::jsonb;
  v_total       INT := 0;
  v_limit       INT;
BEGIN
  v_limit := COALESCE(p_limit, 10);
  IF v_limit < 1 OR v_limit > 50 THEN v_limit := 10; END IF;

  -- Resolve category slug → ID + name + parent
  IF p_category_slug IS NOT NULL THEN
    BEGIN
      SELECT id, name INTO v_cat_id, v_cat_name
      FROM categories WHERE slug = p_category_slug LIMIT 1;
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  -- Resolve city slug → ID + name
  IF p_city_slug IS NOT NULL THEN
    BEGIN
      SELECT c.id, c.name, COALESCE(s.name, '')
      INTO v_city_id, v_city_name, v_state_name
      FROM geo_cities c
      LEFT JOIN geo_districts d ON d.id = c.district_id
      LEFT JOIN geo_states s ON s.id = d.state_id
      WHERE c.slug = p_city_slug LIMIT 1;
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  -- Build ranked list
  -- Composite score: rating × log(reviews+1) + verification + photos + completeness
  WITH scored AS (
    SELECT
      b.id, b.name, b.slug, b.mobile, b.whatsapp_mobile,
      b.photos, b.usp_text, b.about_text, b.address,
      b.rating_avg, b.rating_count,
      b.verified_score, b.established_year,
      b.hours_json, b.city_id, b.primary_category_id,
      (
        COALESCE(b.rating_avg, 0) * 20
        + LEAST(COALESCE(b.rating_count, 0), 50) * 1.5
        + COALESCE(b.verified_score, 0) * 12
        + LEAST(COALESCE(array_length(b.photos, 1), 0), 10) * 2
        + (CASE WHEN length(COALESCE(b.usp_text, '')) > 10 THEN 5 ELSE 0 END)
        + (CASE WHEN length(COALESCE(b.about_text, '')) > 50 THEN 5 ELSE 0 END)
      ) AS score
    FROM businesses b
    WHERE b.status = 'active'
      AND (v_cat_id IS NULL OR b.primary_category_id = v_cat_id)
      AND (v_city_id IS NULL OR b.city_id = v_city_id)
  )
  SELECT
    COALESCE(jsonb_agg(jsonb_build_object(
      'id',           s.id,
      'name',         s.name,
      'slug',         s.slug,
      'mobile',       s.mobile,
      'whatsapp',     s.whatsapp_mobile,
      'photo',        s.photos[1],
      'usp',          LEFT(COALESCE(s.usp_text, ''), 140),
      'address',      LEFT(COALESCE(s.address, ''), 200),
      'rating_avg',   COALESCE(s.rating_avg, 0),
      'rating_count', COALESCE(s.rating_count, 0),
      'verified',     COALESCE(s.verified_score, 0) >= 1,
      'verified_score', COALESCE(s.verified_score, 0),
      'established_year', s.established_year,
      'score',        ROUND(s.score::numeric, 1)
    ) ORDER BY s.score DESC, s.rating_count DESC), '[]'::jsonb),
    COUNT(*)
  INTO v_items, v_total
  FROM (
    SELECT * FROM scored
    ORDER BY score DESC, rating_count DESC
    LIMIT v_limit
  ) AS s;

  RETURN jsonb_build_object(
    'items',         v_items,
    'count',         jsonb_array_length(v_items),
    'category_name', COALESCE(v_cat_name, 'All categories'),
    'category_slug', p_category_slug,
    'city_name',     COALESCE(v_city_name, 'All cities'),
    'city_slug',     p_city_slug,
    'state_name',    v_state_name,
    'computed_at',   NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_top_for_seo(TEXT, TEXT, INT) TO authenticated, anon;


-- ============================================================
-- list_seo_combinations — for sitemap generator
-- Returns combos with 3+ active shops (worth indexing)
-- ============================================================
DROP FUNCTION IF EXISTS list_seo_combinations(INT);
CREATE OR REPLACE FUNCTION list_seo_combinations(p_limit INT DEFAULT 500)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE v_result JSONB;
BEGIN
  IF p_limit < 1 OR p_limit > 5000 THEN p_limit := 500; END IF;

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
      cit.slug AS city_slug,
      cit.name AS city_name,
      COUNT(*) AS cnt
    FROM businesses b
    JOIN categories cat ON cat.id = b.primary_category_id
    JOIN geo_cities  cit ON cit.id = b.city_id
    WHERE b.status = 'active'
    GROUP BY cat.slug, cat.name, cit.slug, cit.name
    HAVING COUNT(*) >= 3
    ORDER BY COUNT(*) DESC
    LIMIT p_limit
  ) AS combos;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION list_seo_combinations(INT) TO authenticated, anon;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'db/111 installed.';
  RAISE NOTICE '  RPC: get_top_for_seo(cat_slug, city_slug, limit)';
  RAISE NOTICE '  RPC: list_seo_combinations(limit)';
END $$;
