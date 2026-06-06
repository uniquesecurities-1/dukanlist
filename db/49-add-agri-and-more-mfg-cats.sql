-- =====================================================
-- db/49-add-agri-and-more-mfg-cats.sql
-- =====================================================
-- ADDITIVE ONLY: adds new 'agri-business' parent + 22 sub-cats
-- AND 12 more manufacturer sub-cats under retail-shopping.
--
-- Zero risk to existing data. Safe to run multiple times.
-- All inserts use ON CONFLICT (slug) DO NOTHING.
--
-- HOW TO RUN:
--   Supabase Dashboard → SQL Editor → New Query
--   Paste this entire file → Run
-- =====================================================

BEGIN;

-- ============================================================
-- PART 1: NEW PARENT — agri-business
-- ============================================================
INSERT INTO categories (parent_id, slug, name, name_hi, icon, color, sort_order, active)
VALUES (NULL, 'agri-business', 'Agri Business / Farming', 'कृषि व्यवसाय / खेती', '🌾', '#16A34A', 850, true)
ON CONFLICT (slug) DO NOTHING;

-- ============================================================
-- PART 2: AGRI BUSINESS sub-categories (22)
-- ============================================================
INSERT INTO categories (parent_id, slug, name, name_hi, icon, sort_order, active)
SELECT p.id, v.slug, v.name, v.name_hi, v.icon, v.sort_order, true
FROM categories p
CROSS JOIN (VALUES
  ('aarhti-commission',    'Aarhti / Commission Agent (Galla Mandi)', 'आढ़ती / कमीशन एजेंट',         '🌾', 851),
  ('pesticide-shop',       'Pesticide / Insecticide Shop',            'कीटनाशक शॉप',                  '🧴', 852),
  ('fertilizer-shop',      'Fertilizer / Khaad Shop',                 'खाद / उर्वरक शॉप',             '🪴', 853),
  ('seeds-shop',           'Seeds / Beej Shop',                       'बीज / सीड्स शॉप',              '🌱', 854),
  ('agri-equipment-shop',  'Agri Equipment / Implements Shop',        'कृषि उपकरण शॉप',                '🚜', 855),
  ('tractor-dealer',       'Tractor / Combine Harvester Dealer',      'ट्रैक्टर / हार्वेस्टर डीलर',     '🚜', 856),
  ('cattle-feed-shop',     'Cattle Feed / Pashu Aahar Shop',          'पशु आहार / दाना शॉप',           '🌽', 857),
  ('dairy-farm',           'Dairy Farm / Milk Producer',              'डेयरी फार्म / दूध उत्पादक',      '🐄', 858),
  ('poultry-farm',         'Poultry / Murgi Palan Farm',              'मुर्गी पालन फार्म',             '🐔', 859),
  ('bee-keeping',          'Bee Keeping / Honey Producer',            'मधुमक्खी पालन / शहद',           '🍯', 860),
  ('plant-nursery',        'Plant Nursery / Saplings',                'पौधा नर्सरी / पौधे',             '🌿', 861),
  ('agri-vet-doctor',      'Veterinary / Animal Doctor',              'पशु चिकित्सक',                 '🐾', 862),
  ('drip-irrigation',      'Drip Irrigation / Sprinkler Dealer',      'ड्रिप / स्प्रिंकलर डीलर',       '💧', 863),
  ('cold-storage',         'Cold Storage / Warehouse',                'कोल्ड स्टोरेज / गोदाम',          '❄️', 864),
  ('agri-export',          'Agri Trader / Exporter',                  'कृषि व्यापारी / निर्यातक',       '📦', 865),
  ('agri-loan-agent',      'Agri Loan / KCC Agent',                   'कृषि लोन / KCC एजेंट',          '💰', 866),
  ('flour-mill',           'Flour Mill / Atta Chakki',                'आटा चक्की / फ्लोर मिल',          '🌾', 867),
  ('rice-mill',            'Rice Mill / Chawal Mill',                 'राइस मिल / चावल मिल',           '🍚', 868),
  ('oil-mill',             'Oil Mill / Tel Mill',                     'तेल मिल / कोल्हू',              '🛢️', 869),
  ('cotton-ginning',       'Cotton Ginning / Kapas Factory',          'कपास जिनिंग / कॉटन फैक्ट्री',    '🧶', 870),
  ('animal-husbandry',     'Animal Husbandry / Goat / Sheep',         'पशुपालन / बकरी / भेड़',          '🐐', 871),
  ('fishery',              'Fishery / Fish Farm',                     'मछली पालन / फिशरी',             '🐟', 872)
) AS v(slug, name, name_hi, icon, sort_order)
WHERE p.slug = 'agri-business'
ON CONFLICT (slug) DO NOTHING;

-- ============================================================
-- PART 3: MORE MANUFACTURER sub-categories under retail-shopping (12)
-- ============================================================
INSERT INTO categories (parent_id, slug, name, name_hi, icon, sort_order, active)
SELECT p.id, v.slug, v.name, v.name_hi, v.icon, v.sort_order, true
FROM categories p
CROSS JOIN (VALUES
  ('manufacturer-metal',        'Metal / Steel Fabrication Manufacturer', 'धातु / स्टील निर्माता',         '⚙️',  255),
  ('manufacturer-plastic',      'Plastic / Packaging Manufacturer',       'प्लास्टिक / पैकेजिंग निर्माता',  '🛍️',  256),
  ('manufacturer-chemical',     'Chemical / Industrial Manufacturer',     'रसायन / औद्योगिक निर्माता',       '🧪',  257),
  ('manufacturer-leather',      'Leather Goods Manufacturer',             'चमड़ा उत्पाद निर्माता',           '👜',  258),
  ('manufacturer-paper',        'Paper / Cardboard Manufacturer',         'कागज / कार्डबोर्ड निर्माता',       '📦',  259),
  ('manufacturer-electronics',  'Electronics / LED Manufacturer',         'इलेक्ट्रॉनिक्स / LED निर्माता',    '💡',  260),
  ('manufacturer-machinery',    'Machinery / Equipment Manufacturer',     'मशीनरी / उपकरण निर्माता',         '🏗️',  261),
  ('manufacturer-construction', 'Construction Material Manufacturer',     'निर्माण सामग्री निर्माता',         '🧱',  262),
  ('manufacturer-handicraft',   'Handicraft / Art Manufacturer',          'हस्तशिल्प निर्माता',              '🎨',  263),
  ('manufacturer-spices',       'Spices / Masala Manufacturer',           'मसाला / स्पाइस निर्माता',          '🌶️',  264),
  ('manufacturer-cosmetic',     'Cosmetic / Personal Care Manufacturer',  'कॉस्मेटिक निर्माता',              '💄',  265),
  ('manufacturer-pharma',       'Pharma / Medicine Manufacturer',         'फार्मा / दवा निर्माता',           '💊',  266)
) AS v(slug, name, name_hi, icon, sort_order)
WHERE p.slug = 'retail-shopping'
ON CONFLICT (slug) DO NOTHING;

-- ============================================================
-- Reload PostgREST schema cache so REST API sees new rows
-- ============================================================
NOTIFY pgrst, 'reload schema';

-- ============================================================
-- Verify
-- ============================================================
DO $$
DECLARE
  v_agri_parent INT;
  v_agri_subs INT;
  v_mfg_subs INT;
BEGIN
  SELECT COUNT(*) INTO v_agri_parent FROM categories WHERE slug = 'agri-business' AND parent_id IS NULL;
  SELECT COUNT(*) INTO v_agri_subs   FROM categories WHERE parent_id = (SELECT id FROM categories WHERE slug = 'agri-business');
  SELECT COUNT(*) INTO v_mfg_subs    FROM categories WHERE slug LIKE 'manufacturer%';

  RAISE NOTICE 'agri-business parent exists : % (expected 1)', v_agri_parent;
  RAISE NOTICE 'agri-business sub-cats      : % (expected 22)', v_agri_subs;
  RAISE NOTICE 'manufacturer-* total        : % (expected 17)', v_mfg_subs;
END $$;

COMMIT;

-- =====================================================
-- After running this, all pages on the website will
-- automatically show the new categories — they're loaded
-- from this `categories` table:
--   - register.html  (category picker)
--   - browse.html    (category browser)
--   - search.html    (filter rail)
--   - index.html     (homepage category strip)
--   - business.html  (multi-cat tags)
--   - admin/*        (admin tools)
-- No frontend code changes needed.
-- =====================================================
