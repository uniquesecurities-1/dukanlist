-- =====================================================
-- 14-owner-analytics.sql
-- Shopkeeper Analytics RPC — get_owner_analytics()
-- =====================================================
-- WHAT THIS DOES:
--   Returns rich analytics for a business owner:
--     1. Summary counts (views, call, whatsapp, direction, share)
--        for the requested period
--     2. Same counts for previous period (% change comparison)
--     3. Daily breakdown for line/bar chart
--     4. Recent leads (last 30) with action + timestamp
--     5. Review summary (count + average rating)
--
-- PREREQUISITES: 01-13 SQL files executed.
-- HOW TO RUN: Paste in Supabase SQL Editor → Run.
-- IDEMPOTENT: CREATE OR REPLACE, safe to re-run.
-- =====================================================
--
-- USAGE FROM CLIENT (JS):
--   const { data } = await client.rpc('get_owner_analytics', {
--     p_business_id: 'YOUR-UUID',
--     p_days: 30                    -- 7 / 30 / 90 typical
--   });
--   // data is JSONB with keys: summary, previous, daily, recent_leads, reviews
-- =====================================================


CREATE OR REPLACE FUNCTION get_owner_analytics(
  p_business_id UUID,
  p_days        INT DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id      UUID;
  v_is_owner     BOOLEAN;
  v_start_date   TIMESTAMPTZ;
  v_prev_start   TIMESTAMPTZ;
  v_result       JSONB;
  v_summary      JSONB;
  v_previous     JSONB;
  v_daily        JSONB;
  v_leads        JSONB;
  v_reviews      JSONB;
  v_biz          JSONB;
BEGIN
  -- ===== Auth & ownership check =====
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM business_owners
    WHERE business_id  = p_business_id
      AND auth_user_id = v_user_id
  ) INTO v_is_owner;

  IF NOT v_is_owner THEN
    RAISE EXCEPTION 'Not authorised to view analytics for this business';
  END IF;

  -- Clamp days
  IF p_days IS NULL OR p_days < 1 THEN p_days := 30; END IF;
  IF p_days > 365 THEN p_days := 365; END IF;

  v_start_date := NOW() - (p_days || ' days')::INTERVAL;
  v_prev_start := NOW() - (2 * p_days || ' days')::INTERVAL;

  -- ===== Business info (overall totals + slug for sharing) =====
  SELECT jsonb_build_object(
    'id',           id,
    'slug',         slug,
    'name',         name,
    'view_count',   COALESCE(view_count, 0),
    'lead_count',   COALESCE(lead_count, 0),
    'rating_avg',   COALESCE(rating_avg, 0),
    'rating_count', COALESCE(rating_count, 0),
    'created_at',   created_at,
    'days_old',     EXTRACT(DAY FROM (NOW() - created_at))::INT
  )
  INTO v_biz
  FROM businesses
  WHERE id = p_business_id;

  -- ===== Period summary (current window) =====
  SELECT jsonb_build_object(
    'views',      COUNT(*) FILTER (WHERE action = 'view'),
    'call',       COUNT(*) FILTER (WHERE action = 'call'),
    'whatsapp',   COUNT(*) FILTER (WHERE action = 'whatsapp'),
    'direction',  COUNT(*) FILTER (WHERE action = 'direction'),
    'share',      COUNT(*) FILTER (WHERE action = 'share'),
    'total_leads',COUNT(*) FILTER (WHERE action IN ('call','whatsapp','direction')),
    'total_all',  COUNT(*)
  )
  INTO v_summary
  FROM leads_log
  WHERE business_id = p_business_id
    AND created_at >= v_start_date;

  -- ===== Previous period (for % change vs current) =====
  SELECT jsonb_build_object(
    'views',      COUNT(*) FILTER (WHERE action = 'view'),
    'call',       COUNT(*) FILTER (WHERE action = 'call'),
    'whatsapp',   COUNT(*) FILTER (WHERE action = 'whatsapp'),
    'direction',  COUNT(*) FILTER (WHERE action = 'direction'),
    'share',      COUNT(*) FILTER (WHERE action = 'share'),
    'total_leads',COUNT(*) FILTER (WHERE action IN ('call','whatsapp','direction')),
    'total_all',  COUNT(*)
  )
  INTO v_previous
  FROM leads_log
  WHERE business_id = p_business_id
    AND created_at >= v_prev_start
    AND created_at <  v_start_date;

  -- ===== Daily breakdown (for chart) =====
  -- Returns array of: { date, views, call, whatsapp, direction, share }
  WITH date_series AS (
    SELECT generate_series(
      DATE_TRUNC('day', v_start_date)::DATE,
      DATE_TRUNC('day', NOW())::DATE,
      '1 day'::INTERVAL
    )::DATE AS d
  ),
  daily_counts AS (
    SELECT
      DATE_TRUNC('day', created_at)::DATE AS d,
      COUNT(*) FILTER (WHERE action = 'view')      AS views,
      COUNT(*) FILTER (WHERE action = 'call')      AS call_n,
      COUNT(*) FILTER (WHERE action = 'whatsapp')  AS whatsapp_n,
      COUNT(*) FILTER (WHERE action = 'direction') AS direction_n,
      COUNT(*) FILTER (WHERE action = 'share')     AS share_n
    FROM leads_log
    WHERE business_id = p_business_id
      AND created_at >= v_start_date
    GROUP BY DATE_TRUNC('day', created_at)::DATE
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'date',      ds.d,
      'views',     COALESCE(dc.views, 0),
      'call',      COALESCE(dc.call_n, 0),
      'whatsapp',  COALESCE(dc.whatsapp_n, 0),
      'direction', COALESCE(dc.direction_n, 0),
      'share',     COALESCE(dc.share_n, 0),
      'leads',     COALESCE(dc.call_n, 0) + COALESCE(dc.whatsapp_n, 0) + COALESCE(dc.direction_n, 0)
    ) ORDER BY ds.d
  )
  INTO v_daily
  FROM date_series ds
  LEFT JOIN daily_counts dc ON dc.d = ds.d;

  -- ===== Recent leads (last 30 events, excluding views) =====
  SELECT jsonb_agg(
    jsonb_build_object(
      'action',     action,
      'created_at', created_at,
      'when',       TO_CHAR(created_at AT TIME ZONE 'Asia/Kolkata', 'DD Mon YYYY · HH12:MI AM')
    ) ORDER BY created_at DESC
  )
  INTO v_leads
  FROM (
    SELECT action, created_at
    FROM leads_log
    WHERE business_id = p_business_id
      AND action IN ('call', 'whatsapp', 'direction', 'share')
    ORDER BY created_at DESC
    LIMIT 30
  ) sub;

  -- ===== Review activity (current window) =====
  SELECT jsonb_build_object(
    'new_in_period',  COUNT(*) FILTER (WHERE created_at >= v_start_date),
    'replied',        COUNT(*) FILTER (WHERE owner_reply IS NOT NULL),
    'unreplied',      COUNT(*) FILTER (WHERE owner_reply IS NULL),
    'avg_rating',     ROUND(AVG(rating)::NUMERIC, 2),
    'total',          COUNT(*)
  )
  INTO v_reviews
  FROM reviews
  WHERE business_id = p_business_id
    AND status = 'active';

  -- ===== Compose final result =====
  v_result := jsonb_build_object(
    'business',  v_biz,
    'period',    jsonb_build_object(
                   'days',       p_days,
                   'start_date', v_start_date,
                   'end_date',   NOW()
                 ),
    'summary',   v_summary,
    'previous',  v_previous,
    'daily',     COALESCE(v_daily, '[]'::jsonb),
    'recent_leads', COALESCE(v_leads, '[]'::jsonb),
    'reviews',   v_reviews
  );

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_owner_analytics(UUID, INT) TO authenticated;


-- =====================================================
-- Reload PostgREST schema cache
-- =====================================================
NOTIFY pgrst, 'reload schema';


-- =====================================================
-- VERIFICATION
-- =====================================================
-- 1) Function visible:
--    SELECT proname FROM pg_proc WHERE proname = 'get_owner_analytics';
--    (expect 1 row)
--
-- 2) Test call (replace UUID with your business id, logged in as owner):
--    SELECT get_owner_analytics('YOUR-UUID-HERE'::uuid, 30);
--
-- 3) Sample expected shape:
--    {
--      "business": { "id":..., "slug":..., "view_count":..., "rating_avg":... },
--      "period":   { "days": 30, "start_date":..., "end_date":... },
--      "summary":  { "views":..., "call":..., "whatsapp":..., "direction":..., "total_leads":... },
--      "previous": {... same shape, for previous 30 days ...},
--      "daily":    [ { "date": "2026-04-21", "views": 12, "call": 1, ... }, ... ],
--      "recent_leads": [ { "action":"whatsapp", "when":"19 May 2026 · 03:42 PM" }, ... ],
--      "reviews":  { "new_in_period":..., "avg_rating":..., "total":... }
--    }
-- =====================================================
