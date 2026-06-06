-- =====================================================
-- db/97-monitoring-error-logs.sql
-- =====================================================
-- USER REQUEST (2026-06-04):
--   "Monitoring + alerting set up karo — Sentry / UptimeRobot /
--    Supabase Logs / Vercel Analytics"
--
-- THIS PATCH builds the SELF-HOSTED ERROR CAPTURE layer (zero
-- third-party dependency, zero cost). Stores every uncaught
-- JS error / failed fetch / unhandled promise rejection from
-- ANY page on the site for admin visibility.
--
-- DESIGN:
--   * Table:        public.error_logs
--   * Public RPC:   log_client_error()  - called from /api/log-error
--                   SECURITY DEFINER, rate-limited per ip_hash
--   * Admin RPCs:   admin_get_recent_errors(), admin_clear_error_logs()
--   * Indexed for:  recent errors (created_at DESC),
--                   grouping by url/source
--   * Auto-prune:   keep only last 30 days (background job optional)
--
-- BACKWARDS COMPATIBLE — purely additive.
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. error_logs table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.error_logs (
  id            BIGSERIAL PRIMARY KEY,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  source        TEXT NOT NULL DEFAULT 'js',     -- 'js' | 'fetch' | 'promise' | 'server'
  severity      TEXT NOT NULL DEFAULT 'error',  -- 'error' | 'warn' | 'info'
  page_url      TEXT,
  error_msg     TEXT NOT NULL,
  error_stack   TEXT,
  user_agent    TEXT,
  ip_hash       TEXT,                            -- SHA-256 truncated, no PII
  session_id    TEXT,                            -- client-side random id (no PII)
  user_id       UUID,                            -- auth.users.id if logged in
  meta          JSONB
);

-- Constrain enum-like columns
DO $$
BEGIN
  ALTER TABLE public.error_logs
    ADD CONSTRAINT error_logs_source_chk
    CHECK (source IN ('js', 'fetch', 'promise', 'server', 'unknown'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$
BEGIN
  ALTER TABLE public.error_logs
    ADD CONSTRAINT error_logs_severity_chk
    CHECK (severity IN ('error', 'warn', 'info', 'critical'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Indexes
CREATE INDEX IF NOT EXISTS error_logs_created_idx
  ON public.error_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS error_logs_severity_idx
  ON public.error_logs (severity, created_at DESC);
CREATE INDEX IF NOT EXISTS error_logs_ip_idx
  ON public.error_logs (ip_hash, created_at DESC);

-- RLS — disable for this table (only RPC writes, admin reads via RPC)
ALTER TABLE public.error_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "error_logs no direct access" ON public.error_logs;
CREATE POLICY "error_logs no direct access" ON public.error_logs
  FOR ALL TO authenticated, anon USING (FALSE) WITH CHECK (FALSE);


-- ============================================================
-- 2. log_client_error RPC — called from /api/log-error
--    Rate-limited per ip_hash: max 30 errors/minute, 200/hour
-- ============================================================
DROP FUNCTION IF EXISTS log_client_error(JSONB);
CREATE OR REPLACE FUNCTION log_client_error(p_data JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ip_hash      TEXT := COALESCE(p_data->>'ip_hash', 'unknown');
  v_recent_min   INT;
  v_recent_hour  INT;
  v_msg          TEXT := COALESCE(p_data->>'error_msg', 'unknown error');
  v_stack        TEXT := p_data->>'error_stack';
  v_url          TEXT := p_data->>'page_url';
  v_ua           TEXT := p_data->>'user_agent';
  v_source       TEXT := COALESCE(p_data->>'source', 'js');
  v_severity     TEXT := COALESCE(p_data->>'severity', 'error');
  v_session      TEXT := p_data->>'session_id';
  v_user_id      UUID;
BEGIN
  -- Cap message + stack length to prevent abuse
  v_msg := LEFT(v_msg, 1000);
  v_stack := LEFT(COALESCE(v_stack, ''), 4000);
  v_url := LEFT(COALESCE(v_url, ''), 500);
  v_ua := LEFT(COALESCE(v_ua, ''), 500);

  -- Validate source/severity
  IF v_source NOT IN ('js', 'fetch', 'promise', 'server', 'unknown') THEN
    v_source := 'unknown';
  END IF;
  IF v_severity NOT IN ('error', 'warn', 'info', 'critical') THEN
    v_severity := 'error';
  END IF;

  -- Rate limit: max 30/min, 200/hour per ip_hash
  IF v_ip_hash != 'unknown' THEN
    SELECT COUNT(*) INTO v_recent_min
      FROM error_logs
     WHERE ip_hash = v_ip_hash
       AND created_at >= NOW() - INTERVAL '1 minute';
    IF v_recent_min >= 30 THEN RETURN; END IF;

    SELECT COUNT(*) INTO v_recent_hour
      FROM error_logs
     WHERE ip_hash = v_ip_hash
       AND created_at >= NOW() - INTERVAL '1 hour';
    IF v_recent_hour >= 200 THEN RETURN; END IF;
  END IF;

  -- Optional logged-in user (passed by API after JWT decode)
  BEGIN
    v_user_id := (p_data->>'user_id')::UUID;
  EXCEPTION WHEN OTHERS THEN
    v_user_id := NULL;
  END;

  -- De-dup: same exact msg + url + ip in last 5 minutes → skip
  IF EXISTS (
    SELECT 1 FROM error_logs
     WHERE ip_hash = v_ip_hash
       AND error_msg = v_msg
       AND COALESCE(page_url, '') = COALESCE(v_url, '')
       AND created_at >= NOW() - INTERVAL '5 minutes'
  ) THEN
    RETURN;
  END IF;

  INSERT INTO error_logs (
    source, severity, page_url, error_msg, error_stack,
    user_agent, ip_hash, session_id, user_id, meta
  ) VALUES (
    v_source, v_severity, v_url, v_msg, v_stack,
    v_ua, v_ip_hash, v_session, v_user_id,
    p_data - 'error_msg' - 'error_stack' - 'page_url' - 'user_agent' - 'ip_hash' - 'session_id' - 'user_id' - 'source' - 'severity'
  );
END;
$$;

-- Anyone may CALL the RPC (only the API endpoint should, but we allow anon)
GRANT EXECUTE ON FUNCTION log_client_error(JSONB) TO anon, authenticated;


-- ============================================================
-- 3. Admin viewer RPC — last X hours grouped by error
-- ============================================================
DROP FUNCTION IF EXISTS admin_get_recent_errors(INT);
CREATE OR REPLACE FUNCTION admin_get_recent_errors(p_hours INT DEFAULT 24)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  IF p_hours NOT BETWEEN 1 AND 720 THEN
    p_hours := 24;
  END IF;

  -- Build result
  WITH recent AS (
    SELECT * FROM error_logs
     WHERE created_at >= NOW() - (p_hours || ' hours')::INTERVAL
  ),
  grouped AS (
    SELECT
      error_msg,
      MAX(severity) AS severity,
      COUNT(*)::INT AS occurrences,
      COUNT(DISTINCT ip_hash)::INT AS affected_users,
      array_agg(DISTINCT page_url) FILTER (WHERE page_url IS NOT NULL) AS pages,
      MIN(created_at) AS first_seen,
      MAX(created_at) AS last_seen,
      (array_agg(error_stack ORDER BY created_at DESC))[1] AS latest_stack
    FROM recent
    GROUP BY error_msg
    ORDER BY MAX(created_at) DESC
    LIMIT 100
  )
  SELECT jsonb_build_object(
    'window_hours',     p_hours,
    'total_errors',     (SELECT COUNT(*) FROM recent)::INT,
    'unique_errors',    (SELECT COUNT(DISTINCT error_msg) FROM recent)::INT,
    'affected_users',   (SELECT COUNT(DISTINCT ip_hash) FROM recent)::INT,
    'by_severity', (
      SELECT jsonb_object_agg(severity, cnt)
      FROM (SELECT severity, COUNT(*)::INT AS cnt FROM recent GROUP BY severity) s
    ),
    'errors', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'error_msg',       error_msg,
        'severity',        severity,
        'occurrences',     occurrences,
        'affected_users',  affected_users,
        'pages',           pages,
        'first_seen',      first_seen,
        'last_seen',       last_seen,
        'latest_stack',    latest_stack
      )) FROM grouped
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_get_recent_errors(INT) TO authenticated;


-- ============================================================
-- 4. Admin clear / prune utility
-- ============================================================
DROP FUNCTION IF EXISTS admin_clear_error_logs(INT);
CREATE OR REPLACE FUNCTION admin_clear_error_logs(p_older_than_days INT DEFAULT 30)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_deleted INT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;
  IF p_older_than_days < 1 THEN p_older_than_days := 1; END IF;

  DELETE FROM error_logs
   WHERE created_at < NOW() - (p_older_than_days || ' days')::INTERVAL;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_clear_error_logs(INT) TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'db/97 installed.';
  RAISE NOTICE '  Table: error_logs (RLS-locked, RPC-only access)';
  RAISE NOTICE '  Public RPC: log_client_error(jsonb)  - rate-limited 30/min, 200/hr per ip';
  RAISE NOTICE '  Admin RPC : admin_get_recent_errors(hours)';
  RAISE NOTICE '  Admin RPC : admin_clear_error_logs(older_than_days)';
END $$;
