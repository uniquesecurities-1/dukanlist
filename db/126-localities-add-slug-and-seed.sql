-- ============================================================
-- db/126 — Hyperlocal Areas Feature: Phase 1
-- ============================================================
-- 1. Add `slug` column to geo_localities (for SEO landing page URLs)
-- 2. Backfill slugs for existing 10 Mandi Dabwali entries
-- 3. Add Deepak's curated list of new Mandi Dabwali areas
--    (Meena Bazaar, Main Bazaar, Grain Market, G.T. Road,
--     Ekta Nagri, Rajiv Nagar, Friends Colony, Goal Chowk,
--     Goal Bazaar, Colony Road)
-- 4. Add helper RPC: list_localities_by_city(slug)
--
-- DB SAFETY: All inserts use ON CONFLICT DO NOTHING. Re-runnable.
-- Forward-only migration. Existing shop→locality links untouched.
-- ============================================================

BEGIN;

-- ---- 1. Add slug column (idempotent) ----
ALTER TABLE geo_localities
  ADD COLUMN IF NOT EXISTS slug TEXT;

-- Backfill slug from name for any NULL entries.
-- Simple slugify: lowercase, replace non-alphanumeric with hyphen, trim hyphens.
UPDATE geo_localities
SET slug = regexp_replace(
             regexp_replace(
               lower(trim(name)),
               '[^a-z0-9]+', '-', 'g'
             ),
             '(^-+|-+$)', '', 'g'
           )
WHERE slug IS NULL OR slug = '';

-- Make slug NOT NULL + unique per city
ALTER TABLE geo_localities
  ALTER COLUMN slug SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_localities_city_slug
  ON geo_localities(city_id, slug);

CREATE INDEX IF NOT EXISTS idx_localities_slug
  ON geo_localities(slug);

-- ---- 2. Insert new Mandi Dabwali localities ----
-- Skip if (city_id, slug) already exists.
WITH md_city AS (
  SELECT id FROM geo_cities WHERE name = 'Mandi Dabwali' LIMIT 1
)
INSERT INTO geo_localities (city_id, name, name_hi, slug, pincode)
SELECT md_city.id, v.name, v.name_hi, v.slug, '125104'
FROM md_city, (VALUES
  ('Meena Bazaar',     'मीना बाज़ार',       'meena-bazaar'),
  ('Main Bazaar',      'मेन बाज़ार',         'main-bazaar'),
  ('Grain Market',     'अनाज मंडी',           'grain-market'),
  ('G.T. Road',        'जी.टी. रोड',          'gt-road'),
  ('Bus Stand Road',   'बस स्टैंड रोड',       'bus-stand-road'),
  ('Colony Road',      'कॉलोनी रोड',          'colony-road'),
  ('Ekta Nagri',       'एकता नगरी',            'ekta-nagri'),
  ('Rajiv Nagar',      'राजीव नगर',            'rajiv-nagar'),
  ('Friends Colony',   'फ्रेंड्स कॉलोनी',      'friends-colony'),
  ('Goal Chowk',       'गोल चौक',              'goal-chowk'),
  ('Goal Bazaar',      'गोल बाज़ार',           'goal-bazaar')
) AS v(name, name_hi, slug)
ON CONFLICT (city_id, slug) DO NOTHING;

-- ---- 3. Helper RPC for frontend dropdowns ----
-- Returns localities for a given city slug, ordered by usage (most shops first).
DROP FUNCTION IF EXISTS list_localities_by_city(TEXT);
CREATE OR REPLACE FUNCTION list_localities_by_city(p_city_slug TEXT)
RETURNS TABLE (
  id          INT,
  name        TEXT,
  name_hi     TEXT,
  slug        TEXT,
  shop_count  INT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    l.id,
    l.name,
    l.name_hi,
    l.slug,
    COALESCE((
      SELECT COUNT(*)::INT FROM businesses b
       WHERE b.locality_id = l.id
         AND b.status = 'active'
    ), 0) AS shop_count
  FROM geo_localities l
  JOIN geo_cities c ON c.id = l.city_id
  WHERE lower(c.name) = lower(p_city_slug)
     OR lower(replace(c.name, ' ', '-')) = lower(p_city_slug)
  ORDER BY shop_count DESC, l.name ASC;
$$;

GRANT EXECUTE ON FUNCTION list_localities_by_city(TEXT) TO anon, authenticated;

-- ---- 4. Helper RPC for landing pages (city + locality) ----
DROP FUNCTION IF EXISTS get_shops_by_locality(TEXT, TEXT, INT);
CREATE OR REPLACE FUNCTION get_shops_by_locality(
  p_city_slug     TEXT,
  p_locality_slug TEXT,
  p_limit         INT DEFAULT 50
)
RETURNS TABLE (
  id              UUID,
  slug            TEXT,
  name            TEXT,
  name_hi         TEXT,
  owner_name      TEXT,
  usp_text        TEXT,
  mobile          TEXT,
  whatsapp        TEXT,
  photos          TEXT[],
  rating_avg      NUMERIC,
  rating_count    INT,
  verified_score  INT,
  category_id     INT,
  category_name   TEXT,
  category_icon   TEXT,
  city_name       TEXT,
  locality_name   TEXT,
  created_at      TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    b.id, b.slug, b.name, b.name_hi, b.owner_name, b.usp_text,
    b.mobile, b.whatsapp, b.photos,
    b.rating_avg, b.rating_count, b.verified_score,
    b.category_id,
    cat.name AS category_name,
    cat.icon AS category_icon,
    gc.name AS city_name,
    gl.name AS locality_name,
    b.created_at
  FROM businesses b
  JOIN geo_localities gl ON gl.id = b.locality_id
  JOIN geo_cities gc     ON gc.id = gl.city_id
  LEFT JOIN categories cat ON cat.id = COALESCE(b.sub_category_id, b.category_id)
  WHERE (lower(gc.name) = lower(p_city_slug)
         OR lower(replace(gc.name, ' ', '-')) = lower(p_city_slug))
    AND gl.slug = p_locality_slug
    AND b.status = 'active'
  ORDER BY
    COALESCE(b.verified_score, 0) DESC,
    b.rating_avg DESC NULLS LAST,
    b.created_at DESC
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION get_shops_by_locality(TEXT, TEXT, INT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================
-- VERIFY — should show all Mandi Dabwali localities with slug
-- ============================================================
SELECT
  l.name,
  l.name_hi,
  l.slug,
  l.pincode,
  (SELECT COUNT(*) FROM businesses b WHERE b.locality_id = l.id AND b.status = 'active') AS active_shops
FROM geo_localities l
JOIN geo_cities c ON c.id = l.city_id
WHERE c.name = 'Mandi Dabwali'
ORDER BY active_shops DESC, l.name;

DO $$
DECLARE
  v_total INT;
BEGIN
  SELECT COUNT(*) INTO v_total
  FROM geo_localities l
  JOIN geo_cities c ON c.id = l.city_id
  WHERE c.name = 'Mandi Dabwali';
  RAISE NOTICE 'db/126 installed.';
  RAISE NOTICE '  Mandi Dabwali total localities: %', v_total;
  RAISE NOTICE '  Helper RPCs: list_localities_by_city, get_shops_by_locality';
  RAISE NOTICE '  Landing page URL pattern: /local/mandi-dabwali/<slug>';
END $$;
