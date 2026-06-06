-- =====================================================
-- db/89-cleanup-orphan-deleted-biz-users.sql  (v2 — simplified)
-- =====================================================
-- USER (2026-06-02): "Jaise sacredheartpublicschool wali shop maine
--   delete kar di — uske users bhi clean kar do. Jo shops deleted hai
--   un users ko bhi handle karo."
--
-- v1 ERROR FIX:
--   v1 had a "content preservation" guard that referenced
--   community_questions.author_user_id, community_replies.author_user_id
--   and reviews.user_id. Those columns DO NOT EXIST in this schema —
--   the actual tables identify authors by anonymous phone_hash
--   (asker_phone_hash, replier_phone_hash, customer_phone_hash) — they
--   are not tied to auth.users at all. So those guards both errored
--   and were unnecessary. v2 simply removes them.
--
-- WHAT THIS DOES:
--   Safely DELETES orphan auth.users rows where:
--     - raw_user_meta_data.business_id points to a UUID
--     - that UUID is NOT in `businesses` (deleted business)
--     - user has NO row in business_owners
--     - user is NOT an admin
--   Cascade automatically removes their sessions, refresh_tokens,
--   identities via Supabase auth FKs.
--
-- LIMIT 200 per run as a safety guard against accidental mass-delete.
-- IDEMPOTENT: safe to re-run.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. PREVIEW: how many will be deleted
-- ============================================================
DO $$
DECLARE
  v_to_delete  INT;
BEGIN
  SELECT COUNT(*) INTO v_to_delete
  FROM auth.users u
  WHERE u.raw_user_meta_data->>'business_id' IS NOT NULL
    AND u.raw_user_meta_data->>'business_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    AND NOT EXISTS (
      SELECT 1 FROM businesses b
      WHERE b.id = (u.raw_user_meta_data->>'business_id')::UUID
    )
    AND NOT EXISTS (SELECT 1 FROM business_owners bo WHERE bo.auth_user_id = u.id)
    AND NOT EXISTS (SELECT 1 FROM admin_users a       WHERE a.auth_user_id = u.id);

  RAISE NOTICE '====================================================';
  RAISE NOTICE 'ORPHAN AUTH USER CLEANUP — PREVIEW';
  RAISE NOTICE '====================================================';
  RAISE NOTICE 'Will delete: % orphan auth users', v_to_delete;
  RAISE NOTICE '(business deleted, no business_owners link, not admin)';
  RAISE NOTICE '====================================================';
END $$;


-- ============================================================
-- 2. SHOW the rows being deleted (audit trail in output)
-- ============================================================
SELECT
  u.email                                AS email_being_deleted,
  u.created_at::DATE                     AS registered_on,
  u.email_confirmed_at IS NOT NULL       AS was_email_verified,
  u.raw_user_meta_data->>'business_id'   AS pointed_to_deleted_biz_id,
  u.raw_user_meta_data->>'mobile'        AS metadata_mobile
FROM auth.users u
WHERE u.raw_user_meta_data->>'business_id' IS NOT NULL
  AND u.raw_user_meta_data->>'business_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  AND NOT EXISTS (
    SELECT 1 FROM businesses b
    WHERE b.id = (u.raw_user_meta_data->>'business_id')::UUID
  )
  AND NOT EXISTS (SELECT 1 FROM business_owners bo WHERE bo.auth_user_id = u.id)
  AND NOT EXISTS (SELECT 1 FROM admin_users a       WHERE a.auth_user_id = u.id)
ORDER BY u.created_at DESC
LIMIT 200;


-- ============================================================
-- 3. ACTUAL DELETE
--    Uses the SAME filter. LIMIT 200 prevents accident.
--    Cascade handles sessions / refresh_tokens / identities.
-- ============================================================
WITH targets AS (
  SELECT u.id
  FROM auth.users u
  WHERE u.raw_user_meta_data->>'business_id' IS NOT NULL
    AND u.raw_user_meta_data->>'business_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    AND NOT EXISTS (
      SELECT 1 FROM businesses b
      WHERE b.id = (u.raw_user_meta_data->>'business_id')::UUID
    )
    AND NOT EXISTS (SELECT 1 FROM business_owners bo WHERE bo.auth_user_id = u.id)
    AND NOT EXISTS (SELECT 1 FROM admin_users a       WHERE a.auth_user_id = u.id)
  LIMIT 200
)
DELETE FROM auth.users
WHERE id IN (SELECT id FROM targets);


-- ============================================================
-- 4. FINAL STATE REPORT
-- ============================================================
DO $$
DECLARE
  v_total_users        INT;
  v_remaining_orphans  INT;
  v_all_unlinked       INT;
BEGIN
  SELECT COUNT(*) INTO v_total_users FROM auth.users;

  -- Still-orphan users whose business is deleted (should be 0 now)
  SELECT COUNT(*) INTO v_remaining_orphans
  FROM auth.users u
  WHERE u.raw_user_meta_data->>'business_id' IS NOT NULL
    AND u.raw_user_meta_data->>'business_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    AND NOT EXISTS (
      SELECT 1 FROM businesses b
      WHERE b.id = (u.raw_user_meta_data->>'business_id')::UUID
    )
    AND NOT EXISTS (SELECT 1 FROM business_owners bo WHERE bo.auth_user_id = u.id)
    AND NOT EXISTS (SELECT 1 FROM admin_users a       WHERE a.auth_user_id = u.id);

  -- All unlinked auth.users (any reason)
  SELECT COUNT(*) INTO v_all_unlinked
  FROM auth.users u
  WHERE NOT EXISTS (SELECT 1 FROM business_owners bo WHERE bo.auth_user_id = u.id)
    AND NOT EXISTS (SELECT 1 FROM admin_users a       WHERE a.auth_user_id = u.id);

  RAISE NOTICE '';
  RAISE NOTICE '====================================================';
  RAISE NOTICE 'AFTER CLEANUP';
  RAISE NOTICE '====================================================';
  RAISE NOTICE 'Total auth.users now:                      %', v_total_users;
  RAISE NOTICE 'Deleted-biz orphans remaining:             %', v_remaining_orphans;
  RAISE NOTICE 'All unlinked auth.users (any reason):      %', v_all_unlinked;
  RAISE NOTICE '====================================================';
  IF v_remaining_orphans = 0 THEN
    RAISE NOTICE 'SUCCESS — all deleted-business ghost accounts cleaned.';
  ELSE
    RAISE NOTICE 'NOTE: % still remain (likely > 200 limit). Re-run.', v_remaining_orphans;
  END IF;
END $$;

COMMIT;


-- ============================================================
-- 5. FINAL LIST — anyone STILL orphan (after cleanup)
-- ============================================================
SELECT
  u.email,
  u.created_at::DATE                                          AS registered_on,
  u.email_confirmed_at IS NOT NULL                            AS email_verified,
  u.raw_user_meta_data->>'business_id'                        AS metadata_biz_id,
  CASE
    WHEN u.raw_user_meta_data->>'business_id' IS NULL
      THEN 'No business_id - likely a customer / old account'
    WHEN u.raw_user_meta_data->>'business_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN 'Invalid metadata UUID'
    WHEN NOT EXISTS (
      SELECT 1 FROM businesses b
      WHERE b.id = (u.raw_user_meta_data->>'business_id')::UUID
    )
      THEN 'Deleted-biz orphan - re-run db/89 (over 200 batch limit)'
    ELSE
      'Linkable - re-run db/88 to attach to existing business'
  END                                                         AS why_still_orphan
FROM auth.users u
WHERE NOT EXISTS (SELECT 1 FROM business_owners bo WHERE bo.auth_user_id = u.id)
  AND NOT EXISTS (SELECT 1 FROM admin_users a       WHERE a.auth_user_id = u.id)
ORDER BY u.created_at DESC
LIMIT 30;
