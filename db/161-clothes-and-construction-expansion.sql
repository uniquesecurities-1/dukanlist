-- ============================================================
-- db/161 — Clothes split + Construction category expansion
-- ============================================================
-- Two-part category overhaul requested by Deepak:
--
-- PART A — Clothes / Tailor:
--   The single 'clothes' category ("Clothes / Tailor") is too broad —
--   a cloth merchant, a readymade garments shop, and a ladies-only
--   tailor are completely different businesses. Customer can't filter
--   correctly. Split into 7 properly-scoped sub-categories under
--   the existing 'clothes' parent:
--     • cloth-merchant         (wholesale/retail fabric dealer)
--     • garments-unstitched    (unstitched suits, dress material)
--     • garments-semi-stitched (semi-stitched kurtis, sarees)
--     • tailor-ladies          (ladies specialist tailor)
--     • tailor-gents           (gents specialist tailor)
--     • tailor-unisex          (both)
--   Plus re-parents the existing 'readymade-garments' (db/116, was
--   under retail-shopping) to sit under 'clothes' so all garment
--   types live in one logical group.
--
-- PART B — Construction expansion:
--   User specifically requested: PVC sheets, Gypsum down ceiling,
--   Construction work, Profile sheets, Angle, Cement sheet, ERW pipe.
--   Plus "check others too and update" — I've added the most-requested
--   commonly-missing items in the building-material space for the
--   Mandi Dabwali / Sirsa / Bathinda construction trade:
--     • pvc-sheet, cement-sheet, profile-sheet, erw-pipe, ms-angle,
--       gypsum-ceiling (the 6 explicitly requested)
--     • welding-fabrication, waterproofing, interior-designer,
--       aluminium-fabrication, glass-mirror-shop, borewell-tubewell,
--       civil-contractor, architect-civil-engineer (8 commonly-asked
--       service categories from owners during onboarding)
--
-- IDEMPOTENT: All INSERTs use ON CONFLICT (slug) DO UPDATE so re-running
-- only refreshes metadata. Re-parenting is done by an explicit UPDATE.
-- No business data touched — businesses already assigned to 'clothes'
-- stay there until owner re-classifies via panel/profile.
-- ============================================================

BEGIN;

-- ============================================================
-- PART A1 — Refresh the 'clothes' parent description
-- ============================================================
UPDATE categories
   SET name        = 'Clothes / Tailor / Garments',
       name_hi     = 'कपड़ा / दर्ज़ी / गारमेंट्स',
       description = 'Cloth merchant, unstitched & semi-stitched garments, readymade clothing, ladies / gents / unisex tailoring',
       keywords    = COALESCE(keywords,'') || ',cloth merchant,kapda dukaan,fabric dealer,garment,readymade,unstitched,semi stitched,tailor,darzi,ladies tailor,gents tailor,boutique,suit,saree,kurti,fashion'
 WHERE slug = 'clothes';

-- ============================================================
-- PART A2 — Add 6 new sub-categories under 'clothes'
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'clothes' LIMIT 1)
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order, description, keywords,
  parent_id, default_listing_type, active
)
SELECT t.slug, t.name, t.name_hi, t.icon, '#A855F7', t.sort_order,
       t.description, t.keywords, p.id, 'shop', TRUE
FROM (VALUES
  ('cloth-merchant',
   'Cloth Merchant (Fabric Shop)',
   'कपड़ा मर्चेंट / कपड़े की दुकान',
   '🧵', 10,
   'Wholesale & retail fabric dealer — cotton, polyester, silk, suiting, shirting, lining, plain & printed fabric by metre / thaan',
   'cloth merchant,kapda merchant,fabric shop,fabric dealer,kapda dukaan,thaan,thaan kapda,suiting,shirting,cotton,polyester,silk,linen,lining,blouse fabric,saree fabric,plain fabric,printed fabric,fashion fabric,kapde wala,kapda wholesaler'),

  ('garments-unstitched',
   'Unstitched Suits & Garments',
   'अनस्टिच्ड सूट / कपड़े',
   '👗', 20,
   'Unstitched suit pieces, dress material, dupatta with cloth, salwar-kameez fabric set — ready for tailoring',
   'unstitched,unstitched suit,unstitched garments,suit piece,suit length,dress material,salwar kameez fabric,dupatta set,sharara fabric,unstitched salwar suit,piece kapda,suit length material,fabric set,readymade dupatta,unstitched lehenga'),

  ('garments-semi-stitched',
   'Semi-Stitched Garments',
   'सेमी-स्टिच्ड गारमेंट्स',
   '🪡', 30,
   'Pre-stitched kurtis, sarees with blouse piece, lehenga with stitching pending, anarkali — needs final fit alteration',
   'semi stitched,semi-stitched,semi stitched suit,semi stitched lehenga,semi stitched anarkali,kurti semi stitched,pre stitched,saree blouse piece,fall pico saree,bridal lehenga,readymade with alteration,fitting alteration'),

  ('tailor-ladies',
   'Ladies Tailor',
   'लेडीज़ टेलर / औरतों के दर्ज़ी',
   '👚', 50,
   'Ladies specialist tailor — blouse, kurti, salwar suit, lehenga, anarkali, designer dress stitching & fall-pico',
   'ladies tailor,female tailor,aurat ka tailor,blouse stitching,kurti stitching,salwar suit stitching,lehenga stitching,anarkali stitching,designer dress,boutique,ladies darzi,silai,silai wala,silai wali,women tailor,bridal stitching,fall pico,saree fall'),

  ('tailor-gents',
   'Gents Tailor',
   'जेंट्स टेलर / आदमियों के दर्ज़ी',
   '👔', 60,
   'Gents specialist tailor — pant, shirt, kurta-pyjama, sherwani, achkan, suit stitching & alteration',
   'gents tailor,male tailor,admiyon ka tailor,pant stitching,shirt stitching,kurta pajama stitching,sherwani stitching,achkan,three piece suit,coat pant,blazer stitching,gents silai,gents darzi,men tailor,wedding sherwani,groom suit,alteration tailor'),

  ('tailor-unisex',
   'Tailor (Unisex / All Stitching)',
   'टेलर (यूनिसेक्स / सब प्रकार)',
   '✂️', 70,
   'General tailor stitching for both ladies & gents — all-rounder darzi for repair, alteration, simple stitching',
   'unisex tailor,general tailor,all stitching tailor,tailor shop,darzi,silai master,alteration tailor,repair tailor,simple stitching,both ladies gents,common tailor,village tailor,small tailor shop')

) AS t(slug, name, name_hi, icon, sort_order, description, keywords)
CROSS JOIN parent p
ON CONFLICT (slug) DO UPDATE
  SET keywords             = EXCLUDED.keywords,
      description          = EXCLUDED.description,
      parent_id            = EXCLUDED.parent_id,
      name                 = EXCLUDED.name,
      name_hi              = EXCLUDED.name_hi,
      icon                 = EXCLUDED.icon,
      sort_order           = EXCLUDED.sort_order,
      default_listing_type = EXCLUDED.default_listing_type,
      active               = TRUE;

-- ============================================================
-- PART A3 — Re-parent 'readymade-garments' under 'clothes'
-- ============================================================
-- Already exists under 'retail-shopping' (db/116). Move it so all
-- garment types live in one logical group. Slug + URL unchanged.
UPDATE categories
   SET parent_id = (SELECT id FROM categories WHERE slug = 'clothes' LIMIT 1),
       sort_order = 40,
       icon       = '🧥',
       color      = '#A855F7',
       description = 'Ready-to-wear clothing — kids, men, women apparel, jeans, t-shirts, dresses, ready stitched suits',
       keywords    = 'readymade,ready made,readymade garments,ready to wear,kids wear,mens wear,womens wear,jeans,t-shirt,shirt,dress,pant,kurti readymade,saree readymade,readymade suit,branded clothes,family store,garments shop'
 WHERE slug = 'readymade-garments';


-- ============================================================
-- PART B — Construction expansion under 'construction-material'
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'construction-material' LIMIT 1)
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order, description, keywords,
  parent_id, default_listing_type, active
)
SELECT t.slug, t.name, t.name_hi, t.icon, '#92400E', t.sort_order,
       t.description, t.keywords, p.id, t.listing_type, TRUE
FROM (VALUES
  -- ====== User explicitly requested 6 ======
  ('pvc-sheet',
   'PVC Sheet / Plastic Sheet Dealer',
   'PVC शीट / प्लास्टिक शीट',
   '🟦', 60,
   'PVC sheets — wall panel, ceiling panel, foam sheet, sunmica alternative, flex board, signboard PVC, hoarding sheet',
   'pvc sheet,plastic sheet,pvc wall panel,pvc ceiling panel,pvc foam sheet,pvc flex,foam board,flex board,signboard pvc,plastic panel,pvc dealer,pvc sheet wholesale,pvc sheet retail,sintex panel,acp alternative,plain pvc sheet',
   'shop'),

  ('cement-sheet',
   'Cement Sheet / Asbestos Roofing',
   'सीमेंट शीट / एसबेस्टस छत',
   '🏚️', 61,
   'Cement sheets, asbestos sheets, fibre cement roofing, AC sheets — corrugated roof material for sheds, godowns, factories',
   'cement sheet,asbestos sheet,fibre cement sheet,ac sheet,everest sheet,visaka,charminar,corrugated sheet,roof sheet,roofing material,shed material,godown roof,factory roof,cement roofing,industrial roof,big sheet,plain sheet,fc sheet',
   'shop'),

  ('profile-sheet',
   'Profile Sheet / Colour Coated Roofing',
   'प्रोफाइल शीट / कलर कोटेड छत',
   '🔶', 62,
   'Colour coated profile sheets, JSW, Tata, Jindal sheets — galvanized, GI, GP, GC sheets for industrial roofing, sheds, walls',
   'profile sheet,colour coated sheet,color coated sheet,ccp sheet,gi sheet,gp sheet,gc sheet,galvanized sheet,jsw sheet,tata sheet,jindal sheet,corrugated metal sheet,trapezoidal sheet,kalyani steel,metal roofing,industrial roofing,pre painted sheet,ppgi,ppgl',
   'shop'),

  ('erw-pipe',
   'ERW Pipe / GI Pipe / Steel Pipe',
   'ERW पाइप / GI पाइप',
   '🚿', 63,
   'ERW (Electric Resistance Welded) pipes, GI pipes, MS pipes, square pipe, rectangular pipe, hollow section — Tata, Jindal, Surya Roshni',
   'erw pipe,erw,gi pipe,ms pipe,steel pipe,electric resistance welded,square pipe,rectangular pipe,hollow section,structural pipe,water pipe steel,tata pipe,jindal pipe,surya roshni,apl apollo,structural tubing,industrial pipe,pipe dealer',
   'shop'),

  ('ms-angle-channel',
   'MS Angle / Channel / Flat',
   'MS एंगल / चैनल / फ्लैट',
   '📐', 64,
   'MS (mild steel) angle, channel, flat bar, square bar, round bar — for gate, grill, structure work; SAIL, JSW, Tata, Vizag',
   'ms angle,iron angle,steel angle,angle bar,m s angle,ms channel,c channel,ms flat,flat bar,square bar,round bar,structural steel,gate angle,grill angle,trusses material,fabrication material,sail steel,jindal angle,scaffolding pipe,loha,angle iron,angle dealer',
   'shop'),

  ('gypsum-ceiling',
   'Gypsum Board / False Ceiling Material',
   'जिप्सम बोर्ड / डाउन सीलिंग',
   '🏠', 65,
   'Gypsum board, Gyproc, Saint-Gobain, USG Boral, drywall, gypsum partition, false ceiling channels, accessories — material + installation service',
   'gypsum board,gypsum,gyproc,saint gobain,usg boral,armstrong ceiling,drywall,gypsum partition,gypsum ceiling,down ceiling,gypsum false ceiling,gypsum tile,suspended ceiling,plasterboard,ceiling channel,c channel,t channel,grid ceiling,office ceiling,shop ceiling,gypsum dealer,gypsum supplier',
   'shop'),

  -- ====== Similar / related — common construction trades ======
  ('welding-fabrication',
   'Welding / Steel Fabrication',
   'वेल्डिंग / स्टील फेब्रिकेशन',
   '🔥', 66,
   'Welding shop, gate maker, grill fabricator, MS fabrication, stainless steel fabrication, truss fabrication, shed fabrication',
   'welding,welder,welding shop,fabrication,fabricator,steel fabrication,iron fabrication,ms fabrication,ss fabrication,stainless steel fabrication,gate maker,gate welder,grill maker,grill welder,jangla,truss fabrication,shed fabrication,iron work,loha work,iron gate,wrought iron,welding service',
   'service'),

  ('waterproofing',
   'Waterproofing Material & Service',
   'वाटरप्रूफिंग सामग्री और सेवा',
   '💧', 67,
   'Roof waterproofing, terrace waterproofing, basement waterproofing, Dr. Fixit, Asian Smartcare, MasterSeal — material + contractor',
   'waterproofing,water proofing,roof waterproofing,terrace waterproofing,basement waterproofing,dr fixit,fixit,asian smartcare,masterseal,fosroc,sika,leak proofing,seepage treatment,leakage repair,wall seepage,roof leak,basement seepage,chhat leakage,paani band karne wala,waterproof coating,acrylic coating',
   'service'),

  ('interior-designer',
   'Interior Designer / Decorator',
   'इंटीरियर डिज़ाइनर / डेकोरेटर',
   '🛋️', 68,
   'Interior designer, home decorator, office interior, shop interior, modular kitchen designer, false ceiling designer, wallpaper, curtains',
   'interior designer,interior decorator,home decor,office interior,shop interior,modular kitchen,kitchen designer,false ceiling design,wallpaper,wall covering,curtain shop,blind shop,interior architect,home renovation,office renovation,shop renovation,interior contractor,decorator',
   'service'),

  ('aluminium-fabrication',
   'Aluminium Fabrication / Windows',
   'एल्युमिनियम फेब्रिकेशन / खिड़की',
   '🪟', 69,
   'Aluminium fabrication, aluminium windows, sliding window, UPVC window, partition, aluminium section dealer — Jindal, Hindalco',
   'aluminium fabrication,aluminium window,sliding window,upvc window,upvc door,aluminium partition,aluminium section,jindal aluminium,hindalco,glazing,aluminium gate,aluminium frame,aluminium contractor,window fabricator,glass partition,aluminium shutter,office partition,acp panel,acp dealer',
   'service'),

  ('glass-mirror-shop',
   'Glass / Mirror / Toughened Glass',
   'शीशा / दर्पण / टफन ग्लास',
   '🪞', 70,
   'Glass shop, mirror, toughened glass, tempered glass, plain glass, frosted glass, decorative glass, kaanch, glazing dealer',
   'glass shop,kaanch,glass dealer,mirror shop,sheesha,toughened glass,tempered glass,plain glass,frosted glass,coloured glass,decorative glass,glass partition,glass railing,glass door,shower cubicle,saint gobain glass,modi glass,asahi glass,kaanch wala,kaanch ki dukaan',
   'shop'),

  ('borewell-tubewell',
   'Borewell / Tubewell Drilling',
   'बोरवेल / ट्यूबवेल खुदाई',
   '⛲', 71,
   'Borewell drilling, tubewell drilling, submersible pump installation, borewell service, water boring contractor, deep boring',
   'borewell,borwell,boring,tubewell,tube well,bore well,water boring,deep boring,submersible pump,kos pump,boring wala,borewell drilling,jet drilling,rotary drilling,kheti boring,khet boring,boring contractor,water table boring,pani ka boring,pani boring',
   'service'),

  ('civil-contractor',
   'Civil / Construction Contractor',
   'सिविल / निर्माण ठेकेदार',
   '👷', 72,
   'Civil contractor, construction contractor, building contractor, RCC contractor, brickwork, plastering, complete house construction, turnkey project',
   'civil contractor,construction contractor,building contractor,rcc contractor,thekedar,construction thekedar,makaan banane wala,house construction,turnkey construction,plastering contractor,brickwork,brick work,labour contractor,raj mistri,civil work,construction work,nirman thekedar,builder,contractor,site supervisor',
   'service'),

  ('architect-civil-engineer',
   'Architect / Civil Engineer',
   'आर्किटेक्ट / सिविल इंजीनियर',
   '📐', 73,
   'Architect, civil engineer, structural engineer, building design, naksha banane wala, vastu consultant, 3D elevation, building plan approval consultant',
   'architect,civil engineer,structural engineer,naksha,naksha banana,building plan,building design,3d elevation,front elevation,vastu consultant,vastu shastra,interior architect,construction consultant,site engineer,architectural drawing,floor plan,building approval,nagar palika naksha,muncipal approval,architect consultant',
   'service')

) AS t(slug, name, name_hi, icon, sort_order, description, keywords, listing_type)
CROSS JOIN parent p
ON CONFLICT (slug) DO UPDATE
  SET keywords             = EXCLUDED.keywords,
      description          = EXCLUDED.description,
      parent_id            = EXCLUDED.parent_id,
      name                 = EXCLUDED.name,
      name_hi              = EXCLUDED.name_hi,
      icon                 = EXCLUDED.icon,
      sort_order           = EXCLUDED.sort_order,
      default_listing_type = EXCLUDED.default_listing_type,
      active               = TRUE;


NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================
-- Verification
-- ============================================================
DO $$
DECLARE
  v_clothes_subs   INT;
  v_construction_new INT;
BEGIN
  SELECT COUNT(*) INTO v_clothes_subs
    FROM categories
    WHERE parent_id = (SELECT id FROM categories WHERE slug = 'clothes')
      AND active = TRUE;
  SELECT COUNT(*) INTO v_construction_new
    FROM categories
    WHERE slug IN (
      'pvc-sheet','cement-sheet','profile-sheet','erw-pipe',
      'ms-angle-channel','gypsum-ceiling','welding-fabrication',
      'waterproofing','interior-designer','aluminium-fabrication',
      'glass-mirror-shop','borewell-tubewell','civil-contractor',
      'architect-civil-engineer'
    );
  RAISE NOTICE 'db/161 installed.';
  RAISE NOTICE '  Clothes parent now has % active sub-categories (expect 7).', v_clothes_subs;
  RAISE NOTICE '  Construction got % new sub-categories (expect 14).', v_construction_new;
END $$;
