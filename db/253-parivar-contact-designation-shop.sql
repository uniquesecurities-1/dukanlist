-- ============================================================
-- db/253 — sanstha contact: designation + their DukanList shop
-- ============================================================
-- Deepak, 13 Oct: the sanstha's contact person needs a designation
-- (President / Secretary / Founder …) and, when that person already has a
-- shop on DukanList (e.g. Unique Securities), the shop tagged with it.
--
-- Saving a sanstha now also SYNCS that contact into Dabwali Parivar:
--   * the person is found by mobile (or created) — number shown publicly,
--     since it is the sanstha's official contact
--   * they get the designation as their role in the current session
--   * the tagged shop is linked to them as a firm
-- So one entry fills the sanstha card, the office-bearer list and the
-- person's own page. Also: 'founder' and 'advisor' added as roles.
-- Safe to re-run.
-- ============================================================
BEGIN;

ALTER TABLE public.parivar_orgs ADD COLUMN IF NOT EXISTS contact_role TEXT;
ALTER TABLE public.parivar_orgs ADD COLUMN IF NOT EXISTS contact_business_id UUID REFERENCES public.businesses(id) ON DELETE SET NULL;
ALTER TABLE public.parivar_orgs ADD COLUMN IF NOT EXISTS contact_person_id UUID REFERENCES public.parivar_people(id) ON DELETE SET NULL;

ALTER TABLE public.parivar_org_roles DROP CONSTRAINT IF EXISTS parivar_org_roles_role_check;
ALTER TABLE public.parivar_org_roles ADD CONSTRAINT parivar_org_roles_role_check
  CHECK (role IN ('president', 'vice_president', 'secretary', 'joint_secretary', 'treasurer', 'pro', 'patron',
                  'chairman', 'founder', 'director', 'advisor', 'coordinator', 'member', 'other'));
ALTER TABLE public.parivar_orgs DROP CONSTRAINT IF EXISTS parivar_orgs_contact_role_check;
ALTER TABLE public.parivar_orgs ADD CONSTRAINT parivar_orgs_contact_role_check
  CHECK (contact_role IS NULL OR contact_role IN ('president', 'vice_president', 'secretary', 'joint_secretary', 'treasurer',
                  'pro', 'patron', 'chairman', 'founder', 'director', 'advisor', 'coordinator', 'member', 'other'));

-- p: {id?, name, name_hi?, kind?, about?, contact_name?, contact_mobile?, contact_role?, contact_business_id?,
--     session_start_month?, logo_url?, city_id?, status?}
CREATE OR REPLACE FUNCTION public.admin_parivar_upsert_org(p JSONB)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE
  v_id UUID := NULLIF(p->>'id', '')::UUID; v_mob TEXT; v_month INT; v_city INT;
  v_cname TEXT; v_crole TEXT; v_cbiz UUID; v_pid UUID; v_session TEXT;
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

  IF v_id IS NULL THEN
    INSERT INTO parivar_orgs (slug, name, name_hi, kind, city_id, about, logo_url, contact_name, contact_mobile,
                              contact_role, contact_business_id, session_start_month, current_session, added_by)
    VALUES (public._parivar_slug(p->>'name', 'parivar_orgs'), btrim(p->>'name'),
            NULLIF(btrim(COALESCE(p->>'name_hi', '')), ''), COALESCE(NULLIF(p->>'kind', ''), 'samajik'), v_city,
            NULLIF(btrim(COALESCE(p->>'about', '')), ''), NULLIF(p->>'logo_url', ''),
            v_cname, v_mob, v_crole, v_cbiz,
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

-- admin read: add the tagged shop's name for the form
CREATE OR REPLACE FUNCTION public.admin_parivar_get(p_kind TEXT, p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF p_kind = 'org' THEN
    RETURN (SELECT to_jsonb(o) || jsonb_build_object(
              'contact_business_name', (SELECT b.name FROM businesses b WHERE b.id = o.contact_business_id),
              'roles', COALESCE((
              SELECT jsonb_agg(jsonb_build_object('id', r.id, 'person_id', p.id, 'name', p.full_name, 'slug', p.slug,
                                                  'mobile', p.mobile, 'role', r.role, 'role_label', r.role_label, 'session', r.session)
                     ORDER BY r.session DESC, (r.role = 'member'), p.full_name)
                FROM parivar_org_roles r JOIN parivar_people p ON p.id = r.person_id WHERE r.org_id = o.id), '[]'::jsonb))
              FROM parivar_orgs o WHERE o.id = p_id);
  ELSE
    RETURN (SELECT to_jsonb(p) || jsonb_build_object(
              'firms', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', f.id, 'business_id', f.business_id,
                                   'name', COALESCE(b.name, f.firm_name), 'role', f.role, 'role_label', f.role_label))
                                   FROM parivar_firm_roles f LEFT JOIN businesses b ON b.id = f.business_id WHERE f.person_id = p.id), '[]'::jsonb),
              'roles', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', r.id, 'org_id', o.id, 'org', o.name,
                                   'role', r.role, 'role_label', r.role_label, 'session', r.session) ORDER BY r.session DESC)
                                   FROM parivar_org_roles r JOIN parivar_orgs o ON o.id = r.org_id WHERE r.person_id = p.id), '[]'::jsonb))
              FROM parivar_people p WHERE p.id = p_id);
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_get(TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_get(TEXT, UUID) TO authenticated;

-- public sanstha page: contact designation, their page and their shop
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
    'about', o.about, 'logo', o.logo_url, 'session', o.current_session,
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
REVOKE ALL ON FUNCTION public.parivar_get_org(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_get_org(TEXT) TO anon, authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/253-parivar-contact-designation-shop.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Checks — both rows should say yes
SELECT 'new contact columns' AS check,
       CASE WHEN (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'parivar_orgs'
                   AND column_name IN ('contact_role', 'contact_business_id', 'contact_person_id')) = 3 THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'founder is a valid role',
       CASE WHEN pg_get_constraintdef((SELECT oid FROM pg_constraint WHERE conname = 'parivar_org_roles_role_check')) LIKE '%founder%'
            THEN 'yes' ELSE 'NO — tell Claude' END;
