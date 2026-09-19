-- ============================================================
-- db/215 — admin_pre_list_shop: accept the owner's email
-- ============================================================
-- Quick Add could capture only name + mobile, so every pre-listed
-- shop then needed a second trip through Owner Invites to collect
-- an email. This adds an optional p_email that is written to
-- businesses.email at creation time, so the admin can pre-list AND
-- fire the verification/claim invite in one pass.
--
-- Implemented as a WRAPPER: the existing 9-arg function (db/165)
-- is untouched and still does all the work, so nothing that calls
-- the old signature breaks.
--
-- SAFE: additive, idempotent, re-runnable.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_pre_list_shop(
  p_name                   TEXT,
  p_mobile                 TEXT,
  p_area                   TEXT     DEFAULT NULL,
  p_category_slugs         TEXT[]   DEFAULT NULL,
  p_primary_category_slug  TEXT     DEFAULT NULL,
  p_city_id                INT      DEFAULT NULL,
  p_source                 TEXT     DEFAULT 'manual',
  p_consent_method         TEXT     DEFAULT 'verbal',
  p_notes                  TEXT     DEFAULT NULL,
  p_email                  TEXT     DEFAULT NULL       -- ← new
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, auth, pg_temp
AS $$
DECLARE
  v_res   JSONB;
  v_email TEXT;
  v_id    UUID;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  -- Do the real work with the existing, proven 9-arg function
  v_res := public.admin_pre_list_shop(
    p_name, p_mobile, p_area, p_category_slugs,
    p_primary_category_slug, p_city_id, p_source,
    p_consent_method, p_notes
  );

  -- Attach the email if one was supplied and the shop was created
  v_email := NULLIF(lower(trim(COALESCE(p_email, ''))), '');
  IF v_email IS NOT NULL AND v_res ? 'business_id' THEN
    IF v_email !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' THEN
      RAISE EXCEPTION 'Invalid email format: %', v_email;
    END IF;
    v_id := (v_res->>'business_id')::UUID;
    UPDATE public.businesses
       SET email = v_email
     WHERE id = v_id
       AND (email IS NULL OR email = '');     -- never clobber an existing one
    v_res := v_res || jsonb_build_object('email', v_email);
  END IF;

  RETURN v_res;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_pre_list_shop(
  TEXT, TEXT, TEXT, TEXT[], TEXT, INT, TEXT, TEXT, TEXT, TEXT
) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- Verify:
-- SELECT proname, pg_get_function_identity_arguments(oid)
-- FROM pg_proc WHERE proname = 'admin_pre_list_shop';
--   → should list BOTH the 9-arg and the 10-arg version.

DO $$ BEGIN
  RAISE NOTICE '✓ db/215 installed. admin_pre_list_shop now accepts p_email (old signature still works).';
END $$;
