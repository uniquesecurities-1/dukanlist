-- ============================================================
-- db/134 — RESYNC db/125 hospitality categories with correct schema
-- ============================================================
-- BACKGROUND:
--   db/125 was written using `is_parent` and `created_at` columns,
--   neither of which exist on the categories table (per db/01-schema.sql
--   the real columns are: id, parent_id, slug, name, name_hi, icon,
--   color, description, sort_order, active, business_count).
--   Result: every INSERT in db/125 failed with PostgreSQL error 42703
--   "column 'is_parent' of relation 'categories' does not exist", so
--   ZERO hospitality categories landed in the DB.
--
--   Meanwhile assets/data/categories.json v3.5 listed them as available,
--   so owner dropdowns showed them — but selecting them would fail at
--   business INSERT because no matching category_id exists. User verified:
--   "hotel me kuch found nahi hota" (hotel returns no results).
--
-- WHAT THIS MIGRATION ADDS (10 rows total):
--   NEW PARENT:
--     - hospitality-travel  (Hospitality, Hotels & Banquets)  🏨
--
--   7 SUBS under hospitality-travel:
--     - hotel                   🏨
--     - marriage-palace         💒
--     - banquet-hall            🎉
--     - resort-farm-stay        🏝️
--     - guest-house-lodge       🛏️
--     - dharamshala             🛕
--     - ticket-booking-counter  🎫
--
--   1 SUB under existing 'education':
--     - training-institute      🎯
--
--   1 SUB under existing 'professional-services':
--     - placement-agency        💼
--
-- SCHEMA NOTES:
--   * Parent rows: parent_id IS NULL.
--   * Sub rows:    parent_id = id of parent.
--   * No is_parent column needed — NULL parent_id implies parent.
--   * No created_at column needed.
--
-- SAFE: All inserts use ON CONFLICT (slug) DO NOTHING. Re-runnable.
-- DB never disturbed — forward-only migration, no deletes, no schema changes.
-- ============================================================

BEGIN;

-- ---- 1. New PARENT: hospitality-travel ----
-- For top-level parents we want a sort_order that follows the last existing parent.
INSERT INTO categories (slug, name, name_hi, icon, parent_id, sort_order)
VALUES (
  'hospitality-travel',
  'Hospitality, Hotels & Banquets',
  'होटल, बैंक्वेट एवं आतिथ्य',
  '🏨',
  NULL,
  COALESCE((SELECT MAX(sort_order) + 10 FROM categories WHERE parent_id IS NULL), 1000)
)
ON CONFLICT (slug) DO NOTHING;

-- ---- 2. Seven subs under hospitality-travel ----
WITH p AS (SELECT id FROM categories WHERE slug = 'hospitality-travel')
INSERT INTO categories (slug, name, name_hi, icon, parent_id, sort_order)
SELECT v.slug, v.name, v.name_hi, v.icon, p.id, v.sort
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

-- ---- 3. training-institute under existing 'education' parent ----
WITH p AS (SELECT id FROM categories WHERE slug = 'education')
INSERT INTO categories (slug, name, name_hi, icon, parent_id, sort_order)
SELECT
  'training-institute',
  'Training Centre / Institute',
  'ट्रेनिंग सेंटर / संस्थान',
  '🎯',
  p.id,
  COALESCE((SELECT MAX(sort_order) + 10 FROM categories WHERE parent_id = p.id), 500)
FROM p
ON CONFLICT (slug) DO NOTHING;

-- ---- 4. placement-agency under existing 'professional-services' parent ----
WITH p AS (SELECT id FROM categories WHERE slug = 'professional-services')
INSERT INTO categories (slug, name, name_hi, icon, parent_id, sort_order)
SELECT
  'placement-agency',
  'Placement Agency / HR Consultant',
  'प्लेसमेंट एजेंसी / HR कंसल्टेंट',
  '💼',
  p.id,
  COALESCE((SELECT MAX(sort_order) + 10 FROM categories WHERE parent_id = p.id), 500)
FROM p
ON CONFLICT (slug) DO NOTHING;

-- ---- Tell PostgREST to reload its schema cache (so new categories are immediately queryable) ----
NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================
-- VERIFY — expected output: 10 rows
-- (1 parent + 7 hospitality subs + training-institute + placement-agency)
-- ============================================================
SELECT
  c.slug,
  c.name,
  c.icon,
  c.sort_order,
  CASE WHEN c.parent_id IS NULL THEN '[PARENT]' ELSE p.slug END AS parent_slug
FROM categories c
LEFT JOIN categories p ON c.parent_id = p.id
WHERE c.slug IN (
  'hospitality-travel',
  'hotel', 'marriage-palace', 'banquet-hall',
  'resort-farm-stay', 'guest-house-lodge', 'dharamshala',
  'ticket-booking-counter',
  'training-institute', 'placement-agency'
)
ORDER BY (c.parent_id IS NOT NULL), c.sort_order;
