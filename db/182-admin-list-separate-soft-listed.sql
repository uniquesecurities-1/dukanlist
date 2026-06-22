-- ============================================================
-- db/182 — Separate soft_listed from main DukanList in admin views
-- ============================================================
-- USER REPORT:
--   "Soft listed and main listed mix ho rahe hai... I need ki
--    dono alag alag dikhe taaki team ko manage karna mushkil na ho"
--
--   = In admin views (especially dashboard Recent feed),
--     soft_listed (Golden Pages) shops were appearing mixed in with
--     active/pending main DukanList shops because callers passed
--     p_status=NULL which let everything through.
--
-- ARCHITECTURE FIX:
--   - admin_list_businesses(p_status=NULL) now EXCLUDES soft_listed.
--     NULL is interpreted as "all main DukanList queues", NOT
--     "literally every status".
--   - To explicitly fetch soft_listed, pass p_status='soft_listed'.
--   - Backward compatible because the only callers passing NULL
--     today are admin dashboard's "Recent" feed (intended to show
--     main DukanList only).
--
--   - New convenience RPC admin_recent_soft_listed(limit) returns
--     the LATEST soft_listed shops for a dedicated dashboard panel.
-- ============================================================

BEGIN;

-- ============================================================
-- PART 1: Replace admin_list_businesses with soft_listed exclusion
-- ============================================================
DROP FUNCTION IF EXISTS admin_list_businesses(TEXT, INT, INT, TEXT);

CREATE OR REPLACE FUNCTION admin_list_businesses(
  p_status TEXT     DEFAULT NULL,
  p_limit  INT      DEFAULT 50,
  p_offset INT      DEFAULT 0,
  p_sort   TEXT     DEFAULT 'newest'
)
RETURNS TABLE (
  id            UUID,
  slug          TEXT,
  name          TEXT,
  name_hi       TEXT,
  owner_name    TEXT,
  mobile        TEXT,
  whatsapp      TEXT,
  email         TEXT,
  status        TEXT,
  primary_cat   TEXT,
  city_name     TEXT,
  state_code    TEXT,
  pincode       TEXT,
  photos_count  INT,
  verified_score INT,
  rating_avg    NUMERIC,
  rating_count  INT,
  flagged_count INT,
  lead_count    INT,
  view_count    INT,
  created_at    TIMESTAMPTZ,
  last_active_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role   TEXT;
  v_cities INT[];
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT role, assigned_city_ids INTO v_role, v_cities
  FROM admin_users WHERE auth_user_id = auth.uid();

  RETURN QUERY
  SELECT
    b.id, b.slug, b.name, b.name_hi, b.owner_name, b.mobile, b.whatsapp, b.email,
    b.status::TEXT,
    COALESCE(pc.name, fc.name)        AS primary_cat,
    gc.name                            AS city_name,
    gs.code                            AS state_code,
    b.pincode,
    COALESCE(array_length(b.photos,1),0)::INT AS photos_count,
    b.verified_score,
    b.rating_avg, b.rating_count,
    b.flagged_count, b.lead_count, b.view_count,
    b.created_at, b.last_active_at
  FROM businesses b
  LEFT JOIN geo_cities  gc ON gc.id = b.city_id
  LEFT JOIN geo_states  gs ON gs.id = b.state_id
  LEFT JOIN business_categories bcp ON bcp.business_id = b.id AND bcp.is_primary = TRUE
  LEFT JOIN categories pc ON pc.id = bcp.category_id
  LEFT JOIN categories fc ON fc.id = b.sub_category_id
  WHERE (
          -- If admin explicitly asked for a status, return only that one
          (p_status IS NOT NULL AND b.status::TEXT = p_status)
          -- If p_status IS NULL → "all main DukanList" — exclude Golden Pages
          OR (p_status IS NULL AND b.status::TEXT <> 'soft_listed')
        )
    AND (v_role = 'super_admin' OR v_cities IS NULL OR v_cities = '{}' OR b.city_id = ANY(v_cities))
    -- Email gate stays the same — when looking at pending, hide unverified-email registrations
    AND (
      p_status IS DISTINCT FROM 'pending'
      OR b.email_gate_at_signup = FALSE
      OR business_has_verified_owner(b.id)
    )
  ORDER BY
    CASE WHEN p_sort = 'oldest' THEN b.created_at END ASC,
    CASE WHEN p_sort = 'newest' OR p_sort IS NULL THEN b.created_at END DESC,
    CASE WHEN p_sort = 'flags' THEN b.flagged_count END DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_list_businesses(TEXT,INT,INT,TEXT) TO authenticated;


-- ============================================================
-- PART 2: admin_recent_soft_listed — dedicated GP recent panel
-- ============================================================
CREATE OR REPLACE FUNCTION admin_recent_soft_listed(
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
    c.name AS primary_cat,
    gc.name AS city_name,
    b.pre_listed_at,
    b.pre_listed_by,
    EXISTS (SELECT 1 FROM business_owners bo WHERE bo.business_id = b.id),
    b.claim_token
  FROM businesses b
  LEFT JOIN categories c ON c.id = b.category_id
  LEFT JOIN geo_cities gc ON gc.id = b.city_id
  WHERE b.status = 'soft_listed'
  ORDER BY b.pre_listed_at DESC NULLS LAST, b.created_at DESC
  LIMIT GREATEST(1, LEAST(p_limit, 100));
END;
$$;

GRANT EXECUTE ON FUNCTION admin_recent_soft_listed(INT) TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/182 installed. admin_list_businesses(NULL) now excludes soft_listed. admin_recent_soft_listed ready for dedicated GP panel.';
END $$;
