-- =====================================================
-- db/39-admin-productivity.sql
-- Admin Productivity Pack — Phase 1
-- =====================================================
-- ADDS:
--   1. admin_dashboard_digest()        — Today's tasks counts + recent items
--   2. admin_global_search(q)          — Search across name/mobile/slug/email/owner
--   3. admin_bulk_approve(ids[])       — One-shot approve multiple shops
--   4. admin_bulk_ban(ids[], reason)   — One-shot ban multiple shops
--   5. admin_bulk_set_status(ids[], status, reason) — generic bulk status change
-- =====================================================
BEGIN;

-- ---------- 1. Dashboard digest ----------
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
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  -- Pending shop approvals
  SELECT COUNT(*) INTO v_pending_count
    FROM businesses WHERE status = 'pending';

  -- Pending owner edits awaiting review
  SELECT COUNT(*) INTO v_pending_edits_count
    FROM businesses WHERE pending_edits IS NOT NULL;

  -- Flagged businesses
  SELECT COUNT(*) INTO v_flagged_count
    FROM businesses WHERE status = 'flagged';

  -- Open community flags (defensive — table may not exist on every env)
  BEGIN
    SELECT COUNT(*) INTO v_flags_open
      FROM flags WHERE status = 'pending';
  EXCEPTION WHEN OTHERS THEN v_flags_open := 0; END;

  -- Featured stats (defensive — db/37 may not be applied)
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

  -- Growth metrics
  SELECT COUNT(*) INTO v_new_today
    FROM businesses WHERE created_at >= date_trunc('day', NOW());
  SELECT COUNT(*) INTO v_new_week
    FROM businesses WHERE created_at >= NOW() - INTERVAL '7 days';
  SELECT COUNT(*) INTO v_total_active
    FROM businesses WHERE status = 'active';

  -- Reports (defensive)
  BEGIN
    SELECT COUNT(*) INTO v_reports_open
      FROM business_reports WHERE resolved_at IS NULL;
  EXCEPTION WHEN OTHERS THEN v_reports_open := 0; END;

  SELECT jsonb_build_object(
    'tasks', jsonb_build_object(
      'pending',         v_pending_count,
      'pending_edits',   v_pending_edits_count,
      'flagged',         v_flagged_count,
      'flags_open',      v_flags_open,
      'featured_expiring', v_featured_expiring,
      'reports_open',    v_reports_open,
      'total_actionable', v_pending_count + v_pending_edits_count + v_flagged_count + v_flags_open + v_featured_expiring + v_reports_open
    ),
    'stats', jsonb_build_object(
      'total_active',    v_total_active,
      'new_today',       v_new_today,
      'new_week',        v_new_week,
      'featured_active', v_featured_active
    ),
    'recent_pending', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id',           b.id,
        'slug',         b.slug,
        'name',         b.name,
        'mobile',       b.mobile,
        'city_name',    gc.name,
        'created_at',   b.created_at,
        'photo',        (b.photos)[1]
      ) ORDER BY b.created_at DESC)
        FROM (SELECT * FROM businesses WHERE status = 'pending' ORDER BY created_at DESC LIMIT 5) b
        LEFT JOIN geo_cities gc ON gc.id = b.city_id
    ), '[]'::jsonb),
    'recent_edits', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id',                b.id,
        'slug',              b.slug,
        'name',              b.name,
        'city_name',         gc.name,
        'pending_edits_at',  b.pending_edits_at,
        'pending_fields',    (SELECT array_agg(key) FROM jsonb_object_keys(b.pending_edits) AS key)
      ) ORDER BY b.pending_edits_at DESC NULLS LAST)
        FROM (SELECT * FROM businesses WHERE pending_edits IS NOT NULL ORDER BY pending_edits_at DESC NULLS LAST LIMIT 5) b
        LEFT JOIN geo_cities gc ON gc.id = b.city_id
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_dashboard_digest() TO authenticated;

-- ---------- 2. Global search ----------
DROP FUNCTION IF EXISTS admin_global_search(TEXT, INT);

CREATE OR REPLACE FUNCTION admin_global_search(p_query TEXT, p_limit INT DEFAULT 20)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_result JSONB;
  v_q TEXT;
  v_phone TEXT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  IF p_query IS NULL OR length(trim(p_query)) < 2 THEN
    RETURN '[]'::jsonb;
  END IF;
  v_q := trim(p_query);
  v_phone := regexp_replace(v_q, '\D', '', 'g');
  IF length(v_phone) >= 10 THEN v_phone := right(v_phone, 10); ELSE v_phone := NULL; END IF;

  SELECT COALESCE(jsonb_agg(row), '[]'::jsonb) INTO v_result FROM (
    SELECT jsonb_build_object(
      'id',         b.id,
      'slug',       b.slug,
      'name',       b.name,
      'mobile',     b.mobile,
      'email',      b.email,
      'owner_name', b.owner_name,
      'status',     b.status,
      'city_name',  gc.name,
      'pincode',    b.pincode,
      'verified_score', COALESCE(b.verified_score, 0),
      'photo',      (b.photos)[1],
      'created_at', b.created_at,
      'match_on',   CASE
        WHEN v_phone IS NOT NULL AND b.canonical_mobile = v_phone THEN 'mobile'
        WHEN b.name   ILIKE '%' || v_q || '%' THEN 'name'
        WHEN b.slug   ILIKE '%' || v_q || '%' THEN 'slug'
        WHEN b.email  ILIKE '%' || v_q || '%' THEN 'email'
        WHEN b.owner_name ILIKE '%' || v_q || '%' THEN 'owner'
        ELSE 'other'
      END
    ) AS row
    FROM businesses b
    LEFT JOIN geo_cities gc ON gc.id = b.city_id
    WHERE
      (v_phone IS NOT NULL AND b.canonical_mobile = v_phone)
      OR b.name        ILIKE '%' || v_q || '%'
      OR b.slug        ILIKE '%' || v_q || '%'
      OR b.email       ILIKE '%' || v_q || '%'
      OR b.owner_name  ILIKE '%' || v_q || '%'
      OR b.mobile      ILIKE '%' || v_q || '%'
    ORDER BY
      CASE
        WHEN v_phone IS NOT NULL AND b.canonical_mobile = v_phone THEN 0
        WHEN b.name   ILIKE v_q || '%' THEN 1
        WHEN b.name   ILIKE '%' || v_q || '%' THEN 2
        ELSE 3
      END,
      b.verified_score DESC NULLS LAST,
      b.created_at DESC
    LIMIT GREATEST(1, LEAST(p_limit, 50))
  ) sub;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_global_search(TEXT, INT) TO authenticated;

-- ---------- 3. Bulk status change ----------
DROP FUNCTION IF EXISTS admin_bulk_set_status(UUID[], TEXT, TEXT);

CREATE OR REPLACE FUNCTION admin_bulk_set_status(
  p_ids    UUID[],
  p_status TEXT,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID := auth.uid();
  v_changed_count INT := 0;
  v_id UUID;
  v_old_status TEXT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;
  IF p_status NOT IN ('active','pending','pending_review','flagged','banned','self_hidden') THEN
    RAISE EXCEPTION 'Invalid status: %', p_status;
  END IF;
  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL OR array_length(p_ids, 1) = 0 THEN
    RAISE EXCEPTION 'No business IDs provided';
  END IF;
  IF array_length(p_ids, 1) > 200 THEN
    RAISE EXCEPTION 'Too many IDs (max 200 per bulk action)';
  END IF;

  -- Process each id and log to audit
  FOREACH v_id IN ARRAY p_ids LOOP
    SELECT status INTO v_old_status FROM businesses WHERE id = v_id;
    IF v_old_status IS NULL THEN CONTINUE; END IF;
    IF v_old_status = p_status THEN CONTINUE; END IF;
    UPDATE businesses
       SET status = p_status, updated_at = NOW()
     WHERE id = v_id;
    INSERT INTO business_edits(business_id, field_name, old_value, new_value, edited_by, edited_role)
      VALUES (v_id, 'status', v_old_status, p_status, v_admin_id, 'admin');
    v_changed_count := v_changed_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'ok',            TRUE,
    'changed_count', v_changed_count,
    'requested',     array_length(p_ids, 1),
    'new_status',    p_status
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_bulk_set_status(UUID[], TEXT, TEXT) TO authenticated;

-- Convenience wrappers (keep API tidy)
DROP FUNCTION IF EXISTS admin_bulk_approve(UUID[]);
CREATE OR REPLACE FUNCTION admin_bulk_approve(p_ids UUID[])
RETURNS JSONB
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  SELECT admin_bulk_set_status(p_ids, 'active', NULL);
$$;
GRANT EXECUTE ON FUNCTION admin_bulk_approve(UUID[]) TO authenticated;

DROP FUNCTION IF EXISTS admin_bulk_ban(UUID[], TEXT);
CREATE OR REPLACE FUNCTION admin_bulk_ban(p_ids UUID[], p_reason TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  SELECT admin_bulk_set_status(p_ids, 'banned', p_reason);
$$;
GRANT EXECUTE ON FUNCTION admin_bulk_ban(UUID[], TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- VERIFY:
-- SELECT admin_dashboard_digest();
-- SELECT admin_global_search('singla', 10);
-- SELECT admin_global_search('9541223377', 10);
-- =====================================================
