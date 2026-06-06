-- =====================================================
-- db/105-owner-today-pulse.sql
-- =====================================================
-- STRATEGIC FEATURE (2026-06-05):
--   "Aaj ka Score" Live Dashboard Hero —
--   Shopkeeper login karte hi dopamine-hit big-number dikhe:
--     "Aaj 12 logon ne aapka shop dekha (↑25%)"
--
-- THIS RPC:
--   get_owner_today_pulse(business_id) → JSONB
--   Returns: today_views, yest_views, week_views,
--            today_calls, today_saves, reviews,
--            rating, delta_pct, trend
--
-- Data sources (all existing — no new tables):
--   - leads_log (action='view' = view, action IN ('call','whatsapp') = lead)
--   - business_favorites (today's saves)
--   - reviews (avg rating + count)
--
-- SECURITY: owner-only, gated via business_owners.
--
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

DROP FUNCTION IF EXISTS get_owner_today_pulse(UUID);
CREATE OR REPLACE FUNCTION get_owner_today_pulse(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id        UUID;
  v_is_owner       BOOLEAN;
  v_today          DATE := CURRENT_DATE;
  v_yest           DATE := CURRENT_DATE - 1;
  v_week_ago       DATE := CURRENT_DATE - 7;
  v_today_views    INT := 0;
  v_yest_views     INT := 0;
  v_week_views     INT := 0;
  v_today_calls    INT := 0;
  v_today_saves    INT := 0;
  v_total_reviews  INT := 0;
  v_avg_rating     NUMERIC := 0;
  v_lifetime_views INT := 0;
  v_delta_pct      INT := 0;
  v_trend          TEXT := 'flat';
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Owner gate
  SELECT EXISTS (
    SELECT 1 FROM business_owners
    WHERE business_id = p_business_id AND auth_user_id = v_user_id
  ) INTO v_is_owner;
  IF NOT v_is_owner THEN
    RAISE EXCEPTION 'Not authorized for this business';
  END IF;

  -- Today's views (from leads_log)
  BEGIN
    SELECT COUNT(*) INTO v_today_views
    FROM leads_log
    WHERE business_id = p_business_id
      AND action = 'view'
      AND created_at::date = v_today;
  EXCEPTION WHEN OTHERS THEN v_today_views := 0; END;

  -- Yesterday's views
  BEGIN
    SELECT COUNT(*) INTO v_yest_views
    FROM leads_log
    WHERE business_id = p_business_id
      AND action = 'view'
      AND created_at::date = v_yest;
  EXCEPTION WHEN OTHERS THEN v_yest_views := 0; END;

  -- Week views
  BEGIN
    SELECT COUNT(*) INTO v_week_views
    FROM leads_log
    WHERE business_id = p_business_id
      AND action = 'view'
      AND created_at::date >= v_week_ago;
  EXCEPTION WHEN OTHERS THEN v_week_views := 0; END;

  -- Today's calls + whatsapp = leads
  BEGIN
    SELECT COUNT(*) INTO v_today_calls
    FROM leads_log
    WHERE business_id = p_business_id
      AND action IN ('call', 'whatsapp')
      AND created_at::date = v_today;
  EXCEPTION WHEN OTHERS THEN v_today_calls := 0; END;

  -- Today's saves (favorites added today)
  BEGIN
    SELECT COUNT(*) INTO v_today_saves
    FROM business_favorites
    WHERE business_id = p_business_id
      AND created_at::date = v_today;
  EXCEPTION WHEN OTHERS THEN v_today_saves := 0; END;

  -- Reviews
  BEGIN
    SELECT COUNT(*), ROUND(COALESCE(AVG(rating), 0)::numeric, 1)
    INTO v_total_reviews, v_avg_rating
    FROM reviews
    WHERE business_id = p_business_id
      AND COALESCE(status, 'active') NOT IN ('removed', 'hidden');
  EXCEPTION WHEN OTHERS THEN END;

  -- Lifetime views (from businesses.view_count fallback)
  BEGIN
    SELECT COALESCE(view_count, 0) INTO v_lifetime_views
    FROM businesses WHERE id = p_business_id;
  EXCEPTION WHEN OTHERS THEN v_lifetime_views := 0; END;

  -- Delta % vs yesterday
  IF v_yest_views = 0 AND v_today_views > 0 THEN
    v_delta_pct := 100;
  ELSIF v_yest_views = 0 THEN
    v_delta_pct := 0;
  ELSE
    v_delta_pct := ROUND(((v_today_views - v_yest_views)::NUMERIC / v_yest_views) * 100);
  END IF;

  -- Trend
  IF v_today_views > v_yest_views THEN
    v_trend := 'up';
  ELSIF v_today_views < v_yest_views THEN
    v_trend := 'down';
  ELSE
    v_trend := 'flat';
  END IF;

  RETURN jsonb_build_object(
    'today_views',    v_today_views,
    'yest_views',     v_yest_views,
    'week_views',     v_week_views,
    'today_calls',    v_today_calls,
    'today_saves',    v_today_saves,
    'reviews',        v_total_reviews,
    'rating',         v_avg_rating,
    'lifetime_views', v_lifetime_views,
    'delta_pct',      v_delta_pct,
    'trend',          v_trend,
    'computed_at',    NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_owner_today_pulse(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'db/105 installed.';
  RAISE NOTICE '  RPC: get_owner_today_pulse(business_id)';
  RAISE NOTICE '  Returns: today_views, yest_views, week_views,';
  RAISE NOTICE '           today_calls, today_saves, reviews, rating,';
  RAISE NOTICE '           lifetime_views, delta_pct, trend';
  RAISE NOTICE '  Used by panel/dashboard.html Aaj ka Score hero card';
END $$;
