-- ============================================================
-- db/259 — Dabwali Parivar: members added by the office/organisation get "WhatsApp only"
-- ============================================================
-- Deepak, 13 Oct: default contact for listed members = WhatsApp button only
-- (number never printed on the page; the member can switch to Hidden from their own link).
--   1. admin_parivar_bulk_add: new people with a mobile → 'whatsapp' (was 'hidden').
--   2. One-time: people added by the office/organisation who have a number, are still 'hidden'
--      and have NOT confirmed their own page → 'whatsapp'. People who confirmed themselves
--      (mobile verified) keep whatever they chose.
-- Needs db/257. Safe to re-run.

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_parivar_bulk_add(p_org_id UUID, p_lines TEXT, p_role TEXT DEFAULT 'member')
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE
  o parivar_orgs; ln TEXT; v_rest TEXT; parts TEXT[]; v_name TEXT; v_prof TEXT; v_digits TEXT; v_mob TEXT; v_pid UUID; v_biz UUID;
  n_new INT := 0; n_linked INT := 0; n_already INT := 0; n_shops INT := 0; skipped TEXT[] := '{}';
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
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
              CASE WHEN v_mob IS NOT NULL THEN 'whatsapp' ELSE 'hidden' END, v_prof, 'sanstha', auth.uid())
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
        INSERT INTO parivar_firm_roles (person_id, business_id, role, added_by) VALUES (v_pid, v_biz, 'owner', auth.uid());
        n_shops := n_shops + 1;
      END LOOP;
    END IF;

    IF EXISTS (SELECT 1 FROM parivar_org_roles WHERE org_id = p_org_id AND person_id = v_pid AND session = o.current_session) THEN
      n_already := n_already + 1;
    ELSE
      INSERT INTO parivar_org_roles (org_id, person_id, role, session, added_by)
      VALUES (p_org_id, v_pid, COALESCE(p_role, 'member'), o.current_session, auth.uid());
    END IF;
  END LOOP;
  RETURN jsonb_build_object('new_people', n_new, 'existing_people', n_linked, 'already_in_session', n_already,
                            'shops_linked', n_shops, 'skipped', to_jsonb(skipped), 'session', o.current_session);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_bulk_add(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_bulk_add(UUID, TEXT, TEXT) TO authenticated;

UPDATE public.parivar_people
   SET contact_mode = 'whatsapp', updated_at = NOW()
 WHERE contact_mode = 'hidden'
   AND mobile IS NOT NULL
   AND mobile_verified_at IS NULL
   AND source <> 'self';

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/259-parivar-default-whatsapp.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Checks — first row yes; the others show the counts
SELECT 'bulk add uses WhatsApp only' AS check,
       CASE WHEN pg_get_functiondef('public.admin_parivar_bulk_add(uuid,text,text)'::regprocedure) LIKE '%THEN ''whatsapp'' ELSE ''hidden''%' THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'people now WhatsApp only', (SELECT count(*)::text FROM public.parivar_people WHERE contact_mode = 'whatsapp')
UNION ALL
SELECT 'people still hidden (no number, or chose it themselves)', (SELECT count(*)::text FROM public.parivar_people WHERE contact_mode = 'hidden')
UNION ALL
SELECT 'Lions Club Aks: members with WhatsApp',
       (SELECT count(*) FILTER (WHERE m->>'mobile' IS NOT NULL) || ' of ' || count(*)
          FROM jsonb_array_elements(public.parivar_get_org('lions-club-aks')->'members') m);
