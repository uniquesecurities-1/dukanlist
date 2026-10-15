-- ============================================================
-- db/273 — Dabwali Parivar phase 2: "I'll come" + past-event photos
-- ============================================================
-- Deepak, 15 Oct (phase 2):
--   * "मैं आऊँगा" on an upcoming event: one tap per phone (an anonymous device id kept in the
--     browser — no name, no number); the count shows on the event, to the manager and the office
--   * photos of past events: the organisation (manager link) adds up to 8 photos to an event
--     from the last 60 days → the office approves → "बीते कार्यक्रम" gallery on the
--     organisation's page (events of the last 12 months). The office's own photos go live at once.
--   (the team poster is drawn in the browser — no database change)
-- Needs db/270. Safe to re-run.

BEGIN;

CREATE TABLE IF NOT EXISTS public.parivar_event_rsvps (
  event_id   UUID        NOT NULL REFERENCES public.parivar_events(id) ON DELETE CASCADE,
  device     TEXT        NOT NULL CHECK (device ~ '^[a-z0-9]{16,64}$'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (event_id, device)
);
ALTER TABLE public.parivar_event_rsvps ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.parivar_event_rsvps FROM anon, authenticated;

CREATE TABLE IF NOT EXISTS public.parivar_event_photos (
  id          BIGSERIAL PRIMARY KEY,
  event_id    UUID        NOT NULL REFERENCES public.parivar_events(id) ON DELETE CASCADE,
  url         TEXT        NOT NULL CHECK (url ~ '^https://res\.cloudinary\.com/dukanlist/image/upload/'),
  status      TEXT        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  created_via TEXT        NOT NULL DEFAULT 'office' CHECK (created_via IN ('office', 'manager')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_pv_event_photos ON public.parivar_event_photos (event_id, status);
ALTER TABLE public.parivar_event_photos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.parivar_event_photos FROM anon, authenticated;

-- ---------- public: "I'll come" ----------
CREATE OR REPLACE FUNCTION public.parivar_event_rsvp(p_event_id UUID, p_device TEXT, p_going BOOLEAN)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_dev TEXT := lower(btrim(COALESCE(p_device, '')));
BEGIN
  IF v_dev !~ '^[a-z0-9]{16,64}$' THEN RAISE EXCEPTION 'bad device'; END IF;
  IF NOT EXISTS (SELECT 1 FROM parivar_events e JOIN parivar_orgs o ON o.id = e.org_id
                  WHERE e.id = p_event_id AND e.status = 'approved' AND o.status = 'active' AND public._pv_event_upcoming(e.starts_at)) THEN
    RAISE EXCEPTION 'This event is not open any more.';
  END IF;
  IF p_going THEN
    INSERT INTO parivar_event_rsvps (event_id, device) VALUES (p_event_id, v_dev) ON CONFLICT DO NOTHING;
  ELSE
    DELETE FROM parivar_event_rsvps WHERE event_id = p_event_id AND device = v_dev;
  END IF;
  RETURN (SELECT COUNT(*) FROM parivar_event_rsvps WHERE event_id = p_event_id);
END $$;
REVOKE ALL ON FUNCTION public.parivar_event_rsvp(UUID, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_event_rsvp(UUID, TEXT, BOOLEAN) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.parivar_upcoming_events(p_org_slug TEXT DEFAULT NULL, p_limit INT DEFAULT 12)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE(jsonb_agg(x ORDER BY (x->>'starts_at')::timestamptz), '[]'::jsonb) FROM (
    SELECT jsonb_build_object('id', e.id, 'title', e.title, 'starts_at', e.starts_at, 'venue', e.venue,
                              'details', e.details, 'contact', e.contact, 'poster', e.poster_url,
                              'going', (SELECT COUNT(*) FROM parivar_event_rsvps v WHERE v.event_id = e.id),
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

-- ---------- public: past events with approved photos ----------
CREATE OR REPLACE FUNCTION public.parivar_past_events(p_org_slug TEXT)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE(jsonb_agg(x ORDER BY (x->>'starts_at')::timestamptz DESC), '[]'::jsonb) FROM (
    SELECT jsonb_build_object('id', e.id, 'title', e.title, 'starts_at', e.starts_at, 'venue', e.venue,
             'poster', e.poster_url,
             'photos', (SELECT jsonb_agg(ph.url ORDER BY ph.created_at) FROM parivar_event_photos ph WHERE ph.event_id = e.id AND ph.status = 'approved')) AS x
      FROM parivar_events e JOIN parivar_orgs o ON o.id = e.org_id
     WHERE o.slug = p_org_slug AND o.status = 'active' AND e.status = 'approved'
       AND NOT public._pv_event_upcoming(e.starts_at) AND e.starts_at > NOW() - INTERVAL '12 months'
       AND EXISTS (SELECT 1 FROM parivar_event_photos ph WHERE ph.event_id = e.id AND ph.status = 'approved')
     ORDER BY e.starts_at DESC LIMIT 12
  ) s;
$$;
REVOKE ALL ON FUNCTION public.parivar_past_events(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_past_events(TEXT) TO anon, authenticated;

-- ---------- manager link ----------
-- events of this organisation: upcoming (with "I'll come" count) and the last 60 days (for photos)
CREATE OR REPLACE FUNCTION public.pv_mgr_events(p_token TEXT)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE l parivar_org_manager_links;
BEGIN
  l := public._pv_mgr_open(p_token, FALSE);
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id', e.id, 'title', e.title, 'starts_at', e.starts_at, 'venue', e.venue,
                                   'details', e.details, 'contact', e.contact, 'poster', e.poster_url, 'status', e.status,
                                   'past', NOT public._pv_event_upcoming(e.starts_at),
                                   'going', (SELECT COUNT(*) FROM parivar_event_rsvps v WHERE v.event_id = e.id),
                                   'photos', COALESCE((SELECT jsonb_agg(jsonb_build_object('url', ph.url, 'status', ph.status) ORDER BY ph.created_at)
                                                         FROM parivar_event_photos ph WHERE ph.event_id = e.id AND ph.status <> 'rejected'), '[]'::jsonb))
                                   ORDER BY e.starts_at)
                     FROM parivar_events e
                    WHERE e.org_id = l.org_id AND e.status <> 'removed'
                      AND (public._pv_event_upcoming(e.starts_at) OR (e.status = 'approved' AND e.starts_at > NOW() - INTERVAL '60 days'))), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.pv_mgr_events(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pv_mgr_events(TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.pv_mgr_event_photo_add(p_token TEXT, p_event_id UUID, p_url TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE l parivar_org_manager_links; e parivar_events;
BEGIN
  l := public._pv_mgr_open(p_token, TRUE);
  SELECT * INTO e FROM parivar_events WHERE id = p_event_id AND org_id = l.org_id AND status = 'approved';
  IF e.id IS NULL THEN RAISE EXCEPTION 'Event not found.'; END IF;
  IF public._pv_event_upcoming(e.starts_at) THEN RAISE EXCEPTION 'Photos can be added after the event.'; END IF;
  IF e.starts_at < NOW() - INTERVAL '60 days' THEN RAISE EXCEPTION 'Photos can be added up to 60 days after the event.'; END IF;
  IF p_url IS NULL OR p_url !~ '^https://res\.cloudinary\.com/dukanlist/image/upload/[A-Za-z0-9_,./:@%()-]+$' THEN RAISE EXCEPTION 'The photo could not be accepted. Please choose it again.'; END IF;
  IF (SELECT COUNT(*) FROM parivar_event_photos WHERE event_id = e.id AND status <> 'rejected') >= 8 THEN RAISE EXCEPTION 'At most 8 photos per event.'; END IF;
  INSERT INTO parivar_event_photos (event_id, url, status, created_via) VALUES (e.id, p_url, 'pending', 'manager');
  PERFORM public._pv_mgr_log(l, 'event_photo_sent', jsonb_build_object('title', e.title));
  RETURN jsonb_build_object('ok', TRUE, 'pending', TRUE);
END $$;
REVOKE ALL ON FUNCTION public.pv_mgr_event_photo_add(TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pv_mgr_event_photo_add(TEXT, UUID, TEXT) TO anon, authenticated;

-- ---------- office ----------
CREATE OR REPLACE FUNCTION public.admin_parivar_event_photos(p_org_id UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('event_id', e.id, 'title', e.title, 'starts_at', e.starts_at, 'org_id', e.org_id, 'org', o.name,
                                   'going', (SELECT COUNT(*) FROM parivar_event_rsvps v WHERE v.event_id = e.id),
                                   'photos', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', ph.id, 'url', ph.url, 'status', ph.status) ORDER BY ph.created_at)
                                                         FROM parivar_event_photos ph WHERE ph.event_id = e.id AND ph.status <> 'rejected'), '[]'::jsonb))
                                   ORDER BY e.starts_at DESC)
                    FROM parivar_events e JOIN parivar_orgs o ON o.id = e.org_id
                   WHERE e.status = 'approved' AND NOT public._pv_event_upcoming(e.starts_at) AND e.starts_at > NOW() - INTERVAL '60 days'
                     AND (p_org_id IS NULL OR e.org_id = p_org_id)
                     AND (p_org_id IS NOT NULL OR EXISTS (SELECT 1 FROM parivar_event_photos ph WHERE ph.event_id = e.id AND ph.status = 'pending'))), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_event_photos(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_event_photos(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_event_photo_add(p_event_id UUID, p_url TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF p_url IS NULL OR p_url !~ '^https://res\.cloudinary\.com/dukanlist/image/upload/' THEN RAISE EXCEPTION 'bad photo address'; END IF;
  IF (SELECT COUNT(*) FROM parivar_event_photos WHERE event_id = p_event_id AND status <> 'rejected') >= 8 THEN RAISE EXCEPTION 'At most 8 photos per event.'; END IF;
  INSERT INTO parivar_event_photos (event_id, url, status, created_via) VALUES (p_event_id, p_url, 'approved', 'office');
  RETURN TRUE;
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_event_photo_add(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_event_photo_add(UUID, TEXT) TO authenticated;

-- approve / reject / take down one photo
CREATE OR REPLACE FUNCTION public.admin_parivar_event_photo_decide(p_photo_id BIGINT, p_approve BOOLEAN)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  UPDATE parivar_event_photos SET status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END WHERE id = p_photo_id;
  RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_event_photo_decide(BIGINT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_event_photo_decide(BIGINT, BOOLEAN) TO authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/273-parivar-rsvp-event-photos.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Checks — every row should say yes
SELECT 'RSVP + event photo tables, closed to the public' AS check,
       CASE WHEN to_regclass('public.parivar_event_rsvps') IS NOT NULL AND to_regclass('public.parivar_event_photos') IS NOT NULL
             AND NOT has_table_privilege('anon', 'public.parivar_event_rsvps', 'SELECT') AND NOT has_table_privilege('anon', 'public.parivar_event_photos', 'SELECT') THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'visitors can tap "I''ll come", only the office approves photos',
       CASE WHEN has_function_privilege('anon', 'public.parivar_event_rsvp(uuid,text,boolean)', 'EXECUTE')
             AND NOT has_function_privilege('anon', 'public.admin_parivar_event_photo_decide(bigint,boolean)', 'EXECUTE') THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'events carry the "going" count',
       CASE WHEN pg_get_functiondef('public.parivar_upcoming_events(text,integer)'::regprocedure) LIKE '%going%' THEN 'yes' ELSE 'NO — tell Claude' END;
