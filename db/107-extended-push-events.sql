-- =====================================================
-- db/107-extended-push-events.sql
-- =====================================================
-- STRATEGIC PHASE 3 (2026-06-05):
--   Extend real-time push alerts beyond call/whatsapp.
--   Add per-event throttling to prevent spam.
--
--   New events:
--     favorite    — Customer added shop to favorites
--     review      — New review submitted
--     view_burst  — 5+ views in last 30 minutes (special signal)
--
-- THROTTLE RULES (built into notify_owner_event):
--   call         — max 1 push per 5 minutes
--   whatsapp     — max 1 push per 5 minutes
--   favorite     — max 1 push per 60 minutes
--   review       — always send (no throttle)
--   view_burst   — max 1 push per 6 hours (don't be annoying)
--
-- ZERO COST — same Supabase Pro plan + same Vercel free tier.
-- ZERO new external dependencies.
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. notify_throttle table — track last push per business+event
-- ============================================================
CREATE TABLE IF NOT EXISTS notify_throttle (
  business_id   UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  event_type    TEXT NOT NULL,
  last_sent_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  send_count    INT  NOT NULL DEFAULT 1,
  PRIMARY KEY (business_id, event_type)
);

CREATE INDEX IF NOT EXISTS idx_notify_throttle_recent
  ON notify_throttle (business_id, last_sent_at DESC);

-- RLS — locked, only RPCs touch this
ALTER TABLE notify_throttle ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS notify_throttle_no_direct ON notify_throttle;
CREATE POLICY notify_throttle_no_direct ON notify_throttle FOR SELECT USING (false);


-- ============================================================
-- 2. notify_owner_event(business_id, event_type) RPC
--    Returns JSONB with:
--      - allowed: boolean (false if throttled)
--      - subscriptions: array of push subs (if allowed)
--      - cooldown_minutes_remaining: how long until next allowed
--      - shop_name, shop_slug: for the notification body
-- ============================================================
DROP FUNCTION IF EXISTS notify_owner_event(UUID, TEXT);
CREATE OR REPLACE FUNCTION notify_owner_event(
  p_business_id UUID,
  p_event_type  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now           TIMESTAMPTZ := NOW();
  v_last_sent     TIMESTAMPTZ;
  v_cooldown_min  INT;
  v_elapsed_min   INT;
  v_remaining     INT;
  v_shop_name     TEXT;
  v_shop_slug     TEXT;
  v_subs          JSONB := '[]'::jsonb;
  v_count         INT := 0;
BEGIN
  -- Validate event type
  IF p_event_type NOT IN ('call','whatsapp','favorite','review','view_burst') THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'reason',  'invalid_event_type'
    );
  END IF;

  -- Per-event cooldown
  v_cooldown_min := CASE p_event_type
    WHEN 'call'       THEN 5
    WHEN 'whatsapp'   THEN 5
    WHEN 'favorite'   THEN 60
    WHEN 'review'     THEN 0
    WHEN 'view_burst' THEN 360
    ELSE 5
  END;

  -- Check throttle
  SELECT last_sent_at INTO v_last_sent
  FROM notify_throttle
  WHERE business_id = p_business_id AND event_type = p_event_type;

  IF v_last_sent IS NOT NULL AND v_cooldown_min > 0 THEN
    v_elapsed_min := FLOOR(EXTRACT(EPOCH FROM (v_now - v_last_sent)) / 60)::INT;
    IF v_elapsed_min < v_cooldown_min THEN
      v_remaining := v_cooldown_min - v_elapsed_min;
      RETURN jsonb_build_object(
        'allowed',                     false,
        'reason',                      'throttled',
        'cooldown_minutes_remaining',  v_remaining
      );
    END IF;
  END IF;

  -- Get shop info for notification body
  BEGIN
    SELECT name, slug INTO v_shop_name, v_shop_slug
    FROM businesses WHERE id = p_business_id;
  EXCEPTION WHEN OTHERS THEN
    v_shop_name := 'Your business';
    v_shop_slug := '';
  END;

  -- Get owner push subscriptions (using existing helper from db/46)
  BEGIN
    SELECT jsonb_agg(jsonb_build_object(
      'endpoint', endpoint,
      'p256dh',   p256dh,
      'auth',     auth
    )), COUNT(*)
    INTO v_subs, v_count
    FROM push_subscriptions ps
    WHERE ps.user_id IN (
      SELECT user_id FROM business_owners WHERE business_id = p_business_id
    )
    AND ps.audience = 'shopkeeper'
    AND COALESCE(ps.failed_count, 0) < 5;
  EXCEPTION WHEN OTHERS THEN
    v_subs := '[]'::jsonb;
    v_count := 0;
  END;

  -- Record send (upsert)
  INSERT INTO notify_throttle (business_id, event_type, last_sent_at, send_count)
  VALUES (p_business_id, p_event_type, v_now, 1)
  ON CONFLICT (business_id, event_type)
  DO UPDATE SET
    last_sent_at = v_now,
    send_count   = notify_throttle.send_count + 1;

  RETURN jsonb_build_object(
    'allowed',         true,
    'shop_name',       v_shop_name,
    'shop_slug',       v_shop_slug,
    'event_type',      p_event_type,
    'subscriptions',   COALESCE(v_subs, '[]'::jsonb),
    'subscriber_count', v_count
  );
END;
$$;

GRANT EXECUTE ON FUNCTION notify_owner_event(UUID, TEXT) TO authenticated, anon;


-- ============================================================
-- 3. count_recent_views(business_id, minutes) helper
--    Used by client to detect view_burst (5+ in 30 min).
-- ============================================================
DROP FUNCTION IF EXISTS count_recent_views(UUID, INT);
CREATE OR REPLACE FUNCTION count_recent_views(
  p_business_id UUID,
  p_minutes     INT DEFAULT 30
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE v_count INT;
BEGIN
  IF p_minutes < 1 OR p_minutes > 1440 THEN p_minutes := 30; END IF;
  SELECT COUNT(*) INTO v_count
  FROM leads_log
  WHERE business_id = p_business_id
    AND action = 'view'
    AND created_at >= NOW() - (p_minutes || ' minutes')::INTERVAL;
  RETURN COALESCE(v_count, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION count_recent_views(UUID, INT) TO authenticated, anon;


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'db/107 installed.';
  RAISE NOTICE '  Table:    notify_throttle (RLS locked)';
  RAISE NOTICE '  RPC:      notify_owner_event(business_id, event_type)';
  RAISE NOTICE '  RPC:      count_recent_views(business_id, minutes)';
  RAISE NOTICE '';
  RAISE NOTICE '  Throttle: call=5min, whatsapp=5min, favorite=60min,';
  RAISE NOTICE '            review=always, view_burst=6hr';
END $$;
