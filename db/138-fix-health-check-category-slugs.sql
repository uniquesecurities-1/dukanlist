-- ============================================================
-- db/138 — Fix admin_health_check: use real category slugs
-- ============================================================
-- BUG: db/136 (carried into db/137) hardcoded the slug 'food-restaurant'
--      in the v_critical_categories array. That slug does NOT exist —
--      the actual parent for restaurants/dhabas/cafes is 'food-beverage'
--      (per assets/data/categories.json).
--
-- Symptom in UI: Health Dashboard correctly reported "Parent category:
--      food-restaurant — MISSING — silent migration failure?" — but it
--      was a phantom check, not a real missing migration.
--
-- This migration updates the function to use the ACTUAL parent slugs.
-- Verified against the live categories.json v3.6 (15 parents):
--   healthcare, financial-services, insurance, home-services,
--   automotive, food-beverage, retail-shopping, construction-material,
--   beauty-wellness, education, professional-services, agri-business,
--   energy-solar, community-social, hospitality-travel
--
-- I'm keeping the check list to a focused set of 8 "must-have" parents
-- rather than all 15, because the health page is about *signal* not noise.
-- If any of these go missing, something is genuinely broken.
--
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
  -- FIXED in db/138: real slugs from categories.json v3.6
  v_critical_categories TEXT[] := ARRAY[
    'healthcare',
    'food-beverage',        -- was 'food-restaurant' (phantom)
    'retail-shopping',
    'home-services',
    'education',
    'professional-services',
    'hospitality-travel',   -- depends on db/134 having been run
    'automotive'
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
  -- Uses business_owners join table (fixed in db/137).
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
  RAISE NOTICE '✓ db/138 — admin_health_check uses real parent slugs from categories.json';
END $$;

COMMIT;
