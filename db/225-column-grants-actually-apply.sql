-- ============================================================
-- db/225 — make the db/219 column locks ACTUALLY take effect
-- ============================================================
--
-- WHAT HAPPENED
--   Deepak ran db/219. It reported no error. Parts of it worked:
--   the open write policies really are gone (verified live — anon
--   INSERT into shop_likes and search_log now returns 42501).
--
--   But §2, the column locks, did nothing at all. Verified live on
--   2026-09-21 with nothing but the public anon key:
--
--     SELECT email, canonical_mobile, claim_token, notes_internal,
--            admin_notes, consent_notes, pre_listed_by, pending_edits
--     FROM businesses;        -> all 8 columns returned
--
--   A real owner login email and a real mobile number came back.
--
-- WHY IT SILENTLY FAILED
--   This is a PostgreSQL rule that bites everyone once:
--
--     Column privileges ADD to table privileges. They cannot
--     subtract from them.
--
--   db/02 granted anon SELECT on the WHOLE businesses table. Once
--   that table-wide grant exists, REVOKE SELECT (email) ... FROM anon
--   has nothing to remove — the permission anon is using comes from
--   the table-level grant, not a column-level one. Postgres does not
--   warn. It reports success and changes nothing.
--
--   That is exactly why db/219 looked like it worked.
--
-- THE ONLY CORRECT SHAPE
--   Drop the table-wide grant first, then hand back the columns that
--   are genuinely public:
--
--     REVOKE SELECT ON t FROM role;            -- remove the blanket
--     GRANT  SELECT (a, b, c) ON t TO role;    -- list what is public
--
--   The public list is built here from information_schema rather than
--   typed out, so this file cannot drift out of step with the table.
--
-- ⚠ ONE CONSEQUENCE, ON PURPOSE
--   After this runs, businesses/reviews/shop_questions stop being
--   "public by default". A column added LATER will not be readable by
--   anon until it is granted. That is the safe direction — a new
--   column is far more likely to be internal than public, and a
--   missing field is a visible bug, while a leaked one is silent.
--   If you add a public column later, grant it:
--       GRANT SELECT (new_col) ON public.businesses TO anon;
--
-- Requires db/219 to have been run. Safe to re-run.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. businesses — hide the 8 internal columns from anon
--
-- alt_mobile is deliberately NOT secret: the owner sets it himself
-- in panel/profile.html as a backup number so a customer can reach
-- him when the main line does not answer, and business.html renders
-- it as a public click-to-call chip.
--
-- `authenticated` keeps full table access: the owner panel and the
-- admin screens read email and the internal notes, and both already
-- sit behind RLS that limits a logged-in user to his own shop.
-- ------------------------------------------------------------
DO $$
DECLARE
  v_secret TEXT[] := ARRAY[
    'claim_token', 'canonical_mobile', 'notes_internal', 'admin_notes',
    'consent_notes', 'pre_listed_by', 'pending_edits', 'email'
  ];
  v_public TEXT;
  v_n      INT;
BEGIN
  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position),
         count(*)
    INTO v_public, v_n
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name   = 'businesses'
    AND NOT (column_name = ANY(v_secret));

  IF v_public IS NULL THEN
    RAISE EXCEPTION 'businesses has no public columns — refusing to lock the table out entirely';
  END IF;

  -- Order matters. The blanket grant has to go first, or the grant
  -- below is just a no-op on top of it — the db/219 mistake again.
  REVOKE SELECT ON public.businesses FROM anon;
  EXECUTE format('GRANT SELECT (%s) ON public.businesses TO anon', v_public);

  RAISE NOTICE 'businesses: anon can now read % of % columns; % hidden',
               v_n, v_n + array_length(v_secret, 1), array_length(v_secret, 1);
END $$;


-- ------------------------------------------------------------
-- 2. reviews.customer_phone_hash / shop_questions.asker_phone_hash
--
-- Unsalted SHA-256 over a 10-digit space is not a one-way door:
-- all 10^10 candidates can be hashed in minutes on a laptop, so the
-- hash IS the phone number. Leaving it readable let anyone work out
-- who left a one-star review. Hidden from `authenticated` too — a
-- logged-in shopkeeper is exactly the person with a motive.
--
-- Nothing breaks: admin/reviews.html gets these rows through
-- admin_list_all_reviews / admin_pending_reviews, which are
-- SECURITY DEFINER and are not affected by column grants.
-- ------------------------------------------------------------
DO $$
DECLARE
  r RECORD;
  v_public TEXT;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('reviews',        'customer_phone_hash'),
      ('shop_questions', 'asker_phone_hash')
    ) AS t(tbl, secret_col)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name=r.tbl AND column_name=r.secret_col
    ) THEN
      RAISE NOTICE '%.% does not exist — skipped', r.tbl, r.secret_col;
      CONTINUE;
    END IF;

    SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
      INTO v_public
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name=r.tbl AND column_name <> r.secret_col;

    EXECUTE format('REVOKE SELECT ON public.%I FROM anon, authenticated', r.tbl);
    EXECUTE format('GRANT SELECT (%s) ON public.%I TO anon, authenticated', v_public, r.tbl);

    RAISE NOTICE '%: % is now hidden from anon and authenticated', r.tbl, r.secret_col;
  END LOOP;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- ============================================================
-- PROOF, not assumption.
--
-- db/219 is the reason this block exists: it announced success and
-- changed nothing, and nobody found out for weeks. So this reads the
-- privileges back out of the catalog and fails loudly if any secret
-- column is still reachable by anon.
-- ============================================================
DO $$
DECLARE
  v_leaked TEXT;
BEGIN
  SELECT string_agg(x.tbl || '.' || x.col, ', ')
    INTO v_leaked
  FROM (
    SELECT 'businesses' AS tbl, unnest(ARRAY[
             'claim_token','canonical_mobile','notes_internal','admin_notes',
             'consent_notes','pre_listed_by','pending_edits','email']) AS col
    UNION ALL SELECT 'reviews',        'customer_phone_hash'
    UNION ALL SELECT 'shop_questions', 'asker_phone_hash'
  ) x
  WHERE EXISTS (
    SELECT 1 FROM information_schema.column_privileges p
    WHERE p.table_schema = 'public'
      AND p.table_name   = x.tbl
      AND p.column_name  = x.col
      AND p.grantee      = 'anon'
      AND p.privilege_type = 'SELECT'
  );

  IF v_leaked IS NOT NULL THEN
    RAISE EXCEPTION 'db/225 FAILED — anon can still read: %', v_leaked;
  END IF;

  RAISE NOTICE '--------------------------------------------------';
  RAISE NOTICE 'db/225 OK. Verified against the catalog:';
  RAISE NOTICE '  anon can no longer SELECT any of the 10 secret columns.';
  RAISE NOTICE 'Next: reload dukanlist.com and open any shop page.';
  RAISE NOTICE '--------------------------------------------------';
END $$;
