-- ============================================================
-- db/265 — Sanstha Manager: adding or removing members needs office approval
-- ============================================================
-- Deepak, 13 Oct: if a manager link is misused (by mistake, on purpose, or it reaches the
-- wrong person), nobody must be able to wipe or flood a member list.
--   * pv_mgr_add / pv_mgr_remove no longer change the list — they file a REQUEST
--     (parivar_org_requests, status 'pending'); the office approves or rejects it in the admin
--   * the manager sees "waiting for approval" on their page, and the office's decisions
--   * at most 30 pending requests per organisation, and the same removal can't be filed twice
--   * role changes stay instant (they are needed on meeting day) but the log now keeps the old role,
--     so the office can undo one with a click
-- Needs db/264. Safe to re-run.

BEGIN;

CREATE TABLE IF NOT EXISTS public.parivar_org_requests (
  id          BIGSERIAL PRIMARY KEY,
  org_id      UUID        NOT NULL REFERENCES public.parivar_orgs(id) ON DELETE CASCADE,
  link_id     BIGINT,
  by_name     TEXT,
  kind        TEXT        NOT NULL CHECK (kind IN ('add', 'remove')),
  payload     JSONB       NOT NULL,
  status      TEXT        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  decided_at  TIMESTAMPTZ,
  decided_by  UUID,
  result      JSONB
);
CREATE INDEX IF NOT EXISTS idx_pv_org_req ON public.parivar_org_requests (org_id, status, created_at DESC);
ALTER TABLE public.parivar_org_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.parivar_org_requests FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public._pv_mgr_request_room(p_org_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF (SELECT COUNT(*) FROM parivar_org_requests WHERE org_id = p_org_id AND status = 'pending') >= 30 THEN
    RAISE EXCEPTION 'Many requests are already waiting for the DukanList office. Please wait until they are approved.';
  END IF;
END $$;
REVOKE ALL ON FUNCTION public._pv_mgr_request_room(UUID) FROM PUBLIC, anon, authenticated;

-- ---------- manager: requests instead of direct changes ----------
DROP FUNCTION IF EXISTS public.pv_mgr_add(TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.pv_mgr_add(p_token TEXT, p_lines TEXT, p_role TEXT DEFAULT 'member', p_since INT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE l parivar_org_manager_links; v_lines TEXT; v_n INT; v_id BIGINT;
BEGIN
  l := public._pv_mgr_open(p_token, TRUE);
  v_lines := btrim(COALESCE(p_lines, ''));
  SELECT COUNT(*) INTO v_n FROM unnest(regexp_split_to_array(v_lines, E'\n')) x WHERE btrim(x) <> '';
  IF v_n = 0 THEN RAISE EXCEPTION 'Please write at least one name.'; END IF;
  IF v_n > 200 THEN RAISE EXCEPTION 'Please send at most 200 names at a time.'; END IF;
  IF COALESCE(NULLIF(p_role, ''), 'member') NOT IN ('president','vice_president','secretary','joint_secretary','treasurer','pro','patron','chairman','founder','director','advisor','coordinator','member','other') THEN RAISE EXCEPTION 'unknown role'; END IF;
  IF p_since IS NOT NULL AND (p_since < 1900 OR p_since > EXTRACT(YEAR FROM NOW())::INT) THEN RAISE EXCEPTION 'Please enter a year like 2012.'; END IF;
  PERFORM public._pv_mgr_request_room(l.org_id);
  INSERT INTO parivar_org_requests (org_id, link_id, by_name, kind, payload)
  VALUES (l.org_id, l.id, l.sent_to_name, 'add',
          jsonb_build_object('lines', left(v_lines, 20000), 'count', v_n, 'role', COALESCE(NULLIF(p_role, ''), 'member'), 'since', p_since))
  RETURNING id INTO v_id;
  PERFORM public._pv_mgr_log(l, 'add_requested', jsonb_build_object('count', v_n, 'request_id', v_id));
  RETURN jsonb_build_object('pending', TRUE, 'request_id', v_id, 'count', v_n);
END $$;
REVOKE ALL ON FUNCTION public.pv_mgr_add(TEXT, TEXT, TEXT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pv_mgr_add(TEXT, TEXT, TEXT, INT) TO anon, authenticated;

DROP FUNCTION IF EXISTS public.pv_mgr_remove(TEXT, UUID);
CREATE OR REPLACE FUNCTION public.pv_mgr_remove(p_token TEXT, p_person_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE l parivar_org_manager_links; v_session TEXT; v_name TEXT; v_id BIGINT;
BEGIN
  l := public._pv_mgr_open(p_token, TRUE);
  SELECT current_session INTO v_session FROM parivar_orgs WHERE id = l.org_id;
  IF NOT EXISTS (SELECT 1 FROM parivar_org_roles WHERE org_id = l.org_id AND person_id = p_person_id AND session = v_session) THEN
    RAISE EXCEPTION 'This person is not on this session''s list.';
  END IF;
  IF EXISTS (SELECT 1 FROM parivar_org_requests WHERE org_id = l.org_id AND status = 'pending' AND kind = 'remove' AND payload->>'person_id' = p_person_id::TEXT) THEN
    RAISE EXCEPTION 'A request to remove this person is already waiting for approval.';
  END IF;
  PERFORM public._pv_mgr_request_room(l.org_id);
  SELECT full_name INTO v_name FROM parivar_people WHERE id = p_person_id;
  INSERT INTO parivar_org_requests (org_id, link_id, by_name, kind, payload)
  VALUES (l.org_id, l.id, l.sent_to_name, 'remove', jsonb_build_object('person_id', p_person_id, 'person', v_name, 'session', v_session))
  RETURNING id INTO v_id;
  PERFORM public._pv_mgr_log(l, 'remove_requested', jsonb_build_object('person', v_name, 'request_id', v_id));
  RETURN jsonb_build_object('pending', TRUE, 'request_id', v_id);
END $$;
REVOKE ALL ON FUNCTION public.pv_mgr_remove(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pv_mgr_remove(TEXT, UUID) TO anon, authenticated;

-- the manager can take back a request that is still waiting
CREATE OR REPLACE FUNCTION public.pv_mgr_cancel_request(p_token TEXT, p_request_id BIGINT)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE l parivar_org_manager_links;
BEGIN
  l := public._pv_mgr_open(p_token, TRUE);
  DELETE FROM parivar_org_requests WHERE id = p_request_id AND org_id = l.org_id AND status = 'pending';
  IF FOUND THEN PERFORM public._pv_mgr_log(l, 'request_cancelled', jsonb_build_object('request_id', p_request_id)); END IF;
  RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.pv_mgr_cancel_request(TEXT, BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pv_mgr_cancel_request(TEXT, BIGINT) TO anon, authenticated;

-- role changes stay instant, but remember the old role so the office can undo
CREATE OR REPLACE FUNCTION public.pv_mgr_set_role(p_token TEXT, p_person_id UUID, p_role TEXT, p_role_label TEXT DEFAULT NULL)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE l parivar_org_manager_links; v_session TEXT; v_old TEXT; v_old_role TEXT; v_old_label TEXT;
BEGIN
  l := public._pv_mgr_open(p_token, TRUE);
  IF NOT public._pv_mgr_member(l.org_id, p_person_id) THEN RAISE EXCEPTION 'This person is not in your organisation.'; END IF;
  SELECT current_session INTO v_session FROM parivar_orgs WHERE id = l.org_id;
  SELECT string_agg(COALESCE(role_label, role), ', ') INTO v_old FROM parivar_org_roles WHERE org_id = l.org_id AND person_id = p_person_id AND session = v_session;
  SELECT role, role_label INTO v_old_role, v_old_label FROM parivar_org_roles
   WHERE org_id = l.org_id AND person_id = p_person_id AND session = v_session ORDER BY (role = 'member') LIMIT 1;
  PERFORM public._parivar_put_role(l.org_id, p_person_id, p_role, p_role_label, v_session, NULL);
  PERFORM public._pv_mgr_log(l, 'role_changed', jsonb_build_object('person_id', p_person_id, 'person', (SELECT full_name FROM parivar_people WHERE id = p_person_id),
                                                                   'from', v_old, 'from_role', v_old_role, 'from_label', v_old_label,
                                                                   'to', COALESCE(NULLIF(p_role_label, ''), p_role), 'session', v_session));
  RETURN TRUE;
END $$;
REVOKE ALL ON FUNCTION public.pv_mgr_set_role(TEXT, UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pv_mgr_set_role(TEXT, UUID, TEXT, TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.pv_mgr_get(p_token TEXT)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE l parivar_org_manager_links; o parivar_orgs; v_due TEXT;
BEGIN
  l := public._pv_mgr_open(p_token, FALSE);
  SELECT * INTO o FROM parivar_orgs WHERE id = l.org_id;
  v_due := public._parivar_session_for(o.session_start_month);
  RETURN jsonb_build_object(
    'ok', TRUE, 'manager', l.sent_to_name, 'expires_at', l.expires_at,
    'org', jsonb_build_object('slug', o.slug, 'name', o.name, 'name_hi', o.name_hi, 'kind', o.kind, 'about', o.about,
                              'address', o.address, 'founded_year', o.founded_year, 'logo', o.logo_url,
                              'logo_waiting', o.pending_logo_url IS NOT NULL, 'session', o.current_session,
                              'next_session_due', CASE WHEN v_due > o.current_session THEN v_due END),
    'members', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', p.id, 'name', p.full_name, 'profession', p.profession, 'photo', p.photo_url,
               'role', x.role, 'role_label', x.role_label, 'joined_year', x.joined_year,
               'verified', p.mobile_verified_at IS NOT NULL,
               'mobile_hint', CASE WHEN p.mobile IS NOT NULL THEN '••••• ' || right(p.mobile, 5) END,
               'firm', (SELECT COALESCE(b.name, f.firm_name) FROM parivar_firm_roles f LEFT JOIN businesses b ON b.id = f.business_id
                         WHERE f.person_id = p.id ORDER BY (f.business_id IS NULL), f.created_at LIMIT 1))
             ORDER BY (x.role = 'member'), p.full_name)
        FROM (SELECT DISTINCT ON (r.person_id) r.person_id, r.role, r.role_label,
                     (SELECT MIN(r2.joined_year) FROM parivar_org_roles r2 WHERE r2.org_id = o.id AND r2.person_id = r.person_id) AS joined_year
                FROM parivar_org_roles r WHERE r.org_id = o.id AND r.session = o.current_session
               ORDER BY r.person_id, (r.role = 'member')) x
        JOIN parivar_people p ON p.id = x.person_id), '[]'::jsonb),
    -- v375: additions / removals wait for the office
    'pending', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', q.id, 'kind', q.kind, 'at', q.created_at,
                                   'person_id', q.payload->>'person_id', 'person', q.payload->>'person',
                                   'lines', q.payload->>'lines', 'role', q.payload->>'role') ORDER BY q.created_at DESC)
                          FROM parivar_org_requests q WHERE q.org_id = o.id AND q.status = 'pending'), '[]'::jsonb),
    'recent_decisions', COALESCE((SELECT jsonb_agg(jsonb_build_object('kind', q.kind, 'status', q.status, 'at', q.decided_at,
                                   'person', q.payload->>'person', 'lines', left(q.payload->>'lines', 200)) ORDER BY q.decided_at DESC)
                          FROM (SELECT * FROM parivar_org_requests WHERE org_id = o.id AND status <> 'pending' AND decided_at > NOW() - INTERVAL '14 days'
                                 ORDER BY decided_at DESC LIMIT 10) q), '[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.pv_mgr_get(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pv_mgr_get(TEXT) TO anon, authenticated;

-- ---------- office ----------
CREATE OR REPLACE FUNCTION public.admin_parivar_requests(p_org_id UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id', q.id, 'org_id', q.org_id, 'org', o.name, 'by', q.by_name, 'kind', q.kind,
                                   'at', q.created_at, 'payload', q.payload,
                                   'person_now', CASE WHEN q.kind = 'remove' THEN
                                      (SELECT string_agg(COALESCE(r.role_label, r.role), ', ') FROM parivar_org_roles r
                                        WHERE r.org_id = q.org_id AND r.person_id = (q.payload->>'person_id')::UUID AND r.session = o.current_session) END)
                                   ORDER BY q.created_at)
                    FROM parivar_org_requests q JOIN parivar_orgs o ON o.id = q.org_id
                   WHERE q.status = 'pending' AND (p_org_id IS NULL OR q.org_id = p_org_id)), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_requests(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_requests(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_decide_request(p_request_id BIGINT, p_approve BOOLEAN)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE q parivar_org_requests; o parivar_orgs; r JSONB := '{}'::jsonb; v_pid TEXT; n INT;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO q FROM parivar_org_requests WHERE id = p_request_id FOR UPDATE;
  IF q.id IS NULL THEN RAISE EXCEPTION 'request not found'; END IF;
  IF q.status <> 'pending' THEN RAISE EXCEPTION 'this request was already %', q.status; END IF;
  SELECT * INTO o FROM parivar_orgs WHERE id = q.org_id;
  IF p_approve THEN
    IF q.kind = 'add' THEN
      r := public._parivar_bulk_add_core(q.org_id, q.payload->>'lines', COALESCE(q.payload->>'role', 'member'), auth.uid());
      IF NULLIF(q.payload->>'since', '') IS NOT NULL THEN
        FOR v_pid IN SELECT jsonb_array_elements_text(r->'person_ids') LOOP
          UPDATE parivar_org_roles SET joined_year = (q.payload->>'since')::INT WHERE org_id = q.org_id AND person_id = v_pid::UUID;
        END LOOP;
      END IF;
      r := r - 'person_ids';
    ELSE
      IF q.payload->>'session' <> o.current_session THEN RAISE EXCEPTION 'that request was for session %, which has ended', q.payload->>'session'; END IF;
      DELETE FROM parivar_org_roles WHERE org_id = q.org_id AND person_id = (q.payload->>'person_id')::UUID AND session = o.current_session;
      GET DIAGNOSTICS n = ROW_COUNT;
      r := jsonb_build_object('removed_rows', n);
    END IF;
  END IF;
  UPDATE parivar_org_requests SET status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
         decided_at = NOW(), decided_by = auth.uid(), result = r
   WHERE id = q.id;
  INSERT INTO parivar_org_changes (org_id, by_name, action, detail)
  VALUES (q.org_id, 'Office', CASE WHEN p_approve THEN 'request_approved' ELSE 'request_rejected' END,
          jsonb_build_object('kind', q.kind, 'person', q.payload->>'person', 'count', q.payload->>'count') || r);
  RETURN jsonb_build_object('ok', TRUE, 'status', CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END) || r;
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_decide_request(BIGINT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_decide_request(BIGINT, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_list(p_kind TEXT, p_q TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF p_kind = 'org' THEN
    RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id', o.id, 'slug', o.slug, 'name', o.name, 'kind', o.kind,
                       'session', o.current_session, 'status', o.status, 'logo_waiting', o.pending_logo_url IS NOT NULL,
                       'manager_changes_24h', (SELECT COUNT(*) FROM parivar_org_changes c WHERE c.org_id = o.id AND c.created_at > NOW() - INTERVAL '24 hours' AND c.link_id IS NOT NULL),
                       'requests_pending', (SELECT COUNT(*) FROM parivar_org_requests q WHERE q.org_id = o.id AND q.status = 'pending'),
                       'members', (SELECT COUNT(DISTINCT person_id) FROM parivar_org_roles r WHERE r.org_id = o.id AND r.session = o.current_session))
                       ORDER BY (o.pending_logo_url IS NULL AND NOT EXISTS (SELECT 1 FROM parivar_org_requests q WHERE q.org_id = o.id AND q.status = 'pending')), o.name)
                     FROM parivar_orgs o
                    WHERE NULLIF(btrim(COALESCE(p_q, '')), '') IS NULL OR o.name ILIKE '%' || btrim(p_q) || '%'), '[]'::jsonb);
  END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id', p.id, 'slug', p.slug, 'name', p.full_name, 'mobile', p.mobile,
                     'contact_mode', p.contact_mode, 'status', p.status, 'verified', p.mobile_verified_at IS NOT NULL,
                     'photo_waiting', p.pending_photo_url IS NOT NULL, 'note_waiting', p.member_note IS NOT NULL)
                     -- people waiting for the office (new photo / note) come first
                     ORDER BY (p.pending_photo_url IS NULL AND p.member_note IS NULL), p.full_name)
                   FROM (SELECT * FROM parivar_people
                          WHERE NULLIF(btrim(COALESCE(p_q, '')), '') IS NULL
                             OR full_name ILIKE '%' || btrim(p_q) || '%'
                             OR (length(regexp_replace(p_q, '\D', '', 'g')) >= 4 AND mobile LIKE '%' || regexp_replace(p_q, '\D', '', 'g') || '%')
                          ORDER BY (pending_photo_url IS NULL AND member_note IS NULL), full_name LIMIT 300) p), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_list(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_list(TEXT, TEXT) TO authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/265-parivar-manager-approval.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Checks — every row should say yes
SELECT 'requests table, closed to the public' AS check,
       CASE WHEN to_regclass('public.parivar_org_requests') IS NOT NULL AND NOT has_table_privilege('anon', 'public.parivar_org_requests', 'SELECT') THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'manager add / remove now only file a request',
       CASE WHEN pg_get_functiondef('public.pv_mgr_add(text,text,text,integer)'::regprocedure) LIKE '%parivar_org_requests%'
             AND pg_get_functiondef('public.pv_mgr_remove(text,uuid)'::regprocedure) LIKE '%parivar_org_requests%'
             AND pg_get_functiondef('public.pv_mgr_remove(text,uuid)'::regprocedure) NOT LIKE '%DELETE FROM parivar_org_roles%' THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'only the office can approve',
       CASE WHEN NOT has_function_privilege('anon', 'public.admin_parivar_decide_request(bigint,boolean)', 'EXECUTE') THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'old direct-add function removed',
       CASE WHEN to_regprocedure('public.pv_mgr_add(text,text,text)') IS NULL THEN 'yes' ELSE 'NO — tell Claude' END;
