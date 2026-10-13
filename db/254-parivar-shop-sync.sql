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
