-- ============================================================
-- db/255 — Dabwali Parivar: founded year, meeting place, profession,
--           and pasting a whole member list at once
-- ============================================================
-- Deepak, 13 Oct ("teeno jodo"):
--   1. organisations: founded_year, address (meeting place / office)
--   2. people: profession (CA, Doctor, Teacher …) — searchable, and shown
--      under the name when the person holds no office
--   3. admin_parivar_bulk_add(org, lines, role) — paste "Name, mobile" one
--      per line; existing people are matched by mobile (or, without a
--      number, by name within this organisation), new ones are created
--      with the number hidden, and everyone joins the current session.
--      Someone who already holds a role this session keeps it.
-- Safe to re-run.
-- ============================================================
BEGIN;

ALTER TABLE public.parivar_orgs   ADD COLUMN IF NOT EXISTS founded_year INT;
ALTER TABLE public.parivar_orgs   ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE public.parivar_people ADD COLUMN IF NOT EXISTS profession TEXT;
ALTER TABLE public.parivar_orgs   DROP CONSTRAINT IF EXISTS parivar_orgs_founded_year_check;
ALTER TABLE public.parivar_orgs   ADD CONSTRAINT parivar_orgs_founded_year_check CHECK (founded_year IS NULL OR founded_year BETWEEN 1800 AND 2100);
ALTER TABLE public.parivar_orgs   DROP CONSTRAINT IF EXISTS parivar_orgs_address_check;
ALTER TABLE public.parivar_orgs   ADD CONSTRAINT parivar_orgs_address_check CHECK (address IS NULL OR length(address) <= 200);
ALTER TABLE public.parivar_people DROP CONSTRAINT IF EXISTS parivar_people_profession_check;
ALTER TABLE public.parivar_people ADD CONSTRAINT parivar_people_profession_check CHECK (profession IS NULL OR length(profession) <= 60);

CREATE OR REPLACE FUNCTION public.admin_parivar_upsert_org(p JSONB)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE
  v_id UUID := NULLIF(p->>'id', '')::UUID; v_mob TEXT; v_month INT; v_city INT;
  v_cname TEXT; v_crole TEXT; v_cbiz UUID; v_pid UUID; v_session TEXT; v_year INT; v_addr TEXT;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  v_mob := public._parivar_mobile(p->>'contact_mobile');
  IF COALESCE(p->>'contact_mobile', '') <> '' AND v_mob IS NULL THEN RAISE EXCEPTION 'contact mobile must be 10 digits'; END IF;
  v_month := COALESCE(NULLIF(p->>'session_start_month', '')::INT, 4);
  v_city  := COALESCE(NULLIF(p->>'city_id', '')::INT, (SELECT id FROM geo_cities WHERE name ILIKE 'mandi dabwali' LIMIT 1));
  v_cname := NULLIF(btrim(COALESCE(p->>'contact_name', '')), '');
  v_crole := NULLIF(p->>'contact_role', '');
  v_cbiz  := NULLIF(p->>'contact_business_id', '')::UUID;
  IF v_cbiz IS NOT NULL AND NOT EXISTS (SELECT 1 FROM businesses WHERE id = v_cbiz) THEN RAISE EXCEPTION 'tagged shop not found'; END IF;
  v_year := NULLIF(left(regexp_replace(COALESCE(p->>'founded_year', ''), '\D', '', 'g'), 4), '')::INT;
  IF v_year IS NOT NULL AND (v_year < 1800 OR v_year > EXTRACT(YEAR FROM NOW())::INT) THEN RAISE EXCEPTION 'founded year looks wrong'; END IF;
  v_addr := NULLIF(left(btrim(COALESCE(p->>'address', '')), 200), '');

  IF v_id IS NULL THEN
    INSERT INTO parivar_orgs (slug, name, name_hi, kind, city_id, about, logo_url, contact_name, contact_mobile,
                              contact_role, contact_business_id, founded_year, address, session_start_month, current_session, added_by)
    VALUES (public._parivar_slug(p->>'name', 'parivar_orgs'), btrim(p->>'name'),
            NULLIF(btrim(COALESCE(p->>'name_hi', '')), ''), COALESCE(NULLIF(p->>'kind', ''), 'samajik'), v_city,
            NULLIF(btrim(COALESCE(p->>'about', '')), ''), NULLIF(p->>'logo_url', ''),
            v_cname, v_mob, v_crole, v_cbiz, v_year, v_addr,
            v_month, public._parivar_session_for(v_month), auth.uid())
    RETURNING id INTO v_id;
  ELSE
    UPDATE parivar_orgs SET
      name           = COALESCE(NULLIF(btrim(COALESCE(p->>'name', '')), ''), name),
      name_hi        = CASE WHEN p ? 'name_hi' THEN NULLIF(btrim(COALESCE(p->>'name_hi', '')), '') ELSE name_hi END,
      kind           = COALESCE(NULLIF(p->>'kind', ''), kind),
      city_id        = CASE WHEN p ? 'city_id' THEN v_city ELSE city_id END,
      about          = CASE WHEN p ? 'about' THEN NULLIF(btrim(COALESCE(p->>'about', '')), '') ELSE about END,
      logo_url       = CASE WHEN p ? 'logo_url' THEN NULLIF(p->>'logo_url', '') ELSE logo_url END,
      contact_name   = CASE WHEN p ? 'contact_name' THEN v_cname ELSE contact_name END,
      contact_mobile = CASE WHEN p ? 'contact_mobile' THEN v_mob ELSE contact_mobile END,
      contact_role   = CASE WHEN p ? 'contact_role' THEN v_crole ELSE contact_role END,
      contact_business_id = CASE WHEN p ? 'contact_business_id' THEN v_cbiz ELSE contact_business_id END,
      founded_year   = CASE WHEN p ? 'founded_year' THEN v_year ELSE founded_year END,
      address        = CASE WHEN p ? 'address' THEN v_addr ELSE address END,
      session_start_month = CASE WHEN p ? 'session_start_month' THEN v_month ELSE session_start_month END,
      status         = COALESCE(NULLIF(p->>'status', ''), status),
      updated_at     = NOW()
    WHERE id = v_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'sanstha not found'; END IF;
  END IF;

  -- sync the contact into Dabwali Parivar
  IF v_cname IS NOT NULL THEN
    IF v_mob IS NOT NULL THEN
      SELECT id INTO v_pid FROM parivar_people WHERE mobile = v_mob;
    END IF;
    IF v_pid IS NULL THEN
      SELECT contact_person_id INTO v_pid FROM parivar_orgs WHERE id = v_id;
      -- reuse the previous contact only if it is the same name
      IF v_pid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM parivar_people WHERE id = v_pid AND lower(full_name) = lower(v_cname)) THEN
        v_pid := NULL;
      END IF;
    END IF;
    IF v_pid IS NULL THEN
      INSERT INTO parivar_people (slug, full_name, city_id, mobile, contact_mode, source, added_by)
      VALUES (public._parivar_slug(v_cname, 'parivar_people'), v_cname, v_city, v_mob,
              CASE WHEN v_mob IS NOT NULL THEN 'show' ELSE 'hidden' END, 'admin', auth.uid())
      RETURNING id INTO v_pid;
    ELSIF v_mob IS NOT NULL THEN
      UPDATE parivar_people SET mobile = COALESCE(mobile, v_mob),
             contact_mode = CASE WHEN contact_mode = 'hidden' THEN 'show' ELSE contact_mode END,
             updated_at = NOW()
       WHERE id = v_pid;
    END IF;
    UPDATE parivar_orgs SET contact_person_id = v_pid WHERE id = v_id;

    SELECT current_session INTO v_session FROM parivar_orgs WHERE id = v_id;
    IF v_crole IS NOT NULL THEN
      DELETE FROM parivar_org_roles WHERE org_id = v_id AND person_id = v_pid AND session = v_session;
      INSERT INTO parivar_org_roles (org_id, person_id, role, session, added_by)
      VALUES (v_id, v_pid, v_crole, v_session, auth.uid());
    ELSIF NOT EXISTS (SELECT 1 FROM parivar_org_roles WHERE org_id = v_id AND person_id = v_pid AND session = v_session) THEN
      INSERT INTO parivar_org_roles (org_id, person_id, role, session, added_by)
      VALUES (v_id, v_pid, 'coordinator', v_session, auth.uid());
    END IF;

    IF v_cbiz IS NOT NULL AND NOT EXISTS (SELECT 1 FROM parivar_firm_roles WHERE person_id = v_pid AND business_id = v_cbiz) THEN
      INSERT INTO parivar_firm_roles (person_id, business_id, role, added_by) VALUES (v_pid, v_cbiz, 'owner', auth.uid());
    END IF;
  END IF;

  RETURN (SELECT jsonb_build_object('id', id, 'slug', slug, 'session', current_session, 'contact_person_id', contact_person_id)
            FROM parivar_orgs WHERE id = v_id);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_upsert_org(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_upsert_org(JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_upsert_person(p JSONB)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE v_id UUID := NULLIF(p->>'id', '')::UUID; v_mob TEXT; v_slug TEXT; v_city INT;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  v_mob := public._parivar_mobile(p->>'mobile');
  IF COALESCE(p->>'mobile', '') <> '' AND v_mob IS NULL THEN RAISE EXCEPTION 'mobile must be 10 digits'; END IF;
  IF v_mob IS NOT NULL AND EXISTS (SELECT 1 FROM parivar_people WHERE mobile = v_mob AND id IS DISTINCT FROM v_id) THEN
    RAISE EXCEPTION 'this mobile already belongs to another person';
  END IF;
  v_city := COALESCE(NULLIF(p->>'city_id', '')::INT, (SELECT id FROM geo_cities WHERE name ILIKE 'mandi dabwali' LIMIT 1));
  IF v_id IS NULL THEN
    v_slug := public._parivar_slug(p->>'full_name', 'parivar_people');
    INSERT INTO parivar_people (slug, full_name, name_hi, city_id, mobile, contact_mode, photo_url, bio, profession, source, added_by)
    VALUES (v_slug, btrim(p->>'full_name'), NULLIF(btrim(COALESCE(p->>'name_hi', '')), ''), v_city, v_mob,
            COALESCE(NULLIF(p->>'contact_mode', ''), 'hidden'), NULLIF(p->>'photo_url', ''), NULLIF(btrim(COALESCE(p->>'bio', '')), ''),
            NULLIF(left(btrim(COALESCE(p->>'profession', '')), 60), ''), 'admin', auth.uid())
    RETURNING id INTO v_id;
  ELSE
    UPDATE parivar_people SET
      full_name    = COALESCE(NULLIF(btrim(COALESCE(p->>'full_name', '')), ''), full_name),
      name_hi      = CASE WHEN p ? 'name_hi' THEN NULLIF(btrim(COALESCE(p->>'name_hi', '')), '') ELSE name_hi END,
      city_id      = CASE WHEN p ? 'city_id' THEN v_city ELSE city_id END,
      mobile       = CASE WHEN p ? 'mobile' THEN v_mob ELSE mobile END,
      contact_mode = COALESCE(NULLIF(p->>'contact_mode', ''), contact_mode),
      photo_url    = CASE WHEN p ? 'photo_url' THEN NULLIF(p->>'photo_url', '') ELSE photo_url END,
      bio          = CASE WHEN p ? 'bio' THEN NULLIF(btrim(COALESCE(p->>'bio', '')), '') ELSE bio END,
      profession   = CASE WHEN p ? 'profession' THEN NULLIF(left(btrim(COALESCE(p->>'profession', '')), 60), '') ELSE profession END,
      status       = COALESCE(NULLIF(p->>'status', ''), status),
      updated_at   = NOW()
    WHERE id = v_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'person not found'; END IF;
  END IF;
  RETURN (SELECT jsonb_build_object('id', id, 'slug', slug) FROM parivar_people WHERE id = v_id);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_upsert_person(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_upsert_person(JSONB) TO authenticated;

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
      SELECT jsonb_agg(jsonb_build_object('name', x.full_name, 'slug', x.slug, 'verified', x.verified,
                                          'added_by_sanstha', x.by_sanstha) ORDER BY x.full_name)
        FROM (SELECT DISTINCT p.full_name, p.slug, p.mobile_verified_at IS NOT NULL AS verified,
                     (p.source <> 'self' AND p.mobile_verified_at IS NULL) AS by_sanstha
                FROM parivar_org_roles r JOIN parivar_people p ON p.id = r.person_id
               WHERE r.org_id = o.id AND r.session = o.current_session AND p.status = 'active') x), '[]'::jsonb),
    'past_presidents', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('session', r.session, 'name', p.full_name, 'slug', p.slug) ORDER BY r.session DESC)
        FROM parivar_org_roles r JOIN parivar_people p ON p.id = r.person_id
       WHERE r.org_id = o.id AND r.role = 'president' AND r.session < o.current_session AND p.status = 'active'), '[]'::jsonb));
END $$;

CREATE OR REPLACE FUNCTION public.parivar_get_person(p_slug TEXT)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE p parivar_people; v_city TEXT;
BEGIN
  SELECT * INTO p FROM parivar_people WHERE slug = p_slug AND status = 'active';
  IF p.id IS NULL THEN RETURN NULL; END IF;
  SELECT name INTO v_city FROM geo_cities WHERE id = p.city_id;
  RETURN jsonb_build_object(
    'slug', p.slug, 'name', p.full_name, 'name_hi', p.name_hi, 'city', v_city,
    'photo', p.photo_url, 'bio', p.bio, 'profession', p.profession,
    'verified', p.mobile_verified_at IS NOT NULL,
    'added_by_sanstha', p.source <> 'self' AND p.mobile_verified_at IS NULL,
    'contact_mode', CASE WHEN p.mobile IS NULL THEN 'hidden' ELSE p.contact_mode END,
    'mobile', CASE WHEN p.mobile IS NOT NULL AND p.contact_mode IN ('show', 'whatsapp') THEN p.mobile END,
    'firms', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'role', f.role, 'role_label', f.role_label,
               'name', COALESCE(b.name, f.firm_name),
               'slug', CASE WHEN b.status = 'active' THEN b.slug END,
               'category', (SELECT c.name FROM categories c WHERE c.id = COALESCE(b.sub_category_id, b.category_id)))
             ORDER BY f.created_at)
        FROM parivar_firm_roles f LEFT JOIN businesses b ON b.id = f.business_id
       WHERE f.person_id = p.id), '[]'::jsonb),
    'roles', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'org', o.name, 'org_slug', o.slug, 'role', r.role, 'role_label', r.role_label,
               'session', r.session, 'current', r.session = o.current_session)
             ORDER BY (r.session = o.current_session) DESC, r.session DESC, (r.role = 'member'))
        FROM parivar_org_roles r JOIN parivar_orgs o ON o.id = r.org_id
       WHERE r.person_id = p.id AND o.status = 'active'), '[]'::jsonb));
END $$;

CREATE OR REPLACE FUNCTION public.parivar_search(p_q TEXT DEFAULT NULL, p_limit INT DEFAULT 40)
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  WITH q AS (SELECT NULLIF(btrim(COALESCE(p_q, '')), '') AS t)
  SELECT COALESCE(jsonb_agg(r ORDER BY r->>'kind', r->>'name'), '[]'::jsonb) FROM (
    SELECT jsonb_build_object('kind', 'org', 'slug', o.slug, 'name', o.name, 'name_hi', o.name_hi, 'org_kind', o.kind,
             'members', (SELECT COUNT(DISTINCT person_id) FROM parivar_org_roles r WHERE r.org_id = o.id AND r.session = o.current_session)) AS r
      FROM parivar_orgs o, q
     WHERE o.status = 'active' AND (q.t IS NULL OR o.name ILIKE '%' || q.t || '%' OR o.name_hi ILIKE '%' || q.t || '%')
    UNION ALL
    SELECT jsonb_build_object('kind', 'person', 'slug', p.slug, 'name', p.full_name, 'name_hi', p.name_hi,
             'photo', p.photo_url, 'verified', p.mobile_verified_at IS NOT NULL,
             'line', (SELECT CASE WHEN r.role = 'member' THEN 'Member' ELSE initcap(replace(COALESCE(r.role_label, r.role), '_', ' ')) END || ', ' || o.name
                        FROM parivar_org_roles r JOIN parivar_orgs o ON o.id = r.org_id
                       WHERE r.person_id = p.id AND r.session = o.current_session AND o.status = 'active'
                       ORDER BY (r.role = 'member'), r.created_at LIMIT 1),
             'profession', p.profession)
      FROM parivar_people p, q
     WHERE p.status = 'active' AND q.t IS NOT NULL
       AND (p.full_name ILIKE '%' || q.t || '%' OR p.name_hi ILIKE '%' || q.t || '%' OR p.profession ILIKE '%' || q.t || '%')
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 40), 100))
  ) s(r);
$$;
REVOKE ALL ON FUNCTION public.parivar_search(TEXT, INT), public.parivar_get_person(TEXT), public.parivar_get_org(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_search(TEXT, INT), public.parivar_get_person(TEXT), public.parivar_get_org(TEXT) TO anon, authenticated;

-- paste a list: one person per line — "Name, 98xxxxxxxx" / "Name 98xxxxxxxx" / "Name"
CREATE OR REPLACE FUNCTION public.admin_parivar_bulk_add(p_org_id UUID, p_lines TEXT, p_role TEXT DEFAULT 'member')
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE
  o parivar_orgs; ln TEXT; v_name TEXT; v_digits TEXT; v_mob TEXT; v_pid UUID;
  n_new INT := 0; n_linked INT := 0; n_already INT := 0; skipped TEXT[] := '{}';
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
    IF array_length(skipped, 1) >= 200 THEN EXIT; END IF;
    v_digits := regexp_replace(ln, '\D', '', 'g');
    v_mob := CASE WHEN length(v_digits) >= 10 THEN public._parivar_mobile(right(v_digits, 12)) END;
    IF v_mob IS NULL AND length(v_digits) >= 10 THEN v_mob := public._parivar_mobile(right(v_digits, 10)); END IF;
    v_name := btrim(regexp_replace(regexp_replace(ln, '[+0-9][0-9 ()-]{8,}', '', 'g'), '[,;:|\t-]+\s*$', ''));
    v_name := btrim(regexp_replace(v_name, '^[0-9]+[.)]\s*', ''));   -- "1. Ramesh" / "2) Suresh"
    IF length(v_name) < 2 OR length(v_name) > 80 THEN skipped := skipped || ln; CONTINUE; END IF;
    IF v_mob IS NOT NULL AND v_mob !~ '^[6-9][0-9]{9}$' THEN v_mob := NULL; END IF;

    v_pid := NULL;
    IF v_mob IS NOT NULL THEN SELECT id INTO v_pid FROM parivar_people WHERE mobile = v_mob; END IF;
    IF v_pid IS NULL AND v_mob IS NULL THEN
      -- no number: reuse a same-named person already in this organisation (any session)
      SELECT p.id INTO v_pid FROM parivar_people p JOIN parivar_org_roles r ON r.person_id = p.id
       WHERE r.org_id = p_org_id AND lower(p.full_name) = lower(v_name) LIMIT 1;
    END IF;
    IF v_pid IS NULL THEN
      INSERT INTO parivar_people (slug, full_name, city_id, mobile, contact_mode, source, added_by)
      VALUES (public._parivar_slug(v_name, 'parivar_people'), v_name, o.city_id, v_mob, 'hidden', 'sanstha', auth.uid())
      RETURNING id INTO v_pid;
      n_new := n_new + 1;
    ELSE
      n_linked := n_linked + 1;
    END IF;

    IF EXISTS (SELECT 1 FROM parivar_org_roles WHERE org_id = p_org_id AND person_id = v_pid AND session = o.current_session) THEN
      n_already := n_already + 1;       -- keeps an office bearer's role; never demotes to member
    ELSE
      INSERT INTO parivar_org_roles (org_id, person_id, role, session, added_by)
      VALUES (p_org_id, v_pid, COALESCE(p_role, 'member'), o.current_session, auth.uid());
    END IF;
  END LOOP;
  RETURN jsonb_build_object('new_people', n_new, 'existing_people', n_linked, 'already_in_session', n_already,
                            'skipped', to_jsonb(skipped), 'session', o.current_session);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_bulk_add(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_bulk_add(UUID, TEXT, TEXT) TO authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/255-parivar-founded-profession-bulk.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Checks — every row should say yes
SELECT 'new columns' AS check,
       CASE WHEN (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = 'public'
                   AND ((table_name = 'parivar_orgs' AND column_name IN ('founded_year', 'address'))
                     OR (table_name = 'parivar_people' AND column_name = 'profession'))) = 3 THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'bulk add is admin-only',
       CASE WHEN NOT has_function_privilege('anon', 'public.admin_parivar_bulk_add(uuid,text,text)', 'EXECUTE')
             AND has_function_privilege('authenticated', 'public.admin_parivar_bulk_add(uuid,text,text)', 'EXECUTE') THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'contact sync from db/253 still in place',
       CASE WHEN pg_get_functiondef('public.admin_parivar_upsert_org(jsonb)'::regprocedure) LIKE '%contact_person_id%' THEN 'yes' ELSE 'NO — tell Claude' END;
