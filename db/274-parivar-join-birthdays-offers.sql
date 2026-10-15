-- ============================================================
-- db/274 — Dabwali Parivar phase 3: join form · birthdays (opt-in) · member offers
-- ============================================================
-- Deepak, 15 Oct (phase 3):
--   1. "परिवार से जुड़िए" — anyone can ask to be added (name, mobile, profession, organisation,
--      business, how the number shows, birthday if they want). It waits for the office;
--      on approval the person is created (or matched by mobile), added to the organisation as a
--      member (the office sets any post), and a DukanList shop on the same number is linked.
--      Spam guard: one waiting request per mobile, 30 waiting in total max per day.
--   2. Birthdays — only day + month, only when the person ticks "show my birthday"
--      (on the join form or their own profile link). "आज जन्मदिन है" on the Parivar page.
--   3. सदस्य ऑफर — a DukanList shop gives members of an organisation (or all of Dabwali Parivar)
--      an offer, e.g. "10% छूट". The office adds them; they show on the organisation page,
--      on the shop's page and on the Parivar page until their end date.
-- Needs db/261 + db/271. Safe to re-run.

BEGIN;

ALTER TABLE public.parivar_people ADD COLUMN IF NOT EXISTS birth_month SMALLINT;
ALTER TABLE public.parivar_people ADD COLUMN IF NOT EXISTS birth_day SMALLINT;
ALTER TABLE public.parivar_people ADD COLUMN IF NOT EXISTS birthday_public BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.parivar_people DROP CONSTRAINT IF EXISTS parivar_people_birthday_check;
ALTER TABLE public.parivar_people ADD CONSTRAINT parivar_people_birthday_check
  CHECK ((birth_month IS NULL AND birth_day IS NULL) OR (birth_month BETWEEN 1 AND 12 AND birth_day BETWEEN 1 AND 31));

CREATE TABLE IF NOT EXISTS public.parivar_join_requests (
  id           BIGSERIAL PRIMARY KEY,
  full_name    TEXT        NOT NULL CHECK (length(btrim(full_name)) BETWEEN 2 AND 80),
  mobile       TEXT        NOT NULL CHECK (mobile ~ '^[6-9][0-9]{9}$'),
  profession   TEXT        CHECK (profession IS NULL OR length(profession) <= 150),
  org_id       UUID        REFERENCES public.parivar_orgs(id) ON DELETE SET NULL,
  org_other    TEXT        CHECK (org_other IS NULL OR length(org_other) <= 120),
  role_wanted  TEXT        CHECK (role_wanted IS NULL OR length(role_wanted) <= 40),
  business     TEXT        CHECK (business IS NULL OR length(business) <= 120),
  contact_mode TEXT        NOT NULL DEFAULT 'whatsapp' CHECK (contact_mode IN ('show', 'whatsapp', 'hidden')),
  birthday     TEXT        CHECK (birthday IS NULL OR birthday ~ '^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'),
  birthday_public BOOLEAN  NOT NULL DEFAULT FALSE,
  status       TEXT        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  person_id    UUID,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  decided_at   TIMESTAMPTZ,
  decided_by   UUID
);
CREATE INDEX IF NOT EXISTS idx_pv_join_status ON public.parivar_join_requests (status, created_at DESC);
ALTER TABLE public.parivar_join_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.parivar_join_requests FROM anon, authenticated;

CREATE TABLE IF NOT EXISTS public.parivar_member_offers (
  id          BIGSERIAL PRIMARY KEY,
  business_id UUID        NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
  org_id      UUID        REFERENCES public.parivar_orgs(id) ON DELETE CASCADE,   -- NULL = every Dabwali Parivar member
  offer_text  TEXT        NOT NULL CHECK (length(btrim(offer_text)) BETWEEN 3 AND 140),
  valid_until DATE        NOT NULL,
  status      TEXT        NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'removed')),
  created_by  UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_pv_offers ON public.parivar_member_offers (status, valid_until);
ALTER TABLE public.parivar_member_offers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.parivar_member_offers FROM anon, authenticated;

-- ---------- 1. join form ----------
CREATE OR REPLACE FUNCTION public.parivar_join(p JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_mob TEXT; v_name TEXT; v_org UUID; v_bday TEXT; v_id BIGINT;
BEGIN
  IF COALESCE(p->>'website', '') <> '' THEN RETURN jsonb_build_object('ok', TRUE); END IF;   -- bots fill the hidden field
  v_name := btrim(COALESCE(p->>'full_name', ''));
  IF length(v_name) < 2 OR length(v_name) > 80 OR v_name ~ '[0-9]' THEN RAISE EXCEPTION 'पूरा नाम लिखें।'; END IF;
  v_mob := public._parivar_mobile(p->>'mobile');
  IF v_mob IS NULL OR v_mob !~ '^[6-9][0-9]{9}$' THEN RAISE EXCEPTION '10 अंकों का मोबाइल नंबर लिखें।'; END IF;
  IF EXISTS (SELECT 1 FROM parivar_join_requests WHERE mobile = v_mob AND status = 'pending') THEN
    RAISE EXCEPTION 'इस नंबर से request पहले से भेजी हुई है — हम जल्दी ही जोड़ देंगे।';
  END IF;
  IF (SELECT COUNT(*) FROM parivar_join_requests WHERE status = 'pending' AND created_at > NOW() - INTERVAL '1 day') >= 30 THEN
    RAISE EXCEPTION 'आज बहुत requests आ चुकी हैं — कल फिर कोशिश करें या हेल्पलाइन पर WhatsApp करें।';
  END IF;
  v_org := (SELECT id FROM parivar_orgs WHERE id::text = NULLIF(p->>'org_id', '') AND status = 'active');
  v_bday := NULLIF(p->>'birthday', '');
  IF v_bday IS NOT NULL AND v_bday !~ '^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$' THEN v_bday := NULL; END IF;
  INSERT INTO parivar_join_requests (full_name, mobile, profession, org_id, org_other, role_wanted, business, contact_mode, birthday, birthday_public)
  VALUES (v_name, v_mob, NULLIF(left(btrim(COALESCE(p->>'profession', '')), 150), ''), v_org,
          CASE WHEN v_org IS NULL THEN NULLIF(left(btrim(COALESCE(p->>'org_other', '')), 120), '') END,
          NULLIF(left(btrim(COALESCE(p->>'role_wanted', '')), 40), ''), NULLIF(left(btrim(COALESCE(p->>'business', '')), 120), ''),
          CASE WHEN p->>'contact_mode' IN ('show', 'whatsapp', 'hidden') THEN p->>'contact_mode' ELSE 'whatsapp' END,
          v_bday, v_bday IS NOT NULL AND COALESCE((p->>'birthday_public')::boolean, FALSE))
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', TRUE, 'id', v_id);
END $$;
REVOKE ALL ON FUNCTION public.parivar_join(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_join(JSONB) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_join_requests()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id', j.id, 'name', j.full_name, 'mobile', j.mobile, 'profession', j.profession,
                                   'org_id', j.org_id, 'org', o.name, 'org_other', j.org_other, 'role_wanted', j.role_wanted, 'business', j.business,
                                   'contact_mode', j.contact_mode, 'birthday', j.birthday, 'birthday_public', j.birthday_public, 'at', j.created_at,
                                   'existing', (SELECT jsonb_build_object('name', p.full_name, 'slug', p.slug) FROM parivar_people p WHERE p.mobile = j.mobile),
                                   'shops', (SELECT jsonb_agg(b.name) FROM businesses b WHERE b.status = 'active'
                                               AND (right(regexp_replace(COALESCE(b.mobile, ''), '\D', '', 'g'), 10) = j.mobile
                                                 OR right(regexp_replace(COALESCE(b.whatsapp, ''), '\D', '', 'g'), 10) = j.mobile)))
                                   ORDER BY j.created_at)
                    FROM parivar_join_requests j LEFT JOIN parivar_orgs o ON o.id = j.org_id WHERE j.status = 'pending'), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_join_requests() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_join_requests() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_join_decide(p_id BIGINT, p_approve BOOLEAN)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE j parivar_join_requests; v_pid UUID; v_new BOOLEAN := FALSE; o parivar_orgs; v_biz UUID; n_shops INT := 0;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO j FROM parivar_join_requests WHERE id = p_id FOR UPDATE;
  IF j.id IS NULL THEN RAISE EXCEPTION 'request not found'; END IF;
  IF j.status <> 'pending' THEN RAISE EXCEPTION 'already %', j.status; END IF;
  IF NOT p_approve THEN
    UPDATE parivar_join_requests SET status = 'rejected', decided_at = NOW(), decided_by = auth.uid() WHERE id = j.id;
    RETURN jsonb_build_object('ok', TRUE, 'status', 'rejected');
  END IF;
  SELECT id INTO v_pid FROM parivar_people WHERE mobile = j.mobile;
  IF v_pid IS NULL THEN
    INSERT INTO parivar_people (slug, full_name, city_id, mobile, contact_mode, profession, source, added_by, birth_month, birth_day, birthday_public)
    VALUES (public._parivar_slug(j.full_name, 'parivar_people'), j.full_name,
            (SELECT id FROM geo_cities WHERE name ILIKE 'mandi dabwali' LIMIT 1), j.mobile, j.contact_mode, j.profession, 'self', auth.uid(),
            CASE WHEN j.birthday IS NOT NULL THEN split_part(j.birthday, '-', 1)::INT END,
            CASE WHEN j.birthday IS NOT NULL THEN split_part(j.birthday, '-', 2)::INT END, j.birthday_public)
    RETURNING id INTO v_pid; v_new := TRUE;
  ELSE
    UPDATE parivar_people SET profession = COALESCE(profession, j.profession),
           birth_month = COALESCE(birth_month, CASE WHEN j.birthday IS NOT NULL THEN split_part(j.birthday, '-', 1)::INT END),
           birth_day = COALESCE(birth_day, CASE WHEN j.birthday IS NOT NULL THEN split_part(j.birthday, '-', 2)::INT END),
           birthday_public = birthday_public OR j.birthday_public, updated_at = NOW()
     WHERE id = v_pid;
  END IF;
  IF j.org_id IS NOT NULL THEN
    SELECT * INTO o FROM parivar_orgs WHERE id = j.org_id;
    IF o.id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM parivar_org_roles WHERE org_id = o.id AND person_id = v_pid AND session = o.current_session) THEN
      INSERT INTO parivar_org_roles (org_id, person_id, role, session, added_by) VALUES (o.id, v_pid, 'member', o.current_session, auth.uid());
    END IF;
  END IF;
  FOR v_biz IN SELECT b.id FROM businesses b WHERE b.status = 'active'
                 AND (right(regexp_replace(COALESCE(b.mobile, ''), '\D', '', 'g'), 10) = j.mobile
                   OR right(regexp_replace(COALESCE(b.whatsapp, ''), '\D', '', 'g'), 10) = j.mobile)
                 AND NOT EXISTS (SELECT 1 FROM parivar_firm_roles f WHERE f.person_id = v_pid AND f.business_id = b.id) LOOP
    INSERT INTO parivar_firm_roles (person_id, business_id, role, added_by) VALUES (v_pid, v_biz, 'owner', auth.uid()); n_shops := n_shops + 1;
  END LOOP;
  IF n_shops = 0 AND j.business IS NOT NULL AND NOT EXISTS (SELECT 1 FROM parivar_firm_roles WHERE person_id = v_pid) THEN
    INSERT INTO parivar_firm_roles (person_id, firm_name, role, added_by) VALUES (v_pid, j.business, 'owner', auth.uid());
  END IF;
  UPDATE parivar_join_requests SET status = 'approved', person_id = v_pid, decided_at = NOW(), decided_by = auth.uid() WHERE id = j.id;
  RETURN jsonb_build_object('ok', TRUE, 'status', 'approved', 'person_id', v_pid, 'new', v_new, 'shops_linked', n_shops,
                            'slug', (SELECT slug FROM parivar_people WHERE id = v_pid), 'role_wanted', j.role_wanted, 'org_id', j.org_id);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_join_decide(BIGINT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_join_decide(BIGINT, BOOLEAN) TO authenticated;

-- public list of organisations for the join form
CREATE OR REPLACE FUNCTION public.parivar_org_names()
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'name_hi', name_hi) ORDER BY name), '[]'::jsonb) FROM parivar_orgs WHERE status = 'active';
$$;
REVOKE ALL ON FUNCTION public.parivar_org_names() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_org_names() TO anon, authenticated;

-- ---------- 2. birthdays ----------
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
    'birthday', CASE WHEN p.birth_month IS NOT NULL THEN lpad(p.birth_month::text, 2, '0') || '-' || lpad(p.birth_day::text, 2, '0') END,
    'birthday_public', p.birthday_public,
    'firms', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', COALESCE(b.name, f.firm_name), 'role', f.role, 'role_label', f.role_label))
                         FROM parivar_firm_roles f LEFT JOIN businesses b ON b.id = f.business_id WHERE f.person_id = p.id), '[]'::jsonb),
    'roles', COALESCE((SELECT jsonb_agg(jsonb_build_object('org', o.name, 'role', r.role, 'role_label', r.role_label, 'session', r.session)
                                ORDER BY r.session DESC)
                         FROM parivar_org_roles r JOIN parivar_orgs o ON o.id = r.org_id
                        WHERE r.person_id = p.id AND r.session = o.current_session), '[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.parivar_profile_get(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_profile_get(TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.parivar_profile_save(p_token TEXT, p JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE l parivar_profile_links; v parivar_people; v_photo TEXT; v_note TEXT; v_bm INT; v_bd INT;
BEGIN
  l := public._parivar_live_link(p_token);
  IF l.id IS NULL THEN RAISE EXCEPTION 'This link has expired. Please ask DukanList for a new one.'; END IF;
  IF l.uses >= 30 THEN RAISE EXCEPTION 'This link has been used too many times. Please ask DukanList for a new one.'; END IF;
  IF l.last_used_at IS NOT NULL AND l.last_used_at > NOW() - INTERVAL '10 seconds' THEN RAISE EXCEPTION 'Please wait a few seconds and try again.'; END IF;
  SELECT * INTO v FROM parivar_people WHERE id = l.person_id FOR UPDATE;

  v_photo := NULLIF(p->>'photo', '');
  -- v370: a bad photo address is now an error the member sees, not silently dropped
  IF v_photo IS NOT NULL AND v_photo !~ '^https://res\.cloudinary\.com/dukanlist/image/upload/[A-Za-z0-9_,./:@%()-]+$' THEN
    RAISE EXCEPTION 'The photo could not be accepted. Please choose the photo again.';
  END IF;
  v_note := NULLIF(left(btrim(COALESCE(p->>'note', '')), 500), '');
  -- v393: birthday — day and month only ("MM-DD"); shown only if the member says so
  IF p ? 'birthday' AND NULLIF(p->>'birthday', '') IS NOT NULL THEN
    IF p->>'birthday' !~ '^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$' THEN RAISE EXCEPTION 'Please choose the birthday again.'; END IF;
    v_bm := split_part(p->>'birthday', '-', 1)::INT; v_bd := split_part(p->>'birthday', '-', 2)::INT;
    IF v_bd > (ARRAY[31,29,31,30,31,30,31,31,30,31,30,31])[v_bm] THEN RAISE EXCEPTION 'Please choose the birthday again.'; END IF;
  END IF;

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
    birth_month       = CASE WHEN p ? 'birthday' THEN v_bm ELSE birth_month END,
    birth_day         = CASE WHEN p ? 'birthday' THEN v_bd ELSE birth_day END,
    birthday_public   = CASE WHEN p ? 'birthday_public' THEN COALESCE((p->>'birthday_public')::boolean, FALSE) ELSE birthday_public END,
    status            = CASE WHEN COALESCE((p->>'hide')::boolean, FALSE) THEN 'hidden'
                             WHEN COALESCE((p->>'unhide')::boolean, FALSE) THEN 'active' ELSE status END,
    updated_at        = NOW()
  WHERE id = v.id;
  UPDATE parivar_profile_links SET uses = uses + 1, last_used_at = NOW() WHERE id = l.id;
  RETURN jsonb_build_object('ok', TRUE, 'slug', v.slug, 'photo_saved', v_photo IS NOT NULL);
END $$;
REVOKE ALL ON FUNCTION public.parivar_profile_save(TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_profile_save(TEXT, JSONB) TO anon, authenticated;

-- today's birthdays (India date), only people who chose to show it; number only as their contact setting allows
CREATE OR REPLACE FUNCTION public.parivar_birthdays_today()
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('name', p.full_name, 'slug', p.slug, 'photo', p.photo_url, 'profession', p.profession,
                    'verified', p.mobile_verified_at IS NOT NULL,
                    'contact_mode', CASE WHEN p.mobile IS NULL THEN 'hidden' ELSE p.contact_mode END,
                    'mobile', CASE WHEN p.mobile IS NOT NULL AND p.contact_mode IN ('show', 'whatsapp') THEN p.mobile END,
                    'org', (SELECT o.name FROM parivar_org_roles r JOIN parivar_orgs o ON o.id = r.org_id AND o.status = 'active'
                             WHERE r.person_id = p.id ORDER BY (r.role = 'member'), r.created_at LIMIT 1)) ORDER BY p.full_name), '[]'::jsonb)
    FROM parivar_people p
   WHERE p.status = 'active' AND p.birthday_public
     AND p.birth_month = EXTRACT(MONTH FROM (NOW() AT TIME ZONE 'Asia/Kolkata'))::INT
     AND p.birth_day = EXTRACT(DAY FROM (NOW() AT TIME ZONE 'Asia/Kolkata'))::INT;
$$;
REVOKE ALL ON FUNCTION public.parivar_birthdays_today() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_birthdays_today() TO anon, authenticated;

-- ---------- 3. member offers ----------
CREATE OR REPLACE FUNCTION public.parivar_offers(p_org_slug TEXT DEFAULT NULL, p_business_id UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', f.id, 'offer', f.offer_text, 'valid_until', f.valid_until,
                    'shop', b.name, 'shop_slug', b.slug, 'shop_photo', (CASE WHEN array_length(b.photos, 1) > 0 THEN b.photos[1] END),
                    'org', o.name, 'org_slug', o.slug) ORDER BY f.created_at DESC), '[]'::jsonb)
    FROM parivar_member_offers f JOIN businesses b ON b.id = f.business_id AND b.status = 'active'
    LEFT JOIN parivar_orgs o ON o.id = f.org_id
   WHERE f.status = 'active' AND f.valid_until >= (NOW() AT TIME ZONE 'Asia/Kolkata')::date
     AND (f.org_id IS NULL OR o.status = 'active')
     AND (p_org_slug IS NULL OR o.slug = p_org_slug OR f.org_id IS NULL)
     AND (p_business_id IS NULL OR f.business_id = p_business_id);
$$;
REVOKE ALL ON FUNCTION public.parivar_offers(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_offers(TEXT, UUID) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_offers()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id', f.id, 'offer', f.offer_text, 'valid_until', f.valid_until, 'shop', b.name,
                                   'org', COALESCE(o.name, 'All Dabwali Parivar'), 'org_id', f.org_id,
                                   'expired', f.valid_until < (NOW() AT TIME ZONE 'Asia/Kolkata')::date) ORDER BY f.valid_until DESC)
                    FROM parivar_member_offers f JOIN businesses b ON b.id = f.business_id LEFT JOIN parivar_orgs o ON o.id = f.org_id
                   WHERE f.status = 'active' AND f.valid_until > (NOW() AT TIME ZONE 'Asia/Kolkata')::date - 30), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_offers() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_offers() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_offer_add(p_business_id UUID, p_org_id UUID, p_text TEXT, p_until DATE)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE v_id BIGINT;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF NOT EXISTS (SELECT 1 FROM businesses WHERE id = p_business_id) THEN RAISE EXCEPTION 'pick the shop'; END IF;
  IF length(btrim(COALESCE(p_text, ''))) < 3 THEN RAISE EXCEPTION 'write the offer'; END IF;
  IF p_until IS NULL OR p_until < (NOW() AT TIME ZONE 'Asia/Kolkata')::date OR p_until > (NOW() AT TIME ZONE 'Asia/Kolkata')::date + 366 THEN
    RAISE EXCEPTION 'end date must be within the next year';
  END IF;
  INSERT INTO parivar_member_offers (business_id, org_id, offer_text, valid_until, created_by)
  VALUES (p_business_id, p_org_id, left(btrim(p_text), 140), p_until, auth.uid()) RETURNING id INTO v_id;
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_offer_add(UUID, UUID, TEXT, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_offer_add(UUID, UUID, TEXT, DATE) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_offer_remove(p_id BIGINT)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  UPDATE parivar_member_offers SET status = 'removed' WHERE id = p_id; RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_offer_remove(BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_offer_remove(BIGINT) TO authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/274-parivar-join-birthdays-offers.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Checks — every row should say yes
SELECT 'join requests + offers tables, closed to the public' AS check,
       CASE WHEN to_regclass('public.parivar_join_requests') IS NOT NULL AND to_regclass('public.parivar_member_offers') IS NOT NULL
             AND NOT has_table_privilege('anon', 'public.parivar_join_requests', 'SELECT') AND NOT has_table_privilege('anon', 'public.parivar_member_offers', 'SELECT') THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'visitors can send a join request, only the office approves',
       CASE WHEN has_function_privilege('anon', 'public.parivar_join(jsonb)', 'EXECUTE') AND NOT has_function_privilege('anon', 'public.admin_parivar_join_decide(bigint,boolean)', 'EXECUTE') THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'birthday saved from the member''s own link',
       CASE WHEN pg_get_functiondef('public.parivar_profile_save(text,jsonb)'::regprocedure) LIKE '%birth_month%' THEN 'yes' ELSE 'NO — tell Claude' END;
