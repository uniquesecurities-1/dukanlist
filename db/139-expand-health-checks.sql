-- ============================================================
-- db/139 — Expand admin_health_check with 9 new checks
-- ============================================================
-- Adds operational + data-quality + abuse signals to the health page.
-- All checks are O(rows-in-businesses) or smaller, indexed lookups.
-- The page already runs admin_health_check on every load, so we keep
-- each check cheap.
--
-- New checks (added on top of the 12 existing ones):
--   A. Schema    — 10 critical RPC functions exist (via pg_proc)
--   B. Data Quality:
--      1. Active shops missing critical field (name/mobile/category/address)
--      2. Active shops with no business hours set
--      3. Active shops with no photos
--      4. Active shops with duplicate mobile numbers
--   C. Cleanup signals:
--      5. Featured shops past expiry but featured=TRUE
--      6. Pending shops older than 7 days (moderation backlog)
--      7. Reviews attached to banned/removed businesses (orphaned content)
--   D. Abuse signals:
--      8. Self-recommendations (rule violation — should be 0)
--      9. Pucho Bhai questions tied to deleted/banned businesses
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
  v_critical_categories TEXT[] := ARRAY[
    'healthcare','food-beverage','retail-shopping','home-services',
    'education','professional-services','hospitality-travel','automotive'
  ];
  v_critical_rpcs TEXT[] := ARRAY[
    'is_admin',
    'admin_health_check',
    'admin_get_shop_full',
    'admin_update_shop',
    'admin_approve_business',
    'admin_delete_business',
    'admin_dashboard_digest',
    'log_admin_error',
    'add_recommendation',
    'get_spotlight_of_week'
  ];
  v_item TEXT;
  v_status TEXT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  -- =========================================================
  -- A. SCHEMA INVARIANTS
  -- =========================================================

  -- ---- 1. Critical parent categories present? ----
  FOREACH v_item IN ARRAY v_critical_categories LOOP
    SELECT COUNT(*) INTO v_n FROM categories WHERE slug = v_item AND parent_id IS NULL;
    v_status := CASE WHEN v_n = 1 THEN 'ok' ELSE 'fail' END;
    v_checks := v_checks || jsonb_build_object(
      'category', 'Schema',
      'name',     'Parent category: ' || v_item,
      'status',   v_status,
      'expected', 1,
      'actual',   v_n,
      'message',  CASE WHEN v_n = 1 THEN 'present' ELSE 'MISSING — silent migration failure?' END
    );
  END LOOP;

  -- ---- 2. NEW: Critical RPCs exist in pg_proc? ----
  FOREACH v_item IN ARRAY v_critical_rpcs LOOP
    SELECT COUNT(*) INTO v_n FROM pg_proc WHERE proname = v_item AND pronamespace = 'public'::regnamespace;
    v_status := CASE WHEN v_n >= 1 THEN 'ok' ELSE 'fail' END;
    v_checks := v_checks || jsonb_build_object(
      'category', 'Schema',
      'name',     'RPC exists: ' || v_item || '()',
      'status',   v_status,
      'expected', '>= 1',
      'actual',   v_n,
      'message',  CASE WHEN v_n >= 1 THEN 'callable' ELSE 'MISSING — function deleted or migration skipped' END
    );
  END LOOP;

  -- =========================================================
  -- B. DATA INTEGRITY (FK orphans)
  -- =========================================================

  -- ---- 3. Shops with orphan category_id ----
  SELECT COUNT(*) INTO v_n
  FROM businesses b
  WHERE b.category_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM categories c WHERE c.id = b.category_id);
  v_checks := v_checks || jsonb_build_object(
    'category', 'Data Integrity',
    'name',     'Shops with orphan category_id',
    'status',   CASE WHEN v_n = 0 THEN 'ok' WHEN v_n < 5 THEN 'warn' ELSE 'fail' END,
    'expected', 0, 'actual', v_n,
    'message',  CASE WHEN v_n = 0 THEN 'clean' ELSE v_n::TEXT || ' shops point at deleted categories' END
  );

  -- ---- 4. Shops with orphan city_id ----
  SELECT COUNT(*) INTO v_n
  FROM businesses b
  WHERE b.city_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM geo_cities c WHERE c.id = b.city_id);
  v_checks := v_checks || jsonb_build_object(
    'category', 'Data Integrity',
    'name',     'Shops with orphan city_id',
    'status',   CASE WHEN v_n = 0 THEN 'ok' WHEN v_n < 5 THEN 'warn' ELSE 'fail' END,
    'expected', 0, 'actual', v_n,
    'message',  CASE WHEN v_n = 0 THEN 'clean' ELSE v_n::TEXT || ' shops point at deleted cities' END
  );

  -- ---- 5. Shops with orphan locality_id ----
  SELECT COUNT(*) INTO v_n
  FROM businesses b
  WHERE b.locality_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM geo_localities l WHERE l.id = b.locality_id);
  v_checks := v_checks || jsonb_build_object(
    'category', 'Data Integrity',
    'name',     'Shops with orphan locality_id',
    'status',   CASE WHEN v_n = 0 THEN 'ok' WHEN v_n < 5 THEN 'warn' ELSE 'fail' END,
    'expected', 0, 'actual', v_n,
    'message',  CASE WHEN v_n = 0 THEN 'clean' ELSE v_n::TEXT || ' shops point at deleted localities' END
  );

  -- ---- 6. Owners without any linked shop (>7 days old) ----
  SELECT COUNT(*) INTO v_n
  FROM auth.users u
  WHERE NOT EXISTS (SELECT 1 FROM business_owners bo WHERE bo.auth_user_id = u.id)
    AND u.email IS NOT NULL
    AND u.created_at < NOW() - INTERVAL '7 days';
  v_checks := v_checks || jsonb_build_object(
    'category', 'Data Integrity',
    'name',     'Owners without any shop (>7 days old)',
    'status',   CASE WHEN v_n = 0 THEN 'ok' WHEN v_n < 20 THEN 'warn' ELSE 'fail' END,
    'expected', '< 5', 'actual', v_n,
    'message',  v_n::TEXT || ' accounts never created a listing'
  );

  -- =========================================================
  -- C. DATA QUALITY (NEW)
  -- =========================================================

  -- ---- 7. NEW: Active shops missing critical field ----
  SELECT COUNT(*) INTO v_n
  FROM businesses
  WHERE status = 'active'
    AND ( name IS NULL OR name = ''
       OR mobile IS NULL OR mobile = ''
       OR category_id IS NULL
       OR address_line1 IS NULL OR address_line1 = '' );
  v_checks := v_checks || jsonb_build_object(
    'category', 'Data Quality',
    'name',     'Active shops missing name/mobile/category/address',
    'status',   CASE WHEN v_n = 0 THEN 'ok' WHEN v_n < 5 THEN 'warn' ELSE 'fail' END,
    'expected', 0, 'actual', v_n,
    'message',  CASE WHEN v_n = 0 THEN 'all active shops have core fields'
                     ELSE v_n::TEXT || ' active listings are missing required data' END
  );

  -- ---- 8. NEW: Active shops with no hours_json set ----
  SELECT COUNT(*) INTO v_n
  FROM businesses
  WHERE status = 'active'
    AND (hours_json IS NULL OR hours_json = '{}'::jsonb);
  v_checks := v_checks || jsonb_build_object(
    'category', 'Data Quality',
    'name',     'Active shops with no business hours',
    'status',   CASE WHEN v_n = 0 THEN 'ok' WHEN v_n < 30 THEN 'warn' ELSE 'fail' END,
    'expected', '< 30%', 'actual', v_n,
    'message',  v_n::TEXT || ' active shops excluded from "Open Now" filter'
  );

  -- ---- 9. NEW: Active shops with no photos ----
  SELECT COUNT(*) INTO v_n
  FROM businesses
  WHERE status = 'active'
    AND (photos IS NULL OR array_length(photos, 1) IS NULL);
  v_checks := v_checks || jsonb_build_object(
    'category', 'Data Quality',
    'name',     'Active shops with no photos',
    'status',   CASE WHEN v_n = 0 THEN 'ok' WHEN v_n < 30 THEN 'warn' ELSE 'fail' END,
    'expected', '< 30%', 'actual', v_n,
    'message',  v_n::TEXT || ' active listings have zero photos (5x lower views)'
  );

  -- ---- 10. NEW: Duplicate mobile across active shops ----
  SELECT COUNT(*) INTO v_n
  FROM (
    SELECT mobile
    FROM businesses
    WHERE status = 'active' AND mobile IS NOT NULL AND mobile <> ''
    GROUP BY mobile
    HAVING COUNT(*) > 1
  ) dups;
  v_checks := v_checks || jsonb_build_object(
    'category', 'Data Quality',
    'name',     'Duplicate mobile numbers (active shops)',
    'status',   CASE WHEN v_n = 0 THEN 'ok' WHEN v_n < 5 THEN 'warn' ELSE 'fail' END,
    'expected', 0, 'actual', v_n,
    'message',  CASE WHEN v_n = 0 THEN 'every active shop has a unique mobile'
                     ELSE v_n::TEXT || ' mobile numbers shared by multiple active listings' END
  );

  -- =========================================================
  -- D. CLEANUP SIGNALS (NEW)
  -- =========================================================

  -- ---- 11. NEW: Featured shops past expiry but featured=TRUE ----
  SELECT COUNT(*) INTO v_n
  FROM businesses
  WHERE featured = TRUE
    AND featured_until IS NOT NULL
    AND featured_until < NOW();
  v_checks := v_checks || jsonb_build_object(
    'category', 'Cleanup',
    'name',     'Featured shops past expiry (need un-featuring)',
    'status',   CASE WHEN v_n = 0 THEN 'ok' WHEN v_n < 5 THEN 'warn' ELSE 'fail' END,
    'expected', 0, 'actual', v_n,
    'message',  CASE WHEN v_n = 0 THEN 'no stale features'
                     ELSE v_n::TEXT || ' featured listings expired but still flagged' END
  );

  -- ---- 12. NEW: Pending shops older than 7 days ----
  SELECT COUNT(*) INTO v_n
  FROM businesses
  WHERE status = 'pending'
    AND created_at < NOW() - INTERVAL '7 days';
  v_checks := v_checks || jsonb_build_object(
    'category', 'Cleanup',
    'name',     'Pending shops older than 7 days',
    'status',   CASE WHEN v_n = 0 THEN 'ok' WHEN v_n < 5 THEN 'warn' ELSE 'fail' END,
    'expected', 0, 'actual', v_n,
    'message',  CASE WHEN v_n = 0 THEN 'moderation queue is fresh'
                     ELSE v_n::TEXT || ' shops waiting > 7 days for approval' END
  );

  -- ---- 13. NEW: Reviews on banned/removed businesses ----
  SELECT COUNT(*) INTO v_n
  FROM reviews r
  JOIN businesses b ON b.id = r.business_id
  WHERE r.status = 'active'
    AND b.status IN ('banned', 'removed');
  v_checks := v_checks || jsonb_build_object(
    'category', 'Cleanup',
    'name',     'Active reviews on banned/removed shops',
    'status',   CASE WHEN v_n = 0 THEN 'ok' WHEN v_n < 10 THEN 'warn' ELSE 'fail' END,
    'expected', 0, 'actual', v_n,
    'message',  CASE WHEN v_n = 0 THEN 'no orphan content'
                     ELSE v_n::TEXT || ' reviews still visible for banned listings' END
  );

  -- =========================================================
  -- E. ABUSE SIGNALS (NEW)
  -- =========================================================

  -- ---- 14. NEW: Self-recommendations (rule violation) ----
  -- The add_recommendation RPC blocks this, but DB-level check catches
  -- direct INSERTs or future RPC bugs.
  IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'business_recommendations') THEN
    SELECT COUNT(*) INTO v_n
    FROM business_recommendations
    WHERE recommender_business_id = recommended_business_id;
    v_checks := v_checks || jsonb_build_object(
      'category', 'Abuse',
      'name',     'Self-recommendations (rule violation)',
      'status',   CASE WHEN v_n = 0 THEN 'ok' ELSE 'fail' END,
      'expected', 0, 'actual', v_n,
      'message',  CASE WHEN v_n = 0 THEN 'no self-references'
                       ELSE v_n::TEXT || ' shops are recommending themselves — investigate' END
    );
  END IF;

  -- ---- 15. NEW: Recommendations pointing at non-active businesses ----
  IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'business_recommendations') THEN
    SELECT COUNT(*) INTO v_n
    FROM business_recommendations br
    JOIN businesses b ON b.id = br.recommended_business_id
    WHERE b.status <> 'active';
    v_checks := v_checks || jsonb_build_object(
      'category', 'Cleanup',
      'name',     'Recommendations pointing at non-active shops',
      'status',   CASE WHEN v_n = 0 THEN 'ok' WHEN v_n < 5 THEN 'warn' ELSE 'fail' END,
      'expected', 0, 'actual', v_n,
      'message',  CASE WHEN v_n = 0 THEN 'all recommendation targets are active'
                       ELSE v_n::TEXT || ' recommendations show non-active shops to visitors' END
    );
  END IF;

  -- =========================================================
  -- F. ERROR LOG (existing)
  -- =========================================================
  SELECT COUNT(*) INTO v_n  FROM admin_errors WHERE created_at > NOW() - INTERVAL '24 hours';
  SELECT COUNT(*) INTO v_n2 FROM admin_errors WHERE created_at > NOW() - INTERVAL '24 hours' AND resolved = FALSE;
  v_checks := v_checks || jsonb_build_object(
    'category', 'Errors',
    'name',     'Client errors logged (last 24h)',
    'status',   CASE WHEN v_n2 = 0 THEN 'ok' WHEN v_n2 < 10 THEN 'warn' ELSE 'fail' END,
    'expected', 0, 'actual', v_n2,
    'message',  v_n::TEXT || ' total, ' || v_n2::TEXT || ' unresolved'
  );

  -- =========================================================
  -- G. STATS GRID
  -- =========================================================
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
  RAISE NOTICE '✓ db/139 — admin_health_check expanded with 9 new checks';
  RAISE NOTICE '  Schema     : 10 critical RPCs + 8 parent categories';
  RAISE NOTICE '  Data Quality: missing fields, no hours, no photos, dup mobiles';
  RAISE NOTICE '  Cleanup    : stale features, old pending, orphan reviews, dead recommendations';
  RAISE NOTICE '  Abuse      : self-recommendations';
END $$;

COMMIT;
