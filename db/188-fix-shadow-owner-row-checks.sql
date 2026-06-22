-- ============================================================
-- db/188 — Treat "shadow" business_owners rows correctly
-- ============================================================
-- BUG REPORT:
--   Admin clicked "Send Verification Email" on /admin/shop?id=...
--   for Sachdeva silai machine (which has NO auth account, just a
--   shadow business_owners row left by register_business_public).
--   RPC threw: "Failed: This listing already has an owner linked"
--
-- ROOT CAUSE:
--   db/15's register_business_public inserts a SHADOW business_owners
--   row with auth_user_id=NULL + owner_phone=<mobile>. This row is a
--   placeholder waiting for the owner to authenticate later. It does
--   NOT mean an account is linked — it just records who registered.
--
--   But db/175's admin_log_email_invite (and admin_unclaimed_list +
--   db/186's admin_manual_link_owner) all check:
--       EXISTS (SELECT 1 FROM business_owners WHERE business_id = X)
--   which returns TRUE for shadow rows too — wrongly blocking action.
--
-- THE FIX:
--   Everywhere we check "is an owner linked", we must look for a row
--   WHERE auth_user_id IS NOT NULL. Shadow rows are not real links.
--
-- AFFECTED RPCs:
--   1. admin_log_email_invite   (db/175) — was blocking on shadow rows
--   2. admin_unclaimed_list     (db/175) — was hiding listings w/ shadows
--   3. admin_email_pending_list (db/185) — bucket logic same issue
--   4. admin_manual_link_owner  (db/186) — was blocking + upgrading wrong
--
-- This migration recreates all four with the corrected check.
-- ============================================================

BEGIN;

-- ============================================================
-- 1. Fix admin_log_email_invite
-- ============================================================
CREATE OR REPLACE FUNCTION admin_log_email_invite(
  p_business_id UUID,
  p_email       TEXT,
  p_notes       TEXT DEFAULT NULL,
  p_sent_via    TEXT DEFAULT 'magic-link'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_email TEXT;
  v_business    RECORD;
  v_invite_id   BIGINT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  IF p_email IS NULL OR NOT (p_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') THEN
    RAISE EXCEPTION 'Invalid email format';
  END IF;

  SELECT id, name, status, claim_token
    INTO v_business
    FROM businesses WHERE id = p_business_id LIMIT 1;
  IF v_business.id IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  IF v_business.status NOT IN ('soft_listed','active','pending') THEN
    RAISE EXCEPTION 'Cannot invite for status=% — only soft_listed, active or pending listings', v_business.status;
  END IF;

  -- FIX: Only block if a REAL auth account is already linked. Shadow rows
  -- (auth_user_id IS NULL) are placeholders waiting to be upgraded; they
  -- should NOT block sending an invite.
  IF EXISTS (
    SELECT 1 FROM business_owners
     WHERE business_id = v_business.id
       AND auth_user_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'This listing already has an OWNER ACCOUNT linked';
  END IF;

  SELECT email INTO v_admin_email FROM admin_users WHERE auth_user_id = auth.uid();

  INSERT INTO owner_invite_log (business_id, email, sent_by_admin, sent_via, notes)
  VALUES (v_business.id, LOWER(TRIM(p_email)), v_admin_email, COALESCE(p_sent_via,'magic-link'), p_notes)
  RETURNING id INTO v_invite_id;

  -- Bump claim_status to claimed_pending so manage view reflects "invite sent"
  UPDATE businesses
     SET claim_status = 'claimed_pending',
         claim_sent_count = COALESCE(claim_sent_count, 0) + 1,
         last_claim_attempt_at = NOW(),
         updated_at = NOW()
   WHERE id = v_business.id
     AND claim_status = 'unclaimed';

  RETURN jsonb_build_object(
    'success',     TRUE,
    'invite_id',   v_invite_id,
    'business_id', v_business.id,
    'email',       LOWER(TRIM(p_email)),
    'claim_url',   'https://dukanlist.com/claim-complete.html?token=' || v_business.claim_token,
    'sent_at',     NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_log_email_invite(UUID, TEXT, TEXT, TEXT) TO authenticated;


-- ============================================================
-- 2. Fix admin_unclaimed_list — include listings with only shadow rows
-- ============================================================
CREATE OR REPLACE FUNCTION admin_unclaimed_list(
  p_search         TEXT    DEFAULT NULL,
  p_status_filter  TEXT    DEFAULT NULL,
  p_city_id        INT     DEFAULT NULL,
  p_limit          INT     DEFAULT 50,
  p_offset         INT     DEFAULT 0
)
RETURNS TABLE (
  id              UUID,
  slug            TEXT,
  name            TEXT,
  name_hi         TEXT,
  owner_name      TEXT,
  mobile          TEXT,
  area            TEXT,
  status          TEXT,
  claim_status    TEXT,
  category_name   TEXT,
  category_icon   TEXT,
  city_name       TEXT,
  pre_listed_at   TIMESTAMPTZ,
  claim_token     TEXT,
  invite_count    INT,
  last_invite_at  TIMESTAMPTZ,
  last_invite_to  TEXT,
  total_count     BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total BIGINT;
  v_status TEXT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  v_status := NULLIF(LOWER(TRIM(COALESCE(p_status_filter,''))), '');
  IF v_status IS NOT NULL AND v_status NOT IN ('soft_listed','active','pending') THEN
    RAISE EXCEPTION 'Invalid status filter: %', v_status;
  END IF;

  SELECT COUNT(*) INTO v_total
    FROM businesses b
   WHERE b.status IN ('soft_listed','active','pending')
     AND (v_status IS NULL OR b.status = v_status)
     -- FIX: Only exclude listings with a REAL auth account linked,
     -- shadow rows (auth_user_id IS NULL) are still considered unclaimed
     AND NOT EXISTS (
       SELECT 1 FROM business_owners bo
        WHERE bo.business_id = b.id
          AND bo.auth_user_id IS NOT NULL
     )
     AND (p_city_id IS NULL OR b.city_id = p_city_id)
     AND (p_search IS NULL OR LENGTH(TRIM(p_search)) = 0 OR
          b.name ILIKE '%' || TRIM(p_search) || '%' OR
          b.address_line1 ILIKE '%' || TRIM(p_search) || '%' OR
          COALESCE(b.owner_name,'') ILIKE '%' || TRIM(p_search) || '%' OR
          COALESCE(b.mobile,'') ILIKE '%' || TRIM(p_search) || '%');

  RETURN QUERY
  SELECT
    b.id, b.slug, b.name, b.name_hi, b.owner_name, b.mobile, b.address_line1,
    b.status, b.claim_status,
    c.name, c.icon,
    gc.name,
    b.pre_listed_at,
    b.claim_token,
    (SELECT COUNT(*)::INT FROM owner_invite_log l WHERE l.business_id = b.id),
    (SELECT MAX(l.sent_at)  FROM owner_invite_log l WHERE l.business_id = b.id),
    (SELECT l.email FROM owner_invite_log l WHERE l.business_id = b.id ORDER BY l.sent_at DESC LIMIT 1),
    v_total
  FROM businesses b
  LEFT JOIN categories c  ON c.id = b.category_id
  LEFT JOIN geo_cities gc ON gc.id = b.city_id
  WHERE b.status IN ('soft_listed','active','pending')
    AND (v_status IS NULL OR b.status = v_status)
    AND NOT EXISTS (
      SELECT 1 FROM business_owners bo
       WHERE bo.business_id = b.id
         AND bo.auth_user_id IS NOT NULL
    )
    AND (p_city_id IS NULL OR b.city_id = p_city_id)
    AND (p_search IS NULL OR LENGTH(TRIM(p_search)) = 0 OR
         b.name ILIKE '%' || TRIM(p_search) || '%' OR
         b.address_line1 ILIKE '%' || TRIM(p_search) || '%' OR
         COALESCE(b.owner_name,'') ILIKE '%' || TRIM(p_search) || '%' OR
         COALESCE(b.mobile,'') ILIKE '%' || TRIM(p_search) || '%')
  ORDER BY
    (SELECT MAX(l.sent_at) FROM owner_invite_log l WHERE l.business_id = b.id) DESC NULLS LAST,
    b.pre_listed_at DESC NULLS LAST
  LIMIT p_limit OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_unclaimed_list(TEXT, TEXT, INT, INT, INT) TO authenticated;


-- ============================================================
-- 3. Fix admin_email_pending_list — bucket logic with shadow rows
-- ============================================================
CREATE OR REPLACE FUNCTION admin_email_pending_list(
  p_search   TEXT DEFAULT NULL,
  p_status   TEXT DEFAULT NULL,
  p_bucket   TEXT DEFAULT NULL,
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
  bucket          TEXT,
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

  WITH candidates AS (
    SELECT
      b.id,
      CASE
        -- 'no_account' = no row at all OR only shadow rows (auth_user_id NULL)
        WHEN NOT EXISTS (
          SELECT 1 FROM business_owners bo
           WHERE bo.business_id = b.id
             AND bo.auth_user_id IS NOT NULL
        ) THEN 'no_account'
        -- 'email_unconfirmed' = linked auth user but email_confirmed_at IS NULL
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
    CASE
      WHEN NOT EXISTS (
        SELECT 1 FROM business_owners bo
         WHERE bo.business_id = b.id
           AND bo.auth_user_id IS NOT NULL
      ) THEN 'no_account'
      ELSE 'email_unconfirmed'
    END::TEXT AS bucket,
    (SELECT bo.auth_user_id FROM business_owners bo
      WHERE bo.business_id = b.id AND bo.auth_user_id IS NOT NULL LIMIT 1),
    (SELECT au.email FROM business_owners bo
       JOIN auth.users au ON au.id = bo.auth_user_id
      WHERE bo.business_id = b.id
        AND bo.auth_user_id IS NOT NULL LIMIT 1),
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
      NOT EXISTS (
        SELECT 1 FROM business_owners bo
         WHERE bo.business_id = b.id
           AND bo.auth_user_id IS NOT NULL
      )
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
         (p_bucket = 'no_account' AND NOT EXISTS (
           SELECT 1 FROM business_owners bo
            WHERE bo.business_id = b.id AND bo.auth_user_id IS NOT NULL
         ))
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


-- ============================================================
-- 4. Fix admin_manual_link_owner — also use the corrected check
-- ============================================================
CREATE OR REPLACE FUNCTION admin_manual_link_owner(
  p_business_id UUID,
  p_email       TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_email TEXT;
  v_auth_user_id UUID;
  v_email_confirmed TIMESTAMPTZ;
  v_biz RECORD;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  IF p_email IS NULL OR NOT (p_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') THEN
    RAISE EXCEPTION 'Invalid email format';
  END IF;

  SELECT email INTO v_admin_email FROM admin_users WHERE auth_user_id = auth.uid();

  SELECT id, email_confirmed_at INTO v_auth_user_id, v_email_confirmed
    FROM auth.users WHERE lower(email) = lower(TRIM(p_email)) LIMIT 1;

  IF v_auth_user_id IS NULL THEN
    RAISE EXCEPTION 'No auth user found with email %', p_email;
  END IF;

  IF v_email_confirmed IS NULL THEN
    RAISE EXCEPTION 'User % exists but email is NOT yet verified', p_email;
  END IF;

  SELECT id, name, status, mobile, claim_status INTO v_biz
    FROM businesses WHERE id = p_business_id;
  IF v_biz.id IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  -- FIX: Only block if a REAL auth owner is already linked (not shadow row)
  IF EXISTS (
    SELECT 1 FROM business_owners
     WHERE business_id = v_biz.id
       AND auth_user_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'This listing already has a linked owner account. Remove existing link first if you really want to re-assign.';
  END IF;

  -- Upgrade shadow row OR insert fresh
  IF EXISTS (SELECT 1 FROM business_owners WHERE business_id = v_biz.id AND auth_user_id IS NULL) THEN
    UPDATE business_owners
       SET auth_user_id = v_auth_user_id,
           added_at = COALESCE(added_at, NOW())
     WHERE business_id = v_biz.id
       AND auth_user_id IS NULL;
  ELSE
    INSERT INTO business_owners (business_id, auth_user_id, owner_phone, role, added_at)
    VALUES (v_biz.id, v_auth_user_id, v_biz.mobile, 'owner', NOW());
  END IF;

  UPDATE businesses
     SET claim_status = 'claimed_verified',
         claimed_at   = NOW(),
         updated_at   = NOW()
   WHERE id = v_biz.id;

  IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'admin_errors' AND schemaname = 'public') THEN
    INSERT INTO admin_errors (
      user_email, page, error_type, error_message, payload, resolved, resolved_at
    ) VALUES (
      v_admin_email, '/admin/shop.html', 'manual-link',
      'Manually linked ' || p_email || ' to ' || v_biz.name,
      jsonb_build_object('business_id', v_biz.id, 'email', p_email, 'auth_user_id', v_auth_user_id),
      TRUE, NOW()
    );
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'business_id', v_biz.id,
    'business_name', v_biz.name,
    'linked_email', LOWER(TRIM(p_email)),
    'auth_user_id', v_auth_user_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_manual_link_owner(UUID, TEXT) TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/188 installed. Shadow business_owners rows (auth_user_id IS NULL) are now correctly treated as "no real owner linked".';
END $$;
