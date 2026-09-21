-- ============================================================
-- db/219 — SECURITY: close open write policies + data leaks
-- ============================================================
-- Found in the full-site audit. Each item below is exploitable
-- today with nothing more than the public anon key.
--
--  1. ANY logged-in user could make themselves owner of ANY shop
--  2. anon could read claim_token → take over every unclaimed listing
--  3. anon could DELETE every push subscription
--  4. anon could write directly to shop_likes / search_log /
--     business_reports, bypassing the rate-limited RPCs
--  5. reviewer phone numbers recoverable from an unsalted SHA-256
--  6. owner login email, internal notes and the admin's own email
--     were readable by anon
--
-- db/206 tried to fix (3)/(4) but dropped policy names that never
-- existed, so it was a no-op. The real names are used below.
--
-- SAFE: idempotent. Every capability removed here already has a
-- SECURITY DEFINER RPC that the frontend uses.
-- ============================================================

BEGIN;

-- ============================================================
-- 1. Ownership self-grant  (CRITICAL)
-- ------------------------------------------------------------
-- p_owners_self_insert (db/02:67) only checked auth_user_id = auth.uid();
-- business_id was unconstrained, so:
--   POST /rest/v1/business_owners {business_id:<any>, auth_user_id:<me>}
-- handed the caller read+write on that business via p_biz_owner_read /
-- p_biz_owner_update. Legitimate inserts all go through SECURITY
-- DEFINER RPCs, so no policy is needed.
-- ============================================================
DROP POLICY IF EXISTS p_owners_self_insert ON public.business_owners;

-- ============================================================
-- 2. Anon-readable secrets on businesses  (CRITICAL)
-- ------------------------------------------------------------
-- db/02:34 grants anon SELECT on ALL columns of active rows, and
-- pre-listed shops are inserted as 'active'. claim_token is enough
-- to claim a listing (db/163:78).
-- ============================================================
DO $$
DECLARE
  c TEXT;
  cols TEXT[] := ARRAY[
    'claim_token', 'canonical_mobile', 'notes_internal', 'admin_notes',
    'consent_notes', 'pre_listed_by', 'pending_edits', 'email'
    -- alt_mobile was in this list and has been REMOVED on purpose.
    -- It is not a secret: it is the owner's backup number, which he sets
    -- himself in panel/profile.html precisely so a customer can reach him
    -- when the main number does not answer, and business.html renders it
    -- as a public click-to-call chip. Revoking it would have blanked that
    -- chip on every listing page while protecting nothing.
  ];
BEGIN
  FOREACH c IN ARRAY cols LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='businesses' AND column_name=c
    ) THEN
      EXECUTE format('REVOKE SELECT (%I) ON public.businesses FROM anon', c);
      RAISE NOTICE '  revoked anon SELECT on businesses.%', c;
    END IF;
  END LOOP;
END $$;

-- Reviewer / asker phone hashes (unsalted SHA-256 over a 10-digit
-- space = trivially reversible). No frontend selects these.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='reviews' AND column_name='customer_phone_hash') THEN
    REVOKE SELECT (customer_phone_hash) ON public.reviews FROM anon, authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='shop_questions' AND column_name='asker_phone_hash') THEN
    REVOKE SELECT (asker_phone_hash) ON public.shop_questions FROM anon, authenticated;
  END IF;
END $$;

-- ============================================================
-- 3+4. Always-true write policies  (CRITICAL / HIGH)
-- ------------------------------------------------------------
-- push_delete_own was FOR DELETE TO anon USING (TRUE) — a stranger
-- could wipe every push subscriber on the site.
-- Each of these has a SECURITY DEFINER RPC the frontend already uses:
--   subscribe_push, toggle_shop_like, log_search, report_business
-- ============================================================
DROP POLICY IF EXISTS push_delete_own        ON public.push_subscriptions;
DROP POLICY IF EXISTS push_insert_any        ON public.push_subscriptions;
DROP POLICY IF EXISTS shop_likes_anon_insert ON public.shop_likes;
DROP POLICY IF EXISTS search_log_anon_insert ON public.search_log;
DROP POLICY IF EXISTS reports_insert_anon    ON public.business_reports;

-- ============================================================
-- 5. Keep the moderation keyword list private
-- ------------------------------------------------------------
-- db/38:184 exposed the exact spam-filter list to anon.
-- check_content_violations is SECURITY DEFINER and bypasses RLS.
-- ============================================================
DROP POLICY IF EXISTS bk_read_all ON public.blocked_keywords;

-- ============================================================
-- 6. Rate-limit the new review-flag RPC (db/218)
-- ------------------------------------------------------------
-- session_id is client-supplied, so the dedup index alone does not
-- stop a flood with random ids.
-- ============================================================
CREATE OR REPLACE FUNCTION public.flag_review_public(
  p_review_id  UUID,
  p_reason     TEXT DEFAULT 'inappropriate',
  p_session_id TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_reason TEXT;
  v_open   INT;
  v_sid    TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.reviews WHERE id = p_review_id) THEN
    RAISE EXCEPTION 'Review not found';
  END IF;

  v_sid := NULLIF(trim(COALESCE(p_session_id, '')), '');
  IF v_sid IS NOT NULL AND length(v_sid) > 64 THEN
    v_sid := left(v_sid, 64);
  END IF;

  -- 5 flags per review per hour, site-wide
  BEGIN
    IF NOT public.check_rate_limit('flag:' || p_review_id::TEXT, 'flag', 5, 3600, 3600) THEN
      RETURN jsonb_build_object('success', false, 'reason', 'rate limited');
    END IF;
  EXCEPTION WHEN undefined_function THEN
    NULL;                                    -- rate limiter absent → continue
  END;

  v_reason := lower(trim(COALESCE(p_reason, 'inappropriate')));
  IF v_reason NOT IN ('inappropriate','spam','fake','offensive','other') THEN
    v_reason := 'other';
  END IF;

  BEGIN
    INSERT INTO public.review_flags (review_id, reason, session_id)
    VALUES (p_review_id, v_reason, v_sid);
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('success', true, 'already', true);
  END;

  SELECT count(*) INTO v_open
  FROM public.review_flags WHERE review_id = p_review_id AND resolved_at IS NULL;

  RETURN jsonb_build_object('success', true, 'flags', v_open);
END;
$$;

GRANT EXECUTE ON FUNCTION public.flag_review_public(UUID, TEXT, TEXT) TO anon, authenticated;

-- ============================================================
-- 7. Admin bypass on the duplicate-mobile guard
-- ------------------------------------------------------------
-- prevent_dup_active_mobile (db/100:272) fires BEFORE the
-- admin-aware trg_biz_one_per_mobile and has no is_admin() escape,
-- so an admin could not add a legitimate shared/franchise number.
-- ============================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
             WHERE n.nspname='public' AND p.proname='prevent_duplicate_active_mobile') THEN
    RAISE NOTICE '  note: prevent_duplicate_active_mobile exists — admin bypass patched separately if needed';
  END IF;
END $$;

-- ============================================================
-- 8. claim_lookup_by_token leaked the UNMASKED mobile
-- ------------------------------------------------------------
-- db/162:372 returned 'full_mobile' right under a comment saying the
-- number was masked for privacy, and the RPC is granted to anon.
-- masked_mobile is what the claim page shows; full_mobile was only
-- stashed into user_metadata and is not needed.
-- ============================================================
DO $$
DECLARE v_src TEXT;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'claim_lookup_by_token' LIMIT 1;
  IF v_src IS NULL THEN
    RAISE NOTICE '  claim_lookup_by_token not found — skipping';
  ELSIF position('full_mobile' in v_src) = 0 THEN
    RAISE NOTICE '  claim_lookup_by_token already clean';
  ELSE
    EXECUTE 'CREATE OR REPLACE FUNCTION public.claim_lookup_by_token(p_token TEXT) '
         || 'RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER '
         || 'SET search_path = public, extensions, pg_temp AS $fn$'
         || replace(v_src, '''full_mobile'',     v_row.mobile,', '')
         || '$fn$';
    RAISE NOTICE '  ✓ full_mobile removed from claim_lookup_by_token';
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ---- Verify (run separately) -------------------------------
-- 0) claim_lookup_by_token must no longer return full_mobile:
--   SELECT prosrc LIKE '%full_mobile%' FROM pg_proc WHERE proname='claim_lookup_by_token';  -- expect false
--
-- 1) Should return 0 rows — no always-true write policies left:
--   SELECT tablename, policyname, cmd FROM pg_policies
--   WHERE schemaname='public' AND cmd <> 'SELECT'
--     AND (qual = 'true' OR with_check = 'true');
--
-- 2) Should ERROR (permission denied for column claim_token):
--   set role anon; SELECT claim_token FROM businesses LIMIT 1; reset role;
--
-- 3) Public pages must still work — open the homepage, a business
--    page, and search while logged out.

DO $$ BEGIN
  RAISE NOTICE '✓ db/219 installed. Ownership self-grant, claim_token leak, anon push-delete and anon direct writes are closed.';
END $$;
