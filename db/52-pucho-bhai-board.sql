-- =====================================================
-- db/52-pucho-bhai-board.sql
-- =====================================================
-- ADDITIVE ONLY: creates "Pucho Bhai" — community Q&A
-- system (Reddit-style local recommendation board).
--
-- ZERO RISK to existing data:
--   • No existing tables modified — only 2 new tables added
--   • New RPCs only — no existing function changed
--   • RLS protects content properly
--
-- WHAT IT DOES:
--   • Anyone (no login needed) can ASK a question
--   • Anyone can REPLY
--   • Questions filtered by locality (Sirsa, Bathinda, Mandi
--     Dabwali, etc.) — multi-city safe
--   • Admin can hide spam via existing moderation pattern
--   • Phone-hash dedup prevents spammers
--
-- HOW TO RUN:
--   Supabase Dashboard → SQL Editor → New Query → Paste → Run
-- =====================================================

BEGIN;

-- ============================================================
-- 1. community_questions table
-- ============================================================
CREATE TABLE IF NOT EXISTS community_questions (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  city_id         INT REFERENCES geo_cities(id) ON DELETE SET NULL,
  category_id     INT REFERENCES categories(id) ON DELETE SET NULL,
  asker_name      TEXT,                                  -- optional, can be NULL/anon
  asker_phone_hash TEXT NOT NULL,                        -- SHA256 hash for dedup
  question_text   TEXT NOT NULL CHECK (length(question_text) BETWEEN 10 AND 500),
  view_count      INT DEFAULT 0,
  reply_count     INT DEFAULT 0,
  status          TEXT NOT NULL DEFAULT 'active'
                   CHECK (status IN ('active','flagged','removed')),
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cq_city     ON community_questions(city_id) WHERE status='active';
CREATE INDEX IF NOT EXISTS idx_cq_category ON community_questions(category_id) WHERE status='active';
CREATE INDEX IF NOT EXISTS idx_cq_created  ON community_questions(created_at DESC);

-- ============================================================
-- 2. community_replies table
-- ============================================================
CREATE TABLE IF NOT EXISTS community_replies (
  id               UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  question_id      UUID NOT NULL REFERENCES community_questions(id) ON DELETE CASCADE,
  replier_name     TEXT,
  replier_phone_hash TEXT NOT NULL,
  business_id      UUID REFERENCES businesses(id) ON DELETE SET NULL,
  reply_text       TEXT NOT NULL CHECK (length(reply_text) BETWEEN 4 AND 1000),
  helpful_count    INT DEFAULT 0,
  status           TEXT NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active','flagged','removed')),
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cr_question ON community_replies(question_id) WHERE status='active';
CREATE INDEX IF NOT EXISTS idx_cr_business ON community_replies(business_id);

-- Auto-update reply_count on question when reply added
CREATE OR REPLACE FUNCTION _trg_update_question_reply_count() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.status='active' THEN
    UPDATE community_questions
      SET reply_count = reply_count + 1, updated_at = NOW()
      WHERE id = NEW.question_id;
  ELSIF TG_OP = 'UPDATE' THEN
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
CREATE TRIGGER trg_cr_count
  AFTER INSERT OR UPDATE ON community_replies
  FOR EACH ROW EXECUTE FUNCTION _trg_update_question_reply_count();

-- ============================================================
-- 3. RLS Policies
-- ============================================================
ALTER TABLE community_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_replies   ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cq_public_read"  ON community_questions;
DROP POLICY IF EXISTS "cq_admin_all"    ON community_questions;
DROP POLICY IF EXISTS "cr_public_read"  ON community_replies;
DROP POLICY IF EXISTS "cr_admin_all"    ON community_replies;

CREATE POLICY "cq_public_read" ON community_questions
  FOR SELECT TO anon, authenticated USING (status = 'active');
CREATE POLICY "cq_admin_all" ON community_questions
  FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY "cr_public_read" ON community_replies
  FOR SELECT TO anon, authenticated USING (status = 'active');
CREATE POLICY "cr_admin_all" ON community_replies
  FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

-- ============================================================
-- 4. RPC: post_community_question
-- ============================================================
DROP FUNCTION IF EXISTS post_community_question(INT, INT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION post_community_question(
  p_city_id        INT,
  p_category_id    INT,
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
  v_hash := encode(digest('cq:' || v_clean_phone, 'sha256'), 'hex');

  -- Rate-limit: max 5 questions per phone per hour
  IF (SELECT COUNT(*) FROM community_questions
      WHERE asker_phone_hash = v_hash AND created_at > NOW() - INTERVAL '1 hour') >= 5 THEN
    RAISE EXCEPTION 'Too many questions in the last hour. Please wait.';
  END IF;

  -- Spam keyword check (uses existing blocked_keywords table)
  IF EXISTS (
    SELECT 1 FROM blocked_keywords k
    WHERE k.active = TRUE
      AND k.severity = 'block'
      AND (
        (k.is_regex AND p_question_text ~* k.pattern) OR
        (NOT k.is_regex AND position(lower(k.pattern) IN lower(p_question_text)) > 0)
      )
  ) THEN
    RAISE EXCEPTION 'Your question contains blocked content';
  END IF;

  INSERT INTO community_questions (city_id, category_id, asker_name, asker_phone_hash, question_text)
  VALUES (
    p_city_id,
    p_category_id,
    NULLIF(trim(coalesce(p_asker_name, '')), ''),
    v_hash,
    trim(p_question_text)
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION post_community_question(INT, INT, TEXT, TEXT, TEXT) TO anon, authenticated;

-- ============================================================
-- 5. RPC: post_community_reply
-- ============================================================
DROP FUNCTION IF EXISTS post_community_reply(UUID, TEXT, TEXT, TEXT, UUID);

CREATE OR REPLACE FUNCTION post_community_reply(
  p_question_id    UUID,
  p_reply_text     TEXT,
  p_replier_name   TEXT,
  p_replier_phone  TEXT,
  p_business_id    UUID
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_hash TEXT;
  v_id   UUID;
  v_clean_phone TEXT;
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
  v_hash := encode(digest('cr:' || v_clean_phone, 'sha256'), 'hex');

  IF NOT EXISTS (SELECT 1 FROM community_questions WHERE id = p_question_id AND status='active') THEN
    RAISE EXCEPTION 'Question not found';
  END IF;

  -- Rate-limit: max 10 replies per phone per hour
  IF (SELECT COUNT(*) FROM community_replies
      WHERE replier_phone_hash = v_hash AND created_at > NOW() - INTERVAL '1 hour') >= 10 THEN
    RAISE EXCEPTION 'Too many replies in the last hour. Please wait.';
  END IF;

  -- Spam keyword check
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

  INSERT INTO community_replies (question_id, replier_name, replier_phone_hash, business_id, reply_text)
  VALUES (
    p_question_id,
    NULLIF(trim(coalesce(p_replier_name, '')), ''),
    v_hash,
    p_business_id,
    trim(p_reply_text)
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION post_community_reply(UUID, TEXT, TEXT, TEXT, UUID) TO anon, authenticated;

-- ============================================================
-- 6. RPC: get_community_questions
-- ============================================================
DROP FUNCTION IF EXISTS get_community_questions(INT, INT, INT);

CREATE OR REPLACE FUNCTION get_community_questions(
  p_city_id  INT,
  p_limit    INT DEFAULT 30,
  p_offset   INT DEFAULT 0
)
RETURNS TABLE (
  id             UUID,
  city_id        INT,
  city_name      TEXT,
  category_id    INT,
  category_name  TEXT,
  asker_name     TEXT,
  question_text  TEXT,
  view_count     INT,
  reply_count    INT,
  created_at     TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    q.id, q.city_id, c.name, q.category_id, cat.name,
    q.asker_name, q.question_text, q.view_count, q.reply_count, q.created_at
  FROM community_questions q
  LEFT JOIN geo_cities c ON c.id = q.city_id
  LEFT JOIN categories cat ON cat.id = q.category_id
  WHERE q.status = 'active'
    AND (p_city_id IS NULL OR q.city_id = p_city_id)
  ORDER BY q.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION get_community_questions(INT, INT, INT) TO anon, authenticated;

-- ============================================================
-- 7. RPC: get_community_question_detail
-- ============================================================
DROP FUNCTION IF EXISTS get_community_question_detail(UUID);

CREATE OR REPLACE FUNCTION get_community_question_detail(p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_question JSONB;
  v_replies JSONB;
BEGIN
  -- Increment view count (best-effort, no error if fails)
  UPDATE community_questions SET view_count = view_count + 1 WHERE id = p_id AND status='active';

  SELECT to_jsonb(t) INTO v_question FROM (
    SELECT q.id, q.city_id, c.name AS city_name,
           q.category_id, cat.name AS category_name,
           q.asker_name, q.question_text, q.view_count, q.reply_count, q.created_at
    FROM community_questions q
    LEFT JOIN geo_cities c ON c.id = q.city_id
    LEFT JOIN categories cat ON cat.id = q.category_id
    WHERE q.id = p_id AND q.status='active'
  ) t;

  IF v_question IS NULL THEN
    RAISE EXCEPTION 'Question not found';
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY (r->>'helpful_count')::int DESC, r->>'created_at'), '[]'::jsonb) INTO v_replies FROM (
    SELECT
      r.id, r.replier_name, r.reply_text, r.helpful_count, r.created_at,
      r.business_id,
      b.name AS business_name,
      b.slug AS business_slug
    FROM community_replies r
    LEFT JOIN businesses b ON b.id = r.business_id
    WHERE r.question_id = p_id AND r.status='active'
    ORDER BY r.helpful_count DESC, r.created_at ASC
  ) r;

  RETURN jsonb_build_object('question', v_question, 'replies', v_replies);
END;
$$;

GRANT EXECUTE ON FUNCTION get_community_question_detail(UUID) TO anon, authenticated;

-- ============================================================
-- 8. RPC: get_community_city_leaderboard
-- ============================================================
DROP FUNCTION IF EXISTS get_community_city_leaderboard();

CREATE OR REPLACE FUNCTION get_community_city_leaderboard()
RETURNS TABLE (
  city_id        INT,
  city_name      TEXT,
  question_count BIGINT,
  reply_count    BIGINT,
  recent_count   BIGINT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    c.id, c.name,
    COUNT(DISTINCT q.id) AS question_count,
    COUNT(r.id) AS reply_count,
    COUNT(DISTINCT q.id) FILTER (WHERE q.created_at > NOW() - INTERVAL '7 days') AS recent_count
  FROM geo_cities c
  LEFT JOIN community_questions q ON q.city_id = c.id AND q.status='active'
  LEFT JOIN community_replies   r ON r.question_id = q.id AND r.status='active'
  WHERE c.active = TRUE
  GROUP BY c.id, c.name
  HAVING COUNT(DISTINCT q.id) > 0
  ORDER BY question_count DESC, reply_count DESC
  LIMIT 12;
END;
$$;

GRANT EXECUTE ON FUNCTION get_community_city_leaderboard() TO anon, authenticated;

-- ============================================================
-- 9. RPC: admin_moderate_community_item
-- ============================================================
DROP FUNCTION IF EXISTS admin_moderate_community_item(TEXT, UUID, TEXT);

CREATE OR REPLACE FUNCTION admin_moderate_community_item(
  p_type TEXT,        -- 'question' or 'reply'
  p_id   UUID,
  p_new_status TEXT   -- 'active', 'flagged', 'removed'
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  IF p_new_status NOT IN ('active','flagged','removed') THEN
    RAISE EXCEPTION 'Invalid status';
  END IF;

  IF p_type = 'question' THEN
    UPDATE community_questions SET status = p_new_status WHERE id = p_id;
  ELSIF p_type = 'reply' THEN
    UPDATE community_replies SET status = p_new_status WHERE id = p_id;
  ELSE
    RAISE EXCEPTION 'Invalid type';
  END IF;
  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_moderate_community_item(TEXT, UUID, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';

DO $$
DECLARE v_tbl INT; v_fn INT;
BEGIN
  SELECT COUNT(*) INTO v_tbl FROM information_schema.tables
    WHERE table_name IN ('community_questions', 'community_replies');
  SELECT COUNT(*) INTO v_fn FROM pg_proc
    WHERE proname IN ('post_community_question','post_community_reply',
                      'get_community_questions','get_community_question_detail',
                      'get_community_city_leaderboard','admin_moderate_community_item');
  RAISE NOTICE 'Tables: % of 2 · Functions: % of 6', v_tbl, v_fn;
  IF v_tbl < 2 OR v_fn < 6 THEN
    RAISE EXCEPTION 'Install incomplete';
  END IF;
END $$;

COMMIT;

-- =====================================================
-- ROLLBACK if ever needed:
--   DROP TABLE community_replies CASCADE;
--   DROP TABLE community_questions CASCADE;
--   DROP FUNCTION post_community_question(INT, INT, TEXT, TEXT, TEXT);
--   DROP FUNCTION post_community_reply(UUID, TEXT, TEXT, TEXT, UUID);
--   DROP FUNCTION get_community_questions(INT, INT, INT);
--   DROP FUNCTION get_community_question_detail(UUID);
--   DROP FUNCTION get_community_city_leaderboard();
--   DROP FUNCTION admin_moderate_community_item(TEXT, UUID, TEXT);
-- =====================================================
