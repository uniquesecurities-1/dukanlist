-- =====================================================
-- db/116-add-readymade-category.sql
-- =====================================================
-- Adds "Readymade Garments" subcategory under Retail & Shopping.
-- Common term for ready-to-wear clothes (kids, men, women) — distinct
-- from "Clothes / Tailor" (which is for custom tailoring).
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

INSERT INTO categories (slug, name, parent_id, icon, is_active, sort_order)
SELECT
  'readymade-garments',
  'Readymade Garments',
  (SELECT id FROM categories WHERE slug = 'retail-shopping' LIMIT 1),
  '🧥',
  TRUE,
  COALESCE(
    (SELECT MAX(sort_order) FROM categories
      WHERE parent_id = (SELECT id FROM categories WHERE slug = 'retail-shopping' LIMIT 1)),
    0) + 1
WHERE NOT EXISTS (
  SELECT 1 FROM categories WHERE slug = 'readymade-garments'
);

NOTIFY pgrst, 'reload schema';
COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'db/116 installed.';
  RAISE NOTICE '  + Readymade Garments under Retail & Shopping';
END $$;
