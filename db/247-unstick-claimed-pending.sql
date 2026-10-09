-- ============================================================
-- db/247 — claims stuck in "Claim in progress"
-- ============================================================
-- Deepak, 9 Oct: Wadhwa Electronics shows "CLAIM IN PROGRESS — contact
-- details unlock honge" although the shop is Admin Verified GOLD (5/5,
-- phone + visit verified). Three active shops sit in claimed_pending.
--
-- WHY: claimed_pending → claimed_verified happens in exactly one place,
-- auto_approve_after_email_verify() (db/163), and that is only called
-- from /panel/email-verified.html. An owner who confirms the email and
-- then signs in any other way (login page, magic link to the dashboard,
-- admin "Login as Owner") never runs it. The listing stays "in
-- progress" for ever, and on the public page body.claim-locked hides
-- the contact buttons.
--
-- FIX
--   1. a trigger on auth.users: the moment email_confirmed_at is set,
--      that user's pre-listed pending claims are promoted — no page
--      visit needed
--   2. backfill: promote every pending claim whose owner already has a
--      confirmed email
--   3. admin_complete_claim(business_id) — for an admin who has
--      verified the owner by phone/visit and wants it done now
-- The public page also stops locking a shop the team has verified
-- (v333), so this cannot bite a verified shop again.
-- Safe to re-run.
-- ============================================================
BEGIN;

-- 1. promote on email confirmation, wherever it happens
CREATE OR REPLACE FUNCTION public.promote_claims_on_email_confirm()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.email_confirmed_at IS NOT NULL AND OLD.email_confirmed_at IS NULL THEN
    UPDATE public.businesses b
       SET claim_status = 'claimed_verified',
           claimed_at   = COALESCE(b.claimed_at, NOW()),
           status       = CASE WHEN b.status IN ('pending','pending_review') THEN 'active' ELSE b.status END,
           claim_token  = NULL,
           updated_at   = NOW()
     WHERE b.claim_status = 'claimed_pending'
       AND b.id IN (SELECT bo.business_id FROM public.business_owners bo WHERE bo.auth_user_id = NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_promote_claims_on_email_confirm ON auth.users;
CREATE TRIGGER trg_promote_claims_on_email_confirm
  AFTER UPDATE OF email_confirmed_at ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.promote_claims_on_email_confirm();

-- 2. backfill the ones already stuck
CREATE TEMP TABLE _promoted AS
WITH p AS (
  UPDATE public.businesses b
     SET claim_status = 'claimed_verified',
         claimed_at   = COALESCE(b.claimed_at, NOW()),
         status       = CASE WHEN b.status IN ('pending','pending_review') THEN 'active' ELSE b.status END,
         claim_token  = NULL,
         updated_at   = NOW()
   WHERE b.claim_status = 'claimed_pending'
     AND EXISTS (SELECT 1 FROM public.business_owners bo
                   JOIN auth.users u ON u.id = bo.auth_user_id
                  WHERE bo.business_id = b.id AND u.email_confirmed_at IS NOT NULL)
  RETURNING b.name
) SELECT name FROM p;

-- 3. admin finishes a claim by hand
CREATE OR REPLACE FUNCTION public.admin_complete_claim(p_business_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND COALESCE(disabled, FALSE) = FALSE) THEN
    RAISE EXCEPTION 'admin only';
  END IF;
  UPDATE businesses
     SET claim_status = 'claimed_verified',
         claimed_at   = COALESCE(claimed_at, NOW()),
         status       = CASE WHEN status IN ('pending','pending_review') THEN 'active' ELSE status END,
         claim_token  = NULL,
         updated_at   = NOW()
   WHERE id = p_business_id AND claim_status <> 'claimed_verified';
  RETURN (SELECT claim_status FROM businesses WHERE id = p_business_id);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_complete_claim(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_complete_claim(UUID) TO authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/247-unstick-claimed-pending.sql');
  END IF;
END $$;

COMMIT;

-- Promoted now, and what is still pending (those owners have NOT
-- confirmed their email — use the admin button, or ask them to verify).
SELECT 'promoted' AS what, name FROM _promoted
UNION ALL
SELECT 'still pending', b.name || '  — owner email confirmed: ' ||
       COALESCE((SELECT CASE WHEN u.email_confirmed_at IS NULL THEN 'no' ELSE 'yes' END
                   FROM business_owners bo JOIN auth.users u ON u.id = bo.auth_user_id
                  WHERE bo.business_id = b.id LIMIT 1), 'no owner linked')
  FROM public.businesses b WHERE b.claim_status = 'claimed_pending' AND b.status = 'active';
