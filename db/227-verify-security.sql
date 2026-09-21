-- ============================================================
-- db/227 — READ-ONLY. Reports the true state of every db/219 and
--          db/225 item. Changes nothing. Safe to run any time.
-- ============================================================
--
-- WHY THIS EXISTS
--   db/219 said it had hardened six things. It ran without error.
--   Checking from the browser today found that its column locks had
--   silently done nothing (db/225 explains and fixes that), while
--   other parts of it HAD applied. "It ran" told us nothing.
--
--   And from the client there is a limit to what can be known:
--   PostgREST filters rows by RLS before returning them, so an empty
--   result means EITHER "RLS is protecting this" OR "the table is
--   simply empty". I could not tell those apart from outside, and I
--   have guessed wrong on exactly that before (leads_log).
--
--   Inside the database the policies are visible. So this asks
--   Postgres directly, and prints PASS or FAIL per item.
--
-- WHAT IT DOES NOT COVER
--   §1 below is the most serious item in db/219 — a logged-in user
--   making themselves owner of any shop — and it is the one thing
--   that could not be tested from a browser without an account.
--   This settles it.
-- ============================================================

\echo ''
\echo '=== db/219 + db/225 — actual state ==================='
\echo ''

DO $$
DECLARE
  v_fail INT := 0;
  v_n    INT;
  c      TEXT;
BEGIN
  ---------------------------------------------------------------
  -- 1. CRITICAL: ownership self-grant (db/219 §1)
  --    p_owners_self_insert let any authenticated user INSERT a row
  --    into business_owners for ANY business_id.
  ---------------------------------------------------------------
  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='public' AND tablename='business_owners'
     AND policyname='p_owners_self_insert';
  IF v_n > 0 THEN
    v_fail := v_fail + 1;
    RAISE WARNING 'FAIL  §1  p_owners_self_insert STILL EXISTS — any logged-in user can claim any shop';
  ELSE
    RAISE NOTICE 'PASS  §1  ownership self-insert policy is gone';
  END IF;

  ---------------------------------------------------------------
  -- 2. Secret columns must not be granted to anon (db/219 §2 / db/225)
  ---------------------------------------------------------------
  FOR c IN SELECT unnest(ARRAY['claim_token','canonical_mobile','notes_internal',
                               'admin_notes','consent_notes','pre_listed_by',
                               'pending_edits','email'])
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.column_privileges
                WHERE table_schema='public' AND table_name='businesses'
                  AND column_name=c AND grantee='anon' AND privilege_type='SELECT') THEN
      v_fail := v_fail + 1;
      RAISE WARNING 'FAIL  §2  anon can still SELECT businesses.%', c;
    END IF;
  END LOOP;
  IF v_fail = 0 OR TRUE THEN
    RAISE NOTICE 'PASS/FAIL §2 reported above (silence = all eight columns locked)';
  END IF;

  -- alt_mobile must STILL be public — it is the owner's backup number
  IF NOT EXISTS (SELECT 1 FROM information_schema.column_privileges
                  WHERE table_schema='public' AND table_name='businesses'
                    AND column_name='alt_mobile' AND grantee='anon' AND privilege_type='SELECT') THEN
    v_fail := v_fail + 1;
    RAISE WARNING 'FAIL  §2  alt_mobile is NOT readable by anon — the click-to-call chip will be blank';
  ELSE
    RAISE NOTICE 'PASS  §2  alt_mobile still public, as intended';
  END IF;

  ---------------------------------------------------------------
  -- 3 + 4. Always-true write policies (db/219 §3/§4)
  ---------------------------------------------------------------
  FOR c IN SELECT unnest(ARRAY['push_delete_own','push_insert_any',
                               'shop_likes_anon_insert','search_log_anon_insert',
                               'reports_insert_anon'])
  LOOP
    SELECT count(*) INTO v_n FROM pg_policies WHERE schemaname='public' AND policyname=c;
    IF v_n > 0 THEN
      v_fail := v_fail + 1;
      RAISE WARNING 'FAIL  §3/4  open write policy still present: %', c;
    END IF;
  END LOOP;
  RAISE NOTICE 'PASS/FAIL §3/4 reported above (silence = all five open policies dropped)';

  ---------------------------------------------------------------
  -- 5. Phone hashes hidden from anon AND authenticated (db/225)
  --    Unsalted SHA-256 over ten digits is not a one-way door.
  ---------------------------------------------------------------
  IF EXISTS (SELECT 1 FROM information_schema.column_privileges
              WHERE table_schema='public' AND table_name='reviews'
                AND column_name='customer_phone_hash'
                AND grantee IN ('anon','authenticated') AND privilege_type='SELECT') THEN
    v_fail := v_fail + 1;
    RAISE WARNING 'FAIL  §5  reviews.customer_phone_hash is still readable';
  ELSE
    RAISE NOTICE 'PASS  §5  reviewer phone hash is hidden';
  END IF;

  ---------------------------------------------------------------
  -- 6. The spam keyword list stays private (db/219 §5)
  ---------------------------------------------------------------
  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='public' AND tablename='blocked_keywords' AND policyname='bk_read_all';
  IF v_n > 0 THEN
    v_fail := v_fail + 1;
    RAISE WARNING 'FAIL  §6  bk_read_all still exposes the spam filter list';
  ELSE
    RAISE NOTICE 'PASS  §6  blocked_keywords is private';
  END IF;

  ---------------------------------------------------------------
  RAISE NOTICE '';
  IF v_fail = 0 THEN
    RAISE NOTICE '================ ALL CHECKS PASSED ================';
  ELSE
    RAISE NOTICE '================ % CHECK(S) FAILED — see WARNINGs above ================', v_fail;
  END IF;
END $$;

\echo ''
\echo '--- every policy currently on the sensitive tables ---'
SELECT tablename, policyname, cmd, roles::text
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('business_owners','businesses','push_subscriptions',
                    'shop_likes','search_log','business_reports',
                    'blocked_keywords','reviews','shop_questions','rank_snapshots')
ORDER BY tablename, policyname;
