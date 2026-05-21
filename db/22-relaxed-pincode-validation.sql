-- =====================================================
-- 22-relaxed-pincode-validation.sql
-- Relax pincode validation: district-level match (not strict city)
-- =====================================================
-- WHY:
--   Current validation: pincode MUST match the exact selected city.
--   Problem: A shopkeeper in Mandi Dabwali area may have pincode
--   125201 (Kalanwali) because that's the actual postal pincode
--   serving their location. Rejecting on submission is bad UX.
--
-- NEW BEHAVIOUR:
--   Pincode is valid if it matches ANY city within the SAME DISTRICT
--   as the selected city. So selecting "Mandi Dabwali" with pincode
--   125201 is OK because Kalanwali is in Sirsa district too.
--
-- ADMIN STILL SEES the discrepancy via verified_address flag.
-- PREREQUISITES: 01-21 SQL files executed.
-- HOW TO RUN: Paste in Supabase SQL Editor → Run.
-- IDEMPOTENT: CREATE OR REPLACE, safe to re-run.
-- =====================================================

CREATE OR REPLACE FUNCTION validate_pincode_city(p_pincode TEXT, p_city_id INT)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_district_id INT;
  v_found       BOOLEAN;
BEGIN
  -- Resolve the city's district
  SELECT district_id INTO v_district_id
  FROM geo_cities
  WHERE id = p_city_id;

  IF v_district_id IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Pincode valid if any city in this district has it
  SELECT EXISTS (
    SELECT 1
    FROM geo_cities c
    WHERE c.district_id = v_district_id
      AND c.active = TRUE
      AND p_pincode = ANY(c.pincodes)
  ) INTO v_found;

  RETURN v_found;
END;
$$;

GRANT EXECUTE ON FUNCTION validate_pincode_city(TEXT, INT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- =====================================================
-- VERIFICATION
-- =====================================================
-- Should now return TRUE (pincode 125201 is in Sirsa district):
--   SELECT validate_pincode_city(
--     '125201',
--     (SELECT id FROM geo_cities WHERE name = 'Mandi Dabwali' LIMIT 1)
--   );
--
-- Should return FALSE (pincode from outside Sirsa):
--   SELECT validate_pincode_city(
--     '110001',
--     (SELECT id FROM geo_cities WHERE name = 'Mandi Dabwali' LIMIT 1)
--   );
-- =====================================================
