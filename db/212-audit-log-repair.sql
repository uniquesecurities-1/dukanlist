-- ============================================================
-- db/212 — Audit log repair: column drift + bulk action logging
-- ============================================================
-- AUDIT FINDING: admin_audit_log was created in db/17 with columns
--   (admin_user_id, action, target_type, target_id, target_name,
--    details, ip_hash, ua_summary, created_at)
-- but 12+ later migrations INSERT with column names that don't exist:
--   admin_id      (db/26, 27, 66, 68, 78, 79, 205)
--   business_id   (db/26, 27, 68, 78)
--   action_type   (db/148)
--   payload       (db/148)
--   meta          (db/205)
--   target_label  (db/90)
-- Every such insert sits inside EXCEPTION WHEN OTHERS THEN NULL,
-- so they fail invisibly. Net effect: shop edits, review add/edit/
-- delete, professional verification — none were ever audited.
--
-- STRATEGY (no function rewrites needed):
--   1. ADD the drifted column names as real nullable columns.
--      → the broken INSERTs immediately stop erroring.
--   2. BEFORE INSERT trigger normalizes drifted values into the
--      canonical columns (admin_user_id/action/target_id/target_name/
--      details), so activity.html + admin_recent_activity keep working
--      unchanged and see ALL actions.
--   3. Add a summary log_admin_action() to admin_bulk_set_status
--      (used by admin_bulk_approve / admin_bulk_ban from moderation).
--
-- SAFE: Idempotent. Additive only. Re-runnable.
-- ============================================================

BEGIN;

-- ---- 1. Add drifted column names as real columns -------------
ALTER TABLE admin_audit_log ADD COLUMN IF NOT EXISTS admin_id     UUID;
ALTER TABLE admin_audit_log ADD COLUMN IF NOT EXISTS business_id  UUID;
ALTER TABLE admin_audit_log ADD COLUMN IF NOT EXISTS action_type  TEXT;
ALTER TABLE admin_audit_log ADD COLUMN IF NOT EXISTS payload      JSONB;
ALTER TABLE admin_audit_log ADD COLUMN IF NOT EXISTS meta         JSONB;
ALTER TABLE admin_audit_log ADD COLUMN IF NOT EXISTS target_label TEXT;

-- ---- 2. Normalizer trigger -----------------------------------
CREATE OR REPLACE FUNCTION audit_log_normalize()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  -- admin_id → admin_user_id
  IF NEW.admin_user_id IS NULL AND NEW.admin_id IS NOT NULL THEN
    NEW.admin_user_id := NEW.admin_id;
  END IF;
  -- action_type → action
  IF NEW.action IS NULL AND NEW.action_type IS NOT NULL THEN
    NEW.action := NEW.action_type;
  END IF;
  -- business_id → target_id + target_type
  IF NEW.target_id IS NULL AND NEW.business_id IS NOT NULL THEN
    NEW.target_id   := NEW.business_id::TEXT;
    NEW.target_type := COALESCE(NEW.target_type, 'business');
  END IF;
  -- target_label → target_name
  IF NEW.target_name IS NULL AND NEW.target_label IS NOT NULL THEN
    NEW.target_name := NEW.target_label;
  END IF;
  -- payload / meta → details
  IF NEW.details IS NULL THEN
    NEW.details := COALESCE(NEW.payload, NEW.meta);
  END IF;
  -- action must never be NULL (activity viewer filters on it)
  IF NEW.action IS NULL THEN
    NEW.action := 'unknown';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_log_normalize ON admin_audit_log;
CREATE TRIGGER trg_audit_log_normalize
  BEFORE INSERT ON admin_audit_log
  FOR EACH ROW EXECUTE FUNCTION audit_log_normalize();

-- ---- 3. Bulk approve/ban summary logging ---------------------
CREATE OR REPLACE FUNCTION admin_bulk_set_status(
  p_ids    UUID[],
  p_status TEXT,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_admin_id UUID := auth.uid();
  v_changed_count INT := 0;
  v_id UUID;
  v_old_status TEXT;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;
  IF p_status NOT IN ('active','pending','pending_review','flagged','banned','self_hidden') THEN
    RAISE EXCEPTION 'Invalid status: %', p_status;
  END IF;
  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL OR array_length(p_ids, 1) = 0 THEN
    RAISE EXCEPTION 'No business IDs provided';
  END IF;
  IF array_length(p_ids, 1) > 200 THEN
    RAISE EXCEPTION 'Too many IDs (max 200 per bulk action)';
  END IF;

  FOREACH v_id IN ARRAY p_ids LOOP
    SELECT status INTO v_old_status FROM businesses WHERE id = v_id;
    IF v_old_status IS NULL THEN CONTINUE; END IF;
    IF v_old_status = p_status THEN CONTINUE; END IF;
    UPDATE businesses
       SET status = p_status, updated_at = NOW()
     WHERE id = v_id;
    INSERT INTO business_edits(business_id, field_name, old_value, new_value, edited_by, edited_role)
      VALUES (v_id, 'status', v_old_status, p_status, v_admin_id, 'admin');
    v_changed_count := v_changed_count + 1;
  END LOOP;

  -- db/212: one summary audit row per bulk operation
  BEGIN
    PERFORM public.log_admin_action(
      CASE p_status WHEN 'active' THEN 'bulk_approve'
                    WHEN 'banned' THEN 'bulk_ban'
                    ELSE 'bulk_set_' || p_status END,
      'business', 'bulk', NULL,
      jsonb_build_object('count', v_changed_count,
                         'requested', array_length(p_ids, 1),
                         'ids', to_jsonb(p_ids),
                         'reason', p_reason)
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object(
    'ok',            TRUE,
    'changed_count', v_changed_count,
    'requested',     array_length(p_ids, 1),
    'new_status',    p_status
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_bulk_set_status(UUID[], TEXT, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ---- Verify (run separately after commit) --------------------
-- 1. Trigger exists:
--    SELECT tgname FROM pg_trigger WHERE tgname='trg_audit_log_normalize';
-- 2. Drifted-column insert now lands + normalizes:
--    (edit any shop in /admin/shop.html, then:)
--    SELECT action, target_id, admin_user_id, created_at
--    FROM admin_audit_log ORDER BY created_at DESC LIMIT 5;
-- 3. Bulk approve from moderation logs a 'bulk_approve' row.

DO $$ BEGIN
  RAISE NOTICE '✓ db/212 installed. Audit log accepts legacy column names (normalized into canonical columns); bulk approve/ban now audited.';
END $$;
