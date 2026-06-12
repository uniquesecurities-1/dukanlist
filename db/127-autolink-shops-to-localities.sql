-- ============================================================
-- db/127 — Auto-link existing shops to their localities
-- ============================================================
-- After db/126 added 11 new Mandi Dabwali localities, we have 98+
-- existing shops whose `locality_id` is NULL. This script does an
-- intelligent scan of each shop's address_line1 / address_line2
-- and links it to the matching locality.
--
-- HEURISTIC: ILIKE match on address with the locality name.
-- Multiple matches → longest match wins (more specific).
-- E.g. "Old Grain Market" beats "Grain Market" if both match.
--
-- SAFE: Only updates shops where locality_id IS NULL. Re-runnable.
-- DB never disturbed (forward-only, no deletes).
-- ============================================================

BEGIN;

-- ---- Pre-scan: how many shops are unlinked? ----
DO $$
DECLARE
  v_unlinked INT;
  v_total    INT;
BEGIN
  SELECT COUNT(*) INTO v_unlinked
  FROM businesses
  WHERE locality_id IS NULL AND city_id IS NOT NULL;

  SELECT COUNT(*) INTO v_total
  FROM businesses
  WHERE city_id IS NOT NULL;

  RAISE NOTICE 'Pre-scan: % of % shops have NULL locality_id (%.1f%%)',
    v_unlinked, v_total, (v_unlinked::numeric * 100 / GREATEST(v_total, 1));
END $$;

-- ---- Auto-link via substring match ----
-- For each unlinked shop, find the locality in the same city whose
-- name appears as a substring in address_line1 (or address_line2).
-- Longest-match wins.
UPDATE businesses b
SET locality_id = sub.matched_locality_id
FROM (
  SELECT DISTINCT ON (b2.id)
    b2.id AS biz_id,
    l.id  AS matched_locality_id,
    l.name AS matched_locality_name
  FROM businesses b2
  JOIN geo_localities l ON l.city_id = b2.city_id
  WHERE b2.locality_id IS NULL
    AND b2.city_id IS NOT NULL
    AND (
      -- Match against either address line; trim whitespace, case-insensitive
      lower(COALESCE(b2.address_line1, '')) LIKE '%' || lower(l.name) || '%'
      OR lower(COALESCE(b2.address_line2, '')) LIKE '%' || lower(l.name) || '%'
      -- Also match Hindi name if present
      OR (l.name_hi IS NOT NULL AND (
           lower(COALESCE(b2.address_line1, '')) LIKE '%' || lower(l.name_hi) || '%'
        OR lower(COALESCE(b2.address_line2, '')) LIKE '%' || lower(l.name_hi) || '%'
      ))
    )
  -- DISTINCT ON (b2.id) keeps the FIRST row per biz, ordered by:
  --   length of locality name DESC (longest match wins — "Old Grain Market" beats "Grain Market")
  ORDER BY b2.id, length(l.name) DESC, l.id
) AS sub
WHERE b.id = sub.biz_id;

-- ---- Post-scan: report what got linked ----
DO $$
DECLARE
  v_still_unlinked INT;
  v_total          INT;
BEGIN
  SELECT COUNT(*) INTO v_still_unlinked
  FROM businesses
  WHERE locality_id IS NULL AND city_id IS NOT NULL;

  SELECT COUNT(*) INTO v_total
  FROM businesses
  WHERE city_id IS NOT NULL;

  RAISE NOTICE 'Post-scan: % of % shops STILL have NULL locality_id (%.1f%%)',
    v_still_unlinked, v_total, (v_still_unlinked::numeric * 100 / GREATEST(v_total, 1));
END $$;

COMMIT;

-- ============================================================
-- VERIFY 1: locality distribution after autolink
-- ============================================================
SELECT
  l.name AS locality,
  c.name AS city,
  COUNT(b.id) AS active_shops
FROM geo_localities l
JOIN geo_cities c ON c.id = l.city_id
LEFT JOIN businesses b ON b.locality_id = l.id AND b.status = 'active'
WHERE c.name = 'Mandi Dabwali'
GROUP BY l.id, l.name, c.name
ORDER BY active_shops DESC, l.name;

-- ============================================================
-- VERIFY 2: shops still without a locality (manual review list)
-- ============================================================
SELECT
  b.name,
  b.address_line1,
  c.name AS city
FROM businesses b
JOIN geo_cities c ON c.id = b.city_id
WHERE b.locality_id IS NULL
  AND b.status = 'active'
ORDER BY c.name, b.created_at DESC
LIMIT 30;

DO $$ BEGIN
  RAISE NOTICE 'db/127 installed.';
  RAISE NOTICE '  Existing shops auto-linked to localities where their address';
  RAISE NOTICE '  mentions a known locality name. Manual review for remainder.';
END $$;
