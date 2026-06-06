-- =====================================================
-- db/116-add-readymade-category.sql
-- =====================================================
-- Adds "Readymade Garments" subcategory under Retail & Shopping.
-- Common term for ready-to-wear clothes (kids, men, women) — distinct
-- from "Clothes / Tailor" (which is for custom tailoring).
--
-- Schema reference (from db/01-schema.sql):
--   categories(id, parent_id, slug, name, name_hi, icon, color,
--              description, sort_order, active, business_count)
--   NOTE: column is "active" not "is_active".
--
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

INSERT INTO categories (slug, name, name_hi, parent_id, icon, color, sort_order, active, description)
SELECT
  'readymade-garments',
  'Readymade Garments',
  'रेडीमेड कपड़े',
  (SELECT id FROM categories WHERE slug = 'retail-shopping' LIMIT 1),
  '🧥',
  '#A855F7',
  COALESCE(
    (SELECT MAX(sort_order) FROM categories
      WHERE parent_id = (SELECT id FROM categor