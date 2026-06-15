-- ============================================================
-- db/144 — Sync 60 JSON-only orphan slugs to DB
-- ============================================================
-- Audit finding: assets/data/categories.json lists 60 sub-categories
-- that were never INSERTed by any db/*.sql migration. As a result:
--   * SEO URLs like /local/<city>/<slug> return 404 from api/locality.js
--   * The search-by-slug RPC silently returns 0 rows for those slugs
--   * Admin "categories" panel doesn't show them
--   * Even though shop registration forms (which read JSON) would
--     happily let owners pick these — the link is then dead.
--
-- Examples of high-impact orphans:
--   beauty-parlour   — directly linked from index.html SEO pill
--                      "Beauty Parlours in Mandi Dabwali"
--   cycle-shop       — member of MEGA_SLUGS.mechanic
--   puncture-shop    — member of MEGA_SLUGS.mechanic
--   tractor-parts    — member of MEGA_SLUGS.mechanic
--   bakery-cake      — member of MEGA_SLUGS.bakery
--   wholesale-dealer — member of MEGA_SLUGS.grocery
--
-- This migration creates each missing slug under its correct parent
-- (per the JSON), with name / name_hi / icon copied verbatim from
-- categories.json v3.8. Sort orders start at 200 per parent to slot
-- the new rows after existing subs without renumbering anything.
--
-- SAFE: ON CONFLICT (slug) DO NOTHING. Re-runnable.
-- DB never disturbed — only forward INSERTs. No deletes, no updates,
-- no schema changes, no existing data touched.
--
-- NOTE: 4 of these 60 slugs may already exist in DB from earlier migrations
-- (where the INSERT pattern wasn't caught by my orphan-detector regex):
--   - bakery-cake, footwear-shop  (canonical slugs created by db/123 merge)
--   - training-institute, placement-agency  (added by db/125)
-- For those, ON CONFLICT (slug) DO NOTHING quietly skips — no error.
-- Expected new INSERTs: ~56 of 60. Verification SELECT at end shows ALL 60.
-- ============================================================

BEGIN;

-- ---- 4 subs under 'automotive' ----
WITH p AS (SELECT id FROM categories WHERE slug = 'automotive')
INSERT INTO categories (slug, name, name_hi, icon, parent_id, sort_order)
SELECT v.slug, v.name, v.name_hi, v.icon, p.id, v.sort
FROM p, (VALUES
  ('tractor-parts', 'Tractor Parts / Spares', 'ट्रैक्टर पार्ट्स', '🚜', 200),
  ('cycle-shop', 'Bicycle Shop / Repair', 'साइकिल की दुकान', '🚲', 201),
  ('puncture-shop', 'Puncture / Tyre Shop', 'पंक्चर / टायर', '🛞', 202),
  ('commercial-vehicle', 'Commercial Vehicle Parts', 'कमर्शियल व्हीकल', '🚛', 203)
) AS v(slug, name, name_hi, icon, sort)
ON CONFLICT (slug) DO NOTHING;

-- ---- 3 subs under 'beauty-wellness' ----
WITH p AS (SELECT id FROM categories WHERE slug = 'beauty-wellness')
INSERT INTO categories (slug, name, name_hi, icon, parent_id, sort_order)
SELECT v.slug, v.name, v.name_hi, v.icon, p.id, v.sort
FROM p, (VALUES
  ('beauty-parlour', 'Beauty Parlour (Ladies)', 'ब्यूटी पार्लर', '💋', 200),
  ('mehendi-artist', 'Mehendi / Henna Artist', 'मेहंदी आर्टिस्ट', '🌿', 201),
  ('tattoo-piercing', 'Tattoo / Piercing Studio', 'टैटू स्टूडियो', '🎨', 202)
) AS v(slug, name, name_hi, icon, sort)
ON CONFLICT (slug) DO NOTHING;

-- ---- 2 subs under 'community-social' ----
WITH p AS (SELECT id FROM categories WHERE slug = 'community-social')
INSERT INTO categories (slug, name, name_hi, icon, parent_id, sort_order)
SELECT v.slug, v.name, v.name_hi, v.icon, p.id, v.sort
FROM p, (VALUES
  ('temple-mandir', 'Temple / Mandir', 'मंदिर', '🛕', 200),
  ('community-hall', 'Marriage Hall / Community Hall', 'मैरिज हॉल', '🏛️', 201)
) AS v(slug, name, name_hi, icon, sort)
ON CONFLICT (slug) DO NOTHING;

-- ---- 1 subs under 'education' ----
WITH p AS (SELECT id FROM categories WHERE slug = 'education')
INSERT INTO categories (slug, name, name_hi, icon, parent_id, sort_order)
SELECT v.slug, v.name, v.name_hi, v.icon, p.id, v.sort
FROM p, (VALUES
  ('training-institute', 'Training Centre / Institute', 'ट्रेनिंग सेंटर / संस्थान', '🎯', 200)
) AS v(slug, name, name_hi, icon, sort)
ON CONFLICT (slug) DO NOTHING;

-- ---- 11 subs under 'food-beverage' ----
WITH p AS (SELECT id FROM categories WHERE slug = 'food-beverage')
INSERT INTO categories (slug, name, name_hi, icon, parent_id, sort_order)
SELECT v.slug, v.name, v.name_hi, v.icon, p.id, v.sort
FROM p, (VALUES
  ('halwai-mithai', 'Halwai / Mithai Shop', 'हलवाई / मिठाई की दुकान', '🍬', 200),
  ('bakery-cake', 'Bakery / Cake Shop', 'बेकरी / केक शॉप', '🎂', 201),
  ('dhaba-roadside', 'Dhaba / Roadside Eatery', 'ढाबा', '🍛', 202),
  ('tea-stall', 'Tea Stall / Chai Kiosk', 'चाय की दुकान', '🫖', 203),
  ('juice-shake', 'Juice / Shake / Cold Drink', 'जूस / शेक', '🥤', 204),
  ('ice-cream-parlour', 'Ice Cream Parlour', 'आइसक्रीम पार्लर', '🍦', 205),
  ('dairy-milk', 'Dairy / Milk Shop', 'डेयरी / दूध', '🥛', 206),
  ('fruit-vegetable', 'Fruit / Vegetable / Sabzi', 'फल-सब्ज़ी', '🥬', 207),
  ('meat-chicken', 'Meat / Chicken / Fish Shop', 'मांस / चिकन', '🍗', 208),
  ('catering-service', 'Catering Service', 'कैटरिंग सेवा', '🍴', 209),
  ('gas-agency', 'LPG Gas Agency', 'गैस एजेंसी', '🔥', 210)
) AS v(slug, name, name_hi, icon, sort)
ON CONFLICT (slug) DO NOTHING;

-- ---- 10 subs under 'home-services' ----
WITH p AS (SELECT id FROM categories WHERE slug = 'home-services')
INSERT INTO categories (slug, name, name_hi, icon, parent_id, sort_order)
SELECT v.slug, v.name, v.name_hi, v.icon, p.id, v.sort
FROM p, (VALUES
  ('furniture-wood', 'Furniture / Wood Works', 'फर्नीचर / लकड़ी', '🪑', 200),
  ('welding-iron', 'Welding / Iron Works', 'वेल्डिंग / लोहार', '🔥', 201),
  ('cooler-fan-repair', 'Cooler / Fan Repair', 'कूलर / पंखा', '💨', 202),
  ('led-lighting', 'LED / Lighting Shop', 'LED / लाइटिंग', '💡', 203),
  ('solar-inverter', 'Solar / Inverter / Battery', 'सोलर / इन्वर्टर', '🔋', 204),
  ('borewell-water', 'Borewell / Submersible Pump', 'बोरवेल / पम्प', '⛲', 205),
  ('curtain-upholstery', 'Curtain / Upholstery / Sofa', 'पर्दा / सोफा', '🛋️', 206),
  ('carpet-mat', 'Carpet / Mat / Durries', 'कालीन / दरी', '🟫', 207),
  ('mandap-tent', 'Mandap / Tent House', 'टेंट हाउस', '⛺', 208),
  ('dj-sound-system', 'DJ / Sound System / Light', 'DJ / साउंड', '🔊', 209)
) AS v(slug, name, name_hi, icon, sort)
ON CONFLICT (slug) DO NOTHING;

-- ---- 7 subs under 'professional-services' ----
WITH p AS (SELECT id FROM categories WHERE slug = 'professional-services')
INSERT INTO categories (slug, name, name_hi, icon, parent_id, sort_order)
SELECT v.slug, v.name, v.name_hi, v.icon, p.id, v.sort
FROM p, (VALUES
  ('placement-agency', 'Placement Agency / HR Consultant', 'प्लेसमेंट एजेंसी / HR कंसल्टेंट', '💼', 200),
  ('pesticide-agri', 'Pesticide / Agri Inputs', 'कीटनाशक / कृषि', '🌾', 201),
  ('seeds-fertilizer', 'Seeds / Fertilizer Shop', 'बीज / खाद', '🌱', 202),
  ('veterinary-doctor', 'Veterinary Doctor', 'पशु चिकित्सक', '🐄', 203),
  ('photo-studio', 'Photo Studio / Videography', 'फोटो स्टूडियो', '📸', 204),
  ('cement-dealer', 'Cement / Steel Dealer', 'सीमेंट / सरिया', '🏗️', 205),
  ('transport-tempo', 'Transport / Tempo / Mini Truck', 'ट्रांसपोर्ट', '🚚', 206)
) AS v(slug, name, name_hi, icon, sort)
ON CONFLICT (slug) DO NOTHING;

-- ---- 22 subs under 'retail-shopping' ----
WITH p AS (SELECT id FROM categories WHERE slug = 'retail-shopping')
INSERT INTO categories (slug, name, name_hi, icon, parent_id, sort_order)
SELECT v.slug, v.name, v.name_hi, v.icon, p.id, v.sort
FROM p, (VALUES
  ('saree-shop', 'Saree Shop', 'साड़ी की दुकान', '🥻', 200),
  ('lehenga-bridal', 'Lehenga / Bridal Wear', 'लहंगा / दुल्हन परिधान', '👰', 201),
  ('boutique-designer', 'Boutique / Designer Wear', 'बूटीक / डिज़ाइनर वियर', '👗', 202),
  ('kids-wear', 'Kids Wear', 'बच्चों के कपड़े', '👶', 203),
  ('mens-wear', 'Men''s Wear / Suiting', 'पुरुष परिधान / सूटिंग', '👔', 204),
  ('cloth-merchant', 'Cloth Merchant / Fabric', 'कपड़ा व्यापारी', '🧶', 205),
  ('undergarment', 'Hosiery / Undergarments', 'होज़री', '👙', 206),
  ('utensils-shop', 'Utensils / Bartan Shop', 'बर्तन की दुकान', '🍳', 207),
  ('crockery-glassware', 'Crockery / Glassware', 'क्रॉकरी / काँच के बर्तन', '🍽️', 208),
  ('plastic-items', 'Plastic Items / Containers', 'प्लास्टिक सामान', '🪣', 209),
  ('pottery-shop', 'Pottery / Mitti ke Bartan', 'मिट्टी के बर्तन', '🏺', 210),
  ('footwear-shop', 'Footwear / Shoes / Chappal', 'जूते-चप्पल', '👞', 211),
  ('watch-shop', 'Watch Shop / Repair', 'घड़ी की दुकान', '⌚', 212),
  ('optical-shop', 'Optical / Spectacles', 'चश्मे की दुकान', '👓', 213),
  ('jewellery-imitation', 'Imitation Jewellery / Bangles', 'इमिटेशन ज्वेलरी', '💍', 214),
  ('bookstore', 'Book Store / Stationery', 'किताब / स्टेशनरी', '📚', 215),
  ('photocopy-cyber', 'Photocopy / Cyber Cafe', 'फोटोकॉपी / साइबर', '🖨️', 216),
  ('toy-shop', 'Toy Shop', 'खिलौने की दुकान', '🧸', 217),
  ('cosmetic-shop', 'Cosmetic / Beauty Products', 'कॉस्मेटिक की दुकान', '💄', 218),
  ('pooja-samagri', 'Pooja Samagri Shop', 'पूजा सामग्री', '🪔', 219),
  ('florist', 'Florist / Flower Shop', 'फूलवाला', '💐', 220),
  ('wholesale-dealer', 'Wholesale / Galla Mandi Dealer', 'थोक विक्रेता', '📦', 221)
) AS v(slug, name, name_hi, icon, sort)
ON CONFLICT (slug) DO NOTHING;

-- ---- Verification (read-only) — expected: 60 rows ----
SELECT c.slug, c.name, p.slug AS parent_slug, c.sort_order
FROM categories c
LEFT JOIN categories p ON p.id = c.parent_id
WHERE c.slug IN ('furniture-wood', 'welding-iron', 'cooler-fan-repair', 'led-lighting', 'solar-inverter', 'borewell-water', 'curtain-upholstery', 'carpet-mat', 'mandap-tent', 'dj-sound-system', 'tractor-parts', 'cycle-shop', 'puncture-shop', 'commercial-vehicle', 'halwai-mithai', 'bakery-cake', 'dhaba-roadside', 'tea-stall', 'juice-shake', 'ice-cream-parlour', 'dairy-milk', 'fruit-vegetable', 'meat-chicken', 'catering-service', 'gas-agency', 'saree-shop', 'lehenga-bridal', 'boutique-designer', 'kids-wear', 'mens-wear', 'cloth-merchant', 'undergarment', 'utensils-shop', 'crockery-glassware', 'plastic-items', 'pottery-shop', 'footwear-shop', 'watch-shop', 'optical-shop', 'jewellery-imitation', 'bookstore', 'photocopy-cyber', 'toy-shop', 'cosmetic-shop', 'pooja-samagri', 'florist', 'wholesale-dealer', 'beauty-parlour', 'mehendi-artist', 'tattoo-piercing', 'training-institute', 'placement-agency', 'pesticide-agri', 'seeds-fertilizer', 'veterinary-doctor', 'photo-studio', 'cement-dealer', 'transport-tempo', 'temple-mandir', 'community-hall')
ORDER BY p.slug, c.sort_order;

COMMIT;
