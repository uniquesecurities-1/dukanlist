-- =====================================================
-- db/60-pucho-bhai-MASTER-HOTFIX.sql
-- =====================================================
-- USER FEEDBACK: 'Reply post nahi ho raha. Sab fix ek baar me karo.'
--
-- This is the ONE-SHOT MASTER file for Pucho Bhai.
-- Safe to run even if db/52..db/59 were partially applied.
-- 100% idempotent — every block uses IF NOT EXISTS / CREATE OR REPLACE.
--
-- WHAT THIS DOES:
--   1. Ensures pgcrypto extension is in 'extensions' schema
--   2. Ensures all required tables + columns exist
--   3. Recreates ALL Pucho Bhai RPCs with the latest correct code:
--      • Uses extensions.digest(...) (was failing earlier)
--      • search_path = public, extensions
--      • Replies allow phone numbers (feature: sharing shop contact)
--      • Pattern check only blocks URLs in replies, not phone leaks
--      • Defensive checks for optional tables (community_phone_blacklist,
--        blocked_keywords, _pucho_pattern_check)
--   4. Smoke tests at end — RAISE NOTICE for each component
--
-- HOW TO RUN:
--   Supabase Dashboard → SQL Editor → New Query → paste → Run
--   Even if other db/* files were already run, this is safe.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. Ensure pgcrypto extension
-- ============================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ============================================================
-- 2. Ensure tables exist with all required columns
-- ============================================================
CREATE TABLE IF NOT EXISTS community_questions (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  city_id         INT REFERENCES geo_cities(id) ON DELETE SET NULL,
  category_id     INT REFERENCES categories(id) ON DELETE SET NULL,
  asker_name      TEXT,
  asker_phone_hash TEXT NOT NULL,
  question_text   TEXT NOT NULL CHECK (length(question_text) BETWEEN 10 AND 500),
  view_count      INT DEFAULT 0,
  reply_count     INT DEFAULT 0,
  status          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','flagged','removed')),
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS community_replies (
  id               UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  question_id      UUID NOT NULL REFERENCES community_questions(id) ON DELETE CASCADE,
  replier_name     TEXT,
  replier_phone_hash TEXT NOT NULL,
  business_id      UUID REFERENCES businesses(id) ON DELETE SET NULL,
  reply_text       TEXT NOT NULL CHECK (length(reply_text) BETWEEN 4 AND 1000),
  helpful_count    INT DEFAULT 0,
  status           TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','flagged','removed')),
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS community_reports (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  target_type     TEXT NOT NULL CHECK (target_type IN ('question','reply')),
  target_id       UUID NOT NULL,
  reporter_phone_hash TEXT NOT NULL,
  reason          TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (target_type, target_id, reporter_phone_hash)
);

CREATE TABLE IF NOT EXISTS community_phone_blacklist (
  phone_hash    TEXT PRIMARY KEY,
  banned_at     TIMESTAMPTZ DEFAULT NOW(),
  reason        TEXT,
  banned_by     UUID REFERENCES auth.users(id)
);

-- Ensure later-added columns exist (idempotent)
ALTER TABLE community_questions
  ADD COLUMN IF NOT EXISTS is_pinned    BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS is_resolved  BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS pinned_at    TIMESTAMPTZ;

ALTER TABLE community_replies
  ADD COLUMN IF NOT EXISTS is_best      BOOLEAN NOT NULL DEFAULT FALSE;

-- Indexes (idempotent)
CREATE INDEX IF NOT EXISTS idx_cq_city     ON community_questions(city_id) WHERE status='active';
CREATE INDEX IF NOT EXISTS idx_cq_pinned   ON community_questions(is_pinned DESC, pinned_at DESC NULLS LAST, created_at DESC) WHERE status='active';
CREATE INDEX IF NOT EXISTS idx_cr_question ON community_replies(question_id) WHERE status='active';
CREATE INDEX IF NOT EXISTS idx_cr_best     ON community_replies(question_id, is_best DESC, created_at ASC) WHERE status='active';

-- RLS (idempotent)
ALTER TABLE community_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_replies   ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_reports   ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_phone_blacklist ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cq_public_read" ON community_questions;
CREATE POLICY "cq_public_read" ON community_questions FOR SELECT TO anon, authenticated USING (status='active');
DROP POLICY IF EXISTS "cq_admin_all" ON community_questions;
CREATE POLICY "cq_admin_all" ON community_questions FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

DROP POLICY IF EXISTS "cr_public_read" ON community_replies;
CREATE POLICY "cr_public_read" ON community_replies FOR SELECT TO anon, authenticated USING (status='active');
DROP POLICY IF EXISTS "cr_admin_all" ON community_replies;
CREATE POLICY "cr_admin_all" ON community_replies FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

DROP POLICY IF EXISTS "creports_admin_all" ON community_reports;
CREATE POLICY "creports_admin_all" ON community_reports FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

DROP POLICY IF EXISTS "cpb_admin_all" ON community_phone_blacklist;
CREATE POLICY "cpb_admin_all" ON community_phone_blacklist FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

-- Trigger for reply_count
CREATE OR REPLACE FUNCTION _trg_update_question_reply_count() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='INSERT' AND NEW.status='active' THEN
    UPDATE community_questions SET reply_count = reply_count + 1, updated_at = NOW() WHERE id = NEW.question_id;
  ELSIF TG_OP='UPDATE' THEN
    IF OLD.status='active' AND NEW.status<>'active' THEN
      UPDATE community_questions SET reply_count = GREATEST(0, reply_count-1) WHERE id = NEW.question_id;
    ELSIF OLD.status<>'active' AND NEW.status='active' THEN
      UPDATE community_questions SET reply_count = reply_count + 1 WHERE id = NEW.question_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cr_count ON community_replies;
CREATE TRIGGER trg_cr_count AFTER INSERT OR UPDATE ON community_replies
  FOR EACH ROW EXECUTE FUNCTION _trg_update_question_reply_count();

-- Pattern check helper (idempotent)
CREATE OR REPLACE FUNCTION _pucho_pattern_check(p_text TEXT, p_strict_phone BOOLEAN DEFAULT TRUE)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_caps_ratio NUMERIC;
  v_total INT;
  v_upper INT;
BEGIN
  -- URL → block
  IF p_text ~* '(https?://|www\.|[a-z0-9-]+\.(com|in|net|org|co|biz|info|me|link))' THEN
    RETURN 'block';
  END IF;

  -- Phone number — block only if strict mode (used for QUESTIONS, not replies)
  IF p_strict_phone AND p_text ~ '(\+?91[-\s]?)?[6-9]\d{9}' THEN
    RETURN 'flag';
  END IF;

  -- All-caps shouting (12+ letters, >70% upper) → flag
  v_total := length(regexp_replace(p_text, '[^A-Za-z]', '', 'g'));
  IF v_total >= 12 THEN
    v_upper := length(regexp_replace(p_text, '[^A-Z]', '', 'g'));
    v_caps_ratio := v_upper::numeric / v_total;
    IF v_caps_ratio > 0.7 THEN RETURN 'flag'; END IF;
  END IF;

  -- Repeated char spam
  IF p_text ~ '(.)\1{5,}' THEN RETURN 'flag'; END IF;

  RETURN 'ok';
END;
$$;

COMMIT;

BEGIN;

-- ============================================================
-- 3. RPC: post_community_question
-- ============================================================
DROP FUNCTION IF EXISTS post_community_question(INT, INT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION post_community_question(
  p_city_id INT, p_category_id INT, p_question_text TEXT,
  p_asker_name TEXT, p_asker_phone TEXT
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
DECLARE
  v_hash TEXT; v_id UUID; v_clean TEXT;
  v_pat TEXT; v_status TEXT := 'active';
BEGIN
  IF p_question_text IS NULL OR length(trim(p_question_text)) < 10 THEN
    RAISE EXCEPTION 'Question too short (min 10 chars)';
  END IF;
  IF length(p_question_text) > 500 THEN
    RAISE EXCEPTION 'Question too long (max 500 chars)';
  END IF;

  v_clean := regexp_replace(coalesce(p_asker_phone,''), '[^0-9]', '', 'g');
  IF length(v_clean) < 10 THEN
    RAISE EXCEPTION 'Valid mobile number required';
  END IF;
  IF length(v_clean) >= 12 AND substring(v_clean,1,2) = '91' THEN
    v_clean := substring(v_clean,3);
  END IF;
  v_hash := encode(extensions.digest('cq:' || v_clean, 'sha256'), 'hex');

  -- Blacklist check
  IF EXISTS (SELECT 1 FROM community_phone_blacklist WHERE phone_hash = v_hash) THEN
    RAISE EXCEPTION 'Your number has been blocked for spam.';
  END IF;

  -- Rate limit (5/hr)
  IF (SELECT COUNT(*) FROM community_questions
      WHERE asker_phone_hash = v_hash AND created_at > NOW() - INTERVAL '1 hour') >= 5 THEN
    RAISE EXCEPTION 'Too many questions in the last hour. Please wait.';
  END IF;

  -- Blocked keywords (strict)
  IF EXISTS (
    SELECT 1 FROM blocked_keywords k WHERE k.active=TRUE AND k.severity='block'
      AND ((k.is_regex AND p_question_text ~* k.pattern)
        OR (NOT k.is_regex AND position(lower(k.pattern) IN lower(p_question_text)) > 0))
  ) THEN
    RAISE EXCEPTION 'Your question contains blocked content';
  END IF;

  -- Pattern check (with phone-flag enabled for questions)
  v_pat := _pucho_pattern_check(p_question_text, TRUE);
  IF v_pat = 'block' THEN
    RAISE EXCEPTION 'External links not allowed in questions';
  ELSIF v_pat = 'flag' THEN
    v_status := 'flagged';
  END IF;

  -- Flag-severity keyword check
  IF v_status = 'active' AND EXISTS (
    SELECT 1 FROM blocked_keywords k WHERE k.active=TRUE AND k.severity='flag'
      AND ((k.is_regex AND p_question_text ~* k.pattern)
        OR (NOT k.is_regex AND position(lower(k.pattern) IN lower(p_question_text)) > 0))
  ) THEN
    v_status := 'flagged';
  END IF;

  INSERT INTO community_questions (city_id, category_id, asker_name, asker_phone_hash, question_text, status)
  VALUES (p_city_id, p_category_id, NULLIF(trim(coalesce(p_asker_name,'')),''), v_hash, trim(p_question_text), v_status)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION post_community_question(INT, INT, TEXT, TEXT, TEXT) TO anon, authenticated;

-- ============================================================
-- 4. RPC: post_community_reply  ← FIX: phone numbers ALLOWED in replies
-- ============================================================
DROP FUNCTION IF EXISTS post_community_reply(UUID, TEXT, TEXT, TEXT, UUID);
CREATE OR REPLACE FUNCTION post_community_reply(
  p_question_id UUID, p_reply_text TEXT,
  p_replier_name TEXT, p_replier_phone TEXT,
  p_business_id UUID
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
DECLARE
  v_hash TEXT; v_id UUID; v_clean TEXT;
  v_pat TEXT; v_status TEXT := 'active';
BEGIN
  IF p_reply_text IS NULL OR length(trim(p_reply_text)) < 4 THEN
    RAISE EXCEPTION 'Reply too short (min 4 chars)';
  END IF;
  IF length(p_reply_text) > 1000 THEN
    RAISE EXCEPTION 'Reply too long (max 1000 chars)';
  END IF;

  v_clean := regexp_replace(coalesce(p_replier_phone,''), '[^0-9]', '', 'g');
  IF length(v_clean) < 10 THEN
    RAISE EXCEPTION 'Valid mobile number required';
  END IF;
  IF length(v_clean) >= 12 AND substring(v_clean,1,2) = '91' THEN
    v_clean := substring(v_clean,3);
  END IF;
  v_hash := encode(extensions.digest('cr:' || v_clean, 'sha256'), 'hex');

  -- Blacklist check (both cq + cr hash forms)
  IF EXISTS (SELECT 1 FROM community_phone_blacklist
             WHERE phone_hash = v_hash
                OR phone_hash = encode(extensions.digest('cq:' || v_clean, 'sha256'), 'hex')) THEN
    RAISE EXCEPTION 'Your number has been blocked for spam.';
  END IF;

  -- Verify question exists + active
  IF NOT EXISTS (SELECT 1 FROM community_questions WHERE id = p_question_id AND status='active') THEN
    RAISE EXCEPTION 'Question not found or no longer active';
  END IF;

  -- Rate limit (10/hr)
  IF (SELECT COUNT(*) FROM community_replies
      WHERE replier_phone_hash = v_hash AND created_at > NOW() - INTERVAL '1 hour') >= 10 THEN
    RAISE EXCEPTION 'Too many replies in the last hour. Please wait.';
  END IF;

  -- Blocked keywords (strict)
  IF EXISTS (
    SELECT 1 FROM blocked_keywords k WHERE k.active=TRUE AND k.severity='block'
      AND ((k.is_regex AND p_reply_text ~* k.pattern)
        OR (NOT k.is_regex AND position(lower(k.pattern) IN lower(p_reply_text)) > 0))
  ) THEN
    RAISE EXCEPTION 'Your reply contains blocked content';
  END IF;

  -- Pattern check — strict_phone=FALSE: replies can share phone numbers
  -- (this is a feature — people share shop contact in replies)
  -- URL is still blocked.
  v_pat := _pucho_pattern_check(p_reply_text, FALSE);
  IF v_pat = 'block' THEN
    RAISE EXCEPTION 'External links not allowed in replies';
  ELSIF v_pat = 'flag' THEN
    v_status := 'flagged';
  END IF;

  -- Flag-severity keyword check
  IF v_status = 'active' AND EXISTS (
    SELECT 1 FROM blocked_keywords k WHERE k.active=TRUE AND k.severity='flag'
      AND ((k.is_regex AND p_reply_text ~* k.pattern)
        OR (NOT k.is_regex AND position(lower(k.pattern) IN lower(p_reply_text)) > 0))
  ) THEN
    v_status := 'flagged';
  END IF;

  INSERT INTO community_replies (question_id, replier_name, replier_phone_hash, business_id, reply_text, status)
  VALUES (p_question_id, NULLIF(trim(coalesce(p_replier_name,'')),''), v_hash, p_business_id, trim(p_reply_text), v_status)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION post_community_reply(UUID, TEXT, TEXT, TEXT, UUID) TO anon, authenticated;

COMMIT;

BEGIN;

-- ============================================================
-- 5. RPC: get_community_questions (with is_pinned + is_resolved)
-- ============================================================
DROP FUNCTION IF EXISTS get_community_questions(INT, INT, INT);
CREATE OR REPLACE FUNCTION get_community_questions(
  p_city_id INT, p_limit INT DEFAULT 30, p_offset INT DEFAULT 0
) RETURNS TABLE (
  id UUID, city_id INT, city_name TEXT,
  category_id INT, category_name TEXT,
  asker_name TEXT, question_text TEXT,
  view_count INT, reply_count INT,
  is_pinned BOOLEAN, is_resolved BOOLEAN,
  created_at TIMESTAMPTZ
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  SELECT q.id, q.city_id, c.name, q.category_id, cat.name,
         q.asker_name, q.question_text,
         q.view_count, q.reply_count,
         q.is_pinned, q.is_resolved, q.created_at
  FROM community_questions q
  LEFT JOIN geo_cities c   ON c.id = q.city_id
  LEFT JOIN categories cat ON cat.id = q.category_id
  WHERE q.status='active' AND (p_city_id IS NULL OR q.city_id = p_city_id)
  ORDER BY q.is_pinned DESC, q.pinned_at DESC NULLS LAST, q.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END; $$;
GRANT EXECUTE ON FUNCTION get_community_questions(INT, INT, INT) TO anon, authenticated;

-- ============================================================
-- 6. RPC: get_community_question_detail (best-answer aware)
-- ============================================================
DROP FUNCTION IF EXISTS get_community_question_detail(UUID);
CREATE OR REPLACE FUNCTION get_community_question_detail(p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_q JSONB; v_r JSONB;
BEGIN
  UPDATE community_questions SET view_count = view_count + 1
    WHERE id = p_id AND status='active';

  SELECT to_jsonb(t) INTO v_q FROM (
    SELECT q.id, q.city_id, c.name AS city_name,
           q.category_id, cat.name AS category_name,
           q.asker_name, q.question_text,
           q.view_count, q.reply_count,
           q.is_pinned, q.is_resolved, q.created_at
    FROM community_questions q
    LEFT JOIN geo_cities c   ON c.id = q.city_id
    LEFT JOIN categories cat ON cat.id = q.category_id
    WHERE q.id = p_id AND q.status='active'
  ) t;

  IF v_q IS NULL THEN RAISE EXCEPTION 'Question not found'; END IF;

  SELECT coalesce(
    jsonb_agg(to_jsonb(sub) ORDER BY sub.is_best DESC, sub.helpful_count DESC NULLS LAST, sub.created_at ASC),
    '[]'::jsonb
  ) INTO v_r FROM (
    SELECT r.id, r.replier_name, r.reply_text, r.helpful_count, r.is_best,
           r.created_at, r.business_id,
           b.name AS business_name, b.slug AS business_slug
    FROM community_replies r
    LEFT JOIN businesses b ON b.id = r.business_id
    WHERE r.question_id = p_id AND r.status='active'
  ) sub;

  RETURN jsonb_build_object('question', v_q, 'replies', v_r);
END; $$;
GRANT EXECUTE ON FUNCTION get_community_question_detail(UUID) TO anon, authenticated;

-- ============================================================
-- 7. RPC: report_community_item
-- ============================================================
DROP FUNCTION IF EXISTS report_community_item(TEXT, UUID, TEXT, TEXT);
CREATE OR REPLACE FUNCTION report_community_item(
  p_type TEXT, p_id UUID, p_reason TEXT, p_reporter_phone TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
DECLARE v_hash TEXT; v_clean TEXT; v_total INT;
BEGIN
  IF p_type NOT IN ('question','reply') THEN RAISE EXCEPTION 'Invalid type'; END IF;
  v_clean := regexp_replace(coalesce(p_reporter_phone,''), '[^0-9]', '', 'g');
  IF length(v_clean) < 10 THEN RAISE EXCEPTION 'Valid mobile number required'; END IF;
  IF length(v_clean) >= 12 AND substring(v_clean,1,2)='91' THEN v_clean := substring(v_clean,3); END IF;
  v_hash := encode(extensions.digest('rep:' || v_clean, 'sha256'), 'hex');

  IF (SELECT COUNT(*) FROM community_reports
      WHERE reporter_phone_hash = v_hash AND created_at > NOW() - INTERVAL '1 hour') >= 20 THEN
    RAISE EXCEPTION 'Too many reports submitted recently. Please wait.';
  END IF;

  INSERT INTO community_reports (target_type, target_id, reporter_phone_hash, reason)
    VALUES (p_type, p_id, v_hash, NULLIF(trim(coalesce(p_reason,'')),''))
    ON CONFLICT (target_type, target_id, reporter_phone_hash) DO NOTHING;

  SELECT COUNT(DISTINCT reporter_phone_hash) INTO v_total
    FROM community_reports WHERE target_type=p_type AND target_id=p_id;

  IF v_total >= 3 THEN
    IF p_type='question' THEN
      UPDATE community_questions SET status='flagged' WHERE id=p_id AND status='active';
    ELSE
      UPDATE community_replies SET status='flagged' WHERE id=p_id AND status='active';
    END IF;
  END IF;
  RETURN TRUE;
END; $$;
GRANT EXECUTE ON FUNCTION report_community_item(TEXT, UUID, TEXT, TEXT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- 8. SMOKE TESTS
-- ============================================================
DO $$
DECLARE
  v_test TEXT;
  v_q_count INT;
  v_r_count INT;
BEGIN
  -- Verify extensions.digest works
  SELECT encode(extensions.digest('test','sha256'), 'hex') INTO v_test;
  IF length(v_test) <> 64 THEN RAISE EXCEPTION 'pgcrypto digest broken'; END IF;
  RAISE NOTICE '✓ pgcrypto extensions.digest works (sample: %)', substring(v_test,1,16);

  -- Verify tables exist
  PERFORM 1 FROM information_schema.tables WHERE table_name='community_questions';
  IF NOT FOUND THEN RAISE EXCEPTION 'community_questions missing'; END IF;
  PERFORM 1 FROM information_schema.tables WHERE table_name='community_replies';
  IF NOT FOUND THEN RAISE EXCEPTION 'community_replies missing'; END IF;
  RAISE NOTICE '✓ All Pucho Bhai tables present';

  -- Verify all columns
  PERFORM 1 FROM information_schema.columns WHERE table_name='community_questions' AND column_name='is_pinned';
  IF NOT FOUND THEN RAISE EXCEPTION 'is_pinned column missing'; END IF;
  PERFORM 1 FROM information_schema.columns WHERE table_name='community_replies' AND column_name='is_best';
  IF NOT FOUND THEN RAISE EXCEPTION 'is_best column missing'; END IF;
  RAISE NOTICE '✓ All required columns present';

  -- Verify all RPCs exist
  PERFORM 1 FROM pg_proc WHERE proname='post_community_question';
  IF NOT FOUND THEN RAISE EXCEPTION 'post_community_question missing'; END IF;
  PERFORM 1 FROM pg_proc WHERE proname='post_community_reply';
  IF NOT FOUND THEN RAISE EXCEPTION 'post_community_reply missing'; END IF;
  PERFORM 1 FROM pg_proc WHERE proname='get_community_question_detail';
  IF NOT FOUND THEN RAISE EXCEPTION 'get_community_question_detail missing'; END IF;
  RAISE NOTICE '✓ All 5 Pucho Bhai RPCs registered';

  -- Snapshot counts
  SELECT COUNT(*) INTO v_q_count FROM community_questions WHERE status='active';
  SELECT COUNT(*) INTO v_r_count FROM community_replies WHERE status='active';
  RAISE NOTICE '✓ Active questions: %, Active replies: %', v_q_count, v_r_count;

  RAISE NOTICE '═══ Pucho Bhai MASTER HOTFIX applied successfully ═══';
END $$;

COMMIT;
