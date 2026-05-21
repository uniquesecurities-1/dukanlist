-- =====================================================
-- db/29-lead-notifications.sql
-- Instant Lead Ping — in-app notifications for shopkeepers
-- =====================================================
-- When a customer clicks Call / WhatsApp / Share on a business page,
-- log_lead() inserts a row in `notifications` for the shop's owner.
-- Shopkeeper panel reads + marks-as-read via 2 RPCs.
--
-- Future: a Postgres webhook on notifications insert can fire a
-- Resend email or WhatsApp Business API ping — but in-app first.
-- =====================================================

BEGIN;

-- ---------- 1. Notifications table -----------------------------------
CREATE TABLE IF NOT EXISTS notifications (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_id  UUID NOT NULL,                          -- auth.users.id
  business_id   UUID REFERENCES businesses(id) ON DELETE CASCADE,
  type          TEXT NOT NULL,                          -- 'lead_call' | 'lead_whatsapp' | 'lead_share' | 'review' | 'system'
  title         TEXT NOT NULL,
  body          TEXT,
  payload       JSONB DEFAULT '{}'::JSONB,
  read_at       TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notif_recipient
  ON notifications(recipient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notif_unread
  ON notifications(recipient_id) WHERE read_at IS NULL;

-- ---------- RLS -----------------------------------------------------
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "notif_own_read"   ON notifications;
DROP POLICY IF EXISTS "notif_own_update" ON notifications;

CREATE POLICY "notif_own_read" ON notifications
  FOR SELECT TO authenticated
  USING (recipient_id = auth.uid());

CREATE POLICY "notif_own_update" ON notifications
  FOR UPDATE TO authenticated
  USING (recipient_id = auth.uid());

-- ---------- 2. Trigger on leads_log to push notifications --------------
-- The existing log_lead() RPC (or whatever inserts into leads_log)
-- will now trigger a notification row.
--
-- We use a SECURITY DEFINER trigger so it can read business_owners
-- and write notifications regardless of caller RLS.

CREATE OR REPLACE FUNCTION on_lead_notify()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id UUID;
  v_shop_name TEXT;
  v_title TEXT;
  v_body  TEXT;
BEGIN
  -- Find shop owner (first owner of the business)
  SELECT auth_user_id INTO v_owner_id
    FROM business_owners
    WHERE business_id = NEW.business_id
    LIMIT 1;

  IF v_owner_id IS NULL THEN
    RETURN NEW;  -- no owner yet (unclaimed listing); skip
  END IF;

  SELECT name INTO v_shop_name FROM businesses WHERE id = NEW.business_id;

  -- Build human-readable title per action
  v_title := CASE NEW.action
    WHEN 'call'     THEN '📞 Someone clicked Call'
    WHEN 'whatsapp' THEN '💬 Someone clicked WhatsApp'
    WHEN 'share'    THEN '🔗 Your shop was shared'
    WHEN 'view'     THEN NULL  -- skip view spam
    ELSE NULL
  END;

  IF v_title IS NULL THEN
    RETURN NEW;
  END IF;

  v_body := 'A customer just interacted with your shop "' || COALESCE(v_shop_name, '') || '". Open the lead now to follow up.';

  INSERT INTO notifications(recipient_id, business_id, type, title, body, payload)
  VALUES (v_owner_id, NEW.business_id, 'lead_' || NEW.action, v_title, v_body,
          jsonb_build_object('action', NEW.action, 'lead_id', NEW.id));

  RETURN NEW;
END;
$$;

-- Attach trigger to leads_log INSERTs
DROP TRIGGER IF EXISTS trg_lead_notify ON leads_log;
CREATE TRIGGER trg_lead_notify
  AFTER INSERT ON leads_log
  FOR EACH ROW
  EXECUTE FUNCTION on_lead_notify();

-- ---------- 3. List + count + mark-read RPCs ---------------------------

DROP FUNCTION IF EXISTS my_notifications(INT);
CREATE OR REPLACE FUNCTION my_notifications(p_limit INT DEFAULT 20)
RETURNS TABLE (
  id          UUID,
  business_id UUID,
  type        TEXT,
  title       TEXT,
  body        TEXT,
  payload     JSONB,
  read_at     TIMESTAMPTZ,
  created_at  TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT n.id, n.business_id, n.type, n.title, n.body, n.payload, n.read_at, n.created_at
  FROM notifications n
  WHERE n.recipient_id = auth.uid()
  ORDER BY n.created_at DESC
  LIMIT GREATEST(1, LEAST(p_limit, 100));
$$;

GRANT EXECUTE ON FUNCTION my_notifications(INT) TO authenticated;

DROP FUNCTION IF EXISTS my_notifications_unread_count();
CREATE OR REPLACE FUNCTION my_notifications_unread_count()
RETURNS INT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COUNT(*)::INT
  FROM notifications
  WHERE recipient_id = auth.uid() AND read_at IS NULL;
$$;

GRANT EXECUTE ON FUNCTION my_notifications_unread_count() TO authenticated;

DROP FUNCTION IF EXISTS mark_notifications_read(UUID[]);
CREATE OR REPLACE FUNCTION mark_notifications_read(p_ids UUID[] DEFAULT NULL)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_count INT;
BEGIN
  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL THEN
    -- mark all
    UPDATE notifications SET read_at = NOW()
      WHERE recipient_id = auth.uid() AND read_at IS NULL;
  ELSE
    UPDATE notifications SET read_at = NOW()
      WHERE recipient_id = auth.uid() AND id = ANY(p_ids) AND read_at IS NULL;
  END IF;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION mark_notifications_read(UUID[]) TO authenticated;

COMMIT;

-- =====================================================
-- TEST (run as super-admin to verify):
-- =====================================================
-- 1. List recent for a shopkeeper:
--    SELECT * FROM my_notifications(10);
--
-- 2. Force-insert a test notification (admin only):
--    INSERT INTO notifications(recipient_id, business_id, type, title, body)
--    VALUES ('<owner-auth-uid>', '<biz-uuid>', 'system',
--            '🎉 Welcome to DukanList', 'Your shop is live.');
--
-- 3. From the shopkeeper panel (logged in as that user):
--    SELECT my_notifications_unread_count();   -- should be 1
--    SELECT mark_notifications_read(NULL);     -- marks all read, returns 1
-- =====================================================
