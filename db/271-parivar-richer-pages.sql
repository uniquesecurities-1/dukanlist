-- ============================================================
-- db/271 — Dabwali Parivar: richer person page + Parivar page
-- ============================================================
-- Deepak, 15 Oct (all suggestions accepted):
--   * parivar_get_person: each organisation also carries its logo and "member since" year
--   * parivar_search (organisations): the head this session (President → Chairman → Founder)
--   * parivar_overview(): counts for the top of the Parivar page (organisations, people,
--     upcoming events), the most common professions (for the quick-search chips), and the
--     people who joined most recently
-- Only fields are added; nothing private is exposed (mobile numbers are not in any of these).
-- Needs db/263 + db/270. Safe to re-run.

BEGIN;

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
               'org', o.name, 'org_slug', o.slug, 'org_logo', o.logo_url, 'role', r.role, 'role_label', r.role_label,
               'session', r.session, 'current', r.session = o.current_session,
               -- v388: "member since" for this organisation (joined year, else the first session)
               'since', (SELECT LEAST(MIN(r2.joined_year), MIN(left(r2.session, 4)::INT))
                           FROM parivar_org_roles r2 WHERE r2.org_id = o.id AND r2.person_id = p.id))
             ORDER BY (r.session = o.current_session) DESC, r.session DESC, (r.role = 'member'))
        FROM parivar_org_roles r JOIN parivar_orgs o ON o.id = r.org_id
       WHERE r.person_id = p.id AND o.status = 'active'), '[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.parivar_get_person(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_get_person(TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.parivar_search(p_q TEXT DEFAULT NULL, p_limit INT DEFAULT 40)
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  WITH q AS (
    SELECT NULLIF(btrim(COALESCE(p_q, '')), '') AS t
  ), tk AS (
    SELECT q.t,
           array_remove(regexp_split_to_array(lower(COALESCE(q.t, '')), '\s+'), '') AS toks,
           regexp_replace(lower(COALESCE(q.t, '')), '[[:space:][:punct:]]', '', 'g') AS flat
      FROM q
  ), people AS (
    SELECT p.id, p.slug, p.full_name, p.name_hi, p.photo_url, p.profession, p.mobile_verified_at,
           lower(concat_ws(' ', p.full_name, p.name_hi, p.profession,
                 (SELECT string_agg(COALESCE(b.name, f.firm_name), ' ')
                    FROM parivar_firm_roles f LEFT JOIN businesses b ON b.id = f.business_id
                   WHERE f.person_id = p.id))) AS hay
      FROM parivar_people p, tk
     WHERE p.status = 'active' AND tk.t IS NOT NULL
  ), hits AS (
    SELECT pe.*, (pe.full_name ILIKE '%' || tk.t || '%' OR COALESCE(pe.name_hi, '') ILIKE '%' || tk.t || '%') AS name_hit
      FROM people pe, tk
     WHERE NOT EXISTS (SELECT 1 FROM unnest(tk.toks) w
                        WHERE NOT (pe.hay LIKE '%' || w || '%'
                                   OR (char_length(w) >= 4 AND pe.hay LIKE '%' || left(w, char_length(w) - 1) || '%')))
        OR (char_length(tk.flat) >= 4 AND regexp_replace(pe.hay, '[[:space:][:punct:]]', '', 'g') LIKE '%' || tk.flat || '%')
  )
  SELECT COALESCE(jsonb_agg(r ORDER BY r->>'kind', (r->>'rank')::INT, r->>'name'), '[]'::jsonb) FROM (
    (SELECT jsonb_build_object('kind', 'org', 'rank', 0, 'slug', o.slug, 'name', o.name, 'name_hi', o.name_hi, 'org_kind', o.kind, 'logo', o.logo_url,
             -- v388: the head of the organisation this session (President, else Chairman, else Founder)
             'head', (SELECT jsonb_build_object('name', p.full_name, 'role', r.role, 'slug', p.slug)
                        FROM parivar_org_roles r JOIN parivar_people p ON p.id = r.person_id AND p.status = 'active'
                       WHERE r.org_id = o.id AND r.session = o.current_session AND r.role IN ('president', 'chairman', 'founder')
                       ORDER BY array_position(ARRAY['president','chairman','founder'], r.role) LIMIT 1),
             'members', (SELECT COUNT(DISTINCT person_id) FROM parivar_org_roles r WHERE r.org_id = o.id AND r.session = o.current_session)) AS r
       FROM parivar_orgs o, tk
      WHERE o.status = 'active'
        AND (tk.t IS NULL OR o.name ILIKE '%' || tk.t || '%' OR o.name_hi ILIKE '%' || tk.t || '%'))
    UNION ALL
    (SELECT jsonb_build_object('kind', 'person', 'rank', CASE WHEN h.name_hit THEN 0 ELSE 1 END,
             'slug', h.slug, 'name', h.full_name, 'name_hi', h.name_hi,
             'photo', h.photo_url, 'verified', h.mobile_verified_at IS NOT NULL, 'profession', h.profession,
             'line', (SELECT CASE WHEN r.role = 'member' THEN 'Member' ELSE initcap(replace(COALESCE(r.role_label, r.role), '_', ' ')) END || ', ' || o.name
                        FROM parivar_org_roles r JOIN parivar_orgs o ON o.id = r.org_id
                       WHERE r.person_id = h.id AND r.session = o.current_session AND o.status = 'active'
                       ORDER BY (r.role = 'member'), r.created_at LIMIT 1),
             'firms', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', COALESCE(b.name, f.firm_name),
                                         'slug', CASE WHEN b.status = 'active' THEN b.slug END,
                                         'role', f.role, 'role_label', f.role_label) ORDER BY (f.business_id IS NULL), f.created_at)
                                  FROM parivar_firm_roles f LEFT JOIN businesses b ON b.id = f.business_id
                                 WHERE f.person_id = h.id), '[]'::jsonb),
             'orgs', COALESCE((SELECT jsonb_agg(jsonb_build_object('org', o.name, 'slug', o.slug, 'role', x.role, 'role_label', x.role_label)
                                        ORDER BY (x.role = 'member'), o.name)
                                 FROM (SELECT DISTINCT ON (r.org_id) r.org_id, r.role, r.role_label
                                         FROM parivar_org_roles r JOIN parivar_orgs o2 ON o2.id = r.org_id
                                        WHERE r.person_id = h.id AND r.session = o2.current_session
                                        ORDER BY r.org_id, (r.role = 'member')) x
                                 JOIN parivar_orgs o ON o.id = x.org_id AND o.status = 'active'), '[]'::jsonb))
       FROM hits h
      ORDER BY (NOT h.name_hit), h.full_name
      LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 40), 100)))
  ) s(r);
$$;
REVOKE ALL ON FUNCTION public.parivar_search(TEXT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_search(TEXT, INT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.parivar_overview()
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT jsonb_build_object(
    'orgs',   (SELECT COUNT(*) FROM parivar_orgs WHERE status = 'active'),
    'people', (SELECT COUNT(*) FROM parivar_people WHERE status = 'active'),
    'events', (SELECT COUNT(*) FROM parivar_events e JOIN parivar_orgs o ON o.id = e.org_id
                WHERE e.status = 'approved' AND o.status = 'active' AND public._pv_event_upcoming(e.starts_at)),
    -- professions are stored as "A · B · C" — count each one
    'professions', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', x.name, 'n', x.n) ORDER BY x.n DESC, x.name)
                               FROM (SELECT btrim(t) AS name, COUNT(*) AS n
                                       FROM parivar_people p, unnest(string_to_array(p.profession, '·')) t
                                      WHERE p.status = 'active' AND btrim(COALESCE(t, '')) <> ''
                                      GROUP BY btrim(t) ORDER BY COUNT(*) DESC, btrim(t) LIMIT 14) x), '[]'::jsonb),
    'recent', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', p.full_name, 'slug', p.slug, 'photo', p.photo_url,
                                         'verified', p.mobile_verified_at IS NOT NULL, 'profession', p.profession,
                                         'org', (SELECT o.name FROM parivar_org_roles r JOIN parivar_orgs o ON o.id = r.org_id AND o.status = 'active'
                                                  WHERE r.person_id = p.id ORDER BY (r.role = 'member'), r.created_at LIMIT 1))
                                         ORDER BY p.created_at DESC)
                          FROM (SELECT * FROM parivar_people WHERE status = 'active' ORDER BY created_at DESC LIMIT 10) p), '[]'::jsonb));
$$;
REVOKE ALL ON FUNCTION public.parivar_overview() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_overview() TO anon, authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/271-parivar-richer-pages.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Checks — first two yes; the last shows the counts the Parivar page will show
SELECT 'person page: organisation logo + member since' AS check,
       CASE WHEN pg_get_functiondef('public.parivar_get_person(text)'::regprocedure) LIKE '%org_logo%' THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'organisation cards: head of the organisation',
       CASE WHEN pg_get_functiondef('public.parivar_search(text,integer)'::regprocedure) LIKE '%''head''%' THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'Parivar page counts',
       (SELECT (o->>'orgs') || ' organisations · ' || (o->>'people') || ' people · ' || (o->>'events') || ' events' FROM (SELECT public.parivar_overview() o) x);
