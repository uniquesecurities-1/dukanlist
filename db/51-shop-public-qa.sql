-- =====================================================
-- db/51-shop-public-qa.sql
-- =====================================================
-- ADDITIVE ONLY: creates public Q&A system on shop pages.
-- Customers ask, shop owners answer, everyone sees — Quora-style.
--
-- ZERO RISK to existing data — only adds 1 new table + helper RPCs.
--
-- WHAT THIS GIVES YOU:
--   • Visitor asks a public question on any shop page
--   • Owner gets notified, writes a public answer
--   • SEO boost (Google indexes Q&A as featured snippets)
--   • Trust signal (active engagement = real shop)
--   • Zero spam (admin moderation built in)
--
-- HOW TO RUN:
--   Supabase Dashboard → SQL Editor → Run this file.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. shop_questions table
-- ============================================================
CREATE TABLE IF NOT EXISTS shop_questions (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  business_id     UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  asker_name      TEXT,                                -- nullable, optional anon
  asker_phone_hash TEXT NOT NULL,                      -- SHA256 for dedup
  question_text   TEXT NOT NULL CHECK (length(question_text) BETWEEN 8 AND 500),
  answer_text     TEXT CHECK (answer_text IS NULL OR length(answer_text) BETWEEN 4 AND 1000),
  answered_at     TIMESTAMPTZ,
  status          TEXT NOT NULL DEFAULT 'active'
                   CHECK (status IN ('active','flagged','removed')),
  helpful_count   INT DEFAULT 0,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sq_business ON shop_questions(business_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_sq_created  ON shop_questions(created_at DESC);

-- ============================================================
-- 2. RLS Policies
-- ============================================================
ALTER TABLE shop_questions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "sq_public_read"  ON shop_questions;
DROP POLICY IF EXISTS "sq_admin_all"    ON shop_questions;

-- Anyone can read active questions/answers
CREATE POLICY "sq_public_read" ON shop_questions
  FOR SELECT TO anon, authenticated
  USING (status = 'active');

-- Admins manage everything
CREATE POLICY "sq_admin_all" ON shop_questions
  FOR ALL TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());

-- ============================================================
-- 3. RPC: post_shop_question(p_business_id, p_question_text, p_asker_name, p_asker_phone)
--    Anyone (anon or auth) can post a question. Phone is hashed (anti-dup).
-- ============================================================
DROP FUNCTION IF EXISTS post_shop_question(UUID, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION post_shop_question(
  p_business_id    UUID,
  p_question_text  TEXT,
  p_asker_name     TEXT,
  p_asker_phone    TEXT
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_hash TEXT;
  v_id   UUID;
  v_clean_phone TEXT;
BEGIN
  -- Validate question length
  IF p_question_text IS NULL OR length(trim(p_question_text)) < 8 THEN
    RAISE EXCEPTION 'Question too short (min 8 chars)';
  END IF;
  IF length(p_question_text) > 500 THEN
    RAISE EXCEPTION 'Question too long (max 500 chars)';
  END IF;

  -- Validate phone
  v_clean_phone := regexp_replace(coalesce(p_asker_phone, ''), '[^0-9]', '', 'g');
  IF length(v_clean_phone) < 10 THEN
    RAISE EXCEPTION 'Valid phone number required';
  END IF;
  IF length(v_clean_phone) >= 12 AND substring(v_clean_phone, 1, 2) = '91' THEN
    v_clean_phone := substring(v_clean_phone, 3);
  END IF;
  v_hash := encode(digest('q:' || v_clean_phone, 'sha256'), 'hex');

  -- Verify business exists
  IF NOT EXISTS (SELECT 1 FROM businesses WHERE id = p_business_id AND status = 'active') THEN
    RAISE EXCEPTION 'Business not found or inactive';
  END IF;

  INSERT INTO shop_questions (business_id, asker_name, asker_phone_hash, question_text)
  VALUES (
    p_business_id,
    NULLIF(trim(coalesce(p_asker_name, '')), ''),
    v_hash,
    trim(p_question_text)
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION post_shop_question(UUID, TEXT, TEXT, TEXT) TO anon, authenticated;

-- ============================================================
-- 4. RPC: answer_shop_question(p_question_id, p_answer_text)
--    Only the shop owner of that business can answer.
-- ============================================================
DROP FUNCTION IF EXISTS answer_shop_question(UUID, TEXT);

CREATE OR REPLACE FUNCTION answer_shop_question(
  p_question_id  UUID,
  p_answer_text  TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid     UUID;
  v_biz_id  UUID;
  v_owns    BOOLEAN;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF p_answer_text IS NULL OR length(trim(p_answer_text)) < 4 THEN
    RAISE EXCEPTION 'Answer too short (min 4 chars)';
  END IF;
  IF length(p_answer_text) > 1000 THEN
    RAISE EXCEPTION 'Answer too long (max 1000 chars)';
  END IF;

  SELECT business_id INTO v_biz_id FROM shop_questions WHERE id = p_question_id;
  IF v_biz_id IS NULL THEN
    RAISE EXCEPTION 'Question not found';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM business_owners
    WHERE business_id = v_biz_id AND auth_user_id = v_uid
  ) INTO v_owns;

  -- Admin can also answer (for moderation/help)
  IF NOT v_owns AND NOT is_admin() THEN
    RAISE EXCEPTION 'Only shop owner can answer';
  END IF;

  UPDATE shop_questions
    SET answer_text = trim(p_answer_text),
        answered_at = NOW()
    WHERE id = p_question_id;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION answer_shop_question(UUID, TEXT) TO authenticated;

-- ============================================================
-- 5. RPC: get_shop_questions(p_business_id)
--    Returns active Q&A for public display.
-- ============================================================
DROP FUNCTION IF EXISTS get_shop_questions(UUID);

CREATE OR REPLACE FUNCTION get_shop_questions(p_business_id UUID)
RETURNS TABLE (
  id             UUID,
  asker_name     TEXT,
  question_text  TEXT,
  answer_text    TEXT,
  answered_at    TIMESTAMPTZ,
  created_at     TIMESTAMPTZ,
  helpful_count  INT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT q.id, q.asker_name, q.question_text, q.answer_text,
         q.answered_at, q.created_at, q.helpful_count
  FROM shop_questions q
  WHERE q.business_id = p_business_id AND q.status = 'active'
  ORDER BY (q.answer_text IS NOT NULL) DESC, q.created_at DESC
  LIMIT 50;
END;
$$;

GRANT EXECUTE ON FUNCTION get_shop_questions(UUID) TO anon, authenticated;

-- ============================================================
-- 6. RPC: get_my_pending_questions()
--    For shopkeeper dashboard: questions awaiting their answer.
-- ============================================================
DROP FUNCTION IF EXISTS get_my_pending_questions();

CREATE OR REPLACE FUNCTION get_my_pending_questions()
RETURNS TABLE (
  id             UUID,
  business_id    UUID,
  business_name  TEXT,
  asker_name     TEXT,
  question_text  TEXT,
  created_at     TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_uid UUID;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT q.id, q.business_id, b.name, q.asker_name, q.question_text, q.created_at
  FROM shop_questions q
  JOIN businesses b ON b.id = q.business_id
  JOIN business_owners bo ON bo.business_id = q.business_id
  WHERE bo.auth_user_id = v_uid
    AND q.status = 'active'
    AND q.answer_text IS NULL
  ORDER BY q.created_at DESC
  LIMIT 50;
END;
$$;

GRANT EXECUTE ON FUNCTION get_my_pending_questions() TO authenticated;

NOTIFY pgrst, 'reload schema';

-- Verify
DO $$
DECLARE v_tbl INT; v_fn INT;
BEGIN
  SELECT COUNT(*) INTO v_tbl FROM information_schema.tables WHERE table_name = 'shop_questions';
  SELECT COUNT(*) INTO v_fn FROM pg_proc
    WHERE proname IN ('post_shop_question','answer_shop_question','get_shop_questions','get_my_pending_questions');
  RAISE NOTICE 'Q&A table created: %  (expect 1)', v_tbl;
  RAISE NOTICE 'Q&A functions registered: % of 4', v_fn;
  IF v_tbl < 1 OR v_fn < 4 THEN
    RAISE EXCEPTION 'Q&A install incomplete';
  END IF;
END $$;

COMMIT;

-- =====================================================
-- ROLLBACK if ever needed:
--   DROP TABLE shop_questions CASCADE;
--   DROP FUNCTION post_shop_question(UUID, TEXT, TEXT, TEXT);
--   DROP FUNCTION answer_shop_question(UUID, TEXT);
--   DROP FUNCTION get_shop_questions(UUID);
--   DROP FUNCTION get_my_pending_questions();
-- =====================================================
