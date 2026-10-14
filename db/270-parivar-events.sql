-- ============================================================
-- db/270 — Dabwali Parivar: upcoming events (poster) from organisations
-- ============================================================
-- Deepak, 14 Oct: an organisation puts up the poster of an upcoming event; it pops up on the
-- Dabwali Parivar page (2–3 s after opening, once per visitor per event), shows in an
-- "upcoming events" strip there, on the organisation's page, and as a small line on the home page.
--   * the Sanstha Manager (link) or the office adds it; the manager's events wait for the
--     office's approval; the office's own go live at once
--   * an event disappears by itself once its day is over (India time)
--   * limits: at most 3 upcoming events per organisation, date within the next 60 days,
--     a poster is required
--   * public read: parivar_upcoming_events() — approved, upcoming, active organisations only
-- Needs db/264 (manager link). Safe to re-run.

BEGIN;

CREATE TABLE IF NOT EXISTS public.parivar_events (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id       UUID        NOT NULL REFERENCES public.parivar_orgs(id) ON DELETE CASCADE,
  title        TEXT        NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 120),
  starts_at    TIMESTAMPTZ NOT NULL,
  venue        TEXT        CHECK (venue IS NULL OR length(venue) <= 200),
  details      TEXT        CHECK (details IS NULL OR length(details) <= 500),
  contact      TEXT        CHECK (contact IS NULL OR contact ~ '^[6-9][0-9]{9}$'),
  poster_url   TEXT        NOT NULL CHECK (poster_url ~ '^https://res\.cloudinary\.com/dukanlist/image/upload/'),
  status       TEXT        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'removed')),
  created_via  TEXT        NOT NULL DEFAULT 'office' CHECK (created_via IN ('office', 'manager')),
  link_id      BIGINT,
  by_name      TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  decided_at   TIMESTAMPTZ,
  decided_by   UUID
);
CREATE INDEX IF NOT EXISTS idx_pv_events_live ON public.parivar_events (status, starts_at);
CREATE INDEX IF NOT EXISTS idx_pv_events_org ON public.parivar_events (org_id, starts_at);
ALTER TABLE public.parivar_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.parivar_events FROM anon, authenticated;

-- "still upcoming" = its day (India time) is today or later
CREATE OR REPLACE FUNCTION public._pv_event_upcoming(p_at TIMESTAMPTZ)
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT (p_at AT TIME ZONE 'Asia/Kolkata')::date >= (NOW() AT TIME ZONE 'Asia/Kolkata')::date;
$$;

-- checks shared by the manager and the office; returns the cleaned fields
CREATE OR REPLACE FUNCTION public._pv_event_clean(p_org_id UUID, p JSONB, p_except UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_at TIMESTAMPTZ; v_poster TEXT; v_contact TEXT;
BEGIN
  IF length(btrim(COALESCE(p->>'title', ''))) < 3 THEN RAISE EXCEPTION 'Please write the event name.'; END IF;
  BEGIN v_at := (p->>'starts_at')::TIMESTAMPTZ; EXCEPTION WHEN OTHERS THEN v_at := NULL; END;
  IF v_at IS NULL THEN RAISE EXCEPTION 'Please choose the event date and time.'; END IF;
  IF NOT public._pv_event_upcoming(v_at) THEN RAISE EXCEPTION 'The event date has already passed.'; END IF;
  IF v_at > NOW() + INTERVAL '60 days' THEN RAISE EXCEPTION 'Events can be added up to 60 days ahead.'; END IF;
  v_poster := NULLIF(p->>'poster_url', '');
  IF v_poster IS NULL OR v_poster !~ '^https://res\.cloudinary\.com/dukanlist/image/upload/[A-Za-z0-9_,./:@%()-]+$' THEN
    RAISE EXCEPTION 'Please upload the event poster.';
  END IF;
  v_contact := NULLIF(regexp_replace(COALESCE(p->>'contact', ''), '\D', '', 'g'), '');
  IF v_contact IS NOT NULL THEN
    v_contact := right(v_contact, 10);
    IF v_contact !~ '^[6-9][0-9]{9}$' THEN RAISE EXCEPTION 'Contact number must be 10 digits.'; END IF;
  END IF;
  IF (SELECT COUNT(*) FROM parivar_events
       WHERE org_id = p_org_id AND status IN ('pending', 'approved') AND public._pv_event_upcoming(starts_at)
         AND id IS DISTINCT FROM p_except) >= 3 THEN
    RAISE EXCEPTION 'An organisation can have at most 3 upcoming events. Remove one first.';
  END IF;
  RETURN jsonb_build_object('title', left(btrim(p->>'title'), 120), 'starts_at', v_at,
                            'venue', NULLIF(left(btrim(COALESCE(p->>'venue', '')), 200), ''),
                            'details', NULLIF(left(btrim(COALESCE(p->>'details', '')), 500), ''),
                            'contact', v_contact, 'poster_url', v_poster);
END $$;
REVOKE ALL ON FUNCTION public._pv_event_clean(UUID, JSONB, UUID) FROM PUBLIC, anon, authenticated;

-- ---------- public ----------
CREATE OR REPLACE FUNCTION public.parivar_upcoming_events(p_org_slug TEXT DEFAULT NULL, p_limit INT DEFAULT 12)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE(jsonb_agg(x ORDER BY (x->>'starts_at')::timestamptz), '[]'::jsonb) FROM (
    SELECT jsonb_build_object('id', e.id, 'title', e.title, 'starts_at', e.starts_at, 'venue', e.venue,
                              'details', e.details, 'contact', e.contact, 'poster', e.poster_url,
                              'org', o.name, 'org_hi', o.name_hi, 'org_slug', o.slug, 'org_logo', o.logo_url) AS x
      FROM parivar_events e JOIN parivar_orgs o ON o.id = e.org_id
     WHERE e.status = 'approved' AND o.status = 'active' AND public._pv_event_upcoming(e.starts_at)
       AND (p_org_slug IS NULL OR o.slug = p_org_slug)
     ORDER BY e.starts_at
     LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 12), 30))
  ) s;
$$;
REVOKE ALL ON FUNCTION public.parivar_upcoming_events(TEXT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_upcoming_events(TEXT, INT) TO anon, authenticated;

-- ---------- manager link ----------
CREATE OR REPLACE FUNCTION public.pv_mgr_events(p_token TEXT)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE l parivar_org_manager_links;
BEGIN
  l := public._pv_mgr_open(p_token, FALSE);
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id', e.id, 'title', e.title, 'starts_at', e.starts_at, 'venue', e.venue,
                                   'details', e.details, 'contact', e.contact, 'poster', e.poster_url, 'status', e.status) ORDER BY e.starts_at)
                     FROM parivar_events e
                    WHERE e.org_id = l.org_id AND e.status <> 'removed' AND public._pv_event_upcoming(e.starts_at)), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.pv_mgr_events(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pv_mgr_events(TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.pv_mgr_event_add(p_token TEXT, p JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE l parivar_org_manager_links; c JSONB; v_id UUID;
BEGIN
  l := public._pv_mgr_open(p_token, TRUE);
  c := public._pv_event_clean(l.org_id, p, NULL);
  INSERT INTO parivar_events (org_id, title, starts_at, venue, details, contact, poster_url, status, created_via, link_id, by_name)
  VALUES (l.org_id, c->>'title', (c->>'starts_at')::timestamptz, c->>'venue', c->>'details', c->>'contact', c->>'poster_url',
          'pending', 'manager', l.id, l.sent_to_name)
  RETURNING id INTO v_id;
  PERFORM public._pv_mgr_log(l, 'event_sent', jsonb_build_object('title', c->>'title', 'starts_at', c->>'starts_at'));
  RETURN jsonb_build_object('ok', TRUE, 'id', v_id, 'pending', TRUE);
END $$;
REVOKE ALL ON FUNCTION public.pv_mgr_event_add(TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pv_mgr_event_add(TEXT, JSONB) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.pv_mgr_event_remove(p_token TEXT, p_event_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE l parivar_org_manager_links; v_title TEXT;
BEGIN
  l := public._pv_mgr_open(p_token, TRUE);
  UPDATE parivar_events SET status = 'removed' WHERE id = p_event_id AND org_id = l.org_id AND status <> 'removed'
  RETURNING title INTO v_title;
  IF v_title IS NULL THEN RETURN FALSE; END IF;
  PERFORM public._pv_mgr_log(l, 'event_removed', jsonb_build_object('title', v_title));
  RETURN TRUE;
END $$;
REVOKE ALL ON FUNCTION public.pv_mgr_event_remove(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pv_mgr_event_remove(TEXT, UUID) TO anon, authenticated;

-- ---------- office ----------
CREATE OR REPLACE FUNCTION public.admin_parivar_events(p_org_id UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id', e.id, 'org_id', e.org_id, 'org', o.name, 'title', e.title,
                                   'starts_at', e.starts_at, 'venue', e.venue, 'details', e.details, 'contact', e.contact,
                                   'poster', e.poster_url, 'status', e.status, 'via', e.created_via, 'by', e.by_name, 'at', e.created_at)
                                   ORDER BY (e.status <> 'pending'), e.starts_at)
                    FROM parivar_events e JOIN parivar_orgs o ON o.id = e.org_id
                   WHERE e.status IN ('pending', 'approved') AND public._pv_event_upcoming(e.starts_at)
                     AND (p_org_id IS NULL OR e.org_id = p_org_id)), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_events(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_events(UUID) TO authenticated;

-- the office adds an event — live at once
CREATE OR REPLACE FUNCTION public.admin_parivar_event_add(p_org_id UUID, p JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE c JSONB; v_id UUID;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF NOT EXISTS (SELECT 1 FROM parivar_orgs WHERE id = p_org_id) THEN RAISE EXCEPTION 'organisation not found'; END IF;
  c := public._pv_event_clean(p_org_id, p, NULL);
  INSERT INTO parivar_events (org_id, title, starts_at, venue, details, contact, poster_url, status, created_via, by_name, decided_at, decided_by)
  VALUES (p_org_id, c->>'title', (c->>'starts_at')::timestamptz, c->>'venue', c->>'details', c->>'contact', c->>'poster_url',
          'approved', 'office', 'Office', NOW(), auth.uid())
  RETURNING id INTO v_id;
  INSERT INTO parivar_org_changes (org_id, by_name, action, detail) VALUES (p_org_id, 'Office', 'event_added', jsonb_build_object('title', c->>'title'));
  RETURN jsonb_build_object('ok', TRUE, 'id', v_id);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_event_add(UUID, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_event_add(UUID, JSONB) TO authenticated;

-- approve / reject a manager's event, or take any event down ('remove')
CREATE OR REPLACE FUNCTION public.admin_parivar_event_decide(p_event_id UUID, p_decision TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE e parivar_events;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF p_decision NOT IN ('approve', 'reject', 'remove') THEN RAISE EXCEPTION 'unknown decision'; END IF;
  SELECT * INTO e FROM parivar_events WHERE id = p_event_id FOR UPDATE;
  IF e.id IS NULL THEN RAISE EXCEPTION 'event not found'; END IF;
  IF p_decision = 'approve' AND e.status <> 'pending' THEN RAISE EXCEPTION 'this event is already %', e.status; END IF;
  UPDATE parivar_events SET status = CASE p_decision WHEN 'approve' THEN 'approved' WHEN 'reject' THEN 'rejected' ELSE 'removed' END,
         decided_at = NOW(), decided_by = auth.uid()
   WHERE id = e.id;
  INSERT INTO parivar_org_changes (org_id, by_name, action, detail)
  VALUES (e.org_id, 'Office', CASE p_decision WHEN 'approve' THEN 'event_approved' WHEN 'reject' THEN 'event_rejected' ELSE 'event_taken_down' END,
          jsonb_build_object('title', e.title));
  RETURN TRUE;
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_event_decide(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_event_decide(UUID, TEXT) TO authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/270-parivar-events.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Checks — every row should say yes
SELECT 'events table, closed to the public' AS check,
       CASE WHEN to_regclass('public.parivar_events') IS NOT NULL AND NOT has_table_privilege('anon', 'public.parivar_events', 'SELECT') THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'visitors see approved upcoming events only',
       CASE WHEN has_function_privilege('anon', 'public.parivar_upcoming_events(text,integer)', 'EXECUTE')
             AND NOT has_function_privilege('anon', 'public.admin_parivar_event_decide(uuid,text)', 'EXECUTE') THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'nothing live yet (expected 0 now)', (SELECT jsonb_array_length(public.parivar_upcoming_events(NULL, 30)))::text;
