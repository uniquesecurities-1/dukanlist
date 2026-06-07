-- =====================================================
-- db/117-spotlight-search-walkins.sql
-- =====================================================
-- 4 zero-cost growth features in one migration:
--   1. weekly_spotlight  — admin's pick of the week
--   2. search_log        — track every search (esp. zero-result)
--   3. businesses.walk_ins_today + walk_ins_total — tap counter
--   4. RPCs for all of the above
--
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

-- ===== 1. WEEKLY SPOTLIGHT =====
CREATE TABLE IF NOT EXISTS weekly_spotlight (
  id              SERIAL PRIMARY KEY,
  business_id     UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  week_start      DATE NOT NULL,           -- Monday of the spotlight week
  picked_by       UUID REFERENCES auth.users(id),
  pick_reason     TEXT,                    -- admin's short note
  whatsapp_sent   BOOLEAN DEFAULT FALSE,
  featured_until  TIMESTAMPTZ,             -- auto-set to week_start + 30d
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (week_start)
);
CREATE INDEX IF NOT EXISTS idx_spotlight_week ON weekly_spotlight(week_start DESC);

-- ===== 2. SEARCH LOG =====
CREATE TABLE IF NOT EXISTS search_log (
  id              BIGSERIAL PRIMARY KEY,
  query           TEXT NOT NULL,
  query_norm      TEXT GENERATED ALWAYS AS (LOWER(TRIM(query))) STORED,
  city_slug       TEXT,
  result_count    INT NOT NULL DEFAULT 0,
  user_agent      TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_search_norm   ON search_log(query_norm);
CREATE INDEX IF NOT EXISTS idx_search_zero   ON search_log(created_at DESC) WHERE result_count = 0;
CREATE INDEX IF NOT EXISTS idx_search_recent ON search_log(created_at DESC);

-- ===== 3. WALK-IN COUNTER =====
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS walk_ins_today INT DEFAULT 0;
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS walk_ins_total INT DEFAULT 0;
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS walk_ins_reset_at DATE DEFAULT CURRENT_DATE;

-- ===== RLS =====
ALTER TABLE weekly_spotlight ENABLE ROW LEVEL SECURITY;
ALTER TABLE search_log       ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS spotlight_public_read ON weekly_spotlight;
CREATE POLICY spotlight_public_read ON weekly_spotlight FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS search_log_admin_read ON search_log;
CREATE POLICY search_log_admin_read ON search_log FOR SELECT
  USING (EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid()));

-- Anonymous can INSERT into search_log (track all searches)
DROP POLICY IF EXISTS search_log_anon_insert ON search_log;
CREATE POLICY search_log_anon_insert ON search_log FOR INSERT WITH CHECK (TRUE);


-- =====================================================
-- RPC: log_search — call from frontend after every search
-- =====================================================
DROP FUNCTION IF EXISTS log_search(TEXT, TEXT, INT);
CREATE OR REPLACE FUNCTION log_search(
  p_query        TEXT,
  p_city_slug    TEXT DEFAULT NULL,
  p_result_count INT  DEFAULT 0
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF p_query IS NULL OR LENGTH(TRIM(p_query)) < 2 THEN RETURN; END IF;
  INSERT INTO search_log (query, city_slug, result_count)
  VALUES (TRIM(p_query), p_city_slug, COALESCE(p_result_count, 0));
END;
$$;
GRANT EXECUTE ON FUNCTION log_search(TEXT, TEXT, INT) TO anon, authenticated;


-- =====================================================
-- RPC: admin_lost_searches — group zero-result searches
-- =====================================================
DROP FUNCTION IF EXISTS admin_lost_searches(INT);
CREATE OR REPLACE FUNCTION admin_lost_searches(p_days INT DEFAULT 7)
RETURNS TABLE (
  query        TEXT,
  city_slug    TEXT,
  hit_count    BIGINT,
  last_seen    TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid()) THEN
    RAISE EXCEPTION 'admin only';
  END IF;
  RETURN QUERY
  SELECT sl.query_norm AS query,
         COALESCE(sl.city_slug, '') AS city_slug,
         COUNT(*) AS hit_count,
         MAX(sl.created_at) AS last_seen
    FROM search_log sl
   WHERE sl.result_count = 0
     AND sl.created_at >= NOW() - (p_days || ' days')::INTERVAL
   GROUP BY sl.query_norm, sl.city_slug
   ORDER BY hit_count DESC, last_seen DESC
   LIMIT 200;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_lost_searches(INT) TO authenticated;


-- =====================================================
-- RPC: admin_set_spotlight — pick a shop for this week
-- =====================================================
DROP FUNCTION IF EXISTS admin_set_spotlight(UUID, TEXT);
CREATE OR REPLACE FUNCTION admin_set_spotlight(
  p_business_id UUID,
  p_reason      TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_week_start DATE;
  v_id INT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid()) THEN
    RAISE EXCEPTION 'admin only';
  END IF;
  -- Monday of current week
  v_week_start := DATE_TRUNC('week', CURRENT_DATE)::DATE;

  INSERT INTO weekly_spotlight (business_id, week_start, picked_by, pick_reason, featured_until)
  VALUES (p_business_id, v_week_start, auth.uid(), p_reason, NOW() + INTERVAL '30 days')
  ON CONFLICT (week_start) DO UPDATE
    SET business_id    = EXCLUDED.business_id,
        picked_by      = EXCLUDED.picked_by,
        pick_reason    = EXCLUDED.pick_reason,
        featured_until = EXCLUDED.featured_until,
        whatsapp_sent  = FALSE
  RETURNING id INTO v_id;

  -- Also give the shop 1-month free Featured boost
  UPDATE businesses
     SET featured_until = GREATEST(COALESCE(featured_until, NOW()), NOW() + INTERVAL '30 days')
   WHERE id = p_business_id;

  RETURN jsonb_build_object(
    'ok',          TRUE,
    'spotlight_id', v_id,
    'week_start',   v_week_start,
    'business_id',  p_business_id
  );
END;
$$;
GRANT EXECUTE ON FUNCTION admin_set_spotlight(UUID, TEXT) TO authenticated;


-- =====================================================
-- RPC: get_current_spotlight — for homepage banner (public)
-- =====================================================
DROP FUNCTION IF EXISTS get_current_spotlight();
CREATE OR REPLACE FUNCTION get_current_spotlight()
RETURNS TABLE (
  business_id  UUID,
  name         TEXT,
  slug         TEXT,
  photo        TEXT,
  city_name    TEXT,
  cat_name     TEXT,
  rating_avg   NUMERIC,
  rating_count INT,
  pick_reason  TEXT,
  week_start   DATE
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT b.id,
         b.name,
         b.slug,
         CASE WHEN array_length(b.photos, 1) > 0 THEN b.photos[1] ELSE NULL END AS photo,
         gc.name AS city_name,
         cat.name AS cat_name,
         b.rating_avg,
         b.rating_count,
         ws.pick_reason,
         ws.week_start
    FROM weekly_spotlight ws
    JOIN businesses b ON b.id = ws.business_id
    LEFT JOIN geo_cities gc ON gc.id = b.city_id
    LEFT JOIN categories cat ON cat.id = COALESCE(b.sub_category_id, b.category_id)
   WHERE b.status = 'active'
   ORDER BY ws.week_start DESC
   LIMIT 1;
END;
$$;
GRANT EXECUTE ON FUNCTION get_current_spotlight() TO anon, authenticated;


-- =====================================================
-- RPC: bump_walk_in — owner taps "+1 walk-in"
-- =====================================================
DROP FUNCTION IF EXISTS bump_walk_in(UUID);
CREATE OR REPLACE FUNCTION bump_walk_in(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_user_id  UUID := auth.uid();
  v_today    INT;
  v_total    INT;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM business_owners
     WHERE business_id = p_business_id AND auth_user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'not your shop';
  END IF;

  -- Reset today's count if date rolled over
  UPDATE businesses
     SET walk_ins_today = CASE WHEN walk_ins_reset_at < CURRENT_DATE THEN 1
                                ELSE walk_ins_today + 1 END,
         walk_ins_total = walk_ins_total + 1,
         walk_ins_reset_at = CURRENT_DATE
   WHERE id = p_business_id
   RETURNING walk_ins_today, walk_ins_total INTO v_today, v_total;

  RETURN jsonb_build_object('today', v_today, 'total', v_total);
END;
$$;
GRANT EXECUTE ON FUNCTION bump_walk_in(UUID) TO authenticated;


-- =====================================================
-- RPC: get_walk_ins — public read for shop card
-- =====================================================
DROP FUNCTION IF EXISTS get_walk_ins(UUID);
CREATE OR REPLACE FUNCTION get_walk_ins(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_today INT;
  v_total INT;
  v_reset DATE;
BEGIN
  SELECT walk_ins_today, walk_ins_total, walk_ins_reset_at
    INTO v_today, v_total, v_reset
    FROM businesses
   WHERE id = p_business_id;
  -- If reset date is stale, today should be displayed as 0
  IF v_reset IS NULL OR v_reset < CURRENT_DATE THEN
    v_today := 0;
  END IF;
  RETURN jsonb_build_object('today', COALESCE(v_today, 0), 'total', COALESCE(v_total, 0));
END;
$$;
GRANT EXECUTE ON FUNCTION get_walk_ins(UUID) TO anon, authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'db/117 installed.';
  RAISE NOTICE '  + weekly_spotlight table + admin_set_spotlight() + get_current_spotlight()';
  RAISE NOTICE '  + search_log table + log_search() + admin_lost_searches()';
  RAISE NOTICE '  + businesses.walk_ins_today/total + bump_walk_in() + get_walk_ins()';
END $$;
