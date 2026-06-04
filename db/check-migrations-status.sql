-- =====================================================
-- check-migrations-status.sql
-- =====================================================
-- USE: Paste in Supabase SQL Editor and RUN.
-- Returns a clear table showing which recent migrations are
-- applied vs pending.
--
-- Read the 'status' column:
--   ✅ APPLIED  — migration ran successfully
--   ❌ PENDING  — file exists locally but not run in Supabase yet
--
-- This is READ-ONLY. Safe to run anytime.
-- =====================================================

WITH checks AS (
  -- ─────────────────────────────────────────────────────────
  -- db/96 — Energy/Solar categories
  -- ─────────────────────────────────────────────────────────
  SELECT
    'db/96-add-energy-solar-renewable-categories.sql' AS migration,
    'Adds Energy/Solar parent + 15 sub-categories'      AS what,
    CASE WHEN EXISTS (
      SELECT 1 FROM categories WHERE slug = 'energy-solar'
    ) THEN '✅ APPLIED' ELSE '❌ PENDING' END             AS status

  UNION ALL

  -- ─────────────────────────────────────────────────────────
  -- db/97 — Monitoring error logs
  -- ─────────────────────────────────────────────────────────
  SELECT
    'db/97-monitoring-error-logs.sql',
    'error_logs table + log_client_error + admin_get_recent_errors',
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_proc WHERE proname = 'log_client_error'
    ) AND EXISTS (
      SELECT 1 FROM pg_proc WHERE proname = 'admin_get_recent_errors'
    ) AND EXISTS (
      SELECT 1 FROM information_schema.tables WHERE table_name = 'error_logs'
    ) THEN '✅ APPLIED' ELSE '❌ PENDING' END

  UNION ALL

  -- ─────────────────────────────────────────────────────────
  -- db/98 — Review spam filter
  -- ─────────────────────────────────────────────────────────
  SELECT
    'db/98-review-spam-filter.sql',
    'check_review_content + reviews_spam_filter trigger + applies_to column',
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_proc WHERE proname = 'check_review_content'
    ) AND EXISTS (
      SELECT 1 FROM pg_trigger WHERE tgname = 'reviews_spam_filter'
    ) AND EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_name = 'blocked_keywords' AND column_name = 'applies_to'
    ) THEN '✅ APPLIED' ELSE '❌ PENDING' END

  UNION ALL

  -- ─────────────────────────────────────────────────────────
  -- db/99 — Duplicate shop detection
  -- ─────────────────────────────────────────────────────────
  SELECT
    'db/99-duplicate-shop-detection.sql',
    'admin_find_duplicate_shops + duplicate_allowlist + norm_mobile_10',
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_proc WHERE proname = 'admin_find_duplicate_shops'
    ) AND EXISTS (
      SELECT 1 FROM information_schema.tables WHERE table_name = 'duplicate_allowlist'
    ) AND EXISTS (
      SELECT 1 FROM pg_proc WHERE proname = 'norm_mobile_10'
    ) THEN '✅ APPLIED' ELSE '❌ PENDING' END

  UNION ALL

  -- ─────────────────────────────────────────────────────────
  -- db/100 — Phase 2 bugfixes (atomic photo + dup mobile + review velocity)
  -- ─────────────────────────────────────────────────────────
  SELECT
    'db/100-phase2-bugfixes.sql',
    'owner_append_shop_photo + prevent_dup_active_mobile + limit_review_velocity',
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_proc WHERE proname = 'owner_append_shop_photo'
    ) AND EXISTS (
      SELECT 1 FROM pg_trigger WHERE tgname = 'prevent_dup_active_mobile'
    ) AND EXISTS (
      SELECT 1 FROM pg_trigger WHERE tgname = 'limit_review_velocity_trg'
    ) THEN '✅ APPLIED' ELSE '❌ PENDING' END

  UNION ALL

  -- ─────────────────────────────────────────────────────────
  -- db/101 — Suspicious shops photos_count fix
  -- ─────────────────────────────────────────────────────────
  SELECT
    'db/101-hotfix-suspicious-photos-count.sql',
    'admin_get_suspicious_shops fixed (uses array_length not photos_count)',
    -- Test by calling the function — if it works without error, applied.
    -- We check function source contains the fix marker.
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_proc p
       WHERE p.proname = 'admin_get_suspicious_shops'
         AND pg_get_functiondef(p.oid) LIKE '%array_length(b.photos%'
    ) THEN '✅ APPLIED' ELSE '❌ PENDING' END

  UNION ALL

  -- ─────────────────────────────────────────────────────────
  -- db/102 — bo.added_at hotfix
  -- ─────────────────────────────────────────────────────────
  SELECT
    'db/102-hotfix-bo-added-at.sql',
    'admin_audit_business_owners uses bo.added_at correctly',
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_proc p
       WHERE p.proname = 'admin_audit_business_owners'
         AND pg_get_functiondef(p.oid) LIKE '%bo.added_at%'
    ) THEN '✅ APPLIED' ELSE '❌ PENDING (optional — low priority)' END

  UNION ALL

  -- ─────────────────────────────────────────────────────────
  -- db/103 — Mobile login status RPC
  -- ─────────────────────────────────────────────────────────
  SELECT
    'db/103-mobile-login-status.sql',
    'lookup_login_mobile_status RPC for better login error messages',
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_proc WHERE proname = 'lookup_login_mobile_status'
    ) THEN '✅ APPLIED' ELSE '❌ PENDING' END
)
SELECT
  status,
  migration,
  what
FROM checks
ORDER BY
  -- pending first so they're easy to spot
  CASE WHEN status LIKE '❌%' THEN 0 ELSE 1 END,
  migration;
