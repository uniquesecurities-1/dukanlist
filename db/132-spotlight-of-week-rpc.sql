-- ============================================================
-- db/132 — Spotlight of the Week RPC (genuinely weekly)
-- ============================================================
-- Problem: Current loadFSOTW shows all-time top rated shop —
-- never changes week to week. "Spotlight of the Week" lies.
--
-- New algorithm — tiered fallback for true weekly freshness:
--   Tier 1: Shop with most NEW reviews in last 7 days
--           (must have ≥2 new reviews + avg rating ≥ 4.0)
--   Tier 2: Shop with most NEW reviews in last 30 days
--           (must have ≥3 reviews this month + ≥4.0)
--   Tier 3: Recently active shop (review in last 90 days)
--           with highest rating
--
-- This way: every week likely shows DIFFERENT shop because
-- review activity varies. Even small Mandi Dabwali traffic
-- creates rotation.
-- ============================================================

BEGIN;

DROP FUNCTION IF EXISTS get_spotlight_of_week();

CREATE OR REPLACE FUNCTION get_spotlight_of_week()
RETURNS TABLE (
  id            UUID,
  slug          TEXT,
  name          TEXT,
  owner_name    TEXT,
  usp_text      TEXT,
  photos        TEXT[],
  rating_avg    NUMERIC,
  rating_count  INT,
  verified_score SMALLINT,
  city_name     TEXT,
  tier          TEXT,         -- 'week' | 'month' | 'recent'
  new_reviews   INT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_result RECORD;
BEGIN
  -- TIER 1: Most NEW reviews in last 7 days (with quality bar)
  SELECT b.id, b.slug, b.name, b.owner_name, b.usp_text, b.photos,
         b.rating_avg, b.rating_count, b.verified_score,
         (SELECT gc.name FROM geo_cities gc WHERE gc.id = b.city_id) AS city_name,
         'week' AS tier,
         COUNT(r.id)::INT AS new_reviews
    INTO v_result
    FROM businesses b
    JOIN reviews r ON r.business_id = b.id
   WHERE b.status = 'active'
     AND r.status = 'active'
     AND r.created_at >= NOW() - INTERVAL '7 days'
     AND r.rating >= 4
   GROUP BY b.id
  HAVING COUNT(r.id) >= 2
     AND AVG(r.rating) >= 4.0
   ORDER BY COUNT(r.id) DESC,
            AVG(r.rating) DESC,
            b.rating_count DESC
   LIMIT 1;

  IF FOUND THEN
    id := v_result.id; slug := v_result.slug; name := v_result.name;
    owner_name := v_result.owner_name; usp_text := v_result.usp_text;
    photos := v_result.photos; rating_avg := v_result.rating_avg;
    rating_count := v_result.rating_count; verified_score := v_result.verified_score;
    city_name := v_result.city_name; tier := v_result.tier;
    new_reviews := v_result.new_reviews;
    RETURN NEXT;
    RETURN;
  END IF;

  -- TIER 2: Most NEW reviews in last 30 days
  SELECT b.id, b.slug, b.name, b.owner_name, b.usp_text, b.photos,
         b.rating_avg, b.rating_count, b.verified_score,
         (SELECT gc.name FROM geo_cities gc WHERE gc.id = b.city_id) AS city_name,
         'month' AS tier,
         COUNT(r.id)::INT AS new_reviews
    INTO v_result
    FROM businesses b
    JOIN reviews r ON r.business_id = b.id
   WHERE b.status = 'active'
     AND r.status = 'active'
     AND r.created_at >= NOW() - INTERVAL '30 days'
     AND r.rating >= 4
   GROUP BY b.id
  HAVING COUNT(r.id) >= 3
     AND AVG(r.rating) >= 4.0
   ORDER BY COUNT(r.id) DESC,
            AVG(r.rating) DESC,
            b.rating_count DESC
   LIMIT 1;

  IF FOUND THEN
    id := v_result.id; slug := v_result.slug; name := v_result.name;
    owner_name := v_result.owner_name; usp_text := v_result.usp_text;
    photos := v_result.photos; rating_avg := v_result.rating_avg;
    rating_count := v_result.rating_count; verified_score := v_result.verified_score;
    city_name := v_result.city_name; tier := v_result.tier;
    new_reviews := v_result.new_reviews;
    RETURN NEXT;
    RETURN;
  END IF;

  -- TIER 3: Recently active (review in last 90 days) with best rating
  SELECT b.id, b.slug, b.name, b.owner_name, b.usp_text, b.photos,
         b.rating_avg, b.rating_count, b.verified_score,
         (SELECT gc.name FROM geo_cities gc WHERE gc.id = b.city_id) AS city_name,
         'recent' AS tier,
         COUNT(r.id)::INT AS new_reviews
    INTO v_result
    FROM businesses b
    JOIN reviews r ON r.business_id = b.id
   WHERE b.status = 'active'
     AND r.status = 'active'
     AND r.created_at >= NOW() - INTERVAL '90 days'
   GROUP BY b.id
  HAVING b.rating_avg >= 4.0
     AND b.rating_count >= 3
   ORDER BY b.rating_avg DESC, b.rating_count DESC
   LIMIT 1;

  IF FOUND THEN
    id := v_result.id; slug := v_result.slug; name := v_result.name;
    owner_name := v_result.owner_name; usp_text := v_result.usp_text;
    photos := v_result.photos; rating_avg := v_result.rating_avg;
    rating_count := v_result.rating_count; verified_score := v_result.verified_score;
    city_name := v_result.city_name; tier := v_result.tier;
    new_reviews := v_result.new_reviews;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Nothing matches → return nothing
  RETURN;
END $$;

GRANT EXECUTE ON FUNCTION get_spotlight_of_week() TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

DO $$
BEGIN
  RAISE NOTICE '✓ db/132 — Spotlight of the Week RPC ready (tiered weekly freshness)';
END $$;

COMMIT;
