-- =========================================================================
-- Migration 200: Restore Photos via Cloudinary CDN
-- Created: 2026-07-30
-- Author:  Deepak Singla / DigiMutual Goals Pvt. Ltd.
--
-- BACKGROUND:
--   Photos feature was hidden via CSS only (db/190 was NEVER RUN — data intact).
--   Now re-enabling with Cloudinary as the CDN instead of Supabase Storage
--   to preserve Supabase free tier bandwidth (5 GB/month) which would break
--   quickly with photo traffic.
--
-- WHAT THIS MIGRATION DOES:
--   1. Adds cloudinary_url, cloudinary_public_id, delete_token columns to
--      business_photos (if not already there)
--   2. Adds a trigger enforcing max 5 photos per shop
--   3. Adds RLS policy allowing shop owners to manage their own photos
--
-- CLOUDINARY CONFIG (frontend uses these — not stored in DB):
--   Cloud Name:     jqh6qwxr
--   Upload Preset:  dukanlist_shops (unsigned)
--   Folder:         businesses/
--
-- SAFE TO RE-RUN. Uses idempotent DO $$ blocks.
-- =========================================================================

BEGIN;

-- =========================================================================
-- STEP 1: Ensure business_photos table exists with proper structure
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.business_photos (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id   UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  uploaded_by   UUID REFERENCES auth.users(id),
  uploaded_at   TIMESTAMPTZ DEFAULT NOW(),
  is_featured   BOOLEAN DEFAULT false
);

-- =========================================================================
-- STEP 2: Add Cloudinary-specific columns (idempotent)
-- =========================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'business_photos' AND column_name = 'cloudinary_url'
  ) THEN
    ALTER TABLE public.business_photos ADD COLUMN cloudinary_url TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'business_photos' AND column_name = 'cloudinary_public_id'
  ) THEN
    ALTER TABLE public.business_photos ADD COLUMN cloudinary_public_id TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'business_photos' AND column_name = 'delete_token'
  ) THEN
    -- Cloudinary delete_token (browser can delete without API secret; expires in 10 min)
    ALTER TABLE public.business_photos ADD COLUMN delete_token TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'business_photos' AND column_name = 'uploaded_by'
  ) THEN
    ALTER TABLE public.business_photos ADD COLUMN uploaded_by UUID REFERENCES auth.users(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'business_photos' AND column_name = 'is_featured'
  ) THEN
    ALTER TABLE public.business_photos ADD COLUMN is_featured BOOLEAN DEFAULT false;
  END IF;
END $$;

-- Index for fast lookup by business
CREATE INDEX IF NOT EXISTS idx_business_photos_business_id
  ON public.business_photos(business_id);

-- =========================================================================
-- STEP 3: Enforce 5-photo limit per shop (DB-level trigger)
-- =========================================================================

CREATE OR REPLACE FUNCTION public.enforce_photo_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
    FROM public.business_photos
   WHERE business_id = NEW.business_id;

  IF v_count >= 5 THEN
    RAISE EXCEPTION 'Photo limit reached — maximum 5 photos per shop allowed'
      USING HINT = 'Delete an existing photo to upload a new one';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_photo_limit ON public.business_photos;
CREATE TRIGGER trg_enforce_photo_limit
  BEFORE INSERT ON public.business_photos
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_photo_limit();

-- =========================================================================
-- STEP 4: RLS policies — shop owners manage own photos, public reads all
-- =========================================================================

ALTER TABLE public.business_photos ENABLE ROW LEVEL SECURITY;

-- Public can READ all photos (needed for homepage / search / business page)
DROP POLICY IF EXISTS "public_read_photos" ON public.business_photos;
CREATE POLICY "public_read_photos"
  ON public.business_photos
  FOR SELECT
  USING (true);

-- Authenticated users can INSERT photos for businesses they own
DROP POLICY IF EXISTS "owner_insert_photos" ON public.business_photos;
CREATE POLICY "owner_insert_photos"
  ON public.business_photos
  FOR INSERT
  TO authenticated
  WITH CHECK (
    business_id IN (
      SELECT bo.business_id
        FROM public.business_owners bo
       WHERE bo.auth_user_id = auth.uid()
    )
  );

-- Owners can DELETE their own photos
DROP POLICY IF EXISTS "owner_delete_photos" ON public.business_photos;
CREATE POLICY "owner_delete_photos"
  ON public.business_photos
  FOR DELETE
  TO authenticated
  USING (
    business_id IN (
      SELECT bo.business_id
        FROM public.business_owners bo
       WHERE bo.auth_user_id = auth.uid()
    )
  );

-- Owners can UPDATE their own photos (e.g., mark as featured)
DROP POLICY IF EXISTS "owner_update_photos" ON public.business_photos;
CREATE POLICY "owner_update_photos"
  ON public.business_photos
  FOR UPDATE
  TO authenticated
  USING (
    business_id IN (
      SELECT bo.business_id
        FROM public.business_owners bo
       WHERE bo.auth_user_id = auth.uid()
    )
  );

-- Admins have full access
DROP POLICY IF EXISTS "admin_all_photos" ON public.business_photos;
CREATE POLICY "admin_all_photos"
  ON public.business_photos
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users WHERE auth_user_id = auth.uid()
    )
  );

COMMIT;

-- =========================================================================
-- HOW TO RUN
-- =========================================================================
-- 1. Supabase Dashboard → SQL Editor
-- 2. Paste this entire file
-- 3. Click "Run"
-- 4. Should see "Success. No rows returned"
--
-- VERIFY:
--   SELECT COUNT(*) FROM business_photos;
--   -- Should return current photo count (if any old data exists)
--
--   -- Test the trigger (this SHOULD fail for a shop that has 5 photos):
--   -- INSERT INTO business_photos (business_id, cloudinary_url)
--   -- VALUES ('some-shop-uuid', 'test');
-- =========================================================================
