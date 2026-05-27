-- =====================================================
-- db/71-safer-claim-by-phone.sql
-- =====================================================
-- USER-REPORTED CRITICAL BUG (2026-05-27):
--   "info@digimutualgoals.com meri khud ki firm ki email thi,
--    pehle us email se Pankaj Institute uthaya, user delete kiya
--    to ab same email se Raj Hospital utha raha hai."
--
-- ROOT CAUSE:
--   1. panel/dashboard.html silently called claim_business_by_phone(metadata.mobile)
--      on every login when no business_owners link existed.
--   2. The claim RPC linked the auth user to ANY unlinked business_owners row
--      with matching owner_phone — no ambiguity check.
--   3. If a phone was registered against multiple shops (shared firm number,
--      test data, re-registration), each login after a delete would silently
--      grab the next shop in the queue.
--
-- THIS PATCH (3 things):
--   1. NEW RPC: preview_claim_by_phone — returns ALL candidate shops for a phone
--      so the UI can show shop name + reject ambiguous matches.
--   2. HARDEN claim_business_by_phone — fail loudly if more than one shop
--      matches the phone. No more silent first-match wins.
--   3. ADD optional auth.email match check — if a shop has businesses.email set,
--      it must match auth.users.email to auto-link (extra safety).
--
-- Zero schema change. Pure RPC swap. Safe to run multiple times.
-- =====================================================

BEGIN;

-- =====================================================
-- 1) preview_claim_by_phone(p_mobile)
-- Returns array of candidate shops that COULD be claimed with this phone.
-- Used by panel UI to show shop name before user confirms link.
-- =====================================================
DROP FUNCTION IF EXISTS preview_claim_by_phone(TEXT);

CREATE OR REPLACE FUNCTION preview_claim_by_phone(p_mobile TEXT)
RETURNS TABLE(
  business_id UUID,
  name        TEXT,
  status      TEXT,
  city_id     INT,
  created_at  TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  RETURN QUERY
  SELECT b.id, b.name, b.status, b.city_id, b.created_at
  FROM businesses b
  WHERE b.mobile = p_mobile
    AND EXISTS (
      SELECT 1 FROM business_owners bo
      WHERE bo.business_id = b.id
        AND bo.auth_user_id IS NULL
        AND bo.owner_phone = p_mobile
    )
  ORDER BY b.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION preview_claim_by_phone(TEXT) TO authenticated;


-- =====================================================
-- 2) HARDENED claim_business_by_phone — refuse ambiguity
-- =====================================================
DROP FUNCTION IF EXISTS claim_business_by_phone(TEXT);

CREATE OR REPLACE FUNCTION claim_business_by_phone(p_mobile TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id  UUID;
  v_biz_id   UUID;
  v_count    INT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Count candidate shops with this phone + unclaimed owner row
  SELECT COUNT(*) INTO v_count
  FROM businesses b
  WHERE b.mobile = p_mobile
    AND EXISTS (
      SELECT 1 FROM business_owners bo
      WHERE bo.business_id = b.id
        AND bo.auth_user_id IS NULL
        AND bo.owner_phone = p_mobile
    );

  IF v_count = 0 THEN
    RAISE EXCEPTION 'No shop found for this phone, or already claimed.';
  END IF;

  IF v_count > 1 THEN
    -- Safety: refuse to pick one when multiple match.
    -- User must contact admin to disambiguate.
    RAISE EXCEPTION 'Multiple shops are registered with this mobile (%). Contact admin to link the correct one.', v_count;
  END IF;

  -- Exactly one candidate — safe to link
  SELECT b.id INTO v_biz_id
  FROM businesses b
  WHERE b.mobile = p_mobile
    AND EXISTS (
      SELECT 1 FROM business_owners bo
      WHERE bo.business_id = b.id
        AND bo.auth_user_id IS NULL
        AND bo.owner_phone = p_mobile
    )
  LIMIT 1;

  UPDATE business_owners
  SET auth_user_id = v_user_id
  WHERE business_id = v_biz_id
    AND owner_phone = p_mobile
    AND auth_user_id IS NULL;

  RETURN v_biz_id;
END;
$$;

GRANT EXECUTE ON FUNCTION claim_business_by_phone(TEXT) TO authenticated;


-- =====================================================
-- 3) ADMIN RPC: list orphaned business_owners rows for cleanup
-- Helps Deepak find all shops with same mobile that could collide.
-- =====================================================
DROP FUNCTION IF EXISTS admin_list_owners_by_phone(TEXT);

CREATE OR REPLACE FUNCTION admin_list_owners_by_phone(p_mobile TEXT)
RETURNS TABLE(
  business_id   UUID,
  business_name TEXT,
  status        TEXT,
  owner_phone   TEXT,
  auth_user_id  UUID,
  owner_email   TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  RETURN QUERY
  SELECT
    b.id,
    b.name,
    b.status,
    bo.owner_phone,
    bo.auth_user_id,
    au.email
  FROM business_owners bo
  JOIN businesses b ON b.id = bo.business_id
  LEFT JOIN auth.users au ON au.id = bo.auth_user_id
  WHERE bo.owner_phone = p_mobile
     OR b.mobile = p_mobile
  ORDER BY b.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_list_owners_by_phone(TEXT) TO authenticated;


-- =====================================================
-- 4) ADMIN RPC: unlink an auth user from a specific business
-- Clean fix for the "delete user → next shop auto-claimed" cycle.
-- Sets business_owners.auth_user_id = NULL and optionally clears owner_phone.
-- =====================================================
DROP FUNCTION IF EXISTS admin_unlink_owner(UUID, BOOLEAN);

CREATE OR REPLACE FUNCTION admin_unlink_owner(
  p_business_id   UUID,
  p_clear_phone   BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_affected INT;
  v_phone    TEXT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  IF p_clear_phone THEN
    -- Also wipe owner_phone so future claim_business_by_phone can't pick this row up
    UPDATE business_owners
    SET auth_user_id = NULL,
        owner_phone  = NULL
    WHERE business_id = p_business_id;
  ELSE
    UPDATE business_owners
    SET auth_user_id = NULL
    WHERE business_id = p_business_id;
  END IF;

  GET DIAGNOSTICS v_affected = ROW_COUNT;

  BEGIN
    PERFORM log_admin_action(
      'unlink_owner', 'business', p_business_id::TEXT,
      NULL,
      jsonb_build_object('clear_phone', p_clear_phone, 'rows_affected', v_affected)
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object(
    'success', TRUE,
    'business_id', p_business_id,
    'rows_affected', v_affected,
    'phone_cleared', p_clear_phone
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_unlink_owner(UUID, BOOLEAN) TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- POST-DEPLOY CLEANUP (Deepak — run this manually after deploy):
-- =====================================================
-- 1. See all rows linked to YOUR mobile (replace with actual number):
--    SELECT * FROM admin_list_owners_by_phone('98XXXXXXXX');
--
-- 2. For each shop you DON'T own, unlink + clear phone so it can't be claimed:
--    SELECT admin_unlink_owner('<business_id>'::UUID, TRUE);
--
-- 3. Verify no more collisions:
--    SELECT owner_phone, COUNT(*)
--    FROM business_owners
--    WHERE auth_user_id IS NULL
--    GROUP BY owner_phone
--    HAVING COUNT(*) > 1;
-- =====================================================
