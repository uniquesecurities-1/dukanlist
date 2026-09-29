-- ============================================================
-- db/241 — "Delete my account" actually does something
-- ============================================================
--
-- panel/profile.html has had a "Permanently Delete" button since v226
-- that calls rpc('request_account_deletion'). The function was never
-- written, so every press fell through to the WhatsApp fallback. Google
-- Play requires an in-app deletion path that works; the public
-- /delete-account page promises 30-day recovery and a 48-hour manual
-- process. This migration makes the button keep that promise.
--
-- WHAT IT DOES (when the owner presses the button)
--   1. every listing linked to the signed-in owner goes status =
--      'self_hidden' — a status the schema has had since db/01 for
--      exactly this: off the site, off search, off the sitemap, but
--      the row is intact for the 30-day recovery window
--   2. one row is written to account_deletion_requests, so the admin
--      can see who asked, when, and which listings — and finish the
--      job (remove the auth user) within the promised window
--   3. nothing is deleted here. Deleting the auth user is a service-
--      role action the admin performs; recovery inside 30 days is
--      "set status back to active"
--
-- WHY THE TRIGGER CHANGES
--   trg_biz_protect_admin_cols reverts businesses.status for any
--   caller who is not an admin — it checks auth.uid(), so a SECURITY
--   DEFINER function running for a shopkeeper is still "not an admin"
--   and its status change would be silently undone. The trigger now
--   also lets the change through when the transaction-local setting
--   dl.self_hide = '1' is present. Only request_account_deletion sets
--   it, it is local to that one transaction (set_config(..., true)),
--   and a shopkeeper cannot set it through PostgREST. Every other
--   protected column is still reverted exactly as before.
--
-- Safe to re-run.
-- ============================================================

BEGIN;

-- 1. the register ------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.account_deletion_requests (
  id            BIGSERIAL PRIMARY KEY,
  auth_user_id  UUID        NOT NULL,
  business_ids  UUID[]      NOT NULL DEFAULT '{}',
  business_names TEXT[]     NOT NULL DEFAULT '{}',
  requested_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  recover_until TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '30 days',
  processed_at  TIMESTAMPTZ,
  processed_by  UUID,
  note          TEXT
);
CREATE INDEX IF NOT EXISTS idx_adr_open ON public.account_deletion_requests (requested_at)
  WHERE processed_at IS NULL;

ALTER TABLE public.account_deletion_requests ENABLE ROW LEVEL SECURITY;
-- Admins read; nobody writes through REST (the function below writes).
DROP POLICY IF EXISTS adr_admin_read ON public.account_deletion_requests;
CREATE POLICY adr_admin_read ON public.account_deletion_requests
  FOR SELECT TO authenticated USING (public.is_admin());
DROP POLICY IF EXISTS adr_admin_update ON public.account_deletion_requests;
CREATE POLICY adr_admin_update ON public.account_deletion_requests
  FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
REVOKE ALL ON public.account_deletion_requests FROM anon;
GRANT SELECT, UPDATE ON public.account_deletion_requests TO authenticated;

-- 2. the protect trigger learns one narrow exception --------------------
CREATE OR REPLACE FUNCTION public.trg_biz_protect_admin_cols()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public, auth, pg_temp
AS $$
BEGIN
  -- Admins (any role) bypass — they can update anything via admin_update_shop etc.
  IF is_admin() THEN RETURN NEW; END IF;

  -- db/241: request_account_deletion() may move a shop to self_hidden
  -- on the owner's behalf. Status only; everything else below still
  -- reverts.
  IF COALESCE(current_setting('dl.self_hide', TRUE), '') = '1'
     AND NEW.status = 'self_hidden' THEN
    NULL;
  ELSE
    NEW.status            := OLD.status;
  END IF;

  -- For non-admin callers, revert any change to protected columns
  NEW.verified_mobile     := OLD.verified_mobile;
  NEW.verified_address    := OLD.verified_address;
  NEW.verified_photo      := OLD.verified_photo;
  NEW.verified_visit      := OLD.verified_visit;
  NEW.featured            := OLD.featured;
  NEW.admin_notes         := OLD.admin_notes;
  BEGIN
    NEW.featured_until       := OLD.featured_until;
    NEW.featured_started_at  := OLD.featured_started_at;
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN
    NEW.pending_edits        := OLD.pending_edits;
    NEW.pending_edits_at     := OLD.pending_edits_at;
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN
    NEW.canonical_mobile := OLD.canonical_mobile;
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN NEW;
END;
$$;

-- 3. the function the button calls --------------------------------------
CREATE OR REPLACE FUNCTION public.request_account_deletion()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_uid    UUID := auth.uid();
  v_ids    UUID[];
  v_names  TEXT[];
  v_hidden INT := 0;
  v_req    BIGINT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'login required';
  END IF;

  SELECT COALESCE(array_agg(b.id), '{}'), COALESCE(array_agg(b.name), '{}')
    INTO v_ids, v_names
    FROM public.business_owners bo
    JOIN public.businesses b ON b.id = bo.business_id
   WHERE bo.auth_user_id = v_uid;

  -- Let the protect trigger accept status = self_hidden for this
  -- transaction only.
  PERFORM set_config('dl.self_hide', '1', TRUE);

  UPDATE public.businesses
     SET status     = 'self_hidden',
         updated_at = NOW()
   WHERE id = ANY (v_ids)
     AND status NOT IN ('banned', 'self_hidden');
  GET DIAGNOSTICS v_hidden = ROW_COUNT;

  INSERT INTO public.account_deletion_requests (auth_user_id, business_ids, business_names)
  VALUES (v_uid, v_ids, v_names)
  RETURNING id INTO v_req;

  RETURN jsonb_build_object(
    'ok',            TRUE,
    'request_id',    v_req,
    'listings',      COALESCE(array_length(v_ids, 1), 0),
    'hidden_now',    v_hidden,
    'recover_until', (NOW() + INTERVAL '30 days')::date
  );
END;
$$;

REVOKE ALL ON FUNCTION public.request_account_deletion() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_account_deletion() TO authenticated;

DO $$ BEGIN
  IF to_regproc('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/241-request-account-deletion.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- Checks (read-only)
-- ============================================================
SELECT 'request_account_deletion exists' AS check,
       CASE WHEN to_regproc('public.request_account_deletion()') IS NOT NULL
            THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'anon cannot call it',
       CASE WHEN has_function_privilege('anon', 'public.request_account_deletion()', 'EXECUTE')
            THEN 'NO — anon can execute, tell Claude' ELSE 'yes' END
UNION ALL
SELECT 'trigger still installed',
       CASE WHEN EXISTS (SELECT 1 FROM pg_trigger
                          WHERE tgrelid = 'public.businesses'::regclass
                            AND tgfoid  = 'public.trg_biz_protect_admin_cols'::regproc
                            AND NOT tgisinternal)
            THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'open deletion requests', COUNT(*)::text
  FROM public.account_deletion_requests WHERE processed_at IS NULL;

-- ============================================================
-- FOR THE ADMIN, LATER (not run now):
--   who asked:   SELECT * FROM account_deletion_requests WHERE processed_at IS NULL;
--   recover:     UPDATE businesses SET status='active' WHERE id = ANY(<business_ids>);
--   finish:      delete the auth user from Supabase → Authentication → Users,
--                then UPDATE account_deletion_requests SET processed_at = NOW() WHERE id = <id>;
-- ============================================================
