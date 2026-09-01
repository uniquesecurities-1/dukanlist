-- ============================================================
-- db/213 — 🔥 Trending This Week (public RPC from leads_log)
-- ============================================================
-- leads_log records every view/call/whatsapp/direction/share tap
-- but was only read by owner analytics. This RPC surfaces the
-- most-engaged ACTIVE shops of the last 7 days for the homepage
-- "Trending" section. Weighted: contact actions worth more than
-- passive views (a call is a stronger signal than a view).
--
-- Public + anon callable (read-only, no PII exposed).
-- SAFE: Idempotent. Re-runnable.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.get_trending_shops(
  p_city_id INT DEFAULT NULL,
  p_limit   INT DEFAULT 8
)
RETURNS TABLE (
  id            UUID,
  name          TEXT,
  name_hi       TEXT,
  slug          TEXT,
  category_name TEXT,
  city_name     TEXT,
  photo         TEXT,
  rating_avg    NUMERIC,
  rating_count  INT,
  likes_count   INT,
  trend_score   BIGINT,
  week_leads    BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH weekly AS (
    SELECT
      l.business_id,
      COUNT(*) AS week_leads,
      SUM(CASE l.action
            WHEN 'call'      THEN 5
            WHEN 'whatsapp'  THEN 5
            WHEN 'direction' THEN 3
            WHEN 'share'     THEN 3
            ELSE 1               -- view
          END) AS trend_score
    FROM leads_log l
    WHERE l.created_at > NOW() - INTERVAL '7 days'
    GROUP BY l.business_id
  )
  SELECT
    b.id,
    b.name,
    b.name_hi,
    b.slug,
    c.name  AS category_name,
    gc.name AS city_name,
    (CASE WHEN array_length(b.photos, 1) > 0 THEN b.photos[1] ELSE NULL END) AS photo,
    b.rating_avg,
    b.rating_count,
    COALESCE(b.likes_count, 0) AS likes_count,
    w.trend_score,
    w.week_leads
  FROM weekly w
  JOIN businesses b ON b.id = w.business_id
  LEFT JOIN categories c   ON c.id = b.category_id
  LEFT JOIN geo_cities gc  ON gc.id = b.city_id
  WHERE b.status = 'active'
    AND (p_city_id IS NULL OR b.city_id = p_city_id)
  ORDER BY w.trend_score DESC, b.rating_avg DESC NULLS LAST
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 8), 1), 24);
$$;

GRANT EXECUTE ON FUNCTION public.get_trending_shops(INT, INT) TO anon;
GRANT EXECUTE ON FUNCTION public.get_trending_shops(INT, INT) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- Verify:
-- SELECT name, trend_score, week_leads FROM get_trending_shops(NULL, 8);

DO $$ BEGIN
  RAISE NOTICE '✓ db/213 installed. get_trending_shops() ready for homepage Trending section.';
END $$;
