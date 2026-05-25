-- =====================================================
-- db/48-add-manufacturer-cats.sql
-- =====================================================
-- ADDITIVE ONLY: adds Manufacturer sub-categories under
-- the existing 'retail-shopping' parent. Zero risk to
-- existing data. Safe to run multiple times.
--
-- HOW TO RUN:
--   Supabase Dashboard → SQL Editor → New Query
--   Paste this entire file → Run
-- =====================================================

BEGIN;

-- 5 new manufacturer-type categories under retail-shopping
-- (We pick retail-shopping because manufacturers often also retail/wholesale.
--  If you later want a dedicated 'Manufacturing' parent, that's a separate change.)
INSERT INTO categories (parent_id, slug, name, name_hi, icon, sort_order, active)
SELECT
  p.id,
  v.slug, v.name, v.name_hi, v.icon, v.sort_order, true
FROM categories p
CROSS JOIN (VALUES
  ('manufacturer',           'Manufacturer / Factory / Production Unit', 'निर्माता / फैक्ट्री',         '🏭', 250),
  ('manufacturer-textile',   'Textile / Garment Manufacturer',           'टेक्सटाइल / गारमेंट निर्माता',  '🧵', 251),
  ('manufacturer-food',      'Food / Snacks Manufacturer',               'खाद्य / स्नैक्स निर्माता',      '🍱', 252),
  ('manufacturer-furniture', 'Furniture Manufacturer',                   'फर्नीचर निर्माता',             '🪑', 253),
  ('manufacturer-agri',      'Agri Equipment / Tools Manufacturer',      'कृषि उपकरण निर्माता',          '🚜', 254)
) AS v(slug, name, name_hi, icon, sort_order)
WHERE p.slug = 'retail-shopping'
ON CONFLICT (slug) DO NOTHING;

-- Reload PostgREST schema cache so REST API sees new rows immediately
NOTIFY pgrst, 'reload schema';

-- Verify — should show 5 new (or more if already existed)
DO $$
DECLARE v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count FROM categories WHERE slug LIKE 'manufacturer%';
  RAISE NOTICE 'Manufacturer-related categories now in DB: %', v_count;
END $$;

COMMIT;
