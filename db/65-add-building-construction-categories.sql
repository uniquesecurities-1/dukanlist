-- =====================================================
-- db/65-add-building-construction-categories.sql
-- =====================================================
-- USER FEEDBACK:
--   "Paint, Hardware Products, Chuna (Kali) like categories shayad nahi hai"
--
-- ROOT CAUSE:
--   Static assets/data/categories.json already lists hardware-shop,
--   paint-shop, building-material, tiles-marble, sanitary-bathroom
--   under retail-shopping parent — but these slugs were never inserted
--   into the live `categories` table. So DB-driven dropdowns (register,
--   browse, search, admin/shop) silently miss them.
--
--   Chuna / Sariya / Plywood / Pipes / Doors-Windows etc. were missing
--   entirely from both static + DB.
--
-- WHAT THIS SQL DOES:
--   1. Create NEW parent 'construction-material' (Building & Construction)
--   2. Insert/upsert 13 sub-categories under it. Slugs that ALREADY exist
--      in static JSON (hardware-shop, paint-shop, building-material,
--      tiles-marble, sanitary-bathroom) are reused so frontend stays in sync.
--   3. NEW slugs: chuna-lime, sariya-tmt, plywood-laminate, sand-gravel,
--      pipes-fittings, electrical-hardware, doors-windows-grills, marble-granite
--   4. Rich keywords for each (Hinglish + English + local terms like
--      'kali', 'bajri', 'eet', 'jangla', 'reta', etc.) so search picks up.
--
-- ZERO RISK — additive + idempotent (ON CONFLICT updates harmlessly).
-- HOW TO RUN: Supabase Dashboard → SQL Editor → paste → Run
-- =====================================================

BEGIN;

-- ============================================================
-- 1. PARENT CATEGORY
-- ============================================================
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order, description, keywords,
  default_listing_type, active
)
VALUES (
  'construction-material',
  'Building & Construction Material',
  'भवन निर्माण सामग्री',
  '🧱',
  '#92400E',
  45,
  'Paint, hardware, cement, chuna, sariya, tiles, plywood, marble, sand, pipes — everything for house building & repair',
  'construction,building,material,nirman,makaan,ghar banana,raw material,builder supply,civil work,hardware,paint,cement,sariya,tiles,bajri,chuna,kali,plywood,marble,sanitary,pipe',
  'shop',
  TRUE
)
ON CONFLICT (slug) DO UPDATE
  SET name = EXCLUDED.name,
      name_hi = EXCLUDED.name_hi,
      icon = EXCLUDED.icon,
      color = EXCLUDED.color,
      sort_order = EXCLUDED.sort_order,
      description = EXCLUDED.description,
      keywords = EXCLUDED.keywords,
      default_listing_type = EXCLUDED.default_listing_type,
      active = TRUE;

-- ============================================================
-- 2. SUB-CATEGORIES (13) under Building & Construction Material
--    Slugs match static categories.json where they already exist.
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'construction-material')
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order, description, keywords,
  parent_id, default_listing_type, active
)
SELECT t.slug, t.name, t.name_hi, t.icon, '#92400E', t.sort_order,
       t.description, t.keywords, p.id, 'shop', TRUE
FROM (VALUES
  ('paint-shop',
   'Paint Shop',
   'पेंट की दुकान',
   '🎨', 46,
   'Asian Paints, Berger, Nerolac, Dulux dealer, primer, distemper, putty, enamel, wood polish, brush, roller',
   'paint,paint shop,paint store,asian paints,berger,nerolac,dulux,kansai nerolac,jsw paint,primer,putty,distemper,enamel,emulsion,wood polish,wall paint,wood paint,brush,roller,thinner,turpentine,rang,rangai,paint dealer'),

  ('hardware-shop',
   'Hardware Shop',
   'हार्डवेयर की दुकान',
   '🔩', 47,
   'Nails, screws, nut-bolt, locks, hinges, hand tools, drill bits, hammer, wrench, tape, glue, building hardware',
   'hardware,hardware store,hardware shop,nails,kil,screw,nut bolt,locks,tala,hinges,kabze,tools,hand tools,drill,hammer,hatouda,wrench,plier,measuring tape,gum,fevicol,m-seal,builder hardware,construction hardware,iron mongery'),

  ('building-material',
   'Cement / Building Material',
   'सीमेंट / निर्माण सामग्री',
   '🏗️', 48,
   'UltraTech, ACC, Ambuja, Shree cement dealer, white cement, ready mix, AAC blocks, bricks, fly ash',
   'cement,building material,ultratech,acc,ambuja,shree cement,jk cement,birla cement,white cement,grey cement,opc,ppc,bricks,eet,it,aac block,fly ash brick,red brick,concrete blocks,ready mix concrete,rmc,builder supply,nirman samagri'),

  ('chuna-lime',
   'Chuna / Lime / White-wash Material',
   'चूना / कली / सफेदी सामग्री',
   '🪣', 49,
   'Chuna (kali), hydrated lime, quick lime, white-wash powder, distemper, neela thotha, gerua, ramraj — full white-wash & seasonal painting raw material',
   'chuna,kali,kalee,lime,quick lime,hydrated lime,white wash,whitewash,safedi,distemper,neela thotha,blue,gerua,ramraj,khadiya,wall finish,seasonal paint,festive paint,diwali safedi,kachra chuna,kalai,kalai wala'),

  ('sariya-tmt',
   'Sariya / TMT / Steel Bars',
   'सरिया / टीएमटी / स्टील',
   '⛓️', 50,
   'TMT bars (Tata Tiscon, JSW, Kamdhenu, SAIL), GI pipes, MS angle, channel, sheet, square pipe, binding wire',
   'sariya,saria,tmt,tmt bar,steel bar,iron rod,tata tiscon,jsw steel,kamdhenu,sail steel,gi pipe,ms pipe,angle,channel,sheet,square pipe,binding wire,iron rod,loha,steel,8mm,10mm,12mm,16mm,20mm,reinforcement bar'),

  ('tiles-marble',
   'Tiles / Marble / Granite',
   'टाइल्स / मार्बल / ग्रेनाइट',
   '🟧', 51,
   'Floor tiles, wall tiles, vitrified tiles, Kajaria, Somany, Asian Granito, marble, granite, kotah stone — flooring & cladding shop',
   'tiles,floor tiles,wall tiles,vitrified,ceramic tile,kajaria,somany,asian granito,nitco,johnson,marble,granite,marble dealer,granite dealer,kotah stone,kota stone,makrana,italian marble,kitchen platform,flooring stone,polished granite'),

  ('sanitary-bathroom',
   'Sanitary / Bathroom Fittings',
   'सेनेटरी / बाथरूम फिटिंग',
   '🚿', 52,
   'Hindware, Cera, Parryware, Jaquar, Kohler — washbasin, commode, geyser, tap, shower, bathroom accessory shop',
   'sanitary,sanitaryware,hindware,cera,parryware,jaquar,kohler,washbasin,commode,wc,toilet seat,bathroom fitting,tap,nal,shower,geyser,bathroom shop,bathroom accessory'),

  ('plywood-laminate',
   'Plywood, Laminate & Ply',
   'प्लाइवुड / लैमिनेट',
   '🪵', 53,
   'Plywood (Century, Greenply, Kitply), MDF, particle board, laminate sheet (Sunmica, Merino), veneer, edge banding',
   'plywood,ply,century ply,centuryply,greenply,kitply,duro ply,mdf,particle board,blockboard,laminate,sunmica,merino,royale touche,greenlam,veneer,edge banding,hardware ply,interior material,furniture material'),

  ('sand-gravel',
   'Sand / Bajri / Gravel Supplier',
   'रेत / बजरी / रोड़ी',
   '🏖️', 54,
   'Sand (badarpur, river sand, M-sand), bajri / gravel / kanker / roda, RMC concrete supplier, trolley supply',
   'sand,bajri,bajree,gravel,roda,rodi,kanker,grit,stone aggregate,badarpur,river sand,m-sand,manufactured sand,fine sand,coarse sand,trolley sand,truck sand,reti,reta,builder supply,sand supplier'),

  ('pipes-fittings',
   'Pipes & Fittings (PVC/CPVC)',
   'पाइप / फिटिंग',
   '🚰', 55,
   'PVC pipes, CPVC pipes (Astral, Supreme, Finolex, Prince), water tank, sintex, soil pipe, elbow, T, valve',
   'pvc pipe,cpvc pipe,plumbing pipe,water pipe,astral,supreme,finolex,prince pipe,kisan pipe,water tank,sintex,plastic tank,plumbing fitting,elbow,t joint,valve,bend,reducer,soil pipe,drainage pipe,plumber material'),

  ('electrical-hardware',
   'Electrical Hardware (Wire/Switch/MCB)',
   'इलेक्ट्रिकल हार्डवेयर',
   '⚡', 56,
   'Havells, Anchor, Polycab, Finolex wire, MCB, distribution box, switch, socket, holder, fan capacitor, LED light',
   'electrical,electrical hardware,wire,cable,polycab,havells,anchor,finolex,kei,rr kabel,mcb,distribution box,db,switch,socket,modular switch,holder,bulb,led,tube light,fan,ceiling fan,capacitor,electrician material,bijli ka samaan'),

  ('doors-windows-grills',
   'Doors, Windows & Grills',
   'दरवाजे / खिड़की / ग्रिल',
   '🚪', 57,
   'Wooden door, flush door, PVC door, aluminium window, UPVC window, steel window, iron grill, safety door, gate maker',
   'door,doors,window,khirki,darwaza,wooden door,flush door,pvc door,aluminium window,upvc window,steel window,iron window,grill,grill maker,jangla,safety door,gate,iron gate,welding work,fabricator,jangle wala,grill wala'),

  ('pop-false-ceiling',
   'POP / False Ceiling Material',
   'POP / सीलिंग सामग्री',
   '🏠', 58,
   'POP (plaster of paris), gypsum board, false ceiling material, PVC panel, grid ceiling, designer ceiling supply',
   'pop,plaster of paris,gypsum,gypsum board,false ceiling,pvc panel,grid ceiling,designer ceiling,ceiling material,armstrong,saint gobain,gyproc,wall panel,roof panel')

) AS t(slug, name, name_hi, icon, sort_order, description, keywords)
CROSS JOIN parent p
ON CONFLICT (slug) DO UPDATE
  SET keywords = EXCLUDED.keywords,
      description = EXCLUDED.description,
      parent_id = EXCLUDED.parent_id,
      name = EXCLUDED.name,
      name_hi = EXCLUDED.name_hi,
      icon = EXCLUDED.icon,
      sort_order = EXCLUDED.sort_order,
      default_listing_type = EXCLUDED.default_listing_type,
      active = TRUE;

-- ============================================================
-- 3. Cross-link: also help users find shops via Painter service
-- ============================================================
UPDATE categories
   SET keywords = COALESCE(keywords,'') ||
       ',paint shop,paint store,asian paints,berger dealer,rang ki dukaan'
 WHERE slug = 'painter'
   AND (keywords IS NULL OR keywords NOT LIKE '%paint shop%');

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- 4. Verification
-- ==============================