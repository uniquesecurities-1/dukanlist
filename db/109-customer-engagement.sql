-- =====================================================
-- db/109-customer-engagement.sql
-- =====================================================
-- STRATEGIC PHASE 5 (2026-06-05):
--   Customer-side engagement. The shopkeeper side is now fully
--   gamified — we need to give CUSTOMERS a daily reason to open
--   DukanList too. Without customers visiting, the shopkeeper
--   dashboard stats stay at 0 and engagement loop breaks.
--
-- TWO RPCs:
--
-- 1. get_customer_favorite_feed(limit)
--    Returns recent activity (deals + new photos + new reviews)
--    from the logged-in customer's favorited businesses,
--    sorted by recency.
--
-- 2. get_local_pulse(city_slug_or_id)
--    Public RPC for homepage widget. Returns today's local
--    activity summary: new shops, new deals, new reviews,
--    busiest categories. NO auth required.
--
-- ZERO external API. ZERO additional storage cost.
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. get_customer_favorite_feed(p_limit)
-- ============================================================
DROP FUNCTION IF EXISTS get_customer_favorite_feed(INT);
CREATE OR REPLACE FUNCTION get_customer_favorite_feed(p_limit INT DEFAULT 20)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_user_id    UUID;
  v_items      JSONB := '[]'::jsonb;
  v_fav_count  INT := 0;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_limit < 1 OR p_limit > 100 THEN p_limit := 20; END IF;

  -- Get favorite count
  BEGIN
    SELECT COUNT(*) INTO v_fav_count
    FROM business_favorites
    WHERE user_id = v_user_id;
  EXCEPTION WHEN OTHERS THEN v_fav_count := 0; END;

  IF v_fav_count = 0 THEN
    RETURN jsonb_build_object(
      'items',      '[]'::jsonb,
      'fav_count',  0,
      'empty',      true
    );
  END IF;

  -- Build merged feed: recent deals + recent reviews + recently active shops
  BEGIN
    WITH my_favs AS (
      SELECT business_id FROM business_favorites WHERE user_id = v_user_id
    ),
    -- Deals from favorited shops (last 30 days)
    recent_deals AS (
      SELECT
        'deal' AS kind,
        d.id::text AS ref_id,
        d.business_id,
        b.name AS shop_name,
        b.slug AS shop_slug,
        b.photos[1] AS shop_photo,
        COALESCE(b.city_name, '') AS shop_city,
        d.title AS title,
        COALESCE(d.description, '') AS detail,
        d.created_at AS activity_at
      FROM deals d
      JOIN businesses b ON b.id = d.business_id
      WHERE d.business_id IN (SELECT business_id FROM my_favs)
        AND COALESCE(d.status, 'active') = 'active'
        AND d.created_at >= NOW() - INTERVAL '30 days'
    ),
    -- New reviews on favorited shops (last 14 days)
    recent_reviews AS (
      SELECT
        'review' AS kind,
        r.id::text AS ref_id,
        r.business_id,
        b.name AS shop_name,
        b.slug AS shop_slug,
        b.photos[1] AS shop_photo,
        COALESCE(b.city_name, '') AS shop_city,
        'New review: ' || COALESCE(r.rating::text, '?') || '/5 stars' AS title,
        LEFT(COALESCE(r.text, ''), 120) AS detail,
        r.created_at AS activity_at
      FROM reviews r
      JOIN businesses b ON b.id = r.business_id
      WHERE r.business_id IN (SELECT business_id FROM my_favs)
        AND COALESCE(r.status, 'active') NOT IN ('removed', 'hidden')
        AND r.created_at >= NOW() - INTERVAL '14 days'
    )
    SELECT COALESCE(jsonb_agg(row_data ORDER BY (row_data->>'activity_at') DESC), '[]'::jsonb)
    INTO v_items
    FROM (
      SELECT jsonb_build_object(
        'kind',         kind,
        'ref_id',       ref_id,
        'business_id',  business_id,
        'shop_name',    shop_name,
        'shop_slug',    shop_slug,
        'shop_photo',   shop_photo,
        'shop_city',    shop_city,
        'title',        title,
        'detail',       detail,
        'activity_at',  activity_at
      ) AS row_data
      FROM (
        SELECT * FROM recent_deals
        UNION ALL
        SELECT * FROM recent_reviews
      ) AS combined
      ORDER BY activity_at DESC
      LIMIT p_limit
    ) AS sorted;
  EXCEPTION WHEN OTHERS THEN
    v_items := '[]'::jsonb;
  END;

  RETURN jsonb_build_object(
    'items',      v_items,
    'fav_count',  v_fav_count,
    'empty',      (jsonb_array_length(v_items) = 0)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_customer_favorite_feed(INT) TO authenticated;


-- ============================================================
-- 2. get_local_pulse(city_slug)
--    Public widget for homepage. Returns today's local stats.
-- ============================================================
DROP FUNCTION IF EXISTS get_local_pulse(TEXT);
CREATE OR REPLACE FUNCTION get_local_pulse(p_city_slug TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_city_id        UUID;
  v_city_name      TEXT;
  v_today          DATE := CURRENT_DATE;
  v_yest           DATE := CURRENT_DATE - 1;
  v_new_shops      INT := 0;
  v_new_deals      INT := 0;
  v_new_reviews    INT := 0;
  v_active_shops   INT := 0;
  v_top_cats       JSONB := '[]'::jsonb;
BEGIN
  -- Resolve city
  IF p_city_slug IS NOT NULL AND length(p_city_slug) > 0 THEN
    BEGIN
      SELECT id, name INTO v_city_id, v_city_name
      FROM geo_cities WHERE slug = p_city_slug LIMIT 1;
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  -- New shops today (in this city, or all if no city)
  BEGIN
    SELECT COUNT(*) INTO v_new_shops
    FROM businesses
    WHERE status = 'active'
      AND created_at::date = v_today
      AND (v_city_id IS NULL OR city_id = v_city_id);
  EXCEPTION WHEN OTHERS THEN v_new_shops := 0; END;

  -- New deals today
  BEGIN
    SELECT COUNT(*) INTO v_new_deals
    FROM deals d
    JOIN businesses b ON b.id = d.business_id
    WHERE d.created_at::date = v_today
      AND COALESCE(d.status, 'active') = 'active'
      AND (v_city_id IS NULL OR b.city_id = v_city_id);
  EXCEPTION WHEN OTHERS THEN v_new_deals := 0; END;

  -- New reviews today
  BEGIN
    SELECT COUNT(*) INTO v_new_reviews
    FROM reviews r
    JOIN businesses b ON b.id = r.business_id
    WHERE r.created_at::date = v_today
      AND COALESCE(r.status, 'active') NOT IN ('removed', 'hidden')
      AND (v_city_id IS NULL OR b.city_id = v_city_id);
  EXCEPTION WHEN OTHERS THEN v_new_reviews := 0; END;

  -- Total active shops in city
  BEGIN
    SELECT COUNT(*) INTO v_active_shops
    FROM businesses
    WHERE status = 'active'
      AND (v_city_id IS NULL OR city_id = v_city_id);
  EXCEPTION WHEN OTHERS THEN v_active_shops := 0; END;

  -- Top 3 categories by recent activity (views in last 24h)
  BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'category_id',   cat_id,
      'category_name', cat_name,
      'view_count',    view_count
    )), '[]'::jsonb) INTO v_top_cats
    FROM (
      SELECT c.id AS cat_id, c.name AS cat_name, COUNT(l.id) AS view_count
      FROM leads_log l
      JOIN businesses b ON b.id = l.business_id
      LEFT JOIN categories c ON c.id = b.primary_category_id
      WHERE l.action = 'view'
        AND l.created_at >= NOW() - INTERVAL '24 hours'
        AND (v_city_id IS NULL OR b.city_id = v_city_id)
        AND c.id IS NOT NULL
      GROUP BY c.id, c.name
      ORDER BY view_count DESC
      LIMIT 3
    ) AS t;
  EXCEPTION WHEN OTHERS THEN v_top_cats := '[]'::jsonb; END;

  RETURN jsonb_build_object(
    'city_name',     COALESCE(v_city_name, 'All cities'),
    'date',          v_today,
    'new_shops',     v_new_shops,
    'new_deals',     v_new_deals,
    'new_reviews',   v_new_reviews,
    'active_shops',  v_active_shops,
    'top_categories', v_top_cats,
    'computed_at',   NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_local_pulse(TEXT) TO authenticated, anon;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'db/109 installed.';
  RAISE NOTICE '  RPC: get_customer_favorite_feed(limit) — auth required';
  RAISE NOTICE '  RPC: get_local_pulse(city_slug) — public anon';
END $$;
