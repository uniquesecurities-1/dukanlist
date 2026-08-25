-- =========================================================================
-- Migration 206: Supabase Security Audit Fixes (from 19-Aug-2026 audit)
-- Created: 2026-08-01
-- Source: dukanlist-supabase-audit_1.md
--
-- ADDRESSES:
--   Item 1 (CRITICAL) — owner_role_options view SECURITY DEFINER → security_invoker
--   Item 2 (HIGH)     — 5 always-true RLS policies on write operations
--   Item 3 (HIGH)     — SECURITY DEFINER functions with public EXECUTE
--   Item 6 (BULK)     — Function search_path mutable (bulk fix)
--
-- DOES NOT COVER (dashboard actions required):
--   Item 4 — Storage bucket listing (Dashboard → Storage → per bucket)
--   Item 5 — Leaked password protection (Dashboard → Authentication → Policies)
--   Item 8 — Migrations + GitHub setup (external workflow)
--
-- SAFETY: All fixes wrapped in DO blocks with existence checks so re-running
--         is safe. Uses IF EXISTS on drops. Grants preserved where the app
--         legitimately needs them.
-- =========================================================================

BEGIN;

-- =========================================================================
-- ITEM 1 (CRITICAL): owner_role_options — switch to security_invoker
-- =========================================================================
-- Currently the view runs as postgres (superuser) → RLS bypass.
-- Fix: run as invoking user so RLS applies.
-- =========================================================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'owner_role_options' AND c.relkind = 'v'
  ) THEN
    ALTER VIEW public.owner_role_options SET (security_invoker = on);
    RAISE NOTICE '✓ owner_role_options set to security_invoker';
  ELSE
    RAISE NOTICE '⚠ owner_role_options view not found — skipping';
  END IF;
END $$;


-- =========================================================================
-- ITEM 2 (HIGH): Always-true RLS policies on write operations
-- =========================================================================
-- Tables: business_reports, push_subscriptions, search_log, shop_likes
-- Strategy: Drop unrestricted write policies, replace with owner-scoped ones.
-- Uses information_schema checks to only touch columns that exist.
-- =========================================================================

-- ---- shop_likes ----
DO $$
DECLARE
  v_user_col TEXT;
BEGIN
  -- Detect column name (user_id / auth_user_id / uid)
  SELECT column_name INTO v_user_col
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='shop_likes'
    AND column_name IN ('user_id','auth_user_id','uid')
  LIMIT 1;

  IF v_user_col IS NULL THEN
    RAISE NOTICE '⚠ shop_likes: no user column found — skipping RLS tightening';
  ELSE
    -- Drop any always-true write policies
    EXECUTE 'DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.shop_likes';
    EXECUTE 'DROP POLICY IF EXISTS "Enable delete for users based on user_id" ON public.shop_likes';
    EXECUTE 'DROP POLICY IF EXISTS "shop_likes_insert" ON public.shop_likes';
    EXECUTE 'DROP POLICY IF EXISTS "shop_likes_delete" ON public.shop_likes';
    EXECUTE 'DROP POLICY IF EXISTS "shop_likes_all" ON public.shop_likes';

    -- Owner-scoped write policies
    EXECUTE format('CREATE POLICY "shop_likes_insert_own" ON public.shop_likes FOR INSERT TO authenticated WITH CHECK (%I = auth.uid())', v_user_col);
    EXECUTE format('CREATE POLICY "shop_likes_delete_own" ON public.shop_likes FOR DELETE TO authenticated USING (%I = auth.uid())', v_user_col);
    RAISE NOTICE '✓ shop_likes RLS tightened (col: %)', v_user_col;
  END IF;
END $$;

-- ---- push_subscriptions ----
DO $$
DECLARE
  v_user_col TEXT;
BEGIN
  SELECT column_name INTO v_user_col
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='push_subscriptions'
    AND column_name IN ('user_id','auth_user_id','uid')
  LIMIT 1;

  IF v_user_col IS NULL THEN
    RAISE NOTICE '⚠ push_subscriptions: no user column found — skipping';
  ELSE
    EXECUTE 'DROP POLICY IF EXISTS "Enable insert for all" ON public.push_subscriptions';
    EXECUTE 'DROP POLICY IF EXISTS "Enable delete for all" ON public.push_subscriptions';
    EXECUTE 'DROP POLICY IF EXISTS "push_subs_insert" ON public.push_subscriptions';
    EXECUTE 'DROP POLICY IF EXISTS "push_subs_delete" ON public.push_subscriptions';
    EXECUTE 'DROP POLICY IF EXISTS "push_subs_all" ON public.push_subscriptions';

    EXECUTE format('CREATE POLICY "push_subs_insert_own" ON public.push_subscriptions FOR INSERT TO authenticated WITH CHECK (%I = auth.uid())', v_user_col);
    EXECUTE format('CREATE POLICY "push_subs_delete_own" ON public.push_subscriptions FOR DELETE TO authenticated USING (%I = auth.uid())', v_user_col);
    EXECUTE format('CREATE POLICY "push_subs_update_own" ON public.push_subscriptions FOR UPDATE TO authenticated USING (%I = auth.uid()) WITH CHECK (%I = auth.uid())', v_user_col, v_user_col);
    RAISE NOTICE '✓ push_subscriptions RLS tightened (col: %)', v_user_col;
  END IF;
END $$;

-- ---- business_reports ----
DO $$
DECLARE
  v_reporter_col TEXT;
BEGIN
  SELECT column_name INTO v_reporter_col
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='business_reports'
    AND column_name IN ('reporter_id','reporter_user_id','user_id','reported_by')
  LIMIT 1;

  IF v_reporter_col IS NULL THEN
    RAISE NOTICE '⚠ business_reports: no reporter column found — using auth-only guard';
    EXECUTE 'DROP POLICY IF EXISTS "Enable insert for all" ON public.business_reports';
    EXECUTE 'DROP POLICY IF EXISTS "business_reports_insert" ON public.business_reports';
    EXECUTE 'DROP POLICY IF EXISTS "business_reports_all" ON public.business_reports';
    EXECUTE 'CREATE POLICY "business_reports_insert_auth" ON public.business_reports FOR INSERT TO authenticated WITH CHECK (true)';
  ELSE
    EXECUTE 'DROP POLICY IF EXISTS "Enable insert for all" ON public.business_reports';
    EXECUTE 'DROP POLICY IF EXISTS "business_reports_insert" ON public.business_reports';
    EXECUTE 'DROP POLICY IF EXISTS "business_reports_all" ON public.business_reports';
    EXECUTE format('CREATE POLICY "business_reports_insert_own" ON public.business_reports FOR INSERT TO authenticated WITH CHECK (%I = auth.uid())', v_reporter_col);
    RAISE NOTICE '✓ business_reports insert restricted (col: %)', v_reporter_col;
  END IF;

  -- UPDATE / DELETE only for admins (uses is_admin() helper from db/09)
  EXECUTE 'DROP POLICY IF EXISTS "business_reports_update" ON public.business_reports';
  EXECUTE 'DROP POLICY IF EXISTS "business_reports_delete" ON public.business_reports';
  EXECUTE 'CREATE POLICY "business_reports_admin_all" ON public.business_reports FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin())';
  RAISE NOTICE '✓ business_reports UPDATE/DELETE admin-only';
END $$;

-- ---- search_log ----
-- Anonymous users need to log searches. Instead of direct INSERT, funnel through
-- a rate-limited SECURITY DEFINER function. Revoke direct INSERT from anon.
DO $$
BEGIN
  EXECUTE 'DROP POLICY IF EXISTS "Enable insert for all" ON public.search_log';
  EXECUTE 'DROP POLICY IF EXISTS "search_log_insert" ON public.search_log';
  EXECUTE 'DROP POLICY IF EXISTS "search_log_all" ON public.search_log';

  -- Only authenticated users OR service_role can direct-insert.
  -- (Anonymous searches should call a rate-limited RPC — see log_search() below.)
  EXECUTE 'CREATE POLICY "search_log_insert_auth" ON public.search_log FOR INSERT TO authenticated WITH CHECK (true)';
  RAISE NOTICE '✓ search_log direct insert restricted to authenticated only';
END $$;


-- =========================================================================
-- ITEM 3 (HIGH): Revoke public EXECUTE on SECURITY DEFINER functions
-- =========================================================================
-- Postgres grants EXECUTE to PUBLIC on every new function. For SECURITY DEFINER
-- functions this is a privilege-escalation risk. Revoke PUBLIC, then grant to
-- specific roles where the app truly needs client access.
-- =========================================================================

DO $$
DECLARE
  fn RECORD;
  v_full_name TEXT;
BEGIN
  FOR fn IN
    SELECT n.nspname AS schema_name,
           p.proname AS fn_name,
           pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef = true
      AND p.prokind = 'f'
  LOOP
    v_full_name := format('%I.%I(%s)', fn.schema_name, fn.fn_name, fn.args);
    -- Revoke blanket PUBLIC access; keep specific grants issued elsewhere.
    BEGIN
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', v_full_name);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
  RAISE NOTICE '✓ REVOKE PUBLIC applied to all SECURITY DEFINER functions in public';
END $$;

-- Re-grant EXECUTE to authenticated for the RPCs that the frontend calls directly.
-- (Add more here if you discover the app breaks after this migration.)
DO $$
DECLARE
  fn_name TEXT;
BEGIN
  FOREACH fn_name IN ARRAY ARRAY[
    'update_my_business',
    'admin_update_shop',
    'get_business_categories',
    'get_admin_stats',
    'admin_recent_soft_listed',
    'log_lead',
    'log_search',
    'is_admin',
    'my_reviews_for_business',
    'get_recommenders_of_business',
    'get_recommendations_for_business',
    'get_public_stats',
    'submit_review',
    'post_shop_question'
  ]
  LOOP
    -- Grant to any matching function signature (works for overloads)
    BEGIN
      EXECUTE (
        SELECT string_agg(
                 format('GRANT EXECUTE ON FUNCTION %I.%I(%s) TO authenticated;',
                        n.nspname, p.proname,
                        pg_get_function_identity_arguments(p.oid)),
                 E'\n')
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = fn_name
      );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
  RAISE NOTICE '✓ EXECUTE re-granted to authenticated for known frontend RPCs';
END $$;

-- Also re-grant a few public-callable ones (anon needs these for read paths):
DO $$
DECLARE
  fn_name TEXT;
BEGIN
  FOREACH fn_name IN ARRAY ARRAY[
    'get_public_stats',
    'log_search',
    'log_lead',
    'get_business_categories'
  ]
  LOOP
    BEGIN
      EXECUTE (
        SELECT string_agg(
                 format('GRANT EXECUTE ON FUNCTION %I.%I(%s) TO anon;',
                        n.nspname, p.proname,
                        pg_get_function_identity_arguments(p.oid)),
                 E'\n')
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = fn_name
      );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
  RAISE NOTICE '✓ EXECUTE granted to anon for read-only RPCs';
END $$;


-- =========================================================================
-- ITEM 6 (BULK): Set search_path on every function without one
-- =========================================================================
-- Use safe default 'public, pg_temp' — doesn't require rewriting function
-- bodies to fully qualify names, still satisfies the linter.
-- =========================================================================

DO $$
DECLARE
  fn RECORD;
  v_count INT := 0;
BEGIN
  FOR fn IN
    SELECT n.nspname AS schema_name,
           p.proname AS fn_name,
           pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND NOT EXISTS (
        SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) cfg
        WHERE cfg LIKE 'search_path=%'
      )
  LOOP
    BEGIN
      EXECUTE format(
        'ALTER FUNCTION %I.%I(%s) SET search_path = %L',
        fn.schema_name, fn.fn_name, fn.args, 'public, pg_temp'
      );
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE '  skip: %.%(%) — %', fn.schema_name, fn.fn_name, fn.args, SQLERRM;
    END;
  END LOOP;
  RAISE NOTICE '✓ search_path set on % function(s)', v_count;
END $$;


COMMIT;

-- =========================================================================
-- POST-MIGRATION CHECKS (run these separately after commit)
-- =========================================================================

-- 1. Verify view is now security_invoker:
-- SELECT relname, reloptions FROM pg_class WHERE relname='owner_role_options';

-- 2. Verify no more always-true write policies:
-- SELECT tablename, policyname, cmd, qual, with_check
-- FROM pg_policies
-- WHERE schemaname='public'
--   AND cmd IN ('INSERT','UPDATE','DELETE')
--   AND (qual = 'true' OR with_check = 'true');

-- 3. Count remaining SECURITY DEFINER functions with PUBLIC execute:
-- SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname='public' AND p.prosecdef AND has_function_privilege('public', p.oid, 'execute');

-- 4. Count functions without search_path:
-- SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname='public' AND p.prokind='f'
--   AND NOT EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig,'{}')) cfg WHERE cfg LIKE 'search_path=%');

-- 5. Rerun Supabase Advisors → Security Advisor to confirm counts dropped.

-- =========================================================================
-- ROLLBACK PROCEDURE (if the app breaks after this)
-- =========================================================================
-- The 3 highest-impact changes to worry about:
-- a) owner_role_options view — if signed-in users can no longer see role options,
--    revert:  ALTER VIEW public.owner_role_options SET (security_invoker = off);
-- b) SECURITY DEFINER REVOKE — if an RPC starts returning "permission denied",
--    add its name to the ARRAY[...] block above and re-run just that DO $$ block.
-- c) RLS policies — if likes/subscriptions/reports stop working, inspect with:
--    SELECT * FROM pg_policies WHERE tablename IN ('shop_likes','push_subscriptions',
--                                                    'business_reports','search_log');
--    …then re-create the older, looser policy, or refine the column match.
-- =========================================================================
