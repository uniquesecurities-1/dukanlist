-- =====================================================
-- db/75-add-handloom-and-more-categories.sql
-- =====================================================
-- USER (2026-05-28):
--   "Handloom category nahi hai abhi.. kuch aur bhi dekhe & update kare."
--
-- AUDIT FINDING:
--   handloom-shop IS in static categories.json (Retail-Shopping) but
--   was never inserted into the live `categories` table. Same applies
--   to several other common local shop types.
--
-- THIS PATCH adds 16 missing local categories across 5 parents:
--
-- Retail-Shopping (10):
--   handloom-shop, music-instruments, sports-goods, mewa-dryfruits,
--   namkeen-snacks, sofa-set, glass-mirror, sofa-furniture,
--   mithai-wholesale, gift-bouquet
--
-- Home Services (3):
--   aluminum-fabricator, iron-grills, refrigerator-washing-repair
--
-- Healthcare (1): hearing-aid-mobility
-- Professional Services (1): drone-prewedding-photo
-- Automotive (1): generator-dg-set
--
-- All inserts are idempotent (ON CONFLICT (slug) DO UPDATE).
-- =====================================================

BEGIN;

-- ============================================================
-- 1) RETAIL & SHOPPING (10)
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'retail-shopping')
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order, description, keywords,
  parent_id, default_listing_type, active
)
SELECT t.slug, t.name, t.name_hi, t.icon, '#9333EA', t.sort_order,
       t.description, t.keywords, p.id, 'shop', TRUE
FROM (VALUES
  ('handloom-shop',
   'Handloom / Khadi Shop',
   'हथकरघा / खादी की दुकान',
   '🧵', 520,
   'Handloom sarees, khadi, cotton fabric, hand-woven textiles, dhurries, bedsheets, organic cotton, traditional weaves',
   'handloom,khadi,hand loom,handwoven,khadi kapda,cotton fabric,desi cotton,organic cotton,village weaver,bunkar,handicraft fabric,charkha,sutli,dhurrie,coir,jute,traditional saree,banarasi,kanjivaram,chanderi,maheshwari,village made,khadi gramodyog'),

  ('music-instruments',
   'Music Instruments Shop',
   'संगीत वाद्ययंत्र',
   '🎹', 521,
   'Harmonium, tabla, sitar, flute, guitar, keyboard, casio, drums, dholak, dafli — sales + repair + tuning',
   'music instrument,musical instrument,sangeet,harmonium,tabla,sitar,santoor,flute,bansuri,guitar,bass guitar,electric guitar,keyboard,piano,casio,yamaha,roland,drum,dholak,dafli,khanjari,manjeera,ghungroo,saaj,tuning,instrument repair'),

  ('sports-goods',
   'Sports Goods / Cricket Shop',
   'खेल का सामान / क्रिकेट',
   '🏏', 522,
   'Cricket bat, ball, kit, football, hockey, badminton, gym equipment, dumbbells, jersey, shoes, kabaddi, sports accessories',
   'sports goods,sports shop,cricket bat,bat,ball,leather ball,tennis ball,wicket,gloves,pads,cricket kit,football,foot ball,hockey,hockey stick,badminton,racket,racquet,shuttle,carrom board,chess,kabaddi,volleyball,basket ball,gym equipment,dumbbell,treadmill,jersey,sports shoes'),

  ('mewa-dryfruits',
   'Dry Fruits / Mewa Shop',
   'मेवा / सूखे मेवे',
   '🥜', 523,
   'Almonds, cashews, walnuts, raisins, pistachio, anjeer, chironji, dates, kishmish, makhana, gond, premium dry fruits',
   'mewa,dry fruits,dryfruits,kaaju,kaju,cashew,almond,badam,akhrot,walnut,pista,pistachio,kishmish,raisin,munakka,anjeer,fig,khajoor,dates,chironji,makhana,gond,gond ke laddu,chilgoza,supari,desi mewa,kashmiri mewa,iranian mewa,wholesale mewa'),

  ('namkeen-snacks',
   'Namkeen / Bhujia / Snacks Shop',
   'नमकीन / भुजिया',
   '🍿', 524,
   'Bikaneri bhujia, namkeen, chips, mathri, sev, gathiya, papdi, snacks, mukhwaas, churan, pickles retail',
   'namkeen,bhujia,bikaneri bhujia,sev,gathiya,gathia,mathri,mathiya,papdi,chivda,chivada,khari,nimki,dalmoth,churan,chataka,chaat masala,papad,achar,pickle,mukhwaas,saunf,supari mix,desi snacks,snacks shop,paan masala'),

  ('sofa-set',
   'Sofa Set / Furniture Showroom',
   'सोफा सेट / फर्नीचर शोरूम',
   '🛋️', 525,
   'Sofa set, recliner, dining table, double bed, wardrobe, modular furniture, sectional sofa, designer furniture sales',
   'sofa,sofa set,3+2 sofa,recliner,l shape sofa,sectional sofa,leather sofa,fabric sofa,dining table,khane ki table,double bed,king size bed,wardrobe,almirah,modular kitchen,furniture showroom,nilkamal,godrej interio,evok,wakefit,urban ladder,pepperfry,kurlon,bonnel,designer furniture'),

  ('glass-mirror',
   'Glass / Mirror Shop',
   'शीशा / आइना की दुकान',
   '🪞', 526,
   'Window glass, mirror, toughened glass, frosted glass, glass cutting, mirror fitting, shower partition, glass dealer',
   'glass shop,glass dealer,sheesha,sheeshe wala,kanch,mirror,aaina,aina,toughened glass,frosted glass,frost glass,window glass,sliding window,shower partition,glass partition,glass cutting,mirror fitting,glass installation,wall mirror,full length mirror,framed mirror,decor mirror'),

  ('sofa-furniture',
   'Office / Office Furniture',
   'ऑफिस फर्नीचर',
   '🗄️', 527,
   'Office chair, conference table, executive desk, reception counter, filing cabinet, partition, ergonomic chair, mesh chair',
   'office furniture,office chair,executive chair,revolving chair,mesh chair,ergonomic chair,conference table,boardroom table,reception counter,counter,partition,office partition,workstation,executive desk,study table,filing cabinet,office cabinet,steel almirah office'),

  ('mithai-wholesale',
   'Mithai Wholesale / Halwai Supplier',
   'मिठाई होलसेल',
   '🧁', 528,
   'Wholesale mithai, marriage caterer supplier, mawa, paneer, ghee bulk, sweets in tin, marriage halwai, festival bulk supply',
   'mithai wholesale,wholesale halwai,bulk mithai,marriage mithai,shaadi ki mithai,sweets supplier,mawa,khoya,paneer wholesale,ghee bulk,desi ghee bulk,dabba mithai,gulab jamun bulk,laddoo bulk,burfi bulk,kaju katli bulk,festival mithai,diwali mithai,rakhi mithai,bhaiya dooj'),

  ('gift-bouquet',
   'Gift Shop / Flower Bouquet',
   'गिफ्ट शॉप / फूल बुके',
   '🎁', 529,
   'Gift items, bouquets, flower delivery, chocolates, return gifts, anniversary gift, birthday gift, gift hampers, corporate gifting',
   'gift,gift shop,bouquet,phool bouquet,flower bouquet,flower delivery,phool wala,rose bouquet,birthday gift,anniversary gift,return gift,corporate gift,gift hamper,chocolate hamper,wedding gift,gift item,gifting,custom gift,personalized gift,photo frame gift')

) AS t(slug,name,name_hi,icon,sort_order,description,keywords)
CROSS JOIN parent p
ON CONFLICT (slug) DO UPDATE
  SET name = EXCLUDED.name,
      name_hi = EXCLUDED.name_hi,
      icon = EXCLUDED.icon,
      description = EXCLUDED.description,
      keywords = EXCLUDED.keywords,
      parent_id = EXCLUDED.parent_id,
      active = TRUE;


-- ============================================================
-- 2) HOME SERVICES (3)
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'home-services')
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order, description, keywords,
  parent_id, default_listing_type, active
)
SELECT t.slug, t.name, t.name_hi, t.icon, '#0EA5E9', t.sort_order,
       t.description, t.keywords, p.id, 'service', TRUE
FROM (VALUES
  ('aluminum-fabricator',
   'Aluminium Fabricator / Window Maker',
   'एल्युमिनियम फेब्रिकेटर',
   '🪟', 230,
   'Aluminium windows, sliding doors, mosquito mesh, ACP cladding, glass partition fabrication, false ceiling',
   'aluminum fabricator,aluminium fabricator,aluminium windows,sliding windows,sliding door,french door,mosquito mesh,mosquito net,acp cladding,acp sheet,glass partition,kanch ki partition,fabrication,window fabricator,louver,louvre,sliding'),

  ('iron-grills',
   'Iron Grills / Steel Gate Maker',
   'लोहे की ग्रिल / गेट',
   '🚪', 231,
   'Iron grills, steel gates, railing, balcony grill, window grill, MS fabrication, gate fitting, decorative grill, jali',
   'iron grill,steel gate,jangla,lohey ki grill,railing,balcony grill,window grill,ms fabrication,mild steel,wrought iron,decorative grill,jali,jaali,gate maker,gate fitter,boundary wall gate,sliding gate,main gate,iron stairs,iron stair railing'),

  ('refrigerator-washing-repair',
   'Refrigerator / Washing Machine Repair',
   'फ्रिज / वॉशिंग मशीन रिपेयर',
   '🧺', 232,
   'Refrigerator service, washing machine repair, microwave repair, dishwasher service, geyser repair, white goods technician',
   'refrigerator repair,fridge repair,washing machine repair,washing machine service,front load,top load,microwave repair,oven repair,dishwasher,geyser repair,water heater repair,white goods,whirlpool service,samsung service,lg service,godrej service,videocon,onida,ifb,bosch')

) AS t(slug,name,name_hi,icon,sort_order,description,keywords)
CROSS JOIN parent p
ON CONFLICT (slug) DO UPDATE
  SET name = EXCLUDED.name,
      name_hi = EXCLUDED.name_hi,
      icon = EXCLUDED.icon,
      description = EXCLUDED.description,
      keywords = EXCLUDED.keywords,
      parent_id = EXCLUDED.parent_id,
      active = TRUE;


-- ============================================================
-- 3) HEALTHCARE (1)
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'healthcare')
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order, description, keywords,
  parent_id, default_listing_type, active
)
SELECT t.slug, t.name, t.name_hi, t.icon, '#0EA5E9', t.sort_order,
       t.description, t.keywords, p.id, 'shop', TRUE
FROM (VALUES
  ('hearing-aid-mobility',
   'Hearing Aid / Mobility Aids',
   'श्रवण यंत्र / सहायक उपकरण',
   '🦽', 92,
   'Hearing aid, wheelchair, walking stick, walker, hospital bed rental, crutches, BP machine, glucometer, surgical, mobility products',
   'hearing aid,kaan ki machine,kaan ka yantra,hearing machine,wheelchair,wheel chair,walking stick,chhadi,walker,crutch,baisaakhi,hospital bed,bed rental,patient bed,oxygen cylinder,bp machine,blood pressure machine,glucometer,surgical store,medical equipment,mobility aid,cpap')

) AS t(slug,name,name_hi,icon,sort_order,description,keywords)
CROSS JOIN parent p
ON CONFLICT (slug) DO UPDATE
  SET name = EXCLUDED.name,
      name_hi = EXCLUDED.name_hi,
      icon = EXCLUDED.icon,
      description = EXCLUDED.description,
      keywords = EXCLUDED.keywords,
      parent_id = EXCLUDED.parent_id,
      active = TRUE;


-- ============================================================
-- 4) PROFESSIONAL SERVICES (1)
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'professional-services')
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order, description, keywords,
  parent_id, default_listing_type, active
)
SELECT t.slug, t.name, t.name_hi, t.icon, '#1E40AF', t.sort_order,
       t.description, t.keywords, p.id, 'professional', TRUE
FROM (VALUES
  ('drone-prewedding-photo',
   'Drone / Pre-Wedding Photography',
   'ड्रोन / प्री-वेडिंग फोटो',
   '🚁', 560,
   'Drone photography, pre-wedding shoot, candid wedding photos, destination wedding, ariel shoot, cinematic videography, baby shoot',
   'drone photography,drone shoot,pre wedding,prewedding shoot,pre-wedding shoot,candid wedding,destination wedding,cinematic wedding,wedding cinematography,aerial shoot,maternity shoot,baby shoot,newborn shoot,fashion shoot,product shoot,model shoot,event drone,reels videography,wedding reel,short film')

) AS t(slug,name,name_hi,icon,sort_order,description,keywords)
CROSS JOIN parent p
ON CONFLICT (slug) DO UPDATE
  SET name = EXCLUDED.name,
      name_hi = EXCLUDED.name_hi,
      icon = EXCLUDED.icon,
      description = EXCLUDED.description,
      keywords = EXCLUDED.keywords,
      parent_id = EXCLUDED.parent_id,
      active = TRUE;


-- ============================================================
-- 5) AUTOMOTIVE (1)
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'automotive')
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order, description, keywords,
  parent_id, default_listing_type, active
)
SELECT t.slug, t.name, t.name_hi, t.icon, '#0EA5E9', t.sort_order,
       t.description, t.keywords, p.id, 'shop', TRUE
FROM (VALUES
  ('generator-dg-set',
   'Generator / DG Set Sales / Rental',
   'जनरेटर / DG सेट',
   '⚙️', 293,
   'Diesel generator, silent DG set, portable generator, generator on rent, kirloskar, mahindra, cummins, AMC, repair, fuel filter',
   'generator,jenerator,dg set,diesel generator,silent generator,silent dg,portable generator,inverter generator,kirloskar,cummins,mahindra powerol,ashok leyland,birla,honda generator,generator on rent,rent generator,event generator,wedding generator,industrial generator,gen set,genset,amc')

) AS t(slug,name,name_hi,icon,sort_order,description,keywords)
CROSS JOIN parent p
ON CONFLICT (slug) DO UPDATE
  SET name = EXCLUDED.name,
      name_hi = EXCLUDED.name_hi,
      icon = EXCLUDED.icon,
      description = EXCLUDED.description,
      keywords = EXCLUDED.keywords,
      parent_id = EXCLUDED.parent_id,
      active = TRUE;


-- ============================================================
-- VERIFY
-- ============================================================
DO $$
DECLARE
  v_n INT;
BEGIN
  SELECT COUNT(*) INTO v_n FROM categories WHERE slug IN (
    'handloom-shop','music-instruments','sports-goods','mewa-dryfruits',
    'namkeen-snacks','sofa-set','glass-mirror','sofa-furniture',
    'mithai-wholesale','gift-bouquet',
    'aluminum-fabricator','iron-grills','refrigerator-washing-repair',
    'hearing-aid-mobility','drone-prewedding-photo','generator-dg-set'
  );
  RAISE NOTICE '✅ New categories present: % of 16', v_n;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;
