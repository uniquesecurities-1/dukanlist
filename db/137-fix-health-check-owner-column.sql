-- ============================================================
-- db/137 — Fix admin_health_check: wrong owner column reference
-- ============================================================
-- BUG: db/136 used `businesses.owner_user_id` for check #5 (owners with
--      no listing). That column doesn't exist on businesses — instead
--      ownership lives in the join table:
--        business_owners (business_id UUID, auth_user_id UUID, ...)
--      (See db/01-schema.sql.)
--
-- Symptom in UI: admin_health_check returned 400 with
--   ERROR 42703: column "b.owner_user_id" of relation "businesses" does not exist
--
-- This migration replaces the function with the corrected join.
-- IDEMPOTENT: CREATE OR REPLACE.
-- DB never disturbed — forward-only, no schema changes.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION admin_health_check()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_checks JSONB := '[]'::jsonb;
  v_stats  JSONB;
  v_n      BIGINT;
  v_n2     BIGINT;
  v_critical_categories TEXT[] := ARRAY[
    'healthcare','retail-shopping','home-services','food-restaurant',
    'education','professional-services','hospitality-travel'
  ];
  v_cat TEXT;
  v_status TEXT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  -- ---- 1. Schema invariants — critical parent categories present? ----
  FOREACH v_cat IN ARRAY v_critical_categories LOOP
    SELECT COUNT(*) INTO v_n FROM categories WHERE slug = v_cat AND parent_id IS NULL;
    v_status := CASE WHEN v_n = 1 THEN 'ok' ELSE 'fail' END;
    v_checks := v_checks || jsonb_build_object(
      'category',  'Schema',
      'name',      'Parent category: ' || v_cat,
      'status',    v_status,
      'expected',  1,
      'actual',    v_n,
      'message',   CASE WHEN v_n = 1 THEN 'present' ELSE 'MISSING — silent migration failure?' END
    );
  END LOOP;

  -- ---- 2. Shops with orphan category_id (category was deleted) ----
  SELECT COUNT(*) INTO v_n
  FROM businesses b
  WHERE b.category_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM categories c WHERE c.id = b.category_id);
  v_checks := v_checks || jsonb_build_object(
    'category', 'Data Integrity',
    'name',     'Shops with orphan category_id',
    'status',   CASE WHEN v_n = 0 THEN 'ok' WHEN v_n < 5 THEN 'warn' ELSE 'fail' END,
    'expected', 0,
    'actual',   v_n,
    'message',  CASE WHEN v_n = 0 THEN 'clean' ELSE v_n::TEXT || ' shops point at deleted categories' END
  );

  -- ---- 3. Shops with orphan city_id ----
  SELECT COUNT(*) INTO v_n
  FROM businesses b
  WHERE b.city_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM geo_cities c WHERE c.id = b.city_id);
  v_checks := v_checks || jsonb_build_object(
    'category', 'Data Integrity',
    'name',     'Shops with orphan city_id',
    'status',   CASE WHEN v_n = 0 THEN 'ok' WHEN v_n < 5 THEN 'warn' ELSE 'fail' END,
    'expected', 0,
    'actual',   v_n,
    'message',  CASE WHEN v_n = 0 THEN 'clean' ELSE v_n::TEXT || ' shops point at deleted cities' END
  );

  -- ---- 4. Shops with orphan locality_id ----
  SELECT COUNT(*) INTO v_n
  FROM businesses b
  WHERE b.locality_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM geo_localities l WHERE l.id = b.locality_id);
  v_checks := v_checks || jsonb_build_object(
    'category', 'Data Integrity',
    'name',     'Shops with orphan locality_id',
    'status',   CASE WHEN v_n = 0 THEN 'ok' WHEN v_n < 5 THEN 'warn' ELSE 'fail' END,
    'expected', 0,
    'actual',   v_n,
    'message',  CASE WHEN v_n = 0 THEN 'clean' ELSE v_n::TEXT || ' shops point at deleted localities' END
  );

  -- ---- 5. Owners without any linked shop (>7 days old) ----
  -- FIXED in db/137: ownership lives in business_owners join table,
  -- NOT on a businesses.owner_user_id column.
  SELECT COUNT(*) INTO v_n
  FROM auth.users u
  WHERE NOT EXISTS (
      SELECT 1 FROM business_owners bo WHERE bo.auth_user_id = u.id
    )
    AND u.email IS NOT NULL
    AND u.created_at < NOW() - INTERVAL '7 days';
  v_checks := v_checks || jsonb_build_object(
    'category', 'Data Integrity',
    'name',     'Owners without any shop (>7 days old)',
    'status',   CASE WHEN v_n = 0 THEN 'ok' WHEN v_n < 20 THEN 'warn' ELSE 'fail' END,
    'expected', '< 5',
    'actual',   v_n,
    'message',  v_n::TEXT || ' accounts never created a listing'
  );

  -- ---- 6. Recent admin errors (last 24h) ----
  SELECT COUNT(*) INTO v_n FROM admin_errors WHERE created_at > NOW() - INTERVAL '24 hours';
  SELECT COUNT(*) INTO v_n2 FROM admin_errors WHERE created_at > NOW() - INTERVAL '24 hours' AND resolved = FALSE;
  v_checks := v_checks || jsonb_build_object(
    'category', 'Errors',
    'name',     'Client errors logged (last 24h)',
    'status',   CASE WHEN v_n2 = 0 THEN 'ok' WHEN v_n2 < 10 THEN 'warn' ELSE 'fail' END,
    'expected', 0,
    'actual',   v_n2,
    'message',  v_n::TEXT || ' total, ' || v_n2::TEXT || ' unresolved'
  );

  -- ---- 7. System stats (always 'ok', just for display) ----
  SELECT jsonb_build_object(
    'total_shops',         (SELECT COUNT(*) FROM businesses),
    'active_shops',        (SELECT COUNT(*) FROM businesses WHERE status = 'active'),
    'pending_shops',       (SELECT COUNT(*) FROM businesses WHERE status = 'pending'),
    'banned_shops',        (SELECT COUNT(*) FROM businesses WHERE status = 'banned'),
    'total_owners',        (SELECT COUNT(*) FROM auth.users WHERE email IS NOT NULL),
    'total_categories',    (SELECT COUNT(*) FROM categories),
    'total_cities',        (SELECT COUNT(*) FROM geo_cities),
    'total_localities',    (SELECT COUNT(*) FROM geo_localities),
    'shops_added_24h',     (SELECT COUNT(*) FROM businesses WHERE created_at > NOW() - INTERVAL '24 hours'),
    'shops_added_7d',      (SELECT COUNT(*) FROM businesses WHERE created_at > NOW() - INTERVAL '7 days'),
    'errors_last_24h',     (SELECT COUNT(*) FROM admin_errors WHERE created_at > NOW() - INTERVAL '24 hours'),
    'errors_unresolved',   (SELECT COUNT(*) FROM admin_errors WHERE resolved = FALSE)
  ) INTO v_stats;

  RETURN jsonb_build_object(
    'generated_at', NOW(),
    'stats',        v_stats,
    'checks',       v_checks
  );
END $$;

GRANT EXECUTE ON FUNCTION admin_health_check() TO authenticated;

NOTIFY pgrst, 'reload schema';

DO $$
BEGIN
  RAISE NOTICE '✓ db/137 — admin_health_check now uses business_owners join (not phantom column)';
END $$;

COMMIT;
