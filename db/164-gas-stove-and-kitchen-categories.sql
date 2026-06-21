-- ============================================================
-- db/164 — Gas stove + kitchen appliance categories
-- ============================================================
-- User requested: gas stove repair, gas stove (sales), gas bhatti
-- (commercial), accessories.
--
-- I'm also adding the most-commonly-grouped neighbours since most
-- gas-stove technicians ALSO fix chimneys / microwaves / geysers,
-- and gas-shops often sell mixer/regulator/pipe combos. Better to
-- ship the full group once than dribble incremental migrations.
--
-- TWO PARENTS USED:
--   • home-services           → repair-side categories
--   • retail-shopping         → sales-side categories
--
-- IDEMPOTENT — all INSERTs use ON CONFLICT (slug) DO UPDATE.
-- ============================================================

BEGIN;

-- ============================================================
-- PART A — REPAIR side (under home-services parent)
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'home-services' LIMIT 1)
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order,
  description, keywords,
  parent_id, default_listing_type, active
)
SELECT t.slug, t.name, t.name_hi, t.icon, '#92400E', t.sort_order,
       t.description, t.keywords, p.id, 'service', TRUE
FROM (VALUES
  ('gas-stove-repair',
   'Gas Stove / Hob / Bhatti Repair',
   'गैस चूल्हा / हॉब / भट्टी मरम्मत',
   '🔥', 75,
   'Gas stove repair, hob repair, gas bhatti repair, burner clean, igniter fix, regulator change, gas leak test — domestic and commercial',
   'gas stove repair,gas chulha repair,chulha mistri,gas mistri,hob repair,gas hob,burner clean,burner replace,igniter repair,knob replace,regulator change,gas leak,gas leakage,gas pipe replace,bhatti repair,halwai bhatti,commercial stove,restaurant gas repair,2 burner,3 burner,4 burner,glass top stove,cooktop repair,LPG stove,PNG stove,gas service'),

  ('geyser-repair',
   'Geyser / Water Heater Repair',
   'गीज़र / वाटर हीटर मरम्मत',
   '🚿', 76,
   'Geyser repair, water heater installation, element change, thermostat repair, gas geyser, electric geyser, instant geyser',
   'geyser repair,geyser installation,water heater repair,electric geyser,gas geyser,instant geyser,storage geyser,bajaj geyser,havells geyser,racold,ao smith,vguard,thermostat,heating element,geyser leak,water heater service'),

  ('chimney-repair',
   'Kitchen Chimney Installation & Repair',
   'किचन चिमनी इंस्टॉल / मरम्मत',
   '🏠', 77,
   'Kitchen chimney installation, chimney cleaning, filter change, motor repair, Faber, Kaff, Elica, Hindware, Glen chimney service',
   'chimney repair,chimney installation,chimney service,chimney cleaning,filter clean,baffle filter,faber chimney,kaff chimney,elica chimney,hindware chimney,glen chimney,sunflame chimney,auto clean chimney,motor repair,chimney noise,modular chimney'),

  ('microwave-otg-repair',
   'Microwave / OTG / Oven Repair',
   'माइक्रोवेव / OTG / ओवन मरम्मत',
   '🍞', 78,
   'Microwave repair, OTG repair, oven service, IFB, LG, Samsung, Whirlpool, Bajaj microwave service, magnetron change',
   'microwave repair,otg repair,oven repair,microwave service,ifb microwave,lg microwave,samsung microwave,whirlpool,bajaj microwave,convection microwave,grill microwave,magnetron repair,microwave not heating,microwave installation'),

  ('mixer-grinder-repair',
   'Mixer / Grinder / Small Appliance Repair',
   'मिक्सी / ग्राइंडर मरम्मत',
   '🥤', 79,
   'Mixer grinder repair, juicer repair, food processor service, motor rewinding, blade change — Preethi, Bajaj, Sumeet, Philips',
   'mixer repair,mixer grinder repair,grinder repair,juicer repair,food processor repair,wet grinder,mixie,preethi,bajaj mixer,sumeet,philips mixer,maharaja,butterfly mixer,motor rewinding,blade change,jar replace,small appliance repair')

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
-- PART B — SALES side (under retail-shopping parent)
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'retail-shopping' LIMIT 1)
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order,
  description, keywords,
  parent_id, default_listing_type, active
)
SELECT t.slug, t.name, t.name_hi, t.icon, '#16A34A', t.sort_order,
       t.description, t.keywords, p.id, 'shop', TRUE
FROM (VALUES
  ('gas-stove-shop',
   'Gas Stove / Hob Dealer',
   'गैस चूल्हा / हॉब की दुकान',
   '🔥', 80,
   'Gas stove dealer, hob seller, cooktop, 2/3/4 burner stove — Sunflame, Prestige, Glen, Hindware, Elica, Faber',
   'gas stove,gas chulha,hob,cooktop,gas stove shop,gas stove dealer,2 burner,3 burner,4 burner,glass top stove,sunflame,prestige stove,glen,hindware,elica hob,faber,kaff,sunflame stove,sleek stove,butterfly stove,inalsa,stovekraft,kitchen stove'),

  ('gas-bhatti-commercial',
   'Commercial Gas Bhatti / Halwai Burner',
   'कमर्शियल गैस भट्टी / हलवाई',
   '🔥', 81,
   'Commercial gas bhatti, halwai burner, restaurant stove, dhaba bhatti, commercial cooking range, deg bhatti, kadhai bhatti',
   'commercial bhatti,halwai bhatti,restaurant bhatti,dhaba bhatti,gas bhatti,commercial gas stove,industrial burner,deg bhatti,kadhai bhatti,jumbo burner,3 burner commercial,4 burner commercial,canteen stove,catering stove,hotel kitchen stove,commercial cooking range,Indian kitchen equipment,SS bhatti,stainless steel bhatti'),

  ('gas-accessories',
   'Gas Regulator / Pipe / Accessories',
   'गैस रेगुलेटर / पाइप / सामान',
   '🛠️', 82,
   'Gas regulator, gas pipe (rubber + suraksha), gas lighter, burner cap, knob, igniter, gas hose, ISI certified accessories',
   'gas accessories,gas regulator,gas pipe,suraksha pipe,rubber pipe,gas lighter,burner cap,gas knob,igniter,gas hose,ISI gas pipe,LPG accessories,gas connection accessories,gas safety,gas valve,gas clamp,gas burner spare,stove spare parts,Indane accessories,HP gas accessories,Bharat gas accessories'),

  ('kitchen-appliances-shop',
   'Kitchen Appliances Shop',
   'किचन उपकरण की दुकान',
   '🍳', 83,
   'Mixer, grinder, juicer, microwave, OTG, induction cooktop, electric kettle, toaster, sandwich maker — small kitchen appliances retail',
   'kitchen appliances,mixer grinder,juicer,microwave,otg,oven,induction cooktop,electric kettle,toaster,sandwich maker,kitchen tools,small appliances,bajaj,preethi,prestige,philips kitchen,sumeet,butterfly,inalsa,morphy richards,havells kitchen,maharaja whiteline,kitchen ka samaan'),

  ('induction-cooktop',
   'Induction Cooktop Dealer',
   'इंडक्शन कुकटॉप',
   '🔌', 84,
   'Induction cooktop dealer, electric cooking induction, Pigeon, Prestige, Bajaj, Havells, Philips induction',
   'induction cooktop,induction stove,electric cooktop,pigeon induction,prestige induction,bajaj induction,havells induction,philips induction,butterfly induction,induction plate,smart induction')

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
-- PART C — Enrich existing gas-agency keywords (search reach)
-- ============================================================
-- gas-agency was kept under food/beverage from earlier seed.
-- Beef up its keywords so customers searching for "LPG connection"
-- or "Indane Dabwali" or "HP gas booking" hit it too.
UPDATE categories
   SET keywords = COALESCE(NULLIF(keywords,''),'') ||
                  CASE WHEN keywords IS NULL OR keywords = '' THEN '' ELSE ',' END ||
                  'lpg agency,lpg distributor,indane,indane gas,hp gas,bharat gas,bharat petroleum,bpcl,iocl,gas connection,gas booking,gas refill,gas cylinder,domestic cylinder,commercial cylinder,5kg cylinder,14kg cylinder,19kg cylinder,gas dealer,new connection,gas distributor,gas service centre,go gas,supergas,nayara,reliance gas'
 WHERE slug = 'gas-agency'
   AND (keywords IS NULL OR keywords NOT LIKE '%indane%');


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
DECLARE
  v_added INT;
BEGIN
  SELECT COUNT(*) INTO v_added FROM categories
   WHERE slug IN (
     'gas-stove-repair','geyser-repair','chimney-repair',
     'microwave-otg-repair','mixer-grinder-repair',
     'gas-stove-shop','gas-bhatti-commercial','gas-accessories',
     'kitchen-appliances-shop','induction-cooktop'
   );
  RAISE NOTICE 'db/164 installed. % gas+kitchen categories live.', v_added;
END $$;
