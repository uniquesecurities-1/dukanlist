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
