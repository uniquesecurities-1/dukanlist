-- ============================================================
-- db/237 — put the photos back on the cards
-- ============================================================
--
-- Reported by Deepak on 2026-09-29: "profile photo lagi hui hai, par
-- saamne se dikhti nahi". Regal Foods was the example. Checked live:
--
--   business_photos      3 rows, all three load fine  → the shop's own
--                        page shows them
--   businesses.photos    empty                        → every card on
--                        the site (home, search, category, golden
--                        pages) reads this one, so: no picture
--
-- Three shops fully invisible (Regal Foods, Gumber Collection, Midha
-- Mobile Accessories) and three more with fewer pictures on the cards
-- than in the gallery, out of 68 shops that have photos at all.
--
-- HOW THEY GOT THERE
--   Before the 2026-09-22 Cloudinary migration the two stores held
--   different things, so panel/photos.html listed both: "Photos" from
--   business_photos and "Old photos" from businesses.photos. After the
--   migration both hold the SAME Cloudinary URLs, so the panel showed
--   every picture twice. Owners deleted what looked like duplicates —
--   and "Delete old photo" writes only businesses.photos. The gallery
--   survived; the cards went blank. v297 stops the panel showing the
--   duplicates; this migration repairs the rows they already emptied.
--
-- sync_business_photos_array (db/222) already knows how to rebuild the
-- array from business_photos, keeping any genuinely manual URL that is
-- not in there. It is simply never called unless business_photos
-- itself changes. So: call it for every shop that is out of step.
--
-- Read-only for shops that are already correct. Safe to re-run.
-- ============================================================

BEGIN;

-- Who is out of step: the array does not match what business_photos holds.
CREATE TEMP TABLE _photo_drift AS
SELECT b.id,
       b.slug,
       b.name,
       COALESCE(array_length(b.photos, 1), 0) AS arr_before,
       COUNT(bp.id)                           AS cloud_rows
FROM public.businesses b
JOIN public.business_photos bp
  ON bp.business_id = b.id
 AND bp.cloudinary_url IS NOT NULL
 AND bp.cloudinary_url <> ''
WHERE b.status = 'active'
GROUP BY b.id, b.slug, b.name, b.photos
HAVING COALESCE(array_length(b.photos, 1), 0) <> COUNT(bp.id);

-- Rebuild each one from its own photo rows.
SELECT public.sync_business_photos_array(id) FROM _photo_drift;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/237-repair-photos-array.sql');
  END IF;
END $$;

COMMIT;

-- ============================================================
-- Before and after, per shop. 'arr_after' should now equal
-- 'cloud_rows' (or exceed it, if the shop also has a genuinely
-- manual URL that was never a business_photos row).
-- ============================================================
SELECT d.slug,
       d.name,
       d.arr_before,
       d.cloud_rows,
       COALESCE(array_length(b.photos, 1), 0) AS arr_after,
       CASE WHEN COALESCE(array_length(b.photos, 1), 0) >= d.cloud_rows
            THEN 'fixed' ELSE 'STILL SHORT — tell Claude' END AS result
FROM _photo_drift d
JOIN public.businesses b ON b.id = d.id
ORDER BY d.arr_before, d.slug;
