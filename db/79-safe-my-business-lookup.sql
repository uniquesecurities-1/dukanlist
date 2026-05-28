-- =====================================================
-- db/79-safe-my-business-lookup.sql
-- =====================================================
-- 🚨 CRITICAL SECURITY FIX (2026-05-28):
-- User report: "Mai apna shop ka login karta hu to kabhi kisi shop ka
-- to kabhi kisi shop ka panel khul jaata hai... isse to koi bhi kisi
-- ka bhi data kharab kar dega maze lene ke liye."
--
-- ROOT CAUSE:
--   panel/*.html pages call:
--     .from('business_owners').select('business_id')
--     .eq('auth_user_id', user.id).limit(1)
--   When the same auth_user_id is linked to MULTIPLE business_id rows
--   (legacy data from before the db/71 silent-auto-claim fix), this
--   .limit(1) returns NON-DETERMINISTIC row — so the same login can
--   show different shops on different page loads.
--
-- WHY BAD ROWS EXIST:
--   Before db/71, login silently called claim_business_by_phone(mobile),
--   which added a business_owners row even if the user wasn't the real
--   owner — as long as their mobile matched. After a shop was deleted,
--   the NEXT shop with the same phone would silently get claimed.
--   db/71 stopped FUTURE silent claims, but did NOT clean up existing
--   bad rows. This SQL provides cleanup + safe lookup going forward.
--
-- THIS MIGRATION ADDS:
--   1. get_my_business_safe() RPC — returns the SINGLE best-match
--      business for the calling user, with a confidence flag. Used by
--      all panel/*.html pages instead of raw .limit(1).
--   2. get_my_businesses() RPC — returns ALL businesses linked to
--      this user, ranked by match quality. Used if UI wants a switcher.
--   3. admin_audit_business_owners() RPC — super-admin tool to find
--      suspicious cross-links (auth_user_id linked to a business whose
--      email/mobile don't match the auth user's identity).
--   4. admin_unlink_bad_business_owners() RPC — super-admin tool to
--      clean up suspicious links. DRY-RUN by default.
--
-- BACKWARDS COMPATIBLE: all existing pages continue to work; they
-- just need to switch to the new RPC for the safer behavior.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. get_my_business_safe() — single best match for current user
-- ============================================================
DROP FUNCTION IF EXISTS get_my_business_safe();

CREATE OR REPLACE FUNCTION get_my_business_safe()
RETURNS TABLE (
  business_id    UUID,
  match_score    INT,     -- 0=ambiguous, 1=mobile-match, 2=email-match, 3=both-match
  total_links    INT,     -- how many business_owners rows exist for this user
  warning        TEXT     -- non-empty if ambiguous/suspicious
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id      UUID;
  v_user_email   TEXT;
  v_user_phone   TEXT;
  v_total        INT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Pull auth user's email + phone (from auth.users)
  SELECT lower(au.email), au.raw_user_meta_data->>'mobile'
    INTO v_user_email, v_user_phone
  FROM auth.users au
  WHERE au.id = v_user_id;

  -- Normalize phone (strip +91/91/leading 0)
  IF v_user_phone IS NOT NULL THEN
    v_user_phone := regexp_replace(v_user_phone, '^(\+?91|0)', '');
  END IF;

  -- Count all links for this user
  SELECT COUNT(*) INTO v_total FROM business_owners WHERE auth_user_id = v_user_id;

  IF v_total = 0 THEN
    RETURN; -- no business linked
  END IF;

  -- Return the BEST match: highest match_score, then earliest claim
  RETURN QUERY
  SELECT
    bo.business_id,
    (
      -- Score: +1 for mobile match, +2 for email match (max 3)
      CASE WHEN b.mobile IS NOT NULL AND v_user_phone IS NOT NULL
           AND regexp_replace(b.mobile, '^(\+?91|0)', '') = v_user_phone
           THEN 1 ELSE 0 END
      +
      CASE WHEN b.email IS NOT NULL AND v_user_email IS NOT NULL
           AND lower(b.email) = v_user_email
           THEN 2 ELSE 0 END
    )::INT AS match_score,
    v_total AS total_links,
    CASE
      WHEN v_total > 1 THEN
        '⚠ Multiple shops linked to this account (' || v_total || ' total). Showing best match. Use "Switch shop" to change.'
      ELSE
        ''
    END::TEXT AS warning
  FROM business_owners bo
  JOIN businesses b ON b.id = bo.business_id
  WHERE bo.auth_user_id = v_user_id
  ORDER BY
    -- Best match first
    (
      CASE WHEN b.mobile IS NOT NULL AND v_user_phone IS NOT NULL
           AND regexp_replace(b.mobile, '^(\+?91|0)', '') = v_user_phone
           THEN 1 ELSE 0 END
      +
      CASE WHEN b.email IS NOT NULL AND v_user_email IS NOT NULL
           AND lower(b.email) = v_user_email
           THEN 2 ELSE 0 END
    ) DESC,
    -- Then: business created earliest (oldest, most likely the original)
    b.created_at ASC
  LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION get_my_business_safe() TO authenticated;


-- ============================================================
-- 2. get_my_businesses() — full list (for switcher UI)
-- ============================================================
DROP FUNCTION IF EXISTS get_my_businesses();

CREATE OR REPLACE FUNCTION get_my_businesses()
RETURNS TABLE (
  business_id    UUID,
  name           TEXT,
  slug           TEXT,
  city_name      TEXT,
  status         TEXT,
  match_score    INT,
  is_best        BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id      UUID;
  v_user_email   TEXT;
  v_user_phone   TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT lower(au.email), au.raw_user_meta_data->>'mobile'
    INTO v_user_email, v_user_phone
  FROM auth.users au
  WHERE au.id = v_user_id;

  IF v_user_phone IS NOT NULL THEN
    v_user_phone := regexp_replace(v_user_phone, '^(\+?91|0)', '');
  END IF;

  RETURN QUERY
  WITH scored AS (
    SELECT
      bo.business_id,
      b.name,
      b.slug,
      gc.name AS city_name,
      b.status,
      (
        CASE WHEN b.mobile IS NOT NULL AND v_user_phone IS NOT NULL
             AND regexp_replace(b.mobile, '^(\+?91|0)', '') = v_user_phone
             THEN 1 ELSE 0 END
        +
        CASE WHEN b.email IS NOT NULL AND v_user_email IS NOT NULL
             AND lower(b.email) = v_user_email
             THEN 2 ELSE 0 END
      )::INT AS match_score,
      b.created_at
    FROM business_owners bo
    JOIN businesses b ON b.id = bo.business_id
    LEFT JOIN geo_cities gc ON gc.id = b.city_id
    WHERE bo.auth_user_id = v_user_id
  ),
  ranked AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY match_score DESC, created_at ASC) AS rn
    FROM scored
  )
  SELECT
    r.business_id, r.name, r.slug, r.city_name, r.status, r.match_score,
    (r.rn = 1) AS is_best
  FROM ranked r
  ORDER BY r.match_score DESC, r.created_at ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_my_businesses() TO authenticated;


-- ============================================================
-- 3. admin_audit_business_owners() — find suspicious cross-links
-- ============================================================
DROP FUNCTION IF EXISTS admin_audit_business_owners();

CREATE OR REPLACE FUNCTION admin_audit_business_owners()
RETURNS TABLE (
  auth_user_id   UUID,
  user_email     TEXT,
  user_phone     TEXT,
  business_id    UUID,
  business_name  TEXT,
  business_email TEXT,
  business_mobile TEXT,
  email_match    BOOLEAN,
  phone_match    BOOLEAN,
  is_suspicious  BOOLEAN,
  claimed_at     TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  RETURN QUERY
  SELECT
    bo.auth_user_id,
    lower(au.email)::TEXT AS user_email,
    regexp_replace(coalesce(au.raw_user_meta_data->>'mobile', ''), '^(\+?91|0)', '')::TEXT AS user_phone,
    bo.business_id,
    b.name::TEXT AS business_name,
    lower(coalesce(b.email, ''))::TEXT AS business_email,
    regexp_replace(coalesce(b.mobile, ''), '^(\+?91|0)', '')::TEXT AS business_mobile,
    (b.email IS NOT NULL AND lower(b.email) = lower(au.email)) AS email_match,
    (
      b.mobile IS NOT NULL
      AND au.raw_user_meta_data->>'mobile' IS NOT NULL
      AND regexp_replace(b.mobile, '^(\+?91|0)', '') = regexp_replace(au.raw_user_meta_data->>'mobile', '^(\+?91|0)', '')
    ) AS phone_match,
    -- Suspicious if NEITHER email nor phone matches
    NOT (
      (b.email IS NOT NULL AND lower(b.email) = lower(au.email))
      OR
      (b.mobile IS NOT NULL
       AND au.raw_user_meta_data->>'mobile' IS NOT NULL
       AND regexp_replace(b.mobile, '^(\+?91|0)', '') = regexp_replace(au.raw_user_meta_data->>'mobile', '^(\+?91|0)', ''))
    ) AS is_suspicious,
    bo.created_at AS claimed_at
  FROM business_owners bo
  JOIN auth.users au ON au.id = bo.auth_user_id
  JOIN businesses b ON b.id = bo.business_id
  ORDER BY is_suspicious DESC, bo.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_audit_business_owners() TO authenticated;


-- ============================================================
-- 4. admin_unlink_bad_business_owners() — DRY-RUN cleanup
-- ============================================================
DROP FUNCTION IF EXISTS admin_unlink_bad_business_owners(BOOLEAN);

CREATE OR REPLACE FUNCTION admin_unlink_bad_business_owners(p_dry_run BOOLEAN DEFAULT TRUE)
RETURNS TABLE (
  action           TEXT,
  auth_user_id     UUID,
  business_id      UUID,
  business_name    TEXT,
  reason           TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;
  v_admin_id := auth.uid();

  -- Identify suspicious links: auth user has NO email/phone match with the business
  -- AND user has ANOTHER linked business which DOES match (so this one is the bad one)
  RETURN QUERY
  WITH user_matches AS (
    SELECT
      bo.auth_user_id,
      bo.business_id,
      b.name AS business_name,
      (b.email IS NOT NULL AND lower(b.email) = lower(au.email)) AS email_match,
      (
        b.mobile IS NOT NULL
        AND au.raw_user_meta_data->>'mobile' IS NOT NULL
        AND regexp_replace(b.mobile, '^(\+?91|0)', '') = regexp_replace(au.raw_user_meta_data->>'mobile', '^(\+?91|0)', '')
      ) AS phone_match
    FROM business_owners bo
    JOIN auth.users au ON au.id = bo.auth_user_id
    JOIN businesses b ON b.id = bo.business_id
  ),
  bad_links AS (
    SELECT um.auth_user_id, um.business_id, um.business_name
    FROM user_matches um
    WHERE um.email_match = FALSE AND um.phone_match = FALSE
      AND EXISTS (
        SELECT 1 FROM user_matches um2
        WHERE um2.auth_user_id = um.auth_user_id
          AND um2.business_id <> um.business_id
          AND (um2.email_match OR um2.phone_match)
      )
  )
  SELECT
    CASE WHEN p_dry_run THEN 'WOULD UNLINK (dry-run)' ELSE 'UNLINKED' END::TEXT,
    bl.auth_user_id,
    bl.business_id,
    bl.business_name::TEXT,
    'No email/phone match — user has another valid link'::TEXT
  FROM bad_links bl;

  -- If not dry-run, actually delete + log to admin_audit_log
  IF NOT p_dry_run THEN
    BEGIN
      INSERT INTO admin_audit_log(admin_id, action, details)
      SELECT
        v_admin_id,
        'unlink_bad_business_owner',
        jsonb_build_object('auth_user_id', bl.auth_user_id, 'business_id', bl.business_id, 'business_name', bl.business_name)
      FROM (
        SELECT um.auth_user_id, um.business_id, um.business_name
        FROM (
          SELECT
            bo.auth_user_id, bo.business_id, b.name AS business_name,
            (b.email IS NOT NULL AND lower(b.email) = lower(au.email)) AS email_match,
            (b.mobile IS NOT NULL AND au.raw_user_meta_data->>'mobile' IS NOT NULL
             AND regexp_replace(b.mobile, '^(\+?91|0)', '') = regexp_replace(au.raw_user_meta_data->>'mobile', '^(\+?91|0)', '')) AS phone_match
          FROM business_owners bo
          JOIN auth.users au ON au.id = bo.auth_user_id
          JOIN businesses b ON b.id = bo.business_id
        ) um
        WHERE um.email_match = FALSE AND um.phone_match = FALSE
          AND EXISTS (
            SELECT 1 FROM business_owners bo2
            JOIN auth.users au2 ON au2.id = bo2.auth_user_id
            JOIN businesses b2 ON b2.id = bo2.business_id
            WHERE bo2.auth_user_id = um.auth_user_id
              AND bo2.business_id <> um.business_id
              AND (
                (b2.email IS NOT NULL AND lower(b2.email) = lower(au2.email))
                OR
                (b2.mobile IS NOT NULL AND au2.raw_user_meta_data->>'mobile' IS NOT NULL
                 AND regexp_replace(b2.mobile, '^(\+?91|0)', '') = regexp_replace(au2.raw_user_meta_data->>'mobile', '^(\+?91|0)', ''))
              )
          )
      ) bl;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    DELETE FROM business_owners bo
    WHERE EXISTS (
      SELECT 1 FROM (
        SELECT um.auth_user_id, um.business_id
        FROM (
          SELECT
            bo2.auth_user_id, bo2.business_id,
            (b.email IS NOT NULL AND lower(b.email) = lower(au.email)) AS email_match,
            (b.mobile IS NOT NULL AND au.raw_user_meta_data->>'mobile' IS NOT NULL
             AND regexp_replace(b.mobile, '^(\+?91|0)', '') = regexp_replace(au.raw_user_meta_data->>'mobile', '^(\+?91|0)', '')) AS phone_match
          FROM business_owners bo2
          JOIN auth.users au ON au.id = bo2.auth_user_id
          JOIN businesses b ON b.id = bo2.business_id
        ) um
        WHERE um.email_match = FALSE AND um.phone_match = FALSE
          AND um.auth_user_id = bo.auth_user_id
          AND um.business_id = bo.business_id
          AND EXISTS (
            SELECT 1 FROM business_owners bo3
            JOIN auth.users au3 ON au3.id = bo3.auth_user_id
            JOIN businesses b3 ON b3.id = bo3.business_id
            WHERE bo3.auth_user_id = um.auth_user_id
              AND bo3.business_id <> um.business_id
              AND (
                (b3.email IS NOT NULL AND lower(b3.email) = lower(au3.email))
                OR
                (b3.mobile IS NOT NULL AND au3.raw_user_meta_data->>'mobile' IS NOT NULL
                 AND regexp_replace(b3.mobile, '^(\+?91|0)', '') = regexp_replace(au3.raw_user_meta_data->>'mobile', '^(\+?91|0)', ''))
              )
          )
      ) bl
    );
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_unlink_bad_business_owners(BOOLEAN) TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- HOW TO USE (run in Supabase SQL Editor, manually, as super_admin):
-- =====================================================
-- STEP 1: Audit (see all current links + identify suspicious ones)
--    SELECT * FROM admin_audit_business_owners()
--    WHERE is_suspicious = TRUE
--    ORDER BY user_email;
--
-- STEP 2: Dry-run cleanup (see what would be unlinked, no changes yet)
--    SELECT * FROM admin_unlink_bad_business_owners(TRUE);
--
-- STEP 3: Review dry-run output. If safe, run cleanup for real:
--    SELECT * FROM admin_unlink_bad_business_owners(FALSE);
--
-- STEP 4: Verify no suspicious links remain:
--    SELECT COUNT(*) FROM admin_audit_business_owners() WHERE is_suspicious;
-- =====================================================
