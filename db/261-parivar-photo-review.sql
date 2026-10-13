-- ============================================================
-- db/261 — Dabwali Parivar: member photos must never be lost silently
-- ============================================================
-- Deepak, 13 Oct: a member uploaded a photo from their link but it never reached the office.
-- What we found: the photo is held for office approval (pending_photo_url) and only shown
-- inside that person's editor, and if anything was off the save quietly dropped the photo.
--   1. parivar_profile_save: a bad photo address now raises an error the member sees;
--      the reply says photo_saved true/false.  (The page now also sends the photo the
--      moment it finishes uploading, so leaving without pressing Save no longer loses it.)
--   2. admin_parivar_list: each person carries photo_waiting / note_waiting, and those
--      people are listed first, so the office sees them straight away.
-- Needs db/260. Safe to re-run.

BEGIN;

CREATE OR REPLACE FUNCTION public.parivar_profile_save(p_token TEXT, p JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE l parivar_profile_links; v parivar_people; v_photo TEXT; v_note TEXT;
BEGIN
  l := public._parivar_live_link(p_token);
  IF l.id IS NULL THEN RAISE EXCEPTION 'This link has expired. Please ask DukanList for a new one.'; END IF;
  IF l.uses >= 30 THEN RAISE EXCEPTION 'This link has been used too many times. Please ask DukanList for a new one.'; END IF;
  IF l.last_used_at IS NOT NULL AND l.last_used_at > NOW() - INTERVAL '10 seconds' THEN RAISE EXCEPTION 'Please wait a few seconds and try again.'; END IF;
  SELECT * INTO v FROM parivar_people WHERE id = l.person_id FOR UPDATE;

  v_photo := NULLIF(p->>'photo', '');
  -- v370: a bad photo address is now an error the member sees, not silently dropped
  IF v_photo IS NOT NULL AND v_photo !~ '^https://res\.cloudinary\.com/dukanlist/image/upload/[A-Za-z0-9_,./:@%()-]+$' THEN
    RAISE EXCEPTION 'The photo could not be accepted. Please choose the photo again.';
  END IF;
  v_note := NULLIF(left(btrim(COALESCE(p->>'note', '')), 500), '');

  UPDATE parivar_people SET
    -- the link was sent to this person's own number, so opening it and confirming verifies that number
    mobile_verified_at = CASE WHEN COALESCE((p->>'confirm')::boolean, FALSE) AND mobile IS NOT NULL THEN COALESCE(mobile_verified_at, NOW()) ELSE mobile_verified_at END,
    source            = CASE WHEN COALESCE((p->>'confirm')::boolean, FALSE) THEN 'self' ELSE source END,
    contact_mode      = CASE WHEN p->>'contact_mode' IN ('show', 'whatsapp', 'hidden') AND mobile IS NOT NULL THEN p->>'contact_mode' ELSE contact_mode END,
    profession        = CASE WHEN p ? 'profession' THEN NULLIF(left(btrim(COALESCE(p->>'profession', '')), 150), '') ELSE profession END,
    bio               = CASE WHEN p ? 'bio' THEN NULLIF(left(btrim(COALESCE(p->>'bio', '')), 300), '') ELSE bio END,
    pending_photo_url = COALESCE(v_photo, pending_photo_url),
    member_note       = COALESCE(v_note, member_note),
    member_note_at    = CASE WHEN v_note IS NOT NULL THEN NOW() ELSE member_note_at END,
    status            = CASE WHEN COALESCE((p->>'hide')::boolean, FALSE) THEN 'hidden'
                             WHEN COALESCE((p->>'unhide')::boolean, FALSE) THEN 'active' ELSE status END,
    updated_at        = NOW()
  WHERE id = v.id;
  UPDATE parivar_profile_links SET uses = uses + 1, last_used_at = NOW() WHERE id = l.id;
  RETURN jsonb_build_object('ok', TRUE, 'slug', v.slug, 'photo_saved', v_photo IS NOT NULL);
END $$;
REVOKE ALL ON FUNCTION public.parivar_profile_save(TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_profile_save(TEXT, JSONB) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_list(p_kind TEXT, p_q TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF p_kind = 'org' THEN
    RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id', o.id, 'slug', o.slug, 'name', o.name, 'kind', o.kind,
                       'session', o.current_session, 'status', o.status,
                       'members', (SELECT COUNT(DISTINCT person_id) FROM parivar_org_roles r WHERE r.org_id = o.id AND r.session = o.current_session))
                       ORDER BY o.name)
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
    PERFORM public.record_migration('db/261-parivar-photo-review.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Checks — first two yes; the third shows who is waiting for the office right now
SELECT 'member save reports the photo' AS check,
       CASE WHEN pg_get_functiondef('public.parivar_profile_save(text,jsonb)'::regprocedure) LIKE '%photo_saved%' THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'office list flags waiting photos',
       CASE WHEN pg_get_functiondef('public.admin_parivar_list(text,text)'::regprocedure) LIKE '%photo_waiting%' THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'waiting now (photo / note)',
       COALESCE((SELECT string_agg(full_name || CASE WHEN pending_photo_url IS NOT NULL THEN ' 📷' ELSE '' END
                                             || CASE WHEN member_note IS NOT NULL THEN ' 📝' ELSE '' END, ', ')
                   FROM public.parivar_people WHERE pending_photo_url IS NOT NULL OR member_note IS NOT NULL), 'nobody');
