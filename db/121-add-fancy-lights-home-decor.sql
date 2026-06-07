-- =====================================================
-- db/121-add-fancy-lights-home-decor.sql
-- =====================================================
-- Adds "Fancy Lights" and "Home Decor" subcategories
-- under Home Services (parent slug: home-services).
--
-- "Fancy Lights" is distinct from "LED / Lighting Shop":
--   - LED / Lighting Shop  = utility LED bulbs, panel lights, batten
--   - Fancy Lights         = decorative — chandeliers, jhumar, fairy
--                            lights, ceiling decoration lights
--
-- "Home Decor" covers showpieces, wall art, vases, curtains, cushions,
-- carpets, photo frames — interior decoration products.
--
-- Schema reference (db/01-schema.sql):
--   categories(id, parent_id, slug, name, name_hi, icon, color,
--              description, sort_order, active, business_count)
--
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

-- ---------- Fancy Lights ----------
INSERT INTO categories (slug, name, name_hi, parent_id, icon, color, sort_order, active, description)
SELECT
  'fancy-lights',
  'Fancy Lights',
  'फैंसी लाइट्स',
  (SELECT id FROM categories WHERE slug = 'home-services' LIMIT 1),
  '✨',
  '#F59E0B',
  COALESCE(
    (SELECT MAX(sort_order) FROM categories
      WHERE parent_id = (SELECT id FROM categories WHERE slug = 'home-services' LIMIT 1)),
    100) + 5,
  TRUE,
  'Decorative lighting — chandeliers, jhumar, fairy lights, ceiling and wall decoration lights, designer pendant lights, party lights, string lights'
WHERE NOT EXISTS (
  SELECT 1 FROM categories WHERE slug = 'fancy-lights'
);

-- ---------- Home Decor ----------
INSERT INTO categories (slug, name, name_hi, parent_id, icon, color, sort_order, active, description)
SELECT
  'home-decor',
  'Home Decor',
  'होम डेकोर',
  (SELECT id FROM categories WHERE slug = 'home-services' LIMIT 1),
  '🖼️',
  '#EC4899',
  COALESCE(
    (SELECT MAX(sort_order) FROM categories
      WHERE parent_id = (SELECT id FROM categories WHERE slug = 'home-services' LIMIT 1)),
    100) + 10,
  TRUE,
  'Interior decoration items — wall art, showpieces, vases, wallpaper, curtains, cushions, rugs, carpets, artificial plants, photo frames, gift items, wall hangings'
WHERE NOT EXISTS (
  SELECT 1 FROM categories WHERE slug = 'home-decor'
);

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
DECLARE
  v_fancy INT;
  v_decor INT;
BEGIN
  SELECT COUNT(*) INTO v_fancy FROM categories WHERE slug = 'fancy-lights';
  SELECT COUNT(*) INTO v_decor FROM categories WHERE slug = 'home-decor';
  RAISE NOTICE 'db/121 installed.';
  IF v_fancy = 1 THEN
    RAISE NOTICE '  + Fancy Lights (under Home Services)';
  ELSE
    RAISE NOTICE '  ! Fancy Lights — not inserted (parent missing or already existed)';
  END IF;
  IF v_decor = 1 THEN
    RAISE NOTICE '  + Home Decor (under Home Services)';
  ELSE
    RAISE NOTICE '  ! Home Decor — not inserted (parent missing or already existed)';
  END IF;
END $$;
