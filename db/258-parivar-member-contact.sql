-- ============================================================
-- db/258 — organisation page: Call / WhatsApp on each member card
-- ============================================================
-- Deepak, 13 Oct: put Call and WhatsApp right on the member card.
-- parivar_get_org now also returns contact_mode + mobile per member, using exactly the
-- rule of the person page (parivar_get_person): the number is sent only when the person's
-- contact setting is 'show' (Call + WhatsApp) or 'whatsapp' (WhatsApp only). 'hidden' → no number.
-- Needs db/257. Safe to re-run.

BEGIN;

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
               -- same rule as the person page: the number goes out only when the person allows it
               'contact_mode', CASE WHEN p.mobile IS NULL THEN 'hidden' ELSE p.contact_mode END,
               'mobile', CASE WHEN p.mobile IS NOT NULL AND p.contact_mode IN ('show', 'whatsapp') THEN p.mobile END,
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

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/258-parivar-member-contact.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Checks — first row yes; second shows how many members of each organisation can be contacted
SELECT 'member cards carry contact' AS check,
       CASE WHEN pg_get_functiondef('public.parivar_get_org(text)'::regprocedure) LIKE '%''contact_mode'', CASE WHEN p.mobile%' THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'Lions Club Aks: members with Call/WhatsApp',
       (SELECT count(*) FILTER (WHERE m->>'mobile' IS NOT NULL) || ' of ' || count(*)
          FROM jsonb_array_elements(public.parivar_get_org('lions-club-aks')->'members') m);
