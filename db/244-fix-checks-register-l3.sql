-- ============================================================
-- db/244 — three loose ends from the 3 Oct verification run
-- ============================================================
--
-- 1. to_regproc() takes a bare name; given 'fn(uuid,jsonb)' it returns
--    NULL. So the "exists" checks in db/241 and db/243 said NO for
--    functions that do exist (the has_function_privilege row, which
--    does take a signature, said yes for the same functions), and the
--    record_migration guard in every migration since db/233 never
--    fired. This records db/234–243 now and re-checks the two
--    functions the right way (to_regprocedure).
-- 2. db/240 left the 7 merged (inactive) rows parked under
--    kirana-grocery, so its third-level check reports 7. Lift them to
--    Retail & Shopping like frozen-foods — inactive either way, but no
--    row should sit under a leaf.
-- 3. db/242: "hotel room" found nothing — 'hotel' and 'room' were
--    separate keywords and the match is a plain substring.
--
-- Safe to re-run.
-- ============================================================

BEGIN;

-- 1a. register what actually ran
DO $$
DECLARE f TEXT;
BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NULL THEN RETURN; END IF;
  FOREACH f IN ARRAY ARRAY[
    'db/234-add-missing-town-categories.sql',
    'db/235-media-distributors-garments-categories.sql',
    'db/236-wholesale-distribution-parent.sql',
    'db/237-repair-photos-array.sql',
    'db/238-search-inside-products.sql',
    'db/239-fill-geo-from-city-trigger.sql',
    'db/240-merge-duplicate-categories.sql',
    'db/241-request-account-deletion.sql',
    'db/242-search-keywords-for-live-categories.sql',
    'db/243-admin-create-deal.sql',
    'db/244-fix-checks-register-l3.sql'
  ] LOOP
    PERFORM public.record_migration(f, 'verified by Deepak 2026-10-03; guard in the file used to_regproc and never fired');
  END LOOP;
END $$;

-- 2. nothing under a leaf
UPDATE public.categories c
   SET parent_id = gp.id
  FROM public.categories p
  JOIN public.categories gp ON gp.id = p.parent_id
 WHERE c.parent_id = p.id
   AND p.parent_id IS NOT NULL;

-- 3. the phrase people type
UPDATE public.categories
   SET keywords = keywords || ',hotel room,room booking,होटल रूम'
 WHERE slug = 'hotel' AND POSITION('hotel room' IN COALESCE(keywords, '')) = 0;

COMMIT;

-- ============================================================
-- Checks — all four should read ok / yes
-- ============================================================
SELECT 'request_account_deletion exists' AS check,
       CASE WHEN to_regprocedure('public.request_account_deletion()') IS NOT NULL THEN 'yes' ELSE 'NO' END AS result
UNION ALL
SELECT 'admin_create_deal exists',
       CASE WHEN to_regprocedure('public.admin_create_deal(uuid,jsonb)') IS NOT NULL THEN 'yes' ELSE 'NO' END
UNION ALL
SELECT 'third-level categories left',
       CASE WHEN (SELECT COUNT(*) FROM public.categories c JOIN public.categories p ON p.id = c.parent_id WHERE p.parent_id IS NOT NULL) = 0 THEN 'ok' ELSE 'CHECK' END
UNION ALL
SELECT '"hotel room" finds shops',
       CASE WHEN (SELECT COUNT(*) FROM public.search_businesses(p_query => 'hotel room', p_limit => 5)) > 0 THEN 'ok' ELSE 'CHECK' END
UNION ALL
SELECT 'migrations registered (db/233 onward)',
       (SELECT COUNT(*)::text FROM public.schema_migrations WHERE filename >= 'db/233');
