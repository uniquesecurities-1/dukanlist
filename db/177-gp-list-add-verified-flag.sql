-- ============================================================
-- db/177 — gp_list_shops: add is_verified_owner flag
-- ============================================================
-- USER ARCHITECTURE (final):
--   - Golden Pages = no email required (public self-add OR admin)
--   - When email is captured + verified → owner gets account
--   - Listing then shifts to DukanList main + gets Verified badge
--   - Admin CAN publish to DukanList without email, BUT no badge
--     and no owner account until email comes in and verifies.
--
-- THIS ADDS:
--   is_verified_owner (BOOLEAN) — TRUE when business_owners row exists
--   for this business (i.e. an email-verified account is linked).
--
-- This lets the public UI show:
--   ✓ Verified Owner badge when owner has an account
--   (no badge when listing is still unclaimed)
-- ============================================================

BEGIN;

DROP FUNCTION IF EXISTS gp_list_shops(TEXT, INT, TEXT, INT, INT);

CREATE OR REPLACE FUNCTION gp_list_shops(
  p_category_slug TEXT DEFAULT NULL,
  p_city_id       INT  DEFAULT NULL,
  p_search        TEXT DEFAULT NULL,
  p_limit         INT  DEFAULT 50,
  p_offset        INT  DEFAULT 0
)
RETURNS TABLE (
  id                  UUID,
  slug                TEXT,
  name                TEXT,
  name_hi             TEXT,
  owner_name          TEXT,
  area                TEXT,
  has_mobile          BOOLEAN,
  mobile_last4        TEXT,
  category_id         INT,
  category_slug       TEXT,
  category_name       TEXT,
  category_icon       TEXT,
  city_id             INT,
  city_name           TEXT,
  pre_listed_at       TIMESTAMPTZ,
  claim_token         TEXT,
  is_verified_owner   BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    b.id, b.slug, b.name,
    b.name_hi,
    b.owner_name,
    b.address_line1,
    (b.mobile IS NOT NULL AND LENGTH(b.mobile) = 10) AS has_mobile,
    CASE
      WHEN b.mobile IS NOT NULL AND LENGTH(b.mobile) = 10 THEN RIGHT(b.mobile, 4)
      ELSE NULL
    END AS mobile_last4,
    b.category_id, c.slug, c.name, c.icon,
    b.city_id, gc.name,
    b.pre_listed_at,
    b.claim_token,
    -- TRUE only when an email-verified owner account is linked
    EXISTS (SELECT 1 FROM business_owners bo WHERE bo.business_id = b.id) AS is_verified_owner
  FROM businesses b
  LEFT JOIN categories c ON c.id = b.category_id
  LEFT JOIN geo_cities gc ON gc.id = b.city_id
  WHERE b.status = 'soft_listed'
    AND (p_category_slug IS NULL OR c.slug = p_category_slug)
    AND (p_city_id IS NULL OR b.city_id = p_city_id)
    AND (p_search IS NULL OR LENGTH(TRIM(p_search)) = 0 OR
         b.name         ILIKE '%' || TRIM(p_search) || '%' OR
         b.name_hi      ILIKE '%' || TRIM(p_search) || '%' OR
         b.owner_name   ILIKE '%' || TRIM(p_search) || '%' OR
         b.address_line1 ILIKE '%' || TRIM(p_search) || '%')
  ORDER BY b.pre_listed_at DESC NULLS LAST, b.name ASC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION gp_list_shops(TEXT, INT, TEXT, INT, INT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/177 installed. gp_list_shops now returns is_verified_owner.';
END $$;
