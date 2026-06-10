-- =====================================================
-- db/123-merge-duplicate-categories.sql
-- =====================================================
-- USER BUG (2026-06-08): Searching "Kirana / Grocery Store" returns
-- "No shops found" — but shops ARE registered in that category.
--
-- ROOT CAUSE: categories.json had DUPLICATE slugs for the same concept:
--   - kirana-grocery  (under food-beverage)    ← canonical
--   - grocery         (under retail-shopping)  ← duplicate
--
-- Shops registered under one slug don't show when searching the other.
--
-- Same issue affects 4 more pairs:
--   bakery        ↔ bakery-cake
--   footwear      ↔ footwear-shop
--   gift-shop     ↔ gift-stationery
--   music-class   ↔ music-dance-class
--   plant-nursery (SAME slug, 2 different parents — true duplicate)
--
-- THIS FILE:
--   1. Identifies each "old" duplicate slug
--   2. Re-points every shop using it to the "canonical" slug
--   3. Updates secondary_category_ids array if needed
--   4. Deletes the empty deprecated row (so admin doesn't see ghost)
--
-- ZERO DATA LOSS — shops stay where they are visually + searchable
-- under canonical slug.
--
-- IDEMPOTENT — safe to re-run anytime.
-- =====================================================

BEGIN;

-- ============================================================
-- Helper: merge one pair (move shops from OLD → NEW, delete OLD)
-- ============================================================
DO $$
DECLARE
  v_old_id   INT;
  v_new_id   INT;
  v_moved    INT;
  v_pair     RECORD;
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

    -- Resolve IDs
    SELECT id INTO v_old_id FROM categories WHERE slug = v_pairs[i][1] LIMIT 1;
    SELECT id INTO v_new_id FROM categories WHERE slug = v_pairs[i][2] LIMIT 1;

    IF v_old_id IS NULL THEN
      RAISE NOTICE 'SKIP: old slug "%" not found (already deleted?)', v_pairs[i][1];
      CONTINUE;
    END IF;
    IF v_new_id IS NULL THEN
      RAISE NOTICE 'SKIP: canonical slug "%" missing — refusing to delete data', v_pairs[i][2];
      CONTINUE;
    END IF;
    IF v_old_id = v_new_id THEN
      RAISE NOTICE 'SKIP: % == % (already same)', v_pairs[i][1], v_pairs[i][2];
      CONTINUE;
    END IF;

    -- 1. Update primary category_id
    UPDATE businesses
       SET category_id = v_new_id
     WHERE category_id = v_old_id;
    GET DIAGNOSTICS v_moved = ROW_COUNT;
    RAISE NOTICE '  % shops moved on primary category (% → %)', v_moved, v_pairs[i][1], v_pairs[i][2];

    -- 2. Update sub_category_id
    UPDATE businesses
       SET sub_category_id = v_new_id
     WHERE sub_category_id = v_old_id;
    GET DIAGNOSTICS v_moved = ROW_COUNT;
    RAISE NOTICE '  % shops moved on sub_category (% → %)', v_moved, v_pairs[i][1], v_pairs[i][2];

    -- 3. Update secondary_category_ids array (if column exists)
    BEGIN
      UPDATE businesses
         SET secondary_category_ids = array_replace(secondary_category_ids, v_old_id, v_new_id)
       WHERE secondary_category_ids @> ARRAY[v_old_id];
      GET DIAGNOSTICS v_moved = ROW_COUNT;
      RAISE NOTICE '  % shops moved on secondary_categories array (% → %)', v_moved, v_pairs[i][1], v_pairs[i][2];
    EXCEPTION WHEN undefined_column THEN
      -- column doesn't exist on this schema, skip silently
      NULL;
    END;

    -- 4. Now safe to delete the empty deprecated row
    DELETE FROM categories WHERE id = v_old_id;
    RAISE NOTICE '  ✓ Deleted deprecated row [% / %]', v_pairs[i][1], v_old_id;
    RAISE NOTICE '';
  END LOOP;
END $$;


-- ============================================================
-- Handle the TRUE duplicate-slug case: plant-nursery
-- (same slug appears under 2 different parents — pick the agri-business one)
-- ============================================================
DO $$
DECLARE
  v_keep_id INT;
  v_drop_id INT;
  v_moved   INT;
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
    RAISE NOTICE 'plant-nursery dedup: already cleaned or not present';
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
  RAISE NOTICE '✓ plant-nursery: deduplicated retail-shopping copy';
END $$;


-- ============================================================
-- Schema cache reload so frontend sees the change immediately
-- ============================================================
NOTIFY pgrst, 'reload schema';

COMMIT;


-- ============================================================
-- Summary report
-- ============================================================
DO $$
DECLARE
  v_total INT;
BEGIN
  SELECT COUNT(*) INTO v_total FROM categories;
  RAISE NOTICE '====================================================';
  RAISE NOTICE 'CATEGORY DEDUP COMPLETE';
  RAISE NOTICE '====================================================';
  RAISE NOTICE 'Total categories after dedup: %', v_total;
  RAISE NOTICE 'Search by canonical slugs now returns ALL shops:';
  RAISE NOTICE '  kirana-grocery        (was: + grocery)';
  RAISE NOTICE '  bakery-cake           (was: + bakery)';
  RAISE NOTICE '  footwear-shop         (was: + footwear)';
  RAISE NOTICE '  gift-shop             (was: + gift-stationery)';
  RAISE NOTICE '  music-dance-class     (was: + music-class)';
  RAISE NOTICE '  plant-nursery         (now only under agri-business)';
  RAISE NOTICE '====================================================';
END $$;
