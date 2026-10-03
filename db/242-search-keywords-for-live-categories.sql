-- ============================================================
-- db/242 — search words for the categories that have shops
-- ============================================================
--
-- Full-site review, 2026-09-29. search_businesses matches a query
-- against categories.keywords (db/57), and that column is the only
-- place a customer's own word — "dawai", "mistri", "AC repair" — can
-- meet the shop. Live count: 439 categories, 165 with keywords, and
-- 92 of the 164 categories that actually HAVE shops carry none.
-- Measured from the live site:
--   "AC repair"  → 0 results   (ac-repair is named "AC / Fridge Repair";
--                               'ac repair' is not a substring of that)
--   "दवाई"       → 0 results   (pharmacy's keywords are Latin only, and
--                               its name_hi is "मेडिकल स्टोर")
--   "electrician"→ 1 result    (a shop whose name happens to contain it)
--
-- This fills keywords for every shop-bearing category that has none,
-- and appends Devanagari to a few high-traffic ones that already had
-- Latin words. Only empty keywords are written; nothing that exists is
-- overwritten. Devanagari is included because people in Dabwali type
-- both scripts, and search lower-cases and substring-matches, so
-- "दवा" hits "दवाई, दवा की दुकान".
--
-- Safe to re-run.
-- ============================================================

BEGIN;

CREATE TEMP TABLE _kw (slug TEXT, kw TEXT);
INSERT INTO _kw VALUES
  -- ---------- home & repair ----------
  ('ac-repair',              'ac repair,ac service,ac gas,ac installation,ac mechanic,split ac,window ac,fridge repair,ac mistri,एसी रिपेयर,एसी मैकेनिक,फ्रिज रिपेयर'),
  ('mobile-repair',          'mobile repair,phone repair,screen replace,display change,battery change,charging port,software,unlock,mobile mistri,मोबाइल रिपेयर,फोन ठीक'),
  ('computer-laptop-repair', 'computer repair,laptop repair,pc repair,formatting,windows install,laptop service,motherboard,keyboard,ssd upgrade,कंप्यूटर रिपेयर,लैपटॉप रिपेयर'),
  ('carpenter',              'carpenter,badhai,furniture repair,wood work,door,almirah,kitchen cabinet,modular kitchen,plywood work,बढ़ई,कारपेंटर,लकड़ी का काम'),
  ('puncture-shop',          'puncture,tyre puncture,tubeless puncture,air fill,wheel balancing,alignment,पंचर,टायर पंचर'),
  ('spare-parts',            'spare parts,auto parts,bike parts,car parts,genuine parts,spares,पार्ट्स,स्पेयर पार्ट्स'),
  ('mechanic-2w',            'bike mechanic,scooter mechanic,activa repair,bike service,two wheeler repair,bike garage,mechanic,बाइक मैकेनिक,स्कूटर रिपेयर'),
  ('mechanic-4w',            'car mechanic,car repair,car service,car garage,denting painting,four wheeler repair,mechanic,कार मैकेनिक,कार रिपेयर,गाड़ी ठीक'),
  ('tyre-shop',              'tyre,tyre shop,tyres,mrf,ceat,apollo,jk tyre,tube,wheel,alloy,टायर,टायर की दुकान'),
  ('cycle-shop',             'cycle,bicycle,cycle repair,cycle shop,kids cycle,gear cycle,hero cycle,साइकिल,साइकिल रिपेयर'),
  ('transport-tempo',        'tempo,transport,loading,chota hathi,pickup,truck,goods carrier,shifting,tata ace,टेम्पो,ट्रांसपोर्ट,लोडिंग'),
  ('ev-dealer',              'electric scooter,electric bike,ev,e-rickshaw,battery scooter,ola electric,ather,tvs iqube,इलेक्ट्रिक स्कूटर,ई-रिक्शा'),
  ('new-car',                'car showroom,new car,car dealer,maruti,hyundai,tata,mahindra,car booking,कार शोरूम,नई गाड़ी'),
  ('tractor-dealer',         'tractor,tractor showroom,tractor dealer,combine,harvester,swaraj,mahindra tractor,john deere,sonalika,ट्रैक्टर,ट्रैक्टर एजेंसी'),
  ('tractor-parts',          'tractor parts,tractor spares,tractor tyre,tractor repair,ट्रैक्टर पार्ट्स,ट्रैक्टर स्पेयर'),

  -- ---------- shops ----------
  ('mobile-shop',            'mobile,mobile shop,phone,smartphone,recharge,sim,jio,airtel,vi,new mobile,samsung,vivo,oppo,realme,redmi,मोबाइल,मोबाइल की दुकान,रिचार्ज'),
  ('mobile-accessories',     'mobile accessories,cover,tempered glass,charger,earphone,headphone,cable,power bank,mobile cover,मोबाइल कवर,चार्जर,ईयरफोन'),
  ('electronics',            'electronics,tv,led tv,fridge,washing machine,ac,cooler,fan,geyser,mixer,appliances,electronic shop,इलेक्ट्रॉनिक्स,टीवी,फ्रिज,वाशिंग मशीन'),
  ('laptop-computer-sale',   'laptop,computer,desktop,pc,printer,laptop shop,computer shop,hp,dell,lenovo,लैपटॉप,कंप्यूटर'),
  ('laptop-computer-accessories','computer accessories,mouse,keyboard,pendrive,hard disk,printer ink,cartridge,laptop bag,ram,ssd,कंप्यूटर एक्सेसरीज'),
  ('general-store',          'general store,kirana,grocery,daily needs,provision,confectionery,household items,जनरल स्टोर,किराना'),
  ('stationery',             'stationery,notebook,pen,copy,register,school stationery,office stationery,files,art material,स्टेशनरी,कॉपी,पेन'),
  ('bookstore',              'book shop,books,school books,ncert,guide,competition books,novels,किताब,किताबों की दुकान,बुक डिपो'),
  ('photocopy-cyber',        'photocopy,xerox,printout,print,lamination,cyber cafe,online form,scan,csc,फोटोकॉपी,प्रिंट,ऑनलाइन फॉर्म'),
  ('gift-shop',              'gift,gift shop,gifts,birthday gift,greeting card,toys,soft toy,showpiece,गिफ्ट,तोहफा,गिफ्ट शॉप'),
  ('jewellery',              'jewellery,jeweller,gold,silver,sona,chandi,sunar,ring,chain,bangles,mangalsutra,hallmark,ज्वेलरी,सुनार,सोना,चांदी'),
  ('jewellery-imitation',    'imitation jewellery,artificial jewellery,fancy jewellery,bangles,chudi,earrings,fashion jewellery,आर्टिफिशियल ज्वेलरी,चूड़ी'),
  ('footwear-shop',          'footwear,shoes,chappal,sandal,slippers,boots,sports shoes,juti,jutti,जूते,चप्पल,फुटवियर,जूती'),
  ('readymade-garments',     'readymade,garments,clothes,shirt,jeans,t-shirt,kurti,dress,kapde,ready made,कपड़े,रेडीमेड,गारमेंट्स'),
  ('clothes',                'clothes,cloth,kapda,kapde,tailor,stitching,suit,fabric,कपड़ा,कपड़े,दर्जी,सिलाई'),
  ('cloth-merchant',         'cloth merchant,cloth house,fabric,suit piece,shirting,suiting,kapda,thaan,कपड़े का व्यापारी,कपड़ा हाउस'),
  ('kids-wear',              'kids wear,children clothes,baby clothes,bachon ke kapde,kids garments,frock,बच्चों के कपड़े,किड्स वियर'),
  ('undergarment',           'undergarments,innerwear,hosiery,banian,vest,bra,panty,lingerie,socks,अंडरगारमेंट,होज़री,बनियान'),
  ('boutique-designer',      'boutique,designer,designer suit,ladies suit,stitching,embroidery,bridal wear,बुटीक,डिजाइनर सूट'),
  ('lehenga-bridal',         'lehenga,bridal,bridal lehenga,wedding dress,dulhan,sherwani,bridal wear,लहंगा,दुल्हन,ब्राइडल'),
  ('bag-luggage',            'bag,bags,luggage,suitcase,trolley bag,school bag,backpack,purse,ladies purse,travel bag,बैग,सूटकेस,पर्स'),
  ('perfume-ittar',          'perfume,ittar,attar,deo,deodorant,scent,fragrance,body spray,परफ्यूम,इत्र,डियो'),
  ('cosmetic-shop',          'cosmetics,makeup,beauty products,lipstick,cream,shampoo,face wash,nail paint,mehndi,कॉस्मेटिक,मेकअप,श्रृंगार'),
  ('optical-shop',           'optical,spectacles,chashma,glasses,lens,contact lens,sunglasses,eye test,frame,चश्मा,ऑप्टिकल,नज़र का चश्मा'),
  ('eye-care',               'eye doctor,eye specialist,eye hospital,eye checkup,cataract,motiyabind,aankh,ophthalmologist,आंखों का डॉक्टर,नेत्र,मोतियाबिंद'),
  ('utensils-shop',          'utensils,bartan,steel bartan,crockery,kitchenware,pressure cooker,kadhai,tawa,बर्तन,बर्तन की दुकान,स्टील'),
  ('crockery-glassware',     'crockery,glassware,dinner set,cups,plates,glass,bone china,gift crockery,क्रॉकरी,कांच के बर्तन'),
  ('plastic-items',          'plastic,plastic items,bucket,tub,plastic chair,storage box,dustbin,प्लास्टिक,बाल्टी,प्लास्टिक का सामान'),
  ('home-decor',             'home decor,decoration,wall hanging,artificial flowers,curtains,parda,showpiece,home furnishing,होम डेकोर,सजावट,पर्दे'),
  ('furniture-wood',         'furniture,sofa,bed,almirah,dining table,wooden furniture,mattress,gadda,chair,फर्नीचर,सोफा,पलंग,गद्दा'),
  ('flour-mill',             'atta chakki,flour mill,chakki,atta,wheat grinding,besan,masala grinding,आटा चक्की,चक्की,आटा'),
  ('cattle-feed-shop',       'cattle feed,pashu aahar,khal,binola,feed,dairy feed,poultry feed,chokar,पशु आहार,खल,बिनौला,चोकर'),
  ('pesticide-shop',         'pesticide,spray,keetnashak,insecticide,weedicide,fungicide,crop medicine,agri chemicals,कीटनाशक,स्प्रे,दवाई खेती'),
  ('fertilizer-shop',        'fertilizer,khad,urea,dap,potash,zinc,organic manure,खाद,यूरिया,डीएपी'),
  ('seeds-shop',             'seeds,beej,seed shop,wheat seed,cotton seed,vegetable seeds,hybrid seed,बीज,बीज भंडार'),
  ('wholesale-dealer',       'wholesale,wholesaler,thok,dealer,distributor,bulk,होलसेल,थोक,डीलर'),
  ('distributor-food',       'distributor,food distributor,fmcg,stockist,supplier,biscuit distributor,namkeen supplier,डिस्ट्रीब्यूटर,सप्लायर'),
  ('gym-supplements',        'supplements,protein,whey,mass gainer,creatine,gym supplement,pre workout,सप्लीमेंट,प्रोटीन'),

  -- ---------- food & stay ----------
  ('juice-shake',            'juice,shake,milkshake,cold coffee,fruit juice,mosambi,smoothie,lassi,जूस,शेक,लस्सी'),
  ('catering-service',       'catering,caterer,halwai,shaadi ka khana,party food,tent catering,कैटरिंग,हलवाई,शादी का खाना'),
  ('hotel',                  'hotel,room,rooms,stay,lodge,ac room,delux room,hotel booking,night stay,होटल,कमरा,रूम'),
  ('guest-house-lodge',      'guest house,lodge,dharamshala,budget room,stay,rest house,गेस्ट हाउस,धर्मशाला,लॉज'),
  ('marriage-palace',        'marriage palace,palace,shaadi palace,wedding venue,banquet,function,reception,मैरिज पैलेस,शादी पैलेस'),
  ('banquet-hall',           'banquet,banquet hall,party hall,function hall,birthday party venue,reception,बैंक्वेट हॉल,पार्टी हॉल'),
  ('event-management',       'event,event management,event planner,party decoration,birthday decoration,balloon decoration,dj,इवेंट,सजावट,डेकोरेशन'),
  ('wedding-planner',        'wedding planner,shaadi planner,wedding decoration,destination wedding,mandap,वेडिंग प्लानर,शादी की तैयारी'),

  -- ---------- health & beauty ----------
  ('dentist',                'dentist,dental,dental clinic,teeth,daant,tooth pain,root canal,braces,denture,teeth cleaning,डेंटिस्ट,दांत,दांतों का डॉक्टर'),
  ('pathology-lab',          'lab,pathology,blood test,test lab,diagnostic,sugar test,thyroid test,x-ray,ultrasound,लैब,ब्लड टेस्ट,जांच'),
  ('veterinary',             'veterinary,vet,animal doctor,pashu doctor,pet doctor,dog doctor,cattle doctor,पशु डॉक्टर,जानवरों का डॉक्टर,पशु चिकित्सक'),
  ('salon',                  'salon,saloon,hair cut,haircut,barber,nai,parlour,beauty parlour,facial,hair spa,shaving,सैलून,नाई,पार्लर,हेयर कट'),
  ('gym',                    'gym,fitness,workout,bodybuilding,exercise,fitness centre,zumba,cardio,जिम,फिटनेस,कसरत'),

  -- ---------- education ----------
  ('school',                 'school,vidyalaya,cbse school,public school,convent,admission,nursery,play way,स्कूल,विद्यालय,एडमिशन'),
  ('tuition-coaching',       'tuition,coaching,tution,home tuition,class 10,class 12,maths tuition,science tuition,ट्यूशन,कोचिंग'),
  ('coaching-institute',     'coaching,institute,coaching institute,neet,jee,ssc,bank coaching,competition,entrance,कोचिंग,इंस्टीट्यूट,प्रतियोगी परीक्षा'),
  ('computer-classes',       'computer classes,computer course,computer centre,tally,dca,basic computer,typing,excel,कंप्यूटर क्लास,कंप्यूटर कोर्स'),
  ('english-speaking',       'english speaking,spoken english,ielts,pte,english course,personality development,इंग्लिश स्पीकिंग,अंग्रेजी'),
  ('library',                'library,reading room,study room,study centre,self study,pustakalaya,लाइब्रेरी,पुस्तकालय,स्टडी रूम'),

  -- ---------- professionals & money ----------
  ('property-dealer',        'property,property dealer,plot,house,makan,zameen,land,rent,kiraya,real estate,broker,प्रॉपर्टी,प्लॉट,मकान,जमीन,किराया'),
  ('architect',              'architect,naksha,house plan,map,building design,3d elevation,interior,आर्किटेक्ट,नक्शा,मकान का नक्शा'),
  ('interior-designer',      'interior,interior designer,home interior,false ceiling,modular kitchen,decoration,इंटीरियर,इंटीरियर डिजाइनर'),
  ('photographer',           'photographer,photography,wedding photography,pre wedding,video,videographer,drone,shoot,फोटोग्राफर,फोटोग्राफी,शादी की फोटो'),
  ('photo-studio',           'photo studio,passport photo,studio,photo print,photo frame,digital studio,lamination,फोटो स्टूडियो,पासपोर्ट फोटो'),
  ('florist',                'florist,flowers,phool,bouquet,flower decoration,garland,mala,rose,फूल,फूलों की दुकान,बुके'),
  ('stock-broker',           'stock broker,share market,demat,trading,shares,stock,zerodha,angel,investment,शेयर मार्केट,डीमैट,ट्रेडिंग'),
  ('financial-advisor',      'financial advisor,investment,mutual fund,sip,fd,fixed deposit,bonds,wealth,retirement plan,financial planning,निवेश,म्यूचुअल फंड,एफडी'),
  ('insurance-health',       'health insurance,mediclaim,medical insurance,star health,niva bupa,care health,cashless,हेल्थ इंश्योरेंस,मेडिक्लेम'),
  ('insurance-general',      'general insurance,car insurance,bike insurance,vehicle insurance,shop insurance,home insurance,third party,गाड़ी का बीमा,बीमा'),
  ('insurance-life',         'life insurance,lic,term plan,term insurance,jeevan bima,policy,lic agent,जीवन बीमा,एलआईसी,पॉलिसी'),
  ('builder-contractor',     'builder,contractor,thekedar,construction,house construction,makan banwana,civil contractor,building,बिल्डर,ठेकेदार,मकान बनवाना,निर्माण'),

  -- ---------- manufacturers ----------
  ('manufacturer',           'manufacturer,factory,production,unit,industry,karkhana,मैन्युफैक्चरर,फैक्ट्री,कारखाना'),
  ('manufacturer-food',      'food manufacturer,snacks factory,namkeen factory,food processing,packaged food,फूड फैक्ट्री,नमकीन फैक्ट्री'),
  ('manufacturer-textile',   'textile,garment factory,textile mill,cloth manufacturer,hosiery unit,टेक्सटाइल,कपड़ा फैक्ट्री'),
  ('manufacturer-machinery', 'machinery,machine manufacturer,agri machinery,fabrication,engineering works,मशीनरी,इंजीनियरिंग वर्क्स'),
  ('manufacturer-furniture', 'furniture factory,furniture manufacturer,sofa maker,bed manufacturer,फर्नीचर फैक्ट्री'),
  ('manufacturer-construction','construction material manufacturer,brick,bricks,eent,cement blocks,tiles factory,ईंट,भट्ठा,सीमेंट ब्लॉक'),
  ('manufacturer-electronics','electronics manufacturer,led manufacturer,led bulb,assembly,इलेक्ट्रॉनिक्स फैक्ट्री'),
  ('manufacturer-cosmetic',  'cosmetic manufacturer,soap factory,personal care manufacturer,detergent,कॉस्मेटिक फैक्ट्री,साबुन');

-- Fill only where empty.
UPDATE public.categories c
   SET keywords = k.kw
  FROM _kw k
 WHERE c.slug = k.slug
   AND NULLIF(TRIM(COALESCE(c.keywords, '')), '') IS NULL;

-- Devanagari for the busiest categories that already had Latin words.
CREATE TEMP TABLE _kw_hi (slug TEXT, extra TEXT);
INSERT INTO _kw_hi VALUES
  ('pharmacy',        'दवाई,दवा,दवा की दुकान,मेडिकल,केमिस्ट'),
  ('kirana-grocery',  'किराना,किराना स्टोर,राशन,परचून,ग्रॉसरी'),
  ('sweets',          'मिठाई,हलवाई,मिठाई की दुकान,लड्डू,बर्फी'),
  ('bakery-cake',     'बेकरी,केक,पेस्ट्री,बर्थडे केक'),
  ('restaurant',      'रेस्टोरेंट,खाना,ढाबा,भोजनालय'),
  ('doctor',          'डॉक्टर,चिकित्सक,क्लिनिक,इलाज'),
  ('hospital',        'अस्पताल,हॉस्पिटल,इमरजेंसी'),
  ('electrician',     'इलेक्ट्रीशियन,बिजली मिस्त्री,बिजली का काम,वायरिंग'),
  ('plumber',         'प्लंबर,नल का काम,पाइप फिटिंग,टंकी'),
  ('dairy-farm',      'डेयरी,दूध,पनीर,दही,घी'),
  ('namkeen-snacks',  'नमकीन,भुजिया,स्नैक्स'),
  ('atm-cash',        'एटीएम,कैश,पैसे निकालना');

UPDATE public.categories c
   SET keywords = COALESCE(NULLIF(TRIM(c.keywords), ''), '') ||
                  CASE WHEN NULLIF(TRIM(COALESCE(c.keywords, '')), '') IS NULL THEN '' ELSE ',' END ||
                  h.extra
  FROM _kw_hi h
 WHERE c.slug = h.slug
   AND POSITION(split_part(h.extra, ',', 1) IN COALESCE(c.keywords, '')) = 0;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/242-search-keywords-for-live-categories.sql');
  END IF;
END $$;

COMMIT;

-- ============================================================
-- Checks. Expected: 0 shop-bearing categories without keywords,
-- and each probe returns at least one shop.
-- ============================================================
SELECT 'shop-bearing categories with no keywords' AS check,
       COUNT(*)::text AS n,
       CASE WHEN COUNT(*) = 0 THEN 'ok' ELSE 'some slugs missing from the list above' END AS result
FROM public.categories
WHERE active AND business_count > 0
  AND NULLIF(TRIM(COALESCE(keywords, '')), '') IS NULL;

SELECT q AS probe, (SELECT COUNT(*) FROM public.search_businesses(p_query => q, p_limit => 5)) AS results
FROM unnest(ARRAY['AC repair','दवाई','electrician','salon','haircut','dentist','hotel room','property','tuition','किराना']) AS q;
