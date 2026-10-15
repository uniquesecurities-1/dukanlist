-- ============================================================
-- db/272 — Dabwali Parivar: send profile links one after another + progress
-- ============================================================
-- Deepak, 15 Oct (phase 1): the office picks an organisation and sends every member their
-- own profile link on WhatsApp, one tap each, with a running count of who has confirmed,
-- who has a photo and who already got a link.
--   * admin_parivar_org_progress(org_id): members of the current session with mobile,
--     confirmed?, photo?, profession?, when the last profile link was sent / opened
-- Office only. Read-only. Safe to re-run.

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_parivar_org_progress(p_org_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE o parivar_orgs;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO o FROM parivar_orgs WHERE id = p_org_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'organisation not found'; END IF;
  RETURN jsonb_build_object('org', o.name, 'session', o.current_session, 'members', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'id', p.id, 'name', p.full_name, 'slug', p.slug, 'mobile', p.mobile,
             'role', x.role, 'role_label', x.role_label,
             'verified', p.mobile_verified_at IS NOT NULL,
             'photo', p.photo_url IS NOT NULL OR p.pending_photo_url IS NOT NULL,
             'profession', p.profession IS NOT NULL,
             'link_sent_at', (SELECT MAX(l.created_at) FROM parivar_profile_links l WHERE l.person_id = p.id),
             'link_opened', EXISTS (SELECT 1 FROM parivar_profile_links l WHERE l.person_id = p.id AND l.uses > 0))
           ORDER BY (p.mobile_verified_at IS NOT NULL), (x.role = 'member'), p.full_name)
      FROM (SELECT DISTINCT ON (r.person_id) r.person_id, r.role, r.role_label
              FROM parivar_org_roles r WHERE r.org_id = o.id AND r.session = o.current_session
             ORDER BY r.person_id, (r.role = 'member')) x
      JOIN parivar_people p ON p.id = x.person_id
     WHERE p.status = 'active'), '[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_org_progress(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_org_progress(UUID) TO authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/272-parivar-link-queue.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Check — each organisation: confirmed / with photo / got a link / members
SELECT o.name AS organisation,
       (SELECT COUNT(*) FILTER (WHERE (m->>'verified')::boolean) || ' confirmed · '
            || COUNT(*) FILTER (WHERE (m->>'photo')::boolean) || ' with photo · '
            || COUNT(*) FILTER (WHERE m->>'link_sent_at' IS NOT NULL) || ' got a link · '
            || COUNT(*) || ' members'
          FROM jsonb_array_elements(
                 (SELECT jsonb_agg(jsonb_build_object('verified', p.mobile_verified_at IS NOT NULL,
                                                      'photo', p.photo_url IS NOT NULL OR p.pending_photo_url IS NOT NULL,
                                                      'link_sent_at', (SELECT MAX(l.created_at) FROM public.parivar_profile_links l WHERE l.person_id = p.id)))
                    FROM (SELECT DISTINCT person_id FROM public.parivar_org_roles r WHERE r.org_id = o.id AND r.session = o.current_session) x
                    JOIN public.parivar_people p ON p.id = x.person_id AND p.status = 'active')) m) AS progress
  FROM public.parivar_orgs o WHERE o.status = 'active' ORDER BY o.name;
