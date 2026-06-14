-- ============================================================
-- db/133 — Add Computer / Mobile / Lottery sub-categories
-- ============================================================
-- Adds 6 sub-categories under existing parents. 1 of these
-- (computer-laptop-repair) already exists in assets/data/categories.json
-- but had no matching DB row — this migration syncs it.
--
-- Under 'retail-shopping' (Retail & Shopping):
--   - laptop-computer-sale         Laptops / Computers Sale          (NEW)
--   - laptop-computer-accessories  Laptop / Computer Accessories     (NEW)
--   - mobile-accessories           Mobile Accessories                (NEW)
--   - lottery-centre               Lottery Centre                    (NEW)
--
-- Under 'home-services' (Home Services):
--   - computer-laptop-repair       Computer / Laptop Repair          (SYNC with JSON)
--   - mobile-repair                Mobile Repair                     (NEW)
--
-- Reasoning:
--   * Sale + Accessories belong with retail-shopping where the existing
--     'mobile-shop' and 'electronics' subs already live.
--   * Repair categories belong with home-services alongside 'ac-repair',
--     'ro-repair' which follow the same "device repair" pattern.
--   * 'mobile-shop' (slug already used) is a generic mobile+recharge shop
--     — these new categories are MORE specific so customers searching
--     for accessories vs repair vs sale can pick the right listing.
--   * 'computer-laptop-repair' slug matches the existing entry in
--     assets/data/categories.json so the DB and frontend cache align.
--
-- SAFE: All inserts use ON CONFLICT (slug) DO NOTHING. Re-runnable.
-- DB never disturbed — only forward migration, no deletes, no schema changes.
-- ============================================================

BEGIN;

-- ---- 4 new subs under 'retail-shopping' ----
-- Existing sort_orders under retail-shopping: 71 (mobile-shop), 72 (electronics),
-- 73 (footwear), 74 (stationery), 75 (gift-shop), 76 (general-store).
-- Picking 77-80 to keep stable ordering.
-- Schema note: categories table (per db/01-schema.sql) has columns:
--   id, parent_id, slug, name, name_hi, icon, color, description, sort_order,
--   active, business_count. No is_parent and no created_at columns exist.
--   A row is a "parent" if its parent_id IS NULL.
WITH p AS (SELECT id FROM categories WHERE slug = 'retail-shopping')
INSERT INTO categories (slug, name, name_hi, icon, parent_id, sort_order)
SELECT v.slug, v.name, v.name_hi, v.icon, p.id, v.sort
FROM p, (VALUES
  ('laptop-computer-sale',        'Laptops / Computers Sale',        'लैपटॉप / कंप्यूटर बिक्री',     '💻', 77),
  ('laptop-computer-accessories', 'Laptop / Computer Accessories',   'लैपटॉप / कंप्यूटर एक्सेसरीज',  '🖱️', 78),
  ('mobile-accessories',          'Mobile Accessories',              'मोबाइल एक्सेसरीज',              '🎧', 79),
  ('lottery-centre',              'Lottery Centre',                  'लॉटरी सेंटर',                   '🎟️', 80)
) AS v(slug, name, name_hi, icon, sort)
ON CONFLICT (slug) DO NOTHING;

-- ---- 2 subs under 'home-services' ----
-- Existing sort_orders under home-services: 41 (painter), 42 (ac-repair),
-- 43 (ro-repair), 44 (pest-control), 45 (maid-service), 46 (cleaning-service),
-- 47 (packers-movers). Picking 48-49 to slot device-repair right after the
-- other appliance-repair categories.
WITH p AS (SELECT id FROM categories WHERE slug = 'home-services')
INSERT INTO categories (slug, name, name_hi, icon, parent_id, sort_order)
SELECT v.slug, v.name, v.name_hi, v.icon, p.id, v.sort
FROM p, (VALUES
  ('computer-laptop-repair', 'Computer / Laptop Repair', 'कंप्यूटर / लैपटॉप रिपेयर', '💻', 48),
  ('mobile-repair',          'Mobile Repair',            'मोबाइल रिपेयर',             '🔧', 49)
) AS v(slug, name, name_hi, icon, sort)
ON CONFLICT (slug) DO NOTHING;

-- ---- Verification (read-only, for sanity check after run) ----
-- Expected output: 6 rows
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
  'laptop-computer-sale',
  'laptop-computer-accessories',
  'mobile-accessories',
  'lottery-centre',
  'computer-laptop-repair',
  'mobile-repair'
)
ORDER BY p.slug, c.sort_order;

COMMIT;
