-- ============================================================
-- db/235 — newspaper & media, distributors, garments/tailor by
--          who they dress, accessories, supplements, builder
-- ============================================================
--
-- From Deepak's list on 2026-09-29. Every slug below was checked
-- against the live 380 first (by slug, by English name and by Hindi
-- name) so nothing here duplicates what is already there:
--
--   newspaper / media      nothing matched newspaper, akhbar, media,
--                          journalist or patrakar
--   fashion-accessories    only vehicle / laptop / mobile / gas
--                          "accessories" existed — no belts or wallets
--   perfume-ittar          nothing matched perfume, ittar or attar
--   gym-supplements        nothing matched supplement or protein
--   distributor-*          only mutual-fund-distributor and two
--                          wholesale entries (mithai, galla mandi)
--   garments-*             readymade-garments, kids-wear and mens-wear
--                          existed; ladies, girls and boys did not
--   tailor-*               tailor-darzi existed as one lump
--   builder-contractor     labour-contractor existed (that is the man
--                          who supplies labour, not the man who builds)
--
-- ONE RENAME, no slug change, so every existing URL and every shop
-- already filed under it are untouched:
--   mens-wear → "Readymade Garments — Gents", so the garment family
--   reads as one set in the picker instead of "Men's Wear" sitting
--   apart from three "Readymade Garments — …" siblings.
--
-- Safe to re-run: inserts are ON CONFLICT guarded, the rename is
-- matched on slug.
-- ============================================================

BEGIN;

INSERT INTO public.categories (parent_id, slug, name, name_hi, icon, color, sort_order, active)
SELECT p.id, v.slug, v.name, v.name_hi, v.icon, p.color, v.sort_order, TRUE
FROM (VALUES
  -- ---------- Newspaper & Media ----------
  ('professional-services', 'newspaper-agency', 'Newspaper Agency / Hawker',      'अख़बार एजेंसी / हॉकर',        '📰', 910::SMALLINT),
  ('professional-services', 'media-news',       'Media / News Channel / Reporter','मीडिया / न्यूज़ चैनल / पत्रकार','🎙️', 911::SMALLINT),

  -- ---------- Retail: accessories, fragrance, supplements ----------
  ('retail-shopping', 'fashion-accessories', 'Belts, Wallets & Fashion Accessories', 'बेल्ट, वॉलेट और फैशन एक्सेसरीज़', '👜', 910::SMALLINT),
  ('retail-shopping', 'perfume-ittar',       'Perfume & Ittar',                      'परफ्यूम और इत्र',                 '🌸', 911::SMALLINT),
  ('retail-shopping', 'gym-supplements',     'Gym & Health Supplements',             'जिम और हेल्थ सप्लीमेंट',          '💪', 912::SMALLINT),

  -- ---------- Retail: readymade garments, by who wears them ----------
  ('retail-shopping', 'garments-ladies', 'Readymade Garments — Ladies', 'रेडीमेड गारमेंट्स — लेडीज़', '👗', 920::SMALLINT),
  ('retail-shopping', 'garments-girls',  'Readymade Garments — Girls',  'रेडीमेड गारमेंट्स — गर्ल्स',  '🎀', 921::SMALLINT),
  ('retail-shopping', 'garments-boys',   'Readymade Garments — Boys',   'रेडीमेड गारमेंट्स — ब्वॉयज़',  '👕', 922::SMALLINT),

  -- ---------- Retail: distributors / wholesalers ----------
  ('retail-shopping', 'distributor-food',        'Distributor / Wholesaler — Food & Grocery',       'डिस्ट्रीब्यूटर — खाद्य एवं किराना',      '📦', 930::SMALLINT),
  ('retail-shopping', 'distributor-clothing',    'Distributor / Wholesaler — Clothing & Textile',   'डिस्ट्रीब्यूटर — कपड़ा एवं टेक्सटाइल',   '🧵', 931::SMALLINT),
  ('retail-shopping', 'distributor-cosmetics',   'Distributor / Wholesaler — Cosmetics & Toiletries','डिस्ट्रीब्यूटर — कॉस्मेटिक',           '💄', 932::SMALLINT),
  ('retail-shopping', 'distributor-electronics', 'Distributor / Wholesaler — Electronics & Appliances','डिस्ट्रीब्यूटर — इलेक्ट्रॉनिक्स',    '🔌', 933::SMALLINT),
  ('retail-shopping', 'distributor-stationery',  'Distributor / Wholesaler — Stationery & Paper',   'डिस्ट्रीब्यूटर — स्टेशनरी एवं पेपर',    '📗', 934::SMALLINT),
  ('retail-shopping', 'distributor-hardware',    'Distributor / Wholesaler — Hardware & Tools',     'डिस्ट्रीब्यूटर — हार्डवेयर एवं टूल्स',  '🔩', 935::SMALLINT),
  ('retail-shopping', 'distributor-pharma',      'Distributor / Wholesaler — Medicine & Pharma',    'डिस्ट्रीब्यूटर — दवा एवं फार्मा',       '💊', 936::SMALLINT),
  ('retail-shopping', 'distributor-plastic',     'Distributor / Wholesaler — Plastic & Household',  'डिस्ट्रीब्यूटर — प्लास्टिक एवं घरेलू',  '🧴', 937::SMALLINT),
  ('retail-shopping', 'distributor-beverages',   'Distributor / Wholesaler — Cold Drinks & Beverages','डिस्ट्रीब्यूटर — कोल्ड ड्रिंक',      '🥤', 938::SMALLINT),
  ('retail-shopping', 'distributor-general',     'Distributor / Wholesaler — Other Goods',          'डिस्ट्रीब्यूटर — अन्य सामान',           '🚚', 939::SMALLINT),

  -- ---------- Home Services: tailor, by who they stitch for ----------
  ('home-services', 'tailor-ladies', 'Ladies Tailor / Boutique Stitching', 'लेडीज़ टेलर / बुटीक सिलाई', '✂️', 910::SMALLINT),
  ('home-services', 'tailor-gents',  'Gents Tailor',                       'जेंट्स टेलर',              '✂️', 911::SMALLINT),
  ('home-services', 'tailor-girls',  'Girls (Kids) Tailor',                'गर्ल्स (बच्चों) टेलर',      '✂️', 912::SMALLINT),
  ('home-services', 'tailor-boys',   'Boys (Kids) Tailor',                 'ब्वॉयज़ (बच्चों) टेलर',      '✂️', 913::SMALLINT),

  -- ---------- Building & Construction ----------
  ('construction-material', 'builder-contractor', 'Builder / Contractor', 'बिल्डर / ठेकेदार', '🏗️', 910::SMALLINT)
) AS v(parent_slug, slug, name, name_hi, icon, sort_order)
JOIN public.categories p
  ON p.slug = v.parent_slug AND p.parent_id IS NULL
ON CONFLICT (slug) DO NOTHING;

-- The one rename. Slug untouched, so /local/<city>/mens-wear and every
-- shop filed under it keep working exactly as before.
UPDATE public.categories
   SET name    = 'Readymade Garments — Gents',
       name_hi = 'रेडीमेड गारमेंट्स — जेंट्स'
 WHERE slug = 'mens-wear';

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/235-media-distributors-garments-categories.sql');
  END IF;
END $$;

COMMIT;

-- ============================================================
-- 23 new rows + the renamed Gents entry should be listed below,
-- each under the right parent.
-- ============================================================
SELECT c.slug, c.name, p.name AS under, c.business_count AS shops
FROM public.categories c
JOIN public.categories p ON p.id = c.parent_id
WHERE c.slug IN (
  'newspaper-agency','media-news',
  'fashion-accessories','perfume-ittar','gym-supplements',
  'garments-ladies','garments-girls','garments-boys','mens-wear',
  'distributor-food','distributor-clothing','distributor-cosmetics',
  'distributor-electronics','distributor-stationery','distributor-hardware',
  'distributor-pharma','distributor-plastic','distributor-beverages','distributor-general',
  'tailor-ladies','tailor-gents','tailor-girls','tailor-boys',
  'builder-contractor'
)
ORDER BY p.sort_order, c.sort_order;
