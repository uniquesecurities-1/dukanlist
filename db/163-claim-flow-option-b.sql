-- ============================================================
-- db/163 — Option B claim flow refactor (email-mandatory aligned)
-- ============================================================
-- Earlier db/162 introduced a simple claim_complete RPC that
-- assumed phone-OTP (not configured) and bypassed the existing
-- email-mandatory + user-verify gate that Deepak built into
-- the normal registration flow.
--
-- Option B (chosen by Deepak):
--   • Pre-listed shops are PUBLICLY visible with an UNCLAIMED badge
--     (creates the "padosi shame" FOMO).
--   • Contact details (mobile, WhatsApp) stay HIDDEN until claimed.
--   • Owner claim REQUIRES email + password (Supabase signUp).
--   • Standard Supabase email verification continues to be mandatory
--     (matches existing setup — no shortcuts).
--   • After email verified, auto-approve: claim_status flips to
--     'claimed_verified' AND status stays 'active' (admin already
--     pre-listed so no separate admin moderation needed).
--   • If admin wants to flag bad pre-listed data, they can manually
--     flip status to 'banned' or claim_status back to 'unclaimed'.
--
-- TWO NEW RPCs:
--   1. claim_register_owner(p_token, p_owner_name)
--      Called from claim.html AFTER successful c.auth.signUp().
--      • Validates token + auth.uid()
--      • Links business_owners row (auth_user_id → business)
--      • Updates email/owner_name on businesses
--      • Flips claim_status: unclaimed → claimed_pending
--
--   2. auto_approve_after_email_verify()
--      Called from /panel/email-verified.html AFTER email verify.
--      • Scans the caller's businesses
--      • For each that is pre_listed AND claim_status='claimed_pending'
--        AND email_confirmed_at IS NOT NULL → flips claim_status to
--        'claimed_verified' and ensures status='active'.
--
-- claim_complete (from db/162) is DEPRECATED — kept for backward
-- compat (returns same shape) but now just routes through the new
-- logic so any stragglers don't break.
--
-- admin_pre_list_shop UNCHANGED — still creates status='active' +
-- claim_status='unclaimed' (this is what makes the FOMO work).
--
-- SAFE: All CREATE OR REPLACE. No schema changes. Re-runnable.
-- ============================================================

BEGIN;

-- ============================================================
-- RPC 1: claim_register_owner — called after Supabase signUp
-- ============================================================
-- This is the FIRST step of the owner claim. Supabase already
-- created the auth user (with email/password). We now link them
-- to the pre-listed business and put the listing into the
-- 'claimed_pending' state (still waiting for email verify).
CREATE OR REPLACE FUNCTION claim_register_owner(
  p_token       TEXT,
  p_owner_name  TEXT DEFAULT NULL,
  p_owner_email TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id    UUID := auth.uid();
  v_user_email TEXT;
  v_business   RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Must be authenticated (sign up first)';
  END IF;

  SELECT id, claim_status, mobile, name, pre_listed_at
    INTO v_business
    FROM businesses
   WHERE claim_token = p_token
   LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired claim link';
  END IF;

  IF v_business.claim_status = 'claimed_verified' THEN
    RAISE EXCEPTION 'This listing has already been claimed';
  END IF;

  -- Pre-listed sanity check
  IF v_business.pre_listed_at IS NULL THEN
    RAISE EXCEPTION 'This listing is not a pre-listed shop';
  END IF;

  -- Get user's email from auth.users (set via signUp)
  SELECT email INTO v_user_email FROM auth.users WHERE id = v_user_id;
  IF v_user_email IS NULL THEN
    v_user_email := p_owner_email;
  END IF;

  -- Link owner via business_owners
  INSERT INTO business_owners (business_id, auth_user_id, role, added_at)
  VALUES (v_business.id, v_user_id, 'owner', NOW())
  ON CONFLICT (business_id, auth_user_id) DO NOTHING;

  -- Update business: set email + owner_name, flip to claimed_pending
  UPDATE businesses
     SET claim_status = 'claimed_pending',
         email        = COALESCE(NULLIF(TRIM(v_user_email),''), email),
         owner_name   = COALESCE(NULLIF(TRIM(p_owner_name),''), owner_name),
         last_claim_attempt_at = NOW(),
         claim_sent_count      = COALESCE(claim_sent_count, 0),
         updated_at   = NOW()
   WHERE id = v_business.id;

  RETURN jsonb_build_object(
    'success',         TRUE,
    'business_id',     v_business.id,
    'shop_name',       v_business.name,
    'claim_status',    'claimed_pending',
    'email_verify_required', TRUE,
    'next',            'Verify your email — link bheja gaya hai'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION claim_register_owner(TEXT, TEXT, TEXT) TO authenticated;


-- ============================================================
-- RPC 2: auto_approve_after_email_verify
-- ============================================================
-- Called from /panel/email-verified.html after Supabase confirms
-- the email. Promotes ALL of caller's pre-listed businesses from
-- 'claimed_pending' → 'claimed_verified' provided their auth user
-- now has email_confirmed_at set. Idempotent.
CREATE OR REPLACE FUNCTION auto_approve_after_email_verify()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id           UUID := auth.uid();
  v_email_confirmed   TIMESTAMPTZ;
  v_updated_count     INT := 0;
  v_business_names    TEXT[];
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Must be authenticated';
  END IF;

  -- Check email actually confirmed
  SELECT email_confirmed_at INTO v_email_confirmed
    FROM auth.users WHERE id = v_user_id;
  IF v_email_confirmed IS NULL THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'reason',  'email_not_confirmed',
      'message', 'Aapka email abhi verify nahi hua — link click karo'
    );
  END IF;

  -- Promote all caller's pre-listed pending claims to verified
  WITH promoted AS (
    UPDATE businesses b
       SET claim_status = 'claimed_verified',
           claimed_at   = COALESCE(claimed_at, NOW()),
           status       = CASE WHEN status = 'pending_review' OR status = 'pending'
                               THEN 'active' ELSE status END,
           claim_token  = NULL,  -- one-time use, burn it
           updated_at   = NOW()
     WHERE b.id IN (
       SELECT bo.business_id
         FROM business_owners bo
        WHERE bo.auth_user_id = v_user_id
     )
       AND b.pre_listed_at IS NOT NULL
       AND b.claim_status = 'claimed_pending'
     RETURNING b.id, b.name
  )
  SELECT COUNT(*)::INT, COALESCE(array_agg(name), ARRAY[]::TEXT[])
    INTO v_updated_count, v_business_names
    FROM promoted;

  RETURN jsonb_build_object(
    'success',           TRUE,
    'promoted_count',    v_updated_count,
    'business_names',    v_business_names,
    'email_confirmed_at', v_email_confirmed
  );
END;
$$;

GRANT EXECUTE ON FUNCTION auto_approve_after_email_verify() TO authenticated;


-- ============================================================
-- RPC 3 (DEPRECATED): claim_complete — kept for backward compat
-- ============================================================
-- The old db/162 single-shot RPC. Now routes through the new logic:
-- - Looks up business
-- - Links owner
-- - If email_confirmed → goes straight to claimed_verified + active
-- - Else → claimed_pending (waits for email verify)
CREATE OR REPLACE FUNCTION claim_complete(
  p_token      TEXT,
  p_owner_name TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id         UUID := auth.uid();
  v_email_confirmed TIMESTAMPTZ;
  v_business        RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Must be authenticated';
  END IF;

  SELECT id, claim_status, mobile, name
    INTO v_business
    FROM businesses
   WHERE claim_token = p_token
   LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired claim link';
  END IF;
  IF v_business.claim_status = 'claimed_verified' THEN
    RAISE EXCEPTION 'This listing has already been claimed';
  END IF;

  -- Link owner
  INSERT INTO business_owners (business_id, auth_user_id, role, added_at)
  VALUES (v_business.id, v_user_id, 'owner', NOW())
  ON CONFLICT (business_id, auth_user_id) DO NOTHING;

  -- Check email confirmation status
  SELECT email_confirmed_at INTO v_email_confirmed
    FROM auth.users WHERE id = v_user_id;

  IF v_email_confirmed IS NOT NULL THEN
    -- Email verified → straight to verified
    UPDATE businesses
       SET claim_status = 'claimed_verified',
           claimed_at   = NOW(),
           owner_name   = COALESCE(NULLIF(TRIM(p_owner_name),''), owner_name),
           claim_token  = NULL,
           updated_at   = NOW()
     WHERE id = v_business.id;
    RETURN jsonb_build_object(
      'success',     TRUE,
      'business_id', v_business.id,
      'shop_name',   v_business.name,
      'claim_status','claimed_verified',
      'redirect_to', '/panel/dashboard.html'
    );
  ELSE
    -- Email not yet verified → pending state
    UPDATE businesses
       SET claim_status = 'claimed_pending',
           owner_name   = COALESCE(NULLIF(TRIM(p_owner_name),''), owner_name),
           updated_at   = NOW()
     WHERE id = v_business.id;
    RETURN jsonb_build_object(
      'success',           TRUE,
      'business_id',       v_business.id,
      'shop_name',         v_business.name,
      'claim_status',      'claimed_pending',
      'email_verify_required', TRUE,
      'redirect_to', '/panel/email-verified.html'
    );
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION claim_complete(TEXT, TEXT) TO authenticated;


-- ============================================================
-- RPC 4 (helper): claim_status_check — public read for business.html
-- ============================================================
-- Anon-callable helper that returns whether a business is claimed,
-- without exposing private contact details. business.html uses this
-- to gate the "UNCLAIMED" badge + hide contact buttons.
CREATE OR REPLACE FUNCTION public_claim_status(p_business_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'claim_status',     COALESCE(claim_status, 'claimed_verified'),
    'is_pre_listed',    pre_listed_at IS NOT NULL,
    'is_unclaimed',     claim_status = 'unclaimed',
    'is_claim_pending', claim_status = 'claimed_pending'
  )
  FROM businesses WHERE id = p_business_id LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public_claim_status(UUID) TO anon, authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/163 installed. Option B claim flow live with email-mandatory alignment.';
END $$;
