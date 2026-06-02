-- =====================================================
-- db/94-admin-todays-focus.sql
-- =====================================================
-- USER REQUEST (2026-06-02):
--   "Admin Today's Focus widget on admin dashboard — single-glance
--    summary of what needs attention TODAY."
--
-- WHAT THIS PATCH DOES:
--   Replaces admin_dashboard_digest() from db/39 with an expanded
--   version that returns more focused-for-today metrics:
--     - Existing: pending, pending_edits, flagged, flags_open,
--                 featured_expiring, reports_open, growth stats
--     - NEW    : email_unverified  (registered last 7d, not verified)
--     - NEW    : verification_requested  (shops awaiting trust badge)
--     - NEW    : pucho_flagged   (community Q&A awaiting moderation)
--     - NEW    : pucho_replies_flagged
--     - NEW    : new_signups_24h (recent signups summary)
--
--   Same JSONB return shape — front-end just reads new keys.
--
-- BACKWARDS COMPATIBLE — existing UI fields keep working.
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

DROP FUNCTION IF EXISTS admin_dashboard_digest();

CREATE OR REPLACE FUNCTION admin_dashboard_digest()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_result JSONB;
  v_pending_count INT := 0;
  v_pending_edits_count INT := 0;
  v_flagged_count INT := 0;
  v_flags_open INT := 0;
  v_featured_active INT := 0;
  v_featured_expiring INT := 0;
  v_new_today INT := 0;
  v_new_week INT := 0;
  v_total_active INT := 0;
  v_reports_open INT := 0;
  -- New metrics
  v_email_unverified INT := 0;
  v_verification_requested INT := 0;
  v_pucho_flagged INT := 0;
  v_pucho_replies_flagged INT := 0;
  v_new_signups_24h INT := 0;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  -- ========== EXISTING METRICS (kept for backward compat) ==========
  SELECT COUNT(*) INTO v_pending_count
    FROM businesses WHERE status = 'pending';

  SELECT COUNT(*) INTO v_pending_edits_count
    FROM businesses WHERE pending_edits IS NOT NULL;

  SELECT COUNT(*) INTO v_flagged_count
    FROM businesses WHERE status = 'flagged';

  BEGIN
    SELECT COUNT(*) INTO v_flags_open
      FROM flags WHERE status = 'pending';
  EXCEPTION WHEN OTHERS THEN v_flags_open := 0; END;

  BEGIN
    SELECT COUNT(*) INTO v_featured_active
      FROM businesses
     WHERE featured = TRUE
       AND (featured_until IS NULL OR featured_until > NOW())
       AND status = 'active';
    SELECT COUNT(*) INTO v_featured_expiring
      FROM businesses
     WHERE featured = TRUE
       AND featured_until BETWEEN NOW() AND NOW() + INTERVAL '7 days'
       AND status = 'active';
  EXCEPTION WHEN OTHERS THEN
    v_featured_active := 0; v_featured_expiring := 0;
  END;

  SELECT COUNT(*) INTO v_new_today
    FROM businesses WHERE created_at >= date_trunc('day', NOW());
  SELECT COUNT(*) INTO v_new_week
    FROM businesses WHERE created_at >= NOW() - INTERVAL '7 days';
  SELECT COUNT(*) INTO v_total_active
    FROM businesses WHERE status = 'active';

  BEGIN
    SELECT COUNT(*) INTO v_reports_open
      FROM business_reports WHERE resolved_at IS NULL;
  EXCEPTION WHEN OTHERS THEN v_reports_open := 0; END;

  -- ========== NEW METRICS ==========

  -- Email-unverified registrations (last 7 days)
  -- These are users who started signup but never clicked the link.
  -- Admin can WhatsApp them OR force-verify via api/admin-force-verify-email
  BEGIN
    SELECT COUNT(*) INTO v_email_unverified
      FROM auth.users
     WHERE email_confirmed_at IS NULL
       AND email IS NOT NULL
       AND created_at >= NOW() - INTERVAL '7 days'
       AND NOT EXISTS (SELECT 1 FROM admin_users a WHERE a.auth_user_id = auth.users.id);
  EXCEPTION WHEN OTHERS THEN v_email_unverified := 0; END;

  -- Shops that requested admin verification badge
  BEGIN
    SELECT COUNT(*) INTO v_verification_requested
      FROM businesses
     WHERE verification_requested_at IS NOT NULL
       AND COALESCE(verified_score, 0) < 5  -- not fully verified yet
       AND status = 'active';
  EXCEPTION WHEN OTHERS THEN v_verification_requested := 0; END;

  -- Pucho Bhai flagged questions awaiting moderation
  BEGIN
    SELECT COUNT(*) INTO v_pucho_flagged
      FROM community_questions
     WHERE status = 'flagged';
  EXCEPTION WHEN OTHERS THEN v_pucho_flagged := 0; END;

  -- Pucho Bhai flagged replies
  BEGIN
    SELECT COUNT(*) INTO v_pucho_replies_flagged
      FROM community_replies
     WHERE status = 'flagged';
  EXCEPTION WHEN OTHERS THEN v_pucho_replies_flagged := 0; END;

  -- New auth signups in last 24h (informational)
  BEGIN
    SELECT COUNT(*) INTO v_new_signups_24h
      FROM auth.users
     WHERE created_at >= NOW() - INTERVAL '24 hours';
  EXCEPTION WHEN OTHERS THEN v_new_signups_24h := 0; END;

  -- ========== BUILD RESULT ==========
  SELECT jsonb_build_object(
    'tasks', jsonb_build_object(
      -- Existing fields (UI compatibility)
      'pending',           v_pending_count,
      'pending_edits',     v_pending_edits_count,
      'flagged',           v_flagged_count,
      'flags_open',        v_flags_open,
      'featured_expiring', v_featured_expiring,
      'reports_open',      v_reports_open,
      -- New fields
      'email_unverified',         v_email_unverified,
      'verification_requested',   v_verification_requested,
      'pucho_flagged',            v_pucho_flagged,
      'pucho_replies_flagged',    v_pucho_replies_flagged,
      'total_actionable',
        v_pending_count + v_pending_edits_count + v_flagged_count
        + v_flags_open + v_featured_expiring + v_reports_open
        + v_email_unverified + v_verification_requested
        + v_pucho_flagged + v_pucho_replies_flagged
    ),
    'stats', jsonb_build_object(
      'total_active',     v_total_active,
      'new_today',        v_new_today,
      'new_week',         v_new_week,
      'featured_active',  v_featured_active,
      'new_signups_24h',  v_new_signups_24h
    ),
    'recent_pending', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id',         b.id,
        'slug',       b.slug,
        'name',       b.name,
        'mobile',     b.mobile,
        'city_name',  gc.name,
        'created_at', b.created_at,
        'photo',      (b.photos)[1]
      ) ORDER BY b.created_at DESC)
        FROM (SELECT * FROM businesses WHERE status = 'pending' ORDER BY created_at DESC LIMIT 5) b
        LEFT JOIN geo_cities gc ON gc.id = b.city_id
    ), '[]'::jsonb),
    'recent_edits', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id',               b.id,
        'slug',             b.slug,
        'name',             b.name,
        'city_name',        gc.name,
        'pending_edits_at', b.pending_edits_at,
        'pending_fields',   (SELECT array_agg(key) FROM jsonb_object_keys(b.pending_edits) AS key)
      ) ORDER BY b.pending_edits_at DESC NULLS LAST)
        FROM (SELECT * FROM businesses WHERE pending_edits IS NOT NULL ORDER BY pending_edits_at DESC NULLS LAST LIMIT 5) b
        LEFT JOIN geo_cities gc ON gc.id = b.city_id
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_dashboard_digest() TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'db/94 installed. admin_dashboard_digest now returns:';
  RAISE NOTICE '  + email_unverified, verification_requested';
  RAISE NOTICE '  + pucho_flagged, pucho_replies_flagged';
  RAISE NOTICE '  + new_signups_24h';
END $$;
