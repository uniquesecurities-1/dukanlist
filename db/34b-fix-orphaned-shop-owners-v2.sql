-- =====================================================
-- db/34b-fix-orphaned-shop-owners-v2.sql
-- Safer version — uses NOT EXISTS instead of ON CONFLICT
-- (some Postgres setups don't expose composite PK as a
-- usable conflict target for ON CONFLICT.)
-- =====================================================
BEGIN;

INSERT INTO business_owners (business_id, auth_user_id, role)
SELECT b.id, au.id, 'owner'
FROM auth.users au
JOIN businesses b
  ON b.mobile = au.raw_user_meta_data ->> 'mobile'
 AND b.status IN ('active','pending')
WHERE au.raw_user_meta_data ->> 'mobile' IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM business_owners bo
     WHERE bo.business_id  = b.id
       AND bo.auth_user_id = au.id
  );

-- Show what got linked (most recent first)
SELECT
  au.email,
  au.raw_user_meta_data ->> 'mobile' AS mobile,
  b.id   AS business_id,
  b.name AS business_name,
  bo.role,
  bo.added_at
FROM business_owners bo
JOIN auth.users au ON au.id = bo.auth_user_id
JOIN businesses  b  ON b.id  = bo.business_id
ORDER BY bo.added_at DESC
LIMIT 10;

COMMIT;
