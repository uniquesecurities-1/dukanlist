-- ============================================================
-- db/263 — Dabwali Parivar: better search + fuller person cards
-- ============================================================
-- Deepak, 13 Oct:
--   * searching a firm ("masitan walon ki dukan") should find the person (Umesh Jindal)
--   * a person's search card should show their firm(s) and EVERY organisation they are in,
--     with any office position (President, Treasurer…) — not just one club
-- parivar_search (people part) now:
--   * matches name, Hindi name, profession AND their firm names (DukanList shop or typed firm)
--   * matches word by word in any order ("dukan masitan" works), a word may be one letter short
--     ("wala" finds "walon"), and also with spaces ignored ("masitanwalon")
--   * people whose NAME matches come first, then firm/profession matches
--   * returns 'firms' [{name, slug, role, role_label}] and 'orgs' [{org, slug, role, role_label}]
--     (current session, office bearers first); the old 'line' stays for older pages
-- Organisations part unchanged (+ logo from db/262). Safe to re-run.

BEGIN;

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

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/263-parivar-better-search.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Checks — a firm search should now find its owner; the card carries firms + all organisations
SELECT 'search "masitan" finds' AS check,
       COALESCE((SELECT string_agg(r->>'name', ', ') FROM jsonb_array_elements(public.parivar_search('masitan', 20)) r WHERE r->>'kind' = 'person'), '(nobody)') AS result
UNION ALL
SELECT 'search "dukan masita" finds',
       COALESCE((SELECT string_agg(r->>'name', ', ') FROM jsonb_array_elements(public.parivar_search('dukan masita', 20)) r WHERE r->>'kind' = 'person'), '(nobody)')
UNION ALL
SELECT 'Umesh card: firms + organisations',
       COALESCE((SELECT (r->'firms')::text || ' | ' || (r->'orgs')::text FROM jsonb_array_elements(public.parivar_search('umesh jindal', 5)) r WHERE r->>'kind' = 'person' LIMIT 1), '(not found)');
