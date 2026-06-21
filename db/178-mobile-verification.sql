-- ============================================================
-- db/178 — Mobile verification toggle (uses existing verified_mobile column)
-- ============================================================
-- USER REQUEST:
--   "phone no. verify hone par full phone no. dikhane ka option
--    bhi mujhe admin end se do"
--   = Admin should have a toggle to verify a phone. When verified,
--     the FULL phone is shown publicly. When unverified, it stays
--     masked (last-4 only).
--
-- DISCOVERY:
--   businesses.verified_mobile BOOLEAN already exists (db/01-schema:129)
--   and contributes to verified_score. We REUSE it here instead of
--   adding a duplicate column.
--
-- ARCHITECTURE:
--   - Default for new listings = FALSE (mobile masked publicly)
--   - Existing 'active' listings (admin-curated DukanList) — backfilled
--     to TRUE since admin manually vetted them
--   - 'soft_listed' (Golden Pages) = FALSE by default
--   - Admin "Verify Phone" button flips to TRUE
--   - When TRUE: full mobile shown publicly + "Phone Verified" badge
--   - When FALSE: masked as XXXXXX-1234
--
-- THIS ADDS:
--   1. mobile_verified_at + mobile_verified_by audit columns
--   2. admin_set_mobile_verified RPC
--   3. Backfill: all 'active' status listings with valid mobile → verified
--   4. Extends gp_list_shops with full mobile (if verified) + flag
-- ============================================================

BEGIN;

-- Audit columns (the boolean already exists, we just track who/when verified)
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS mobile_verified_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS mobile_verified_by   TEXT;

CREATE INDEX IF NOT EXISTS idx_biz_verified_mobile
  ON businesses(verified_mobile) WHERE verified_mobile = TRUE;

-- Backfill: existing 'active' DukanList listings are admin-curated,
-- presume their mobile was verified at entry. Only flip if a valid
-- 10-digit mobile exists AND not already marked.
UPDATE businesses
   SET verified_mobile = TRUE,
       mobile_verified_at = COALESCE(updated_at, NOW()),
       mobile_verified_by = 'backfill:db-178'
 WHERE status = 'active'
   AND mobile IS NOT NULL AND LENGTH(mobile) = 10
   AND COALESCE(verified_mobile, FALSE) = FALSE;


-- ============================================================
-- RPC: admin_set_mobile_verified — single toggle endpoint
-- ============================================================
CREATE OR REPLACE FUNCTION admin_set_mobile_verified(
  p_business_id UUID,
  p_verified    BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_email TEXT;
  v_mobile      TEXT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  SELECT email INTO v_admin_email FROM admin_users WHERE auth_user_id = auth.uid();

  SELECT mobile INTO v_mobile FROM businesses WHERE id = p_business_id;
  IF v_mobile IS NULL OR LENGTH(v_mobile) <> 10 THEN
    RAISE EXCEPTION 'Cannot verify — listing has no valid 10-digit mobile';
  END IF;

  UPDATE businesses
     SET verified_mobile     = COALESCE(p_verified, FALSE),
         mobile_verified_at  = CASE WHEN COALESCE(p_verified, FALSE) THEN NOW() ELSE NULL END,
         mobile_verified_by  = CASE WHEN COALESCE(p_verified, FALSE) THEN v_admin_email ELSE NULL END,
         updated_at          = NOW()
   WHERE id = p_business_id;

  RETURN jsonb_build_object(
    'success',          TRUE,
    'business_id',      p_business_id,
    'mobile_verified',  COALESCE(p_verified, FALSE),
    'verified_at',      CASE WHEN COALESCE(p_verified, FALSE) THEN NOW() ELSE NULL END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_set_mobile_verified(UUID, BOOLEAN) TO authenticated;


-- ============================================================
-- Refresh gp_list_shops with verified_mobile + conditional full mobile
-- ============================================================
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
  mobile_full         TEXT,         -- NULL unless verified_mobile
  mobile_verified     BOOLEAN,
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
    -- Privacy gate: full mobile only exposed when admin verified
    CASE
      WHEN COALESCE(b.verified_mobile, FALSE) = TRUE
       AND b.mobile IS NOT NULL AND LENGTH(b.mobile) = 10
        THEN b.mobile
      ELSE NULL
    END AS mobile_full,
    COALESCE(b.verified_mobile, FALSE) AS mobile_verified,
    b.category_id, c.slug, c.name, c.icon,
    b.city_id, gc.name,
    b.pre_listed_at,
    b.claim_token,
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


-- ============================================================
-- Refresh admin_gp_list_all to include verified_mobile flag
-- ============================================================
DROP FUNCTION IF EXISTS admin_gp_list_all(INT, TEXT, TEXT, BOOLEAN, BOOLEAN, INT, INT);

CREATE OR REPLACE FUNCTION admin_gp_list_all(
  p_city_id        INT  DEFAULT NULL,
  p_category_slug  TEXT DEFAULT NULL,
  p_search         TEXT DEFAULT NULL,
  p_only_no_mobile BOOLEAN DEFAULT FALSE,
  p_only_no_owner  BOOLEAN DEFAULT FALSE,
  p_limit          INT  DEFAULT 50,
  p_offset         INT  DEFAULT 0
)
RETURNS TABLE (
  id                 UUID,
  slug               TEXT,
  name               TEXT,
  name_hi            TEXT,
  owner_name         TEXT,
  mobile             TEXT,
  mobile_verified    BOOLEAN,
  area               TEXT,
  category_id        INT,
  category_name      TEXT,
  category_icon      TEXT,
  category_slug      TEXT,
  city_id            INT,
  city_name          TEXT,
  pre_listed_by      TEXT,
  pre_listed_at      TIMESTAMPTZ,
  consent_notes      TEXT,
  claim_token        TEXT,
  help_request_count INT,
  total_count        BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total BIGINT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  SELECT COUNT(*) INTO v_total
    FROM businesses b
    LEFT JOIN categories c ON c.id = b.category_id
   WHERE b.status = 'soft_listed'
     AND (p_city_id IS NULL OR b.city_id = p_city_id)
     AND (p_category_slug IS NULL OR c.slug = p_category_slug)
     AND (p_search IS NULL OR LENGTH(TRIM(p_search)) = 0 OR
          b.name ILIKE '%' || TRIM(p_search) || '%' OR
          b.address_line1 ILIKE '%' || TRIM(p_search) || '%' OR
          COALESCE(b.owner_name,'') ILIKE '%' || TRIM(p_search) || '%')
     AND (NOT p_only_no_mobile OR b.mobile IS NULL OR LENGTH(b.mobile) <> 10)
     AND (NOT p_only_no_owner  OR b.owner_name IS NULL OR LENGTH(TRIM(b.owner_name)) = 0);

  RETURN QUERY
  SELECT
    b.id, b.slug, b.name, b.name_hi, b.owner_name, b.mobile,
    COALESCE(b.verified_mobile, FALSE),
    b.address_line1,
    b.category_id, c.name, c.icon, c.slug,
    b.city_id, gc.name,
    b.pre_listed_by, b.pre_listed_at, b.consent_notes,
    b.claim_token,
    (SELECT COUNT(*)::INT FROM gp_help_reach_log l WHERE l.business_id = b.id),
    v_total
  FROM businesses b
  LEFT JOIN categories c ON c.id = b.category_id
  LEFT JOIN geo_cities gc ON gc.id = b.city_id
  WHERE b.status = 'soft_listed'
    AND (p_city_id IS NULL OR b.city_id = p_city_id)
    AND (p_category_slug IS NULL OR c.slug = p_category_slug)
    AND (p_search IS NULL OR LENGTH(TRIM(p_search)) = 0 OR
         b.name ILIKE '%' || TRIM(p_search) || '%' OR
         b.address_line1 ILIKE '%' || TRIM(p_search) || '%' OR
         COALESCE(b.owner_name,'') ILIKE '%' || TRIM(p_search) || '%')
    AND (NOT p_only_no_mobile OR b.mobile IS NULL OR LENGTH(b.mobile) <> 10)
    AND (NOT p_only_no_owner  OR b.owner_name IS NULL OR LENGTH(TRIM(b.owner_name)) = 0)
  ORDER BY b.pre_listed_at DESC NULLS LAST
  LIMIT p_limit OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_gp_list_all(INT, TEXT, TEXT, BOOLEAN, BOOLEAN, INT, INT) TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/178 installed. Mobile verification uses existing verified_mobile column. Active listings auto-backfilled.';
END $$;
