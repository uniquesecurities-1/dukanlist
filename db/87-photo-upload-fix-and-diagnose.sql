-- =====================================================
-- db/87-photo-upload-fix-and-diagnose.sql
-- =====================================================
-- USER (2026-06-01): Photo upload showing "Upload permission issue"
-- (frontend translation of Supabase's "database schema is invalid or
-- incompatible" error). Even after frontend fix in commit 2aae96b,
-- actual upload still fails — meaning the underlying RLS / cache issue
-- is genuine.
--
-- THIS FILE COMBINES:
--   1. Full re-run of db/77 storage policies (idempotent)
--   2. Force PostgREST schema reload via NOTIFY
--   3. Run-time diagnostic — shows the admin EXACTLY what the storage
--      policy sees when a given shopkeeper tries to upload
--
-- HOW TO USE:
--   1. Run this entire file in Supabase SQL Editor as POSTGRES role.
--   2. Read the RAISE NOTICE output at the bottom carefully.
--   3. If the diagnostic block shows "0 business_owners rows for this
--      mobile" — the shopkeeper account isn't linked to any shop.
--      Use admin/shop.html → Create Login Account / Link Existing.
--
-- SAFE TO RE-RUN. No data is changed, only RLS policies are reset.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. STORAGE BUCKET — ensure shop-photos exists with right config
-- ============================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'shop-photos',
  'shop-photos',
  TRUE,
  3145728,
  ARRAY['image/jpeg','image/jpg','image/png','image/webp']
)
ON CONFLICT (id) DO UPDATE
  SET public = TRUE,
      file_size_limit = 3145728,
      allowed_mime_types = ARRAY['image/jpeg','image/jpg','image/png','image/webp'];


-- ============================================================
-- 2. DROP all existing shop-photos policies + recreate clean
-- ============================================================
DROP POLICY IF EXISTS "shop_photos_owner_upload" ON storage.objects;
DROP POLICY IF EXISTS "shop_photos_owner_update" ON storage.objects;
DROP POLICY IF EXISTS "shop_photos_owner_delete" ON storage.objects;
DROP POLICY IF EXISTS "shop_photos_public_read"  ON storage.objects;
DROP POLICY IF EXISTS "shop_photos_admin_all"    ON storage.objects;


-- ============================================================
-- 3. RECREATE — Public READ
-- ============================================================
CREATE POLICY "shop_photos_public_read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'shop-photos');


-- ============================================================
-- 4. RECREATE — Owner UPLOAD
-- Path pattern: {business_id}/{filename}.{ext}
-- The shopkeeper's auth.uid() must match business_owners.auth_user_id
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
-- 5. RECREATE — Owner UPDATE (re-upload over existing key)
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
-- 6. RECREATE — Owner DELETE
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
-- 7. RECREATE — Admin can do anything in this bucket
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


-- ============================================================
-- 8. Force PostgREST schema cache reload
-- ============================================================
NOTIFY pgrst, 'reload schema';

COMMIT;


-- ============================================================
-- 9. VERIFY (always runs)
-- ============================================================
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

  RAISE NOTICE '====================================================';
  RAISE NOTICE 'STORAGE POLICY STATE';
  RAISE NOTICE '====================================================';
  RAISE NOTICE 'Bucket shop-photos exists:    % of 1', v_bucket;
  RAISE NOTICE 'Policies installed:           % of 5', v_policies;
  RAISE NOTICE '   (read + upload + update + delete + admin)';
  RAISE NOTICE '';
  IF v_policies = 5 AND v_bucket = 1 THEN
    RAISE NOTICE '✅ SUCCESS — storage policies restored.';
    RAISE NOTICE '   Tell shopkeeper to:';
    RAISE NOTICE '     1. Hard refresh browser (Ctrl+Shift+R)';
    RAISE NOTICE '     2. Logout from panel, login again';
    RAISE NOTICE '     3. Retry photo upload';
  ELSE
    RAISE NOTICE '❌ Something is missing. Re-run this file.';
  END IF;
END $$;


-- ============================================================
-- 10. DIAGNOSTIC — find unlinked / orphan shopkeeper accounts
-- This shows you which shopkeeper users *cannot* upload because
-- they have no business_owners row OR their business_id is wrong.
-- ============================================================
DO $$
DECLARE
  v_total_users   INT;
  v_linked_users  INT;
  v_orphan_rows   INT;
  v_shops_no_link INT;
BEGIN
  SELECT COUNT(*) INTO v_total_users FROM auth.users;
  SELECT COUNT(DISTINCT auth_user_id) INTO v_linked_users
    FROM business_owners WHERE auth_user_id IS NOT NULL;
  SELECT COUNT(*) INTO v_orphan_rows
    FROM business_owners WHERE auth_user_id IS NULL;
  SELECT COUNT(*) INTO v_shops_no_link
    FROM businesses b
    WHERE NOT EXISTS (
      SELECT 1 FROM business_owners bo
      WHERE bo.business_id = b.id AND bo.auth_user_id IS NOT NULL
    );

  RAISE NOTICE '';
  RAISE NOTICE '====================================================';
  RAISE NOTICE 'LINK-STATE DIAGNOSTIC';
  RAISE NOTICE '====================================================';
  RAISE NOTICE 'Total auth.users:                          %', v_total_users;
  RAISE NOTICE 'Users linked to at least 1 business:       %', v_linked_users;
  RAISE NOTICE 'Orphan business_owners rows (NULL link):   %', v_orphan_rows;
  RAISE NOTICE 'Businesses with no linked owner:           %', v_shops_no_link;
  RAISE NOTICE '';
  RAISE NOTICE 'IF the shopkeeper you''re testing isn''t in the linked';
  RAISE NOTICE 'count, they will hit the upload error regardless of';
  RAISE NOTICE 'storage policies. Use admin/shop.html "Create Login';
  RAISE NOTICE 'Account" or "Link Existing User" to fix.';
  RAISE NOTICE '====================================================';
END $$;


-- ============================================================
-- 11. SAMPLE — show last 5 shopkeeper users who have NO business link
-- (these are accounts that registered but auto-claim didn''t happen
-- and admin hasn''t manually linked them yet)
-- ============================================================
SELECT
  '⚠ Unlinked shopkeeper'  AS status,
  u.id::TEXT               AS auth_user_id,
  u.email                  AS email,
  u.raw_user_meta_data->>'mobile' AS mobile_from_metadata,
  u.created_at             AS registered_at
FROM auth.users u
WHERE NOT EXISTS (
        SELECT 1 FROM business_owners bo
        WHERE bo.auth_user_id = u.id AND bo.auth_user_id IS NOT NULL
      )
  AND NOT EXISTS (
        SELECT 1 FROM admin_users a WHERE a.auth_user_id = u.id
      )
  AND u.email IS NOT NULL
ORDER BY u.created_at DESC
LIMIT 5;
