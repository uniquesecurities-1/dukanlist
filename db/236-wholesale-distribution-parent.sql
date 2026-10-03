-- ============================================================
-- db/236 — Wholesale & Distribution becomes its own parent
-- ============================================================
--
-- db/235 filed ten "Distributor / Wholesaler — …" trades under
-- Retail & Shopping. Deepak's point, and he is right: a distributor is
-- not a shop. A customer browsing Retail wants somewhere to buy a
-- saree; a distributor there is noise. And a shopkeeper looking for a
-- supplier has nowhere to look at all.
--
-- So this migration:
--   1. creates a top-level parent, Wholesale & Distribution (sort 75,
--      right after Retail & Shopping at 70)
--   2. moves the ten distributor-* rows under it, plus the two
--      wholesale entries that were already sitting in Retail
--      (wholesale-dealer, mithai-wholesale)
--   3. repoints the primary category of any shop whose trade moved, so
--      a distributor no longer shows up on the Retail landing page
--   4. adds 35 more wholesale trades — each slug checked against the
--      live 403 first; every one was free. They deliberately mirror
--      retail categories (footwear-shop → wholesale-footwear) because
--      that is the real distinction in a mandi town: the same goods,
--      a different customer.
--
-- Nothing is deleted or renamed. Slugs of the moved rows are
-- unchanged, so /local/<city>/distributor-food and every shop already
-- filed there keep working. Safe to re-run.
-- ============================================================

BEGIN;

-- 1. the new parent -------------------------------------------------
INSERT INTO public.categories (parent_id, slug, name, name_hi, icon, color, sort_order, active)
VALUES (NULL, 'wholesale-distribution', 'Wholesale & Distribution', 'होलसेल एवं डिस्ट्रीब्यूशन', '📦', '#B45309', 75, TRUE)
ON CONFLICT (slug) DO NOTHING;

-- 2. move what belongs there ----------------------------------------
UPDATE public.categories c
   SET parent_id = w.id
  FROM public.categories w
 WHERE w.slug = 'wholesale-distribution'
   AND c.slug IN (
     'distributor-food','distributor-clothing','distributor-cosmetics',
     'distributor-electronics','distributor-stationery','distributor-hardware',
     'distributor-pharma','distributor-plastic','distributor-beverages',
     'distributor-general','wholesale-dealer','mithai-wholesale'
   );

-- 3. shops whose trade just moved should move with it ----------------
--    (their sub_category_id is untouched; only the parent pointer that
--     decides which landing page lists them is corrected)
UPDATE public.businesses b
   SET category_id = w.id
  FROM public.categories w
 WHERE w.slug = 'wholesale-distribution'
   AND b.sub_category_id IN (
     SELECT id FROM public.categories WHERE parent_id = w.id
   )
   AND b.category_id IS DISTINCT FROM w.id;

-- 4. the rest of the wholesale trades --------------------------------
INSERT INTO public.categories (parent_id, slug, name, name_hi, icon, color, sort_order, active)
SELECT w.id, v.slug, v.name, v.name_hi, v.icon, w.color, v.sort_order, TRUE
FROM (VALUES
  -- food & grocery line
  ('wholesale-kirana',      'Wholesale — Kirana & Grocery',            'होलसेल — किराना एवं ग्रॉसरी',        '🛒', 100::SMALLINT),
  ('wholesale-grain',       'Wholesale — Grain, Rice & Flour',         'होलसेल — अनाज, चावल एवं आटा',        '🌾', 101::SMALLINT),
  ('wholesale-spices',      'Wholesale — Spices, Dal & Pulses',        'होलसेल — मसाले, दाल एवं पल्सेस',      '🌶️', 102::SMALLINT),
  ('wholesale-dryfruits',   'Wholesale — Dry Fruits & Mewa',           'होलसेल — ड्राई फ्रूट्स एवं मेवा',     '🥜', 103::SMALLINT),
  ('wholesale-namkeen',     'Wholesale — Namkeen & Snacks',            'होलसेल — नमकीन एवं स्नैक्स',          '🍿', 104::SMALLINT),
  ('wholesale-bakery',      'Wholesale — Bakery & Confectionery',      'होलसेल — बेकरी एवं कन्फेक्शनरी',      '🧁', 105::SMALLINT),
  ('wholesale-dairy',       'Wholesale — Dairy & Milk Products',       'होलसेल — डेयरी एवं दूध उत्पाद',       '🥛', 106::SMALLINT),
  ('wholesale-tea',         'Wholesale — Tea & Coffee',                'होलसेल — चाय एवं कॉफी',              '🍵', 107::SMALLINT),
  ('wholesale-fruit-veg',   'Wholesale — Fruit & Vegetable (Mandi)',   'होलसेल — फल एवं सब्ज़ी (मंडी)',       '🥬', 108::SMALLINT),
  ('wholesale-ice',         'Wholesale — Ice Supplier',                'होलसेल — बर्फ सप्लायर',              '🧊', 109::SMALLINT),

  -- clothing & personal
  ('wholesale-sarees',      'Wholesale — Saree & Dress Material',      'होलसेल — साड़ी एवं ड्रेस मटेरियल',    '🥻', 120::SMALLINT),
  ('wholesale-hosiery',     'Wholesale — Hosiery & Undergarments',     'होलसेल — होज़री एवं अंडरगारमेंट',     '🧦', 121::SMALLINT),
  ('wholesale-footwear',    'Wholesale — Footwear',                    'होलसेल — फुटवियर',                   '👟', 122::SMALLINT),
  ('wholesale-imitation',   'Wholesale — Imitation Jewellery & Bangles','होलसेल — इमिटेशन ज्वेलरी एवं चूड़ी', '💍', 123::SMALLINT),

  -- house & hardware
  ('wholesale-crockery',    'Wholesale — Crockery, Utensils & Steel',  'होलसेल — क्रॉकरी, बर्तन एवं स्टील',   '🍽️', 140::SMALLINT),
  ('wholesale-glass',       'Wholesale — Glass & Mirror',              'होलसेल — ग्लास एवं मिरर',            '🪞', 141::SMALLINT),
  ('wholesale-furniture',   'Wholesale — Furniture & Mattress',        'होलसेल — फर्नीचर एवं गद्दे',         '🛋️', 142::SMALLINT),
  ('wholesale-electrical',  'Wholesale — Electrical Goods',            'होलसेल — इलेक्ट्रिकल सामान',          '💡', 143::SMALLINT),
  ('wholesale-sanitary',    'Wholesale — Sanitary & Bath Fittings',    'होलसेल — सैनिटरी एवं बाथ फिटिंग',     '🚿', 144::SMALLINT),
  ('wholesale-paint',       'Wholesale — Paint & Coatings',            'होलसेल — पेंट',                      '🎨', 145::SMALLINT),
  ('wholesale-cement-steel','Wholesale — Cement, Sariya & Building',   'होलसेल — सीमेंट, सरिया एवं बिल्डिंग', '🧱', 146::SMALLINT),

  -- tech & vehicle
  ('wholesale-mobile',      'Wholesale — Mobile & Accessories',        'होलसेल — मोबाइल एवं एक्सेसरीज़',      '📱', 160::SMALLINT),
  ('wholesale-computer',    'Wholesale — Computer & IT Hardware',      'होलसेल — कंप्यूटर एवं आईटी',          '💻', 161::SMALLINT),
  ('wholesale-auto-parts',  'Wholesale — Auto Parts & Spares',         'होलसेल — ऑटो पार्ट्स',               '🔧', 162::SMALLINT),

  -- paper, play, pooja
  ('wholesale-books',       'Wholesale — Books & School Supplies',     'होलसेल — किताबें एवं स्कूल सामान',    '📚', 180::SMALLINT),
  ('wholesale-toys-gifts',  'Wholesale — Toys, Gifts & Novelty',       'होलसेल — खिलौने एवं गिफ्ट',          '🎁', 181::SMALLINT),
  ('wholesale-sports',      'Wholesale — Sports Goods',                'होलसेल — स्पोर्ट्स गुड्स',            '🏏', 182::SMALLINT),
  ('wholesale-pooja',       'Wholesale — Pooja Samagri & Agarbatti',   'होलसेल — पूजा सामग्री एवं अगरबत्ती',  '🪔', 183::SMALLINT),

  -- packaging, agri, industrial
  ('wholesale-packaging',   'Wholesale — Packaging, Cartons & Poly Bags','होलसेल — पैकेजिंग एवं कार्टन',      '📦', 200::SMALLINT),
  ('wholesale-disposable',  'Wholesale — Disposable Items (Dona, Glass)','होलसेल — डिस्पोजेबल आइटम',         '🥤', 201::SMALLINT),
  ('wholesale-agri-inputs', 'Wholesale — Seeds, Fertilizer & Pesticide','होलसेल — बीज, खाद एवं कीटनाशक',     '🌱', 202::SMALLINT),
  ('wholesale-cattle-feed', 'Wholesale — Cattle & Poultry Feed',       'होलसेल — पशु एवं पोल्ट्री आहार',      '🐄', 203::SMALLINT),
  ('wholesale-chemicals',   'Wholesale — Chemicals & Industrial Supply','होलसेल — केमिकल एवं इंडस्ट्रियल',    '⚗️', 204::SMALLINT),
  ('wholesale-scrap',       'Wholesale — Scrap & Recycling',           'होलसेल — स्क्रैप एवं रीसाइक्लिंग',    '♻️', 205::SMALLINT),
  ('cf-agent',              'C&F Agent / Super Stockist',              'सी एंड एफ एजेंट / सुपर स्टॉकिस्ट',    '🏬', 206::SMALLINT)
) AS v(slug, name, name_hi, icon, sort_order)
JOIN public.categories w ON w.slug = 'wholesale-distribution'
ON CONFLICT (slug) DO NOTHING;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/236-wholesale-distribution-parent.sql');
  END IF;
END $$;

COMMIT;

-- ============================================================
-- Everything now under Wholesale & Distribution: 12 moved + 35 new.
-- ============================================================
SELECT c.slug, c.name, c.business_count AS shops
FROM public.categories c
JOIN public.categories w ON w.id = c.parent_id AND w.slug = 'wholesale-distribution'
ORDER BY c.sort_order, c.slug;
