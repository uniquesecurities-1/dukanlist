-- ============================================================
-- db/230 — Golden Pages showed EVERY soft-listed shop as "claimed"
-- ============================================================
--
-- WHAT DEEPAK SAW
--   In the admin Golden Pages list, all ~100 soft-listed shops
--   showed the green "CLAIMED" badge. He was right that this is
--   wrong — almost none of them have a real owner.
--
-- WHY
--   db/217 gives EVERY pre-listed shop a SHADOW owner row:
--       business_owners(business_id, auth_user_id = NULL, ...)
--   so the shop is claimable later, and a trigger keeps making one
--   for each new shop. So a business_owners row exists for all of
--   them — but with auth_user_id NULL, meaning NOBODY has actually
--   claimed it.
--
--   admin_recent_soft_listed computed:
--       has_owner_account = EXISTS(business_owners WHERE business_id=b.id)
--   which counts those shadow rows, so it was true for every shop.
--   The real-claim test is auth_user_id IS NOT NULL.
--
-- WHAT THIS FIXES
--   1. has_owner_account now means a REAL claim (auth_user_id present),
--      so the shells read UNCLAIMED and the genuinely-claimed few read
--      CLAIMED — which is what the v272 Delete button gates on.
--   2. Adds photos_count and rating_count, so the Delete button can
--      show at a glance whether a shell is truly empty before it goes.
--      (The list did not carry these before.)
--
--   Columns are only ADDED to the RETURNS TABLE; the one caller reads
--   fields by name, so nothing breaks.
--
-- Requires db/182. Safe to re-run.
-- ============================================================

BEGIN;

DROP FUNCTION IF EXISTS public.admin_recent_soft_listed(INT);

CREATE FUNCTION public.admin_recent_soft_listed(
  p_limit INT DEFAULT 10
)
RETURNS TABLE (
  id            UUID,
  slug          TEXT,
  name          TEXT,
  name_hi       TEXT,
  owner_name    TEXT,
  mobile        TEXT,
  primary_cat   TEXT,
  city_name     TEXT,
  pre_listed_at TIMESTAMPTZ,
  pre_listed_by TEXT,
  has_owner_account BOOLEAN,
  photos_count  INT,
  rating_count  INT,
  claim_token   TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  RETURN QUERY
  SELECT
    b.id, b.slug, b.name, b.name_hi, b.owner_name, b.mobile,
    c.name  AS primary_cat,
    gc.name AS city_name,
    b.pre_listed_at,
    b.pre_listed_by,
    -- v230: a shadow row has auth_user_id NULL and is NOT a claim.
    EXISTS (
      SELECT 1 FROM business_owners bo
      WHERE bo.business_id = b.id
        AND bo.auth_user_id IS NOT NULL
    ) AS has_owner_account,
    -- photos live in the businesses.photos array AND the
    -- business_photos table (Cloudinary). Count both.
    (COALESCE(array_length(b.photos, 1), 0)
       + COALESCE((SELECT COUNT(*)::INT FROM business_photos bp
                    WHERE bp.business_id = b.id), 0))::INT AS photos_count,
    COALESCE((SELECT COUNT(*)::INT FROM reviews rv
               WHERE rv.business_id = b.id
                 AND COALESCE(rv.status, 'active') = 'active'), 0)::INT AS rating_count,
    b.claim_token
  FROM businesses b
  LEFT JOIN categories c  ON c.id  = b.category_id
  LEFT JOIN geo_cities gc ON gc.id = b.city_id
  WHERE b.status = 'soft_listed'
  ORDER BY b.pre_listed_at DESC NULLS LAST, b.created_at DESC
  LIMIT GREATEST(1, LEAST(p_limit, 500));
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_recent_soft_listed(INT) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- Prove it. Shows how many soft-listed shops are REALLY claimed vs
-- shells, so the "all claimed" symptom is visibly gone.
SELECT
  count(*)                                        AS total_soft_listed,
  count(*) FILTER (WHERE has_owner_account)        AS really_claimed,
  count(*) FILTER (WHERE NOT has_owner_account)    AS unclaimed_shells,
  count(*) FILTER (WHERE NOT has_owner_account
                     AND photos_count = 0
                     AND rating_count = 0)          AS empty_shells
FROM public.admin_recent_soft_listed(500);
