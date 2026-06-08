-- =====================================================
-- FINAL PHOTO UPLOAD CHECK — Unique Securities + info@digimutualgoals.com
-- =====================================================
-- Run this and share the output. Each section answers a specific question.
-- =====================================================


-- Q1: Does auth.users have info@digimutualgoals.com? What's the UUID?
SELECT
  '🔍 Q1 — auth.users row'                AS check_type,
  id::TEXT                                 AS auth_user_id,
  email,
  email_confirmed_at,
  created_at
FROM auth.users
WHERE LOWER(email) = 'info@digimutualgoals.com';


-- Q2: Does Unique Securities exist? What's its UUID and email?
SELECT
  '🔍 Q2 — businesses row'                AS check_type,
  id::TEXT                                 AS business_id,
  name,
  email                                    AS shop_email,
  status,
  created_at
FROM businesses
WHERE name ILIKE 'Unique Securities%';


-- Q3: Is the user linked to Unique Securities in business_owners?
SELECT
  '🔍 Q3 — business_owners link'           AS check_type,
  bo.id::TEXT                              AS bo_row_id,
  bo.business_id::TEXT                     AS business_id,
  b.name                                   AS shop_name,
  bo.auth_user_id::TEXT                    AS linked_auth_user,
  u.email                                  AS linked_email,
  u.email_confirmed_at                     AS verified_at,
  CASE
    WHEN bo.auth_user_id IS NULL          THEN '❌ NOT LINKED — needs UPDATE'
    WHEN u.email = 'info@digimutualgoals.com' THEN '✅ Correctly linked to info@'
    ELSE '⚠ Linked to DIFFERENT user — needs admin review'
  END                                      AS verdict
FROM business_owners bo
LEFT JOIN businesses b ON b.id = bo.business_id
LEFT JOIN auth.users u ON u.id = bo.auth_user_id
WHERE b.name ILIKE 'Unique Securities%';


-- Q4: Are all 5 storage policies installed?
SELECT
  '🔍 Q4 — storage policies'              AS check_type,
  policyname,
  cmd
FROM pg_policies
WHERE tablename = 'objects'
  AND schemaname = 'storage'
  AND policyname LIKE 'shop_photos_%'
ORDER BY policyname;


-- Q5: Bucket exists with correct settings?
SELECT
  '🔍 Q5 — bucket'                        AS check_type,
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
FROM storage.buckets
WHERE id = 'shop-photos';


-- ============================================================
-- AUTO-FIX in same run — if Q3 verdict says NOT LINKED
-- ============================================================
DO $$
DECLARE
  v_user_id        UUID;
  v_business_id    UUID;
  v_was_linked     BOOLEAN;
BEGIN
  -- Get user UUID
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE LOWER(email) = 'info@digimutualgoals.com'
  LIMIT 1;

  -- Get business UUID
  SELECT id INTO v_business_id
  FROM businesses
  WHERE name ILIKE 'Unique Securities%'
  ORDER BY created_at ASC LIMIT 1;

  IF v_user_id IS NULL OR v_business_id IS NULL THEN
    RAISE NOTICE '⚠ Cannot auto-link — user or business not found';
    RETURN;
  END IF;

  -- Already correctly linked?
  SELECT EXISTS (
    SELECT 1 FROM business_owners
    WHERE business_id = v_business_id
      AND auth_user_id = v_user_id
  ) INTO v_was_linked;

  IF v_was_linked THEN
    RAISE NOTICE '✅ AUTO-FIX: Already linked correctly. No change.';
  ELSE
    -- Try to update NULL link first
    UPDATE business_owners
       SET auth_user_id = v_user_id
     WHERE business_id = v_business_id
       AND auth_user_id IS NULL;

    IF FOUND THEN
      RAISE NOTICE '✅ AUTO-FIX: UPDATED orphan row → linked';
    ELSE
      -- No orphan row, insert new
      INSERT INTO business_owners (business_id, auth_user_id, role, added_at)
      VALUES (v_business_id, v_user_id, 'owner', NOW())
      ON CONFLICT DO NOTHING;
      RAISE NOTICE '✅ AUTO-FIX: INSERTED new business_owners row';
    END IF;
  END IF;

  -- Force email verify too
  UPDATE auth.users
     SET email_confirmed_at = COALESCE(email_confirmed_at, NOW())
   WHERE id = v_user_id
     AND email_confirmed_at IS NULL;

  IF FOUND THEN
    RAISE NOTICE '✅ AUTO-FIX: Email forcibly confirmed for info@';
  END IF;
END $$;


-- Q6: AFTER auto-fix — final state confirmation
SELECT
  '✅ AFTER AUTO-FIX'                      AS check_type,
  b.name                                   AS shop_name,
  u.email                                  AS owner_email,
  u.email_confirmed_at                     AS email_verified,
  bo.auth_user_id IS NOT NULL              AS link_present,
  bo.role
FROM business_owners bo
JOIN businesses b ON b.id = bo.business_id
JOIN auth.users u ON u.id = bo.auth_user_id
WHERE u.email = 'info@digimutualgoals.com'
   OR b.name ILIKE 'Unique Securities%';
