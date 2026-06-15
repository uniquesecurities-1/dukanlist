-- ============================================================
-- db/155 — Alternative mobile (alt_mobile) wiring
-- ============================================================
-- The businesses table already has an `alt_mobile TEXT` column (from
-- db/01-schema.sql) — owners often have a second number (spouse's,
-- shop landline, backup mobile) that customers can reach them on if
-- the primary doesn't pick up. But the column has never been wired
-- into any UI or RPC.
--
-- This migration does two things:
--   1. Adds a dedicated owner-side RPC `update_my_alt_mobile` so the
--      owner can set/clear their alt number from panel/profile.html
--      without touching the heavy update_my_business validation flow.
--   2. Extends admin_update_shop's whitelist with 'alt_mobile' so the
--      admin shop-detail editor can update it too.
--
-- Validation:
--   - Owner-side RPC accepts 10-digit Indian mobile OR empty/NULL to clear.
--   - Normalises to bare 10-digit form (strips +91, spaces, dashes).
--   - Rejects if same as primary mobile (defensive — would be confusing).
--
-- SAFE: All CREATE OR REPLACE. No schema changes (column already exists).
-- ============================================================

BEGIN;

-- ============================================================
-- Part 1: Owner-side RPC for alt_mobile
-- ============================================================
CREATE OR REPLACE FUNCTION update_my_alt_mobile(p_alt_mobile TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id      UUID := auth.uid();
  v_business_id  UUID;
  v_primary_mob  TEXT;
  v_normalised   TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  -- Find the caller's business via owner link (handles multi-owner setups)
  SELECT business_id INTO v_business_id
  FROM business_owners
  WHERE auth_user_id = v_user_id
  LIMIT 1;

  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'No business linked to your account';
  END IF;

  -- Normalise input — strip everything non-digit, then take last 10 digits
  v_normalised := regexp_replace(COALESCE(p_alt_mobile, ''), '\D', '', 'g');
  IF LENGTH(v_normalised) > 10 THEN
    v_normalised := RIGHT(v_normalised, 10);
  END IF;

  -- Empty input → clear the field (caller wants to remove the alt number)
  IF v_normalised = '' THEN
    UPDATE businesses
    SET alt_mobile = NULL,
        updated_at = NOW()
    WHERE id = v_business_id;

    RETURN jsonb_build_object('success', TRUE, 'alt_mobile', NULL, 'cleared', TRUE);
  END IF;

  -- Must be exactly 10 digits and start with 6/7/8/9 (Indian mobile)
  IF LENGTH(v_normalised) <> 10 THEN
    RAISE EXCEPTION 'Alternative mobile must be a 10-digit Indian number';
  END IF;
  IF substring(v_normalised, 1, 1) NOT IN ('6','7','8','9') THEN
    RAISE EXCEPTION 'Alternative mobile must start with 6, 7, 8, or 9';
  END IF;

  -- Prevent same as primary mobile (would be confusing to display)
  SELECT mobile INTO v_primary_mob
  FROM businesses
  WHERE id = v_business_id;

  IF RIGHT(regexp_replace(COALESCE(v_primary_mob,''), '\D', '', 'g'), 10) = v_normalised THEN
    RAISE EXCEPTION 'Alternative mobile cannot be the same as your primary mobile';
  END IF;

  UPDATE businesses
  SET alt_mobile = v_normalised,
      updated_at = NOW()
  WHERE id = v_business_id;

  RETURN jsonb_build_object('success', TRUE, 'alt_mobile', v_normalised);
END;
$$;

GRANT EXECUTE ON FUNCTION update_my_alt_mobile(TEXT) TO authenticated;

-- ============================================================
-- Part 2: Add alt_mobile to admin_update_shop whitelist
-- ============================================================
-- Re-create admin_update_shop from db/150 baseline with 'alt_mobile'
-- and 'email' appended to v_allowed. Body is otherwise identical to
-- db/150 so all professional-field handling is preserved.
CREATE OR REPLACE FUNCTION admin_update_shop(p_business_id UUID, p_patch JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id  UUID;
  v_changed   JSONB := '[]'::jsonb;
  v_key       TEXT;
  v_allowed   TEXT[] := ARRAY[
    'name','usp_text','usp_hi','about_text',
    'mobile','whatsapp','owner_name',
    'category_id','sub_category_id',
    'address_line1','address_line2','pincode',
    'hours_json','services_json',
    'photos','video_url',
    'verified_mobile','verified_address','verified_photo','verified_visit',
    'featured','admin_notes',
    'status',
    'payment_methods','special_features','established_year',
    'city_id','locality_id',
    -- db/150 — professional fields
    'is_professional_listing','professional_tier',
    'membership_no','membership_authority','professional_qualification',
    'practice_areas','prof_verification_notes',
    -- db/155 — alternative contact
    'alt_mobile','email'
  ];
  v_array_cols TEXT[] := ARRAY['photos','payment_methods','special_features','practice_areas'];
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  v_admin_id := auth.uid();

  FOR v_key IN SELECT jsonb_object_keys(p_patch)
  LOOP
    IF v_key = ANY(v_allowed) THEN
      IF v_key = ANY(v_array_cols) THEN
        IF p_patch->v_key IS NULL OR jsonb_typeof(p_patch->v_key) = 'null' THEN
          EXECUTE format('UPDATE businesses SET %I = NULL WHERE id = $1', v_key)
            USING p_business_id;
        ELSE
          EXECUTE format(
            'UPDATE businesses SET %I = ARRAY(SELECT jsonb_array_elements_text($1->%L)) WHERE id = $2',
            v_key, v_key
          ) USING p_patch, p_business_id;
        END IF;
      ELSE
        EXECUTE format('UPDATE businesses SET %I = ($1->>%L)::text::%s WHERE id = $2',
                       v_key, v_key,
                       CASE
                         WHEN v_key IN ('category_id','sub_category_id','city_id','locality_id','established_year') THEN 'INTEGER'
                         WHEN v_key LIKE 'verified_%' OR v_key = 'featured' OR v_key = 'is_professional_listing' THEN 'BOOLEAN'
                         WHEN v_key LIKE '%_json' THEN 'JSONB'
                         ELSE 'TEXT'
                       END)
          USING p_patch, p_business_id;
      END IF;
      v_changed := v_changed || jsonb_build_array(v_key);
    END IF;
  END LOOP;

  UPDATE businesses SET updated_at = NOW() WHERE id = p_business_id;

  RETURN jsonb_build_object('updated_fields', v_changed);
END $$;

GRANT EXECUTE ON FUNCTION admin_update_shop(UUID, JSONB) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/155 installed. alt_mobile editable by owner (RPC) + admin (whitelist).';
END $$;
