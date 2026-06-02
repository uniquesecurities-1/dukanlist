-- =====================================================
-- db/88-batch-link-orphan-shopkeepers.sql  (v2 - FK-safe)
-- =====================================================
-- v1 failed on: foreign key constraint business_owners_business_id_fkey
-- when a user metadata.business_id pointed to a DELETED business.
--
-- This v2 filters orphans to only those whose business still exists.
-- Also wraps the UUID cast in a safe regex check so weird metadata
-- values (non-UUID strings) don\'t crash the query.
-- =====================================================

BEGIN;

-- Help PG: cast metadata field through a safe filter
WITH orphans AS (
  SELECT
    u.id                                                        AS auth_user_id,
    u.email                                                     AS user_email,
    (u.raw_user_meta_data->>\'business_id\')::UUID            AS biz_id,
    u.raw_user_meta_data->>\'mobile\'                         AS user_mobile
  FROM auth.users u
  WHERE u.raw_user_meta_data->>\'business_id\' IS NOT NULL
    -- only valid UUID format
    AND u.raw_user_meta_data->>\'business_id\' ~* \'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$\'
    -- business must still exist (no FK violation)
    AND EXISTS (
      SELECT 1 FROM businesses b
      WHERE b.id = (u.raw_user_meta_data->>\'business_id\')::UUID
    )
    -- user not already linked to any business
    AND NOT EXISTS (
      SELECT 1 FROM business_owners bo
      WHERE bo.auth_user_id = u.id
    )
    -- and not an admin
    AND NOT EXISTS (
      SELECT 1 FROM admin_users a
      WHERE a.auth_user_id = u.id
    )
),
linked AS (
  -- Try UPDATE first - orphan row exists from register_business_public
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
    \'owner\'
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


DO $$
DECLARE
  v_total_users     INT;
  v_linked_users    INT;
  v_orphans         INT;
  v_deleted_biz     INT;
BEGIN
  SELECT COUNT(*) INTO v_total_users FROM auth.users;
  SELECT COUNT(DISTINCT auth_user_id) INTO v_linked_users
    FROM business_owners WHERE auth_user_id IS NOT NULL;

  -- Users with metadata.business_id but business deleted (cannot link)
  SELECT COUNT(*) INTO v_deleted_biz
    FROM auth.users u
    WHERE u.raw_user_meta_data->>\'business_id\' IS NOT NULL
      AND u.raw_user_meta_data->>\'business_id\' ~* \'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$\'
      AND NOT EXISTS (
        SELECT 1 FROM businesses b
        WHERE b.id = (u.raw_user_meta_data->>\'business_id\')::UUID
      )
      AND NOT EXISTS (SELECT 1 FROM admin_users a WHERE a.auth_user_id = u.id);

  -- Users with no business_id metadata and no link
  SELECT COUNT(*) INTO v_orphans
    FROM auth.users u
    WHERE NOT EXISTS (
        SELECT 1 FROM business_owners bo
        WHERE bo.auth_user_id = u.id
      )
      AND NOT EXISTS (
        SELECT 1 FROM admin_users a
        WHERE a.auth_user_id = u.id
      );

  RAISE NOTICE \'====================================================\';
  RAISE NOTICE \'BATCH LINK RESULT (v2)\';
  RAISE NOTICE \'====================================================\';
  RAISE NOTICE \'Total auth.users:                          %\', v_total_users;
  RAISE NOTICE \'Users now linked to >=1 business:          %\', v_linked_users;
  RAISE NOTICE \'Total unlinked users remaining:            %\', v_orphans;
  RAISE NOTICE \'  ... of which point to DELETED business:  %\', v_deleted_biz;
  RAISE NOTICE \'  ... rest have no metadata.business_id    %\', v_orphans - v_deleted_biz;
  RAISE NOTICE \'\';
  IF v_deleted_biz > 0 THEN
    RAISE NOTICE \'⚠ % users have orphan auth accounts because their\', v_deleted_biz;
    RAISE NOTICE \'  business was deleted. These should be either:\';
    RAISE NOTICE \'    a) Deleted via admin/test-cleanup.html, OR\';
    RAISE NOTICE \'    b) Re-registered (admin Create Login Account on a real shop)\';
  END IF;
  IF v_orphans = 0 THEN
    RAISE NOTICE \'✅ ALL USERS LINKED OR HANDLED. Photo upload ready.\';
  END IF;
  RAISE NOTICE \'====================================================\';
END $$;


-- Final list of remaining orphans with diagnosis
SELECT
  u.email,
  u.created_at::DATE                                          AS registered_on,
  u.email_confirmed_at IS NOT NULL                            AS email_verified,
  u.raw_user_meta_data->>\'business_id\'                     AS metadata_biz_id,
  u.raw_user_meta_data->>\'mobile\'                          AS metadata_mobile,
  CASE
    WHEN u.raw_user_meta_data->>\'business_id\' IS NULL
      THEN \'⚠ No business_id in metadata - old or manual signup\'
    WHEN u.raw_user_meta_data->>\'business_id\' !~* \'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$\'
      THEN \'⚠ metadata business_id is not a valid UUID\'
    WHEN NOT EXISTS (
      SELECT 1 FROM businesses b
      WHERE b.id = (u.raw_user_meta_data->>\'business_id\')::UUID
    )
      THEN \'⚠ business_id points to DELETED business - delete user or use admin Create Login on real shop\'
    ELSE
      \'✅ Linkable but missed - re-run this file\'
  END                                                          AS why_orphan
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
