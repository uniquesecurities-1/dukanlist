-- ============================================================
-- db/185 — admin_email_pending_list — single source for ALL
--         listings where the owner can't yet log in
-- ============================================================
-- USER QUESTION:
--   "Jo log abhi maine approve kar diye hai... jinki email verify
--    nahi hai abhi tak unhe admin me kaise filter karenge?"
--
--   = After admin approves a 'pending' listing (or bulk-publishes
--     one without email), the owner may not have a usable login
--     because their email_confirmed_at is still NULL or there's
--     no auth user at all. We need an admin view of ALL such
--     listings so admin can take action (resend invite / force
--     verify / contact owner).
--
-- THIS ADDS:
--   admin_email_pending_list — returns active/pending/soft_listed
--   listings that fall into ONE of these "needs action" buckets:
--
--   bucket = 'no_account'           → No business_owners row at all
--   bucket = 'email_unconfirmed'    → Has business_owners row but
--                                     auth.users.email_confirmed_at IS NULL
--
--   Each row carries a `bucket` column so the admin UI can group +
--   colour-code them.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION admin_email_pending_list(
  p_search   TEXT DEFAULT NULL,
  p_status   TEXT DEFAULT NULL,         -- 'active' | 'pending' | 'soft_listed' | NULL=all
  p_bucket   TEXT DEFAULT NULL,         -- 'no_account' | 'email_unconfirmed' | NULL=both
  p_city_id  INT  DEFAULT NULL,
  p_limit    INT  DEFAULT 50,
  p_offset   INT  DEFAULT 0
)
RETURNS TABLE (
  id              UUID,
  slug            TEXT,
  name            TEXT,
  name_hi         TEXT,
  owner_name      TEXT,
  mobile          TEXT,
  email           TEXT,
  area            TEXT,
  status          TEXT,
  bucket          TEXT,                 -- 'no_account' | 'email_unconfirmed'
  owner_auth_uid  UUID,
  owner_auth_email TEXT,
  category_name   TEXT,
  category_icon   TEXT,
  city_name       TEXT,
  pre_listed_at   TIMESTAMPTZ,
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
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  -- Pre-compute total
  WITH candidates AS (
    SELECT
      b.id,
      CASE
        WHEN NOT EXISTS (SELECT 1 FROM business_owners bo WHERE bo.business_id = b.id)
          THEN 'no_account'
        WHEN EXISTS (
          SELECT 1 FROM business_owners bo
            JOIN auth.users au ON au.id = bo.auth_user_id
           WHERE bo.business_id = b.id
             AND au.email_confirmed_at IS NULL
        ) THEN 'email_unconfirmed'
        ELSE NULL
      END AS bucket_calc
    FROM businesses b
    WHERE b.status IN ('active','pending','soft_listed')
      AND (p_status IS NULL OR b.status::TEXT = p_status)
      AND (p_city_id IS NULL OR b.city_id = p_city_id)
  )
  SELECT COUNT(*) INTO v_total
    FROM candidates
   WHERE bucket_calc IS NOT NULL
     AND (p_bucket IS NULL OR bucket_calc = p_bucket);

  RETURN QUERY
  SELECT
    b.id, b.slug, b.name, b.name_hi, b.owner_name, b.mobile, b.email,
    b.address_line1, b.status::TEXT,
    -- Compute bucket per row
    CASE
      WHEN NOT EXISTS (SELECT 1 FROM business_owners bo WHERE bo.business_id = b.id)
        THEN 'no_account'
      ELSE 'email_unconfirmed'
    END::TEXT AS bucket,
    (SELECT bo.auth_user_id FROM business_owners bo WHERE bo.business_id = b.id LIMIT 1),
    (SELECT au.email FROM business_owners bo
       JOIN auth.users au ON au.id = bo.auth_user_id
      WHERE bo.business_id = b.id LIMIT 1),
    c.name::TEXT, c.icon::TEXT,
    gc.name::TEXT,
    b.pre_listed_at, b.created_at,
    b.claim_token,
    v_total
  FROM businesses b
  LEFT JOIN categories c   ON c.id = b.category_id
  LEFT JOIN geo_cities gc  ON gc.id = b.city_id
  WHERE b.status IN ('active','pending','soft_listed')
    AND (
      -- No account: pure account-less listings
      NOT EXISTS (SELECT 1 FROM business_owners bo WHERE bo.business_id = b.id)
      -- OR email unconfirmed: has owner but email_confirmed_at IS NULL
      OR EXISTS (
        SELECT 1 FROM business_owners bo
          JOIN auth.users au ON au.id = bo.auth_user_id
         WHERE bo.business_id = b.id
           AND au.email_confirmed_at IS NULL
      )
    )
    AND (p_status IS NULL OR b.status::TEXT = p_status)
    AND (p_city_id IS NULL OR b.city_id = p_city_id)
    AND (p_bucket IS NULL OR
         (p_bucket = 'no_account' AND NOT EXISTS (SELECT 1 FROM business_owners bo WHERE bo.business_id = b.id))
         OR
         (p_bucket = 'email_unconfirmed' AND EXISTS (
           SELECT 1 FROM business_owners bo
             JOIN auth.users au ON au.id = bo.auth_user_id
            WHERE bo.business_id = b.id
              AND au.email_confirmed_at IS NULL
         ))
        )
    AND (p_search IS NULL OR LENGTH(TRIM(p_search)) = 0 OR
         b.name ILIKE '%' || TRIM(p_search) || '%' OR
         b.address_line1 ILIKE '%' || TRIM(p_search) || '%' OR
         COALESCE(b.owner_name,'') ILIKE '%' || TRIM(p_search) || '%' OR
         COALESCE(b.mobile,'') ILIKE '%' || TRIM(p_search) || '%' OR
         COALESCE(b.email,'') ILIKE '%' || TRIM(p_search) || '%')
  ORDER BY b.created_at DESC NULLS LAST
  LIMIT GREATEST(1, LEAST(p_limit, 200))
  OFFSET GREATEST(0, p_offset);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_email_pending_list(TEXT, TEXT, TEXT, INT, INT, INT) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/185 installed. admin_email_pending_list ready for unified email-pending view.';
END $$;
