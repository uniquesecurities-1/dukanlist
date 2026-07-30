-- =========================================================================
-- Migration 204: Add UPI ID column for Digital Card UPI QR feature (v48)
-- Created: 2026-07-30
--
-- FEATURE:
--   Owner can add UPI ID (e.g. deepak@paytm, 9876543210@ybl, name@okhdfcbank)
--   Public digital card auto-generates UPI QR that customer can scan to pay.
--   India-specific killer feature — global competitors (Popl, HiHello) can't
--   match this natively.
--
-- WHAT THIS DOES:
--   1. Adds businesses.upi_id (TEXT, nullable)
--   2. Updates update_my_business() RPC to handle upi_id field
--   3. Basic UPI validation (must contain @ and be non-empty)
--
-- SAFE TO RE-RUN.
-- =========================================================================

BEGIN;

-- Add upi_id column if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'businesses' AND column_name = 'upi_id'
  ) THEN
    ALTER TABLE public.businesses ADD COLUMN upi_id TEXT;
  END IF;
END $$;

-- Update RPC to handle upi_id field
DROP FUNCTION IF EXISTS update_my_business(JSONB);

CREATE OR REPLACE FUNCTION update_my_business(p_patch JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id        UUID := auth.uid();
  v_business_id    UUID;
  v_old            businesses%ROWTYPE;
  v_fields_updated TEXT[] := ARRAY[]::TEXT[];
  v_new_val        TEXT;
  v_old_val        TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'login required';
  END IF;

  SELECT bo.business_id INTO v_business_id
    FROM business_owners bo
   WHERE bo.auth_user_id = v_user_id
   LIMIT 1;

  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'no business linked to this account';
  END IF;

  SELECT * INTO v_old FROM businesses WHERE id = v_business_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'business not found';
  END IF;

  -- ===== v48: UPI ID (India-specific — for digital card UPI QR) =====
  IF p_patch ? 'upi_id' THEN
    v_new_val := NULLIF(trim(p_patch->>'upi_id'), '');
    -- Basic validation: must contain @ if non-empty
    IF v_new_val IS NOT NULL AND position('@' in v_new_val) = 0 THEN
      RAISE EXCEPTION 'UPI ID must contain @ (e.g. yourname@paytm)';
    END IF;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old.upi_id,'') THEN
      UPDATE businesses SET upi_id = v_new_val WHERE id = v_business_id;
      v_fields_updated := ARRAY_APPEND(v_fields_updated, 'upi_id');
    END IF;
  END IF;

  -- ===== WHATSAPP =====
  IF p_patch ? 'whatsapp' THEN
    v_new_val := NULLIF(trim(p_patch->>'whatsapp'), '');
    v_old_val := v_old.whatsapp;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old_val,'') THEN
      v_new_val := regexp_replace(v_new_val, '\D', '', 'g');
      IF v_new_val IS NOT NULL AND length(v_new_val) NOT IN (10, 12) THEN
        RAISE EXCEPTION 'WhatsApp number must be 10 digits';
      END IF;
      IF v_new_val IS NOT NULL AND length(v_new_val) = 12 THEN
        v_new_val := substring(v_new_val FROM 3);
      END IF;
      UPDATE businesses SET whatsapp = v_new_val WHERE id = v_business_id;
      v_fields_updated := ARRAY_APPEND(v_fields_updated, 'whatsapp');
    END IF;
  END IF;

  IF p_patch ? 'owner_name' THEN
    v_new_val := NULLIF(trim(p_patch->>'owner_name'), '');
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old.owner_name,'') THEN
      UPDATE businesses SET owner_name = v_new_val WHERE id = v_business_id;
      v_fields_updated := ARRAY_APPEND(v_fields_updated, 'owner_name');
    END IF;
  END IF;

  IF p_patch ? 'owner_role' THEN
    v_new_val := NULLIF(trim(p_patch->>'owner_role'), '');
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old.owner_role,'') THEN
      UPDATE businesses SET owner_role = v_new_val WHERE id = v_business_id;
      v_fields_updated := ARRAY_APPEND(v_fields_updated, 'owner_role');
    END IF;
  END IF;

  IF p_patch ? 'name_hi' THEN
    v_new_val := NULLIF(trim(p_patch->>'name_hi'), '');
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old.name_hi,'') THEN
      UPDATE businesses SET name_hi = v_new_val WHERE id = v_business_id;
      v_fields_updated := ARRAY_APPEND(v_fields_updated, 'name_hi');
    END IF;
  END IF;

  IF p_patch ? 'usp_text' THEN
    v_new_val := NULLIF(trim(p_patch->>'usp_text'), '');
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old.usp_text,'') THEN
      UPDATE businesses SET usp_text = v_new_val WHERE id = v_business_id;
      v_fields_updated := ARRAY_APPEND(v_fields_updated, 'usp_text');
    END IF;
  END IF;

  IF p_patch ? 'usp_hi' THEN
    v_new_val := NULLIF(trim(p_patch->>'usp_hi'), '');
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old.usp_hi,'') THEN
      UPDATE businesses SET usp_hi = v_new_val WHERE id = v_business_id;
      v_fields_updated := ARRAY_APPEND(v_fields_updated, 'usp_hi');
    END IF;
  END IF;

  IF p_patch ? 'about_text' THEN
    v_new_val := NULLIF(trim(p_patch->>'about_text'), '');
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old.about_text,'') THEN
      UPDATE businesses SET about_text = v_new_val WHERE id = v_business_id;
      v_fields_updated := ARRAY_APPEND(v_fields_updated, 'about_text');
    END IF;
  END IF;

  -- ===== v46: Website + Social Media URLs =====
  IF p_patch ? 'website_url' THEN
    v_new_val := NULLIF(trim(p_patch->>'website_url'), '');
    IF v_new_val IS NOT NULL AND v_new_val !~* '^https?://' THEN
      v_new_val := 'https://' || v_new_val;
    END IF;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old.website_url,'') THEN
      UPDATE businesses SET website_url = v_new_val WHERE id = v_business_id;
      v_fields_updated := ARRAY_APPEND(v_fields_updated, 'website_url');
    END IF;
  END IF;

  IF p_patch ? 'facebook_url' THEN
    v_new_val := NULLIF(trim(p_patch->>'facebook_url'), '');
    IF v_new_val IS NOT NULL AND v_new_val !~* '^https?://' THEN v_new_val := 'https://' || v_new_val; END IF;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old.facebook_url,'') THEN
      UPDATE businesses SET facebook_url = v_new_val WHERE id = v_business_id;
      v_fields_updated := ARRAY_APPEND(v_fields_updated, 'facebook_url');
    END IF;
  END IF;

  IF p_patch ? 'instagram_url' THEN
    v_new_val := NULLIF(trim(p_patch->>'instagram_url'), '');
    IF v_new_val IS NOT NULL AND v_new_val !~* '^https?://' THEN v_new_val := 'https://' || v_new_val; END IF;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old.instagram_url,'') THEN
      UPDATE businesses SET instagram_url = v_new_val WHERE id = v_business_id;
      v_fields_updated := ARRAY_APPEND(v_fields_updated, 'instagram_url');
    END IF;
  END IF;

  IF p_patch ? 'youtube_url' THEN
    v_new_val := NULLIF(trim(p_patch->>'youtube_url'), '');
    IF v_new_val IS NOT NULL AND v_new_val !~* '^https?://' THEN v_new_val := 'https://' || v_new_val; END IF;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old.youtube_url,'') THEN
      UPDATE businesses SET youtube_url = v_new_val WHERE id = v_business_id;
      v_fields_updated := ARRAY_APPEND(v_fields_updated, 'youtube_url');
    END IF;
  END IF;

  IF p_patch ? 'x_twitter_url' THEN
    v_new_val := NULLIF(trim(p_patch->>'x_twitter_url'), '');
    IF v_new_val IS NOT NULL AND v_new_val !~* '^https?://' THEN v_new_val := 'https://' || v_new_val; END IF;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old.x_twitter_url,'') THEN
      UPDATE businesses SET x_twitter_url = v_new_val WHERE id = v_business_id;
      v_fields_updated := ARRAY_APPEND(v_fields_updated, 'x_twitter_url');
    END IF;
  END IF;

  IF p_patch ? 'linkedin_url' THEN
    v_new_val := NULLIF(trim(p_patch->>'linkedin_url'), '');
    IF v_new_val IS NOT NULL AND v_new_val !~* '^https?://' THEN v_new_val := 'https://' || v_new_val; END IF;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old.linkedin_url,'') THEN
      UPDATE businesses SET linkedin_url = v_new_val WHERE id = v_business_id;
      v_fields_updated := ARRAY_APPEND(v_fields_updated, 'linkedin_url');
    END IF;
  END IF;

  IF p_patch ? 'video_url' THEN
    v_new_val := NULLIF(trim(p_patch->>'video_url'), '');
    IF v_new_val IS NOT NULL AND v_new_val !~* '^https?://' THEN v_new_val := 'https://' || v_new_val; END IF;
    IF COALESCE(v_new_val,'') IS DISTINCT FROM COALESCE(v_old.video_url,'') THEN
      UPDATE businesses SET video_url = v_new_val WHERE id = v_business_id;
      v_fields_updated := ARRAY_APPEND(v_fields_updated, 'video_url');
    END IF;
  END IF;

  -- ===== JSON + array fields =====
  IF p_patch ? 'hours_json' THEN
    UPDATE businesses SET hours_json = p_patch->'hours_json' WHERE id = v_business_id;
    v_fields_updated := ARRAY_APPEND(v_fields_updated, 'hours_json');
  END IF;

  IF p_patch ? 'services_json' THEN
    UPDATE businesses SET services_json = p_patch->'services_json' WHERE id = v_business_id;
    v_fields_updated := ARRAY_APPEND(v_fields_updated, 'services_json');
  END IF;

  IF p_patch ? 'faqs_json' THEN
    UPDATE businesses SET faqs_json = p_patch->'faqs_json' WHERE id = v_business_id;
    v_fields_updated := ARRAY_APPEND(v_fields_updated, 'faqs_json');
  END IF;

  IF p_patch ? 'established_year' THEN
    v_new_val := NULLIF(trim(p_patch->>'established_year'), '');
    IF v_new_val IS NULL THEN
      UPDATE businesses SET established_year = NULL WHERE id = v_business_id;
    ELSE
      UPDATE businesses SET established_year = v_new_val::INT WHERE id = v_business_id;
    END IF;
    v_fields_updated := ARRAY_APPEND(v_fields_updated, 'established_year');
  END IF;

  IF p_patch ? 'payment_methods' THEN
    UPDATE businesses SET payment_methods = ARRAY(SELECT jsonb_array_elements_text(p_patch->'payment_methods'))
      WHERE id = v_business_id;
    v_fields_updated := ARRAY_APPEND(v_fields_updated, 'payment_methods');
  END IF;

  IF p_patch ? 'special_features' THEN
    UPDATE businesses SET special_features = ARRAY(SELECT jsonb_array_elements_text(p_patch->'special_features'))
      WHERE id = v_business_id;
    v_fields_updated := ARRAY_APPEND(v_fields_updated, 'special_features');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'status', 'active',
    'fields_updated', to_jsonb(v_fields_updated),
    'pending_fields', to_jsonb(ARRAY[]::TEXT[]),
    'violations', '[]'::jsonb
  );
END;
$$;

GRANT EXECUTE ON FUNCTION update_my_business(JSONB) TO authenticated;

COMMIT;

-- =========================================================================
-- HOW TO RUN
-- =========================================================================
-- 1. Supabase Dashboard → SQL Editor
-- 2. Paste this entire file
-- 3. Click "Run"
-- 4. Expected: "Success. No rows returned"
-- =========================================================================
