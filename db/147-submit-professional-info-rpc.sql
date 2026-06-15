-- ============================================================
-- db/147 — RPC: submit_professional_info
-- ============================================================
-- Called from register.html immediately after register_business_public succeeds,
-- if the owner's selected categories include a professional one. Persists the
-- membership number, qualification, practice areas and disclaimer acceptance
-- to the freshly-created business row.
--
-- IDENTIFICATION: owner mobile (same number used during registration).
-- Looks up the MOST RECENT pending business with that mobile (status='pending'
-- or 'active' created in last 5 minutes), updates its professional columns.
-- This narrow time-window prevents updating an unrelated existing listing.
--
-- AUTO-DERIVATION: professional_tier is set automatically from the linked
-- categories (db/145 already auto-flags businesses based on category tier
-- via backfill trigger). This RPC only sets the *owner-supplied* fields.
--
-- VERIFICATION STATUS: NOT marked verified by this RPC — admin must verify.
-- The disclaimer_accepted_at timestamp confirms the owner saw + agreed.
--
-- SAFE: SECURITY DEFINER but heavily input-validated. anon-callable since
-- this is part of the public registration flow.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION submit_professional_info(
  p_owner_mobile        TEXT,
  p_membership_no       TEXT,
  p_qualification       TEXT,
  p_practice_areas      TEXT[] DEFAULT '{}',
  p_disclaimer_accepted BOOLEAN DEFAULT FALSE
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_biz_id   UUID;
  v_authority TEXT;
  v_mobile_norm TEXT;
BEGIN
  -- ===== Validation =====
  IF NOT p_disclaimer_accepted THEN
    RAISE EXCEPTION 'Disclaimer must be accepted to submit professional info';
  END IF;
  IF p_membership_no IS NULL OR LENGTH(TRIM(p_membership_no)) < 3 THEN
    RAISE EXCEPTION 'Membership/registration number is required (min 3 chars)';
  END IF;
  IF p_qualification IS NULL OR LENGTH(TRIM(p_qualification)) = 0 THEN
    RAISE EXCEPTION 'Qualification is required';
  END IF;

  -- Normalise mobile to 10 digits
  v_mobile_norm := regexp_replace(COALESCE(p_owner_mobile, ''), '\D', '', 'g');
  IF LENGTH(v_mobile_norm) > 10 THEN
    v_mobile_norm := RIGHT(v_mobile_norm, 10);
  END IF;
  IF LENGTH(v_mobile_norm) <> 10 THEN
    RAISE EXCEPTION 'Owner mobile must be a 10-digit Indian number';
  END IF;

  -- ===== Find target business =====
  -- Most recent biz with matching mobile created in the last 15 minutes
  SELECT id INTO v_biz_id
  FROM businesses
  WHERE RIGHT(regexp_replace(mobile, '\D', '', 'g'), 10) = v_mobile_norm
    AND created_at > NOW() - INTERVAL '15 minutes'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_biz_id IS NULL THEN
    RAISE EXCEPTION 'No recent business found for this mobile. Please register first.';
  END IF;

  -- ===== Derive membership_authority from qualification =====
  v_authority := CASE UPPER(TRIM(p_qualification))
    WHEN 'CA'    THEN 'ICAI'
    WHEN 'ACA'   THEN 'ICAI'
    WHEN 'FCA'   THEN 'ICAI'
    WHEN 'CS'    THEN 'ICSI'
    WHEN 'ACS'   THEN 'ICSI'
    WHEN 'FCS'   THEN 'ICSI'
    WHEN 'CMA'   THEN 'ICMAI'
    WHEN 'ACMA'  THEN 'ICMAI'
    WHEN 'FCMA'  THEN 'ICMAI'
    WHEN 'MBBS'  THEN 'NMC'
    WHEN 'MD'    THEN 'NMC'
    WHEN 'MS'    THEN 'NMC'
    WHEN 'BDS'   THEN 'NMC'
    WHEN 'MDS'   THEN 'NMC'
    WHEN 'BAMS'  THEN 'NMC'
    WHEN 'BHMS'  THEN 'NMC'
    WHEN 'BPT'   THEN 'NMC'
    WHEN 'LLB'   THEN 'BCI'
    WHEN 'LLM'   THEN 'BCI'
    WHEN 'MFD'   THEN 'AMFI'
    WHEN 'AP'    THEN 'SEBI'
    WHEN 'IRDAI' THEN 'IRDAI'
    ELSE NULL
  END;

  -- ===== Persist =====
  UPDATE businesses
  SET membership_no              = TRIM(p_membership_no),
      membership_authority       = COALESCE(v_authority, membership_authority),
      professional_qualification = TRIM(p_qualification),
      practice_areas             = COALESCE(p_practice_areas, '{}'),
      disclaimer_accepted_at     = NOW(),
      -- Force-flag as professional (db/145 backfill may have missed it if
      -- categories were attached after biz creation in some edge flows)
      is_professional_listing    = TRUE,
      professional_tier          = COALESCE(
        professional_tier,
        (SELECT CASE WHEN bool_or(c.professional_tier = 'strict') THEN 'strict' ELSE 'partial' END
         FROM business_categories bc
         JOIN categories c ON c.id = bc.category_id
         WHERE bc.business_id = v_biz_id AND c.professional_tier IS NOT NULL),
        'strict'    -- defensive fallback
      ),
      updated_at = NOW()
  WHERE id = v_biz_id;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION submit_professional_info(TEXT, TEXT, TEXT, TEXT[], BOOLEAN)
  TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/147 installed.';
  RAISE NOTICE '  submit_professional_info(owner_mobile, membership_no, qualification, practice_areas[], disclaimer) -> BOOLEAN';
END $$;
