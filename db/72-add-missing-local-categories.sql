-- =====================================================
-- db/72-add-missing-local-categories.sql
-- =====================================================
-- USER REQUEST (2026-05-28):
--   "Kuch aur categories add karni hai — Bistar Bhandar, R.O, A.C Repair,
--    agar nahi hai to add karni, aur bhi missing categories add kro."
--
-- AUDIT FINDING:
--   AC repair (ac-repair) and RO (ro-repair) already exist in home-services.
--   But many common local Indian shop types were genuinely missing.
--
-- THIS PATCH adds 27 missing local categories across 9 parents:
--   • Retail-shopping (7): bistar-bhandar, mattress-shop, ro-aquaguard-sales,
--                          plant-nursery, pet-shop, scrap-kabadi, old-furniture
--   • Home-services (3):   cctv-camera, almirah-maker, water-tank-cleaning
--   • Beauty-wellness (1): dietician
--   • Education (4):       driving-school, computer-class, music-dance-class,
--                          art-craft-class
--   • Professional (5):    csc-aadhaar, travel-agent, astrologer-pandit,
--                          marriage-bureau, visa-passport
--   • Financial (1):       loan-agent
--   • Community (1):       hostel-pg
--   • Food-beverage (2):   pan-shop, honey-ghee-organic
--   • Automotive (3):      petrol-pump, battery-shop, vehicle-rental
--
-- All inserts are idempotent (ON CONFLICT (slug) DO UPDATE), safe to re-run.
-- Each row has rich keywords (English + Hindi + local Hinglish terms) so
-- search picks them up.
-- =====================================================

BEGIN;

-- =====================================================
-- Helper macro: insert sub under parent slug
-- (using CTE pattern matching db/65)
-- =====================================================

-- ============================================================
-- 1) RETAIL & SHOPPING — 7 new categories
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'retail-shopping')
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order, description, keywords,
  parent_id, default_listing_type, active
)
SELECT t.slug, t.name, t.name_hi, t.icon, '#9333EA', t.sort_order,
       t.description, t.keywords, p.id, 'shop', TRUE
FROM (VALUES
  ('bistar-bhandar',
   'Bistar Bhandar / Razai-Gadda Shop',
   'बिस्तर भंडार / रजाई-गद्दा',
   '🛏️', 510,
   'Razai, gadda, takiya, chaadar, bedsheet, blanket, kambal, double bed cover, pillow cover, comforter',
   'bistar,bistar bhandar,razai,rajai,gadda,gaddha,takiya,pillow,chaadar,bedsheet,bed sheet,blanket,kambal,comforter,double bed,pillow cover,quilt,duvet,foam,rui,cotton bed,kapra dukan'),

  ('mattress-shop',
   'Mattress / Foam Mattress Shop',
   'मैट्रेस / फोम गद्दा',
   '🛌', 511,
   'Sleepwell, Kurlon, Duroflex, Centuary mattress dealer, coir mattress, spring mattress, foam mattress, orthopedic',
   'mattress,mattres,gadda,foam mattress,coir mattress,spring mattress,sleepwell,kurlon,duroflex,centuary,recron,orthopedic,memory foam,latex,bonnel spring,pocket spring,king size,queen size,single bed,double bed'),

  ('ro-aquaguard-sales',
   'RO / Aquaguard Sales Showroom',
   'RO / एक्वागार्ड शोरूम',
   '💧', 512,
   'Kent RO, Aquaguard, Pureit, Livpure, Eureka Forbes — water purifier sales, installation, AMC',
   'ro sales,ro shop,aquaguard,kent ro,pureit,livpure,eureka forbes,bluestar ro,water purifier,water filter,uv,uf,ro install,ro service,amc,pani ki machine,paani saaf,domestic ro,commercial ro'),

  ('plant-nursery',
   'Plant Nursery / Garden Centre',
   'पौधा नर्सरी / गार्डन सेंटर',
   '🌱', 513,
   'Indoor plants, outdoor plants, seeds, pots, garden tools, lawn care, fertilizer, manure, bonsai, flowering plants',
   'nursery,plant nursery,pode,paudh,pediya,garden centre,pots,gamla,gamle,bonsai,indoor plants,outdoor plants,flowering plants,fruit plants,rose,gulab,money plant,tulsi,money tree,khaad,fertilizer organic,seeds,beej,bagicha'),

  ('pet-shop',
   'Pet Shop / Aquarium',
   'पेट शॉप / एक्वेरियम',
   '🐕', 514,
   'Dog food, cat food, bird cage, aquarium, fish tank, fish feed, pet accessories, leash, dog collar, kennel',
   'pet shop,pet store,dog,kutta,cat,billi,bird,parrot,aquarium,fish tank,machli,goldfish,dog food,pedigree,royal canin,whiskas,cat food,bird cage,pinjra,pet accessories,leash,collar,kennel,vet supplies'),

  ('scrap-kabadi',
   'Scrap / Kabadi / Old Material',
   'कबाड़ी / पुराना सामान',
   '♻️', 515,
   'Kabadi wala, scrap dealer, old newspaper, old iron, copper, brass, aluminium, e-waste, raddi, plastic scrap',
   'scrap,kabadi,kabaadi,kabadiwala,raddi,old newspaper,akhbar,puraana,old iron,loha,copper,tamba,brass,pital,aluminium,e-waste,electronics scrap,plastic scrap,metal scrap,recycling,puraana saamaan'),

  ('old-furniture',
   'Old / Second-Hand Furniture',
   'पुराना फर्नीचर / सेकंड-हैंड',
   '🪑', 516,
   'Used furniture buyer & seller, second-hand sofa, bed, almirah, dining table, used office furniture, resale',
   'old furniture,used furniture,second hand furniture,puraana furniture,used sofa,old bed,puraani almirah,used dining table,resale furniture,furniture exchange,second hand,puraani cheez,office furniture used,godown clearance')

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
-- 2) HOME SERVICES — 3 new categories
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'home-services')
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order, description, keywords,
  parent_id, default_listing_type, active
)
SELECT t.slug, t.name, t.name_hi, t.icon, '#0EA5E9', t.sort_order,
       t.description, t.keywords, p.id, 'service', TRUE
FROM (VALUES
  ('cctv-camera',
   'CCTV / Security Camera Installation',
   'CCTV / सुरक्षा कैमरा',
   '📹', 220,
   'CCTV installation, security camera, DVR, NVR, IP camera, dome camera, bullet camera, video door phone, AMC',
   'cctv,cc tv,security camera,nigrani camera,suraksha camera,camera installation,dvr,nvr,ip camera,hikvision,cp plus,dahua,godrej cctv,dome camera,bullet camera,video door phone,intercom,access control,biometric,kachra camera'),

  ('almirah-maker',
   'Steel / Aluminum Almirah / Wardrobe',
   'स्टील / एल्युमिनियम अलमारी',
   '🪟', 221,
   'Steel almirah, aluminum wardrobe maker, modular wardrobe, sliding door, drawer, kitchen cabinet, locker',
   'almirah,almari,steel almirah,wardrobe,aluminum wardrobe,sliding wardrobe,modular wardrobe,kitchen cabinet,locker,steel locker,godrej almirah,trunk,box,drawer,steel box,saamaan rakhne,kapde almari'),

  ('water-tank-cleaning',
   'Water Tank / Sump Cleaning',
   'पानी की टंकी सफाई',
   '🚰', 222,
   'Overhead tank cleaning, underground sump cleaning, RO storage cleaning, sanitization, mechanized cleaning',
   'water tank cleaning,pani ki tanki,tanki safai,sump cleaning,underground tank,overhead tank,plastic tank,sintex,syntex,sanitisation,bacteria removal,mechanized cleaning,housekeeping')

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
-- 3) BEAUTY & WELLNESS — 1 new category
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'beauty-wellness')
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order, description, keywords,
  parent_id, default_listing_type, active
)
SELECT t.slug, t.name, t.name_hi, t.icon, '#EC4899', t.sort_order,
       t.description, t.keywords, p.id, 'professional', TRUE
FROM (VALUES
  ('dietician',
   'Dietician / Nutritionist',
   'डायटीशियन / पोषण विशेषज्ञ',
   '🥗', 380,
   'Diet plan, weight loss, weight gain, PCOS, diabetes diet, thyroid diet, sports nutrition, child nutrition, online consultation',
   'dietician,dietitian,nutritionist,diet,weight loss,vajan kam,weight gain,vajan badhana,motapa,obesity,pcos,thyroid,diabetes diet,sugar control,bp diet,cholesterol,diet chart,sports nutrition,child nutrition,bal pushti,diet consultation')

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
-- 4) EDUCATION — 4 new categories
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'education')
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order, description, keywords,
  parent_id, default_listing_type, active
)
SELECT t.slug, t.name, t.name_hi, t.icon, '#7C3AED', t.sort_order,
       t.description, t.keywords, p.id, 'service', TRUE
FROM (VALUES
  ('driving-school',
   'Driving School / RTO Training',
   'ड्राइविंग स्कूल / RTO',
   '🚙', 460,
   'Car driving lessons, two-wheeler training, learning license, permanent DL, RTO agent, fitness test',
   'driving school,driving class,car driving,bike driving,scooty,gaadi seekhna,learning license,permanent license,driving licence,dl,rto,rto agent,fitness test,driving test,driving instructor,maruti driving school,automatic car training'),

  ('computer-class',
   'Computer Class / Tally / Typing',
   'कंप्यूटर क्लास / Tally / टाइपिंग',
   '💻', 461,
   'Basic computer course, MS Office, Tally, GST, typing class, DTP, hardware course, Photoshop, Excel',
   'computer class,computer course,basic computer,ms office,word,excel,powerpoint,tally,tally erp,tally prime,gst course,accounting,typing class,hindi typing,english typing,dtp,desktop publishing,photoshop,coreldraw,hardware course,ccc'),

  ('music-dance-class',
   'Music / Singing / Dance Class',
   'संगीत / नृत्य कक्षा',
   '🎵', 462,
   'Singing class, instrument training, classical music, harmonium, tabla, guitar, keyboard, dance class, bharatanatyam, kathak, bollywood',
   'music class,singing class,music school,sangeet,gana sikhana,vocal,classical music,harmonium,tabla,sitar,flute,guitar,bass guitar,electric guitar,keyboard,piano,casio,drum,dance class,dance school,nritya,bharatanatyam,kathak,kathak,bollywood dance,western dance,zumba,salsa,hip hop'),

  ('art-craft-class',
   'Art / Craft / Drawing Class',
   'कला / शिल्प / ड्राइंग कक्षा',
   '🎨', 463,
   'Drawing class, painting, sketching, pottery, calligraphy, mehndi class, candle making, craft, kids art',
   'art class,drawing class,painting class,sketching,kids art,art school,kala kendra,calligraphy,sulekh,mehndi class,henna,pottery class,clay,candle making,soap making,resin art,art and craft,kala kshetra,fashion design class,interior design class')

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
-- 5) PROFESSIONAL SERVICES — 5 new categories
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'professional-services')
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order, description, keywords,
  parent_id, default_listing_type, active
)
SELECT t.slug, t.name, t.name_hi, t.icon, '#1E40AF', t.sort_order,
       t.description, t.keywords, p.id, 'service', TRUE
FROM (VALUES
  ('csc-aadhaar',
   'CSC / Aadhaar / PAN Centre',
   'CSC / आधार / पैन केंद्र',
   '🪪', 550,
   'Aadhaar update, PAN card apply, bill payment, recharge, government scheme, CSC Jan Seva Kendra, passport application',
   'csc,jan seva kendra,common service centre,aadhaar,adhar card,aadhar update,pan card,pan apply,pan correction,nsdl,utiitsl,bill payment,electricity bill,recharge,mobile recharge,dth recharge,government scheme,pmjay,ayushman card,fasli loan,ration card,birth certificate,caste certificate'),

  ('travel-agent',
   'Tour & Travel / Bus-Train Booking',
   'टूर ट्रैवल / बस-ट्रेन बुकिंग',
   '✈️', 551,
   'Tour package, hotel booking, flight ticket, train ticket, bus ticket, taxi booking, visa, package tour, religious tour',
   'travel agent,tour and travel,tour package,trip,holiday,vacation,honeymoon,family tour,flight ticket,plane ticket,hawai jahaaj,train ticket,railway ticket,irctc agent,tatkal,bus booking,volvo,sleeper bus,ac bus,taxi booking,cab,car hire,outstation,religious tour,char dham,vaishno devi,goa tour,manali,shimla'),

  ('astrologer-pandit',
   'Astrologer / Pandit ji',
   'ज्योतिषी / पंडित जी',
   '🔮', 552,
   'Janam kundli, horoscope, marriage matching, vastu, palmistry, numerology, gemstone, puja, havan, religious ceremony',
   'astrologer,jyotish,jyotishi,pandit,panditji,pandit ji,acharya,maharaj ji,kundli,janam patri,horoscope,janam kundli,marriage matching,kundli milan,gun milan,vastu,vaastu,palmistry,hast rekha,numerology,ank shastra,gemstone,nag mani,puja,havan,ganesh puja,satyanarayan,grah pravesh,vivah,wedding pandit'),

  ('marriage-bureau',
   'Marriage Bureau / Matchmaker',
   'विवाह ब्यूरो / रिश्ता',
   '💑', 553,
   'Matrimonial services, marriage bureau, rishtey, life partner, biodata, profile match, second marriage, NRI match, community-based',
   'marriage bureau,vivah,shaadi,rishta,rishtey,life partner,jeevan saathi,jodi,matrimonial,bio data,biodata,profile,matchmaker,shaadi.com,bharat matrimony,jeevansathi,community match,gotra,kundli match,second marriage,divyang marriage,nri marriage,inter caste,arrange marriage'),

  ('visa-passport',
   'Visa / Passport / Immigration',
   'वीजा / पासपोर्ट / इमिग्रेशन',
   '🛂', 554,
   'Passport application, visa filing, immigration consultant, student visa, work visa, PR, Canada PR, IELTS, study abroad',
   'visa,passport,passport apply,immigration,immigration consultant,study abroad,canada pr,australia pr,uk visa,usa visa,schengen visa,uae visa,saudi visa,gulf country,work visa,student visa,tourist visa,business visa,ielts,toefl,pte,foreign jaana,videsh,visa stamping,permanent residency')

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
-- 6) FINANCIAL SERVICES — 1 new category
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'financial-services')
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order, description, keywords,
  parent_id, default_listing_type, active
)
SELECT t.slug, t.name, t.name_hi, t.icon, '#10B981', t.sort_order,
       t.description, t.keywords, p.id, 'professional', TRUE
FROM (VALUES
  ('loan-agent',
   'Loan Agent / DSA (Home, Car, Personal)',
   'लोन एजेंट / DSA',
   '💸', 660,
   'Personal loan, home loan, car loan, business loan, education loan, mortgage, balance transfer, loan against property, gold loan',
   'loan agent,loan dealer,loan dsa,dsa,bank loan,home loan,housing loan,car loan,vehicle loan,personal loan,p loan,pl,business loan,msme loan,mudra loan,education loan,property loan,lap,loan against property,gold loan,bajaj finance,hdfc loan,sbi loan,icici loan,axis loan,kotak loan,balance transfer,top up loan,loan transfer')

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
-- 7) COMMUNITY & SOCIAL — 1 new category (Hostel/PG)
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'community-social')
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order, description, keywords,
  parent_id, default_listing_type, active
)
SELECT t.slug, t.name, t.name_hi, t.icon, '#F59E0B', t.sort_order,
       t.description, t.keywords, p.id, 'service', TRUE
FROM (VALUES
  ('hostel-pg',
   'Hostel / PG / Paying Guest',
   'हॉस्टल / PG',
   '🏘️', 770,
   'Boys hostel, girls hostel, PG accommodation, student hostel, working women PG, food + lodging, mess included',
   'hostel,boys hostel,girls hostel,ladies hostel,pg,paying guest,student hostel,working womens hostel,working mens hostel,mess included,food and lodging,lodge,room rent,bachelor accommodation,ac room,non ac room,sharing,single room,monthly rent,kothi pg')

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
-- 8) FOOD & BEVERAGE — 2 new categories
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'food-beverage')
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order, description, keywords,
  parent_id, default_listing_type, active
)
SELECT t.slug, t.name, t.name_hi, t.icon, '#DC2626', t.sort_order,
       t.description, t.keywords, p.id, 'shop', TRUE
FROM (VALUES
  ('pan-shop',
   'Pan / Tobacco / Cigarette Shop',
   'पान / तंबाकू की दुकान',
   '🚬', 880,
   'Pan shop, betel leaf, gutka, supari, cigarette, bidi, lighter, mouth freshener, candy, chocolate, cold drink',
   'pan shop,paan,paan dukan,paan ki dukan,pan wala,pan dukan,betel leaf,paan masala,gutka,gutkha,supari,raja,kamla pasand,vimal,rajnigandha,cigarette,cigret,marlboro,wills,classic,gold flake,bidi,beedi,bombay paan,banarasi paan,meetha paan,sada paan,zafrani paan,mouth freshener,saunf,lighter,matchbox'),

  ('honey-ghee-organic',
   'Honey / Pure Ghee / Organic Products',
   'शहद / देसी घी / जैविक उत्पाद',
   '🍯', 881,
   'Pure desi ghee, raw honey, organic products, A2 cow milk, jaggery, gud, organic atta, cold-pressed oil, sahad',
   'honey,sahad,shahad,desi ghee,pure ghee,gir cow ghee,a2 ghee,a2 milk,desi gay ka doodh,bilona ghee,raw honey,multifloral honey,jamun honey,acacia honey,organic,jaivik,jaggery,gud,gur,organic atta,sattu,cold pressed oil,ghani ka tel,til oil,mustard oil,sarson tel,coconut oil,homemade,village products,desi product')

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
-- 9) AUTOMOTIVE — 3 new categories
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'automotive')
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order, description, keywords,
  parent_id, default_listing_type, active
)
SELECT t.slug, t.name, t.name_hi, t.icon, '#0EA5E9', t.sort_order,
       t.description, t.keywords, p.id, 'shop', TRUE
FROM (VALUES
  ('petrol-pump',
   'Petrol / Diesel Pump',
   'पेट्रोल पंप',
   '⛽', 290,
   'Petrol pump, diesel station, CNG, Indian Oil, BPCL, HPCL, Reliance, Nayara, Shell, fuel filling station',
   'petrol pump,petrol station,diesel pump,fuel station,filling station,cng,cng station,indian oil,iocl,bpcl,hpcl,reliance petrol,nayara,shell,gas station,petroleum,tel pump,deepak petrol,fuel'),

  ('battery-shop',
   'Car / Inverter Battery Shop',
   'बैटरी की दुकान',
   '🔋', 291,
   'Exide, Amaron, Luminous, Microtek battery dealer, car battery, two-wheeler battery, inverter battery, UPS battery, AMC',
   'battery shop,battery dealer,car battery,bike battery,scooter battery,inverter battery,ups battery,tubular battery,exide,amaron,luminous,microtek,sf sonic,livguard,okaya,solar battery,e-rickshaw battery,battery service,battery old change'),

  ('vehicle-rental',
   'Car / Bike Rental',
   'कार / बाइक किराये पर',
   '🚙', 292,
   'Self-drive car, rental car, bike rental, scooty rental, taxi for outstation, marriage car, luxury car rent, mini bus',
   'car rental,car on rent,self drive,bike rental,scooty rental,activa rental,bullet rental,royal enfield rent,marriage car,wedding car,luxury car,bmw rental,audi rental,fortuner rental,innova rental,ertiga rental,tempo traveller,mini bus,sumo rental,outstation taxi,airport taxi,driver wala car')

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
  v_added INT;
BEGIN
  SELECT COUNT(*) INTO v_added FROM categories WHERE slug IN (
    'bistar-bhandar','mattress-shop','ro-aquaguard-sales','plant-nursery','pet-shop',
    'scrap-kabadi','old-furniture',
    'cctv-camera','almirah-maker','water-tank-cleaning',
    'dietician',
    'driving-school','computer-class','music-dance-class','art-craft-class',
    'csc-aadhaar','travel-agent','astrologer-pandit','marriage-bureau','visa-passport',
    'loan-agent',
    'hostel-pg',
    'pan-shop','honey-ghee-organic',
    'petrol-pump','battery-shop','vehicle-rental'
  );
  RAISE NOTICE '✅ Added/upserted: % of 27 new local categories', v_added;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;
