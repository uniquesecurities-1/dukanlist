-- ============================================================
-- db/150 — Extend admin_update_shop whitelist with professional fields
-- ============================================================
-- After db/145 added professional columns to the businesses table, the
-- existing admin RPCs cannot see or edit them:
--
-- - admin_update_shop's v_allowed array silently skips any field name
--   not in the whitelist. So an admin trying to fix a typo'd ICAI
--   number got no error AND no save — confusing UX.
--
-- - admin_get_shop_full doesn't return the 10 new columns, so the
--   admin shop-detail UI literally cannot DISPLAY them either.
--
-- This migration extends both. Verification-only fields (prof_verified_at,
-- prof_verified_by) are NOT included in v_allowed — they should only be
-- written by admin_verify_professional (db/148) to maintain audit trail.
-- prof_verification_notes IS allowed since admin may edit notes after-fact.
--
-- SAFE: CREATE OR REPLACE. Idempotent. DB never disturbed.
-- ============================================================

BEGIN;

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
    -- ====== Added by db/150: professional-listing fields ======
    -- Admin-editable so admin can correct typos in membership numbers,
    -- adjust qualification labels, fix tier classification, add/remove
    -- practice areas, or override the auto-flag. Verification-only
    -- fields (prof_verified_at, prof_verified_by) stay restricted to
    -- the admin_verify_professional RPC so the audit trail is preserved.
    'is_professional_listing','professional_tier',
    'membership_no','membership_authority','professional_qualification',
    'practice_areas','prof_verification_notes'
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


-- ============================================================
-- admin_get_shop_full — add professional fields to JSONB output
-- ============================================================
-- We can't just patch the existing function — it's already at the 100-arg
-- jsonb_build_object limit (db/86 split it into two halves). The cleanest
-- additive fix: add a THIRD jsonb_build_object call appended via ||.
-- This avoids re-stating the entire function body.
--
-- Strategy: create a wrapper RPC admin_get_shop_full_extras that returns
-- just the pro fields, and modify admin/shop.html to call it alongside
-- the main RPC. That's less invasive than re-writing the 150-line main.

CREATE OR REPLACE FUNCTION admin_get_shop_pro_fields(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_email TEXT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  RETURN (
    SELECT jsonb_build_object(
      'is_professional_listing',    COALESCE(b.is_professional_listing, FALSE),
      'professional_tier',          b.professional_tier,
      'membership_no',              b.membership_no,
      'membership_authority',       b.membership_authority,
      'professional_qualification', b.professional_qualification,
      'practice_areas',             COALESCE(b.practice_areas, '{}'),
      'disclaimer_accepted_at',     b.disclaimer_accepted_at,
      'prof_verified_at',           b.prof_verified_at,
      'prof_verified_by',           b.prof_verified_by,
      'prof_verified_by_email',     v_admin_email,
      'prof_verification_notes',    b.prof_verification_notes
    )
    FROM businesses b
    WHERE b.id = p_business_id
  );
END $$;

GRANT EXECUTE ON FUNCTION admin_get_shop_pro_fields(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/150 installed.';
  RAISE NOTICE '  admin_update_shop now accepts 7 new pro fields in patch.';
  RAISE NOTICE '  admin_get_shop_pro_fields() returns the 11 pro columns for UI.';
END $$;
