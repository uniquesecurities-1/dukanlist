-- db/46-lead-push.sql
-- Lead-triggered push notifications to shop owners
--
-- Adds:
--   1. list_owner_push_subs(business_id) — service_role only, returns active
--      subscriptions for all owners of the business
--   2. log_lead_push(business_id, action) — public RPC for rate-limited push
--      enqueue. Records to leads_log AND returns owner subscription info if
--      action is 'call' or 'whatsapp' and rate not exceeded.
--
-- Safe to re-run.

BEGIN;

-- 1. List active push subs for a business's owners (service_role only)
DROP FUNCTION IF EXISTS list_owner_push_subs(UUID);
CREATE OR REPLACE FUNCTION list_owner_push_subs(p_business_id UUID)
RETURNS TABLE (
  endpoint TEXT,
  p256dh   TEXT,
  auth     TEXT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE
AS $$
BEGIN
  -- service_role bypasses; for safety also allow is_admin (manual testing)
  IF current_setting('role') <> 'service_role'
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'forbidden: service_role only';
  END IF;

  RETURN QUERY
  SELECT ps.endpoint, ps.p256dh, ps.auth
    FROM push_subscriptions ps
    JOIN business_owners bo ON bo.auth_user_id = ps.user_id
   WHERE bo.business_id = p_business_id
     AND ps.audience = 'shopkeeper'
     AND COALESCE(ps.failed_count, 0) < 5;
END;
$$;

GRANT EXECUTE ON FUNCTION list_owner_push_subs(UUID) TO service_role;

-- 2. Rate-limit helper: how many leads from this IP for this business in last minute
DROP FUNCTION IF EXISTS recent_lead_count(UUID, TEXT, INTERVAL);
CREATE OR REPLACE FUNCTION recent_lead_count(
  p_business_id UUID,
  p_ip_hash     TEXT,
  p_window      INTERVAL DEFAULT '1 minute'
)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE
AS $$
DECLARE v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
    FROM leads_log
   WHERE business_id = p_business_id
     AND ip_hash = p_ip_hash
     AND created_at > NOW() - p_window;
  RETURN COALESCE(v_count, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION recent_lead_count(UUID, TEXT, INTERVAL) TO service_role, authenticated, anon;

COMMIT;
