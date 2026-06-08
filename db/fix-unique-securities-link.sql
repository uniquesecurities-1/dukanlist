-- =====================================================
-- Targeted fix: Link info@digimutualgoals.com to Unique Securities
-- =====================================================
-- Issue: Photo upload fails on Unique Securities even after db/87 + db/122.
-- Probable cause: business_owners row missing auth_user_id link OR
--                 business.email differs from owner login email.
--
-- This SQL surgically links Unique Securities to info@digimutualgoals.com,
-- regardless of how their emails are stored, and confirms the email so
-- RLS check always passes.
--
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

DO $$
DECLARE
  v_user_id        UUID;
  v_business_id    UUID;
  v_business_name  TEXT;
  v_existing_link  UUID;
BEGIN
  -- 1. Find auth user
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE LOWER(email) = 'info@digimutualgoals.com'
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE NOTICE '❌ User info@digimutualgoals.com NOT FOUND in auth.users';
    RAISE NOTICE '   Solution: Make sure this account is registered, OR';
    RAISE NOTICE '   update this SQL with the correct login email.';
    RETURN;
  END IF;

  RAISE NOTICE '✅ Found user: %', v_user_id;

  -- 2. Find Unique Securities business (case-insensitive, oldest first)
  SELECT id, name INTO v_business_id, v_business_name
  FROM businesses
  WHERE name ILIKE 'Unique Securities%'
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_business_id IS NULL THEN
    RAISE NOTICE '❌ "Unique Securities" shop NOT FOUND in businesses table';
    RETURN;
  END IF;

  RAISE NOTICE '✅ Found shop: % (%)', v_business_name, v_business_id;

  -- 3. Check current link state
  SELECT auth_user_id INTO v_existing_link
  FROM business_owners
  WHERE business_id = v_business_id
  ORDER BY added_at ASC NULLS LAST
  LIMIT 1;

  IF v_existing_link = v_user_id THEN
    RAISE NOTICE '✅ ALREADY CORRECTLY LINKED — no change needed';
  ELSIF EXISTS (
    SELECT 1 FROM business_owners
    WHERE business_id = v_business_id AND auth_user_id IS NULL
  ) THEN
    -- Update the orphan row
    UPDATE business_owners
       SET auth_user_id = v_user_id
     WHERE business_id = v_business_id AND auth_user_id IS NULL;
    RAISE NOTICE '✅ UPDATED existing business_owners row → linked user %', v_user_id;
  ELSIF NOT EXISTS (
    SELECT 1 FROM business_owners
    WHERE business_id = v_business_id AND auth_user_id = v_user_id
  ) THEN
    -- Insert new owner row
    INSERT INTO business_owners (business_id, auth_user_id, role, added_at)
    VALUES (v_business_id, v_user_id, 'owner', NOW());
    RAISE NOTICE '✅ INSERTED new business_owners row → linked user %', v_user_id;
  END IF;
END $$;

-- 4. Force-confirm email so RLS check always passes
UPDATE auth.users
   SET email_confirmed_at = COALESCE(email_confirmed_at, NOW())
 WHERE LOWER(email) = 'info@digimutualgoals.com'
   AND email_confirmed_at IS NULL;

COMMIT;


-- ============================================================
-- VERIFY FINAL STATE
-- ============================================================
SELECT
  '🎯 FINAL STATE'                              AS check_type,
  u.email                                       AS owner_email,
  u.email_confirmed_at                          AS email_verified,
  b.name                                        AS shop_name,
  b.id::TEXT                                    AS business_id,
  bo.role,
  bo.auth_user_id::TEXT                         AS linked_auth_id
FROM business_owners bo
JOIN businesses b ON b.id = bo.business_id
JOIN auth.users u ON u.id = bo.auth_user_id
WHERE u.email = 'info@digimutualgoals.com'
   OR b.name ILIKE 'Unique Securities%';
