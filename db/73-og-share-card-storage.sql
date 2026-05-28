-- =====================================================
-- db/73-og-share-card-storage.sql
-- =====================================================
-- USER FEEDBACK (2026-05-28):
--   "Jab hum kisi ki profile share karte hai to DukanList ki bhaari branding
--    nazar aati hai. Isse jyada sharing nahi hogi. Shopkeeper ki branding
--    chahiye, jyada se jyada sharing ho. Platform to apna hi hoga."
--
-- WHY THIS IS NEEDED:
--   Current /api/share endpoint uses /assets/og-default.png as fallback
--   when a shop has no photos. That image is HEAVY DukanList branding —
--   the shop being shared has zero visual presence. Shopkeepers feel
--   they're advertising DukanList, not their own dukan, so sharing stops.
--
-- FIX ARCHITECTURE:
--   • assets/js/og-card-generator.js generates a beautiful shop-branded
--     1200×630 PNG card client-side using HTML5 Canvas (zero serverless cost).
--   • Card shows HUGE shop name, ⭐ rating, 📍 city, 📞 mobile, owner name,
--     USP text. DukanList footer only ~5% area.
--   • Generated at shop save (register.html + panel/profile.html)
--     and uploaded to NEW Supabase Storage bucket 'business-og'.
--   • New column businesses.og_image_url stores the public URL.
--   • api/share.js picks og_image_url first, then first photo, then default.
--
-- THIS MIGRATION (zero risk, additive):
--   1. Add businesses.og_image_url TEXT column
--   2. Create public 'business-og' storage bucket (PNG, ~150 KB limit)
--   3. RLS: owner can upload/replace their own shop's OG card
--   4. RLS: admins can upload/replace any shop's OG card (for backfill)
--   5. Public read (bucket already public)
-- =====================================================

BEGIN;

-- ============================================================
-- 1. COLUMN — businesses.og_image_url
-- ============================================================
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS og_image_url TEXT;

COMMENT ON COLUMN businesses.og_image_url IS
  'Public URL of shop-branded OG share card (generated client-side on save). '
  'Used by /api/share to render WhatsApp/social link previews where the shop '
  'name is the hero and DukanList is subtle.';


-- ============================================================
-- 2. STORAGE BUCKET — business-og (public, ~150 KB PNG/JPEG)
-- ============================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'business-og',
  'business-og',
  TRUE,
  300000,  -- 300 KB (cards are ~80-150 KB usually)
  ARRAY['image/png','image/jpeg','image/webp']
)
ON CONFLICT (id) DO UPDATE
  SET public = TRUE,
      file_size_limit = 300000,
      allowed_mime_types = ARRAY['image/png','image/jpeg','image/webp'];


-- ============================================================
-- 3. RLS — owner upload + replace
-- ============================================================
-- Path pattern: {business_id}/og.png
-- Owner of the business can INSERT or UPDATE their own card.

DROP POLICY IF EXISTS "business_og_owner_upload" ON storage.objects;
CREATE POLICY "business_og_owner_upload"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'business-og'
    AND (storage.foldername(name))[1]::UUID IN (
      SELECT business_id FROM business_owners
      WHERE auth_user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "business_og_owner_update" ON storage.objects;
CREATE POLICY "business_og_owner_update"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'business-og'
    AND (storage.foldername(name))[1]::UUID IN (
      SELECT business_id FROM business_owners
      WHERE auth_user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "business_og_owner_delete" ON storage.objects;
CREATE POLICY "business_og_owner_delete"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'business-og'
    AND (storage.foldername(name))[1]::UUID IN (
      SELECT business_id FROM business_owners
      WHERE auth_user_id = auth.uid()
    )
  );


-- ============================================================
-- 4. RLS — admin can upload/replace any shop's card (for backfill)
-- ============================================================
DROP POLICY IF EXISTS "business_og_admin_all" ON storage.objects;
CREATE POLICY "business_og_admin_all"
  ON storage.objects FOR ALL TO authenticated
  USING (
    bucket_id = 'business-og'
    AND EXISTS (
      SELECT 1 FROM admin_users
      WHERE auth_user_id = auth.uid()
    )
  )
  WITH CHECK (
    bucket_id = 'business-og'
    AND EXISTS (
      SELECT 1 FROM admin_users
      WHERE auth_user_id = auth.uid()
    )
  );


-- ============================================================
-- 5. RPC — owner updates their own og_image_url
-- Used by client after upload completes.
-- ============================================================
DROP FUNCTION IF EXISTS update_my_og_image(TEXT);

CREATE OR REPLACE FUNCTION update_my_og_image(p_og_url TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_biz_id  UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT business_id INTO v_biz_id
  FROM business_owners
  WHERE auth_user_id = v_user_id
  LIMIT 1;

  IF v_biz_id IS NULL THEN
    RAISE EXCEPTION 'No business linked to this account';
  END IF;

  -- Basic sanity: must be HTTPS URL on supabase domain (prevent abuse)
  IF p_og_url IS NULL OR p_og_url = '' THEN
    UPDATE businesses SET og_image_url = NULL WHERE id = v_biz_id;
  ELSIF p_og_url !~* '^https://[a-z0-9.-]+\.supabase\.co/storage/' THEN
    RAISE EXCEPTION 'og_image_url must be a Supabase Storage URL';
  ELSE
    UPDATE businesses SET og_image_url = p_og_url WHERE id = v_biz_id;
  END IF;

  RETURN v_biz_id;
END;
$$;

GRANT EXECUTE ON FUNCTION update_my_og_image(TEXT) TO authenticated;


-- ============================================================
-- 6. ADMIN RPC — admin can set og_image_url for any business
-- ============================================================
DROP FUNCTION IF EXISTS admin_set_og_image(UUID, TEXT);

CREATE OR REPLACE FUNCTION admin_set_og_image(p_business_id UUID, p_og_url TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  IF p_og_url IS NULL OR p_og_url = '' THEN
    UPDATE businesses SET og_image_url = NULL WHERE id = p_business_id;
  ELSIF p_og_url !~* '^https://[a-z0-9.-]+\.supabase\.co/storage/' THEN
    RAISE EXCEPTION 'og_image_url must be a Supabase Storage URL';
  ELSE
    UPDATE businesses SET og_image_url = p_og_url WHERE id = p_business_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_set_og_image(UUID, TEXT) TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- VERIFY
-- =====================================================
DO $$
DECLARE
  v_col      INT;
  v_bucket   INT;
  v_rpc_user INT;
  v_rpc_adm  INT;
BEGIN
  SELECT COUNT(*) INTO v_col FROM information_schema.columns
    WHERE table_name='businesses' AND column_name='og_image_url';
  SELECT COUNT(*) INTO v_bucket FROM storage.buckets WHERE id='business-og';
  SELECT COUNT(*) INTO v_rpc_user FROM pg_proc WHERE proname='update_my_og_image';
  SELECT COUNT(*) INTO v_rpc_adm  FROM pg_proc WHERE proname='admin_set_og_image';

  RAISE NOTICE '✅ Column og_image_url: % of 1', v_col;
  RAISE NOTICE '✅ Bucket business-og: % of 1', v_bucket;
  RAISE NOTICE '✅ RPC update_my_og_image: % of 1', v_rpc_user;
  RAISE NOTICE '✅ RPC admin_set_og_image: % of 1', v_rpc_adm;
END $$;
