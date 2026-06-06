-- =====================================================
-- db/78-admin-update-shop-add-email.sql
-- =====================================================
-- USER (2026-05-28): "Bansal Handloom ke owner ne placeholder email
-- daali thi (bansal@gmail.com). Ab proper email update karwane ki
-- request aayi hai. Admin shop edit form mein email field nahi hai."
--
-- ROOT CAUSE: admin_update_shop() RPC has a whitelist of allowed
-- columns. `email` was never added — only set during registration
-- and never exposed for admin edit.
--
-- THIS PATCH:
--   1. Adds `email` to v_allowed whitelist in admin_update_shop()
--   2. Adds light validation (basic email format) — RAISE EXCEPTION
--      on garbage so admin gets immediate feedback
--   3. Allows NULL to clear (rare but possible)
--
-- Note: this updates `businesses.email` (PUBLIC shop email, used
-- on the business page contact card). It does NOT change the
-- owner's LOGIN email (auth.users.email) — that requires the
-- existing /api/admin-update-shop-email Vercel endpoint which
-- calls supabase admin.updateUserById.
--
-- Idempotent — pure RPC swap. Zero risk.
-- =====================================================

BEGIN;

DROP FUNCTION IF EXISTS admin_update_shop(UUID, JSONB);

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
  v_email_in  TEXT;
  v_allowed   TEXT[] := ARRAY[
    'name','usp_text','usp_hi','about_text',
    'mobile','whatsapp','owner_name',
    'email',                       -- ← NEW: public shop email
    'category_id','sub_category_id',
    'address_line1','address_line2','pincode',
    'hours_json','services_json',
    'photos','video_url',
    'verified_mobile','verified_address','verified_photo','verified_visit',
    'featured','admin_notes',
    'status',
    'payment_methods','special_features','established_year'
  ];
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  v_admin_id := auth.uid();

  -- Pre-validate email if present
  IF p_patch ? 'email' AND p_patch->'email' <> 'null'::jsonb THEN
    v_email_in := lower(trim(p_patch->>'email'));
    IF v_email_in = '' THEN
      v_email_in := NULL;
    ELSIF v_email_in !~ '^[a-z0-9._+-]+@[a-z0-9.-]+\.[a-z]{2,}$' THEN
      RAISE EXCEPTION 'invalid email format: %', v_email_in;
    END IF;
  END IF;

  FOR v_key IN SELECT jsonb_object_keys(p_patch)
  LOOP
    IF v_key = ANY(v_allowed) THEN

      IF v_key IN ('payment_methods','special_features') THEN
        EXECUTE format(
          'UPDATE businesses SET %I = ARRAY(SELECT jsonb_array_elements_text($1->%L)), updated_at = NOW() WHERE id = $2',
          v_key, v_key
        ) USING p_patch, p_business_id;

      ELSIF v_key = 'photos' THEN
        EXECUTE format(
          'UPDATE businesses SET %I = ARRAY(SELECT jsonb_array_elements_text($1->%L)), updated_at = NOW() WHERE id = $2',
          v_key, v_key
        ) USING p_patch, p_business_id;

      ELSIF v_key = 'established_year' THEN
        IF p_patch ? 'established_year' AND p_patch->'established_year' = 'null'::jsonb THEN
          UPDATE businesses SET established_year = NULL, updated_at = NOW() WHERE id = p_business_id;
        ELSE
          EXECUTE format(
            'UPDATE businesses SET %I = ($1->>%L)::INT, updated_at = NOW() WHERE id = $2',
            v_key, v_key
          ) USING p_patch, p_business_id;
        END IF;

      ELSIF v_key = 'email' THEN
        -- Use the normalized v_email_in (may be NULL to clear)
        UPDATE businesses
           SET email = v_email_in,
               updated_at = NOW()
         WHERE id = p_business_id;

      ELSE
        EXECUTE format(
          'UPDATE businesses SET %I = ($1->>%L)::%s, updated_at = NOW() WHERE id = $2',
          v_key, v_key,
          CASE
            WHEN v_key IN ('category_id','sub_category_id') THEN 'INT'
            WHEN v_key IN ('verified_mobile','verified_address','verified_photo','verified_visit','featured') THEN 'BOOLEAN'
            WHEN v_key IN ('hours_json','services_json') THEN 'JSONB'
            ELSE 'TEXT'
          END
        ) USING p_patch, p_business_id;
      END IF;

      v_changed := v_changed || to_jsonb(v_key);
    END IF;
  END LOOP;

  -- Audit log (defensive — don't fail save if audit table missing)
  BEGIN
    INSERT INTO admin_audit_log(admin_id, action, business_id, details)
    VALUES (v_admin_id, 'shop_update', p_business_id,
            jsonb_build_object('changed', v_changed, 'patch', p_patch));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', TRUE, 'changed', v_changed);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_update_shop(UUID, JSONB) TO authenticated;

NOTIFY pgrst, 'reload schema';

DO $$
DECLARE v_n INT;
BEGIN
  SELECT COUNT(*) INTO v_n FROM pg_proc
   WHERE proname = 'admin_update_shop';
  RAISE NOTICE '✓ admin_update_shop now accepts `email` field (% def)', v_n;
END $$;

COMMIT;
