-- ============================================================
-- db/217 — Make admin pre-listed shops claimable
-- ============================================================
-- BUG: claim_business_by_phone (db/71:97) only matches a business
-- that has a SHADOW owner row:
--     business_owners(auth_user_id IS NULL, owner_phone = <mobile>)
--
-- register_business_public creates that row (db/17:346), but
-- admin_pre_list_shop (db/165) never did. So every shop added via
-- Quick Add / Bulk CSV answered "No shop found for this phone, or
-- already claimed." — the whole pre-listed population was
-- un-claimable, while panel/claim-account.html invited exactly
-- those owners to claim.
--
-- Fix, in two parts:
--   1. BACKFILL a shadow row for every existing pre-listed shop
--   2. TRIGGER so any future insert gets one automatically —
--      this covers admin_pre_list_shop, bulk CSV, and anything
--      added later, without rewriting those functions.
--
-- SAFE: idempotent, additive, re-runnable.
-- ============================================================

BEGIN;

-- ---- 1. Backfill -------------------------------------------
DO $$
DECLARE v_n INT;
BEGIN
  WITH ins AS (
    INSERT INTO public.business_owners (business_id, auth_user_id, owner_phone, role)
    SELECT b.id,
           NULL,
           right(regexp_replace(COALESCE(b.mobile, ''), '\D', '', 'g'), 10),
           'owner'
    FROM public.businesses b
    WHERE COALESCE(b.mobile, '') <> ''
      AND NOT EXISTS (                      -- no owner row of any kind yet
        SELECT 1 FROM public.business_owners bo WHERE bo.business_id = b.id
      )
    ON CONFLICT DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM ins;
  RAISE NOTICE '✓ shadow owner rows backfilled: %', v_n;
END $$;

-- ---- 2. Trigger for everything created from now on ---------
CREATE OR REPLACE FUNCTION public.ensure_shadow_owner_row()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_phone TEXT;
BEGIN
  v_phone := right(regexp_replace(COALESCE(NEW.mobile, ''), '\D', '', 'g'), 10);
  IF v_phone = '' THEN
    RETURN NEW;
  END IF;

  -- Skip if this business already has ANY owner row (real or shadow).
  IF EXISTS (SELECT 1 FROM public.business_owners WHERE business_id = NEW.id) THEN
    RETURN NEW;
  END IF;

  BEGIN
    INSERT INTO public.business_owners (business_id, auth_user_id, owner_phone, role)
    VALUES (NEW.id, NULL, v_phone, 'owner');
  EXCEPTION WHEN unique_violation THEN
    NULL;                                   -- raced with another insert; fine
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ensure_shadow_owner ON public.businesses;
CREATE TRIGGER trg_ensure_shadow_owner
  AFTER INSERT ON public.businesses
  FOR EACH ROW EXECUTE FUNCTION public.ensure_shadow_owner_row();

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ---- Verify (run separately) -------------------------------
-- Businesses that still have NO owner row (should be only the
-- ones with a blank mobile):
--   SELECT count(*) FROM businesses b
--   WHERE NOT EXISTS (SELECT 1 FROM business_owners bo WHERE bo.business_id=b.id);
--
-- Then try a claim with a pre-listed shop's mobile in
-- /panel/claim-account.html — it should now find the shop.

DO $$ BEGIN
  RAISE NOTICE '✓ db/217 installed. Pre-listed shops are now claimable by phone.';
END $$;
