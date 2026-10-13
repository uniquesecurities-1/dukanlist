-- Dabwali Parivar catch-up: db/253 + 254 + 255 + 256 + 257 in one go, in the right order.
-- Every part is safe to re-run, so it does no harm if some of them already ran.
-- Paste the whole file in the Supabase SQL Editor and press Run once.


-- ===================== 253-parivar-contact-designation-shop.sql =====================
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


-- ===================== 254-parivar-shop-sync.sql =====================
-- ============================================================
-- db/254 — Dabwali Parivar ↔ shops, both ways
-- ============================================================
-- Deepak, 13 Oct: a proprietor / founder who is also a sanstha member
-- should show up on BOTH sides.
--   1. parivar_people_for_business(id) — the shop page lists the people
--      linked to it (founder, partner …) with their current sanstha roles,
--      each linking to their Parivar page.
--   2. admin_parivar_shops_by_mobile(mobile) — when the office types a
--      person's mobile, any active shop registered on that number is
--      suggested for linking, so nobody has to search for it by hand.
-- Read-only. Safe to re-run.
-- ============================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.parivar_people_for_business(p_business_id UUID)
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'name'), '[]'::jsonb) FROM (
    SELECT jsonb_build_object(
             'name', p.full_name, 'slug', p.slug, 'photo', p.photo_url,
             'verified', p.mobile_verified_at IS NOT NULL,
             'firm_role', f.role, 'firm_role_label', f.role_label,
             'roles', COALESCE((
               SELECT jsonb_agg(jsonb_build_object('org', o.name, 'org_slug', o.slug, 'role', r.role, 'role_label', r.role_label)
                      ORDER BY (r.role = 'member'), o.name)
                 FROM parivar_org_roles r JOIN parivar_orgs o ON o.id = r.org_id
                WHERE r.person_id = p.id AND r.session = o.current_session AND o.status = 'active'), '[]'::jsonb)) AS x
      FROM parivar_firm_roles f JOIN parivar_people p ON p.id = f.person_id
     WHERE f.business_id = p_business_id AND p.status = 'active'
  ) s;
$$;
REVOKE ALL ON FUNCTION public.parivar_people_for_business(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_people_for_business(UUID) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_shops_by_mobile(p_mobile TEXT)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE m TEXT := public._parivar_mobile(p_mobile);
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF m IS NULL THEN RETURN '[]'::jsonb; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'slug', b.slug, 'owner_name', b.owner_name) ORDER BY b.name)
      FROM businesses b
     WHERE b.status = 'active'
       AND (right(regexp_replace(COALESCE(b.mobile, ''), '\D', '', 'g'), 10) = m
         OR right(regexp_replace(COALESCE(b.whatsapp, ''), '\D', '', 'g'), 10) = m
         OR right(regexp_replace(COALESCE(b.alt_mobile, ''), '\D', '', 'g'), 10) = m)), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_shops_by_mobile(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_shops_by_mobile(TEXT) TO authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/254-parivar-shop-sync.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Checks — both rows should say yes
SELECT 'shop page can read its people' AS check,
       CASE WHEN has_function_privilege('anon', 'public.parivar_people_for_business(uuid)', 'EXECUTE') THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'mobile lookup is admin-only',
       CASE WHEN NOT has_function_privilege('anon', 'public.admin_parivar_shops_by_mobile(text)', 'EXECUTE') THEN 'yes' ELSE 'NO — tell Claude' END;


-- ===================== 255-parivar-founded-profession-bulk.sql =====================
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


-- ===================== 256-parivar-profile-links.sql =====================
-- ============================================================
-- db/256 — Dabwali Parivar: members manage their own page (no login)
-- ============================================================
-- Deepak, 13 Oct: members should be able to see and fix their own page.
-- Same idea as the shop "page sudhaaro" link (db/249), no password:
--   * the office sends a personal link on WhatsApp (to the person's own
--     number) — admin_parivar_create_profile_link()
--   * a DukanList shop owner gets the same link from his panel for the
--     people linked to his shop — my_parivar_profiles() / my_parivar_profile_link()
--   * on the link the person can: confirm "this is me" (→ number verified,
--     page may be indexed), choose contact visibility, set profession and
--     bio, send a new photo (goes to admin approval), send a correction
--     note to the office, or hide their page.
-- Only a SHA-256 of each token is stored; links expire (7 days), the
-- newest link revokes older ones, max 30 saves, one per 10 seconds.
-- Safe to re-run.
-- ============================================================
BEGIN;

ALTER TABLE public.parivar_people ADD COLUMN IF NOT EXISTS pending_photo_url TEXT;
ALTER TABLE public.parivar_people ADD COLUMN IF NOT EXISTS member_note TEXT;
ALTER TABLE public.parivar_people ADD COLUMN IF NOT EXISTS member_note_at TIMESTAMPTZ;
ALTER TABLE public.parivar_people DROP CONSTRAINT IF EXISTS parivar_people_pending_photo_check;
ALTER TABLE public.parivar_people ADD CONSTRAINT parivar_people_pending_photo_check
  CHECK (pending_photo_url IS NULL OR pending_photo_url ~ '^https://res\.cloudinary\.com/dukanlist/image/upload/');

CREATE TABLE IF NOT EXISTS public.parivar_profile_links (
  id           BIGSERIAL PRIMARY KEY,
  person_id    UUID        NOT NULL REFERENCES public.parivar_people(id) ON DELETE CASCADE,
  token_hash   TEXT        NOT NULL UNIQUE,
  created_by   UUID,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at   TIMESTAMPTZ NOT NULL,
  uses         INT         NOT NULL DEFAULT 0,
  last_used_at TIMESTAMPTZ,
  revoked_at   TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_pv_links_person ON public.parivar_profile_links (person_id);
ALTER TABLE public.parivar_profile_links ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.parivar_profile_links FROM anon, authenticated;

-- internal: make a link for a person (revokes their older links)
CREATE OR REPLACE FUNCTION public._parivar_make_link(p_person_id UUID, p_days INT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE v_token TEXT;
BEGIN
  UPDATE parivar_profile_links SET revoked_at = NOW() WHERE person_id = p_person_id AND revoked_at IS NULL;
  v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  INSERT INTO parivar_profile_links (person_id, token_hash, created_by, expires_at)
  VALUES (p_person_id, encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), auth.uid(),
          NOW() + make_interval(days => GREATEST(1, LEAST(COALESCE(p_days, 7), 30))));
  RETURN v_token;
END $$;
REVOKE ALL ON FUNCTION public._parivar_make_link(UUID, INT) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._parivar_live_link(p_token TEXT)
RETURNS public.parivar_profile_links LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT * FROM parivar_profile_links
   WHERE token_hash = encode(sha256(convert_to(COALESCE(p_token, ''), 'UTF8')), 'hex')
     AND revoked_at IS NULL AND expires_at > NOW()
   LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public._parivar_live_link(TEXT) FROM PUBLIC, anon, authenticated;

-- office: create a link (person must have a mobile — the link goes to it)
CREATE OR REPLACE FUNCTION public.admin_parivar_create_profile_link(p_person_id UUID, p_days INT DEFAULT 7)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE p parivar_people;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO p FROM parivar_people WHERE id = p_person_id;
  IF p.id IS NULL THEN RAISE EXCEPTION 'person not found'; END IF;
  IF p.mobile IS NULL THEN RAISE EXCEPTION 'add their mobile number first — the link is sent to it'; END IF;
  RETURN jsonb_build_object('token', public._parivar_make_link(p.id, p_days), 'name', p.full_name, 'slug', p.slug, 'mobile', p.mobile);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_create_profile_link(UUID, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_create_profile_link(UUID, INT) TO authenticated;

-- office: approve / reject a photo a member sent
CREATE OR REPLACE FUNCTION public.admin_parivar_review_photo(p_person_id UUID, p_approve BOOLEAN)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  UPDATE parivar_people
     SET photo_url = CASE WHEN p_approve THEN COALESCE(pending_photo_url, photo_url) ELSE photo_url END,
         pending_photo_url = NULL, updated_at = NOW()
   WHERE id = p_person_id;
  RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_review_photo(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_review_photo(UUID, BOOLEAN) TO authenticated;

-- office: clear a member's note once handled
CREATE OR REPLACE FUNCTION public.admin_parivar_clear_note(p_person_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  UPDATE parivar_people SET member_note = NULL, member_note_at = NULL WHERE id = p_person_id;
  RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_clear_note(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_clear_note(UUID) TO authenticated;

-- member opens the link
CREATE OR REPLACE FUNCTION public.parivar_profile_get(p_token TEXT)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE l parivar_profile_links; p parivar_people;
BEGIN
  IF length(COALESCE(p_token, '')) <> 64 THEN RETURN jsonb_build_object('ok', FALSE); END IF;
  l := public._parivar_live_link(p_token);
  IF l.id IS NULL THEN RETURN jsonb_build_object('ok', FALSE); END IF;
  SELECT * INTO p FROM parivar_people WHERE id = l.person_id;
  RETURN jsonb_build_object(
    'ok', TRUE, 'name', p.full_name, 'slug', p.slug, 'status', p.status,
    'profession', p.profession, 'bio', p.bio, 'photo', p.photo_url, 'pending_photo', p.pending_photo_url IS NOT NULL,
    'contact_mode', p.contact_mode, 'has_mobile', p.mobile IS NOT NULL,
    'mobile_hint', CASE WHEN p.mobile IS NOT NULL THEN '+91 ••••• ' || right(p.mobile, 5) END,
    'verified', p.mobile_verified_at IS NOT NULL,
    'firms', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', COALESCE(b.name, f.firm_name), 'role', f.role, 'role_label', f.role_label))
                         FROM parivar_firm_roles f LEFT JOIN businesses b ON b.id = f.business_id WHERE f.person_id = p.id), '[]'::jsonb),
    'roles', COALESCE((SELECT jsonb_agg(jsonb_build_object('org', o.name, 'role', r.role, 'role_label', r.role_label, 'session', r.session)
                                ORDER BY r.session DESC)
                         FROM parivar_org_roles r JOIN parivar_orgs o ON o.id = r.org_id
                        WHERE r.person_id = p.id AND r.session = o.current_session), '[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.parivar_profile_get(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_profile_get(TEXT) TO anon, authenticated;

-- member saves. p: {confirm?, contact_mode?, profession?, bio?, photo?, note?, hide?, unhide?}
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
  IF v_photo IS NOT NULL AND v_photo !~ '^https://res\.cloudinary\.com/dukanlist/image/upload/[A-Za-z0-9_,./:@-]+$' THEN v_photo := NULL; END IF;
  v_note := NULLIF(left(btrim(COALESCE(p->>'note', '')), 500), '');

  UPDATE parivar_people SET
    -- the link was sent to this person's own number, so opening it and confirming verifies that number
    mobile_verified_at = CASE WHEN COALESCE((p->>'confirm')::boolean, FALSE) AND mobile IS NOT NULL THEN COALESCE(mobile_verified_at, NOW()) ELSE mobile_verified_at END,
    source            = CASE WHEN COALESCE((p->>'confirm')::boolean, FALSE) THEN 'self' ELSE source END,
    contact_mode      = CASE WHEN p->>'contact_mode' IN ('show', 'whatsapp', 'hidden') AND mobile IS NOT NULL THEN p->>'contact_mode' ELSE contact_mode END,
    profession        = CASE WHEN p ? 'profession' THEN NULLIF(left(btrim(COALESCE(p->>'profession', '')), 60), '') ELSE profession END,
    bio               = CASE WHEN p ? 'bio' THEN NULLIF(left(btrim(COALESCE(p->>'bio', '')), 300), '') ELSE bio END,
    pending_photo_url = COALESCE(v_photo, pending_photo_url),
    member_note       = COALESCE(v_note, member_note),
    member_note_at    = CASE WHEN v_note IS NOT NULL THEN NOW() ELSE member_note_at END,
    status            = CASE WHEN COALESCE((p->>'hide')::boolean, FALSE) THEN 'hidden'
                             WHEN COALESCE((p->>'unhide')::boolean, FALSE) THEN 'active' ELSE status END,
    updated_at        = NOW()
  WHERE id = v.id;
  UPDATE parivar_profile_links SET uses = uses + 1, last_used_at = NOW() WHERE id = l.id;
  RETURN jsonb_build_object('ok', TRUE, 'slug', v.slug);
END $$;
REVOKE ALL ON FUNCTION public.parivar_profile_save(TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_profile_save(TEXT, JSONB) TO anon, authenticated;

-- shop owner (logged in): the Parivar people linked to his shops — by firm link or by the shop's number
CREATE OR REPLACE FUNCTION public.my_parivar_profiles()
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
  WITH mine AS (
    SELECT b.id, right(regexp_replace(COALESCE(b.mobile, ''), '\D', '', 'g'), 10) AS m1,
                 right(regexp_replace(COALESCE(b.whatsapp, ''), '\D', '', 'g'), 10) AS m2
      FROM business_owners bo JOIN businesses b ON b.id = bo.business_id
     WHERE bo.auth_user_id = auth.uid()
  )
  SELECT COALESCE(jsonb_agg(DISTINCT jsonb_build_object('id', p.id, 'name', p.full_name, 'slug', p.slug,
                                                        'verified', p.mobile_verified_at IS NOT NULL, 'status', p.status)), '[]'::jsonb)
    FROM parivar_people p
   WHERE auth.uid() IS NOT NULL
     AND (EXISTS (SELECT 1 FROM parivar_firm_roles f JOIN mine ON mine.id = f.business_id WHERE f.person_id = p.id)
       OR (p.mobile IS NOT NULL AND EXISTS (SELECT 1 FROM mine WHERE p.mobile IN (mine.m1, mine.m2))));
$$;
REVOKE ALL ON FUNCTION public.my_parivar_profiles() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_parivar_profiles() TO authenticated;

CREATE OR REPLACE FUNCTION public.my_parivar_profile_link(p_person_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'login required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(public.my_parivar_profiles()) e WHERE (e->>'id')::uuid = p_person_id) THEN
    RAISE EXCEPTION 'this profile is not linked to your shop';
  END IF;
  RETURN public._parivar_make_link(p_person_id, 1);
END $$;
REVOKE ALL ON FUNCTION public.my_parivar_profile_link(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_parivar_profile_link(UUID) TO authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/256-parivar-profile-links.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Checks — every row should say yes
SELECT 'links table closed to REST' AS check,
       CASE WHEN NOT has_table_privilege('anon', 'public.parivar_profile_links', 'SELECT') THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'member can open + save a link',
       CASE WHEN has_function_privilege('anon', 'public.parivar_profile_get(text)', 'EXECUTE')
             AND has_function_privilege('anon', 'public.parivar_profile_save(text,jsonb)', 'EXECUTE') THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'public CANNOT make links',
       CASE WHEN NOT has_function_privilege('anon', 'public.admin_parivar_create_profile_link(uuid,integer)', 'EXECUTE')
             AND NOT has_function_privilege('anon', 'public.my_parivar_profile_link(uuid)', 'EXECUTE') THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'bad token refused',
       CASE WHEN (public.parivar_profile_get(repeat('0', 64))->>'ok')::boolean = FALSE THEN 'yes' ELSE 'NO — tell Claude' END;


-- ===================== 257-parivar-member-cards.sql =====================
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


-- ===================== FINAL CHECK — every row should say yes =====================
SELECT 'db/253 contact designation + shop' AS part,
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='parivar_orgs' AND column_name='contact_role') THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL SELECT 'db/254 shop sync',
       CASE WHEN to_regprocedure('public.parivar_people_for_business(uuid)') IS NOT NULL THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL SELECT 'db/255 founded year / profession',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='parivar_orgs' AND column_name='founded_year') THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL SELECT 'db/256 member self-edit links',
       CASE WHEN to_regclass('public.parivar_profile_links') IS NOT NULL THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL SELECT 'db/257 member cards',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='parivar_org_roles' AND column_name='joined_year') THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL SELECT 'sample member (Lions Club Aks)',
       COALESCE((public.parivar_get_org('lions-club-aks')->'members'->0)::text, '(no members)');
