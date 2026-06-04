-- =====================================================
-- db/96-add-energy-solar-renewable-categories.sql
-- =====================================================
-- USER REQUEST (2026-06-02):
--   "ADD NEW CATEGORIES — Solar, Renewable Energy, Energy Sector"
--
-- WHAT THIS DOES:
--   Adds a NEW PARENT category 'Energy, Solar & Renewable' with
--   15 sub-categories covering the full solar + renewable energy
--   ecosystem — installation, AMC, EPC, consultancy, EV charging,
--   wind, biogas, MNRE subsidy etc.
--
-- WHY A NEW PARENT (not just one sub):
--   The energy sector is broad enough (residential solar, commercial
--   EPC, agri solar pumps under KUSUM, EV charging, energy audit,
--   wind/biogas) to deserve its own bucket. Cleaner UX, easier SEO
--   landing (e.g. /local/<city>/solar-panel-installation).
--
-- All inserts are idempotent (ON CONFLICT (slug) DO UPDATE).
-- =====================================================

BEGIN;

-- ============================================================
-- 1) Parent category — Energy, Solar & Renewable
-- ============================================================
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order,
  description, keywords,
  parent_id, default_listing_type, active
) VALUES (
  'energy-solar',
  'Energy, Solar & Renewable',
  'ऊर्जा, सोलर एवं नवीकरणीय',
  '☀️',
  '#F59E0B',
  1300,
  'Solar panel installation, rooftop solar, solar inverter, solar water heater, EV charging, wind energy, biogas, energy audit, renewable energy consulting, MNRE subsidy assistance.',
  'solar,solar panel,solar shop,renewable energy,green energy,clean energy,off-grid,on-grid,hybrid solar,solar power,sun energy,suraj,suraj ki bijli,bijli ki bachat,inverter,battery,ups,energy audit,energy saving,bachat,mnre,kusum,pm surya ghar,subsidy,solar subsidy,ev charging,electric vehicle,wind energy,biogas,biomass,renewable',
  NULL,
  'shop',
  TRUE
) ON CONFLICT (slug) DO UPDATE
  SET name = EXCLUDED.name,
      name_hi = EXCLUDED.name_hi,
      icon = EXCLUDED.icon,
      color = EXCLUDED.color,
      description = EXCLUDED.description,
      keywords = EXCLUDED.keywords,
      active = TRUE;


-- ============================================================
-- 2) Sub-categories under energy-solar (15 items)
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'energy-solar')
INSERT INTO categories (
  slug, name, name_hi, icon, color, sort_order, description, keywords,
  parent_id, default_listing_type, active
)
SELECT t.slug, t.name, t.name_hi, t.icon, '#F59E0B', t.sort_order,
       t.description, t.keywords, p.id, 'shop', TRUE
FROM (VALUES
  ('solar-panel-installation',
   'Solar Panel Installation',
   'सोलर पैनल इंस्टॉलेशन',
   '🔆', 1310,
   'Residential and commercial solar panel installation, mono-crystalline, polycrystalline, thin-film panels, full turnkey installation including structure, wiring and net metering.',
   'solar panel,solar installation,solar fitter,solar contractor,solar dealer,solar company,kw solar,3kw solar,5kw solar,10kw solar,solar plant,solar system,solar lagana,solar fit karwana,mono panel,poly panel,bifacial,n-type panel,tata solar,adani solar,vikram solar,waaree,loom solar,microtek,luminous solar'),

  ('rooftop-solar',
   'Rooftop Solar (Residential)',
   'रूफटॉप सोलर (घरेलू)',
   '🏠', 1311,
   'Rooftop solar for homes, on-grid net metering, hybrid systems with battery backup, residential capacity 1-25 kW, PM Surya Ghar / state subsidy assistance.',
   'rooftop solar,roof top solar,ghar par solar,ghar ka solar,home solar,residential solar,1kw solar,2kw solar,3kw solar,5kw solar,on grid,off grid,hybrid solar,net metering,pm surya ghar,surya ghar,muft bijli yojana,solar for home'),

  ('commercial-solar-epc',
   'Commercial Solar / EPC',
   'कमर्शियल सोलर / EPC',
   '🏢', 1312,
   'EPC (Engineering, Procurement, Construction) for commercial and industrial solar projects, factory rooftop, agricultural pumpsets, ground-mount solar parks above 25 kW.',
   'epc,commercial solar,industrial solar,c&i solar,ci solar,solar epc,solar contractor,factory solar,office solar,school solar,hospital solar,solar park,ground mount,bipv,turnkey solar,opex solar,capex solar,resco model,ppa'),

  ('solar-water-heater',
   'Solar Water Heater',
   'सोलर वाटर हीटर',
   '♨️', 1313,
   'ETC and FPC type solar water heaters 100/200/300 LPD for homes, hostels, hotels. Pressurized and non-pressurized systems with stand and plumbing.',
   'solar water heater,solar geyser,solar hot water,etc water heater,fpc water heater,pressurized water heater,100 lpd,200 lpd,300 lpd,solar geezer,pani garam karne wala,suraj ka geyser,supreme solar,racold,v-guard solar'),

  ('solar-inverter-battery',
   'Solar Inverter / Battery',
   'सोलर इन्वर्टर / बैटरी',
   '🔋', 1314,
   'Solar PCU, MPPT inverters, solar charge controllers, tubular and lithium batteries for solar systems, replacement and AMC.',
   'solar inverter,pcu,mppt,solar charge controller,solar battery,tubular battery,lithium battery,lifepo4,solar ups,3 phase solar inverter,growatt,deye,sma,delta,sunken,microtek solar,luminous solar,exide,amaron,sf sonic'),

  ('solar-pump-agri',
   'Solar Pump (Agri / KUSUM)',
   'सोलर पंप (कृषि / KUSUM)',
   '💧', 1315,
   'Solar pumps for agriculture under PM KUSUM scheme — 3 HP / 5 HP / 7.5 HP / 10 HP DC and AC pumps, surface and submersible, government subsidy assistance.',
   'solar pump,solar water pump,solar pumpset,agricultural solar,khet ka solar,khet solar pump,kusum,pm kusum,kusum yojana,pradhan mantri kusum,3hp solar pump,5hp solar pump,7.5hp solar pump,10hp solar pump,dc pump,ac pump,submersible,surface pump,shakti pumps,c.r.i,kirloskar'),

  ('solar-street-light',
   'Solar Street Light / Lamp',
   'सोलर स्ट्रीट लाइट',
   '💡', 1316,
   'Solar LED street lights for villages, panchayats, societies, integrated all-in-one street lights, solar garden lights, solar high-mast lighting.',
   'solar street light,solar light,led solar light,all in one,aio,integrated solar light,solar lamp,solar garden light,solar high mast,gram panchayat solar,village solar,society solar,road light,solar lantern'),

  ('solar-amc-cleaning',
   'Solar AMC & Cleaning',
   'सोलर AMC एवं सफाई',
   '🧹', 1317,
   'Solar panel cleaning service, preventive maintenance, AMC contracts, panel washing, inverter health check, monitoring and performance audit.',
   'solar amc,solar cleaning,panel cleaning,solar maintenance,solar repair,solar service,solar safai,panel safai,solar inspection,solar performance,solar audit,inverter repair,solar monitoring,wash robot'),

  ('renewable-energy-consultant',
   'Renewable Energy Consultant',
   'नवीकरणीय ऊर्जा सलाहकार',
   '🌱', 1318,
   'Independent renewable energy advisor — system sizing, tender preparation, ROI analysis, vendor evaluation, performance review and dispute resolution.',
   'renewable energy,re consultant,renewable consultant,energy consultant,clean energy advisor,green energy consultant,solar advisor,solar consultant,energy expert,solar tender,solar bid,solar dpr,project report'),

  ('energy-audit',
   'Energy Audit / Saving',
   'एनर्जी ऑडिट / बचत',
   '📋', 1319,
   'BEE-certified energy audit for homes, factories, hospitals, hotels; identifies wastage, recommends LED, BLDC, VFD, solar, capacitor banks — typical savings 15-40%.',
   'energy audit,bee audit,energy saving,bachat,bijli bachat,electricity audit,power audit,energy efficiency,bee certified,bldc,vfd,led retrofit,capacitor bank,power factor,green building,leed,igbc,star rating'),

  ('wind-energy',
   'Wind Energy Solutions',
   'पवन ऊर्जा समाधान',
   '🌬️', 1320,
   'Small wind turbines for homes and farms (1-10 kW), hybrid wind-solar systems, wind turbine maintenance, wind resource assessment.',
   'wind energy,wind turbine,small wind,vertical axis wind,vawt,hawt,wind power,wind solar hybrid,pavan urja,pawan urja,wind mill,windmill,wind resource'),

  ('biogas-biomass',
   'Biogas / Biomass',
   'बायोगैस / बायोमास',
   '♻️', 1321,
   'Biogas plant installation (gobar gas), biomass briquette and pellet manufacturing, waste-to-energy consultancy for dairy, poultry, food processing units.',
   'biogas,gobar gas,gobar gas plant,biomass,briquette,pellet,waste to energy,wte,dairy biogas,gaushala biogas,kvic biogas,floating dome,deenbandhu,fixed dome,bio cng,compressed biogas,biofuel'),

  ('ev-charging-station',
   'EV Charging Station',
   'EV चार्जिंग स्टेशन',
   '🔌', 1322,
   'EV charging installation — AC slow chargers, DC fast chargers, CCS2, Bharat AC/DC standard, residential and commercial charge points, OCPP-compatible.',
   'ev charging,electric vehicle charging,ev charger,ac charger,dc charger,fast charger,slow charger,bharat ac,bharat dc,ccs2,chademo,type 2,3.3kw,7.4kw,22kw,50kw,150kw,charging station,charge point,ocpp,public charger,society charger'),

  ('ups-inverter-battery',
   'UPS / Inverter / Battery Shop',
   'UPS / इन्वर्टर / बैटरी शॉप',
   '🔋', 1323,
   'Conventional UPS, home inverter, sine wave inverter, tubular and lithium batteries for backup, all major brands sales + service + AMC + battery water top-up.',
   'inverter,inverter battery,ups,home ups,sine wave inverter,square wave,tubular battery,flat plate battery,lithium battery,inverter battery shop,battery shop,microtek,luminous,sukam,exide,amaron,livguard,okaya,battery water,battery service,distilled water'),

  ('solar-subsidy-mnre',
   'Solar Subsidy / MNRE Consultant',
   'सोलर सब्सिडी / MNRE सलाहकार',
   '📜', 1324,
   'Assistance with MNRE rooftop solar subsidy applications, PM Surya Ghar registration, DISCOM net metering paperwork, KUSUM application for farmers.',
   'mnre subsidy,solar subsidy,pm surya ghar,surya ghar yojana,muft bijli yojana,kusum subsidy,solar subsidy form,solar subsidy application,national portal,discom,net metering,bijli vibhag,sansam,sandes,solar yojana,empanelled vendor,empanelment')

) AS t(slug, name, name_hi, icon, sort_order, description, keywords)
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
-- 3) Notify PostgREST to reload its schema cache
-- ============================================================
NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'db/96 applied. Energy/Solar/Renewable parent added with 15 sub-categories.';
  RAISE NOTICE 'Test: SELECT slug, name FROM categories WHERE parent_id = (SELECT id FROM categories WHERE slug = ''energy-solar'') ORDER BY sort_order;';
END $$;
