-- ============================================================
-- db/154 — Hotfix admin_approve_business (drop nonexistent activated_at)
-- ============================================================
-- db/149 added a pro-verification warning to admin_approve_business but
-- mistakenly referenced an `activated_at` column on businesses — that
-- column does not exist in db/01-schema.sql (the table only has
-- `created_at` + `updated_at`).
--
-- Result: admin clicking "Approve & Activate" hits the RPC and gets
-- `ERROR: column "activated_at" does not exist` (PostgrestException 400).
--
-- This migration restores the correct UPDATE to set only status + the
-- existing updated_at field (which is auto-touched by trg_biz_updated
-- anyway, but explicit is fine). The pro-verification warning logic
-- introduced by db/149 is preserved — only the broken column reference
-- is removed.
--
-- SAFE: CREATE OR REPLACE. Re-runnable.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION admin_approve_business(p_business_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_pro       BOOLEAN;
  v_pro_verified TIMESTAMPTZ;
  v_name         TEXT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  -- Fetch existence + pro flags
  SELECT name,
         COALESCE(is_professional_listing, FALSE),
         prof_verified_at
    INTO v_name, v_is_pro, v_pro_verified
  FROM businesses
  WHERE id = p_business_id;

  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Business not found';
  END IF;

  -- db/149 addition: warn admin if approving a strict-tier pro listing
  -- whose membership hasn't been verified yet via /admin/professional-verify
  IF v_is_pro = TRUE AND v_pro_verified IS NULL THEN
    RAISE WARNING 'Professional listing % approved without membership verification. Please verify via /admin/professional-verify.html.', v_name;
  END IF;

  -- Update — only columns that actually exist on businesses.
  -- trg_biz_updated trigger auto-touches updated_at on every UPDATE.
  UPDATE businesses
  SET status = 'active'
  WHERE id = p_business_id;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_approve_business(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/154 installed. admin_approve_business no longer references the nonexistent activated_at column.';
END $$;
