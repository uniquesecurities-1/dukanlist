-- =====================================================
-- db/36-push-subscriptions.sql
-- Web Push subscriptions storage + helper RPCs
-- =====================================================
BEGIN;

CREATE TABLE IF NOT EXISTS push_subscriptions (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  endpoint     TEXT NOT NULL UNIQUE,    -- push service URL (FCM, Mozilla, etc.)
  p256dh       TEXT NOT NULL,           -- client public key
  auth         TEXT NOT NULL,           -- client auth secret
  user_id      UUID,                    -- auth.users.id if logged in, else NULL (anonymous)
  audience     TEXT NOT NULL DEFAULT 'customer'
               CHECK (audience IN ('customer','shopkeeper','admin')),
  user_agent   TEXT,
  city_id      INT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_ok_at   TIMESTAMPTZ,
  failed_count INT NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_push_audience ON push_subscriptions(audience);
CREATE INDEX IF NOT EXISTS idx_push_user     ON push_subscriptions(user_id);

ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;

-- Public can insert (subscribe) and delete their own (by endpoint match)
DROP POLICY IF EXISTS "push_insert_any"  ON push_subscriptions;
DROP POLICY IF EXISTS "push_select_own"  ON push_subscriptions;
DROP POLICY IF EXISTS "push_delete_own"  ON push_subscriptions;

CREATE POLICY "push_insert_any" ON push_subscriptions
  FOR INSERT TO anon, authenticated WITH CHECK (TRUE);

CREATE POLICY "push_select_own" ON push_subscriptions
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR is_admin());

CREATE POLICY "push_delete_own" ON push_subscriptions
  FOR DELETE TO anon, authenticated USING (TRUE);

-- ---------- subscribe_push (PUBLIC) ----------
DROP FUNCTION IF EXISTS subscribe_push(JSONB);

CREATE OR REPLACE FUNCTION subscribe_push(p_data JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  -- Upsert by endpoint (re-subscribing on same device just updates)
  INSERT INTO push_subscriptions (endpoint, p256dh, auth, user_id, audience, user_agent)
  VALUES (
    p_data->>'endpoint',
    p_data->>'p256dh',
    p_data->>'auth',
    auth.uid(),  -- nullable
    COALESCE(p_data->>'audience', 'customer'),
    LEFT(p_data->>'user_agent', 200)
  )
  ON CONFLICT (endpoint) DO UPDATE
    SET p256dh    = EXCLUDED.p256dh,
        auth      = EXCLUDED.auth,
        user_id   = EXCLUDED.user_id,
        audience  = EXCLUDED.audience,
        user_agent= EXCLUDED.user_agent,
        last_ok_at= NULL,
        failed_count = 0
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION subscribe_push(JSONB) TO anon, authenticated;

-- ---------- admin_list_push_subscriptions ----------
DROP FUNCTION IF EXISTS admin_list_push_subscriptions(TEXT);

CREATE OR REPLACE FUNCTION admin_list_push_subscriptions(p_audience TEXT DEFAULT NULL)
RETURNS SETOF push_subscriptions
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT * FROM push_subscriptions
  WHERE failed_count < 5
    AND (p_audience IS NULL OR p_audience = 'all' OR audience = p_audience)
  ORDER BY created_at DESC;
$$;
GRANT EXECUTE ON FUNCTION admin_list_push_subscriptions(TEXT) TO authenticated;

-- ---------- mark_push_failed ----------
DROP FUNCTION IF EXISTS mark_push_failed(TEXT);

CREATE OR REPLACE FUNCTION mark_push_failed(p_endpoint TEXT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE push_subscriptions
     SET failed_count = failed_count + 1
   WHERE endpoint = p_endpoint;
$$;
GRANT EXECUTE ON FUNCTION mark_push_failed(TEXT) TO authenticated;

COMMIT;
