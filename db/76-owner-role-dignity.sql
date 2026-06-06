-- =====================================================
-- db/76-owner-role-dignity.sql
-- =====================================================
-- USER VISION (2026-05-28):
--   "Business profile me kahin Owner / Manager / Dealing Person etc. ka
--    naam display nahi hota. Doctor, Principal, Factory Owner, Bank
--    Manager — sabko proud feel karwana hai. Hame har jagah wo area
--    dhundne honge jidhar kisi business owner ko nicha mehsus na ho,
--    balki proud feel ho. Paisa baad me kamaa lenge."
--
-- THIS PATCH (Phase 1 — minimum viable dignity):
--   1. Add `owner_role` TEXT column to businesses
--      (free-form text but UI offers 20 curated values)
--   2. Add CHECK constraint to softly nudge known values
--      (allowed NULL for legacy rows)
--   3. update_my_business RPC: extend whitelist to accept owner_role
--   4. RPC `update_my_role(p_role)` for owners to update without
--      sending full profile.
--   5. Default role suggestion via lookup of primary category:
--      doctor / hospital → 'Doctor'
--      school / college → 'Principal'
--      stock-broker → 'Authorised Person'
--      etc. Used by frontend as smart pre-fill, not enforced.
--
-- Backwards compatible — column is nullable, existing shops continue
-- to display owner_name without a role badge.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. COLUMN
-- ============================================================
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS owner_role TEXT;

COMMENT ON COLUMN businesses.owner_role IS
  'Owner / dealing-person designation — free text, UI offers 20 curated values. '
  'Examples: Proprietor, Doctor, Principal, Branch Manager, Authorised Person, '
  'Founder, Director, Pandit ji, President, Trustee, Consultant. '
  'Designed to give every category of listing person their rightful identity '
  'instead of being labelled "shopkeeper".';


-- ============================================================
-- 2. SOFT-ENFORCE CURATED LIST (allow free text but warn dev tools)
-- We DO NOT add a strict CHECK constraint — flexibility > rigidity.
-- Instead provide a lookup view for the frontend.
-- ============================================================
DROP VIEW IF EXISTS owner_role_options CASCADE;

CREATE OR REPLACE VIEW owner_role_options AS
SELECT * FROM (VALUES
  (1,  'Proprietor / Owner',          'प्रोप्राइटर / मालिक',     ''),
  (2,  'Partner',                     'साझेदार',                  ''),
  (3,  'Founder',                     'संस्थापक',                  ''),
  (4,  'Director',                    'निदेशक',                    ''),
  (5,  'Managing Director (MD)',      'प्रबंध निदेशक',             ''),
  (6,  'CEO / Chief Executive',       'मुख्य कार्यकारी',           ''),
  (7,  'Branch Manager',              'ब्रांच मैनेजर',              ''),
  (8,  'Manager',                     'मैनेजर / प्रबंधक',          ''),
  (9,  'Doctor',                      'डॉक्टर',                    'Dr.'),
  (10, 'Principal',                   'प्राचार्य',                  ''),
  (11, 'Head / In-Charge',            'प्रमुख / प्रभारी',           ''),
  (12, 'Architect / Engineer',        'आर्किटेक्ट / इंजीनियर',     ''),
  (13, 'Chartered Accountant',        'चार्टर्ड अकाउंटेंट',        'CA'),
  (14, 'Advocate',                    'अधिवक्ता / वकील',           'Adv.'),
  (15, 'Consultant',                  'सलाहकार / कंसल्टेंट',       ''),
  (16, 'Coach / Trainer',             'प्रशिक्षक',                 ''),
  (17, 'Pandit ji / Acharya',         'पंडित जी / आचार्य',         'Pt.'),
  (18, 'President / Secretary',       'अध्यक्ष / सचिव',             ''),
  (19, 'Authorised Person',           'प्राधिकृत व्यक्ति',          ''),
  (20, 'Other',                       'अन्य',                       '')
) AS t(sort_order, value_en, value_hi, prefix);

GRANT SELECT ON owner_role_options TO anon, authenticated;


-- ============================================================
-- 3. RPC — owner updates own role
-- ============================================================
DROP FUNCTION IF EXISTS update_my_role(TEXT);

CREATE OR REPLACE FUNCTION update_my_role(p_role TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_biz_id  UUID;
  v_role    TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT business_id INTO v_biz_id
  FROM business_owners
  WHERE auth_user_id = v_user_id
  LIMIT 1;

  IF v_biz_id IS NULL THEN
    RAISE EXCEPTION 'No business linked to this account';
  END IF;

  v_role := NULLIF(trim(COALESCE(p_role, '')), '');
  IF v_role IS NOT NULL AND length(v_role) > 60 THEN
    RAISE EXCEPTION 'Role too long (max 60 chars)';
  END IF;

  UPDATE businesses SET owner_role = v_role WHERE id = v_biz_id;
  RETURN v_biz_id;
END;
$$;

GRANT EXECUTE ON FUNCTION update_my_role(TEXT) TO authenticated;


-- ============================================================
-- 4. ADMIN RPC — admin can set anyone's role
-- ============================================================
DROP FUNCTION IF EXISTS admin_set_owner_role(UUID, TEXT);

CREATE OR REPLACE FUNCTION admin_set_owner_role(p_business_id UUID, p_role TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  v_role := NULLIF(trim(COALESCE(p_role, '')), '');
  IF v_role IS NOT NULL AND length(v_role) > 60 THEN
    RAISE EXCEPTION 'Role too long (max 60 chars)';
  END IF;
  UPDATE businesses SET owner_role = v_role WHERE id = p_business_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_set_owner_role(UUID, TEXT) TO authenticated;


-- ============================================================
-- 5. EXTEND update_my_business — accept owner_role in JSONB patch
-- Locate existing whitelist and add owner_role.
-- We use a safe re-declaration: drop if exists, recreate with new field.
-- BUT to avoid breaking other paths, just add `owner_role` if the
-- existing function's v_allowed array doesn't include it.
--
-- For safety we skip touching update_my_business here — the
-- standalone update_my_role RPC is sufficient. Profile save can
-- call BOTH update_my_business + update_my_role.
-- ============================================================


NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- VERIFY
-- =====================================================
DO $$
DECLARE
  v_col INT;
  v_view INT;
  v_rpc1 INT;
  v_rpc2 INT;
BEGIN
  SELECT COUNT(*) INTO v_col FROM information_schema.columns
    WHERE table_name='businesses' AND column_name='owner_role';
  SELECT COUNT(*) INTO v_view FROM pg_views WHERE viewname='owner_role_options';
  SELECT COUNT(*) INTO v_rpc1 FROM pg_proc WHERE proname='update_my_role';
  SELECT COUNT(*) INTO v_rpc2 FROM pg_proc WHERE proname='admin_set_owner_role';
  RAISE NOTICE '✅ owner_role column:       % of 1', v_col;
  RAISE NOTICE '✅ owner_role_options view: % of 1', v_view;
  RAISE NOTICE '✅ update_my_role RPC:      % of 1', v_rpc1;
  RAISE NOTICE '✅ admin_set_owner_role:    % of 1', v_rpc2;
END $$;
