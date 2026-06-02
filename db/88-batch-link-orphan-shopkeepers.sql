-- =====================================================
-- db/88-batch-link-orphan-shopkeepers.sql
-- =====================================================
-- CRITICAL USER ISSUE (2026-06-02):
--   Diagnostic showed 10 out of 13 recent shopkeeper signups have NO
--   business_owners link. They registered but their account never got
--   wired to their business.
--
-- ROOT CAUSE:
--   register.html line 1657 only runs claim_business_by_phone() if
--   signUpRes.data.session exists. With email confirmation ON in
--   Supabase, signUp returns NO session — user must verify email first
--   AND THEN log in for the claim to happen.
--
--   Many users register, then either:
--     * Never verify email (account stays orphaned forever)
--     * Verify email but never come back to log in
--     * Verify + login but their user_metadata.mobile doesn't exactly
--       match businesses.mobile (formatting / +91 prefix mismatch)
--
-- THIS PATCH (idempotent, safe):
--   1. Finds all auth.users who have:
--        * No business_owners link yet
--        * user_metadata.business_id pointing to a real business
--          (register.html stores it at signup time)
--   2. INSERTs or UPDATEs the business_owners row to link them.
--   3. Logs how many were fixed.
--
-- SAFE TO RE-RUN — uses ON CONFLICT to upsert and only operates on
-- users where the link is genuinely missing.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. Batch link orphan users using user_metadata.business_id
-- ============================================================
WITH orphans AS (
  SELECT
    u.id                                                    AS auth_user_id,
    u.email                                                 AS user_email,
    (u.raw_user_meta_data->>'business_id')::UUID            AS biz_id,
    u.raw_user_meta_data->>'mobile'                         AS user_mobile
  FROM auth.users u
  WHERE u.raw_user_meta_data->>'business_id' IS NOT NULL
    -- Only candidates with no active link yet
    AND NOT EXISTS (
      SELECT 1 FROM business_owners bo
      WHERE bo.auth_user_id = u.id
    )
    -- And not an admin
    AND NOT EXISTS (
      SELECT 1 FROM admin_users a
      WHERE a.auth_user_id = u.id
    )
),
linked AS (
  -- Try UPDATE first — orphan row exists from register_business_public
  UPDATE business_owners bo
  SET auth_user_id = o.auth_user_id
  FROM orphans o
  WHERE bo.business_id = o.biz_id
    AND bo.auth_user_id IS NULL
  RETURNING bo.business_id, bo.auth_user_id
),
inserted AS (
  -- For users whose business has no orphan row, INSERT a new one
  INSERT INTO business_owners (business_id, auth_user_id, owner_phone, role)
  SELECT
    o.biz_id,
    o.auth_user_id,
    o.user_mobile,
    'owner'
  FROM orphans o
  WHERE NOT EXISTS (
    SELECT 1 FROM business_owners bo2
    WHERE bo2.business_id = o.biz_id
      AND bo2.auth_user_id = o.auth_user_id
  )
  ON CONFLICT DO NOTHING
  RETURNING business_id, auth_user_id
)
SELECT
  (SELECT COUNT(*) FROM linked)    AS updated_orphan_rows,
  (SELECT COUNT(*) FROM inserted)  AS new_link_rows,
  (SELECT COUNT(*) FROM orphans)   AS total_orphan_users_processed;

COMMIT;


-- ============================================================
-- 2. VERIFICATION — show before/after counts
-- ============================================================
DO $$
DECLARE
  v_total_users     INT;
  v_linked_users    INT;
  v_orphans         INT;
BEGIN
  SELECT COUNT(*) INTO v_total_users FROM auth.users;
  SELECT COUNT(DISTINCT auth_user_id) INTO v_linked_users
    FROM business_owners WHERE auth_user_id IS NOT NULL;
  SELECT COUNT(*) INTO v_orphans
    FROM auth.users u
    WHERE u.raw_user_meta_data->>'business_id' IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM business_owners bo
        WHERE bo.auth_user_id = u.id
      )
      AND NOT EXISTS (
        SELECT 1 FROM admin_users a
        WHERE a.auth_user_id = u.id
      );

  RAISE NOTICE '====================================================';
  RAISE NOTICE 'BATCH LINK RESULT';
  RAISE NOTICE '====================================================';
  RAISE NOTICE 'Total auth.users:                          %', v_total_users;
  RAISE NOTICE 'Users now linked to >=1 business:          %', v_linked_users;
  RAISE NOTICE 'Remaining orphan users (could not link):   %', v_orphans;
  RAISE NOTICE '';
  IF v_orphans = 0 THEN
    RAISE NOTICE '✅ All orphan users with valid user_metadata.business_id';
    RAISE NOTICE '   are now linked. Photo upload should work for them.';
  ELSE
    RAISE NOTICE '⚠ % users still unlinked — their user_metadata.business_id', v_orphans;
    RAISE NOTICE '   may be missing or point to a deleted business.';
    RAISE NOTICE '   These need manual admin link via admin/shop.html.';
  END IF;
  RAISE NOTICE '====================================================';
END $$;


-- ============================================================
-- 3. SHOW REMAINING ORPHANS — admin can manually link these
-- ============================================================
SELECT
  u.email,
  u.created_at::DATE                                       AS registered_on,
  u.email_confirmed_at IS NOT NULL                          AS email_verified,
  u.raw_user_meta_data->>'business_id'                      AS metadata_biz_id,
  u.raw_user_meta_data->>'mobile'                           AS metadata_mobile,
  CASE
    WHEN u.raw_user_meta_data->>'business_id' IS NULL
      THEN '⚠ No business_id in metadata — was a manual or old signup'
    WHEN NOT EXISTS (
      SELECT 1 FROM businesses b
      WHERE b.id = (u.raw_user_meta_data->>'business_id')::UUID
    )
      THEN '⚠ business_id points to deleted business — admin Create Login'
    ELSE
      '✅ Linkable but missed — re-run this file or manual link'
  END                                                       AS why_orphan
FROM auth.users u
WHERE NOT EXISTS (
        SELECT 1 FROM business_owners bo
        WHERE bo.auth_user_id = u.id
      )
  AND NOT EXISTS (
        SELECT 1 FROM admin_users a
        WHERE a.auth_user_id = u.id
      )
ORDER BY u.created_at DESC
LIMIT 30;
