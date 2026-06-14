-- ============================================================
-- db/136 — Admin Health Monitoring Infrastructure
-- ============================================================
-- Three pieces for "admin 10X super strong":
--
--   1. admin_errors            — table storing every captured client error
--   2. log_admin_error(...)    — RPC that admin pages call from window.onerror
--   3. admin_health_check()    — RPC returning DB invariants + counts
--
-- Why this is needed:
--   * db/125 silently failed for ~1 year (hospitality categories) — no one
--     knew because nothing surfaced it.
--   * db/129 had an array-cast bug surfaced today (db/135 fixes it) — every
--     save returned 400 but the dual-path fallback hid it.
--   * Without auto-capture, console errors only exist until the tab closes.
--
-- This migration is purely additive. DB never disturbed.
-- ============================================================

BEGIN;

-- =========================================================
-- 1. admin_errors table — every client error gets stored here
-- =========================================================
CREATE TABLE IF NOT EXISTS admin_errors (
  id              BIGSERIAL PRIMARY KEY,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  user_id         UUID,                                -- auth.uid() if available
  user_email      TEXT,
  page            TEXT,                                -- e.g. '/admin/shop'
  error_type      TEXT,                                -- 'js' | 'promise' | 'rpc' | 'fetch'
  error_message   TEXT,
  error_stack     TEXT,
  url             TEXT,                                -- full window.location.href
  user_agent      TEXT,
  payload         JSONB,                               -- any extra context
  resolved        BOOLEAN NOT NULL DEFAULT FALSE,
  resolved_at     TIMESTAMPTZ,
  resolved_by     UUID
);

CREATE INDEX IF NOT EXISTS idx_admin_errors_created   ON admin_errors(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_errors_unresolved ON admin_errors(resolved, created_at DESC) WHERE resolved = FALSE;
CREATE INDEX IF NOT EXISTS idx_admin_errors_page      ON admin_errors(page, created_at DESC);

-- RLS — only admins can read, anyone authenticated can insert (so capture works)
ALTER TABLE admin_errors ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_errors_select_admin ON admin_errors;
CREATE POLICY admin_errors_select_admin ON admin_errors
  FOR SELECT
  USING (is_admin());

DROP POLICY IF EXISTS admin_errors_insert_any_auth ON admin_errors;
CREATE POLICY admin_errors_insert_any_auth ON admin_errors
  FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS admin_errors_update_admin ON admin_errors;
CREATE POLICY admin_errors_update_admin ON admin_errors
  FOR UPDATE
  USING (is_admin())
  WITH CHECK (is_admin());

-- Auto-prune old resolved errors > 30 days (keep DB small)
-- This runs lazily on each insert; cheap enough.
CREATE OR REPLACE FUNCTION admin_errors_autoprune()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- Sample 1 in 50 inserts to avoid hot path
  IF (random() < 0.02) THEN
    DELETE FROM admin_errors
     WHERE resolved = TRUE
       AND resolved_at < NOW() - INTERVAL '30 days';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_admin_errors_autoprune ON admin_errors;
CREATE TRIGGER trg_admin_errors_autoprune
  AFTER INSERT ON admin_errors
  FOR EACH ROW EXECUTE FUNCTION admin_errors_autoprune();


-- =========================================================
-- 2. log_admin_error RPC — called from window.onerror
-- =========================================================
-- Any authenticated user (admin or owner) can call this. We always capture
-- because errors in the owner panel are just as useful for debugging.
-- =========================================================
CREATE OR REPLACE FUNCTION log_admin_error(
  p_page          TEXT,
  p_error_type    TEXT,
  p_error_message TEXT,
  p_error_stack   TEXT DEFAULT NULL,
  p_url           TEXT DEFAULT NULL,
  p_user_agent    TEXT DEFAULT NULL,
  p_payload       JSONB DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    UUID;
  v_email  TEXT;
  v_id     BIGINT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    -- Anonymous errors not stored. (Avoids public spam.)
    RETURN NULL;
  END IF;

  -- Fetch email for easier debugging
  SELECT email INTO v_email FROM auth.users WHERE id = v_uid;

  INSERT INTO admin_errors (
    user_id, user_email, page, error_type, error_message, error_stack,
    url, user_agent, payload
  )
  VALUES (
    v_uid, v_email, p_page, p_error_type,
    LEFT(p_error_message, 4000),    -- cap to prevent giant strings
    LEFT(p_error_stack,   8000),
    p_url, p_user_agent, p_payload
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END $$;

GRANT EXECUTE ON FUNCTION log_admin_error(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,JSONB) TO authenticated;


-- =========================================================
-- 3. admin_health_check RPC — DB invariants + system stats
-- =========================================================
-- Returns a JSON object the health dashboard can render. Each check has
-- name, status ('ok' | 'warn' | 'fail'), expected, actual, message.
--
-- Categories of checks:
--   * Schema invariants (key parents exist, RPCs exist)
--   * Orphan data (shops pointing at deleted categories/cities)
--   * Recent activity (counts last 24h / 7d / 30d)
--   * Error rate (recent admin_errors rows)
-- =========================================================
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

  -- ---- 5. Owners without any linked shop ----
  SELECT COUNT(*) INTO v_n
  FROM auth.users u
  WHERE NOT EXISTS (SELECT 1 FROM businesses b WHERE b.owner_user_id = u.id)
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


-- =========================================================
-- 4. admin_recent_errors RPC — pagination + filter helper
-- =========================================================
CREATE OR REPLACE FUNCTION admin_recent_errors(
  p_limit         INT     DEFAULT 50,
  p_only_unresolved BOOLEAN DEFAULT TRUE,
  p_page_filter   TEXT    DEFAULT NULL    -- e.g. '/admin/shop' or NULL for all
)
RETURNS SETOF admin_errors
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  RETURN QUERY
    SELECT * FROM admin_errors
     WHERE (NOT p_only_unresolved OR resolved = FALSE)
       AND (p_page_filter IS NULL OR page LIKE p_page_filter || '%')
     ORDER BY created_at DESC
     LIMIT GREATEST(1, LEAST(p_limit, 500));
END $$;

GRANT EXECUTE ON FUNCTION admin_recent_errors(INT,BOOLEAN,TEXT) TO authenticated;


-- =========================================================
-- 5. admin_resolve_error RPC — mark error as fixed
-- =========================================================
CREATE OR REPLACE FUNCTION admin_resolve_error(p_error_id BIGINT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  UPDATE admin_errors
     SET resolved = TRUE,
         resolved_at = NOW(),
         resolved_by = auth.uid()
   WHERE id = p_error_id;
  RETURN FOUND;
END $$;

GRANT EXECUTE ON FUNCTION admin_resolve_error(BIGINT) TO authenticated;

NOTIFY pgrst, 'reload schema';

DO $$
BEGIN
  RAISE NOTICE '✓ db/136 — admin health monitoring infrastructure installed';
  RAISE NOTICE '  • admin_errors table created';
  RAISE NOTICE '  • log_admin_error / admin_health_check / admin_recent_errors / admin_resolve_error RPCs ready';
END $$;

COMMIT;
