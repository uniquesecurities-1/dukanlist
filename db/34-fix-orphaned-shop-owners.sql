-- =====================================================
-- db/34-fix-orphaned-shop-owners.sql
-- One-shot repair: link auth.users to their businesses
-- where the business_owners row was never created.
-- =====================================================
-- Scenario: shopkeeper registered → got "confirm email" → confirmed
-- on different device → logged in with NO localStorage carry-over →
-- claim_business_by_phone was never called.
--
-- This script:
--   1. Finds every auth user with metadata.mobile set
--   2. Finds matching active business with same mobile
--   3. Inserts the missing business_owners row (ON CONFLICT skip)
--
-- Safe to run multiple times. Reports affected count at end.
-- =====================================================

BEGIN;

WITH candidates AS (
  SELECT
    au.id                                    AS auth_user_id,
    au.raw_user_meta_data ->> 'mobile'       AS metadata_mobile,
    au.email,
    b.id                                     AS business_id,
    b.name                                   AS business_name
  FROM auth.users au
  JOIN businesses b
    ON b.mobile = au.raw_user_meta_data ->> 'mobile'
   AND b.status IN ('active','pending')
  WHERE au.raw_user_meta_data ->> 'mobile' IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM business_owners bo
       WHERE bo.auth_user_id = au.id
    )
)
INSERT INTO business_owners (business_id, auth_user_id, role)
SELECT business_id, auth_user_id, 'owner'
  FROM candidates
ON CONFLICT (business_id, auth_user_id) DO NOTHING;

-- Show what was linked (for diagnostic — visible in SQL results)
SELECT
  au.email,
  au.raw_user_meta_data ->> 'mobile' AS mobile,
  b.id  AS business_id,
  b.name AS business_name,
  bo.role,
  bo.created_at
FROM business_owners bo
JOIN auth.users au ON au.id = bo.auth_user_id
JOIN businesses  b  ON b.id  = bo.business_id
WHERE bo.created_at > NOW() - INTERVAL '1 hour'
ORDER BY bo.created_at DESC;

COMMIT;
