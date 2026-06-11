-- ============================================================
-- db/125 — Add Hospitality + Placement + Training categories
-- ============================================================
-- Adds 9 new categories to sync with categories.json v3.5:
--
-- NEW PARENT: hospitality-travel  (Hospitality, Hotels & Banquets)
--   - hotel
--   - marriage-palace
--   - banquet-hall
--   - resort-farm-stay
--   - guest-house-lodge
--   - dharamshala
--   - ticket-booking-counter
--
-- NEW SUBS under existing parents:
--   - training-institute  (under: education)
--   - placement-agency    (under: professional-services)
--
-- SAFE: All inserts use ON CONFLICT DO NOTHING. Re-runnable.
-- DB never disturbed — only forward migration, no deletes.
-- ============================================================

BEGIN;

-- ---- New PARENT: hospitality-travel ----
INSERT INTO categories (slug, name, name_hi, icon, is_parent, parent_id, sort_order, created_at)
VALUES
  ('hospitality-travel', 'Hospitality, Hotels & Banquets', 'होटल, बैंक्वेट एवं आतिथ्य', '🏨', TRUE, NULL,
   COALESCE((SELECT MAX(sort_order) + 10 FROM categories WHERE is_parent = TRUE), 1000), NOW())
ON CONFLICT (slug) DO NOTHING;

-- ---- 7 subs under hospitality-travel ----
WITH p AS (SELECT id FROM categories WHERE slug = 'hospitality-travel')
INSERT INTO categories (slug, name, name_hi, icon, is_parent, parent_id, sort_order, created_at)
SELECT v.slug, v.name, v.name_hi, v.icon, FALSE, p.id, v.sort, NOW()
FROM p, (VALUES
  ('hotel',                  'Hotel',                              'होटल',                            '🏨', 10),
  ('marriage-palace',        'Marriage Palace',                    'मैरिज पैलेस',                      '💒', 20),
  ('banquet-hall',           'Banquet Hall / Party Lawn',          'बैंक्वेट हॉल / पार्टी लॉन',         '🎉', 30),
  ('resort-farm-stay',       'Resort / Farm Stay',                 'रिज़ॉर्ट / फार्म स्टे',             '🏝️', 40),
  ('guest-house-lodge',      'Guest House / Lodge',                'गेस्ट हाउस / लॉज',                 '🛏️', 50),
  ('dharamshala',            'Dharamshala / Religious Stay',       'धर्मशाला',                          '🛕', 60),
  ('ticket-booking-counter', 'Bus / Train / Flight Booking Counter','बस / रेल / फ्लाइट बुकिंग',       '🎫', 70)
) AS v(slug, name, name_hi, icon, sort)
ON CONFLICT (slug) DO NOTHING;

-- ---- training-institute under existing 'education' parent ----
WITH p AS (SELECT id FROM categories WHERE slug = 'education')
INSERT INTO categories (slug, name, name_hi, icon, is_parent, parent_id, sort_order, created_at)
SELECT 'training-institute', 'Training Centre / Institute', 'ट्रेनिंग सेंटर / संस्थान', '🎯',
       FALSE, p.id,
       COALESCE((SELECT MAX(sort_order) + 10 FROM categories WHERE parent_id = p.id), 500),
       NOW()
FROM p
ON CONFLICT (slug) DO NOTHING;

-- ---- placement-agency under existing 'professional-services' parent ----
WITH p AS (SELECT id FROM categories WHERE slug = 'professional-services')
INSERT INTO categories (slug, name, name_hi, icon, is_parent, parent_id, sort_order, created_at)
SELECT 'placement-agency', 'Placement Agency / HR Consultant', 'प्लेसमेंट एजेंसी / HR कंसल्टेंट', '💼',
       FALSE, p.id,
       COALESCE((SELECT MAX(sort_order) + 10 FROM categories WHERE parent_id = p.id), 500),
       NOW()
FROM p
ON CONFLICT (slug) DO NOTHING;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================
-- VERIFY — should show all 9 new slugs
-- ============================================================
SELECT
  c.slug,
  c.name,
  c.icon,
  CASE WHEN c.is_parent THEN '[PARENT]' ELSE p.slug END AS parent_slug
FROM categories c
LEFT JOIN categories p ON c.parent_id = p.id
WHERE c.slug IN (
  'hospitality-travel', 'hotel', 'marriage-palace', 'banquet-hall',
  'resort-farm-stay', 'guest-house-lodge', 'dharamshala',
  'ticket-booking-counter', 'training-institute', 'placement-agency'
)
ORDER BY c.is_parent DESC, c.sort_order;

DO $$
BEGIN
  RAISE NOTICE 'db/125 installed.';
  RAISE NOTICE '  1 new parent: hospitality-travel';
  RAISE NOTICE '  7 hospitality subs + 1 training + 1 placement = 9 new subs';
  RAISE NOTICE '  Total new categories: 10';
END $$;
