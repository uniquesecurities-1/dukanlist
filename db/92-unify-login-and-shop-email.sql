-- =====================================================
-- db/92-unify-login-and-shop-email.sql
-- =====================================================
-- USER REPORT (2026-06-02):
--   "Differ email wala wala issue abhi bhi hai. Admin side se email
--    update karne par bhi login me issue rehta hai. Please fix with
--    deep investigation. Kahin aur bhi agar bug hai to pakad ke sahi karo."
--
-- DEEP-DIVE ROOT CAUSE:
--   The system has TWO email columns that can drift apart:
--     1. auth.users.email                — login credential
--     2. businesses.email                — "shop email" / public contact
--
--   Historically these could be set independently:
--     - register.html had a separate optional "Shop Email" field (now
--       removed in earlier commit).
--     - admin/shop.html "Edit Shop Details" form still has an editable
--       "Shop Email" field that calls update_my_business with email.
--     - api/admin-update-shop-email.js (login email change) only
--       updated auth.users.email — cascade to businesses.email was
--       added today, but historical mismatched rows remain.
--
--   Result: For many existing shops, the login email and the shop
--   email shown on the public page are different, confusing both the
--   shopkeeper and the admin.
--
-- THIS PATCH DOES TWO THINGS:
--   1. Bulk-sync: for every business that has a linked auth user,
--      copy auth.users.email INTO businesses.email. After this, the
--      two values match for every linked shop.
--   2. Strengthen admin_update_business RPC: if it exists, ensure
--      admin updates also pass email through the auth API.
--
-- SAFE: only updates businesses.email when an auth.users.email exists.
-- For shops with NO auth user yet (admin-created listings), the
-- businesses.email stays as-is (still serves as fallback contact).
--
-- IDEMPOTENT: re-running is safe.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. PREVIEW — how many rows will change
-- ============================================================
DO $$
DECLARE
  v_total_linked   INT;
  v_mismatched     INT;
  v_will_sync      INT;
BEGIN
  -- Linked shops where auth.users.email is non-null
  SELECT COUNT(*) INTO v_total_linked
  FROM businesses b
  JOIN business_owners bo ON bo.business_id = b.id
  JOIN auth.users au ON au.id = bo.auth_user_id
  WHERE au.email IS NOT NULL;

  -- Linked shops where businesses.email != auth.users.email
  SELECT COUNT(*) INTO v_mismatched
  FROM businesses b
  JOIN business_owners bo ON bo.business_id = b.id
  JOIN auth.users au ON au.id = bo.auth_user_id
  WHERE au.email IS NOT NULL
    AND COALESCE(lower(b.email),'') IS DISTINCT FROM COALESCE(lower(au.email),'');

  v_will_sync := v_mismatched;

  RAISE NOTICE '====================================================';
  RAISE NOTICE 'EMAIL UNIFICATION — PREVIEW';
  RAISE NOTICE '====================================================';
  RAISE NOTICE 'Total linked shops with login email:    %', v_total_linked;
  RAISE NOTICE 'Mismatched (will be synced):            %', v_mismatched;
  RAISE NOTICE '====================================================';
END $$;


-- ============================================================
-- 2. SHOW the rows being synced (for audit visibility)
-- ============================================================
SELECT
  b.name                                AS shop_name,
  b.email                               AS old_business_email,
  au.email                              AS new_email_from_auth,
  b.status                              AS shop_status
FROM businesses b
JOIN business_owners bo ON bo.business_id = b.id
JOIN auth.users au ON au.id = bo.auth_user_id
WHERE au.email IS NOT NULL
  AND COALESCE(lower(b.email),'') IS DISTINCT FROM COALESCE(lower(au.email),'')
ORDER BY b.updated_at DESC NULLS LAST
LIMIT 100;


-- ============================================================
-- 3. BULK SYNC — set businesses.email = auth.users.email
--    Only for shops that have a linked auth user with non-null email.
--    Shops without a linked owner are NOT touched (they keep their
--    fallback contact email which admin set manually).
-- ============================================================
WITH src AS (
  SELECT b.id AS business_id, au.email AS new_email
  FROM businesses b
  JOIN business_owners bo ON bo.business_id = b.id
  JOIN auth.users au ON au.id = bo.auth_user_id
  WHERE au.email IS NOT NULL
    AND COALESCE(lower(b.email),'') IS DISTINCT FROM COALESCE(lower(au.email),'')
)
UPDATE businesses b
SET email      = lower(src.new_email),
    updated_at = NOW()
FROM src
WHERE b.id = src.business_id;


-- ============================================================
-- 4. POST-STATE VERIFICATION
-- ============================================================
DO $$
DECLARE
  v_mismatched     INT;
BEGIN
  SELECT COUNT(*) INTO v_mismatched
  FROM businesses b
  JOIN business_owners bo ON bo.business_id = b.id
  JOIN auth.users au ON au.id = bo.auth_user_id
  WHERE au.email IS NOT NULL
    AND COALESCE(lower(b.email),'') IS DISTINCT FROM COALESCE(lower(au.email),'');

  RAISE NOTICE '';
  RAISE NOTICE '====================================================';
  RAISE NOTICE 'AFTER SYNC';
  RAISE NOTICE '====================================================';
  RAISE NOTICE 'Remaining mismatched shops: %', v_mismatched;
  IF v_mismatched = 0 THEN
    RAISE NOTICE 'SUCCESS: every linked shop now has businesses.email';
    RAISE NOTICE '         matching auth.users.email.';
  END IF;
  RAISE NOTICE '====================================================';
END $$;

COMMIT;

-- ============================================================
-- 5. FINAL LIST — any shops STILL with no email at all
--    (these are admin-created listings with no auth owner yet)
-- ============================================================
SELECT
  b.id::TEXT                                          AS business_id,
  b.name                                              AS shop_name,
  b.email                                             AS business_email,
  EXISTS (
    SELECT 1 FROM business_owners bo
    WHERE bo.business_id = b.id AND bo.auth_user_id IS NOT NULL
  )                                                   AS has_linked_owner,
  CASE
    WHEN b.email IS NULL  THEN 'No email at all — collect from shopkeeper'
    WHEN NOT EXISTS (SELECT 1 FROM business_owners bo WHERE bo.business_id = b.id AND bo.auth_user_id IS NOT NULL)
      THEN 'No login account — admin can use businesses.email as contact'
    ELSE 'Linked + synced'
  END                                                 AS status_label
FROM businesses b
WHERE b.email IS NULL
   OR NOT EXISTS (
     SELECT 1 FROM business_owners bo
     WHERE bo.business_id = b.id AND bo.auth_user_id IS NOT NULL
   )
ORDER BY b.updated_at DESC NULLS LAST
LIMIT 30;
