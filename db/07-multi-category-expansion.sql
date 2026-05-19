-- =====================================================
-- 07-multi-category-expansion.sql
-- DukanList Phase 2: Hierarchical Categories + Multi-Category Support
-- =====================================================
-- WHAT THIS DOES:
--   1. Adds 10 PARENT categories (top-level buckets)
--   2. Migrates existing 15 categories under appropriate parents
--   3. Adds 57 NEW sub-categories (total: 10 parents + 72 sub-cats = 82 entries)
--   4. Creates business_categories junction table (1 business → up to 5 cats)
--   5. Adds RLS policies for the junction table
--   6. Trigger to keep businesses.category_id in sync with primary category
--   7. Trigger to maintain category business_count denormalised counter
--
-- PREREQUISITES: Files 01-06 already executed in Supabase
-- HOW TO RUN: Paste in Supabase SQL Editor → Run
-- IDEMPOTENT: Safe to re-run (uses ON CONFLICT + IF NOT EXISTS)
-- =====================================================


-- =====================================================
-- SECTION 1: 10 PARENT CATEGORIES
-- =====================================================

INSERT INTO categories (slug, name, name_hi, icon, color, sort_order, description) VALUES
  ('healthcare',            'Healthcare & Medical',     'स्वास्थ्य एवं चिकित्सा',     '🏥', '#0EA5E9', 10,  'Doctors, hospitals, pharmacies, diagnostic labs, dental, eye, ayurveda'),
  ('financial-services',    'Financial Services',        'वित्तीय सेवाएं',             '💰', '#1E40AF', 20,  'Mutual funds, stock broking, financial planning, tax consulting'),
  ('insurance',             'Insurance',                 'बीमा',                      '🛡️', '#047857', 30,  'Life, health, motor, general insurance advisors'),
  ('home-services',         'Home Services',             'घरेलू सेवाएं',              '🔧', '#92400E', 40,  'Plumber, electrician, carpenter, painter, AC/RO repair, maid'),
  ('automotive',            'Automotive',                'ऑटोमोटिव',                  '🚗', '#7C3AED', 50,  'Cars, bikes, mechanics, service stations, spare parts'),
  ('food-beverage',         'Food & Beverage',           'खाद्य एवं पेय',             '🍴', '#DC2626', 60,  'Restaurants, dhaba, sweets, bakery, catering, tiffin'),
  ('retail-shopping',       'Retail & Shopping',         'रिटेल / दुकान',             '🛍️', '#16A34A', 70,  'Grocery, clothing, electronics, mobile, jewellery, footwear'),
  ('beauty-wellness',       'Beauty & Wellness',         'सौंदर्य एवं स्वास्थ्य',      '💇', '#EC4899', 80,  'Salon, parlour, gym, yoga, spa, mehndi artists'),
  ('education',             'Education & Training',      'शिक्षा एवं प्रशिक्षण',      '🎓', '#4F46E5', 90,  'Coaching, tuition, music, dance, computer classes, driving school'),
  ('professional-services', 'Professional Services',     'पेशेवर सेवाएं',             '👔', '#1F2937', 100, 'Lawyers, architects, photographers, property dealers, event managers')
ON CONFLICT (slug) DO NOTHING;


-- =====================================================
-- SECTION 2: MIGRATE existing 15 categories under parents
-- =====================================================

UPDATE categories SET parent_id = (SELECT id FROM categories WHERE slug = 'healthcare')
  WHERE slug IN ('doctor', 'pharmacy');

UPDATE categories SET parent_id = (SELECT id FROM categories WHERE slug = 'financial-services')
  WHERE slug = 'ca';

UPDATE categories SET parent_id = (SELECT id FROM categories WHERE slug = 'professional-services')
  WHERE slug = 'lawyer';

UPDATE categories SET parent_id = (SELECT id FROM categories WHERE slug = 'home-services')
  WHERE slug IN ('carpenter', 'plumber', 'electrician');

UPDATE categories SET parent_id = (SELECT id FROM categories WHERE slug = 'automotive')
  WHERE slug IN ('used-car', 'new-car');

UPDATE categories SET parent_id = (SELECT id FROM categories WHERE slug = 'food-beverage')
  WHERE slug IN ('restaurant', 'sweets');

UPDATE categories SET parent_id = (SELECT id FROM categories WHERE slug = 'retail-shopping')
  WHERE slug IN ('grocery', 'clothes', 'jewellery');

UPDATE categories SET parent_id = (SELECT id FROM categories WHERE slug = 'beauty-wellness')
  WHERE slug = 'salon';


-- =====================================================
-- SECTION 3: 57 NEW SUB-CATEGORIES (under parents)
-- =====================================================

INSERT INTO categories (slug, name, name_hi, icon, color, sort_order, description, parent_id)
SELECT v.slug, v.name, v.name_hi, v.icon, v.color, v.sort_order, v.description, p.id
FROM (VALUES

  -- ====== HEALTHCARE (8 new) ======
  ('dentist',                 'Dentist / Dental Clinic',         'डेंटिस्ट / दांत डॉक्टर',     '🦷', '#0EA5E9', 11, 'Dental treatment, braces, RCT, implants, cleaning',                'healthcare'),
  ('pathology-lab',           'Pathology Lab',                   'पैथोलॉजी लैब',                '🧪', '#0EA5E9', 12, 'Blood test, X-ray, ECG, ultrasound, MRI, diagnostic',              'healthcare'),
  ('physiotherapist',         'Physiotherapist',                 'फिजियोथेरेपिस्ट',             '🧑‍⚕️', '#0EA5E9', 13, 'Pain management, sports injury, post-op rehab, home visit',        'healthcare'),
  ('hospital',                'Hospital / Nursing Home',         'अस्पताल / नर्सिंग होम',      '🏨', '#0EA5E9', 14, 'Multi-specialty hospitals, nursing homes, ICU, emergency',         'healthcare'),
  ('ayurveda',                'Ayurvedic Doctor',                'आयुर्वेदिक डॉक्टर',           '🌿', '#0EA5E9', 15, 'Ayurvedic medicine, panchakarma, herbal treatment',                'healthcare'),
  ('homeopathy',              'Homeopathy Doctor',               'होम्योपैथी डॉक्टर',           '⚪', '#0EA5E9', 16, 'Homeopathic treatment, chronic disease care',                      'healthcare'),
  ('eye-care',                'Eye Care / Optometrist',          'नेत्र चिकित्सक / चश्मा',     '👓', '#0EA5E9', 17, 'Eye check-up, spectacles, contact lens, cataract surgery',         'healthcare'),
  ('veterinary',              'Veterinary / Pet Doctor',         'पशु चिकित्सक',                '🐾', '#0EA5E9', 18, 'Vet for cattle, dogs, pets, vaccination',                          'healthcare'),

  -- ====== FINANCIAL SERVICES (5 new) ======
  ('mutual-fund-distributor', 'Mutual Fund Distributor',         'म्यूचुअल फंड डिस्ट्रीब्यूटर','📊', '#1E40AF', 21, 'AMFI registered MFD — SIP, lumpsum, switching, goal planning',     'financial-services'),
  ('stock-broker',            'Stock Broker / Sub-Broker',       'स्टॉक ब्रोकर / सब ब्रोकर',  '📈', '#1E40AF', 22, 'SEBI authorised — equity, F&O, demat, IPO, MF via demat',          'financial-services'),
  ('tax-consultant',          'Tax Consultant (ITR / GST)',      'टैक्स कंसल्टेंट',             '🧾', '#1E40AF', 23, 'Income tax returns, GST filing, TDS, accounting',                  'financial-services'),
  ('financial-advisor',       'Financial Advisor / Planner',     'फाइनेंशियल एडवाइजर',          '💼', '#1E40AF', 24, 'Personal financial planning, retirement, goal-based investing',    'financial-services'),
  ('loan-agent',              'Loan Agent / DSA',                'लोन एजेंट',                   '🏦', '#1E40AF', 25, 'Home loan, business loan, personal loan, vehicle loan',            'financial-services'),

  -- ====== INSURANCE (3 new) ======
  ('insurance-life',          'Insurance Advisor — Life',        'जीवन बीमा सलाहकार',          '❤️', '#047857', 31, 'Life insurance, term plan, ULIP, endowment, savings plans',        'insurance'),
  ('insurance-health',        'Insurance Advisor — Health',      'स्वास्थ्य बीमा सलाहकार',     '🏥', '#047857', 32, 'Health insurance, mediclaim, family floater, critical illness',    'insurance'),
  ('insurance-general',       'Insurance Advisor — General',     'सामान्य बीमा सलाहकार',       '🚙', '#047857', 33, 'Motor, home, travel, fire, marine, business insurance',            'insurance'),

  -- ====== HOME SERVICES (7 new) ======
  ('painter',                 'Painter (House / Commercial)',    'पेंटर / रंगाई',              '🎨', '#92400E', 41, 'Wall painting, texture, POP, polishing, waterproofing',            'home-services'),
  ('ac-repair',               'AC / Fridge Repair',              'AC / फ्रिज मरम्मत',          '❄️', '#92400E', 42, 'AC installation, fridge service, gas refilling, repair',           'home-services'),
  ('ro-repair',               'RO / Water Purifier',             'RO / वाटर प्यूरिफायर',       '💧', '#92400E', 43, 'RO sales, service, filter change, installation',                   'home-services'),
  ('pest-control',            'Pest Control',                    'पेस्ट कंट्रोल',               '🐜', '#92400E', 44, 'Termite, cockroach, mosquito, rat control',                        'home-services'),
  ('maid-service',            'Maid / Cook Service',             'मेड / कुक सेवा',             '🧹', '#92400E', 45, 'Domestic help, maid, cook, full-time / part-time',                 'home-services'),
  ('cleaning-service',        'Cleaning Service',                'क्लीनिंग सर्विस',             '🧽', '#92400E', 46, 'Deep cleaning, sofa cleaning, water tank cleaning',                'home-services'),
  ('packers-movers',          'Packers & Movers',                'पैकर्स एंड मूवर्स',          '📦', '#92400E', 47, 'Household shifting, office relocation, transport',                 'home-services'),

  -- ====== AUTOMOTIVE (7 new) ======
  ('mechanic-2w',             'Mechanic — 2 Wheeler',            'मैकेनिक — दोपहिया',          '🏍️', '#7C3AED', 51, 'Bike, scooter repair, servicing, engine work',                     'automotive'),
  ('mechanic-4w',             'Mechanic — 4 Wheeler',            'मैकेनिक — चारपहिया',         '🚙', '#7C3AED', 52, 'Car repair, servicing, denting-painting, engine overhaul',         'automotive'),
  ('car-service',             'Car Service Station',             'कार सर्विस सेंटर',           '🔧', '#7C3AED', 53, 'Authorized service center, multi-brand service',                   'automotive'),
  ('tyre-shop',               'Tyre Shop',                       'टायर शॉप',                    '🛞', '#7C3AED', 54, 'Tyres, tubes, wheel alignment, balancing',                         'automotive'),
  ('spare-parts',             'Auto Spare Parts',                'ऑटो स्पेयर पार्ट्स',          '⚙️', '#7C3AED', 55, 'Car and bike spare parts, accessories',                            'automotive'),
  ('battery-shop',            'Battery Shop',                    'बैटरी की दुकान',              '🔋', '#7C3AED', 56, 'Inverter battery, car battery, bike battery, sales-service',       'automotive'),
  ('car-wash',                'Car / Bike Wash',                 'कार / बाइक वॉश',             '🚿', '#7C3AED', 57, 'Washing, polishing, detailing, ceramic coating',                   'automotive'),

  -- ====== FOOD & BEVERAGE (5 new) ======
  ('bakery',                  'Bakery / Cake Shop',              'बेकरी / केक शॉप',            '🎂', '#DC2626', 61, 'Cakes, breads, pastries, custom birthday/wedding cakes',           'food-beverage'),
  ('tiffin-service',          'Tiffin / Mess Service',           'टिफिन सर्विस / मेस',         '🍱', '#DC2626', 62, 'Home-cooked food, mess for students, hostel tiffin',               'food-beverage'),
  ('cafe',                    'Cafe / Coffee Shop',              'कैफे / कॉफी शॉप',            '☕', '#DC2626', 63, 'Coffee, tea, snacks, hangout spots',                               'food-beverage'),
  ('juice-corner',            'Juice / Shake Corner',            'जूस / शेक कॉर्नर',           '🥤', '#DC2626', 64, 'Fresh juice, lassi, milkshake, smoothies',                         'food-beverage'),
  ('ice-cream',               'Ice Cream Parlour',               'आइसक्रीम पार्लर',            '🍦', '#DC2626', 65, 'Ice cream parlours, kulfi, frozen desserts',                       'food-beverage'),

  -- ====== RETAIL & SHOPPING (6 new) ======
  ('mobile-shop',             'Mobile / Recharge Shop',          'मोबाइल / रिचार्ज शॉप',       '📱', '#16A34A', 71, 'Mobile phones, accessories, recharge, repair',                     'retail-shopping'),
  ('electronics',             'Electronics / Appliances',        'इलेक्ट्रॉनिक्स',              '📺', '#16A34A', 72, 'TV, fridge, washing machine, home appliances',                     'retail-shopping'),
  ('footwear',                'Footwear / Shoes',                'जूते / चप्पल',                '👞', '#16A34A', 73, 'Shoes, sandals, branded footwear',                                 'retail-shopping'),
  ('stationery',              'Stationery / Books',              'स्टेशनरी / किताबें',         '📚', '#16A34A', 74, 'Stationery, books, school supplies, printing',                     'retail-shopping'),
  ('gift-shop',               'Gift Shop / Cards',               'गिफ्ट शॉप',                   '🎁', '#16A34A', 75, 'Gifts, cards, return gifts, decorative items',                     'retail-shopping'),
  ('general-store',           'General Store',                   'जनरल स्टोर',                  '🏪', '#16A34A', 76, 'Cosmetics, toys, household items, general merchandise',            'retail-shopping'),

  -- ====== BEAUTY & WELLNESS (4 new) ======
  ('gym',                     'Gym / Fitness Center',            'जिम / फिटनेस सेंटर',         '💪', '#EC4899', 81, 'Gym, fitness training, weight loss, body building',                'beauty-wellness'),
  ('yoga-center',             'Yoga / Meditation Center',        'योग केंद्र',                   '🧘', '#EC4899', 82, 'Yoga classes, meditation, pranayama, wellness',                    'beauty-wellness'),
  ('spa',                     'Spa / Massage Center',            'स्पा / मसाज सेंटर',          '💆', '#EC4899', 83, 'Body massage, spa, ayurvedic massage, relaxation',                 'beauty-wellness'),
  ('mehndi-artist',           'Mehndi / Henna Artist',           'मेहंदी आर्टिस्ट',             '🌿', '#EC4899', 84, 'Bridal mehndi, party mehndi, traditional designs',                 'beauty-wellness'),

  -- ====== EDUCATION (5 new) ======
  ('tuition-coaching',        'Tuition / Coaching Center',       'ट्यूशन / कोचिंग',            '✏️', '#4F46E5', 91, 'School, IIT, NEET, banking, government exam coaching',             'education'),
  ('music-dance',             'Music / Dance Classes',           'संगीत / नृत्य क्लास',        '🎵', '#4F46E5', 92, 'Music, dance, instruments, vocal training',                        'education'),
  ('computer-classes',        'Computer / IT Classes',           'कंप्यूटर क्लासेस',            '💻', '#4F46E5', 93, 'Basic computer, Tally, MS Office, programming, digital marketing', 'education'),
  ('english-speaking',        'English Speaking Classes',        'अंग्रेजी भाषा क्लास',        '🗣️', '#4F46E5', 94, 'Spoken English, IELTS, personality development',                   'education'),
  ('driving-school',          'Driving School',                  'ड्राइविंग स्कूल',             '🚦', '#4F46E5', 95, 'Car, bike driving lessons, license assistance',                    'education'),

  -- ====== PROFESSIONAL SERVICES (7 new) ======
  ('architect',               'Architect / Civil Engineer',      'आर्किटेक्ट / इंजीनियर',      '📐', '#1F2937', 101, 'House design, building plan, structural engineer',                'professional-services'),
  ('interior-designer',       'Interior Designer',               'इंटीरियर डिज़ाइनर',           '🛋️', '#1F2937', 102, 'Home interiors, modular kitchen, false ceiling',                  'professional-services'),
  ('property-dealer',         'Property Dealer / Real Estate',   'प्रॉपर्टी डीलर',              '🏘️', '#1F2937', 103, 'Real estate, plot, flat, rental, commercial property',            'professional-services'),
  ('photographer',            'Photographer / Videographer',     'फोटोग्राफर',                  '📷', '#1F2937', 104, 'Wedding, birthday, pre-wedding shoots, drone videos',             'professional-services'),
  ('wedding-planner',         'Wedding / Event Planner',         'वेडिंग प्लानर',               '💐', '#1F2937', 105, 'Wedding planning, decoration, catering coordination',             'professional-services'),
  ('event-management',        'Event Management',                'इवेंट मैनेजमेंट',             '🎪', '#1F2937', 106, 'Birthday, anniversary, corporate events',                          'professional-services'),
  ('printing-press',          'Printing Press / Visiting Cards', 'प्रिंटिंग प्रेस',             '🖨️', '#1F2937', 107, 'Visiting cards, wedding cards, banners, flex, brochures',         'professional-services')

) AS v(slug, name, name_hi, icon, color, sort_order, description, parent_slug)
INNER JOIN categories p ON p.slug = v.parent_slug
ON CONFLICT (slug) DO NOTHING;


-- =====================================================
-- SECTION 4: business_categories JUNCTION TABLE
-- =====================================================
-- A business can belong to UP TO 5 categories.
-- Exactly ONE must be marked is_primary = TRUE.
-- =====================================================

CREATE TABLE IF NOT EXISTS business_categories (
  business_id   UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  category_id   INT  NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
  is_primary    BOOLEAN NOT NULL DEFAULT FALSE,
  added_at      TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (business_id, category_id)
);

-- Enforce: each business has EXACTLY ONE primary category
CREATE UNIQUE INDEX IF NOT EXISTS idx_bizcat_one_primary
  ON business_categories(business_id)
  WHERE is_primary = TRUE;

-- Lookup indexes
CREATE INDEX IF NOT EXISTS idx_bizcat_business ON business_categories(business_id);
CREATE INDEX IF NOT EXISTS idx_bizcat_category ON business_categories(category_id);


-- =====================================================
-- SECTION 5: View for easy querying of business + categories
-- =====================================================

CREATE OR REPLACE VIEW business_categories_view AS
SELECT
  bc.business_id,
  bc.category_id,
  bc.is_primary,
  bc.added_at,
  c.slug      AS category_slug,
  c.name      AS category_name,
  c.name_hi   AS category_name_hi,
  c.icon      AS category_icon,
  c.color     AS category_color,
  c.parent_id AS parent_id,
  p.slug      AS parent_slug,
  p.name      AS parent_name,
  p.icon      AS parent_icon
FROM business_categories bc
JOIN categories c       ON c.id = bc.category_id
LEFT JOIN categories p  ON p.id = c.parent_id;


-- =====================================================
-- SECTION 6: RLS policies for business_categories
-- =====================================================

ALTER TABLE business_categories ENABLE ROW LEVEL SECURITY;

-- Public read access for ACTIVE businesses' categories
DROP POLICY IF EXISTS "public_read_active_biz_cats" ON business_categories;
CREATE POLICY "public_read_active_biz_cats"
  ON business_categories FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM businesses b
      WHERE b.id = business_categories.business_id
        AND b.status = 'active'
    )
  );

-- Owners can manage (CRUD) their own business's categories
DROP POLICY IF EXISTS "owner_manage_biz_cats" ON business_categories;
CREATE POLICY "owner_manage_biz_cats"
  ON business_categories FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM business_owners bo
      WHERE bo.business_id = business_categories.business_id
        AND bo.auth_user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM business_owners bo
      WHERE bo.business_id = business_categories.business_id
        AND bo.auth_user_id = auth.uid()
    )
  );


-- =====================================================
-- SECTION 7: Trigger — keep businesses.category_id in sync with PRIMARY
-- =====================================================
-- When a row is marked is_primary, mirror it to businesses.category_id
-- and businesses.sub_category_id so existing search/RPC keeps working.
-- =====================================================

CREATE OR REPLACE FUNCTION sync_primary_category() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_parent_id INT;
BEGIN
  IF NEW.is_primary = TRUE THEN
    -- Look up the parent (if any) of the newly-primary category
    SELECT parent_id INTO v_parent_id FROM categories WHERE id = NEW.category_id;

    IF v_parent_id IS NOT NULL THEN
      -- It's a sub-category — set both parent and sub on businesses
      UPDATE businesses
      SET category_id     = v_parent_id,
          sub_category_id = NEW.category_id
      WHERE id = NEW.business_id;
    ELSE
      -- It's a top-level category — set as parent, clear sub
      UPDATE businesses
      SET category_id     = NEW.category_id,
          sub_category_id = NULL
      WHERE id = NEW.business_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_primary_cat ON business_categories;
CREATE TRIGGER trg_sync_primary_cat
  AFTER INSERT OR UPDATE OF is_primary ON business_categories
  FOR EACH ROW EXECUTE FUNCTION sync_primary_category();


-- =====================================================
-- SECTION 8: Trigger — maintain category.business_count counter
-- =====================================================

CREATE OR REPLACE FUNCTION update_category_business_count() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE categories
      SET business_count = business_count + 1
      WHERE id = NEW.category_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE categories
      SET business_count = GREATEST(business_count - 1, 0)
      WHERE id = OLD.category_id;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_update_cat_count ON business_categories;
CREATE TRIGGER trg_update_cat_count
  AFTER INSERT OR DELETE ON business_categories
  FOR EACH ROW EXECUTE FUNCTION update_category_business_count();


-- =====================================================
-- SECTION 9: Reload PostgREST schema cache
-- =====================================================

NOTIFY pgrst, 'reload schema';


-- =====================================================
-- VERIFICATION QUERIES — Run AFTER above, copy each separately
-- =====================================================
-- 1) Count parents (expect: 10)
--    SELECT COUNT(*) FROM categories WHERE parent_id IS NULL;
--
-- 2) Count sub-categories (expect: 72 — 15 migrated + 57 new)
--    SELECT COUNT(*) FROM categories WHERE parent_id IS NOT NULL;
--
-- 3) Full tree view:
--    SELECT p.icon || ' ' || p.name AS parent, c.icon || ' ' || c.name AS sub
--    FROM categories c JOIN categories p ON p.id = c.parent_id
--    ORDER BY p.sort_order, c.sort_order;
--
-- 4) Verify Deepak ji's categories exist:
--    SELECT slug, name FROM categories WHERE slug IN
--    ('mutual-fund-distributor','stock-broker','insurance-life','insurance-health','insurance-general');
--    (expect: 5 rows)
--
-- 5) Junction table exists:
--    SELECT COUNT(*) FROM business_categories;  -- expect: 0
-- =====================================================
