-- ============================================================
-- db/222 — make businesses.photos the single source of truth
--
-- THE PROBLEM
-- -----------
-- Photos are stored in two unconnected places:
--   businesses.photos     TEXT[]  — 44 active shops
--   business_photos       table   — 8 active shops (Cloudinary uploads)
-- Today the overlap is exactly ZERO: a shop is in one or the other, never
-- both. Nothing ever wrote an upload back into the array.
--
-- businesses.photos is what the rest of the system actually reads:
--   * admin dashboard photos_count      -> those 8 shops show "0 photos"
--   * dl_shop_score (db/221)            -> 2 points per photo, capped at 10,
--                                          so a shop with uploads loses up to
--                                          20 ranking points for photos it has
--   * api/biz.js og:image               -> shared links fall back to the
--                                          generic DukanList image
-- The public listing page reads business_photos separately, which is why the
-- photo is visible there and the admin table says 0 — the same data
-- disagreeing with itself depending on who asks.
--
-- Now that rank is printed on the public page, in the owner's panel and on a
-- certificate, a shop being silently marked down for photos it uploaded is
-- not a cosmetic bug.
--
-- THE FIX
-- -------
-- One function rebuilds businesses.photos for a shop = its Cloudinary uploads
-- (featured first) followed by any URLs already in the array that did not come
-- from business_photos. A trigger runs it on every insert/update/delete, and a
-- one-time backfill repairs the 8 shops that are wrong today.
--
-- Nothing is deleted: the 44 shops whose photos live only in the array keep
-- them untouched.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.sync_business_photos_array(p_business_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cloud  TEXT[];
  v_manual TEXT[];
  v_final  TEXT[];
BEGIN
  IF p_business_id IS NULL THEN RETURN; END IF;

  -- Uploads, featured first, then oldest first so the order is stable.
  SELECT COALESCE(array_agg(u.cloudinary_url ORDER BY u.feat DESC, u.uploaded_at ASC), '{}')
  INTO v_cloud
  FROM (
    SELECT DISTINCT ON (bp.cloudinary_url)
           bp.cloudinary_url,
           COALESCE(bp.is_featured, false) AS feat,
           bp.uploaded_at
    FROM business_photos bp
    WHERE bp.business_id = p_business_id
      AND bp.cloudinary_url IS NOT NULL
      AND bp.cloudinary_url <> ''
    ORDER BY bp.cloudinary_url, COALESCE(bp.is_featured, false) DESC, bp.uploaded_at ASC
  ) u;

  -- Anything already in the array that did NOT come from business_photos —
  -- photos added directly during registration or bulk upload. Keep them.
  SELECT COALESCE(array_agg(x.url ORDER BY x.ord), '{}')
  INTO v_manual
  FROM (
    SELECT url, ord
    FROM unnest(COALESCE((SELECT b.photos FROM businesses b WHERE b.id = p_business_id), '{}'))
         WITH ORDINALITY AS t(url, ord)
    WHERE url IS NOT NULL AND url <> ''
      AND NOT (url = ANY(v_cloud))
  ) x;

  v_final := v_cloud || v_manual;

  -- Trim to a sane ceiling; the score caps at 10 anyway.
  IF array_length(v_final, 1) > 20 THEN
    v_final := v_final[1:20];
  END IF;

  UPDATE businesses
  SET photos = v_final
  WHERE id = p_business_id
    AND COALESCE(photos, '{}') IS DISTINCT FROM v_final;   -- no pointless writes
END;
$$;


-- ------------------------------------------------------------
-- Keep it true from now on.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_sync_business_photos()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.sync_business_photos_array(OLD.business_id);
    RETURN OLD;
  END IF;

  PERFORM public.sync_business_photos_array(NEW.business_id);
  -- A photo moved between shops: refresh the shop it left, too.
  IF TG_OP = 'UPDATE' AND OLD.business_id IS DISTINCT FROM NEW.business_id THEN
    PERFORM public.sync_business_photos_array(OLD.business_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_business_photos_sync ON public.business_photos;
CREATE TRIGGER trg_business_photos_sync
  AFTER INSERT OR UPDATE OR DELETE ON public.business_photos
  FOR EACH ROW EXECUTE FUNCTION public.trg_sync_business_photos();


-- ------------------------------------------------------------
-- One-time repair of everything already out of sync.
-- ------------------------------------------------------------
DO $$
DECLARE r RECORD; n INT := 0;
BEGIN
  FOR r IN SELECT DISTINCT business_id FROM business_photos WHERE business_id IS NOT NULL
  LOOP
    PERFORM public.sync_business_photos_array(r.business_id);
    n := n + 1;
  END LOOP;
  RAISE NOTICE 'db/222 backfill: synced % businesses that have uploads', n;
END $$;

COMMIT;

-- Report the result so the fix is visible, not assumed.
DO $$
DECLARE v_still_wrong INT; v_with_photos INT;
BEGIN
  SELECT COUNT(*) INTO v_still_wrong
  FROM businesses b
  WHERE b.status = 'active'
    AND EXISTS (SELECT 1 FROM business_photos p WHERE p.business_id = b.id)
    AND COALESCE(array_length(b.photos, 1), 0) = 0;

  SELECT COUNT(*) INTO v_with_photos
  FROM businesses b
  WHERE b.status = 'active' AND COALESCE(array_length(b.photos, 1), 0) > 0;

  RAISE NOTICE 'Active shops that have an upload but still show 0 photos: %  (should be 0)', v_still_wrong;
  RAISE NOTICE 'Active shops now counted as having photos: %', v_with_photos;
  RAISE NOTICE 'db/222 installed.';
END $$;
