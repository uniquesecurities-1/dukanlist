-- ============================================================
-- db/240 — one trade, one category
-- ============================================================
--
-- Full-site review, 2026-09-29. The category table has grown to 439 rows
-- over 240 migrations, and 19 of them are the same trade twice under two
-- slugs — some with identical English names (two "Ice Cream Parlour",
-- two "Dietician / Nutritionist", two Mehndi artists spelt differently).
-- A shopkeeper filing under one never appears on the other's page, and
-- the picker shows both, so the next shopkeeper has to guess.
--
-- Eight more rows are filed UNDER kirana-grocery, which is itself a leaf
-- under Retail & Shopping. Every picker on the site lists one level
-- below a top-level parent, so those eight (atta-chakki, milk-booth,
-- sabzi-shop…) have been invisible since the day they were added. Seven
-- duplicate a visible category and are merged into it; frozen-foods is
-- unique and is simply lifted up to Retail & Shopping.
--
-- Deliberately NOT merged, because the trade is different even when the
-- word is shared: retail vs wholesale pairs (kirana-grocery /
-- wholesale-kirana), dairy-farm (producer) vs dairy-milk (shop),
-- coaching-institute vs tuition-coaching, puncture-shop vs tyre-shop,
-- school vs school-govt / school-private, mechanic-2w vs mechanic-4w.
--
-- HOW A MERGE WORKS HERE
--   business_categories carries every shop ↔ category link and two
--   triggers hang off it: trg_update_cat_count keeps categories.
--   business_count right on INSERT/DELETE, and trg_sync_primary_cat
--   writes businesses.category_id + sub_category_id whenever a row
--   becomes primary. So the merge never UPDATEs a link row (neither
--   trigger would fire); it DELETEs the loser's link and INSERTs the
--   winner's, and both triggers do their job. A shop that already had
--   the winner as a second category just keeps it (and inherits
--   primary if the loser was primary).
--
-- Losers are deactivated, not deleted: their slugs stay resolvable
-- (/local/<city>/<old-slug> answers with the empty, noindex page) and
-- nothing else references a missing id. Safe to re-run: on a second run
-- no link rows match and the UPDATEs are no-ops.
-- ============================================================

BEGIN;

CREATE TEMP TABLE _merge (loser TEXT, winner TEXT, why TEXT);
INSERT INTO _merge VALUES
  -- identical or near-identical name
  ('ice-cream-parlour',  'ice-cream',              'same name, ice-cream has the shops'),
  ('dietician',          'diet-nutrition',         'same name, diet-nutrition has the shop and sits in Healthcare'),
  ('mehendi-artist',     'mehndi-artist',          'spelling'),
  ('temple-mandir',      'mandir',                 'same trade, word order'),
  ('advocate',           'lawyer',                 'same trade'),
  ('gym-fitness',        'gym',                    'same trade, gym has the shop'),
  ('computer-class',     'computer-classes',       'singular/plural'),
  ('dhaba-roadside',     'dhaba',                  'same trade'),
  ('solar-inverter',     'solar-inverter-battery', 'same trade, the winner sits under Energy & Solar'),
  ('dry-fruits',         'mewa-dryfruits',         'same trade; retail shop belongs in Retail'),
  ('agri-vet-doctor',    'veterinary',             'one vet in a mandi town sees cattle and pets alike'),
  ('veterinary-doctor',  'veterinary',             'same trade'),
  -- third-level rows nobody could pick, each duplicating a visible one
  ('atta-chakki',        'flour-mill',             'L3 under kirana; flour-mill has 4 shops'),
  ('provision-store',    'general-store',          'L3 under kirana; same trade'),
  ('cattle-feed',        'cattle-feed-shop',       'L3 under kirana; same trade'),
  ('fruit-shop',         'fruit-vegetable',        'L3 under kirana; same trade'),
  ('sabzi-shop',         'fruit-vegetable',        'L3 under kirana; same trade'),
  ('milk-booth',         'dairy-milk',             'L3 under kirana; same trade'),
  ('pet-supplies',       'pet-shop',               'L3 under kirana; same trade');

-- Guard: every slug in the table must exist, and no winner may itself be
-- a loser (a chain would leave shops on a deactivated row).
DO $$
DECLARE v_missing TEXT; v_chain TEXT;
BEGIN
  SELECT string_agg(s, ', ') INTO v_missing
    FROM (SELECT loser AS s FROM _merge UNION SELECT winner FROM _merge) x
   WHERE NOT EXISTS (SELECT 1 FROM public.categories c WHERE c.slug = x.s);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'db/240: unknown category slug(s): %', v_missing;
  END IF;
  SELECT string_agg(winner, ', ') INTO v_chain
    FROM _merge WHERE winner IN (SELECT loser FROM _merge);
  IF v_chain IS NOT NULL THEN
    RAISE EXCEPTION 'db/240: winner is also a loser: %', v_chain;
  END IF;
END $$;

-- 1. move every shop link from loser to winner ---------------------
DO $$
DECLARE
  m   RECORD;
  r   RECORD;
  v_loser_id  INT;
  v_winner_id INT;
BEGIN
  FOR m IN SELECT loser, winner FROM _merge LOOP
    SELECT id INTO v_loser_id  FROM public.categories WHERE slug = m.loser;
    SELECT id INTO v_winner_id FROM public.categories WHERE slug = m.winner;

    FOR r IN SELECT business_id, is_primary
               FROM public.business_categories
              WHERE category_id = v_loser_id
    LOOP
      DELETE FROM public.business_categories
       WHERE business_id = r.business_id AND category_id = v_loser_id;

      IF EXISTS (SELECT 1 FROM public.business_categories
                  WHERE business_id = r.business_id AND category_id = v_winner_id) THEN
        IF r.is_primary THEN
          UPDATE public.business_categories
             SET is_primary = TRUE
           WHERE business_id = r.business_id AND category_id = v_winner_id;
        END IF;
      ELSE
        INSERT INTO public.business_categories (business_id, category_id, is_primary)
        VALUES (r.business_id, v_winner_id, r.is_primary);
      END IF;
    END LOOP;

    -- Legacy rows that point at the loser directly without a link row.
    UPDATE public.businesses b
       SET sub_category_id = v_winner_id,
           category_id     = COALESCE((SELECT parent_id FROM public.categories WHERE id = v_winner_id), b.category_id)
     WHERE b.sub_category_id = v_loser_id;
    UPDATE public.businesses b
       SET category_id     = COALESCE((SELECT parent_id FROM public.categories WHERE id = v_winner_id), v_winner_id),
           sub_category_id = v_winner_id
     WHERE b.category_id = v_loser_id;
  END LOOP;
END $$;

-- 2. losers off the menu; their count is now 0 by construction -------
UPDATE public.categories
   SET active = FALSE,
       business_count = 0
 WHERE slug IN (SELECT loser FROM _merge);

-- 3. the one third-level row that is unique: lift it to Retail --------
UPDATE public.categories c
   SET parent_id = p.id
  FROM public.categories p
 WHERE p.slug = 'retail-shopping' AND p.parent_id IS NULL
   AND c.slug = 'frozen-foods';

-- 4. winners whose name should now cover both halves ------------------
UPDATE public.categories
   SET name = 'Veterinary / Animal & Pet Doctor', name_hi = 'पशु चिकित्सक (पालतू एवं पशुधन)'
 WHERE slug = 'veterinary';
UPDATE public.categories
   SET name = 'Lawyer / Advocate', name_hi = 'वकील / एडवोकेट'
 WHERE slug = 'lawyer';
UPDATE public.categories
   SET name = 'Mehndi / Mehendi Artist'
 WHERE slug = 'mehndi-artist';

DO $$ BEGIN
  IF to_regproc('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/240-merge-duplicate-categories.sql');
  END IF;
END $$;

COMMIT;

-- ============================================================
-- Checks (read-only).
--  1. every loser: inactive, 0 links, 0 shops pointing at it
--  2. every winner: business_count equals its real link count
--  3. nothing is filed under a non-top-level parent any more
-- ============================================================
SELECT m.loser,
       l.active                                                          AS loser_active,
       (SELECT COUNT(*) FROM public.business_categories WHERE category_id = l.id) AS loser_links,
       (SELECT COUNT(*) FROM public.businesses WHERE sub_category_id = l.id OR category_id = l.id) AS loser_shops,
       m.winner,
       w.business_count                                                  AS winner_count,
       (SELECT COUNT(*) FROM public.business_categories WHERE category_id = w.id) AS winner_links,
       CASE WHEN l.active = FALSE
             AND (SELECT COUNT(*) FROM public.business_categories WHERE category_id = l.id) = 0
             AND (SELECT COUNT(*) FROM public.businesses WHERE sub_category_id = l.id OR category_id = l.id) = 0
             AND w.business_count = (SELECT COUNT(*) FROM public.business_categories WHERE category_id = w.id)
            THEN 'ok' ELSE 'CHECK — tell Claude' END                    AS result
FROM _merge m
JOIN public.categories l ON l.slug = m.loser
JOIN public.categories w ON w.slug = m.winner
ORDER BY (CASE WHEN l.active = FALSE THEN 1 ELSE 0 END), m.loser;

SELECT 'third-level categories left' AS check, COUNT(*) AS n,
       CASE WHEN COUNT(*) = 0 THEN 'ok' ELSE 'CHECK — tell Claude' END AS result
FROM public.categories c
JOIN public.categories p ON p.id = c.parent_id
WHERE p.parent_id IS NOT NULL;
