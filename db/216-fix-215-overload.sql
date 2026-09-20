-- ============================================================
-- db/216 — URGENT: undo db/215's ambiguous overload
-- ============================================================
-- db/215 created a SECOND admin_pre_list_shop with 10 args whose
-- last arg has a DEFAULT, and that wrapper then called
-- admin_pre_list_shop(...9 args...) BY NAME.
--
-- Postgres does not prefer the exact-arity candidate: a 9-arg call
-- matches BOTH the 9-arg function and the 10-arg one (default-padded),
-- so the call raises
--     "function admin_pre_list_shop(...) is not unique"
-- …on the unconditional path inside the wrapper. Net effect: EVERY
-- Quick Add single-add fails, with or without an email.
--
-- Fix: no overload at all.
--   1. DROP the 10-arg function (restores db/165 as the only one)
--   2. Add a tiny, separate admin_set_business_email() that the
--      frontend calls right after a successful pre-list.
--
-- SAFE: idempotent, re-runnable, and harmless if db/215 was never run.
-- ============================================================

BEGIN;

-- ---- 1. Remove the ambiguous overload ----------------------
DROP FUNCTION IF EXISTS public.admin_pre_list_shop(
  TEXT, TEXT, TEXT, TEXT[], TEXT, INT, TEXT, TEXT, TEXT, TEXT
);

-- ---- 2. Dedicated, unambiguous email setter ----------------
CREATE OR REPLACE FUNCTION public.admin_set_business_email(
  p_business_id UUID,
  p_email       TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, auth, pg_temp
AS $$
DECLARE
  v_email TEXT;
  v_old   TEXT;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  v_email := NULLIF(lower(trim(COALESCE(p_email, ''))), '');
  IF v_email IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'empty email');
  END IF;
  IF v_email !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' THEN
    RAISE EXCEPTION 'Invalid email format: %', v_email;
  END IF;

  SELECT email INTO v_old FROM public.businesses WHERE id = p_business_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Business not found';
  END IF;

  -- never clobber an email the owner already set
  IF v_old IS NOT NULL AND v_old <> '' THEN
    RETURN jsonb_build_object('success', false, 'reason', 'email already set', 'existing', v_old);
  END IF;

  UPDATE public.businesses SET email = v_email WHERE id = p_business_id;
  RETURN jsonb_build_object('success', true, 'email', v_email);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_set_business_email(UUID, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ---- Verify (run separately) -------------------------------
-- Must return exactly ONE row (the 9-arg version):
--   SELECT pg_get_function_identity_arguments(oid)
--   FROM pg_proc WHERE proname = 'admin_pre_list_shop';

DO $$ BEGIN
  RAISE NOTICE '✓ db/216 installed. Overload removed; admin_set_business_email() available.';
END $$;
