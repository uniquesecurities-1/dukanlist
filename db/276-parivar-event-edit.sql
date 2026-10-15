-- ============================================================
-- db/276 — Dabwali Parivar: edit an event (poster, name, date, place, text)
-- ============================================================
-- Deepak, 15 Oct: there was no way to change a poster or fix the text of an event.
--   * admin_parivar_event_update(id, p): the office edits any upcoming event — a live event stays live
--   * pv_mgr_event_update(token, id, p): the organisation's manager edits its own upcoming event —
--     the change goes back to the office for approval (status → pending) like a new poster,
--     so nothing unchecked ever goes public
-- Same checks as adding (poster required, date within 60 days, max 3 upcoming). Safe to re-run.

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_parivar_event_update(p_event_id UUID, p JSONB)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE e parivar_events; c JSONB;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO e FROM parivar_events WHERE id = p_event_id FOR UPDATE;
  IF e.id IS NULL OR e.status IN ('removed', 'rejected') THEN RAISE EXCEPTION 'event not found'; END IF;
  c := public._pv_event_clean(e.org_id, p, e.id);
  UPDATE parivar_events SET title = c->>'title', starts_at = (c->>'starts_at')::timestamptz, venue = c->>'venue',
         details = c->>'details', contact = c->>'contact', poster_url = c->>'poster_url'
   WHERE id = e.id;
  INSERT INTO parivar_org_changes (org_id, by_name, action, detail) VALUES (e.org_id, 'Office', 'event_edited', jsonb_build_object('title', c->>'title'));
  RETURN TRUE;
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_event_update(UUID, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_event_update(UUID, JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.pv_mgr_event_update(p_token TEXT, p_event_id UUID, p JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE l parivar_org_manager_links; e parivar_events; c JSONB;
BEGIN
  l := public._pv_mgr_open(p_token, TRUE);
  SELECT * INTO e FROM parivar_events WHERE id = p_event_id AND org_id = l.org_id FOR UPDATE;
  IF e.id IS NULL OR e.status = 'removed' THEN RAISE EXCEPTION 'Event not found.'; END IF;
  IF NOT public._pv_event_upcoming(e.starts_at) THEN RAISE EXCEPTION 'This event is over — it cannot be changed now.'; END IF;
  c := public._pv_event_clean(l.org_id, p, e.id);
  UPDATE parivar_events SET title = c->>'title', starts_at = (c->>'starts_at')::timestamptz, venue = c->>'venue',
         details = c->>'details', contact = c->>'contact', poster_url = c->>'poster_url',
         status = 'pending', created_via = 'manager', link_id = l.id, by_name = l.sent_to_name, decided_at = NULL, decided_by = NULL
   WHERE id = e.id;
  PERFORM public._pv_mgr_log(l, 'event_edit_sent', jsonb_build_object('title', c->>'title'));
  RETURN jsonb_build_object('ok', TRUE, 'pending', TRUE);
END $$;
REVOKE ALL ON FUNCTION public.pv_mgr_event_update(TEXT, UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pv_mgr_event_update(TEXT, UUID, JSONB) TO anon, authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/276-parivar-event-edit.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Check — yes
SELECT 'events can be edited (office live, manager via approval)' AS check,
       CASE WHEN to_regprocedure('public.admin_parivar_event_update(uuid,jsonb)') IS NOT NULL
             AND to_regprocedure('public.pv_mgr_event_update(text,uuid,jsonb)') IS NOT NULL
             AND NOT has_function_privilege('anon', 'public.admin_parivar_event_update(uuid,jsonb)', 'EXECUTE') THEN 'yes' ELSE 'NO — tell Claude' END AS result;
