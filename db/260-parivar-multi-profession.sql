-- ============================================================
-- db/260 — Dabwali Parivar: up to 3 professions per person
-- ============================================================
-- Deepak, 13 Oct: pick 2–3 professions from a searchable list.
-- The page saves them in the same profession column, joined with " · "
-- (e.g. "Mutual Fund Distributor · Insurance Advisor"), so search, cards and
-- the person page keep working unchanged. Only the length limit grows 60 → 150.
-- Redefines admin_parivar_upsert_person (from db/255) and parivar_profile_save
-- (from db/256) with exactly that one change. Safe to re-run.

BEGIN;

ALTER TABLE public.parivar_people DROP CONSTRAINT IF EXISTS parivar_people_profession_check;
ALTER TABLE public.parivar_people ADD CONSTRAINT parivar_people_profession_check CHECK (profession IS NULL OR length(profession) <= 150);

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
            NULLIF(left(btrim(COALESCE(p->>'profession', '')), 150), ''), 'admin', auth.uid())
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
      profession   = CASE WHEN p ? 'profession' THEN NULLIF(left(btrim(COALESCE(p->>'profession', '')), 150), '') ELSE profession END,
      status       = COALESCE(NULLIF(p->>'status', ''), status),
      updated_at   = NOW()
    WHERE id = v_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'person not found'; END IF;
  END IF;
  RETURN (SELECT jsonb_build_object('id', id, 'slug', slug) FROM parivar_people WHERE id = v_id);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_upsert_person(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_upsert_person(JSONB) TO authenticated;

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
    profession        = CASE WHEN p ? 'profession' THEN NULLIF(left(btrim(COALESCE(p->>'profession', '')), 150), '') ELSE profession END,
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

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/260-parivar-multi-profession.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Checks — all three should say yes
SELECT 'profession up to 150 characters' AS check,
       CASE WHEN pg_get_constraintdef((SELECT oid FROM pg_constraint WHERE conname = 'parivar_people_profession_check')) LIKE '%150%' THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'office form saves 3 professions',
       CASE WHEN pg_get_functiondef('public.admin_parivar_upsert_person(jsonb)'::regprocedure) LIKE '%150)%' THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'member link saves 3 professions',
       CASE WHEN pg_get_functiondef('public.parivar_profile_save(text,jsonb)'::regprocedure) LIKE '%150)%' THEN 'yes' ELSE 'NO — tell Claude' END;
