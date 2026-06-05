-- =====================================================
-- db/110-nearby-open-shops.sql
-- =====================================================
-- STRATEGIC PHASE 6 (2026-06-05):
--   "Open Near You" — high-intent killer feature.
--
--   Customer opens DukanList → instantly sees 5 shops within
--   3 km that are OPEN RIGHT NOW. One-tap call / WhatsApp /
--   directions. Mobile-first conversion engine.
--
-- TWO RPCs:
--
-- 1. get_open_shops_near(lat, lng, radius_km, limit)
--    Haversine distance calculation. Filters to open shops
--    using hours_json + current time. Returns sorted by
--    distance ascending. Public anon.
--
-- 2. compute_distance_km(lat1, lng1, lat2, lng2)
--    Reusable helper for client display. SQL immutable.
--
-- ZERO new dependencies — uses existing businesses.lat/lng
-- and businesses.hours_json columns.
--
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

-- ============================================================
-- Haversine distance helper (km)
-- ============================================================
DROP FUNCTION IF EXISTS compute_distance_km(NUMERIC, NUMERIC, NUMERIC, NUMERIC);
CREATE OR REPLACE FUNCTION compute_distance_km(
  p_lat1 NUMERIC, p_lng1 NUMERIC,
  p_lat2 NUMERIC, p_lng2 NUMERIC
)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  v_earth_radius CONSTANT NUMERIC := 6371;
  v_dlat NUMERIC;
  v_dlng NUMERIC;
  v_a    NUMERIC;
  v_c    NUMERIC;
BEGIN
  IF p_lat1 IS NULL OR p_lng1 IS NULL OR p_lat2 IS NULL OR p_lng2 IS NULL THEN
    RETURN NULL;
  END IF;
  v_dlat := radians(p_lat2 - p_lat1);
  v_dlng := radians(p_lng2 - p_lng1);
  v_a := sin(v_dlat / 2) * sin(v_dlat / 2)
       + cos(radians(p_lat1)) * cos(radians(p_lat2))
       * sin(v_dlng / 2) * sin(v_dlng / 2);
  v_c := 2 * atan2(sqrt(v_a), sqrt(1 - v_a));
  RETURN ROUND((v_earth_radius * v_c)::numeric, 2);
END;
$$;

GRANT EXECUTE ON FUNCTION compute_distance_km(NUMERIC, NUMERIC, NUMERIC, NUMERIC) TO authenticated, anon;


-- ============================================================
-- Open-now check: reads hours_json + day-of-week + current time
-- hours_json shape:
--   { "mon": { "open": "09:00", "close": "21:00" },
--     "sun": { "closed": true }, ... }
-- ============================================================
DROP FUNCTION IF EXISTS is_business_open_now(JSONB);
CREATE OR REPLACE FUNCTION is_business_open_now(p_hours JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_day_key  TEXT;
  v_day      JSONB;
  v_now      TIME := CURRENT_TIME AT TIME ZONE 'Asia/Kolkata';
  v_open_s   TEXT;
  v_close_s  TEXT;
  v_open_t   TIME;
  v_close_t  TIME;
BEGIN
  IF p_hours IS NULL OR p_hours::TEXT = '{}' THEN
    -- No hours set = assume open (don't penalize)
    RETURN TRUE;
  END IF;

  -- Day key (mon, tue, wed, thu, fri, sat, sun) in IST
  v_day_key := lower(to_char((NOW() AT TIME ZONE 'Asia/Kolkata')::TIMESTAMP, 'dy'));
  v_day := p_hours -> v_day_key;

  IF v_day IS NULL THEN
    RETURN TRUE;
  END IF;

  IF (v_day ->> 'closed')::BOOLEAN = TRUE THEN
    RETURN FALSE;
  END IF;

  v_open_s  := v_day ->> 'open';
  v_close_s := v_day ->> 'close';
  IF v_open_s IS NULL OR v_close_s IS NULL THEN
    RETURN TRUE;
  END IF;

  BEGIN
    v_open_t  := v_open_s::TIME;
    v_close_t := v_close_s::TIME;
  EXCEPTION WHEN OTHERS THEN RETURN TRUE; END;

  -- Handle close-past-midnight (e.g. 22:00 - 02:00)
  IF v_close_t < v_open_t THEN
    RETURN (v_now >= v_open_t) OR (v_now <= v_close_t);
  END IF;

  RETURN v_now >= v_open_t AND v_now <= v_close_t;
EXCEPTION WHEN OTHERS THEN
  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION is_business_open_now(JSONB) TO authenticated, anon;


-- ============================================================
-- get_open_shops_near(lat, lng, radius_km, limit)
-- ============================================================
DROP FUNCTION IF EXISTS get_open_shops_near(NUMERIC, NUMERIC, NUMERIC, INT);
CREATE OR REPLACE FUNCTION get_open_shops_near(
  p_lat        NUMERIC,
  p_lng        NUMERIC,
  p_radius_km  NUMERIC DEFAULT 3,
  p_limit      INT     DEFAULT 8
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_items     JSONB := '[]'::jsonb;
  v_radius    NUMERIC;
  v_limit     INT;
BEGIN
  -- Defensive: clamp inputs
  IF p_lat IS NULL OR p_lng IS NULL THEN
    RETURN jsonb_build_object('items', '[]'::jsonb, 'count', 0, 'reason', 'no_coords');
  END IF;
  v_radius := COALESCE(p_radius_km, 3);
  IF v_radius < 0.1 OR v_radius > 50 THEN v_radius := 3; END IF;
  v_limit := COALESCE(p_limit, 8);
  IF v_limit < 1 OR v_limit > 50 THEN v_limit := 8; END IF;

  -- Build the list with distance computed inline
  WITH candidates AS (
    SELECT
      b.id, b.name, b.slug, b.mobile, b.whatsapp_mobile,
      b.photos, b.rating_avg, b.rating_count,
      b.lat, b.lng, b.hours_json,
      compute_distance_km(p_lat, p_lng, b.lat, b.lng) AS dist_km
    FROM businesses b
    WHERE b.status = 'active'
      AND b.lat IS NOT NULL AND b.lng IS NOT NULL
      -- Crude bounding box prefilter for performance
      AND b.lat BETWEEN (p_lat - v_radius / 100) AND (p_lat + v_radius / 100)
      AND b.lng BETWEEN (p_lng - v_radius / 100) AND (p_lng + v_radius / 100)
  ),
  filtered AS (
    SELECT *
    FROM candidates
    WHERE dist_km IS NOT NULL AND dist_km <= v_radius
    ORDER BY dist_km ASC
    LIMIT v_limit * 3  -- fetch more, filter open ones below
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id',           f.id,
    'name',         f.name,
    'slug',         f.slug,
    'mobile',       f.mobile,
    'whatsapp',     f.whatsapp_mobile,
    'photo',        f.photos[1],
    'rating_avg',   COALESCE(f.rating_avg, 0),
    'rating_count', COALESCE(f.rating_count, 0),
    'dist_km',      f.dist_km,
    'is_open',      is_business_open_now(f.hours_json)
  ) ORDER BY f.dist_km ASC), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT * FROM filtered
    WHERE is_business_open_now(hours_json) = TRUE
    ORDER BY dist_km ASC
    LIMIT v_limit
  ) AS f;

  RETURN jsonb_build_object(
    'items',       v_items,
    'count',       jsonb_array_length(v_items),
    'radius_km',   v_radius,
    'center_lat',  p_lat,
    'center_lng',  p_lng,
    'computed_at', NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_open_shops_near(NUMERIC, NUMERIC, NUMERIC, INT) TO authenticated, anon;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'db/110 installed.';
  RAISE NOTICE '  Helper: compute_distance_km(lat1, lng1, lat2, lng2)';
  RAISE NOTICE '  Helper: is_business_open_now(hours_json)';
  RAISE NOTICE '  RPC:    get_open_shops_near(lat, lng, radius_km, limit)';
END $$;
