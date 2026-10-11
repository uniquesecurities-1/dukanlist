-- ============================================================
-- db/249 — "Dukaan ke baare mein" + the "page sudhaaro" link
-- ============================================================
--
-- Deepak, 11 Oct: a shopkeeper said a shop page shows nothing about
-- the shop except one photo; the rest reads ready-made. And: no more
-- field team — everything has to run from the office, online.
--
-- 1. Two new public fields on businesses (about_text already exists
--    and becomes the "story"):
--      offerings  TEXT[]  what the shop sells / brands / services
--      why_text   TEXT    the one real reason people come here
-- 2. update_my_about() — the owner sets them from his panel.
-- 3. A per-shop link the office sends on WhatsApp. The shopkeeper opens
--    it on his phone WITHOUT logging in, answers three questions and
--    adds photos. Nothing goes live from the link: it lands in
--    shop_update_submissions as 'pending' and an admin approves it.
--      - only a SHA-256 of the token is stored; the token itself is
--        shown to the admin once
--      - a link expires (default 7 days), is revoked when a new one is
--        made for the same shop, takes at most 10 submissions and one
--        per 30 seconds
--      - photo URLs must be this site's own Cloudinary account
-- 4. Admin list + approve/reject. Approving copies the answers onto the
--    shop and adds the photos (never past the 8-photo limit).
--
-- No extension needed: the token is two gen_random_uuid() values
-- (built in since Postgres 13), hashed with the built-in sha256().
-- Safe to re-run.
-- ============================================================

BEGIN;

-- 1. columns ------------------------------------------------------------
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS offerings TEXT[] NOT NULL DEFAULT '{}';
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS why_text  TEXT;
-- db/225 made businesses column-granted for anon: a new public column
-- must be granted or the shop page cannot read it.
GRANT SELECT (offerings, why_text) ON public.businesses TO anon, authenticated;

-- cleaner shared by every writer: trim, collapse spaces, 2–40 chars,
-- no duplicates (case-insensitive), at most 20, original order kept
CREATE OR REPLACE FUNCTION public._dl_clean_offerings(p TEXT[])
RETURNS TEXT[] LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE e TEXT; t TEXT; outv TEXT[] := '{}'; seen TEXT[] := '{}';
BEGIN
  IF p IS NULL THEN RETURN '{}'; END IF;
  FOREACH e IN ARRAY p LOOP
    t := btrim(regexp_replace(COALESCE(e, ''), '\s+', ' ', 'g'));
    CONTINUE WHEN length(t) < 2 OR length(t) > 40 OR lower(t) = ANY (seen);
    outv := outv || t; seen := seen || lower(t);
    EXIT WHEN array_length(outv, 1) >= 20;
  END LOOP;
  RETURN outv;
END $$;

-- 2. owner sets them ----------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_my_about(p_business_id UUID, p_offerings TEXT[], p_why TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp
AS $$
DECLARE v_off TEXT[]; v_why TEXT;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'login required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM business_owners WHERE business_id = p_business_id AND auth_user_id = auth.uid())
     AND NOT EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND COALESCE(disabled, FALSE) = FALSE) THEN
    RAISE EXCEPTION 'not your shop';
  END IF;
  v_off := public._dl_clean_offerings(p_offerings);
  v_why := NULLIF(left(btrim(COALESCE(p_why, '')), 300), '');
  UPDATE businesses SET offerings = v_off, why_text = v_why, updated_at = NOW() WHERE id = p_business_id;
  RETURN jsonb_build_object('ok', TRUE, 'offerings', to_jsonb(v_off), 'why_text', v_why);
END $$;
REVOKE ALL ON FUNCTION public.update_my_about(UUID, TEXT[], TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_my_about(UUID, TEXT[], TEXT) TO authenticated;

-- 3. links + submissions -------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shop_update_links (
  id           BIGSERIAL PRIMARY KEY,
  business_id  UUID        NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
  token_hash   TEXT        NOT NULL UNIQUE,
  created_by   UUID,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at   TIMESTAMPTZ NOT NULL,
  submissions  INT         NOT NULL DEFAULT 0,
  last_used_at TIMESTAMPTZ,
  revoked_at   TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_sul_biz ON public.shop_update_links (business_id);

CREATE TABLE IF NOT EXISTS public.shop_update_submissions (
  id               BIGSERIAL PRIMARY KEY,
  link_id          BIGINT      REFERENCES public.shop_update_links(id) ON DELETE SET NULL,
  business_id      UUID        NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
  about_text       TEXT,
  offerings        TEXT[]      NOT NULL DEFAULT '{}',
  why_text         TEXT,
  established_year INT,
  photos           TEXT[]      NOT NULL DEFAULT '{}',
  submitted_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  status           TEXT        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_by      UUID,
  reviewed_at      TIMESTAMPTZ,
  review_note      TEXT
);
CREATE INDEX IF NOT EXISTS idx_sus_pending ON public.shop_update_submissions (submitted_at) WHERE status = 'pending';

-- Nobody touches these through REST; only the functions below do.
ALTER TABLE public.shop_update_links       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shop_update_submissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.shop_update_links, public.shop_update_submissions FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public._dl_is_admin_uid()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
  SELECT auth.uid() IS NOT NULL
     AND EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND COALESCE(disabled, FALSE) = FALSE);
$$;
REVOKE ALL ON FUNCTION public._dl_is_admin_uid() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._dl_is_admin_uid() TO authenticated;

-- admin makes a link (older live links for the shop are revoked)
CREATE OR REPLACE FUNCTION public.admin_create_update_link(p_business_id UUID, p_days INT DEFAULT 7)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp
AS $$
DECLARE v_token TEXT; v_exp TIMESTAMPTZ; b RECORD;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT id, name, slug, whatsapp, mobile INTO b FROM businesses WHERE id = p_business_id;
  IF b.id IS NULL THEN RAISE EXCEPTION 'business not found'; END IF;
  UPDATE shop_update_links SET revoked_at = NOW()
   WHERE business_id = p_business_id AND revoked_at IS NULL;
  v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  v_exp   := NOW() + make_interval(days => GREATEST(1, LEAST(COALESCE(p_days, 7), 30)));
  INSERT INTO shop_update_links (business_id, token_hash, created_by, expires_at)
  VALUES (p_business_id, encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), auth.uid(), v_exp);
  RETURN jsonb_build_object('token', v_token, 'expires_at', v_exp,
                            'name', b.name, 'slug', b.slug, 'whatsapp', COALESCE(b.whatsapp, b.mobile));
END $$;
REVOKE ALL ON FUNCTION public.admin_create_update_link(UUID, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_create_update_link(UUID, INT) TO authenticated;

-- internal: token → live link row
CREATE OR REPLACE FUNCTION public._dl_live_link(p_token TEXT)
RETURNS public.shop_update_links LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT * FROM shop_update_links
   WHERE token_hash = encode(sha256(convert_to(COALESCE(p_token, ''), 'UTF8')), 'hex')
     AND revoked_at IS NULL AND expires_at > NOW()
   LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public._dl_live_link(TEXT) FROM PUBLIC, anon, authenticated;

-- shopkeeper opens the link
CREATE OR REPLACE FUNCTION public.public_get_update_link(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE l shop_update_links; b RECORD; v_photos INT; v_cat TEXT;
BEGIN
  IF length(COALESCE(p_token, '')) <> 64 THEN RETURN jsonb_build_object('ok', FALSE, 'reason', 'invalid'); END IF;
  l := public._dl_live_link(p_token);
  IF l.id IS NULL THEN RETURN jsonb_build_object('ok', FALSE, 'reason', 'expired'); END IF;
  SELECT id, name, slug, about_text, offerings, why_text, established_year, sub_category_id, category_id
    INTO b FROM businesses WHERE id = l.business_id;
  SELECT COUNT(*) INTO v_photos FROM business_photos WHERE business_id = l.business_id;
  SELECT name INTO v_cat FROM categories WHERE id = COALESCE(b.sub_category_id, b.category_id);
  RETURN jsonb_build_object(
    'ok', TRUE, 'name', b.name, 'slug', b.slug, 'category', v_cat,
    'about_text', b.about_text, 'offerings', to_jsonb(COALESCE(b.offerings, '{}')), 'why_text', b.why_text,
    'established_year', b.established_year, 'photo_count', v_photos,
    'photo_room', GREATEST(0, 8 - v_photos), 'expires_at', l.expires_at,
    'submissions_left', GREATEST(0, 10 - l.submissions));
END $$;
REVOKE ALL ON FUNCTION public.public_get_update_link(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.public_get_update_link(TEXT) TO anon, authenticated;

-- shopkeeper sends answers + photos → pending
CREATE OR REPLACE FUNCTION public.public_submit_shop_update(p_token TEXT, p_data JSONB)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  l shop_update_links; v_about TEXT; v_why TEXT; v_year INT; v_off TEXT[]; v_ph TEXT[] := '{}';
  e TEXT; v_id BIGINT;
BEGIN
  l := public._dl_live_link(p_token);
  IF l.id IS NULL THEN RAISE EXCEPTION 'This link has expired. Please ask DukanList for a new one.'; END IF;
  IF l.submissions >= 10 THEN RAISE EXCEPTION 'This link has been used too many times. Please ask DukanList for a new one.'; END IF;
  IF l.last_used_at IS NOT NULL AND l.last_used_at > NOW() - INTERVAL '30 seconds' THEN
    RAISE EXCEPTION 'Please wait a few seconds and try again.';
  END IF;

  v_about := NULLIF(left(btrim(COALESCE(p_data->>'about_text', '')), 1500), '');
  v_why   := NULLIF(left(btrim(COALESCE(p_data->>'why_text',   '')), 300),  '');
  v_year  := NULLIF(left(regexp_replace(COALESCE(p_data->>'established_year', ''), '\D', '', 'g'), 4), '')::INT;
  IF v_year IS NOT NULL AND (v_year < 1900 OR v_year > EXTRACT(YEAR FROM NOW())::INT) THEN v_year := NULL; END IF;
  v_off := public._dl_clean_offerings(ARRAY(SELECT jsonb_array_elements_text(
             CASE WHEN jsonb_typeof(p_data->'offerings') = 'array' THEN p_data->'offerings' ELSE '[]'::jsonb END)));
  IF jsonb_typeof(p_data->'photos') = 'array' THEN
    FOR e IN SELECT jsonb_array_elements_text(p_data->'photos') LOOP
      IF e ~ '^https://res\.cloudinary\.com/dukanlist/image/upload/[A-Za-z0-9_,./:@-]+$' AND NOT (e = ANY (v_ph)) THEN
        v_ph := v_ph || e;
      END IF;
      EXIT WHEN array_length(v_ph, 1) >= 6;
    END LOOP;
  END IF;

  IF v_about IS NULL AND v_why IS NULL AND v_year IS NULL
     AND COALESCE(array_length(v_off, 1), 0) = 0 AND COALESCE(array_length(v_ph, 1), 0) = 0 THEN
    RAISE EXCEPTION 'Nothing to save — please fill at least one answer or add a photo.';
  END IF;

  INSERT INTO shop_update_submissions (link_id, business_id, about_text, offerings, why_text, established_year, photos)
  VALUES (l.id, l.business_id, v_about, v_off, v_why, v_year, v_ph)
  RETURNING id INTO v_id;
  UPDATE shop_update_links SET submissions = submissions + 1, last_used_at = NOW() WHERE id = l.id;
  RETURN jsonb_build_object('ok', TRUE, 'id', v_id);
END $$;
REVOKE ALL ON FUNCTION public.public_submit_shop_update(TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.public_submit_shop_update(TEXT, JSONB) TO anon, authenticated;

-- 4. admin review ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_list_shop_updates(p_status TEXT DEFAULT 'pending')
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp
AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(x ORDER BY (x->>'submitted_at') DESC) FROM (
      SELECT jsonb_build_object(
        'id', s.id, 'status', s.status, 'submitted_at', s.submitted_at,
        'business_id', b.id, 'name', b.name, 'slug', b.slug,
        'new', jsonb_build_object('about_text', s.about_text, 'offerings', to_jsonb(s.offerings),
                                  'why_text', s.why_text, 'established_year', s.established_year,
                                  'photos', to_jsonb(s.photos)),
        'old', jsonb_build_object('about_text', b.about_text, 'offerings', to_jsonb(COALESCE(b.offerings, '{}')),
                                  'why_text', b.why_text, 'established_year', b.established_year),
        'photo_count', (SELECT COUNT(*) FROM business_photos p WHERE p.business_id = b.id),
        'review_note', s.review_note, 'reviewed_at', s.reviewed_at) AS x
      FROM shop_update_submissions s JOIN businesses b ON b.id = s.business_id
      WHERE s.status = COALESCE(p_status, 'pending')
      ORDER BY s.submitted_at DESC
      LIMIT 200) q), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_list_shop_updates(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_shop_updates(TEXT) TO authenticated;

-- p_photos: which of the submitted photos to add (NULL = all of them)
CREATE OR REPLACE FUNCTION public.admin_review_shop_update(p_id BIGINT, p_approve BOOLEAN,
                                                          p_note TEXT DEFAULT NULL, p_photos TEXT[] DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp
AS $$
DECLARE s shop_update_submissions; v_room INT; v_has_main BOOLEAN; e TEXT; v_added INT := 0;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO s FROM shop_update_submissions WHERE id = p_id FOR UPDATE;
  IF s.id IS NULL THEN RAISE EXCEPTION 'submission not found'; END IF;
  IF s.status <> 'pending' THEN RAISE EXCEPTION 'already %', s.status; END IF;

  IF p_approve THEN
    UPDATE businesses SET
      about_text       = COALESCE(s.about_text, about_text),
      offerings        = CASE WHEN COALESCE(array_length(s.offerings, 1), 0) > 0 THEN s.offerings ELSE offerings END,
      why_text         = COALESCE(s.why_text, why_text),
      established_year = COALESCE(s.established_year, established_year),
      updated_at       = NOW()
    WHERE id = s.business_id;

    SELECT GREATEST(0, 8 - COUNT(*)) INTO v_room FROM business_photos WHERE business_id = s.business_id;
    FOREACH e IN ARRAY s.photos LOOP
      EXIT WHEN v_added >= v_room;
      CONTINUE WHEN p_photos IS NOT NULL AND NOT (e = ANY (p_photos));
      SELECT EXISTS (SELECT 1 FROM business_photos WHERE business_id = s.business_id AND is_featured) INTO v_has_main;
      INSERT INTO business_photos (business_id, uploaded_by, cloudinary_url, is_featured)
      VALUES (s.business_id, auth.uid(), e, NOT v_has_main);
      v_added := v_added + 1;
    END LOOP;
  END IF;

  UPDATE shop_update_submissions
     SET status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
         reviewed_by = auth.uid(), reviewed_at = NOW(), review_note = NULLIF(btrim(COALESCE(p_note, '')), '')
   WHERE id = p_id;
  RETURN jsonb_build_object('ok', TRUE, 'photos_added', v_added);
END $$;
REVOKE ALL ON FUNCTION public.admin_review_shop_update(BIGINT, BOOLEAN, TEXT, TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_shop_update(BIGINT, BOOLEAN, TEXT, TEXT[]) TO authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/249-shop-about-and-update-links.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- Checks — every row should say yes
-- ============================================================
SELECT 'offerings + why_text columns' AS check,
       CASE WHEN (SELECT COUNT(*) FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'businesses'
                     AND column_name IN ('offerings', 'why_text')) = 2 THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'anon can read them',
       CASE WHEN has_column_privilege('anon', 'public.businesses', 'offerings', 'SELECT')
             AND has_column_privilege('anon', 'public.businesses', 'why_text', 'SELECT') THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'anon can open + submit a link',
       CASE WHEN has_function_privilege('anon', 'public.public_get_update_link(text)', 'EXECUTE')
             AND has_function_privilege('anon', 'public.public_submit_shop_update(text,jsonb)', 'EXECUTE') THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'anon CANNOT make links / approve',
       CASE WHEN NOT has_function_privilege('anon', 'public.admin_create_update_link(uuid,integer)', 'EXECUTE')
             AND NOT has_function_privilege('anon', 'public.admin_review_shop_update(bigint,boolean,text,text[])', 'EXECUTE') THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'anon CANNOT read the tables',
       CASE WHEN NOT has_table_privilege('anon', 'public.shop_update_links', 'SELECT')
             AND NOT has_table_privilege('anon', 'public.shop_update_submissions', 'SELECT') THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'bad token is refused',
       CASE WHEN (public.public_get_update_link(repeat('0', 64))->>'ok')::boolean = FALSE THEN 'yes' ELSE 'NO — tell Claude' END;
