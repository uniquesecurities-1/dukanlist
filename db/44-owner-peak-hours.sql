-- db/44-owner-peak-hours.sql
-- Owner Insights Pack: 24-hour activity heatmap
--
-- Returns hour-of-day breakdown of leads (any action) for the owner's
-- business over the last N days. Used by /panel/analytics.html to
-- show a bar chart of "When do customers visit your shop?"
--
-- Safe to re-run.

BEGIN;

DROP FUNCTION IF EXISTS owner_peak_hours(UUID, INT);
CREATE OR REPLACE FUNCTION owner_peak_hours(
  p_business_id UUID,
  p_days        INT DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id    UUID;
  v_is_owner   BOOLEAN;
  v_start      TIMESTAMPTZ;
  v_buckets    JSONB;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM business_owners
    WHERE business_id = p_business_id AND auth_user_id = v_user_id
  ) INTO v_is_owner;
  IF NOT v_is_owner THEN RAISE EXCEPTION 'Not authorised'; END IF;

  p_days := GREATEST(1, LEAST(p_days, 90));
  v_start := NOW() - (p_days || ' days')::INTERVAL;

  -- Build a 0-23 hour series so empty hours show zero
  WITH hour_series AS (
    SELECT generate_series(0, 23) AS h
  ),
  hour_counts AS (
    SELECT EXTRACT(HOUR FROM (created_at AT TIME ZONE 'Asia/Kolkata'))::INT AS h,
           COUNT(*) FILTER (WHERE action = 'view')                  AS views,
           COUNT(*) FILTER (WHERE action IN ('call','whatsapp','direction')) AS leads,
           COUNT(*)                                                  AS total
      FROM leads_log
     WHERE business_id = p_business_id
       AND created_at >= v_start
     GROUP BY 1
  )
  SELECT jsonb_agg(
           jsonb_build_object(
             'hour',  hs.h,
             'views', COALESCE(hc.views, 0),
             'leads', COALESCE(hc.leads, 0),
             'total', COALESCE(hc.total, 0)
           ) ORDER BY hs.h
         )
    INTO v_buckets
    FROM hour_series hs
    LEFT JOIN hour_counts hc ON hc.h = hs.h;

  RETURN jsonb_build_object(
    'days',    p_days,
    'buckets', COALESCE(v_buckets, '[]'::JSONB)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION owner_peak_hours(UUID, INT) TO authenticated;

COMMIT;
