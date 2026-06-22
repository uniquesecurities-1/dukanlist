-- ============================================================
-- db/179 — Health check coverage for ALL new features (db/166–178)
-- ============================================================
-- USER QUESTION:
--   "kya health settings me bhi update karna hoga kyunki ho sakta
--    hai ki wo poorane setup ke hisab se health check kar raha ho"
--
--   = Yes — health check was running on the OLD set of RPCs only.
--     We've added ~18 new RPCs (Golden Pages, owner invites,
--     mobile verification, self-add, flags) which weren't being
--     monitored. This migration brings them under the umbrella.
--
-- ADDS:
--   1. v_critical_rpcs extended with 18 new function names
--   2. New data integrity checks for soft-listed flow:
--      - soft_listed shops without claim_token
--      - mobile_verified=TRUE with invalid mobile (corruption)
--      - open flags count
--      - stale invites (sent > 7d ago, never claimed)
--      - account-less DukanList listings count (informational)
--   3. New stats block — soft_listed count, open flags, verified phones, etc.
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
  -- All RPCs that admin pages or public pages depend on. Anything missing
  -- here means a migration was skipped or someone dropped a function.
  v_critical_rpcs TEXT[] := ARRAY[
    -- Pre-existing core
    'is_admin',
    'admin_health_check',
    'admin_get_shop_full',
    'admin_update_shop',
    'admin_approve_business',
    'admin_delete_business',
    'admin_dashboard_digest',
    'log_admin_error',
    'add_recommendation',
    'get_spotlight_of_week',
    -- Golden Pages public
    'gp_list_shops',
    'gp_categories_with_counts',
    'gp_stats',
    'gp_help_reach',
    'gp_flag_listing',
    'public_gp_self_add',
    -- Golden Pages admin
    'admin_soft_add_shop',
    'admin_soft_bulk_add',
    'admin_gp_list_all',
    'admin_gp_update_soft',
    'admin_gp_delete_soft',
    'admin_gp_promote_to_full',
    'admin_gp_review_flags',
    'admin_gp_resolve_flag',
    -- Owner invite + mobile verification + claim flow
    'admin_log_email_invite',
    'admin_unclaimed_list',
    'admin_set_mobile_verified',
    'claim_register_owner'
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

  -- 1. Critical parent categories present?
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

  -- 2. Critical RPCs exist in pg_proc?
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

  -- 3. Required new tables present?
  FOR v_item IN SELECT unnest(ARRAY['gp_help_reach_log','owner_invite_log','gp_self_add_log','gp_flags']) LOOP
    SELECT COUNT(*) INTO v_n FROM pg_tables WHERE schemaname = 'public' AND tablename = v_item;
    v_status := CASE WHEN v_n = 1 THEN 'ok' ELSE 'fail' END;
    v_checks := v_checks || jsonb_build_object(
      'category', 'Schema',
      'name',     'Table exists: ' || v_item,
      'status',   v_status,
      'expected', 1,
      'actual',   v_n,
      'message',  CASE WHEN v_n = 1 THEN 'present' ELSE 'MISSING — db/175 or db/176 not run' END
    );
  END LOOP;

  -- 4. status='soft_listed' allowed by CHECK constraint?
  SELECT COUNT(*) INTO v_n
    FROM information_schema.check_constraints
   WHERE check_clause ILIKE '%soft_listed%';
  v_checks := v_checks || jsonb_build_object(
    'category', 'Schema',
    'name',     'CHECK constraint allows soft_listed',
    'status',   CASE WHEN v_n >= 1 THEN 'ok' ELSE 'fail' END,
    'expected', '>= 1',
    'actual',   v_n,
    'message',  CASE WHEN v_n >= 1 THEN 'extended (db/166)' ELSE 'MISSING — db/166 not run' END
  );


  -- =========================================================
  -- B. DATA INTEGRITY (FK + invariants)
  -- =========================================================

  -- 5. Shops with orphan category_id
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

  -- 6. Shops with orphan city_id
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

  -- 7. Soft-listed shops MUST have a claim_token (drives WhatsApp claim flow)
  SELECT COUNT(*) INTO v_n
    FROM businesses
   WHERE status = 'soft_listed'
     AND (claim_token IS NULL OR LENGTH(TRIM(claim_token)) = 0);
  v_checks := v_checks || jsonb_build_object(
    'category', 'Data Integrity',
    'name',     'Soft-listed shops missing claim_token',
    'status',   CASE WHEN v_n = 0 THEN 'ok' ELSE 'fail' END,
    'expected', 0,
    'actual',   v_n,
    'message',  CASE WHEN v_n = 0 THEN 'all soft listings have a claim link'
                     ELSE v_n::TEXT || ' soft listings cannot be claimed via WhatsApp' END
  );

  -- 8. mobile_verified=TRUE but mobile invalid (corruption)
  SELECT COUNT(*) INTO v_n
    FROM businesses
   WHERE COALESCE(verified_mobile, FALSE) = TRUE
     AND (mobile IS NULL OR LENGTH(mobile) <> 10);
  v_checks := v_checks || jsonb_build_object(
    'category', 'Data Integrity',
    'name',     'Verified mobile with invalid number',
    'status',   CASE WHEN v_n = 0 THEN 'ok' ELSE 'fail' END,
    'expected', 0,
    'actual',   v_n,
    'message',  CASE WHEN v_n = 0 THEN 'clean'
                     ELSE v_n::TEXT || ' rows flagged verified but mobile is bad — fix or unverify' END
  );

  -- 9. Active DukanList listings with no business_owners row.
  --    Informational — these are admin bulk-published, NOT a bug.
  SELECT COUNT(*) INTO v_n
    FROM businesses b
   WHERE b.status = 'active'
     AND NOT EXISTS (SELECT 1 FROM business_owners bo WHERE bo.business_id = b.id);
  v_checks := v_checks || jsonb_build_object(
    'category', 'Account-less DukanList',
    'name',     'Active listings without linked owner account',
    'status',   'ok',                              -- always OK (intentional)
    'expected', 'N',
    'actual',   v_n,
    'message',  v_n::TEXT || ' active listings waiting for owner email invite'
  );

  -- 10. Open flags awaiting admin review
  IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'gp_flags' AND schemaname = 'public') THEN
    SELECT COUNT(*) INTO v_n FROM gp_flags WHERE status = 'open';
    v_checks := v_checks || jsonb_build_object(
      'category', 'Moderation',
      'name',     'Open flag reports (Golden Pages)',
      'status',   CASE WHEN v_n = 0 THEN 'ok'
                       WHEN v_n < 5 THEN 'warn'
                       ELSE 'fail' END,
      'expected', 0,
      'actual',   v_n,
      'message',  CASE WHEN v_n = 0 THEN 'no flags pending'
                       ELSE v_n::TEXT || ' flags awaiting review — open /admin/owner-invites (or build /admin/gp-flags)' END
    );
  END IF;

  -- 11. Stale invites — sent > 7 days ago, owner never claimed
  IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'owner_invite_log' AND schemaname = 'public') THEN
    SELECT COUNT(*) INTO v_n
      FROM owner_invite_log l
      JOIN businesses b ON b.id = l.business_id
     WHERE l.sent_at < NOW() - INTERVAL '7 days'
       AND NOT EXISTS (SELECT 1 FROM business_owners bo WHERE bo.business_id = b.id);
    v_checks := v_checks || jsonb_build_object(
      'category', 'Owner Invites',
      'name',     'Stale invites (>7d, never claimed)',
      'status',   CASE WHEN v_n = 0 THEN 'ok' WHEN v_n < 10 THEN 'warn' ELSE 'fail' END,
      'expected', 0,
      'actual',   v_n,
      'message',  CASE WHEN v_n = 0 THEN 'all recent invites claimed or fresh'
                       ELSE v_n::TEXT || ' invites unanswered — consider resending or following up' END
    );
  END IF;

  -- 12. Self-add abuse — same IP hashed identifier > 10 in last 24h
  IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'gp_self_add_log' AND schemaname = 'public') THEN
    SELECT COUNT(DISTINCT ip_hash) INTO v_n
      FROM gp_self_add_log
     WHERE created_at > NOW() - INTERVAL '24 hours'
     GROUP BY ip_hash
    HAVING COUNT(*) > 10
     LIMIT 1;
    v_n := COALESCE(v_n, 0);
    v_checks := v_checks || jsonb_build_object(
      'category', 'Abuse Watch',
      'name',     'Self-add bursts (>10 from one source in 24h)',
      'status',   CASE WHEN v_n = 0 THEN 'ok' ELSE 'warn' END,
      'expected', 0,
      'actual',   v_n,
      'message',  CASE WHEN v_n = 0 THEN 'no burst patterns detected'
                       ELSE v_n::TEXT || ' source(s) exceeded the per-hour limit — review gp_self_add_log' END
    );
  END IF;

  -- =========================================================
  -- C. PRE-EXISTING DATA QUALITY CHECKS (kept from db/139)
  -- =========================================================

  -- 13. Active shops with no business hours (informational)
  SELECT COUNT(*) INTO v_n
    FROM businesses
   WHERE status = 'active'
     AND (hours_json IS NULL OR hours_json::text = '{}' OR hours_json::text = 'null');
  v_checks := v_checks || jsonb_build_object(
    'category', 'Data Quality',
    'name',     'Active shops with no business hours',
    'status',   CASE WHEN v_n = 0 THEN 'ok' WHEN v_n < 20 THEN 'warn' ELSE 'fail' END,
    'expected', '< 10',
    'actual',   v_n,
    'message',  v_n::TEXT || ' active shops missing hours — Open Now filter excludes them'
  );

  -- 14. Active shops with no photos
  SELECT COUNT(*) INTO v_n
    FROM businesses
   WHERE status = 'active'
     AND (photos IS NULL OR array_length(photos, 1) IS NULL);
  v_checks := v_checks || jsonb_build_object(
    'category', 'Data Quality',
    'name',     'Active shops with no photos',
    'status',   CASE WHEN v_n = 0 THEN 'ok' WHEN v_n < 50 THEN 'warn' ELSE 'fail' END,
    'expected', '< 30',
    'actual',   v_n,
    'message',  v_n::TEXT || ' active listings have zero photos (lower discovery)'
  );

  -- 15. Pending shops older than 7 days
  SELECT COUNT(*) INTO v_n
    FROM businesses
   WHERE status = 'pending'
     AND created_at < NOW() - INTERVAL '7 days';
  v_checks := v_checks || jsonb_build_object(
    'category', 'Cleanup',
    'name',     'Pending shops older than 7 days',
    'status',   CASE WHEN v_n = 0 THEN 'ok' WHEN v_n < 5 THEN 'warn' ELSE 'warn' END,
    'expected', 0,
    'actual',   v_n,
    'message',  v_n::TEXT || ' shops waiting > 7 days for approval'
  );

  -- 16. Client errors (last 24h)
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


  -- =========================================================
  -- D. STATS BLOCK
  -- =========================================================
  SELECT jsonb_build_object(
    'total_shops',          (SELECT COUNT(*) FROM businesses),
    'active_shops',         (SELECT COUNT(*) FROM businesses WHERE status = 'active'),
    'pending_shops',        (SELECT COUNT(*) FROM businesses WHERE status = 'pending'),
    'soft_listed_shops',    (SELECT COUNT(*) FROM businesses WHERE status = 'soft_listed'),
    'banned_shops',         (SELECT COUNT(*) FROM businesses WHERE status = 'banned'),
    'total_owners',         (SELECT COUNT(*) FROM auth.users WHERE email IS NOT NULL),
    'verified_mobiles',     (SELECT COUNT(*) FROM businesses WHERE COALESCE(verified_mobile, FALSE) = TRUE),
    'accountless_active',   (SELECT COUNT(*) FROM businesses b
                              WHERE b.status = 'active'
                                AND NOT EXISTS (SELECT 1 FROM business_owners bo WHERE bo.business_id = b.id)),
    'open_flags',           (SELECT COUNT(*) FROM gp_flags WHERE status = 'open'),
    'invites_24h',          (SELECT COUNT(*) FROM owner_invite_log WHERE sent_at > NOW() - INTERVAL '24 hours'),
    'self_adds_24h',        (SELECT COUNT(*) FROM gp_self_add_log WHERE created_at > NOW() - INTERVAL '24 hours'),
    'total_categories',     (SELECT COUNT(*) FROM categories),
    'total_cities',         (SELECT COUNT(*) FROM geo_cities),
    'total_localities',     (SELECT COUNT(*) FROM geo_localities),
    'shops_added_24h',      (SELECT COUNT(*) FROM businesses WHERE created_at > NOW() - INTERVAL '24 hours'),
    'shops_added_7d',       (SELECT COUNT(*) FROM businesses WHERE created_at > NOW() - INTERVAL '7 days'),
    'errors_last_24h',      (SELECT COUNT(*) FROM admin_errors WHERE created_at > NOW() - INTERVAL '24 hours'),
    'errors_unresolved',    (SELECT COUNT(*) FROM admin_errors WHERE resolved = FALSE)
  ) INTO v_stats;

  RETURN jsonb_build_object(
    'generated_at', NOW(),
    'stats',        v_stats,
    'checks',       v_checks
  );
END $$;

GRANT EXECUTE ON FUNCTION admin_health_check() TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/179 installed. Health check now covers 28 critical RPCs + 4 new tables + 6 new integrity checks.';
END $$;
