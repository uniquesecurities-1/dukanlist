-- ============================================================
-- STORAGE BUCKET — shop-photos
-- Run on Supabase SQL Editor after creating project
-- ============================================================

-- Create public bucket via API call (Storage UI also works:
--   Storage → New bucket → Name: shop-photos → Public: ON
--   File size limit: 2 MB
--   Allowed MIME types: image/jpeg, image/png, image/webp)

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'shop-photos',
  'shop-photos',
  TRUE,
  2097152,  -- 2 MB
  ARRAY['image/jpeg','image/jpg','image/png','image/webp']
)
ON CONFLICT (id) DO UPDATE
  SET public = TRUE,
      file_size_limit = 2097152,
      allowed_mime_types = ARRAY['image/jpeg','image/jpg','image/png','image/webp'];

-- ============================================================
-- RLS POLICIES — shop-photos
-- ============================================================

-- Public can READ all photos (since bucket is public)
-- Default Supabase Storage RLS already handles this for public buckets

-- Authenticated users can INSERT photos in their own business folder
-- Path pattern: {business_id}/*
DROP POLICY IF EXISTS "shop_photos_owner_upload" ON storage.objects;
CREATE POLICY "shop_photos_owner_upload"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'shop-photos'
    AND (storage.foldername(name))[1]::UUID IN (
      SELECT business_id::TEXT::UUID
      FROM business_owners
      WHERE auth_user_id = auth.uid()
    )
  );

-- Owners can DELETE their own photos
DROP POLICY IF EXISTS "shop_photos_owner_delete" ON storage.objects;
CREATE POLICY "shop_photos_owner_delete"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'shop-photos'
    AND (storage.foldername(name))[1]::UUID IN (
      SELECT business_id::TEXT::UUID
      FROM business_owners
      WHERE auth_user_id = auth.uid()
    )
  );

NOTIFY pgrst, 'reload schema';
