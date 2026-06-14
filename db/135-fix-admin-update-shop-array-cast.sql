-- ============================================================
-- db/135 — Fix admin_update_shop array-column handling
-- ============================================================
-- BUG (introduced/inherited in db/129):
--   For array columns (photos, payment_methods, special_features) the RPC
--   uses this dynamic SQL:
--
--     UPDATE businesses SET %I = ($1->>%L)::text::TEXT[] WHERE id = $2
--
--   The expression `$1->>'payment_methods'` returns the JSON value AS TEXT.
--   For a JSON array ["cash","credit"] that text is literally:
--
--     ["cash","credit"]
--
--   Casting that string to PostgreSQL TEXT[] fails because PG array
--   literals use {...} not [...]:
--
--     ERROR 22P02: malformed array literal: "["cash", "credit"]"
--     DETAIL: "[" must introduce explicitly-specified array dimensions.
--
--   Effect: any admin save that included payment_methods or
--   special_features (Shop Trust Signals fieldset) returned 400 from
--   the RPC. The client's dual-path save (admin/shop.html applyPatch)
--   masked the failure with a direct UPDATE fallback, so the data did
--   land — but every save spammed a 400 in the console.
--
-- FIX:
--   For array columns, build the PostgreSQL array properly from the
--   JSONB value:
--
--     SET payment_methods = ARRAY(SELECT jsonb_array_elements_text($1->'payment_methods'))
--
--   Note: -> (returns JSONB) NOT ->> (returns TEXT). Then jsonb_array_elements_text
--   unpacks each element into a TEXT row, and ARRAY() collects them into TEXT[].
--   Handles empty arrays, NULLs, and any element count correctly.
--
-- IDEMPOTENT: CREATE OR REPLACE. Existing grants preserved by re-grant.
-- DB never disturbed — forward-only migration, no schema change.
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
    -- From db/68: trust-signal fields
    'payment_methods','special_features','established_year',
    -- From db/129: location reassignment
    'city_id','locality_id'
  ];
  v_array_cols TEXT[] := ARRAY['photos','payment_methods','special_features'];
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  v_admin_id := auth.uid();

  FOR v_key IN SELECT jsonb_object_keys(p_patch)
  LOOP
    IF v_key = ANY(v_allowed) THEN
      IF v_key = ANY(v_array_cols) THEN
        -- ARRAY COLUMNS: unpack JSON array → PG array via jsonb_array_elements_text.
        -- Handles ["a","b"] correctly (which simple ::text::TEXT[] cannot).
        -- If the JSON value is null, ARRAY(SELECT ...) returns an empty array;
        -- to allow explicit NULL clearing, we check first.
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
        -- SCALAR COLUMNS: original logic with type-specific cast.
        EXECUTE format('UPDATE businesses SET %I = ($1->>%L)::text::%s WHERE id = $2',
                       v_key, v_key,
                       CASE
                         -- Integer columns
                         WHEN v_key IN ('category_id','sub_category_id','city_id','locality_id','established_year') THEN 'INTEGER'
                         -- Boolean columns
                         WHEN v_key LIKE 'verified_%' OR v_key = 'featured' THEN 'BOOLEAN'
                         -- JSONB columns
                         WHEN v_key LIKE '%_json' THEN 'JSONB'
                         ELSE 'TEXT'
                       END)
          USING p_patch, p_business_id;
      END IF;
      v_changed := v_changed || jsonb_build_array(v_key);
    END IF;
  END LOOP;

  -- Touch updated_at
  UPDATE businesses SET updated_at = NOW() WHERE id = p_business_id;

  RETURN jsonb_build_object('updated_fields', v_changed);
END $$;

GRANT EXECUTE ON FUNCTION admin_update_shop(UUID, JSONB) TO authenticated;

NOTIFY pgrst, 'reload schema';

DO $$
BEGIN
  RAISE NOTICE '✓ db/135 — admin_update_shop array handling fixed (payment_methods, special_features, photos)';
END $$;

COMMIT;
