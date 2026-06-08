-- =====================================================
-- DIAGNOSE PHOTO UPLOAD FAILURE
-- =====================================================
-- Run this ONLY in Supabase SQL Editor.
-- It tells you EXACTLY which check is failing for which user.
--
-- HOW TO USE:
--   Just run as-is. Read the output tables top-down.
-- =====================================================


-- ============================================================
-- A. STORAGE BUCKET HEALTH
-- ============================================================
SELECT
  '🪣 BUCKET'                         AS check_type,
  id                                  AS bucket_id,
  public                              AS is_public,
  file_size_limit                     AS max_bytes,
  allowed_mime_types
FROM storage.buckets
WHERE id = 'shop-photos';


-- ============================================================
-- B. STORAGE RLS POLICIES — must be exactly 5
-- ============================================================
SELECT
  '🔒 POLICY'                         AS check_type,
  policyname,
  cmd                                 AS operation,
  LEFT(qual::text, 80)                AS using_clause_preview,
  LEFT(with_check::text, 80)          AS check_clause_preview
FROM pg_policies
WHERE tablename = 'objects'
  AND schemaname = 'storage'
  AND policyname LIKE 'shop_photos_%'
ORDER BY policyname;


-- ============================================================
-- C. EVERY UNLINKED VERIFIED USER + which shop they likely own
-- (matches by email and shows what's missing)
-- ============================================================
WITH unlinked AS (
  SELECT u.id, u.email, u.email_confirmed_at
  FROM auth.users u
  WHERE u.email IS NOT NULL
    AND u.email_confirmed_at IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM business_owners bo WHERE bo.auth_user_id = u.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM admin_users a WHERE a.auth_user_id = u.id
    )
)
SELECT
  '⚠ UNLINKED-VERIFIED'                 AS status,
  u.email                                AS auth_email,
  b.name                                 AS matching_shop_name,
  b.email                                AS shop_email,
  CASE
    WHEN b.id IS NULL THEN '❌ No shop has this email — manually link via /admin/verification.html'
    WHEN LOWER(b.email) = LOWER(u.email) THEN '✅ Email matches — db/122 should have linked this. Re-run db/122.'
    ELSE '⚠ Shop email differs — manual link needed'
  END                                    AS diagnosis
FROM unlinked u
LEFT JOIN businesses b ON LOWER(b.email) = LOWER(u.email::TEXT)
ORDER BY u.email_confirmed_at DESC
LIMIT 10;


-- ============================================================
-- D. ALL business_owners — current state of links
-- ============================================================
SELECT
  '👤 OWNER'                          AS check_type,
  bo.business_id,
  b.name                              AS shop_name,
  bo.auth_user_id,
  u.email                             AS owner_email,
  u.email_confirmed_at                AS email_verified,
  CASE
    WHEN bo.auth_user_id IS NULL THEN '❌ No auth link — photo upload BLOCKED'
    WHEN u.email_confirmed_at IS NULL THEN '⚠ Email not verified yet'
    ELSE '✅ Ready to upload'
  END                                 AS status
FROM business_owners bo
LEFT JOIN businesses b ON b.id = bo.business_id
LEFT JOIN auth.users u ON u.id = bo.auth_user_id
ORDER BY status, b.name
LIMIT 30;


-- ============================================================
-- E. SUMMARY COUNTS
-- ============================================================
DO $$
DECLARE
  v_total_biz    INT;
  v_with_owner   INT;
  v_with_auth    INT;
  v_uploadable   INT;
BEGIN
  SELECT COUNT(*) INTO v_total_biz FROM businesses WHERE status::TEXT = 'active';
  SELECT COUNT(DISTINCT bo.business_id) INTO v_with_owner FROM business_owners bo;
  SELECT COUNT(DISTINCT bo.business_id) INTO v_with_auth FROM business_owners bo WHERE bo.auth_user_id IS NOT NULL;
  SELECT COUNT(DISTINCT bo.business_id) INTO v_uploadable
    FROM business_owners bo
    JOIN auth.users u ON u.id = bo.auth_user_id
    WHERE u.email_confirmed_at IS NOT NULL;

  RAISE NOTICE '====================================================';
  RAISE NOTICE 'PHOTO UPLOAD READINESS';
  RAISE NOTICE '====================================================';
  RAISE NOTICE 'Active businesses:               %', v_total_biz;
  RAISE NOTICE 'Have a business_owners row:      %', v_with_owner;
  RAISE NOTICE 'Have auth_user_id linked:        %', v_with_auth;
  RAISE NOTICE 'Owner email is verified:         % ← these can upload', v_uploadable;
  RAISE NOTICE '====================================================';
END $$;
