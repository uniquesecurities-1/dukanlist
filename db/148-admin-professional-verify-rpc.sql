-- ============================================================
-- db/148 — Admin RPCs for Professional Verification
-- ============================================================
-- Two RPCs:
--   1. admin_list_pending_professionals()  — queue of unverified pro listings
--   2. admin_verify_professional()         — approve / reject a listing
--
-- Both admin-only via is_admin() check.
-- ============================================================

BEGIN;

-- ============================================================
-- RPC 1: List pending professional verifications
-- ============================================================
CREATE OR REPLACE FUNCTION admin_list_pending_professionals()
RETURNS TABLE (
  id                          UUID,
  slug                        TEXT,
  name                        TEXT,
  owner_name                  TEXT,
  mobile                      TEXT,
  city_name                   TEXT,
  primary_category_name       TEXT,
  primary_category_slug       TEXT,
  is_professional_listing     BOOLEAN,
  professional_tier           TEXT,
  membership_no               TEXT,
  membership_authority        TEXT,
  professional_qualification  TEXT,
  practice_areas              TEXT[],
  disclaimer_accepted_at      TIMESTAMPTZ,
  prof_verified_at            TIMESTAMPTZ,
  prof_verification_notes     TEXT,
  status                      TEXT,
  created_at                  TIMESTAMPTZ
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  RETURN QUERY
  SELECT
    b.id, b.slug, b.name, b.owner_name, b.mobile,
    gc.name AS city_name,
    pc.name AS primary_category_name,
    pc.slug AS primary_category_slug,
    b.is_professional_listing,
    b.professional_tier,
    b.membership_no,
    b.membership_authority,
    b.professional_qualification,
    b.practice_areas,
    b.disclaimer_accepted_at,
    b.prof_verified_at,
    b.prof_verification_notes,
    b.status,
    b.created_at
  FROM businesses b
  LEFT JOIN geo_cities gc ON gc.id = b.city_id
  LEFT JOIN business_categories bcp ON bcp.business_id = b.id AND bcp.is_primary = TRUE
  LEFT JOIN categories pc ON pc.id = bcp.category_id
  WHERE b.is_professional_listing = TRUE
    AND b.prof_verified_at IS NULL
  ORDER BY
    -- Disclaimer accepted = ready for review (priority)
    CASE WHEN b.disclaimer_accepted_at IS NOT NULL THEN 0 ELSE 1 END,
    b.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_list_pending_professionals() TO authenticated;


-- ============================================================
-- RPC 2: Approve or reject a professional verification
-- ============================================================
CREATE OR REPLACE FUNCTION admin_verify_professional(
  p_business_id UUID,
  p_approve     BOOLEAN,
  p_notes       TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  -- admin_users.auth_user_id IS the primary key (1:1 with auth.users)
  -- So the admin's id = auth.uid() once is_admin() passes
  v_admin_id := auth.uid();

  IF p_approve THEN
    -- Approve: timestamp + admin id + notes
    UPDATE businesses
    SET prof_verified_at        = NOW(),
        prof_verified_by        = v_admin_id,
        prof_verification_notes = p_notes,
        updated_at              = NOW()
    WHERE id = p_business_id;
  ELSE
    -- Reject: clear professional flag so the listing reverts to regular mode
    -- (do NOT delete the membership data — admin notes capture the reason)
    UPDATE businesses
    SET is_professional_listing = FALSE,
        professional_tier       = NULL,
        prof_verification_notes = p_notes,
        prof_verified_by        = v_admin_id,
        prof_verified_at        = NULL,
        updated_at              = NOW()
    WHERE id = p_business_id;
  END IF;

  -- Audit log entry (existing admin_audit_log if available, else silent)
  BEGIN
    INSERT INTO admin_audit_log (admin_id, action_type, target_type, target_id, payload, created_at)
    VALUES (
      v_admin_id,
      CASE WHEN p_approve THEN 'professional.approve' ELSE 'professional.reject' END,
      'business',
      p_business_id,
      jsonb_build_object('notes', p_notes),
      NOW()
    );
  EXCEPTION WHEN OTHERS THEN
    NULL; -- audit log optional, do not fail the action
  END;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_verify_professional(UUID, BOOLEAN, TEXT) TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/148 installed.';
  RAISE NOTICE '  admin_list_pending_professionals() -> queue';
  RAISE NOTICE '  admin_verify_professional(biz_id, approve, notes) -> BOOLEAN';
END $$;
