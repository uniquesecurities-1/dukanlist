-- ============================================================
-- db/227 — READ-ONLY security report. Changes nothing.
-- ============================================================
--
-- Paste the whole thing into the Supabase SQL Editor and Run.
-- It returns a TABLE of checks. Every row should say PASS.
--
-- v2: the first version used \echo, which is a psql meta-command.
-- The Supabase SQL Editor talks to Postgres directly and has no idea
-- what a backslash command is, so it failed at line 28 with
-- "42601: syntax error at or near \". It also swallows RAISE NOTICE
-- output, so a DO block would have run and shown Deepak nothing.
-- Rewritten as a plain SELECT, because the editor renders rows.
--
-- WHY THIS EXISTS
--   db/219 claimed six fixes and ran without error. Checking today
--   showed its column locks had silently done nothing, while other
--   parts HAD applied. "It ran" meant nothing.
--
--   And from a browser there is a hard limit: PostgREST applies RLS
--   before returning rows, so an empty result means EITHER "RLS is
--   protecting this" OR "the table is empty". Those cannot be told
--   apart from outside. Inside the database, policies are visible.
--
--   §1 below is the most serious item in db/219 — a logged-in user
--   making themselves owner of any shop — and it is the one thing
--   that could not be tested without an account. This settles it.
-- ============================================================

SELECT * FROM (

  -- §1  CRITICAL: could any logged-in user claim any shop?
  SELECT 1 AS n,
         'ownership self-insert policy is gone' AS item,
         CASE WHEN EXISTS (
                SELECT 1 FROM pg_policies
                 WHERE schemaname='public' AND tablename='business_owners'
                   AND policyname='p_owners_self_insert')
              THEN 'FAIL — any logged-in user can still claim ANY shop'
              ELSE 'PASS' END AS result

  UNION ALL
  -- §2  the eight secret columns must not be granted to anon
  SELECT 2,
         'businesses: 8 secret columns hidden from anon',
         CASE WHEN count(*) = 0 THEN 'PASS'
              ELSE 'FAIL — anon can still read: ' || string_agg(column_name, ', ') END
  FROM information_schema.column_privileges
  WHERE table_schema='public' AND table_name='businesses'
    AND grantee='anon' AND privilege_type='SELECT'
    AND column_name IN ('claim_token','canonical_mobile','notes_internal','admin_notes',
                        'consent_notes','pre_listed_by','pending_edits','email')

  UNION ALL
  -- §2b alt_mobile must STAY public — the owner's own backup number,
  --     rendered as a click-to-call chip on every listing page.
  SELECT 3,
         'businesses.alt_mobile is still PUBLIC (must be)',
         CASE WHEN EXISTS (
                SELECT 1 FROM information_schema.column_privileges
                 WHERE table_schema='public' AND table_name='businesses'
                   AND column_name='alt_mobile' AND grantee='anon' AND privilege_type='SELECT')
              THEN 'PASS'
              ELSE 'FAIL — the click-to-call chip will be blank everywhere' END

  UNION ALL
  -- §3/§4  the always-true write policies
  SELECT 4,
         'open write policies dropped (push/likes/search/reports)',
         CASE WHEN count(*) = 0 THEN 'PASS'
              ELSE 'FAIL — still present: ' || string_agg(policyname, ', ') END
  FROM pg_policies
  WHERE schemaname='public'
    AND policyname IN ('push_delete_own','push_insert_any','shop_likes_anon_insert',
                       'search_log_anon_insert','reports_insert_anon')

  UNION ALL
  -- §5  reviewer phone hash: unsalted SHA-256 over 10 digits is reversible
  SELECT 5,
         'reviews.customer_phone_hash hidden from anon + authenticated',
         CASE WHEN count(*) = 0 THEN 'PASS'
              ELSE 'FAIL — readable by: ' || string_agg(DISTINCT grantee, ', ') END
  FROM information_schema.column_privileges
  WHERE table_schema='public' AND table_name='reviews'
    AND column_name='customer_phone_hash'
    AND grantee IN ('anon','authenticated') AND privilege_type='SELECT'

  UNION ALL
  SELECT 6,
         'shop_questions.asker_phone_hash hidden from anon + authenticated',
         CASE WHEN count(*) = 0 THEN 'PASS'
              ELSE 'FAIL — readable by: ' || string_agg(DISTINCT grantee, ', ') END
  FROM information_schema.column_privileges
  WHERE table_schema='public' AND table_name='shop_questions'
    AND column_name='asker_phone_hash'
    AND grantee IN ('anon','authenticated') AND privilege_type='SELECT'

  UNION ALL
  -- §6  the spam-filter keyword list must stay private
  SELECT 7,
         'blocked_keywords spam list is private',
         CASE WHEN EXISTS (
                SELECT 1 FROM pg_policies
                 WHERE schemaname='public' AND tablename='blocked_keywords'
                   AND policyname='bk_read_all')
              THEN 'FAIL — bk_read_all still exposes the spam filter'
              ELSE 'PASS' END

  UNION ALL
  -- rank history is the shop's own business (db/224)
  SELECT 8,
         'rank_snapshots not granted to anon/authenticated',
         CASE WHEN count(*) = 0 THEN 'PASS'
              ELSE 'FAIL — readable by: ' || string_agg(DISTINCT grantee, ', ') END
  FROM information_schema.table_privileges
  WHERE table_schema='public' AND table_name='rank_snapshots'
    AND grantee IN ('anon','authenticated') AND privilege_type='SELECT'

) AS report
ORDER BY n;


-- ============================================================
-- OPTIONAL — run this separately if anything above says FAIL.
-- It lists every policy currently on the sensitive tables.
-- ============================================================
-- SELECT tablename, policyname, cmd, roles::text, qual
-- FROM pg_policies
-- WHERE schemaname = 'public'
--   AND tablename IN ('business_owners','businesses','push_subscriptions',
--                     'shop_likes','search_log','business_reports',
--                     'blocked_keywords','reviews','shop_questions','rank_snapshots')
-- ORDER BY tablename, policyname;
