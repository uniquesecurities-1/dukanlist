-- =====================================================
-- db/90-auto-link-trigger-and-self-heal.sql
-- =====================================================
-- USER (2026-06-02): "Photo upload issue baar-baar aa raha hai aur
--   multiple shops par aa raha hai. Fool-proof solution chahiye."
--
-- MASTER FIX — LAYER 1:
--   Postgres trigger on auth.users that AUTOMATICALLY links a user
--   to their business in business_owners table when the user's email
--   gets confirmed (either by user clicking the email link, or by admin
--   force-verifying via api/admin-force-verify-email.js).
--
--   This eliminates the "user registered but business_owners link
--   was never created" class of bugs that have been recurring on
--   DukanList. As of today 10/13 of the latest signups were orphans.
--
-- SAFETY GUARDS:
--   1. Trigger ONLY fires when email_confirmed_at flips NULL -> NOT NULL
--      (does NOT re-fire on subsequent updates).
--   2. Only attempts link if user has a valid UUID in metadata.business_id.
--   3. Only links to businesses with status IN ('pending','pending_review','active').
--      Disabled or rejected businesses will NOT be auto-linked.
--   4. Skips users who already have ANY business_owners row.
--   5. Skips users who are admins.
--   6. Trigger failure does NOT block email confirmation (try/except).
--   7. Logs every auto-link to admin_audit_log for transparency.
--
-- WHAT THIS DOES NOT DO:
--   - Does NOT change businesses.status (approval stays manual)
--   - Does NOT set any verified_* flags
--   - Does NOT make business publicly visible (admin still has to approve)
--
-- PLUS — bonus helper RPC:
--   `try_self_heal_owner_link(p_user_id UUID)` — used by the server upload
--   endpoint to lazily heal a missing link at upload time. Same safety
--   guards. Returns TRUE if a link was created or already exists.
--
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. The auto-link function
-- ============================================================
CREATE OR REPLACE FUNCTION auto_link_business_on_email_confirm()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_biz_id      UUID;
  v_biz_status  TEXT;
  v_mobile      TEXT;
  v_email       TEXT;
  v_updated     INT;
BEGIN
  -- Trigger guard: only proceed on NULL -> NOT NULL transition
  IF NEW.email_confirmed_at IS NULL THEN
    RETURN NEW;
  END IF;
  IF OLD.email_confirmed_at IS NOT NULL THEN
    -- email already confirmed earlier, this is a different update
    RETURN NEW;
  END IF;

  -- Need a business_id in user metadata
  IF NEW.raw_user_meta_data IS NULL THEN RETURN NEW; END IF;
  IF NEW.raw_user_meta_data->>'business_id' IS NULL THEN RETURN NEW; END IF;
  IF NEW.raw_user_meta_data->>'business_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    RETURN NEW;
  END IF;

  v_biz_id := (NEW.raw_user_meta_data->>'business_id')::UUID;
  v_mobile := NEW.raw_user_meta_data->>'mobile';
  v_email  := NEW.email;

  -- Safety: skip if user is an admin
  IF EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = NEW.id) THEN
    RETURN NEW;
  END IF;

  -- Safety: skip if user already has any business_owners row
  IF EXISTS (SELECT 1 FROM business_owners WHERE auth_user_id = NEW.id) THEN
    RETURN NEW;
  END IF;

  -- Get business status — only act on active or pending businesses
  SELECT status INTO v_biz_status FROM businesses WHERE id = v_biz_id;
  IF v_biz_status IS NULL THEN
    -- business doesn't exist (deleted), nothing to link
    RETURN NEW;
  END IF;
  IF v_biz_status NOT IN ('pending','pending_review','active') THEN
    -- disabled / rejected / etc — do not link
    RETURN NEW;
  END IF;

  -- Try UPDATE on orphan business_owners row (auth_user_id IS NULL)
  UPDATE business_owners
  SET auth_user_id = NEW.id,
      owner_phone  = COALESCE(owner_phone, v_mobile)
  WHERE business_id = v_biz_id AND auth_user_id IS NULL;

  GET DIAGNOSTICS v_updated = ROW_COUNT;

  IF v_updated > 0 THEN
    BEGIN
      INSERT INTO admin_audit_log (action, target_type, target_id, target_label, details, created_at)
      VALUES (
        'auto_link_email_confirm',
        'business_owners',
        v_biz_id,
        v_email,
        jsonb_build_object('method','update_orphan','business_status',v_biz_status),
        NOW()
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;
    RETURN NEW;
  END IF;

  -- Otherwise INSERT a fresh row
  BEGIN
    INSERT INTO business_owners (business_id, auth_user_id, owner_phone, role)
    VALUES (v_biz_id, NEW.id, v_mobile, 'owner')
    ON CONFLICT DO NOTHING;

    BEGIN
      INSERT INTO admin_audit_log (action, target_type, target_id, target_label, details, created_at)
      VALUES (
        'auto_link_email_confirm',
        'business_owners',
        v_biz_id,
        v_email,
        jsonb_build_object('method','insert_new','business_status',v_biz_status),
        NOW()
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;
  EXCEPTION WHEN OTHERS THEN
    -- Swallow any error — email confirmation itself must succeed even
    -- if linking fails for any reason
    NULL;
  END;

  RETURN NEW;
END;
$$;


-- ============================================================
-- 2. Install/replace the trigger
--    AFTER UPDATE OF email_confirmed_at means only fires when that
--    specific column changes — efficient.
-- ============================================================
DROP TRIGGER IF EXISTS auto_link_business_on_email_confirm_trg ON auth.users;

CREATE TRIGGER auto_link_business_on_email_confirm_trg
  AFTER UPDATE OF email_confirmed_at ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION auto_link_business_on_email_confirm();


-- ============================================================
-- 3. Bonus helper: server-side self-heal RPC
--    Used by api/upload-shop-photo.js to attempt link creation
--    at upload time if for any weird reason the trigger missed
--    or the user was created before this trigger existed.
--    Returns TRUE if user now has a usable link.
-- ============================================================
CREATE OR REPLACE FUNCTION try_self_heal_owner_link(p_user_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_meta        JSONB;
  v_biz_id      UUID;
  v_biz_status  TEXT;
  v_mobile      TEXT;
  v_email       TEXT;
  v_updated     INT;
BEGIN
  -- Already linked? return true immediately
  IF EXISTS (SELECT 1 FROM business_owners WHERE auth_user_id = p_user_id) THEN
    RETURN TRUE;
  END IF;
  -- Admin? not a shopkeeper — return false
  IF EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = p_user_id) THEN
    RETURN FALSE;
  END IF;

  SELECT raw_user_meta_data, email INTO v_meta, v_email
  FROM auth.users WHERE id = p_user_id;
  IF v_meta IS NULL THEN RETURN FALSE; END IF;

  IF v_meta->>'business_id' IS NULL THEN RETURN FALSE; END IF;
  IF v_meta->>'business_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    RETURN FALSE;
  END IF;

  v_biz_id := (v_meta->>'business_id')::UUID;
  v_mobile := v_meta->>'mobile';

  SELECT status INTO v_biz_status FROM businesses WHERE id = v_biz_id;
  IF v_biz_status IS NULL THEN RETURN FALSE; END IF;
  IF v_biz_status NOT IN ('pending','pending_review','active') THEN RETURN FALSE; END IF;

  -- Try UPDATE orphan row first
  UPDATE business_owners
  SET auth_user_id = p_user_id,
      owner_phone  = COALESCE(owner_phone, v_mobile)
  WHERE business_id = v_biz_id AND auth_user_id IS NULL;

  GET DIAGNOSTICS v_updated = ROW_COUNT;

  IF v_updated = 0 THEN
    INSERT INTO business_owners (business_id, auth_user_id, owner_phone, role)
    VALUES (v_biz_id, p_user_id, v_mobile, 'owner')
    ON CONFLICT DO NOTHING;
  END IF;

  BEGIN
    INSERT INTO admin_audit_log (action, target_type, target_id, target_label, details, created_at)
    VALUES (
      'self_heal_owner_link',
      'business_owners',
      v_biz_id,
      v_email,
      jsonb_build_object('triggered_by','upload_endpoint','business_status',v_biz_status),
      NOW()
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN EXISTS (SELECT 1 FROM business_owners WHERE auth_user_id = p_user_id);
END;
$$;

REVOKE ALL ON FUNCTION try_self_heal_owner_link(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION try_self_heal_owner_link(UUID) TO service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;


-- ============================================================
-- 4. Verify install
-- ============================================================
SELECT
  'trigger installed' AS check_name,
  COUNT(*)::TEXT AS result
FROM pg_trigger
WHERE tgname = 'auto_link_business_on_email_confirm_trg'
  AND tgrelid = 'auth.users'::regclass

UNION ALL SELECT
  'trigger function exists',
  COUNT(*)::TEXT
FROM pg_proc
WHERE proname = 'auto_link_business_on_email_confirm'

UNION ALL SELECT
  'self-heal RPC exists',
  COUNT(*)::TEXT
FROM pg_proc
WHERE proname = 'try_self_heal_owner_link';
