-- ============================================================
-- db/181 — Public RPC for "Unclaimed Businesses" section on home
-- ============================================================
-- USER REQUEST:
--   "Unclaimed business ko bhi specifically dikhana hai alag se,
--    usko main business me nahi dikhana, taaki pata chal sake ki
--    these are unclaimed businesses"
--
--   = Active listings that have no linked owner account (admin
--     bulk-published, claim pending) should be shown in their OWN
--     section on the homepage — clearly labeled as Unclaimed.
--
-- THIS ADDS:
--   public_unclaimed_listings — anyone can call. Returns:
--     - active status listings
--     - that DO NOT have a business_owners row (account-less)
--     - with masked or full mobile based on verified_mobile
--   Order: newest first, capped by p_limit (max 50).
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public_unclaimed_listings(
  p_city_id   INT  DEFAULT NULL,
  p_limit     INT  DEFAULT 12,
  p_offset    INT  DEFAULT 0
)
RETURNS TABLE (
  id              UUID,
  slug            TEXT,
  name            TEXT,
  name_hi         TEXT,
  owner_name      TEXT,
  area            TEXT,
  category_id     INT,
  category_slug   TEXT,
  category_name   TEXT,
  category_icon   TEXT,
  city_id         INT,
  city_name       TEXT,
  has_mobile      BOOLEAN,
  mobile_last4    TEXT,
  mobile_full     TEXT,
  mobile_verified BOOLEAN,
  created_at      TIMESTAMPTZ,
  claim_token     TEXT,
  total_count     BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total BIGINT;
BEGIN
  SELECT COUNT(*) INTO v_total
    FROM businesses b
   WHERE b.status = 'active'
     AND NOT EXISTS (SELECT 1 FROM business_owners bo WHERE bo.business_id = b.id)
     AND (p_city_id IS NULL OR b.city_id = p_city_id);

  RETURN QUERY
  SELECT
    b.id, b.slug, b.name, b.name_hi, b.owner_name, b.address_line1,
    b.category_id, c.slug, c.name, c.icon,
    b.city_id, gc.name,
    (b.mobile IS NOT NULL AND LENGTH(b.mobile) = 10) AS has_mobile,
    CASE WHEN b.mobile IS NOT NULL AND LENGTH(b.mobile) = 10
         THEN RIGHT(b.mobile, 4) ELSE NULL END,
    CASE WHEN COALESCE(b.verified_mobile, FALSE) = TRUE
              AND b.mobile IS NOT NULL AND LENGTH(b.mobile) = 10
         THEN b.mobile ELSE NULL END,
    COALESCE(b.verified_mobile, FALSE),
    b.created_at,
    b.claim_token,
    v_total
  FROM businesses b
  LEFT JOIN categories c ON c.id = b.category_id
  LEFT JOIN geo_cities gc ON gc.id = b.city_id
  WHERE b.status = 'active'
    AND NOT EXISTS (SELECT 1 FROM business_owners bo WHERE bo.business_id = b.id)
    AND (p_city_id IS NULL OR b.city_id = p_city_id)
  ORDER BY b.created_at DESC NULLS LAST
  LIMIT GREATEST(1, LEAST(p_limit, 50)) OFFSET COALESCE(p_offset, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public_unclaimed_listings(INT, INT, INT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/181 installed. public_unclaimed_listings ready for homepage section.';
END $$;
