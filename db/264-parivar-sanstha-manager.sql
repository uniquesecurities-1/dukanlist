-- ============================================================
-- db/264 — Dabwali Parivar: "Sanstha Manager" link (no login)
-- ============================================================
-- Deepak, 13 Oct: let the President / Secretary run their own organisation.
-- Same pattern as shop update links (db/249) and member links (db/256):
--   * the office sends ONE manager link per organisation on WhatsApp (to a person with a mobile)
--   * only the sha256 of the token is stored; 30 days by default; a new link revokes the old one
--     (new President → send a new link → the old one stops working); the office can revoke any time
--   * a manager can: add members (one or a pasted list), set office bearers, remove someone from
--     this session, set "member since", edit about / address / founded year / Hindi name,
--     send a logo (goes live after office approval), start the next session when it is due,
--     and send any member their own profile link
--   * a manager can NOT: touch another organisation, rename the organisation, hide it,
--     see members' full mobile numbers (only the last 5 digits), or publish a logo directly
--   * every change is written to parivar_org_changes (what, when, by which link) and shown to the office
-- Also fixes admin_parivar_set_role: changing someone's role no longer loses their "member since" year.
-- Needs db/257 + db/259. Safe to re-run.

BEGIN;

ALTER TABLE public.parivar_orgs ADD COLUMN IF NOT EXISTS pending_logo_url TEXT;
ALTER TABLE public.parivar_orgs DROP CONSTRAINT IF EXISTS parivar_orgs_pending_logo_check;
ALTER TABLE public.parivar_orgs ADD CONSTRAINT parivar_orgs_pending_logo_check
  CHECK (pending_logo_url IS NULL OR pending_logo_url ~ '^https://res\.cloudinary\.com/dukanlist/image/upload/');

CREATE TABLE IF NOT EXISTS public.parivar_org_manager_links (
  id             BIGSERIAL PRIMARY KEY,
  org_id         UUID        NOT NULL REFERENCES public.parivar_orgs(id) ON DELETE CASCADE,
  person_id      UUID        REFERENCES public.parivar_people(id) ON DELETE SET NULL,
  sent_to_name   TEXT,
  token_hash     TEXT        NOT NULL UNIQUE,
  created_by     UUID,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at     TIMESTAMPTZ NOT NULL,
  uses           INT         NOT NULL DEFAULT 0,
  last_used_at   TIMESTAMPTZ,
  revoked_at     TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_pv_mgr_links_org ON public.parivar_org_manager_links (org_id);
ALTER TABLE public.parivar_org_manager_links ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.parivar_org_manager_links FROM anon, authenticated;

CREATE TABLE IF NOT EXISTS public.parivar_org_changes (
  id         BIGSERIAL PRIMARY KEY,
  org_id     UUID        NOT NULL REFERENCES public.parivar_orgs(id) ON DELETE CASCADE,
  link_id    BIGINT,
  by_name    TEXT,
  action     TEXT        NOT NULL,
  detail     JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_pv_org_changes ON public.parivar_org_changes (org_id, created_at DESC);
ALTER TABLE public.parivar_org_changes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.parivar_org_changes FROM anon, authenticated;

-- ---------- internal ----------
CREATE OR REPLACE FUNCTION public._parivar_bulk_add_core(p_org_id UUID, p_lines TEXT, p_role TEXT, p_by UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE
  o parivar_orgs; ln TEXT; v_rest TEXT; parts TEXT[]; v_name TEXT; v_prof TEXT; v_digits TEXT; v_mob TEXT; v_pid UUID; v_biz UUID;
  n_new INT := 0; n_linked INT := 0; n_already INT := 0; n_shops INT := 0; skipped TEXT[] := '{}'; v_ids UUID[] := '{}';
BEGIN
  SELECT * INTO o FROM parivar_orgs WHERE id = p_org_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'organisation not found'; END IF;
  IF COALESCE(p_role, 'member') NOT IN ('president','vice_president','secretary','joint_secretary','treasurer','pro','patron',
                                         'chairman','founder','director','advisor','coordinator','member','other') THEN
    RAISE EXCEPTION 'unknown role';
  END IF;
  FOREACH ln IN ARRAY regexp_split_to_array(COALESCE(p_lines, ''), E'\n') LOOP
    ln := btrim(ln);
    CONTINUE WHEN ln = '';
    v_digits := regexp_replace(ln, '\D', '', 'g');
    v_mob := CASE WHEN length(v_digits) >= 10 THEN public._parivar_mobile(right(v_digits, 12)) END;
    IF v_mob IS NULL AND length(v_digits) >= 10 THEN v_mob := public._parivar_mobile(right(v_digits, 10)); END IF;
    IF v_mob IS NOT NULL AND v_mob !~ '^[6-9][0-9]{9}$' THEN v_mob := NULL; END IF;
    -- "1. Name, 98xxx xxxxx, Profession" → strip numbering + the number, then split on , ; |
    v_rest := regexp_replace(regexp_replace(ln, '^[0-9]+[.)]\s*', ''), '[+0-9][0-9 ()-]{8,}', '', 'g');
    parts := ARRAY(SELECT btrim(x) FROM unnest(regexp_split_to_array(v_rest, '\s*[,;|\t]\s*')) x WHERE btrim(x) <> '' AND btrim(x) !~ '^[-–—]+$');
    v_name := btrim(regexp_replace(COALESCE(parts[1], ''), '[-–—:]+\s*$', ''));
    v_prof := NULLIF(left(btrim(COALESCE(parts[2], '')), 60), '');
    IF length(v_name) < 2 OR length(v_name) > 80 THEN skipped := skipped || ln; CONTINUE; END IF;

    v_pid := NULL;
    IF v_mob IS NOT NULL THEN SELECT id INTO v_pid FROM parivar_people WHERE mobile = v_mob; END IF;
    IF v_pid IS NULL AND v_mob IS NULL THEN
      SELECT p.id INTO v_pid FROM parivar_people p JOIN parivar_org_roles r ON r.person_id = p.id
       WHERE r.org_id = p_org_id AND lower(p.full_name) = lower(v_name) LIMIT 1;
    END IF;
    IF v_pid IS NULL THEN
      INSERT INTO parivar_people (slug, full_name, city_id, mobile, contact_mode, profession, source, added_by)
      VALUES (public._parivar_slug(v_name, 'parivar_people'), v_name, o.city_id, v_mob,
              CASE WHEN v_mob IS NOT NULL THEN 'whatsapp' ELSE 'hidden' END, v_prof, 'sanstha', p_by)
      RETURNING id INTO v_pid;
      n_new := n_new + 1;
    ELSE
      n_linked := n_linked + 1;
      IF v_prof IS NOT NULL THEN UPDATE parivar_people SET profession = COALESCE(profession, v_prof) WHERE id = v_pid; END IF;
    END IF;

    -- their shop on DukanList, found by the same number
    IF v_mob IS NOT NULL THEN
      FOR v_biz IN SELECT b.id FROM businesses b
                    WHERE b.status = 'active'
                      AND (right(regexp_replace(COALESCE(b.mobile, ''), '\D', '', 'g'), 10) = v_mob
                        OR right(regexp_replace(COALESCE(b.whatsapp, ''), '\D', '', 'g'), 10) = v_mob)
                      AND NOT EXISTS (SELECT 1 FROM parivar_firm_roles f WHERE f.person_id = v_pid AND f.business_id = b.id)
      LOOP
        INSERT INTO parivar_firm_roles (person_id, business_id, role, added_by) VALUES (v_pid, v_biz, 'owner', p_by);
        n_shops := n_shops + 1;
      END LOOP;
    END IF;

    v_ids := v_ids || v_pid;
    IF EXISTS (SELECT 1 FROM parivar_org_roles WHERE org_id = p_org_id AND person_id = v_pid AND session = o.current_session) THEN
      n_already := n_already + 1;
    ELSE
      INSERT INTO parivar_org_roles (org_id, person_id, role, session, added_by)
      VALUES (p_org_id, v_pid, COALESCE(p_role, 'member'), o.current_session, p_by);
    END IF;
  END LOOP;
  RETURN jsonb_build_object('new_people', n_new, 'existing_people', n_linked, 'already_in_session', n_already,
                            'shops_linked', n_shops, 'skipped', to_jsonb(skipped), 'session', o.current_session,
                            'person_ids', to_jsonb(v_ids));
END $$;
REVOKE ALL ON FUNCTION public._parivar_bulk_add_core(UUID, TEXT, TEXT, UUID) FROM PUBLIC, anon, authenticated;

-- the office's paste-a-list keeps working exactly as before, now through the shared core
CREATE OR REPLACE FUNCTION public.admin_parivar_bulk_add(p_org_id UUID, p_lines TEXT, p_role TEXT DEFAULT 'member')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  RETURN public._parivar_bulk_add_core(p_org_id, p_lines, p_role, auth.uid());
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_bulk_add(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_bulk_add(UUID, TEXT, TEXT) TO authenticated;

-- one role per person per organisation per session; keeps their "member since" year
CREATE OR REPLACE FUNCTION public._parivar_put_role(p_org_id UUID, p_person_id UUID, p_role TEXT, p_role_label TEXT, p_session TEXT, p_by UUID)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_id BIGINT; v_joined INT; v_conf TIMESTAMPTZ;
BEGIN
  IF COALESCE(NULLIF(p_role, ''), 'member') NOT IN ('president','vice_president','secretary','joint_secretary','treasurer','pro','patron','chairman','founder','director','advisor','coordinator','member','other') THEN RAISE EXCEPTION 'unknown role'; END IF;
  SELECT MIN(joined_year), MIN(confirmed_at) INTO v_joined, v_conf
    FROM parivar_org_roles WHERE org_id = p_org_id AND person_id = p_person_id AND session = p_session;
  DELETE FROM parivar_org_roles WHERE org_id = p_org_id AND person_id = p_person_id AND session = p_session;
  INSERT INTO parivar_org_roles (org_id, person_id, role, role_label, session, joined_year, confirmed_at, added_by)
  VALUES (p_org_id, p_person_id, COALESCE(NULLIF(p_role, ''), 'member'),
          CASE WHEN p_role = 'other' THEN NULLIF(left(btrim(COALESCE(p_role_label, '')), 40), '') END,
          p_session, v_joined, v_conf, p_by)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public._parivar_put_role(UUID, UUID, TEXT, TEXT, TEXT, UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_set_role(p_org_id UUID, p_person_id UUID, p_role TEXT,
                                                        p_role_label TEXT DEFAULT NULL, p_session TEXT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE v_session TEXT;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT COALESCE(NULLIF(p_session, ''), current_session) INTO v_session FROM parivar_orgs WHERE id = p_org_id;
  IF v_session IS NULL THEN RAISE EXCEPTION 'sanstha not found'; END IF;
  RETURN public._parivar_put_role(p_org_id, p_person_id, p_role, p_role_label, v_session, auth.uid());
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_set_role(UUID, UUID, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_set_role(UUID, UUID, TEXT, TEXT, TEXT) TO authenticated;

-- live manager link → the link row, or an error the manager can understand
CREATE OR REPLACE FUNCTION public._pv_mgr_open(p_token TEXT, p_write BOOLEAN)
RETURNS public.parivar_org_manager_links LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE l parivar_org_manager_links;
BEGIN
  SELECT * INTO l FROM parivar_org_manager_links
   WHERE token_hash = encode(sha256(convert_to(COALESCE(p_token, ''), 'UTF8')), 'hex')
     AND revoked_at IS NULL AND expires_at > NOW()
   LIMIT 1;
  IF l.id IS NULL THEN RAISE EXCEPTION 'This link has expired or was replaced. Please ask DukanList for a new one.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM parivar_orgs WHERE id = l.org_id AND status = 'active') THEN
    RAISE EXCEPTION 'This organisation is not active right now. Please contact DukanList.';
  END IF;
  IF p_write THEN
    IF l.uses >= 3000 THEN RAISE EXCEPTION 'This link has been used too many times. Please ask DukanList for a new one.'; END IF;
    UPDATE parivar_org_manager_links SET uses = uses + 1, last_used_at = NOW() WHERE id = l.id;
  END IF;
  RETURN l;
END $$;
REVOKE ALL ON FUNCTION public._pv_mgr_open(TEXT, BOOLEAN) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._pv_mgr_log(l public.parivar_org_manager_links, p_action TEXT, p_detail JSONB)
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  INSERT INTO parivar_org_changes (org_id, link_id, by_name, action, detail) VALUES (l.org_id, l.id, l.sent_to_name, p_action, p_detail);
$$;
REVOKE ALL ON FUNCTION public._pv_mgr_log(public.parivar_org_manager_links, TEXT, JSONB) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._pv_mgr_member(p_org_id UUID, p_person_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT EXISTS (SELECT 1 FROM parivar_org_roles WHERE org_id = p_org_id AND person_id = p_person_id);
$$;
REVOKE ALL ON FUNCTION public._pv_mgr_member(UUID, UUID) FROM PUBLIC, anon, authenticated;

-- ---------- office ----------
CREATE OR REPLACE FUNCTION public.admin_parivar_create_manager_link(p_org_id UUID, p_person_id UUID, p_days INT DEFAULT 30)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE p parivar_people; v_token TEXT; v_exp TIMESTAMPTZ;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF NOT EXISTS (SELECT 1 FROM parivar_orgs WHERE id = p_org_id) THEN RAISE EXCEPTION 'organisation not found'; END IF;
  SELECT * INTO p FROM parivar_people WHERE id = p_person_id;
  IF p.id IS NULL THEN RAISE EXCEPTION 'pick the person who will manage it'; END IF;
  IF p.mobile IS NULL THEN RAISE EXCEPTION 'add their mobile number first — the link is sent to it'; END IF;
  UPDATE parivar_org_manager_links SET revoked_at = NOW() WHERE org_id = p_org_id AND revoked_at IS NULL;
  v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  v_exp := NOW() + make_interval(days => GREATEST(1, LEAST(COALESCE(p_days, 30), 90)));
  INSERT INTO parivar_org_manager_links (org_id, person_id, sent_to_name, token_hash, created_by, expires_at)
  VALUES (p_org_id, p.id, p.full_name, encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), auth.uid(), v_exp);
  INSERT INTO parivar_org_changes (org_id, by_name, action, detail)
  VALUES (p_org_id, 'Office', 'manager_link_sent', jsonb_build_object('to', p.full_name, 'expires', v_exp));
  RETURN jsonb_build_object('token', v_token, 'name', p.full_name, 'mobile', p.mobile, 'expires_at', v_exp);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_create_manager_link(UUID, UUID, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_create_manager_link(UUID, UUID, INT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_revoke_manager_link(p_org_id UUID)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE n INT;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  UPDATE parivar_org_manager_links SET revoked_at = NOW() WHERE org_id = p_org_id AND revoked_at IS NULL;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN INSERT INTO parivar_org_changes (org_id, by_name, action) VALUES (p_org_id, 'Office', 'manager_link_stopped'); END IF;
  RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_revoke_manager_link(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_revoke_manager_link(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_manager_info(p_org_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  RETURN jsonb_build_object(
    'link', (SELECT jsonb_build_object('to', l.sent_to_name, 'person_id', l.person_id, 'created_at', l.created_at,
                                       'expires_at', l.expires_at, 'last_used_at', l.last_used_at, 'uses', l.uses)
               FROM parivar_org_manager_links l
              WHERE l.org_id = p_org_id AND l.revoked_at IS NULL AND l.expires_at > NOW()
              ORDER BY l.created_at DESC LIMIT 1),
    'changes', COALESCE((SELECT jsonb_agg(jsonb_build_object('at', c.created_at, 'by', c.by_name, 'action', c.action, 'detail', c.detail)
                                          ORDER BY c.created_at DESC)
                           FROM (SELECT * FROM parivar_org_changes WHERE org_id = p_org_id ORDER BY created_at DESC LIMIT 40) c), '[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_manager_info(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_manager_info(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_review_logo(p_org_id UUID, p_approve BOOLEAN)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  UPDATE parivar_orgs
     SET logo_url = CASE WHEN p_approve THEN COALESCE(pending_logo_url, logo_url) ELSE logo_url END,
         pending_logo_url = NULL, updated_at = NOW()
   WHERE id = p_org_id;
  IF FOUND THEN
    INSERT INTO parivar_org_changes (org_id, by_name, action) VALUES (p_org_id, 'Office', CASE WHEN p_approve THEN 'logo_approved' ELSE 'logo_rejected' END);
  END IF;
  RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_review_logo(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_review_logo(UUID, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_list(p_kind TEXT, p_q TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF p_kind = 'org' THEN
    RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id', o.id, 'slug', o.slug, 'name', o.name, 'kind', o.kind,
                       'session', o.current_session, 'status', o.status, 'logo_waiting', o.pending_logo_url IS NOT NULL,
                       'manager_changes_24h', (SELECT COUNT(*) FROM parivar_org_changes c WHERE c.org_id = o.id AND c.created_at > NOW() - INTERVAL '24 hours' AND c.link_id IS NOT NULL),
                       'members', (SELECT COUNT(DISTINCT person_id) FROM parivar_org_roles r WHERE r.org_id = o.id AND r.session = o.current_session))
                       ORDER BY (o.pending_logo_url IS NULL), o.name)
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

-- ---------- the manager's page (/sanstha-manage?t=…) ----------
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
        JOIN parivar_people p ON p.id = x.person_id), '[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.pv_mgr_get(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pv_mgr_get(TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.pv_mgr_add(p_token TEXT, p_lines TEXT, p_role TEXT DEFAULT 'member')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE l parivar_org_manager_links; r JSONB;
BEGIN
  l := public._pv_mgr_open(p_token, TRUE);
  IF array_length(regexp_split_to_array(btrim(COALESCE(p_lines, '')), E'\n'), 1) > 200 THEN RAISE EXCEPTION 'Please paste at most 200 names at a time.'; END IF;
  r := public._parivar_bulk_add_core(l.org_id, p_lines, COALESCE(NULLIF(p_role, ''), 'member'), NULL);
  PERFORM public._pv_mgr_log(l, 'members_added', r - 'person_ids' || jsonb_build_object('lines', left(p_lines, 2000)));
  RETURN r;
END $$;
REVOKE ALL ON FUNCTION public.pv_mgr_add(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pv_mgr_add(TEXT, TEXT, TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.pv_mgr_set_role(p_token TEXT, p_person_id UUID, p_role TEXT, p_role_label TEXT DEFAULT NULL)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE l parivar_org_manager_links; v_session TEXT; v_old TEXT;
BEGIN
  l := public._pv_mgr_open(p_token, TRUE);
  IF NOT public._pv_mgr_member(l.org_id, p_person_id) THEN RAISE EXCEPTION 'This person is not in your organisation.'; END IF;
  SELECT current_session INTO v_session FROM parivar_orgs WHERE id = l.org_id;
  SELECT string_agg(COALESCE(role_label, role), ', ') INTO v_old FROM parivar_org_roles WHERE org_id = l.org_id AND person_id = p_person_id AND session = v_session;
  PERFORM public._parivar_put_role(l.org_id, p_person_id, p_role, p_role_label, v_session, NULL);
  PERFORM public._pv_mgr_log(l, 'role_changed', jsonb_build_object('person', (SELECT full_name FROM parivar_people WHERE id = p_person_id),
                                                                   'from', v_old, 'to', COALESCE(NULLIF(p_role_label, ''), p_role), 'session', v_session));
  RETURN TRUE;
END $$;
REVOKE ALL ON FUNCTION public.pv_mgr_set_role(TEXT, UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pv_mgr_set_role(TEXT, UUID, TEXT, TEXT) TO anon, authenticated;

-- takes someone off THIS session's list (their page and earlier sessions stay); logged so the office can put them back
CREATE OR REPLACE FUNCTION public.pv_mgr_remove(p_token TEXT, p_person_id UUID)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE l parivar_org_manager_links; v_session TEXT; v_rows JSONB; n INT;
BEGIN
  l := public._pv_mgr_open(p_token, TRUE);
  SELECT current_session INTO v_session FROM parivar_orgs WHERE id = l.org_id;
  SELECT jsonb_agg(jsonb_build_object('role', role, 'role_label', role_label, 'joined_year', joined_year)) INTO v_rows
    FROM parivar_org_roles WHERE org_id = l.org_id AND person_id = p_person_id AND session = v_session;
  DELETE FROM parivar_org_roles WHERE org_id = l.org_id AND person_id = p_person_id AND session = v_session;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN
    PERFORM public._pv_mgr_log(l, 'member_removed', jsonb_build_object('person_id', p_person_id,
              'person', (SELECT full_name FROM parivar_people WHERE id = p_person_id), 'session', v_session, 'rows', v_rows));
  END IF;
  RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.pv_mgr_remove(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pv_mgr_remove(TEXT, UUID) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.pv_mgr_set_joined(p_token TEXT, p_person_id UUID, p_year INT)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE l parivar_org_manager_links;
BEGIN
  l := public._pv_mgr_open(p_token, TRUE);
  IF NOT public._pv_mgr_member(l.org_id, p_person_id) THEN RAISE EXCEPTION 'This person is not in your organisation.'; END IF;
  IF p_year IS NOT NULL AND (p_year < 1900 OR p_year > EXTRACT(YEAR FROM NOW())::INT) THEN RAISE EXCEPTION 'Please enter a year like 2012.'; END IF;
  UPDATE parivar_org_roles SET joined_year = p_year WHERE org_id = l.org_id AND person_id = p_person_id;
  PERFORM public._pv_mgr_log(l, 'member_since', jsonb_build_object('person', (SELECT full_name FROM parivar_people WHERE id = p_person_id), 'year', p_year));
  RETURN TRUE;
END $$;
REVOKE ALL ON FUNCTION public.pv_mgr_set_joined(TEXT, UUID, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pv_mgr_set_joined(TEXT, UUID, INT) TO anon, authenticated;

-- p: {about?, address?, founded_year?, name_hi?, logo?} — the logo waits for the office
CREATE OR REPLACE FUNCTION public.pv_mgr_update_org(p_token TEXT, p JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE l parivar_org_manager_links; v_logo TEXT; v_year INT;
BEGIN
  l := public._pv_mgr_open(p_token, TRUE);
  v_logo := NULLIF(p->>'logo', '');
  IF v_logo IS NOT NULL AND v_logo !~ '^https://res\.cloudinary\.com/dukanlist/image/upload/[A-Za-z0-9_,./:@%()-]+$' THEN
    RAISE EXCEPTION 'The logo could not be accepted. Please choose it again.';
  END IF;
  v_year := NULLIF(p->>'founded_year', '')::INT;
  IF v_year IS NOT NULL AND (v_year < 1800 OR v_year > EXTRACT(YEAR FROM NOW())::INT) THEN RAISE EXCEPTION 'Please enter the founding year like 1995.'; END IF;
  UPDATE parivar_orgs SET
    about            = CASE WHEN p ? 'about' THEN NULLIF(left(btrim(COALESCE(p->>'about', '')), 1000), '') ELSE about END,
    address          = CASE WHEN p ? 'address' THEN NULLIF(left(btrim(COALESCE(p->>'address', '')), 200), '') ELSE address END,
    name_hi          = CASE WHEN p ? 'name_hi' THEN NULLIF(left(btrim(COALESCE(p->>'name_hi', '')), 120), '') ELSE name_hi END,
    founded_year     = CASE WHEN p ? 'founded_year' THEN v_year ELSE founded_year END,
    pending_logo_url = COALESCE(v_logo, pending_logo_url),
    updated_at       = NOW()
  WHERE id = l.org_id;
  PERFORM public._pv_mgr_log(l, 'details_updated', p - 'logo' || jsonb_build_object('logo_sent', v_logo IS NOT NULL));
  RETURN jsonb_build_object('ok', TRUE, 'logo_waiting', v_logo IS NOT NULL);
END $$;
REVOKE ALL ON FUNCTION public.pv_mgr_update_org(TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pv_mgr_update_org(TEXT, JSONB) TO anon, authenticated;

-- next session only when it is actually due (e.g. from April for an April–March organisation)
CREATE OR REPLACE FUNCTION public.pv_mgr_new_session(p_token TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE l parivar_org_manager_links; o parivar_orgs; v_new TEXT; v_n INT;
BEGIN
  l := public._pv_mgr_open(p_token, TRUE);
  SELECT * INTO o FROM parivar_orgs WHERE id = l.org_id FOR UPDATE;
  v_new := public._parivar_session_for(o.session_start_month);
  IF v_new <= o.current_session THEN RAISE EXCEPTION 'The % session is still running. The next one can start when it is due.', o.current_session; END IF;
  INSERT INTO parivar_org_roles (org_id, person_id, role, session, confirmed_at, added_by)
  SELECT DISTINCT ON (person_id) org_id, person_id, 'member', v_new, confirmed_at, NULL
    FROM parivar_org_roles WHERE org_id = o.id AND session = o.current_session
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  UPDATE parivar_orgs SET current_session = v_new, updated_at = NOW() WHERE id = o.id;
  PERFORM public._pv_mgr_log(l, 'new_session', jsonb_build_object('from', o.current_session, 'to', v_new, 'carried_over', v_n));
  RETURN jsonb_build_object('session', v_new, 'carried_over', v_n);
END $$;
REVOKE ALL ON FUNCTION public.pv_mgr_new_session(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pv_mgr_new_session(TEXT) TO anon, authenticated;

-- a member's own profile link, for the manager to send on WhatsApp
CREATE OR REPLACE FUNCTION public.pv_mgr_member_link(p_token TEXT, p_person_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE l parivar_org_manager_links; p parivar_people;
BEGIN
  l := public._pv_mgr_open(p_token, TRUE);
  IF NOT public._pv_mgr_member(l.org_id, p_person_id) THEN RAISE EXCEPTION 'This person is not in your organisation.'; END IF;
  IF (SELECT COUNT(*) FROM parivar_org_changes WHERE link_id = l.id AND action = 'member_link' AND created_at > NOW() - INTERVAL '24 hours') >= 150 THEN
    RAISE EXCEPTION 'Too many links today. Please try again tomorrow.';
  END IF;
  SELECT * INTO p FROM parivar_people WHERE id = p_person_id;
  IF p.mobile IS NULL THEN RAISE EXCEPTION 'No mobile number for this member — add it first.'; END IF;
  PERFORM public._pv_mgr_log(l, 'member_link', jsonb_build_object('person', p.full_name));
  RETURN jsonb_build_object('token', public._parivar_make_link(p.id, 7), 'name', p.full_name, 'mobile', p.mobile);
END $$;
REVOKE ALL ON FUNCTION public.pv_mgr_member_link(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pv_mgr_member_link(TEXT, UUID) TO anon, authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/264-parivar-sanstha-manager.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Checks — every row should say yes
SELECT 'manager links + change log tables' AS check,
       CASE WHEN to_regclass('public.parivar_org_manager_links') IS NOT NULL AND to_regclass('public.parivar_org_changes') IS NOT NULL THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'link tables closed to the public',
       CASE WHEN NOT has_table_privilege('anon', 'public.parivar_org_manager_links', 'SELECT')
             AND NOT has_table_privilege('anon', 'public.parivar_org_changes', 'SELECT') THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'manager page functions open, office ones closed',
       CASE WHEN has_function_privilege('anon', 'public.pv_mgr_get(text)', 'EXECUTE')
             AND NOT has_function_privilege('anon', 'public.admin_parivar_create_manager_link(uuid,uuid,integer)', 'EXECUTE')
             AND NOT has_function_privilege('anon', 'public._parivar_bulk_add_core(uuid,text,text,uuid)', 'EXECUTE') THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'a wrong token is refused',
       CASE WHEN (SELECT count(*) FROM parivar_org_manager_links WHERE token_hash = encode(sha256(convert_to('x', 'UTF8')), 'hex')) = 0 THEN 'yes' ELSE 'NO — tell Claude' END;
