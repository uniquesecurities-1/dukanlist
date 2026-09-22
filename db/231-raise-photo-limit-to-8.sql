-- ============================================================
-- db/231 — raise the per-shop photo limit from 5 to 8
-- ============================================================
--
-- Deepak wants every shop to be able to upload up to 8 photos
-- (was 5). The cap lives in two places and BOTH must agree, or the
-- panel lets someone pick an 8th photo and the DB then rejects it:
--
--   * panel/photos.html   MAX_PHOTOS = 8   (done in v273)
--   * this trigger         the real guard, enforced server-side
--
-- Only the number changes. The trigger still counts business_photos
-- (Cloudinary) rows per shop; legacy businesses.photos array entries
-- are not counted here, same as before.
--
-- Safe to re-run.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.enforce_photo_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
    FROM public.business_photos
   WHERE business_id = NEW.business_id;

  IF v_count >= 8 THEN
    RAISE EXCEPTION 'Photo limit reached — maximum 8 photos per shop allowed'
      USING HINT = 'Delete an existing photo to upload a new one';
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger already points at this function (db/200); nothing to re-wire.
COMMIT;

-- Confirm the new limit is in the live function body.
SELECT
  CASE WHEN pg_get_functiondef('public.enforce_photo_limit'::regprocedure) LIKE '%>= 8%'
       THEN 'OK — limit is now 8'
       ELSE 'CHECK — still not 8' END AS photo_limit_status;
