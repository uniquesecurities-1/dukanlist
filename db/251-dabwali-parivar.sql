-- ============================================================
-- db/251 — Dabwali Parivar: people, sansthas, roles, firms
-- ============================================================
--
-- Deepak, 11 Oct: DukanList should hold Dabwali's PEOPLE too — each
-- person, the firms they run (founder / partner / proprietor …) and the
-- sansthas they belong to (president / secretary / member …), all
-- searchable by name.
--
-- PRIVACY RULES (agreed in chat, 11 Oct)
--   * The mobile number is kept for identity only. It is NEVER readable
--     through REST: the tables below are closed to anon/authenticated and
--     every public read goes through the parivar_* functions.
--   * Each person picks contact_mode:
--       show     — number + Call/WhatsApp on the page
--       whatsapp — WhatsApp button only, number not printed
--       hidden   — no contact at all (default)
--     A sanstha's official contact number is public on the sanstha page.
--   * People added by a sanstha/office without a number show as
--     "added by sanstha" (source <> 'self' and not verified).
--
-- ROLES CHANGE EVERY YEAR
--   Roles carry a session ('2026-27'). A sanstha has session_start_month
--   (4 = April, 7 = July for Lions/Rotary). admin_parivar_new_session()
--   copies the members into the new session and leaves the old rows as
--   history ("Past President 2025-26").
--
-- Phase 1 = the office (admins) enters sansthas + office bearers.
-- Self-registration and sanstha-admin panels come later; the columns
-- for them (auth_user_id, mobile_verified_at, parivar_org_admins) are
-- here already so nothing has to be migrated twice.
-- Safe to re-run.
-- ============================================================

BEGIN;

-- 1. tables ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.parivar_people (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug               TEXT NOT NULL UNIQUE,
  full_name          TEXT NOT NULL CHECK (length(btrim(full_name)) BETWEEN 2 AND 80),
  name_hi            TEXT,
  city_id            INT REFERENCES public.geo_cities(id),
  mobile             TEXT CHECK (mobile IS NULL OR mobile ~ '^[6-9][0-9]{9}$'),
  mobile_verified_at TIMESTAMPTZ,
  contact_mode       TEXT NOT NULL DEFAULT 'hidden' CHECK (contact_mode IN ('show', 'whatsapp', 'hidden')),
  photo_url          TEXT CHECK (photo_url IS NULL OR photo_url ~ '^https://res\.cloudinary\.com/'),
  bio                TEXT CHECK (bio IS NULL OR length(bio) <= 300),
  auth_user_id       UUID UNIQUE,
  source             TEXT NOT NULL DEFAULT 'admin' CHECK (source IN ('self', 'sanstha', 'admin')),
  status             TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'hidden')),
  added_by           UUID,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_parivar_people_mobile ON public.parivar_people (mobile) WHERE mobile IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_parivar_people_name ON public.parivar_people (lower(full_name));

CREATE TABLE IF NOT EXISTS public.parivar_orgs (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug                TEXT NOT NULL UNIQUE,
  name                TEXT NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 120),
  name_hi             TEXT,
  kind                TEXT NOT NULL DEFAULT 'samajik'
                      CHECK (kind IN ('seva', 'vyapar', 'dharmik', 'shiksha', 'khel', 'samajik', 'professional', 'other')),
  city_id             INT REFERENCES public.geo_cities(id),
  about               TEXT CHECK (about IS NULL OR length(about) <= 1000),
  logo_url            TEXT CHECK (logo_url IS NULL OR logo_url ~ '^https://res\.cloudinary\.com/'),
  contact_name        TEXT,
  contact_mobile      TEXT CHECK (contact_mobile IS NULL OR contact_mobile ~ '^[6-9][0-9]{9}$'),
  session_start_month INT NOT NULL DEFAULT 4 CHECK (session_start_month BETWEEN 1 AND 12),
  current_session     TEXT NOT NULL CHECK (current_session ~ '^[0-9]{4}-[0-9]{2}$'),
  status              TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'hidden')),
  added_by            UUID,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_parivar_orgs_name ON public.parivar_orgs (lower(name));

-- one row per person per role per session
CREATE TABLE IF NOT EXISTS public.parivar_org_roles (
  id           BIGSERIAL PRIMARY KEY,
  org_id       UUID NOT NULL REFERENCES public.parivar_orgs(id) ON DELETE CASCADE,
  person_id    UUID NOT NULL REFERENCES public.parivar_people(id) ON DELETE CASCADE,
  role         TEXT NOT NULL DEFAULT 'member'
               CHECK (role IN ('president', 'vice_president', 'secretary', 'joint_secretary', 'treasurer',
                               'pro', 'patron', 'chairman', 'director', 'coordinator', 'member', 'other')),
  role_label   TEXT CHECK (role_label IS NULL OR length(role_label) <= 40),
  session      TEXT NOT NULL CHECK (session ~ '^[0-9]{4}-[0-9]{2}$'),
  confirmed_at TIMESTAMPTZ,
  added_by     UUID,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (org_id, person_id, session, role)
);
CREATE INDEX IF NOT EXISTS idx_parivar_roles_org ON public.parivar_org_roles (org_id, session);
CREATE INDEX IF NOT EXISTS idx_parivar_roles_person ON public.parivar_org_roles (person_id);

-- firms: a DukanList listing (business_id) or a firm not listed yet (firm_name)
CREATE TABLE IF NOT EXISTS public.parivar_firm_roles (
  id          BIGSERIAL PRIMARY KEY,
  person_id   UUID NOT NULL REFERENCES public.parivar_people(id) ON DELETE CASCADE,
  business_id UUID REFERENCES public.businesses(id) ON DELETE SET NULL,
  firm_name   TEXT CHECK (firm_name IS NULL OR length(btrim(firm_name)) BETWEEN 2 AND 120),
  role        TEXT NOT NULL DEFAULT 'owner'
              CHECK (role IN ('founder', 'owner', 'proprietor', 'partner', 'director', 'ceo', 'manager', 'other')),
  role_label  TEXT CHECK (role_label IS NULL OR length(role_label) <= 40),
  added_by    UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (business_id IS NOT NULL OR firm_name IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_parivar_firms_person ON public.parivar_firm_roles (person_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_parivar_firm_biz ON public.parivar_firm_roles (person_id, business_id) WHERE business_id IS NOT NULL;

-- later: sanstha admins who may edit their own sanstha
CREATE TABLE IF NOT EXISTS public.parivar_org_admins (
  org_id       UUID NOT NULL REFERENCES public.parivar_orgs(id) ON DELETE CASCADE,
  auth_user_id UUID NOT NULL,
  granted_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (org_id, auth_user_id)
);

-- closed to REST — reads and writes go through the functions below
ALTER TABLE public.parivar_people     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parivar_orgs       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parivar_org_roles  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parivar_firm_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parivar_org_admins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.parivar_people, public.parivar_orgs, public.parivar_org_roles,
              public.parivar_firm_roles, public.parivar_org_admins FROM anon, authenticated;

-- 2. helpers -------------------------------------------------------------
-- '2026-27' for a date and a session start month
CREATE OR REPLACE FUNCTION public._parivar_session_for(p_start_month INT, p_at DATE DEFAULT CURRENT_DATE)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN EXTRACT(MONTH FROM p_at)::INT >= COALESCE(p_start_month, 4)
              THEN EXTRACT(YEAR FROM p_at)::INT ELSE EXTRACT(YEAR FROM p_at)::INT - 1 END::TEXT
         || '-' || lpad(((CASE WHEN EXTRACT(MONTH FROM p_at)::INT >= COALESCE(p_start_month, 4)
              THEN EXTRACT(YEAR FROM p_at)::INT ELSE EXTRACT(YEAR FROM p_at)::INT - 1 END + 1) % 100)::TEXT, 2, '0');
$$;

-- url-safe slug, unique within the given table
CREATE OR REPLACE FUNCTION public._parivar_slug(p_text TEXT, p_table TEXT)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE base TEXT; s TEXT; n INT := 1; taken BOOLEAN;
BEGIN
  base := trim(BOTH '-' FROM regexp_replace(lower(COALESCE(p_text, '')), '[^a-z0-9]+', '-', 'g'));
  IF length(base) < 3 THEN base := 'p-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6); END IF;
  base := left(base, 60);
  s := base;
  LOOP
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I WHERE slug = $1)', p_table) INTO taken USING s;
    EXIT WHEN NOT taken;
    n := n + 1; s := base || '-' || n;
  END LOOP;
  RETURN s;
END $$;

CREATE OR REPLACE FUNCTION public._parivar_mobile(p TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN length(d) = 12 AND left(d, 2) = '91' THEN right(d, 10)
              WHEN length(d) = 11 AND left(d, 1) = '0' THEN right(d, 10)
              WHEN length(d) = 10 THEN d END
  FROM (SELECT regexp_replace(COALESCE(p, ''), '\D', '', 'g') AS d) x;
$$;

-- 3. public reads (no mobile unless the person chose to show it) -----------
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
                       ORDER BY (r.role = 'member'), r.created_at LIMIT 1))
      FROM parivar_people p, q
     WHERE p.status = 'active' AND q.t IS NOT NULL
       AND (p.full_name ILIKE '%' || q.t || '%' OR p.name_hi ILIKE '%' || q.t || '%')
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 40), 100))
  ) s(r);
$$;

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
    'photo', p.photo_url, 'bio', p.bio,
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
    'contact_name', o.contact_name, 'contact_mobile', o.contact_mobile,
    'bearers', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('role', r.role, 'role_label', r.role_label, 'name', p.full_name,
                                          'slug', p.slug, 'photo', p.photo_url, 'verified', p.mobile_verified_at IS NOT NULL)
             ORDER BY array_position(ARRAY['patron','chairman','president','vice_president','secretary','joint_secretary',
                                           'treasurer','pro','director','coordinator','other'], r.role), p.full_name)
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

REVOKE ALL ON FUNCTION public.parivar_search(TEXT, INT), public.parivar_get_person(TEXT), public.parivar_get_org(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_search(TEXT, INT), public.parivar_get_person(TEXT), public.parivar_get_org(TEXT) TO anon, authenticated;

-- 4. office (admin) writes ---------------------------------------------------
-- p: {id?, full_name, name_hi?, mobile?, contact_mode?, bio?, photo_url?, city_id?, status?}
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
    INSERT INTO parivar_people (slug, full_name, name_hi, city_id, mobile, contact_mode, photo_url, bio, source, added_by)
    VALUES (v_slug, btrim(p->>'full_name'), NULLIF(btrim(COALESCE(p->>'name_hi', '')), ''), v_city, v_mob,
            COALESCE(NULLIF(p->>'contact_mode', ''), 'hidden'), NULLIF(p->>'photo_url', ''), NULLIF(btrim(COALESCE(p->>'bio', '')), ''),
            'admin', auth.uid())
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
      status       = COALESCE(NULLIF(p->>'status', ''), status),
      updated_at   = NOW()
    WHERE id = v_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'person not found'; END IF;
  END IF;
  RETURN (SELECT jsonb_build_object('id', id, 'slug', slug) FROM parivar_people WHERE id = v_id);
END $$;

-- p: {id?, name, name_hi?, kind?, about?, contact_name?, contact_mobile?, session_start_month?, logo_url?, city_id?, status?}
CREATE OR REPLACE FUNCTION public.admin_parivar_upsert_org(p JSONB)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE v_id UUID := NULLIF(p->>'id', '')::UUID; v_mob TEXT; v_month INT; v_city INT;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  v_mob := public._parivar_mobile(p->>'contact_mobile');
  IF COALESCE(p->>'contact_mobile', '') <> '' AND v_mob IS NULL THEN RAISE EXCEPTION 'contact mobile must be 10 digits'; END IF;
  v_month := COALESCE(NULLIF(p->>'session_start_month', '')::INT, 4);
  v_city := COALESCE(NULLIF(p->>'city_id', '')::INT, (SELECT id FROM geo_cities WHERE name ILIKE 'mandi dabwali' LIMIT 1));
  IF v_id IS NULL THEN
    INSERT INTO parivar_orgs (slug, name, name_hi, kind, city_id, about, logo_url, contact_name, contact_mobile,
                              session_start_month, current_session, added_by)
    VALUES (public._parivar_slug(p->>'name', 'parivar_orgs'), btrim(p->>'name'),
            NULLIF(btrim(COALESCE(p->>'name_hi', '')), ''), COALESCE(NULLIF(p->>'kind', ''), 'samajik'), v_city,
            NULLIF(btrim(COALESCE(p->>'about', '')), ''), NULLIF(p->>'logo_url', ''),
            NULLIF(btrim(COALESCE(p->>'contact_name', '')), ''), v_mob,
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
      contact_name   = CASE WHEN p ? 'contact_name' THEN NULLIF(btrim(COALESCE(p->>'contact_name', '')), '') ELSE contact_name END,
      contact_mobile = CASE WHEN p ? 'contact_mobile' THEN v_mob ELSE contact_mobile END,
      session_start_month = CASE WHEN p ? 'session_start_month' THEN v_month ELSE session_start_month END,
      status         = COALESCE(NULLIF(p->>'status', ''), status),
      updated_at     = NOW()
    WHERE id = v_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'sanstha not found'; END IF;
  END IF;
  RETURN (SELECT jsonb_build_object('id', id, 'slug', slug, 'session', current_session) FROM parivar_orgs WHERE id = v_id);
END $$;

-- add / change a role in the sanstha's current session (or a given one)
CREATE OR REPLACE FUNCTION public.admin_parivar_set_role(p_org_id UUID, p_person_id UUID, p_role TEXT,
                                                        p_role_label TEXT DEFAULT NULL, p_session TEXT DEFAULT NULL)
RETURNS BIGINT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE v_session TEXT; v_id BIGINT;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT COALESCE(NULLIF(p_session, ''), current_session) INTO v_session FROM parivar_orgs WHERE id = p_org_id;
  IF v_session IS NULL THEN RAISE EXCEPTION 'sanstha not found'; END IF;
  -- a person holds one role per sanstha per session: replace, don't stack
  DELETE FROM parivar_org_roles WHERE org_id = p_org_id AND person_id = p_person_id AND session = v_session;
  INSERT INTO parivar_org_roles (org_id, person_id, role, role_label, session, added_by)
  VALUES (p_org_id, p_person_id, COALESCE(NULLIF(p_role, ''), 'member'), NULLIF(btrim(COALESCE(p_role_label, '')), ''), v_session, auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.admin_parivar_remove_role(p_role_id BIGINT)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  DELETE FROM parivar_org_roles WHERE id = p_role_id;
  RETURN FOUND;
END $$;

-- new session: everyone carries over as a member; office bearers are set again
CREATE OR REPLACE FUNCTION public.admin_parivar_new_session(p_org_id UUID, p_session TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE o parivar_orgs; v_new TEXT; v_n INT;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO o FROM parivar_orgs WHERE id = p_org_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'sanstha not found'; END IF;
  v_new := COALESCE(NULLIF(p_session, ''), left(o.current_session, 4)::INT + 1 || '-' || lpad(((left(o.current_session, 4)::INT + 2) % 100)::TEXT, 2, '0'));
  IF v_new !~ '^[0-9]{4}-[0-9]{2}$' OR v_new <= o.current_session THEN RAISE EXCEPTION 'new session must be after %', o.current_session; END IF;
  INSERT INTO parivar_org_roles (org_id, person_id, role, session, confirmed_at, added_by)
  SELECT DISTINCT ON (person_id) org_id, person_id, 'member', v_new, confirmed_at, auth.uid()
    FROM parivar_org_roles WHERE org_id = p_org_id AND session = o.current_session
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  UPDATE parivar_orgs SET current_session = v_new, updated_at = NOW() WHERE id = p_org_id;
  RETURN jsonb_build_object('session', v_new, 'carried_over', v_n);
END $$;

-- firm link: a DukanList listing (business_id) or a plain name
CREATE OR REPLACE FUNCTION public.admin_parivar_add_firm(p_person_id UUID, p_business_id UUID, p_firm_name TEXT,
                                                        p_role TEXT DEFAULT 'owner', p_role_label TEXT DEFAULT NULL)
RETURNS BIGINT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE v_id BIGINT;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF p_business_id IS NULL AND length(btrim(COALESCE(p_firm_name, ''))) < 2 THEN RAISE EXCEPTION 'firm name or listing required'; END IF;
  IF p_business_id IS NOT NULL THEN
    DELETE FROM parivar_firm_roles WHERE person_id = p_person_id AND business_id = p_business_id;
  END IF;
  INSERT INTO parivar_firm_roles (person_id, business_id, firm_name, role, role_label, added_by)
  VALUES (p_person_id, p_business_id, CASE WHEN p_business_id IS NULL THEN btrim(p_firm_name) END,
          COALESCE(NULLIF(p_role, ''), 'owner'), NULLIF(btrim(COALESCE(p_role_label, '')), ''), auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.admin_parivar_remove_firm(p_id BIGINT)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  DELETE FROM parivar_firm_roles WHERE id = p_id;
  RETURN FOUND;
END $$;

-- admin read: full rows incl. mobile, for the office screens
CREATE OR REPLACE FUNCTION public.admin_parivar_get(p_kind TEXT, p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF p_kind = 'org' THEN
    RETURN (SELECT to_jsonb(o) || jsonb_build_object('roles', COALESCE((
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

-- admin list: everything, newest first (people include mobile for the office)
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
                     'contact_mode', p.contact_mode, 'status', p.status, 'verified', p.mobile_verified_at IS NOT NULL)
                     ORDER BY p.full_name)
                   FROM (SELECT * FROM parivar_people
                          WHERE NULLIF(btrim(COALESCE(p_q, '')), '') IS NULL
                             OR full_name ILIKE '%' || btrim(p_q) || '%'
                             OR (length(regexp_replace(p_q, '\D', '', 'g')) >= 4 AND mobile LIKE '%' || regexp_replace(p_q, '\D', '', 'g') || '%')
                          ORDER BY full_name LIMIT 300) p), '[]'::jsonb);
END $$;

DO $$
DECLARE f TEXT;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.admin_parivar_upsert_person(jsonb)', 'public.admin_parivar_upsert_org(jsonb)',
    'public.admin_parivar_set_role(uuid,uuid,text,text,text)', 'public.admin_parivar_remove_role(bigint)',
    'public.admin_parivar_new_session(uuid,text)', 'public.admin_parivar_add_firm(uuid,uuid,text,text,text)',
    'public.admin_parivar_remove_firm(bigint)', 'public.admin_parivar_get(text,uuid)', 'public.admin_parivar_list(text,text)'
  ] LOOP
    EXECUTE 'REVOKE ALL ON FUNCTION ' || f || ' FROM PUBLIC, anon';
    EXECUTE 'GRANT EXECUTE ON FUNCTION ' || f || ' TO authenticated';
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public._parivar_slug(text, text) FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/251-dabwali-parivar.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- Checks — every row should say yes
-- ============================================================
SELECT 'tables created' AS check,
       CASE WHEN to_regclass('public.parivar_people') IS NOT NULL AND to_regclass('public.parivar_orgs') IS NOT NULL
             AND to_regclass('public.parivar_org_roles') IS NOT NULL AND to_regclass('public.parivar_firm_roles') IS NOT NULL
            THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'mobile NOT readable by the public',
       CASE WHEN NOT has_table_privilege('anon', 'public.parivar_people', 'SELECT')
             AND NOT has_column_privilege('anon', 'public.parivar_people', 'mobile', 'SELECT')
             AND NOT has_column_privilege('authenticated', 'public.parivar_people', 'mobile', 'SELECT')
            THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'public can search + open pages',
       CASE WHEN has_function_privilege('anon', 'public.parivar_search(text,integer)', 'EXECUTE')
             AND has_function_privilege('anon', 'public.parivar_get_person(text)', 'EXECUTE')
             AND has_function_privilege('anon', 'public.parivar_get_org(text)', 'EXECUTE')
            THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'public CANNOT write',
       CASE WHEN NOT has_function_privilege('anon', 'public.admin_parivar_upsert_person(jsonb)', 'EXECUTE')
             AND NOT has_function_privilege('anon', 'public.admin_parivar_set_role(uuid,uuid,text,text,text)', 'EXECUTE')
            THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'session for today (April start / July start)',
       public._parivar_session_for(4) || ' / ' || public._parivar_session_for(7);
