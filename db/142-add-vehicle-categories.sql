-- ============================================================
-- db/142 — Add 11 new sub-categories under 'automotive' parent
-- ============================================================
-- User feedback: "car showroom, cars repair, scooter, scooty,
-- two wheeler, 4 wheeler aisi bahut si categories abhi nahi hai".
--
-- Audit of existing automotive subs found these gaps:
--   * No dedicated CAR-only showroom (only combined 'new-car'
--     = "New Car / Bike Showroom" which mixes 4w + 2w).
--   * No dedicated BIKE / SCOOTER / SCOOTY showroom.
--   * No EV / Electric Vehicle dealer (2026 reality).
--   * No Truck / Tempo / Bus dealer.
--   * No Auto / E-Rickshaw dealer.
--   * No Car AC repair (distinct from general mechanic-4w).
--   * No Denting & Painting workshop.
--   * No Car / Bike accessories shop.
--   * No Towing / Roadside assistance.
--   * No RTO agent / vehicle-registration service.
--   * No Crane / JCB / Hydra heavy-vehicle service (rural Haryana).
--
-- This migration adds those 11 sub-categories under the
-- existing 'automotive' parent. assets/data/categories.json
-- (v3.7) already lists these — this SQL syncs them to the DB
-- so listing-search, RPCs and admin dropdowns all see them.
--
-- SAFE: ON CONFLICT (slug) DO NOTHING. Re-runnable.
-- DB never disturbed — only forward migration. No deletes,
-- no schema changes, no existing data touched.
-- ============================================================

BEGIN;

-- ---- Existing automotive sort_orders (per db/03-seed-categories.sql
-- and later patches): used-car (51), new-car (52), mechanic-2w (53),
-- mechanic-4w (54), car-service (55), tyre-shop (56), spare-parts (57),
-- battery-shop (58), car-wash (59), tractor-parts (60), cycle-shop (61),
-- puncture-shop (62), commercial-vehicle (63), petrol-pump (64),
-- vehicle-rental (65), generator-dg-set (66).
-- Picking 67-77 to slot the new ones at the end in display order.

WITH p AS (SELECT id FROM categories WHERE slug = 'automotive')
INSERT INTO categories (slug, name, name_hi, icon, parent_id, sort_order)
SELECT v.slug, v.name, v.name_hi, v.icon, p.id, v.sort
FROM p, (VALUES
  ('car-showroom',              'Car Showroom (New & Used)',         'कार शोरूम',                       '🚙', 67),
  ('bike-showroom',             'Bike / Scooter / Scooty Showroom',  'बाइक / स्कूटर / स्कूटी शोरूम',    '🏍️', 68),
  ('ev-dealer',                 'Electric Vehicle (EV) Dealer',      'इलेक्ट्रिक व्हीकल डीलर',          '🔌', 69),
  ('commercial-vehicle-dealer', 'Truck / Tempo / Bus Dealer',        'ट्रक / टेम्पो / बस डीलर',          '🚛', 70),
  ('auto-rickshaw',             'Auto / E-Rickshaw Dealer',          'ऑटो / ई-रिक्शा डीलर',             '🛺', 71),
  ('car-ac-repair',             'Car AC Repair / Gas Recharge',      'कार AC रिपेयर / गैस रिचार्ज',     '❄️', 72),
  ('denting-painting',          'Denting & Painting Workshop',       'डेंटिंग एवं पेंटिंग',              '🎨', 73),
  ('vehicle-accessories',       'Car / Bike Accessories',            'कार / बाइक एक्सेसरीज़',            '🎵', 74),
  ('towing-service',            'Towing / Roadside Assistance',      'टोइंग / रोडसाइड सहायता',          '🚚', 75),
  ('rto-agent',                 'RTO Agent / Vehicle Registration',  'RTO एजेंट / वाहन रजिस्ट्रेशन',    '📋', 76),
  ('crane-service',             'Crane / JCB / Hydra Service',       'क्रेन / JCB / हाइड्रा सेवा',       '🏗️', 77)
) AS v(slug, name, name_hi, icon, sort)
ON CONFLICT (slug) DO NOTHING;

-- ---- Verification (read-only, expected: 11 rows) ----
SELECT
  c.slug,
  c.name,
  c.name_hi,
  c.icon,
  c.sort_order,
  p.slug AS parent_slug
FROM categories c
LEFT JOIN categories p ON p.id = c.parent_id
WHERE c.slug IN (
  'car-showroom', 'bike-showroom', 'ev-dealer', 'commercial-vehicle-dealer',
  'auto-rickshaw', 'car-ac-repair', 'denting-painting', 'vehicle-accessories',
  'towing-service', 'rto-agent', 'crane-service'
)
ORDER BY c.sort_order;

COMMIT;
