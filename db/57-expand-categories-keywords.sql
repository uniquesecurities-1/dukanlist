-- =====================================================
-- db/57-expand-categories-keywords.sql
-- =====================================================
-- ADDITIVE ONLY: Two purposes
--   1. Fill major gaps in food/grocery/health/fresh categories
--      (e.g., 'Organic Foods' was missing; users couldn't find it)
--   2. Add a 'keywords' column with rich synonyms — so search by
--      'organic', 'sabzi', 'doodh', 'millet', 'natural' works
--      across pucho-bhai, register, browse, search pages.
--
-- ZERO RISK: only adds rows + 1 column. No existing data touched.
--
-- HOW TO RUN: Supabase Dashboard → SQL Editor → paste → Run
-- =====================================================

BEGIN;

-- ============================================================
-- 1. Add keywords column for synonym search
-- ============================================================
ALTER TABLE categories
  ADD COLUMN IF NOT EXISTS keywords TEXT;

COMMENT ON COLUMN categories.keywords IS
  'Comma-separated synonyms/aliases. Used by frontend search so users can find a category by alternate names (e.g., organic-foods has keywords ''organic,natural,healthy,millet,quinoa,health food'').';

-- ============================================================
-- 2. Backfill keywords on EXISTING food/grocery/health categories
--    so common alternate terms still resolve
-- ============================================================
UPDATE categories SET keywords = 'kirana,karyana,grocery,daily needs,fmcg,raashan,ration,provision store,general store' WHERE slug = 'grocery';
UPDATE categories SET keywords = 'restaurant,dhaba,hotel,khana,food joint,family restaurant,non veg,veg,thali,paratha' WHERE slug = 'restaurant';
UPDATE categories SET keywords = 'sweets,mithai,halwai,laddu,barfi,kaju katli,gulab jamun,rasgulla,confectioner,caterer,catering' WHERE slug = 'sweets';
UPDATE categories SET keywords = 'tiffin,mess,lunch box,dabba,khana service,hostel food,homemade tiffin,office tiffin' WHERE slug = 'tiffin-service';
UPDATE categories SET keywords = 'bakery,cake,bread,pastry,birthday cake,wedding cake,cookies,donut,muffin' WHERE slug = 'bakery';
UPDATE categories SET keywords = 'cafe,coffee shop,tea stall,chai,espresso,coffee house,hangout' WHERE slug = 'cafe';
UPDATE categories SET keywords = 'juice,shake,lassi,smoothie,fresh juice,milkshake,nimbu pani,sharbat' WHERE slug = 'juice-corner';
UPDATE categories SET keywords = 'ice cream,kulfi,frozen dessert,gelato,sundae,softy' WHERE slug = 'ice-cream';
UPDATE categories SET keywords = 'dairy,milk,doodh,paneer,curd,dahi,ghee,butter,milk producer,doodh dairy' WHERE slug = 'dairy-farm';
UPDATE categories SET keywords = 'ayurveda,ayurvedic,herbal,natural medicine,vaidya,panchakarma,desi ilaaj' WHERE slug = 'ayurveda';
UPDATE categories SET keywords = 'pharmacy,medical store,chemist,medicine,dawai,dawakhana,davai' WHERE slug = 'pharmacy';
UPDATE categories SET keywords = 'doctor,clinic,physician,mbbs,opd,physician,dispensary' WHERE slug = 'doctor';
UPDATE categories SET keywords = 'mechanic,workshop,auto repair,garage,bike repair,car repair,2 wheeler,4 wheeler' WHERE slug = 'mechanic';
UPDATE categories SET keywords = 'salon,beauty,parlour,haircut,facial,massage,bridal,makeup,hair spa' WHERE slug = 'beauty-salon';
UPDATE categories SET keywords = 'tutor,coaching,tuition,classes,academy,teacher,padhai' WHERE slug = 'tutor';
UPDATE categories SET keywords = 'mutual fund,sip,investment,wealth,distributor,advisor,amfi,arn' WHERE slug = 'mutual-fund-distributor';

-- food parents (for search resolution via parent_name)
UPDATE categories SET keywords = 'food,beverage,khaana,khana,eating,catering,canteen,mess' WHERE slug = 'food-beverage';
UPDATE categories SET keywords = 'retail,store,shop,kirana,grocery,daily needs' WHERE slug = 'retail';
UPDATE categories SET keywords = 'health,medical,doctor,hospital,clinic,ilaaj,treatment' WHERE slug = 'healthcare';

COMMIT;

BEGIN;

-- ============================================================
-- 3. ADD NEW CATEGORIES — Food & Beverage children
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'food-beverage')
INSERT INTO categories (slug, name, name_hi, icon, color, sort_order, description, keywords, parent_id, active)
SELECT t.slug, t.name, t.name_hi, t.icon, '#DC2626', t.sort_order, t.description, t.keywords, p.id, TRUE
FROM (VALUES
  ('organic-foods',     'Organic / Health Food Store',     'ऑर्गेनिक / हेल्थ फूड स्टोर',     '🌱', 66, 'Organic vegetables, millets, jaggery, natural foods, gluten-free, vegan', 'organic,natural,healthy food,millet,jaggery,gud,quinoa,oats,vegan,gluten free,health store,desi food,desi ghee'),
  ('chaat-corner',      'Chaat / Street Food',             'चाट / स्ट्रीट फूड',              '🥟', 67, 'Golgappa, chaat, tikki, samosa, kachori, chowmein, momos', 'chaat,golgappa,pani puri,tikki,samosa,kachori,momos,chowmein,street food,fast food'),
  ('dhaba',             'Dhaba / Roadside Food',           'ढाबा / रोडसाइड भोजन',           '🍛', 68, 'Punjabi dhaba, highway food, paratha, dal, sabji, tandoor', 'dhaba,punjabi food,highway,paratha,tandoor,dal makhani,paneer,sarson saag'),
  ('veg-restaurant',    'Pure Veg Restaurant',             'शुद्ध शाकाहारी रेस्टोरेंट',      '🥗', 69, 'Pure vegetarian, jain food, satwik, no-onion no-garlic', 'pure veg,vegetarian,jain food,satwik,shudh shakahari,no onion'),
  ('non-veg-restaurant','Non-Veg Restaurant',              'नॉन-वेज रेस्टोरेंट',             '🍗', 70, 'Chicken, mutton, fish, biryani, kebab, tandoori', 'non veg,chicken,mutton,biryani,kebab,tandoori,fish'),
  ('dry-fruits',        'Dry Fruits / Nuts Shop',          'ड्राई फ्रूट / मेवा शॉप',          '🥜', 71, 'Almonds, cashews, walnuts, raisins, dates, kaju badam', 'dry fruit,mewa,kaju,badam,almond,cashew,walnut,akhrot,kishmish,raisin,dates,khajoor'),
  ('homemade-foods',    'Homemade / Pickle / Papad',       'घर का बना / अचार / पापड़',        '🫙', 72, 'Pickles, papad, masala, badi, home-style ready food', 'pickle,achar,papad,masala,home made,desi pickle,kachori,mathri,badi,laddu'),
  ('khoya-mawa',        'Khoya / Mawa / Cream Shop',       'खोया / मावा शॉप',                 '🥛', 73, 'Khoya, mawa, cream, malai, paneer wholesale', 'khoya,mawa,malai,cream,paneer,milk solid,wholesale dairy'),
  ('pan-shop',          'Pan Shop / Tobacco / Cigarette',  'पान शॉप / सिगरेट',                '🥥', 74, 'Pan, gutka, beedi, cigarette, tobacco, mouth freshener', 'pan,paan,gutka,beedi,cigarette,tobacco,mukhwas,supari'),
  ('cold-drinks',       'Cold Drinks / Soda / Snacks',     'कोल्ड ड्रिंक / सोडा शॉप',         '🥤', 75, 'Coke, Pepsi, sodas, mineral water, packaged snacks', 'cold drink,soda,thanda,pepsi,coke,mineral water,bisleri,snacks,chips,kurkure'),
  ('canteen-mess',      'Canteen / Hostel Mess',           'कैंटीन / हॉस्टल मेस',             '🍽️', 76, 'Office canteen, hostel mess, factory tiffin', 'canteen,mess,hostel food,office tiffin,factory canteen')
) AS t(slug, name, name_hi, icon, sort_order, description, keywords)
CROSS JOIN parent p
ON CONFLICT (slug) DO UPDATE
  SET keywords = EXCLUDED.keywords,
      description = EXCLUDED.description,
      parent_id = EXCLUDED.parent_id;

-- ============================================================
-- 4. ADD NEW CATEGORIES — Retail (grocery + fresh produce)
-- ============================================================
WITH parent AS (
  SELECT id FROM categories WHERE slug = 'retail'
  UNION ALL
  SELECT id FROM categories WHERE slug = 'grocery'
  LIMIT 1
)
INSERT INTO categories (slug, name, name_hi, icon, color, sort_order, description, keywords, parent_id, active)
SELECT t.slug, t.name, t.name_hi, t.icon, '#16A34A', t.sort_order, t.description, t.keywords, p.id, TRUE
FROM (VALUES
  ('sabzi-shop',        'Vegetable Shop / Sabzi Wala',     'सब्ज़ी की दुकान / सब्ज़ी वाला',    '🥬', 121, 'Daily fresh vegetables, leafy greens, seasonal sabzi', 'sabzi,sabji,vegetable,bhaji,hari sabzi,leafy,palak,methi,tomato,onion,potato,fresh veg'),
  ('fruit-shop',        'Fruit Shop / Phal Wala',          'फल की दुकान / फल वाला',           '🍎', 122, 'Fresh fruits, mango, apple, banana, seasonal phal', 'fruit,phal,phaal,apple,banana,mango,seb,kela,aam,papita,seasonal fruit,phal wala'),
  ('atta-chakki',       'Atta Chakki / Flour Mill',        'आटा चक्की / आटा मिल',             '🌾', 123, 'Wheat flour, gram flour, mill grinding, atta, besan, custom grind', 'atta,chakki,flour mill,wheat,besan,maida,daliya,custom atta,grinding,gehu'),
  ('milk-booth',        'Milk Booth / Doodh Center',       'दूध बूथ / डेयरी',                 '🥛', 124, 'Local milk supply, doodh dairy outlet, packet milk', 'milk booth,doodh,dairy outlet,amul,mother dairy,milk packet,fresh milk,doodh wala'),
  ('frozen-foods',      'Frozen Food / Cold Storage Retail','फ्रोजन फूड / कोल्ड स्टोरेज',       '🧊', 125, 'Frozen peas, ice cream wholesale, cold storage retail', 'frozen,cold storage,ice cream wholesale,frozen peas,frozen food,deep freezer'),
  ('provision-store',   'General Provision Store',         'जनरल प्रोविजन स्टोर',             '🛒', 126, 'All-in-one daily needs, mini super market', 'provision,general store,mini market,super market,daily needs,household,everyday store'),
  ('cattle-feed',       'Cattle Feed / Bran Shop',         'पशु आहार / चूरी की दुकान',         '🐄', 127, 'Cattle feed, bran (chokar), wheat husk, dairy feed', 'cattle feed,pashu aahar,chokar,bran,husk,buffalo food,cow food,wheat husk,khalli'),
  ('pet-supplies',      'Pet Food / Pet Supplies',         'पेट फूड / पेट सप्लाई',             '🐕', 128, 'Dog food, cat food, pet accessories, pet grooming items', 'pet food,dog food,cat food,pet shop,pet accessories,pedigree,whiskas,pet grooming')
) AS t(slug, name, name_hi, icon, sort_order, description, keywords)
CROSS JOIN parent p
ON CONFLICT (slug) DO UPDATE
  SET keywords = EXCLUDED.keywords,
      description = EXCLUDED.description,
      parent_id = EXCLUDED.parent_id;

COMMIT;

BEGIN;

-- ============================================================
-- 5. ADD NEW CATEGORIES — Health/Wellness extra coverage
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'healthcare')
INSERT INTO categories (slug, name, name_hi, icon, color, sort_order, description, keywords, parent_id, active)
SELECT t.slug, t.name, t.name_hi, t.icon, '#0EA5E9', t.sort_order, t.description, t.keywords, p.id, TRUE
FROM (VALUES
  ('homeopathy',        'Homeopathy Doctor',               'होम्योपैथी डॉक्टर',                 '⚕️', 16, 'Homeopathic medicine, natural healing, side-effect-free', 'homeopathy,homoeopathy,bach flower,natural medicine,bina side effect'),
  ('yoga-meditation',   'Yoga / Meditation Centre',        'योग / मेडिटेशन केंद्र',              '🧘', 17, 'Yoga classes, meditation, pranayama, asanas, mental wellness', 'yoga,meditation,pranayama,asana,wellness,mental health,vipassana'),
  ('gym-fitness',       'Gym / Fitness Centre',            'जिम / फिटनेस सेंटर',                 '💪', 18, 'Gym, crossfit, zumba, aerobics, fitness training', 'gym,fitness,crossfit,zumba,aerobics,personal trainer,workout,body building'),
  ('physio',            'Physiotherapy / Rehab',           'फिजियोथेरेपी / रीहैब',              '🩺', 19, 'Physiotherapy, sports injury, post-surgery recovery, ortho rehab', 'physio,physiotherapy,rehab,sports injury,recovery,back pain,knee pain'),
  ('diet-nutrition',    'Dietician / Nutritionist',        'डाइटीशियन / न्यूट्रिशनिस्ट',         '🥗', 20, 'Diet plans, weight loss, weight gain, sports nutrition, diabetic diet', 'dietician,nutritionist,diet plan,weight loss,weight gain,calorie,diabetic diet,nutrition'),
  ('mental-health',     'Counsellor / Psychologist',       'काउंसलर / मनोवैज्ञानिक',            '🧠', 21, 'Counselling, mental health, stress, depression, relationship', 'counsellor,psychologist,therapist,mental health,depression,stress,anxiety,relationship')
) AS t(slug, name, name_hi, icon, sort_order, description, keywords)
CROSS JOIN parent p
ON CONFLICT (slug) DO UPDATE
  SET keywords = EXCLUDED.keywords,
      description = EXCLUDED.description,
      parent_id = EXCLUDED.parent_id;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- 6. Verification
-- ============================================================
DO $$
DECLARE v_new INT; v_kw_count INT;
BEGIN
  SELECT COUNT(*) INTO v_new FROM categories
    WHERE slug IN ('organic-foods','chaat-corner','dhaba','veg-restaurant','non-veg-restaurant',
                   'dry-fruits','homemade-foods','khoya-mawa','pan-shop','cold-drinks','canteen-mess',
                   'sabzi-shop','fruit-shop','atta-chakki','milk-booth','frozen-foods','provision-store',
                   'cattle-feed','pet-supplies','homeopathy','yoga-meditation','gym-fitness','physio',
                   'diet-nutrition','mental-health');
  SELECT COUNT(*) INTO v_kw_count FROM categories WHERE keywords IS NOT NULL AND length(keywords) > 0;
  RAISE NOTICE 'New categories registered: % of 25', v_new;
  RAISE NOTICE 'Categories with keywords: %', v_kw_count;
  IF v_new < 25 THEN
    RAISE WARNING 'Some categories failed to register — check parent slugs (food-beverage / retail / healthcare)';
  END IF;
END $$;

COMMIT;

-- =====================================================
-- ROLLBACK (if ever needed):
--   DELETE FROM categories WHERE slug IN (
--     'organic-foods','chaat-corner','dhaba','veg-restaurant','non-veg-restaurant',
--     'dry-fruits','homemade-foods','khoya-mawa','pan-shop','cold-drinks','canteen-mess',
--     'sabzi-shop','fruit-shop','atta-chakki','milk-booth','frozen-foods','provision-store',
--     'cattle-feed','pet-supplies','homeopathy','yoga-meditation','gym-fitness','physio',
--     'diet-nutrition','mental-health'
--   );
--   ALTER TABLE categories DROP COLUMN IF EXISTS keywords;
-- =====================================================
