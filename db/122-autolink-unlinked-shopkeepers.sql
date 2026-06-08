-- =====================================================
-- db/122-autolink-unlinked-shopkeepers.sql
-- =====================================================
-- USER (2026-06-08): db/87 storage policies are now installed,
-- but 5 shopkeepers (navneet.nivesheasy@gmail.com, mubasshir45,
-- shrikrishnastudio, subhash125104, issasidhu) still cannot
-- upload photos because they have NO business_owners row
-- linking them to a shop.
--
-- This file auto-links them by:
--   1. Matching auth.users.email → businesses.email
--   2. Updating existing business_owners row (if any) with auth_user_id
--   3. Or inserting a new business_owners row if missing
--
-- IDEMPOTENT — safe to re-run anytime. Only fills NULL or missing links.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. UPDATE existing business_owners rows (auth_user_id IS NULL)
--    that match a verified auth.user by email
-- ============================================================
WITH email_matches AS (
  SELECT
    bo.id            AS bo_id,
    u.id             AS auth_user_id
  FROM business_owners bo
  JOIN businesses b ON b.id = bo.business_id
  JOIN auth.users u ON LOWER(u.email::TEXT) = LOWER(b.email)
  WHERE bo.auth_user_id IS NULL
    AND u.email_confirmed_at IS NOT NULL
    AND NULLIF(b.email, '') IS NOT NULL
)
UPDATE business_owners bo
   SET auth_user_id = em.auth_user_id
  FROM email_matches em
 WHERE bo.id = em.bo_id;


-- ============================================================
-- 2. INSERT business_owners rows for users with NO link at all
--    (auth.users exists, business exists with same email, but
--    business_owners row doesn't exist yet)
-- ============================================================
INSERT INTO business_owners (business_id, auth_user_id, role, added_at)
SELECT
  b.id            AS business_id,
  u.id            AS auth_user_id,
  'owner'         AS role,
  NOW()           AS added_at
FROM businesses b
JOIN auth.users u ON LOWER(u.email::TEXT) = LOWER(b.email)
WHERE u.email_confirmed_at IS NOT NULL
  AND NULLIF(b.email, '') IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM business_owners bo
    WHERE bo.business_id = b.id
      AND bo.auth_user_id = u.id
  );


COMMIT;


-- ============================================================
-- 3. POST-RUN DIAGNOSTIC — show what was healed
-- ============================================================
DO $$
DECLARE
  v_total_users   INT;
  v_linked_users  INT;
  v_unlinked      INT;
BEGIN
  SELECT COUNT(*) INTO v_total_users FROM auth.users WHERE email_confirmed_at IS NOT NULL;
  SELECT COUNT(DISTINCT auth_user_id) INTO v_linked_users
    FROM business_owners WHERE auth_user_id IS NOT NULL;
  SELECT COUNT(*) INTO v_unlinked
    FROM auth.users u
    WHERE u.email_confirmed_at IS NOT NULL
      AND u.email IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM business_owners bo WHERE bo.auth_user_id = u.id
      )
      AND NOT EXISTS (
        SELECT 1 FROM admin_users a WHERE a.auth_user_id = u.id
      );

  RAISE NOTICE '====================================================';
  RAISE NOTICE 'AUTO-LINK COMPLETE';
  RAISE NOTICE '====================================================';
  RAISE NOTICE 'Verified auth users:              %', v_total_users;
  RAISE NOTICE 'Users linked to a business:       %', v_linked_users;
  RAISE NOTICE 'Still unlinked (need admin help): %', v_unlinked;
  RAISE NOTICE '';
  IF v_unlinked = 0 THEN
    RAISE NOTICE '✅ ALL users linked. Photo upload should work for everyone.';
  ELSE
    RAISE NOTICE '⚠ % users still unlinked — these are shops where', v_unlinked;
    RAISE NOTICE '   businesses.email does NOT match auth.users.email.';
    RAISE NOTICE '   Use admin/verification.html → Create Login or';
    RAISE NOTICE '   Link Existing User to fix manually.';
  END IF;
  RAISE NOTICE '====================================================';
END $$;


-- ============================================================
-- 4. SHOW WHICH USERS WERE LINKED IN THIS RUN
--    (for audit log)
-- ============================================================
SELECT
  '✅ Now linked'                              AS status,
  u.email                                       AS user_email,
  b.name                                        AS shop_name,
  b.id::TEXT                                    AS business_id,
  bo.added_at                                   AS linked_at
FROM business_owners bo
JOIN auth.users u ON u.id = bo.auth_user_id
JOIN businesses b ON b.id = bo.business_id
WHERE bo.added_at > NOW() - INTERVAL '2 minutes'
   OR (bo.auth_user_id IS NOT NULL AND bo.added_at IS NULL)
ORDER BY bo.added_at DESC NULLS LAST
LIMIT 20;
