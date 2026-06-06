-- =====================================================
-- db/54-pucho-bhai-pgcrypto-fix.sql
-- =====================================================
-- HOTFIX: "function digest(text, unknown) does not exist"
--
-- ROOT CAUSE: pgcrypto is installed in the `extensions` schema
--   in modern Supabase, but our SECURITY DEFINER RPCs have
--   SET search_path = public — so the digest() function from
--   pgcrypto isn't visible.
--
-- FIX: Switch all phone-hashing calls in Pucho Bhai RPCs to
--   the fully-qualified extensions.digest(...) form, AND ensure
--   pgcrypto is enabled.
--
-- This is ADDITIVE-SAFE — recreates 3 functions only:
--   • post_community_question
--   • post_community_reply
--   • report_community_item
-- All other behavior is unchanged.
--
-- HOW TO RUN:
--   Supabase Dashboard → SQL Editor → New Query → paste → Run
-- =====================================================

BEGIN;

-- 1. Make sure pgcrypto is enabled (idempotent)
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- 2. Replace post_community_question with extensions.digest
DROP FUNCTION IF EXISTS post_community_question(INT, INT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION post_community_question(
  p_city_id        INT,
  p_category_id    INT,
  p_question_text  TEXT,
  p_asker_name     TEXT,
  p_asker_phone    TEXT
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
DECLARE
  v_hash TEXT;
  v_id   UUID;
  v_clean_phone TEXT;
  v_pattern_result TEXT;
  v_initial_status TEXT := 'active';
BEGIN
  IF p_question_text IS NULL OR length(trim(p_question_text)) < 10 THEN
    RAISE EXCEPTION 'Question too short (min 10 chars)';
  END IF;
  IF length(p_question_text) > 500 THEN
    RAISE EXCEPTION 'Question too long (max 500 chars)';
  END IF;

  v_clean_phone := regexp_replace(coalesce(p_asker_phone, ''), '[^0-9]', '', 'g');
  IF length(v_clean_phone) < 10 THEN
    RAISE EXCEPTION 'Valid mobile number required';
  END IF;
  IF length(v_clean_phone) >= 12 AND substring(v_clean_phone, 1, 2) = '91' THEN
    v_clean_phone := substring(v_clean_phone, 3);
  END IF;
  v_hash := encode(extensions.digest('cq:' || v_clean_phone, 'sha256'), 'hex');

  -- Phone blacklist check (only fires if table exists from db/53)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'community_phone_blacklist') THEN
    IF EXISTS (SELECT 1 FROM community_phone_blacklist WHERE phone_hash = v_hash) THEN
      RAISE EXCEPTION 'Your number has been blocked for spam.';
    END IF;
  END IF;

  -- Rate-limit: 5 questions/hour per phone
  IF (SELECT COUNT(*) FROM community_questions
      WHERE asker_phone_hash = v_hash AND created_at > NOW() - INTERVAL '1 hour') >= 5 THEN
    RAISE EXCEPTION 'Too many questions in the last hour. Please wait.';
  END IF;

  -- Hard-block keywords
  IF EXISTS (
    SELECT 1 FROM blocked_keywords k
    WHERE k.active = TRUE AND k.severity = 'block'
      AND (
        (k.is_regex AND p_question_text ~* k.pattern) OR
        (NOT k.is_regex AND position(lower(k.pattern) IN lower(p_question_text)) > 0)
      )
  ) THEN
    RAISE EXCEPTION 'Your question contains blocked content';
  END IF;

  -- Pattern check (runs only if helper exists from db/53)
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = '_pucho_pattern_check') THEN
    v_pattern_result := _pucho_pattern_check(p_question_text);
    IF v_pattern_result = 'block' THEN
      RAISE EXCEPTION 'External links not allowed in questions';
    ELSIF v_pattern_result = 'flag' THEN
      v_initial_status := 'flagged';
    END IF;
  END IF;

  -- Flag-severity keyword check
  IF v_initial_status = 'active' AND EXISTS (
    SELECT 1 FROM blocked_keywords k
    WHERE k.active = TRUE AND k.severity = 'flag'
      AND (
        (k.is_regex AND p_question_text ~* k.pattern) OR
        (NOT k.is_regex AND position(lower(k.pattern) IN lower(p_question_text)) > 0)
      )
  ) THEN
    v_initial_status := 'flagged';
  END IF;

  INSERT INTO community_questions (city_id, category_id, asker_name, asker_phone_hash, question_text, status)
  VALUES (
    p_city_id, p_category_id,
    NULLIF(trim(coalesce(p_asker_name, '')), ''),
    v_hash, trim(p_question_text), v_initial_status
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION post_community_question(INT, INT, TEXT, TEXT, TEXT) TO anon, authenticated;

-- 3. Replace post_community_reply with extensions.digest
DROP FUNCTION IF EXISTS post_community_reply(UUID, TEXT, TEXT, TEXT, UUID);
CREATE OR REPLACE FUNCTION post_community_reply(
  p_question_id    UUID,
  p_reply_text     TEXT,
  p_replier_name   TEXT,
  p_replier_phone  TEXT,
  p_business_id    UUID
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
DECLARE
  v_hash TEXT;
  v_id   UUID;
  v_clean_phone TEXT;
  v_pattern_result TEXT;
  v_initial_status TEXT := 'active';
BEGIN
  IF p_reply_text IS NULL OR length(trim(p_reply_text)) < 4 THEN
    RAISE EXCEPTION 'Reply too short (min 4 chars)';
  END IF;
  IF length(p_reply_text) > 1000 THEN
    RAISE EXCEPTION 'Reply too long (max 1000 chars)';
  END IF;

  v_clean_phone := regexp_replace(coalesce(p_replier_phone, ''), '[^0-9]', '', 'g');
  IF length(v_clean_phone) < 10 THEN
    RAISE EXCEPTION 'Valid mobile number required';
  END IF;
  IF length(v_clean_phone) >= 12 AND substring(v_clean_phone, 1, 2) = '91' THEN
    v_clean_phone := substring(v_clean_phone, 3);
  END IF;
  v_hash := encode(extensions.digest('cr:' || v_clean_phone, 'sha256'), 'hex');

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'community_phone_blacklist') THEN
    IF EXISTS (SELECT 1 FROM community_phone_blacklist
               WHERE phone_hash = v_hash
                  OR phone_hash = encode(extensions.digest('cq:' || v_clean_phone, 'sha256'), 'hex')) THEN
      RAISE EXCEPTION 'Your number has been blocked for spam.';
    END IF;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM community_questions WHERE id = p_question_id AND status='active') THEN
    RAISE EXCEPTION 'Question not found';
  END IF;

  IF (SELECT COUNT(*) FROM community_replies
      WHERE replier_phone_hash = v_hash AND created_at > NOW() - INTERVAL '1 hour') >= 10 THEN
    RAISE EXCEPTION 'Too many replies in the last hour. Please wait.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_keywords k
    WHERE k.active = TRUE AND k.severity = 'block'
      AND (
        (k.is_regex AND p_reply_text ~* k.pattern) OR
        (NOT k.is_regex AND position(lower(k.pattern) IN lower(p_reply_text)) > 0)
      )
  ) THEN
    RAISE EXCEPTION 'Your reply contains blocked content';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = '_pucho_pattern_check') THEN
    v_pattern_result := _pucho_pattern_check(p_reply_text);
    IF v_pattern_result = 'block' THEN
      RAISE EXCEPTION 'External links not allowed in replies';
    ELSIF v_pattern_result = 'flag' THEN
      v_initial_status := 'flagged';
    END IF;
  END IF;

  IF v_initial_status = 'active' AND EXISTS (
    SELECT 1 FROM blocked_keywords k
    WHERE k.active = TRUE AND k.severity = 'flag'
      AND (
        (k.is_regex AND p_reply_text ~* k.pattern) OR
        (NOT k.is_regex AND position(lower(k.pattern) IN lower(p_reply_text)) > 0)
      )
  ) THEN
    v_initial_status := 'flagged';
  END IF;

  INSERT INTO community_replies (question_id, replier_name, replier_phone_hash, business_id, reply_text, status)
  VALUES (
    p_question_id,
    NULLIF(trim(coalesce(p_replier_name, '')), ''),
    v_hash, p_business_id, trim(p_reply_text), v_initial_status
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION post_community_reply(UUID, TEXT, TEXT, TEXT, UUID) TO anon, authenticated;

-- 4. Replace report_community_item with extensions.digest
DROP FUNCTION IF EXISTS report_community_item(TEXT, UUID, TEXT, TEXT);
CREATE OR REPLACE FUNCTION report_community_item(
  p_type   TEXT,
  p_id     UUID,
  p_reason TEXT,
  p_reporter_phone TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
DECLARE
  v_hash TEXT;
  v_clean_phone TEXT;
  v_total_reports INT;
BEGIN
  IF p_type NOT IN ('question','reply') THEN
    RAISE EXCEPTION 'Invalid type';
  END IF;

  v_clean_phone := regexp_replace(coalesce(p_reporter_phone, ''), '[^0-9]', '', 'g');
  IF length(v_clean_phone) < 10 THEN
    RAISE EXCEPTION 'Valid mobile number required';
  END IF;
  IF length(v_clean_phone) >= 12 AND substring(v_clean_phone, 1, 2) = '91' THEN
    v_clean_phone := substring(v_clean_phone, 3);
  END IF;
  v_hash := encode(extensions.digest('rep:' || v_clean_phone, 'sha256'), 'hex');

  IF (SELECT COUNT(*) FROM community_reports
      WHERE reporter_phone_hash = v_hash AND created_at > NOW() - INTERVAL '1 hour') >= 20 THEN
    RAISE EXCEPTION 'Too many reports submitted recently. Please wait.';
  END IF;

  INSERT INTO community_reports (target_type, target_id, reporter_phone_hash, reason)
  VALUES (p_type, p_id, v_hash, NULLIF(trim(coalesce(p_reason, '')), ''))
  ON CONFLICT (target_type, target_id, reporter_phone_hash) DO NOTHING;

  SELECT COUNT(DISTINCT reporter_phone_hash) INTO v_total_reports
  FROM community_reports WHERE target_type = p_type AND target_id = p_id;

  IF v_total_reports >= 3 THEN
    IF p_type = 'question' THEN
      UPDATE community_questions SET status = 'flagged'
        WHERE id = p_id AND status = 'active';
    ELSE
      UPDATE community_replies SET status = 'flagged'
        WHERE id = p_id AND status = 'active';
    END IF;
  END IF;

  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION report_community_item(TEXT, UUID, TEXT, TEXT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- Quick smoke-test
DO $$
DECLARE v_test TEXT;
BEGIN
  -- Make sure extensions.digest is callable
  SELECT encode(extensions.digest('test', 'sha256'), 'hex') INTO v_test;
  IF v_test IS NULL OR length(v_test) <> 64 THEN
    RAISE EXCEPTION 'extensions.digest sanity check failed';
  END IF;
  RAISE NOTICE 'pgcrypto OK. Sample hash: %', substring(v_test, 1, 16);
END $$;

COMMIT;
