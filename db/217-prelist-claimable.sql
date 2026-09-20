-- ============================================================
-- db/217 (v2) — Make admin pre-listed shops claimable
-- ============================================================
-- PROBLEM A — missing shadow row:
--   claim_business_by_phone (db/71:97) only matches a business that
--   has a SHADOW owner row: business_owners(auth_user_id IS NULL,
--   owner_phone = <mobile>). register_business_public creates one
--   (db/17:346); admin_pre_list_shop never did. So every Quick Add /
--   Bulk CSV shop answered "No shop found for this phone".
--
-- PROBLEM B — phone format mismatch (the real blocker):
--   pre-listed businesses.mobile is normalised to 10 digits
--   (norm_indian_mobile, db/162:73), but public registrations store
--   12 digits ('91'+10) and /panel/claim-account.html SENDS 12 digits.
--   So `b.mobile = p_mobile` never matched for pre-listed shops no
--   matter what we did to the owner rows. Both sides are normalised
--   below so the two populations behave identically.
--
-- v2 NOTE — the first draft of this file used a plain AFTER INSERT
-- trigger. That fires BEFORE register_business_public inserts its own
-- shadow row, producing TWO unclaimed rows per new shop, which later
-- tripped uq_biz_owner_authuser and broke email confirmation, and
-- collided with the bulk-CSV insert (db/19:418). It is now a
-- DEFERRABLE INITIALLY DEFERRED constraint trigger, so it runs at
-- COMMIT — by then any function-created row already exists and the
-- EXISTS guard correctly skips.
--
-- SAFE: idempotent, additive, re-runnable.
-- ============================================================

BEGIN;

-- ---- 1. Backfill shops that have no owner row at all -------
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
    WHERE length(regexp_replace(COALESCE(b.mobile, ''), '\D', '', 'g')) >= 10
      AND NOT EXISTS (
        SELECT 1 FROM public.business_owners bo WHERE bo.business_id = b.id
      )
    ON CONFLICT DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM ins;
  RAISE NOTICE '✓ shadow owner rows backfilled: %', v_n;
END $$;

-- ---- 2. Deferred safety net for future inserts -------------
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
  IF length(v_phone) <> 10 THEN
    RETURN NEW;
  END IF;

  -- Runs at COMMIT: if the creating function already made an owner
  -- row (register_business_public, bulk CSV, claim flows), skip.
  IF EXISTS (SELECT 1 FROM public.business_owners WHERE business_id = NEW.id) THEN
    RETURN NEW;
  END IF;

  BEGIN
    INSERT INTO public.business_owners (business_id, auth_user_id, owner_phone, role)
    VALUES (NEW.id, NULL, v_phone, 'owner')
    ON CONFLICT DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    NULL;                                   -- never block the parent insert
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ensure_shadow_owner ON public.businesses;
CREATE CONSTRAINT TRIGGER trg_ensure_shadow_owner
  AFTER INSERT ON public.businesses
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.ensure_shadow_owner_row();

-- ---- 3. Normalise BOTH sides of the phone comparison -------
CREATE OR REPLACE FUNCTION public.claim_business_by_phone(p_mobile TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, auth, pg_temp
AS $$
DECLARE
  v_user_id UUID;
  v_biz_id  UUID;
  v_count   INT;
  v_m       TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- last 10 digits, whatever the caller sent ('91…' or plain)
  v_m := right(regexp_replace(COALESCE(p_mobile, ''), '\D', '', 'g'), 10);
  IF length(v_m) <> 10 THEN
    RAISE EXCEPTION 'Invalid mobile number';
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM businesses b
  WHERE right(regexp_replace(COALESCE(b.mobile, ''), '\D', '', 'g'), 10) = v_m
    AND EXISTS (
      SELECT 1 FROM business_owners bo
      WHERE bo.business_id = b.id
        AND bo.auth_user_id IS NULL
        AND right(regexp_replace(COALESCE(bo.owner_phone, ''), '\D', '', 'g'), 10) = v_m
    );

  IF v_count = 0 THEN
    RAISE EXCEPTION 'No shop found for this phone, or already claimed.';
  END IF;
  IF v_count > 1 THEN
    RAISE EXCEPTION 'Multiple shops are registered with this mobile (%). Contact admin to link the correct one.', v_count;
  END IF;

  SELECT b.id INTO v_biz_id
  FROM businesses b
  WHERE right(regexp_replace(COALESCE(b.mobile, ''), '\D', '', 'g'), 10) = v_m
    AND EXISTS (
      SELECT 1 FROM business_owners bo
      WHERE bo.business_id = b.id
        AND bo.auth_user_id IS NULL
        AND right(regexp_replace(COALESCE(bo.owner_phone, ''), '\D', '', 'g'), 10) = v_m
    )
  LIMIT 1;

  -- Link exactly ONE unclaimed row (avoids tripping uq_biz_owner_authuser
  -- if a business somehow ended up with two shadow rows).
  UPDATE business_owners
     SET auth_user_id = v_user_id
   WHERE ctid = (
     SELECT bo.ctid FROM business_owners bo
      WHERE bo.business_id = v_biz_id
        AND bo.auth_user_id IS NULL
        AND right(regexp_replace(COALESCE(bo.owner_phone, ''), '\D', '', 'g'), 10) = v_m
      LIMIT 1
   );

  RETURN v_biz_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_business_by_phone(TEXT) TO authenticated;

-- ---- 4. Clean up any duplicate shadow rows already created --
-- (only relevant if the v1 draft of this file was run)
DELETE FROM public.business_owners a
USING public.business_owners b
WHERE a.business_id = b.business_id
  AND a.auth_user_id IS NULL
  AND b.auth_user_id IS NULL
  AND a.ctid > b.ctid;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ---- Verify (run separately) -------------------------------
-- No business should have more than one UNCLAIMED owner row:
--   SELECT business_id, count(*) FROM business_owners
--   WHERE auth_user_id IS NULL GROUP BY 1 HAVING count(*) > 1;   -- expect 0 rows
--
-- Then claim a pre-listed shop by its mobile in /panel/claim-account.html.

DO $$ BEGIN
  RAISE NOTICE '✓ db/217 v2 installed. Pre-listed shops claimable; phone matching normalised; trigger deferred.';
END $$;
