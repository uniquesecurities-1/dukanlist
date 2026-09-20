-- ============================================================
-- db/221 — shared ranking engine
--
-- /top proved that a visible rank changes shopkeeper behaviour. This
-- file makes that rank available everywhere instead of only on /top,
-- and — critically — makes ONE scoring formula the single source of
-- truth, so the number a shopkeeper sees in their panel is the same
-- number that decides their position on /top. Two formulas would mean
-- two different answers to "what rank am I", which destroys trust in
-- the whole idea.
--
-- Provides:
--   dl_shop_score(...)       IMMUTABLE — the formula, one copy
--   get_shop_rank(uuid)      rank within category+city, gap to the next
--                            place, and the specific actions that close it
--   get_empty_thrones(...)   categories in a city with no listing at all
--   get_locality_ranked(...) shops in a locality, ranked
--
-- Requires db/220 (which repaired get_top_for_seo). Safe to re-run.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- The formula. Identical to the one inside get_top_for_seo.
-- Kept IMMUTABLE and parameterised so it can be called from a
-- SELECT list, an ORDER BY, or an index later on.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.dl_shop_score(
  p_rating_avg     NUMERIC,
  p_rating_count   INT,
  p_verified_score INT,
  p_photos         TEXT[],
  p_usp_text       TEXT,
  p_about_text     TEXT
)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT ROUND((
      COALESCE(p_rating_avg, 0) * 20
    + LEAST(COALESCE(p_rating_count, 0), 50) * 1.5
    + COALESCE(p_verified_score, 0) * 12
    + LEAST(COALESCE(array_length(p_photos, 1), 0), 10) * 2
    + (CASE WHEN length(COALESCE(p_usp_text, ''))   > 10 THEN 5 ELSE 0 END)
    + (CASE WHEN length(COALESCE(p_about_text, '')) > 50 THEN 5 ELSE 0 END)
  )::numeric, 1);
$$;


-- ------------------------------------------------------------
-- get_shop_rank — "where do I stand, and what closes the gap?"
--
-- Ranks the shop against others in the SAME category and city, which
-- is the comparison a shopkeeper actually feels. Returns the honest
-- rank plus `public_ok`: the caller shows the badge publicly only when
-- the position flatters the shop. A listing sitting at #14 of 15 must
-- never have that broadcast on its own page — it would cost the owner
-- customers, and DukanList exists to bring them customers.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_shop_rank(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
DECLARE
  v_cat_id    INT;
  v_city_id   INT;
  v_cat_name  TEXT;
  v_cat_slug  TEXT;
  v_city_name TEXT;
  v_rank      INT;
  v_total     INT;
  v_score     NUMERIC;
  v_next      NUMERIC;
  v_top_score NUMERIC;
  v_b         RECORD;
  v_tips      JSONB := '[]'::jsonb;
BEGIN
  SELECT b.category_id, b.city_id, b.rating_avg, b.rating_count,
         b.verified_score, b.photos, b.usp_text, b.about_text
  INTO v_b
  FROM businesses b
  WHERE b.id = p_business_id AND b.status = 'active';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('found', false);
  END IF;

  v_cat_id  := v_b.category_id;
  v_city_id := v_b.city_id;

  SELECT c.name, c.slug INTO v_cat_name, v_cat_slug FROM categories c WHERE c.id = v_cat_id;
  SELECT g.name          INTO v_city_name          FROM geo_cities g WHERE g.id = v_city_id;

  -- Peer group: same city, sharing this category as either the primary or the
  -- secondary one. This matches how get_top_for_seo selects a category's shops,
  -- so the rank here and the position on /top are the same number.
  WITH peers AS (
    SELECT b.id,
           dl_shop_score(b.rating_avg, b.rating_count, b.verified_score,
                         b.photos, b.usp_text, b.about_text) AS score
    FROM businesses b
    WHERE b.status = 'active'
      AND b.city_id = v_city_id
      AND (b.category_id = v_cat_id OR b.sub_category_id = v_cat_id)
  ), ranked AS (
    SELECT id, score, ROW_NUMBER() OVER (ORDER BY score DESC, id) AS rn
    FROM peers
  )
  SELECT r.rn, r.score,
         (SELECT COUNT(*) FROM peers),
         (SELECT r2.score FROM ranked r2 WHERE r2.rn = r.rn - 1),
         (SELECT MAX(score) FROM peers)
  INTO v_rank, v_score, v_total, v_next, v_top_score
  FROM ranked r
  WHERE r.id = p_business_id;

  IF v_rank IS NULL THEN
    RETURN jsonb_build_object('found', false);
  END IF;

  -- Concrete, honest next steps. Only things the owner controls, each
  -- with the exact points it is worth, so the advice is checkable.
  IF COALESCE(array_length(v_b.photos, 1), 0) < 10 THEN
    v_tips := v_tips || jsonb_build_object(
      'action', 'photos',
      'label',  'Add ' || LEAST(10 - COALESCE(array_length(v_b.photos, 1), 0), 3)::text || ' more photo(s)',
      'points', LEAST(10 - COALESCE(array_length(v_b.photos, 1), 0), 3) * 2,
      'href',   '/panel/photos.html');
  END IF;

  IF COALESCE(v_b.rating_count, 0) < 50 THEN
    v_tips := v_tips || jsonb_build_object(
      'action', 'reviews',
      'label',  'Get 3 more customer reviews',
      'points', 4.5,
      'href',   '/panel/get-reviews.html');
  END IF;

  IF length(COALESCE(v_b.usp_text, '')) <= 10 THEN
    v_tips := v_tips || jsonb_build_object(
      'action', 'usp', 'label', 'Write your one-line speciality',
      'points', 5, 'href', '/panel/profile.html#usp');
  END IF;

  IF length(COALESCE(v_b.about_text, '')) <= 50 THEN
    v_tips := v_tips || jsonb_build_object(
      'action', 'about', 'label', 'Write an "About us" (50+ characters)',
      'points', 5, 'href', '/panel/profile.html#about');
  END IF;

  IF COALESCE(v_b.verified_score, 0) < 3 THEN
    v_tips := v_tips || jsonb_build_object(
      'action', 'verify', 'label', 'Complete verification',
      'points', (3 - COALESCE(v_b.verified_score, 0)) * 12,
      'href',   '/panel/dashboard.html#verify');
  END IF;

  RETURN jsonb_build_object(
    'found',         true,
    'rank',          v_rank,
    'total',         v_total,
    'score',         v_score,
    'top_score',     v_top_score,
    'gap_to_next',   CASE WHEN v_next IS NULL THEN 0
                          ELSE GREATEST(ROUND(v_next - v_score + 0.1, 1), 0) END,
    'category_name', v_cat_name,
    'category_slug', v_cat_slug,
    'city_name',     v_city_name,
    'tips',          v_tips,
    -- Show publicly only when it helps the shop: top 3, or the better
    -- half of a list long enough for "half" to mean anything.
    'public_ok',     (v_total >= 3) AND (v_rank <= 3 OR v_rank::numeric <= v_total::numeric / 2)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_shop_rank(UUID) TO anon, authenticated;


-- ------------------------------------------------------------
-- get_empty_thrones — categories in a city with nobody in them.
--
-- "Be the first" is a far stronger pitch than "join 199 others", and
-- it answers the question an unlisted shopkeeper actually asks. Only
-- leaf categories: "no #1 in Healthcare" is meaningless, "no #1 in
-- Sweet Shop" is a real, claimable position.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_empty_thrones(
  p_city_slug TEXT,
  p_limit     INT DEFAULT 24
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
DECLARE
  v_city_id   INT;
  v_city_name TEXT;
  v_result    JSONB;
BEGIN
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 200 THEN p_limit := 24; END IF;

  SELECT c.id, c.name INTO v_city_id, v_city_name
  FROM geo_cities c
  WHERE c.active IS NOT FALSE
    AND lower(regexp_replace(c.name, '\s+', '-', 'g')) = lower(COALESCE(p_city_slug, ''))
  LIMIT 1;

  IF v_city_id IS NULL THEN
    RETURN jsonb_build_object('found', false, 'items', '[]'::jsonb);
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'slug', slug, 'name', name, 'name_hi', name_hi, 'icon', icon
         ) ORDER BY sort_order NULLS LAST, name), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT cat.slug, cat.name, cat.name_hi, cat.icon, cat.sort_order
    FROM categories cat
    WHERE cat.active IS NOT FALSE
      AND cat.parent_id IS NOT NULL                    -- leaf categories only
      AND NOT EXISTS (
        SELECT 1 FROM businesses b
        WHERE b.status = 'active'
          AND b.city_id = v_city_id
          AND (b.category_id = cat.id OR b.sub_category_id = cat.id)
      )
    LIMIT p_limit
  ) t;

  RETURN jsonb_build_object(
    'found',     true,
    'city_name', v_city_name,
    'city_slug', p_city_slug,
    'items',     v_result
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_empty_thrones(TEXT, INT) TO anon, authenticated;


-- ------------------------------------------------------------
-- get_locality_ranked — the same score, but the peer group is the
-- street rather than the whole city. A shopkeeper compares himself
-- to the shop across the road long before he compares himself to
-- the whole of Mandi Dabwali.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_locality_ranked(
  p_city_slug     TEXT,
  p_locality_slug TEXT,
  p_limit         INT DEFAULT 50
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
DECLARE
  v_city_id INT;
  v_loc_id  INT;
  v_result  JSONB;
BEGIN
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 200 THEN p_limit := 50; END IF;

  SELECT c.id INTO v_city_id
  FROM geo_cities c
  WHERE c.active IS NOT FALSE
    AND lower(regexp_replace(c.name, '\s+', '-', 'g')) = lower(COALESCE(p_city_slug, ''))
  LIMIT 1;

  IF v_city_id IS NULL THEN RETURN '[]'::jsonb; END IF;

  SELECT l.id INTO v_loc_id
  FROM geo_localities l
  WHERE l.city_id = v_city_id AND l.slug = p_locality_slug
  LIMIT 1;

  IF v_loc_id IS NULL THEN RETURN '[]'::jsonb; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'rank', rn, 'id', id, 'slug', slug, 'name', name,
           'usp_text', usp_text, 'photo', photo,
           'rating_avg', rating_avg, 'rating_count', rating_count,
           'verified_score', verified_score,
           'category_name', category_name, 'category_icon', category_icon,
           'score', score
         ) ORDER BY rn), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT b.id, b.slug, b.name, b.usp_text, b.photos[1] AS photo,
           COALESCE(b.rating_avg, 0)   AS rating_avg,
           COALESCE(b.rating_count, 0) AS rating_count,
           COALESCE(b.verified_score, 0) AS verified_score,
           cat.name AS category_name, cat.icon AS category_icon,
           dl_shop_score(b.rating_avg, b.rating_count, b.verified_score,
                         b.photos, b.usp_text, b.about_text) AS score,
           ROW_NUMBER() OVER (
             ORDER BY dl_shop_score(b.rating_avg, b.rating_count, b.verified_score,
                                    b.photos, b.usp_text, b.about_text) DESC, b.id
           ) AS rn
    FROM businesses b
    LEFT JOIN categories cat ON cat.id = b.category_id
    WHERE b.status = 'active'
      AND b.city_id = v_city_id
      AND b.locality_id = v_loc_id
    LIMIT p_limit
  ) t;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_locality_ranked(TEXT, TEXT, INT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- Sanity check against real data.
DO $$
DECLARE r JSONB; bid UUID;
BEGIN
  SELECT id INTO bid FROM businesses WHERE slug = 'unique-securities-mandi-dabwali' LIMIT 1;
  IF bid IS NOT NULL THEN
    r := public.get_shop_rank(bid);
    RAISE NOTICE 'get_shop_rank -> rank % of % in % (public_ok=%), gap to next: %',
      r->>'rank', r->>'total', r->>'category_name', r->>'public_ok', r->>'gap_to_next';
  END IF;

  r := public.get_empty_thrones('mandi-dabwali', 24);
  RAISE NOTICE 'get_empty_thrones(mandi-dabwali) -> % unclaimed categories',
    jsonb_array_length(r->'items');

  r := public.get_locality_ranked('mandi-dabwali', 'chotala-road', 50);
  RAISE NOTICE 'get_locality_ranked(chotala-road) -> % shops ranked', jsonb_array_length(r);
  RAISE NOTICE 'db/221 installed.';
END $$;
