-- ============================================================
-- db/186 — admin_manual_link_owner — bypass shadow-row requirement
-- ============================================================
-- USE CASE:
--   Admin bulk-published Suvidha Gas. Owner clicked email magic
--   link, account got auto-created (subhash125104@gmail.com,
--   email verified). But because Supabase magic link redirected
--   to /panel/dashboard instead of /claim-complete.html, the
--   business_owners row was never inserted.
--
--   /panel/dashboard tries claim_business_by_phone — fails because
--   that RPC requires a shadow business_owners row (only created
--   during self-registration).
--
-- THIS RPC:
--   Admin pastes the owner email → we look up the auth.users row,
--   verify email_confirmed_at is set, then INSERT business_owners.
--   No shadow row required. Idempotent.
--
-- SAFETY:
--   - Admin only (is_admin check)
--   - Email MUST be confirmed (so we know it's a real verified user)
--   - Refuses if business already has any owner (prevents takeover)
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION admin_manual_link_owner(
  p_business_id UUID,
  p_email       TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_email TEXT;
  v_auth_user_id UUID;
  v_email_confirmed TIMESTAMPTZ;
  v_biz RECORD;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  IF p_email IS NULL OR NOT (p_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') THEN
    RAISE EXCEPTION 'Invalid email format';
  END IF;

  -- Get admin's audit email
  SELECT email INTO v_admin_email FROM admin_users WHERE auth_user_id = auth.uid();

  -- Look up auth user by email
  SELECT id, email_confirmed_at INTO v_auth_user_id, v_email_confirmed
    FROM auth.users WHERE lower(email) = lower(TRIM(p_email)) LIMIT 1;

  IF v_auth_user_id IS NULL THEN
    RAISE EXCEPTION 'No auth user found with email %', p_email;
  END IF;

  IF v_email_confirmed IS NULL THEN
    RAISE EXCEPTION 'User % exists but email is NOT yet verified. Ask them to verify first OR force-verify from moderation page.', p_email;
  END IF;

  -- Look up business
  SELECT id, name, status, mobile, claim_status INTO v_biz
    FROM businesses WHERE id = p_business_id;
  IF v_biz.id IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  -- Refuse if already has any owner (prevent accidental takeover)
  IF EXISTS (SELECT 1 FROM business_owners WHERE business_id = v_biz.id AND auth_user_id IS NOT NULL) THEN
    RAISE EXCEPTION 'This listing already has a linked owner account. Remove existing link first if you really want to re-assign.';
  END IF;

  -- Insert / update business_owners row
  -- (Some listings have a shadow row with auth_user_id=NULL from register_business_public —
  --  upgrade that instead of creating a duplicate)
  IF EXISTS (SELECT 1 FROM business_owners WHERE business_id = v_biz.id AND auth_user_id IS NULL) THEN
    UPDATE business_owners
       SET auth_user_id = v_auth_user_id,
           added_at = COALESCE(added_at, NOW())
     WHERE business_id = v_biz.id
       AND auth_user_id IS NULL;
  ELSE
    INSERT INTO business_owners (business_id, auth_user_id, owner_phone, role, added_at)
    VALUES (v_biz.id, v_auth_user_id, v_biz.mobile, 'owner', NOW());
  END IF;

  -- Mark business as claimed
  UPDATE businesses
     SET claim_status = 'claimed_verified',
         claimed_at   = NOW(),
         updated_at   = NOW()
   WHERE id = v_biz.id;

  -- Audit log (best-effort)
  IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'admin_errors' AND schemaname = 'public') THEN
    INSERT INTO admin_errors (
      user_email, page, error_type, error_message, payload, resolved, resolved_at
    ) VALUES (
      v_admin_email,
      '/admin/shop.html',
      'manual-link',
      'Manually linked ' || p_email || ' to ' || v_biz.name,
      jsonb_build_object('business_id', v_biz.id, 'email', p_email, 'auth_user_id', v_auth_user_id),
      TRUE,
      NOW()
    );
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'business_id', v_biz.id,
    'business_name', v_biz.name,
    'linked_email', LOWER(TRIM(p_email)),
    'auth_user_id', v_auth_user_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_manual_link_owner(UUID, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/186 installed. admin_manual_link_owner ready for cases where claim_business_by_phone fails.';
END $$;
