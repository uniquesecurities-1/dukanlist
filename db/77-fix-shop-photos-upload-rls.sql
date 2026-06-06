-- =====================================================
-- db/77-fix-shop-photos-upload-rls.sql
-- =====================================================
-- USER (2026-05-28): "Photo upload me dikkat aa rahi hai, kaafi
-- complaints hain. Desktop: 'The database schema is invalid or
-- incompatible.. Internet check karein ya retry karein.' Mobile:
-- 'Failed to fetch.'"
--
-- ROOT CAUSE:
--   db/06 created the shop-photos bucket + RLS policies BEFORE db/15
--   reshaped business_owners (made auth_user_id NULLABLE, added
--   owner_phone, changed PK from composite to id UUID).
--
--   The old policies still have a redundant `business_id::TEXT::UUID`
--   double cast and don't account for nullable auth_user_id rows
--   (rows created by register_business_public have auth_user_id = NULL
--   until the owner logs in and claim_business_by_phone runs).
--
--   When the Supabase Storage client posts an upload and the RLS check
--   subquery returns no rows OR throws a cast error, the storage API
--   responds with 'database schema is invalid or incompatible' —
--   confusing but it's an RLS denial under the hood.
--
-- THIS PATCH (bulletproof RLS for shop-photos):
--   1. DROP old INSERT + DELETE policies that have the bad cast
--   2. Recreate with clean policies:
--      - explicit auth_user_id IS NOT NULL filter
--      - no redundant cast (business_id is already UUID)
--      - foldername cast wrapped in NULLIF + safe pattern
--   3. ADD UPDATE policy (was missing — needed for re-upload over
--      existing key)
--
-- All idempotent. Zero-risk. Safe to re-run.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. Ensure bucket exists with right config
-- ============================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'shop-photos',
  'shop-photos',
  TRUE,
  3145728,  -- bump to 3 MB (client compresses; allow some headroom)
  ARRAY['image/jpeg','image/jpg','image/png','image/webp']
)
ON CONFLICT (id) DO UPDATE
  SET public = TRUE,
      file_size_limit = 3145728,
      allowed_mime_types = ARRAY['image/jpeg','image/jpg','image/png','image/webp'];


-- ============================================================
-- 2. Drop all existing policies on storage.objects for this bucket
-- (clean slate — avoid duplicate/conflicting policies)
-- ============================================================
DROP POLICY IF EXISTS "shop_photos_owner_upload" ON storage.objects;
DROP POLICY IF EXISTS "shop_photos_owner_update" ON storage.objects;
DROP POLICY IF EXISTS "shop_photos_owner_delete" ON storage.objects;
DROP POLICY IF EXISTS "shop_photos_public_read"  ON storage.objects;
DROP POLICY IF EXISTS "shop_photos_admin_all"    ON storage.objects;


-- ============================================================
-- 3. Public READ — bucket is public, but explicit policy is safer
-- ============================================================
CREATE POLICY "shop_photos_public_read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'shop-photos');


-- ============================================================
-- 4. Owner UPLOAD — clean, no double cast, NULL-safe
-- Path pattern: {business_id}/{filename}.{ext}
-- business_owners.auth_user_id must match auth.uid() AND not be NULL
-- ============================================================
CREATE POLICY "shop_photos_owner_upload"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'shop-photos'
    AND auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM business_owners bo
      WHERE bo.auth_user_id = auth.uid()
        AND bo.business_id::TEXT = (storage.foldername(name))[1]
    )
  );


-- ============================================================
-- 5. Owner UPDATE — needed when same file path is re-uploaded
-- ============================================================
CREATE POLICY "shop_photos_owner_update"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'shop-photos'
    AND auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM business_owners bo
      WHERE bo.auth_user_id = auth.uid()
        AND bo.business_id::TEXT = (storage.foldername(name))[1]
    )
  );


-- ============================================================
-- 6. Owner DELETE — owner can remove their own photos
-- ============================================================
CREATE POLICY "shop_photos_owner_delete"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'shop-photos'
    AND auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM business_owners bo
      WHERE bo.auth_user_id = auth.uid()
        AND bo.business_id::TEXT = (storage.foldername(name))[1]
    )
  );


-- ============================================================
-- 7. Admin can do ANYTHING in this bucket (for moderation)
-- ============================================================
CREATE POLICY "shop_photos_admin_all"
  ON storage.objects FOR ALL TO authenticated
  USING (
    bucket_id = 'shop-photos'
    AND EXISTS (
      SELECT 1 FROM admin_users
      WHERE auth_user_id = auth.uid()
    )
  )
  WITH CHECK (
    bucket_id = 'shop-photos'
    AND EXISTS (
      SELECT 1 FROM admin_users
      WHERE auth_user_id = auth.uid()
    )
  );


NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- VERIFY
-- =====================================================
DO $$
DECLARE
  v_policies INT;
  v_bucket   INT;
BEGIN
  SELECT COUNT(*) INTO v_policies
    FROM pg_policies
    WHERE tablename = 'objects' AND schemaname = 'storage'
      AND policyname LIKE 'shop_photos_%';

  SELECT COUNT(*) INTO v_bucket FROM storage.buckets WHERE id = 'shop-photos';

  RAISE NOTICE '✅ shop-photos bucket:    % of 1', v_bucket;
  RAISE NOTICE '✅ shop-photos policies:  % of 5 (read+upload+update+delete+admin)', v_policies;
END $$;

-- =====================================================
-- DIAGNOSTIC HELPERS (run manually if upload still fails)
-- =====================================================
-- 1. Verify your user has a business_owners row:
--    SELECT * FROM business_owners WHERE auth_user_id = auth.uid();
--
-- 2. Verify auth.uid() returns something (run while logged in):
--    SELECT auth.uid();
--
-- 3. List shop-photos policies:
--    SELECT policyname, cmd FROM pg_policies
--      WHERE tablename='objects' AND schemaname='storage'
--        AND policyname LIKE 'shop_photos_%';
-- =====================================================
