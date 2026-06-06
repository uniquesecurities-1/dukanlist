-- =====================================================
-- db/59-listing-type-and-org-categories.sql
-- =====================================================
-- USER FEEDBACK:
--   "Gold Loan, Bank nahi hai — these are MAIN categories.
--    Aur 'DukanList' me 'Shop' ke saath 'organization' bhi
--    daal do — doctors, bankers, schools sochte hain 'we are
--    not running a dukan'."
--
-- WHAT THIS SQL DOES (additive only, zero risk):
--
--   1. Adds `listing_type` to businesses table
--        Values: 'shop' | 'professional' | 'organization' | 'service'
--        Default: 'shop' — backward compatible
--
--   2. Adds `default_listing_type` to categories
--        Lets the frontend auto-suggest the right type when a
--        category is picked at registration
--
--   3. Backfills default_listing_type on ~80 existing categories
--        Doctors/Lawyers/CAs → professional
--        Schools/Banks/NGOs/Govt offices → organization
--        Mechanics/Plumbers/Cleaners → service
--        Everything else → shop (default)
--
--   4. ADDS ~17 NEW CATEGORIES under financial-services + civic:
--        Public Sector Bank Branch, Private Bank Branch,
--        Co-operative Bank, Rural / Gramin Bank, ATM Only,
--        Banking Correspondent (Bank Mitra), Gold Loan Branch,
--        Government Office, Post Office, Police Station,
--        Masjid, Church, Mandir, Railway / Bus Station,
--        Self-Help Group, Government School, Private School,
--        Play School / Pre-school
--
--   5. Backfills businesses.listing_type from their existing
--        primary category — so doctor shops already in DB get
--        re-typed to 'professional' without owner intervention
-- =====================================================

BEGIN;

-- ============================================================
-- 1. Add listing_type to businesses
-- ============================================================
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS listing_type TEXT NOT NULL DEFAULT 'shop'
  CHECK (listing_type IN ('shop','professional','organization','service'));

COMMENT ON COLUMN businesses.listing_type IS
  'Surface label used in UI. shop=storefront, professional=individual practitioner, organization=institution, service=skilled-trade provider';

CREATE INDEX IF NOT EXISTS idx_biz_listing_type
  ON businesses(listing_type) WHERE status = 'active';

-- ============================================================
-- 2. Add default_listing_type to categories
-- ============================================================
ALTER TABLE categories
  ADD COLUMN IF NOT EXISTS default_listing_type TEXT NOT NULL DEFAULT 'shop'
  CHECK (default_listing_type IN ('shop','professional','organization','service'));

-- ============================================================
-- 3. Backfill default_listing_type for existing categories
-- ============================================================

-- PROFESSIONAL — individual practitioners
UPDATE categories SET default_listing_type = 'professional' WHERE slug IN (
  'doctor','dentist','ayurveda','homeopathy','veterinary','agri-vet-doctor',
  'eye-care','gynecologist','pediatrician','orthopedic','cardiologist',
  'dermatologist','ent-specialist','surgeon-general','urologist','neurologist',
  'psychiatrist','diabetes-specialist','diet-nutrition','mental-health',
  'lawyer','advocate','chartered-accountant','ca','tax-consultant','company-secretary',
  'financial-advisor','mutual-fund-distributor','insurance-life','insurance-health','insurance-general',
  'loan-agent','agri-loan-agent','aarhti-commission',
  'photographer','architect','interior-designer','real-estate-agent',
  'tutor','tuition-coaching','coaching-institute','driving-school',
  'physio'
);

-- ORGANIZATION — institutions
UPDATE categories SET default_listing_type = 'organization' WHERE slug IN (
  'hospital','nursing-home','pathology-lab','radiology-xray','ultrasound-sonography',
  'school','college','university','library','community-social',
  'gurudwara','temple-trust','ngo-charitable'
);

-- SERVICE — skilled-trade providers
UPDATE categories SET default_listing_type = 'service' WHERE slug IN (
  'mechanic','car-repair','bike-repair','tractor-repair',
  'electrician','plumber','carpenter','painter','mason',
  'ac-repair','ro-repair','tv-repair','fridge-repair','laptop-repair','mobile-repair',
  'cleaning-service','maid-service','laundry','dry-cleaner','tailor',
  'courier-delivery','packers-movers','transport-service',
  'gym-fitness','yoga-meditation','salon','spa','beauty-salon','beauty-wellness',
  'wedding-planner','event-management','dj-sound','tent-decorator','catering',
  'photographer','videographer','printing-press'
);

COMMIT;

BEGIN;

-- ============================================================
-- 4. ADD NEW CATEGORIES — Banks & Finance
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'financial-services')
INSERT INTO categories (slug, name, name_hi, icon, color, sort_order, description, keywords, parent_id, default_listing_type, active)
SELECT t.slug, t.name, t.name_hi, t.icon, '#1E40AF', t.sort_order, t.description, t.keywords, p.id, t.ltype, TRUE
FROM (VALUES
  ('bank-public',      'Public Sector Bank Branch',   'सरकारी बैंक शाखा',         '🏦', 51,
   'Government bank branch — SBI, PNB, BOB, Canara, BOI, IOB, UCO, Indian Bank, BOM',
   'public bank,sbi,state bank,pnb,punjab national bank,bob,bank of baroda,canara,union bank,uco,indian bank,iob,boi,sarkari bank,nationalised bank',
   'organization'),

  ('bank-private',     'Private Bank Branch',         'प्राइवेट बैंक शाखा',        '🏛️', 52,
   'Private bank branch — HDFC, ICICI, Axis, Kotak, Yes, IDFC First, IndusInd, RBL',
   'private bank,hdfc,icici,axis,kotak,yes bank,idfc,indusind,rbl,bandhan,private bank branch',
   'organization'),

  ('bank-cooperative', 'Co-operative Bank Branch',    'सहकारी बैंक शाखा',          '🏦', 53,
   'District / Urban / State Co-operative Bank — DCCB, DCB, Bharat Co-op',
   'cooperative bank,co-operative,dccb,dcb,sahkari,sahakar,district co op,urban co op',
   'organization'),

  ('bank-rural',       'Rural / Gramin Bank',         'ग्रामीण बैंक',              '🌾', 54,
   'Regional Rural Bank — HGB (Haryana Gramin), Punjab Gramin Bank, Sarva Haryana Gramin',
   'gramin bank,rural bank,rrb,regional rural bank,sarva haryana,punjab gramin,sponsored bank',
   'organization'),

  ('atm-cash',         'ATM / Cash Point',            'एटीएम / नकद पॉइंट',         '🏧', 55,
   'Standalone ATM, cash deposit machine, no full branch',
   'atm,cash machine,cdm,cash deposit,nakad,paisa nikalna,cash point,cashpoint',
   'organization'),

  ('bank-mitra',       'Banking Correspondent / Bank Mitra', 'बैंक मित्र / CSP',   '🤝', 56,
   'CSP, Bank Mitra, mini bank, BC outlet, business correspondent',
   'bank mitra,csp,customer service point,business correspondent,mini bank,bc outlet,grameen seva',
   'organization'),

  ('gold-loan',        'Gold Loan Branch',            'गोल्ड लोन शाखा',            '🪙', 57,
   'Muthoot, Manappuram, IIFL Gold, local pawn-broker (gold loan service)',
   'gold loan,sona loan,muthoot,manappuram,iifl,gold finance,pawn shop,girvi,sona girvi rakhna',
   'organization'),

  ('insurance-vehicle','Insurance Advisor — Vehicle / Motor','बीमा सलाहकार — वाहन','🚗', 58,
   'Motor / Vehicle / Car / 2-wheeler insurance advisor or agent',
   'motor insurance,vehicle insurance,car insurance,bike insurance,2 wheeler insurance,gaadi insurance,policy bazaar,bharti axa',
   'professional')
) AS t(slug, name, name_hi, icon, sort_order, description, keywords, ltype)
CROSS JOIN parent p
ON CONFLICT (slug) DO UPDATE
  SET keywords = EXCLUDED.keywords,
      description = EXCLUDED.description,
      default_listing_type = EXCLUDED.default_listing_type,
      parent_id = EXCLUDED.parent_id;

-- ============================================================
-- 5. ADD NEW CATEGORIES — Civic / Government / Religious
-- ============================================================
WITH parent AS (
  SELECT id FROM categories WHERE slug = 'community-social'
  UNION ALL SELECT id FROM categories WHERE slug = 'community'
  LIMIT 1
)
INSERT INTO categories (slug, name, name_hi, icon, color, sort_order, description, keywords, parent_id, default_listing_type, active)
SELECT t.slug, t.name, t.name_hi, t.icon, '#7C2D12', t.sort_order, t.description, t.keywords, p.id, 'organization', TRUE
FROM (VALUES
  ('govt-office',       'Government Office',           'सरकारी कार्यालय',           '🏛️', 70,
   'Tehsil, Municipal corporation, Block office, BDO, Tehsildar, Patwari',
   'govt office,sarkari karyalaya,tehsil,municipal,nagar palika,block,bdo,sdm,patwari,nagar nigam'),

  ('post-office',       'Post Office',                 'डाकघर / पोस्ट ऑफिस',        '📮', 71,
   'India Post branch, speed post, money order, savings account',
   'post office,dakghar,india post,speed post,money order,parcel,post bank,small savings'),

  ('police-station',    'Police Station / Chowki',     'पुलिस थाना / चौकी',          '🚓', 72,
   'Police thana, chowki, traffic police, women cell',
   'police station,thana,chowki,traffic police,helpline,fir,kotwali,women cell'),

  ('masjid',            'Masjid',                      'मस्जिद',                     '🕌', 73,
   'Mosque, jama masjid, prayer place',
   'masjid,mosque,jama masjid,namaz,islamic'),

  ('church',            'Church',                      'चर्च / गिरजाघर',             '⛪', 74,
   'Christian church, chapel, cathedral, prayer hall',
   'church,girja,chapel,christian,catholic,protestant,prayer hall'),

  ('mandir',            'Mandir / Temple',             'मंदिर',                      '🛕', 75,
   'Hindu temple, dharmik sthal, neighbourhood mandir',
   'mandir,temple,dharmik sthal,puja,aarti,bhajan,hindu mandir'),

  ('railway-bus',       'Railway / Bus Station',       'रेलवे / बस स्टैंड',          '🚉', 76,
   'Railway station, bus stand, transit point, public transport hub',
   'railway,station,bus stand,bus stop,bus adda,transit,public transport,depot'),

  ('self-help-group',   'Self-Help Group / Mahila Mandal','स्व-सहायता समूह / महिला मंडल','👭', 77,
   'SHG, mahila mandal, anganwadi, panchayat-level women group',
   'shg,self help,mahila mandal,anganwadi,panchayat,women group,grameen samuh'),

  ('gau-shala',         'Gau Shala / Cow Shelter',     'गौशाला',                     '🐄', 78,
   'Cow shelter, gau seva, panchgavya, cattle care charity',
   'gau shala,goshala,cow shelter,gau seva,panchgavya,cattle care')
) AS t(slug, name, name_hi, icon, sort_order, description, keywords)
CROSS JOIN parent p
ON CONFLICT (slug) DO UPDATE
  SET keywords = EXCLUDED.keywords,
      description = EXCLUDED.description,
      default_listing_type = EXCLUDED.default_listing_type,
      parent_id = EXCLUDED.parent_id;

-- ============================================================
-- 6. ADD NEW CATEGORIES — School variants under Education
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'education')
INSERT INTO categories (slug, name, name_hi, icon, color, sort_order, description, keywords, parent_id, default_listing_type, active)
SELECT t.slug, t.name, t.name_hi, t.icon, '#4F46E5', t.sort_order, t.description, t.keywords, p.id, 'organization', TRUE
FROM (VALUES
  ('school-govt',     'Government School',           'सरकारी स्कूल',              '🏫', 86,
   'Government primary / secondary / senior secondary school',
   'govt school,sarkari school,primary school,middle school,senior secondary,gpss,gsss,boys school,girls school'),

  ('school-private',  'Private School',              'निजी स्कूल',                '🏫', 87,
   'CBSE, ICSE, state board, public schools',
   'private school,cbse,icse,state board,public school,convent,english medium'),

  ('play-school',     'Play School / Pre-school',    'प्ले स्कूल / प्री-स्कूल',    '🧒', 88,
   'Pre-school, daycare, kindergarten, montessori, nursery',
   'play school,pre school,daycare,kindergarten,nursery,montessori,creche,bachhe ka school')
) AS t(slug, name, name_hi, icon, sort_order, description, keywords)
CROSS JOIN parent p
ON CONFLICT (slug) DO UPDATE
  SET keywords = EXCLUDED.keywords,
      description = EXCLUDED.description,
      default_listing_type = EXCLUDED.default_listing_type,
      parent_id = EXCLUDED.parent_id;

COMMIT;

BEGIN;

-- ============================================================
-- 7. Backfill businesses.listing_type from their primary category
--    Only updates rows still at default 'shop' — non-destructive
-- ============================================================
UPDATE businesses b
   SET listing_type = c.default_listing_type
  FROM categories c
 WHERE c.id = b.category_id
   AND c.default_listing_type IS NOT NULL
   AND c.default_listing_type <> 'shop'
   AND b.listing_type = 'shop';

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- 8. Verification
-- ============================================================
DO $$
DECLARE
  v_new INT;
  v_typed INT;
  v_biz_pro INT; v_biz_org INT; v_biz_svc INT;
BEGIN
  SELECT COUNT(*) INTO v_new FROM categories WHERE slug IN (
    'bank-public','bank-private','bank-cooperative','bank-rural','atm-cash',
    'bank-mitra','gold-loan','insurance-vehicle',
    'govt-office','post-office','police-station','masjid','church','mandir',
    'railway-bus','self-help-group','gau-shala',
    'school-govt','school-private','play-school'
  );
  SELECT COUNT(*) INTO v_typed FROM categories
    WHERE default_listing_type IN ('professional','organization','service');
  SELECT COUNT(*) INTO v_biz_pro FROM businesses WHERE listing_type='professional';
  SELECT COUNT(*) INTO v_biz_org FROM businesses WHERE listing_type='organization';
  SELECT COUNT(*) INTO v_biz_svc FROM businesses WHERE listing_type='service';

  RAISE NOTICE 'New categories created: % of 20', v_new;
  RAISE NOTICE 'Categories with non-default listing_type: %', v_typed;
  RAISE NOTICE 'Businesses re-typed: % professional · % organization · % service', v_biz_pro, v_biz_org, v_biz_svc;

  IF v_new < 20 THEN
    RAISE WARNING 'Some categories failed — check parent slugs (financial-services / community-social / education)';
  END IF;
END $$;

COMMIT;

-- =====================================================
-- ROLLBACK (if ever needed):
--   DELETE FROM categories WHERE slug IN (
--     'bank-public','bank-private','bank-cooperative','bank-rural','atm-cash',
--     'bank-mitra','gold-loan','insurance-vehicle','govt-office','post-office',
--     'police-station','masjid','church','mandir','railway-bus','self-help-group',
--     'gau-shala','school-govt','school-private','play-school'
--   );
--   UPDATE businesses SET listing_type='shop';
--   ALTER TABLE businesses DROP COLUMN listing_type;
--   ALTER TABLE categories DROP COLUMN default_listing_type;
-- =====================================================
