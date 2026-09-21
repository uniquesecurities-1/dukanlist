-- ============================================================
-- db/226 — get_homepage_buzz has three bugs. Here they are.
-- ============================================================
--
-- db/112b installed fine. Four of its five functions work. This one
-- is installed and broken — every call from the homepage returns
--
--     42883  operator does not exist: integer = uuid
--
-- which is why /assets/js/daily-buzz.js has been 404-ing, then
-- erroring, on every single homepage load, and the Daily Buzz strip
-- has never once appeared.
--
-- Same family as the db/111 bugs that db/220 repaired: SQL that was
-- written against a guess at the schema rather than the schema.
--
-- BUG 1 — the city id is declared UUID, but it is an INT.
--     DECLARE v_city_id UUID;
--     ... AND (v_city_id IS NULL OR b.city_id = v_city_id)
--   geo_cities.id is an integer (verified live: id 8 = Bathinda,
--   id 1 = Mandi Dabwali), and businesses.city_id is an integer too.
--   Postgres type-checks the whole expression when it plans the
--   query, so this fails even when v_city_id is NULL and the branch
--   would never be reached. The function could never run, for
--   anybody, with any argument.
--
-- BUG 2 — it looks up a column that does not exist.
--     SELECT id INTO v_city_id FROM geo_cities WHERE slug = p_city_slug
--   geo_cities has no slug column (verified live). db/220 hit this
--   same wall and settled on deriving the slug from the name; this
--   now does the identical thing, so /top, /local and the buzz strip
--   all resolve a city the same way.
--
--   Worse, that lookup sat inside
--       BEGIN ... EXCEPTION WHEN OTHERS THEN NULL; END
--   so the missing column raised, got swallowed, and left v_city_id
--   NULL with nothing logged. A blanket exception handler around a
--   query is how a schema mistake survives to production.
--
-- BUG 3 — p_limit did nothing.
--     SELECT COALESCE(jsonb_agg(...)) INTO v_items FROM ... LIMIT p_limit
--   jsonb_agg with no GROUP BY collapses everything to ONE row, so
--   LIMIT 12 limited that single row, not the stories. Every active
--   story in the town would have been aggregated and shipped to the
--   homepage. Nobody noticed because the function never ran. The
--   limit now sits in a subquery, where it belongs.
--
-- Safe to re-run. Requires db/112b.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.get_homepage_buzz(
  p_city_slug TEXT DEFAULT NULL,
  p_limit     INT  DEFAULT 12
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
DECLARE
  v_city_id INT;          -- was UUID. This one word was bug 1.
  v_items   JSONB;
BEGIN
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 50 THEN p_limit := 12; END IF;

  -- No slug column on geo_cities, so derive it from the name exactly
  -- as db/220 / db/223 do. No exception handler: if this ever breaks
  -- again it should be loud, not silent.
  IF p_city_slug IS NOT NULL AND length(btrim(p_city_slug)) > 0 THEN
    SELECT c.id INTO v_city_id
    FROM geo_cities c
    WHERE c.active IS NOT FALSE
      AND lower(regexp_replace(c.name, '\s+', '-', 'g')) = lower(btrim(p_city_slug))
    LIMIT 1;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id',           x.id,
    'business_id',  x.business_id,
    'shop_name',    x.shop_name,
    'shop_slug',    x.shop_slug,
    'shop_photo',   x.shop_photo,
    'text',         x.text,
    'image_url',    x.image_url,
    'bg_style',     x.bg_style,
    'accent_color', x.accent_color,
    'created_at',   x.created_at,
    'hours_left',   x.hours_left
  ) ORDER BY x.created_at DESC), '[]'::jsonb)
  INTO v_items
  FROM (
    -- The LIMIT has to live in here. Outside, next to jsonb_agg, it
    -- was limiting the single aggregated row and letting every story
    -- through. That was bug 3.
    SELECT s.id, s.business_id, b.name AS shop_name, b.slug AS shop_slug,
           b.photos[1] AS shop_photo, s.text, s.image_url, s.bg_style,
           s.accent_color, s.created_at,
           EXTRACT(EPOCH FROM (s.expires_at - NOW())) / 3600 AS hours_left
    FROM shop_stories s
    JOIN businesses b ON b.id = s.business_id
    WHERE s.expires_at > NOW()
      AND b.status = 'active'
      AND (v_city_id IS NULL OR b.city_id = v_city_id)
    ORDER BY s.created_at DESC
    LIMIT p_limit
  ) x;

  RETURN v_items;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_homepage_buzz(TEXT, INT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================
-- Prove it, rather than assume it. db/219 announced success and
-- changed nothing; db/112b installed a function that could not run.
-- This calls it three ways and fails loudly if any of them error.
-- ============================================================
DO $$
DECLARE r JSONB;
BEGIN
  r := public.get_homepage_buzz(NULL, 12);
  RAISE NOTICE 'no city filter      -> % story(ies)', jsonb_array_length(r);

  r := public.get_homepage_buzz('mandi-dabwali', 12);
  RAISE NOTICE 'city=mandi-dabwali  -> % story(ies)', jsonb_array_length(r);

  r := public.get_homepage_buzz('no-such-town', 12);
  RAISE NOTICE 'unknown city        -> % story(ies) (falls back to all)', jsonb_array_length(r);

  RAISE NOTICE '--------------------------------------------------';
  RAISE NOTICE 'db/226 OK. get_homepage_buzz runs.';
  RAISE NOTICE 'shop_stories is empty today, so 0 is the right answer —';
  RAISE NOTICE 'the point is that it RETURNS instead of raising 42883.';
  RAISE NOTICE '--------------------------------------------------';
END $$;
