-- ============================================================
-- db/262 — Dabwali Parivar: organisation logos in lists
-- ============================================================
-- Deepak, 13 Oct: the /parivar page (and the home banner) showed initials ("BN", "LA")
-- even though the organisations have logos. parivar_search now also returns 'logo'.
-- Only that one field is added. Safe to re-run.

BEGIN;

CREATE OR REPLACE FUNCTION public.parivar_search(p_q TEXT DEFAULT NULL, p_limit INT DEFAULT 40)
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  WITH q AS (SELECT NULLIF(btrim(COALESCE(p_q, '')), '') AS t)
  SELECT COALESCE(jsonb_agg(r ORDER BY r->>'kind', r->>'name'), '[]'::jsonb) FROM (
    SELECT jsonb_build_object('kind', 'org', 'slug', o.slug, 'name', o.name, 'name_hi', o.name_hi, 'org_kind', o.kind, 'logo', o.logo_url,
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
REVOKE ALL ON FUNCTION public.parivar_search(TEXT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_search(TEXT, INT) TO anon, authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/262-parivar-org-logos.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Check — shows each organisation and whether a logo is set
SELECT r->>'name' AS organisation, CASE WHEN r->>'logo' IS NOT NULL THEN 'logo ✓' ELSE 'no logo yet' END AS result
  FROM jsonb_array_elements(public.parivar_search(NULL, 100)) r
 WHERE r->>'kind' = 'org';
