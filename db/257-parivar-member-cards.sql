-- ============================================================
-- db/257 — organisation page: richer member cards
-- ============================================================
-- Deepak, 13 Oct: a member list of bare names ("added by the organisation"
-- on every line) does not tell you who anyone is. Each member now carries:
--   profession, photo, their business (first linked firm, with link),
--   "member since" (earliest session, or a joined year the office sets),
--   their role this session, verified.
-- Also:
--   * parivar_org_roles.joined_year + admin_parivar_set_joined() — the
--     office can record "member since 2012" when adding someone
--   * bulk paste reads an optional profession ("Name, mobile, Profession")
--     and links any DukanList shop registered on the member's number
-- Safe to re-run.
-- ============================================================
BEGIN;

ALTER TABLE public.parivar_org_roles ADD COLUMN IF NOT EXISTS joined_year INT;
ALTER TABLE public.parivar_org_roles DROP CONSTRAINT IF EXISTS parivar_org_roles_joined_year_check;
ALTER TABLE public.parivar_org_roles ADD CONSTRAINT parivar_org_roles_joined_year_check CHECK (joined_year IS NULL OR joined_year BETWEEN 1900 AND 2100);

CREATE OR REPLACE FUNCTION public.admin_parivar_set_joined(p_org_id UUID, p_person_id UUID, p_year INT)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF p_year IS NOT NULL AND (p_year < 1900 OR p_year > EXTRACT(YEAR FROM NOW())::INT) THEN RAISE EXCEPTION 'year looks wrong'; END IF;
  UPDATE parivar_org_roles SET joined_year = p_year WHERE org_id = p_org_id AND person_id = p_person_id;
  RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_set_joined(UUID, UUID, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_set_joined(UUID, UUID, INT) TO authenticated;

CREATE OR REPLACE FUNCTION public.parivar_get_org(p_slug TEXT)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE o parivar_orgs; v_city TEXT;
BEGIN
  SELECT * INTO o FROM parivar_orgs WHERE slug = p_slug AND status = 'active';
  IF o.id IS NULL THEN RETURN NULL; END IF;
  SELECT name INTO v_city FROM geo_cities WHERE id = o.city_id;
  RETURN jsonb_build_object(
    'slug', o.slug, 'name', o.name, 'name_hi', o.name_hi, 'kind', o.kind, 'city', v_city,
    'about', o.about, 'logo', o.logo_url, 'session', o.current_session, 'founded_year', o.founded_year, 'address', o.address,
    'contact_name', o.contact_name, 'contact_mobile', o.contact_mobile, 'contact_role', o.contact_role,
    'contact_slug', (SELECT slug FROM parivar_people WHERE id = o.contact_person_id AND status = 'active'),
    'contact_shop', (SELECT jsonb_build_object('name', b.name, 'slug', b.slug) FROM businesses b
                      WHERE b.id = o.contact_business_id AND b.status = 'active'),
    'bearers', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('role', r.role, 'role_label', r.role_label, 'name', p.full_name,
                                          'slug', p.slug, 'photo', p.photo_url, 'verified', p.mobile_verified_at IS NOT NULL)
             ORDER BY array_position(ARRAY['founder','patron','chairman','president','vice_president','secretary','joint_secretary',
                                           'treasurer','pro','director','advisor','coordinator','other'], r.role), p.full_name)
        FROM parivar_org_roles r JOIN parivar_people p ON p.id = r.person_id
       WHERE r.org_id = o.id AND r.session = o.current_session AND r.role <> 'member' AND p.status = 'active'), '[]'::jsonb),
    'members', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'name', p.full_name, 'slug', p.slug, 'photo', p.photo_url, 'profession', p.profession,
               'verified', p.mobile_verified_at IS NOT NULL,
               'added_by_sanstha', (p.source <> 'self' AND p.mobile_verified_at IS NULL),
               'role', x.role, 'role_label', x.role_label,
               'since', (SELECT LEAST(MIN(r2.joined_year), MIN(left(r2.session, 4)::INT))
                           FROM parivar_org_roles r2 WHERE r2.org_id = o.id AND r2.person_id = p.id),
               'firm', (SELECT jsonb_build_object('name', COALESCE(b.name, f.firm_name), 'slug', CASE WHEN b.status = 'active' THEN b.slug END,
                                                  'role', f.role, 'role_label', f.role_label)
                          FROM parivar_firm_roles f LEFT JOIN businesses b ON b.id = f.business_id
                         WHERE f.person_id = p.id ORDER BY (f.business_id IS NULL), f.created_at LIMIT 1))
             ORDER BY p.full_name)
        FROM (SELECT DISTINCT ON (r.person_id) r.person_id, r.role, r.role_label
                FROM parivar_org_roles r WHERE r.org_id = o.id AND r.session = o.current_session
               ORDER BY r.person_id, (r.role = 'member')) x
        JOIN parivar_people p ON p.id = x.person_id
       WHERE p.status = 'active'), '[]'::jsonb),
    'past_presidents', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('session', r.session, 'name', p.full_name, 'slug', p.slug) ORDER BY r.session DESC)
        FROM parivar_org_roles r JOIN parivar_people p ON p.id = r.person_id
       WHERE r.org_id = o.id AND r.role = 'president' AND r.session < o.current_session AND p.status = 'active'), '[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.parivar_get_org(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_get_org(TEXT) TO anon, authenticated;

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
      VALUES (public._parivar_slug(v_name, 'parivar_people'), v_name, o.city_id, v_mob, 'hidden', v_prof, 'sanstha', auth.uid())
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

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/257-parivar-member-cards.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Checks — first two rows should say yes; the third shows Lions Club Aks' first member card
SELECT 'joined_year column' AS check,
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'parivar_org_roles' AND column_name = 'joined_year') THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'members carry profession + business + since',
       CASE WHEN pg_get_functiondef('public.parivar_get_org(text)'::regprocedure) LIKE '%''since''%' THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'sample member', COALESCE((public.parivar_get_org('lions-club-aks')->'members'->0)::text, '(no members)');
