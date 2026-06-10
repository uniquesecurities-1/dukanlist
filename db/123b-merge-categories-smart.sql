-- =====================================================
-- db/123b-merge-categories-smart.sql
-- =====================================================
-- Smarter version of db/123 that handles all 3 cases per pair:
--
--   Case A: Both old & new slugs exist in DB
--           → Move shops from old → new, delete old
--
--   Case B: Only OLD slug exists (canonical missing in DB)
--           → Just RENAME old slug to new (preserves the row + shops)
--
--   Case C: Only NEW slug exists, or neither
--           → Nothing to do
--
-- This was the bug in db/123: pair "grocery → kirana-grocery"
-- skipped because kirana-grocery didn't exist in DB (frontend-only).
-- Result: 13 shops stranded under deprecated slug, search returned 0.
--
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

DO $$
DECLARE
  v_old_id   INT;
  v_new_id   INT;
  v_moved    INT;
  v_pairs    TEXT[][] := ARRAY[
    -- {old_slug, new_slug}
    ARRAY['grocery',           'kirana-grocery'],
    ARRAY['bakery',            'bakery-cake'],
    ARRAY['footwear',          'footwear-shop'],
    ARRAY['gift-stationery',   'gift-shop'],
    ARRAY['music-class',       'music-dance-class']
  ];
  i INT;
BEGIN
  FOR i IN 1..array_length(v_pairs, 1) LOOP
    v_old_id := NULL;
    v_new_id := NULL;
    v_moved  := 0;

    SELECT id INTO v_old_id FROM categories WHERE slug = v_pairs[i][1] LIMIT 1;
    SELECT id INTO v_new_id FROM categories WHERE slug = v_pairs[i][2] LIMIT 1;

    -- Case A: Both exist → migrate + delete
    IF v_old_id IS NOT NULL AND v_new_id IS NOT NULL AND v_old_id != v_new_id THEN
      UPDATE businesses SET category_id     = v_new_id WHERE category_id     = v_old_id;
      GET DIAGNOSTICS v_moved = ROW_COUNT;
      RAISE NOTICE 'A) % shops moved on primary cat (% → %)', v_moved, v_pairs[i][1], v_pairs[i][2];

      UPDATE businesses SET sub_category_id = v_new_id WHERE sub_category_id = v_old_id;
      GET DIAGNOSTICS v_moved = ROW_COUNT;
      RAISE NOTICE '   % shops moved on sub_category', v_moved;

      BEGIN
        UPDATE businesses
           SET secondary_category_ids = array_replace(secondary_category_ids, v_old_id, v_new_id)
         WHERE secondary_category_ids @> ARRAY[v_old_id];
      EXCEPTION WHEN undefined_column THEN NULL; END;

      DELETE FROM categories WHERE id = v_old_id;
      RAISE NOTICE '   Deleted deprecated [%]', v_pairs[i][1];

    -- Case B: Only OLD exists → just rename
    ELSIF v_old_id IS NOT NULL AND v_new_id IS NULL THEN
      UPDATE categories SET slug = v_pairs[i][2] WHERE id = v_old_id;
      SELECT COUNT(*) INTO v_moved FROM businesses
        WHERE category_id = v_old_id OR sub_category_id = v_old_id;
      RAISE NOTICE 'B) Renamed slug % → % (% shops auto-follow)', v_pairs[i][1], v_pairs[i][2], v_moved;

    -- Case C: Old missing — already cleaned or never existed
    ELSIF v_old_id IS NULL THEN
      RAISE NOTICE 'C) % already cleaned (canonical % exists: %)', v_pairs[i][1], v_pairs[i][2], (v_new_id IS NOT NULL);

    ELSE
      RAISE NOTICE 'SKIP: % == %', v_pairs[i][1], v_pairs[i][2];
    END IF;

    RAISE NOTICE '';
  END LOOP;
END $$;


-- ============================================================
-- plant-nursery (true duplicate slug across 2 parents)
-- ============================================================
DO $$
DECLARE
  v_keep_id INT;
  v_drop_id INT;
BEGIN
  SELECT c.id INTO v_keep_id
    FROM categories c
    JOIN categories p ON p.id = c.parent_id
   WHERE c.slug = 'plant-nursery' AND p.slug = 'agri-business'
   LIMIT 1;

  SELECT c.id INTO v_drop_id
    FROM categories c
    JOIN categories p ON p.id = c.parent_id
   WHERE c.slug = 'plant-nursery' AND p.slug = 'retail-shopping'
   LIMIT 1;

  IF v_keep_id IS NULL OR v_drop_id IS NULL THEN
    RAISE NOTICE 'plant-nursery: already deduplicated or not present';
    RETURN;
  END IF;

  UPDATE businesses SET category_id     = v_keep_id WHERE category_id     = v_drop_id;
  UPDATE businesses SET sub_category_id = v_keep_id WHERE sub_category_id = v_drop_id;
  BEGIN
    UPDATE businesses
       SET secondary_category_ids = array_replace(secondary_category_ids, v_drop_id, v_keep_id)
     WHERE secondary_category_ids @> ARRAY[v_drop_id];
  EXCEPTION WHEN undefined_column THEN NULL; END;

  DELETE FROM categories WHERE id = v_drop_id;
  RAISE NOTICE 'plant-nursery: deduplicated retail-shopping copy';
END $$;


NOTIFY pgrst, 'reload schema';
COMMIT;


-- ============================================================
-- Verify
-- ============================================================
SELECT
  'VERIFY' AS status,
  slug,
  name,
  (SELECT COUNT(*) FROM businesses WHERE category_id = c.id OR sub_category_id = c.id) AS shop_count
FROM categories c
WHERE slug IN ('kirana-grocery','grocery','bakery-cake','bakery','footwear-shop','footwear','gift-shop','gift-stationery','music-dance-class','music-class','plant-nursery')
ORDER BY slug;
