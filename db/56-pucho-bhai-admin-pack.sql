-- =====================================================
-- db/56-pucho-bhai-admin-pack.sql
-- =====================================================
-- ADDITIVE ONLY: Superior admin powers for Pucho Bhai
--
-- WHAT THIS DOES (zero risk to existing data):
--   • Adds 3 new columns:
--       community_questions.is_pinned    BOOL   — sticky to top
--       community_questions.is_resolved  BOOL   — marked solved
--       community_replies.is_best        BOOL   — "Best Answer" highlight
--   • 7 new admin RPCs:
--       admin_pin_pucho_question
--       admin_resolve_pucho_question
--       admin_mark_best_reply
--       admin_edit_pucho_question
--       admin_edit_pucho_reply
--       admin_permanently_delete_pucho     (hard delete from DB)
--       admin_pucho_item_report_count      (preview report count)
--   • Updates get_community_questions to ORDER BY is_pinned DESC + return new flags
--   • Updates get_community_question_detail to sort replies best-first + include is_best
--
-- HOW TO RUN:
--   Supabase Dashboard → SQL Editor → New Query → paste → Run
-- =====================================================

BEGIN;

-- ============================================================
-- 1. New columns
-- ============================================================
ALTER TABLE community_questions
  ADD COLUMN IF NOT EXISTS is_pinned    BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS is_resolved  BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS pinned_at    TIMESTAMPTZ;

ALTER TABLE community_replies
  ADD COLUMN IF NOT EXISTS is_best      BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_cq_pinned
  ON community_questions(is_pinned DESC, pinned_at DESC NULLS LAST, created_at DESC)
  WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_cr_best
  ON community_replies(question_id, is_best DESC, created_at ASC)
  WHERE status = 'active';

-- ============================================================
-- 2. Updated PUBLIC RPC: get_community_questions
--    Now returns is_pinned + is_resolved, sorts pinned first
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
  is_pinned      BOOLEAN,
  is_resolved    BOOLEAN,
  created_at     TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    q.id, q.city_id, c.name, q.category_id, cat.name,
    q.asker_name, q.question_text, q.view_count, q.reply_count,
    q.is_pinned, q.is_resolved, q.created_at
  FROM community_questions q
  LEFT JOIN geo_cities c ON c.id = q.city_id
  LEFT JOIN categories cat ON cat.id = q.category_id
  WHERE q.status = 'active'
    AND (p_city_id IS NULL OR q.city_id = p_city_id)
  ORDER BY q.is_pinned DESC, q.pinned_at DESC NULLS LAST, q.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;
GRANT EXECUTE ON FUNCTION get_community_questions(INT, INT, INT) TO anon, authenticated;

-- ============================================================
-- 3. Updated PUBLIC RPC: get_community_question_detail
--    Returns is_best per reply, sorts best replies first
-- ============================================================
DROP FUNCTION IF EXISTS get_community_question_detail(UUID);

CREATE OR REPLACE FUNCTION get_community_question_detail(p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_question JSONB;
  v_replies  JSONB;
BEGIN
  UPDATE community_questions SET view_count = view_count + 1
    WHERE id = p_id AND status = 'active';

  SELECT to_jsonb(t) INTO v_question
  FROM (
    SELECT q.id, q.city_id, c.name AS city_name,
           q.category_id, cat.name AS category_name,
           q.asker_name, q.question_text,
           q.view_count, q.reply_count,
           q.is_pinned, q.is_resolved,
           q.created_at
    FROM community_questions q
    LEFT JOIN geo_cities c   ON c.id   = q.city_id
    LEFT JOIN categories cat ON cat.id = q.category_id
    WHERE q.id = p_id AND q.status = 'active'
  ) t;

  IF v_question IS NULL THEN
    RAISE EXCEPTION 'Question not found';
  END IF;

  SELECT coalesce(
    jsonb_agg(
      to_jsonb(sub)
      ORDER BY sub.is_best DESC, sub.helpful_count DESC NULLS LAST, sub.created_at ASC
    ),
    '[]'::jsonb
  ) INTO v_replies
  FROM (
    SELECT r.id, r.replier_name, r.reply_text, r.helpful_count, r.is_best,
           r.created_at, r.business_id,
           b.name AS business_name, b.slug AS business_slug
    FROM community_replies r
    LEFT JOIN businesses b ON b.id = r.business_id
    WHERE r.question_id = p_id AND r.status = 'active'
  ) sub;

  RETURN jsonb_build_object('question', v_question, 'replies', v_replies);
END;
$$;
GRANT EXECUTE ON FUNCTION get_community_question_detail(UUID) TO anon, authenticated;

COMMIT;

BEGIN;

-- ============================================================
-- 4. ADMIN RPC: Pin / Unpin a question
-- ============================================================
DROP FUNCTION IF EXISTS admin_pin_pucho_question(UUID, BOOLEAN);
CREATE OR REPLACE FUNCTION admin_pin_pucho_question(p_id UUID, p_pinned BOOLEAN)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  UPDATE community_questions
    SET is_pinned = p_pinned,
        pinned_at = CASE WHEN p_pinned THEN NOW() ELSE NULL END,
        updated_at = NOW()
    WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Question not found';
  END IF;
  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_pin_pucho_question(UUID, BOOLEAN) TO authenticated;

-- ============================================================
-- 5. ADMIN RPC: Mark question as resolved / unresolved
-- ============================================================
DROP FUNCTION IF EXISTS admin_resolve_pucho_question(UUID, BOOLEAN);
CREATE OR REPLACE FUNCTION admin_resolve_pucho_question(p_id UUID, p_resolved BOOLEAN)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  UPDATE community_questions
    SET is_resolved = p_resolved, updated_at = NOW()
    WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Question not found';
  END IF;
  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_resolve_pucho_question(UUID, BOOLEAN) TO authenticated;

-- ============================================================
-- 6. ADMIN RPC: Mark a reply as "Best Answer"
--    Auto-unmarks all other replies on the same question.
-- ============================================================
DROP FUNCTION IF EXISTS admin_mark_best_reply(UUID, BOOLEAN);
CREATE OR REPLACE FUNCTION admin_mark_best_reply(p_reply_id UUID, p_is_best BOOLEAN)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_q_id UUID;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  SELECT question_id INTO v_q_id FROM community_replies WHERE id = p_reply_id;
  IF v_q_id IS NULL THEN
    RAISE EXCEPTION 'Reply not found';
  END IF;
  IF p_is_best THEN
    -- First clear other "best" flags on the same question (single best per question)
    UPDATE community_replies SET is_best = FALSE WHERE question_id = v_q_id AND id <> p_reply_id;
    UPDATE community_replies SET is_best = TRUE  WHERE id = p_reply_id;
    -- Auto-mark question as resolved when there's a best answer
    UPDATE community_questions SET is_resolved = TRUE, updated_at = NOW() WHERE id = v_q_id;
  ELSE
    UPDATE community_replies SET is_best = FALSE WHERE id = p_reply_id;
  END IF;
  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_mark_best_reply(UUID, BOOLEAN) TO authenticated;

-- ============================================================
-- 7. ADMIN RPC: Edit question text (typo fix / PII redact)
-- ============================================================
DROP FUNCTION IF EXISTS admin_edit_pucho_question(UUID, TEXT);
CREATE OR REPLACE FUNCTION admin_edit_pucho_question(p_id UUID, p_new_text TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  IF p_new_text IS NULL OR length(trim(p_new_text)) < 10 THEN
    RAISE EXCEPTION 'Text too short (min 10 chars)';
  END IF;
  IF length(p_new_text) > 500 THEN
    RAISE EXCEPTION 'Text too long (max 500 chars)';
  END IF;
  UPDATE community_questions
    SET question_text = trim(p_new_text), updated_at = NOW()
    WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Question not found';
  END IF;
  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_edit_pucho_question(UUID, TEXT) TO authenticated;

-- ============================================================
-- 8. ADMIN RPC: Edit reply text
-- ============================================================
DROP FUNCTION IF EXISTS admin_edit_pucho_reply(UUID, TEXT);
CREATE OR REPLACE FUNCTION admin_edit_pucho_reply(p_id UUID, p_new_text TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  IF p_new_text IS NULL OR length(trim(p_new_text)) < 4 THEN
    RAISE EXCEPTION 'Text too short (min 4 chars)';
  END IF;
  IF length(p_new_text) > 1000 THEN
    RAISE EXCEPTION 'Text too long (max 1000 chars)';
  END IF;
  UPDATE community_replies SET reply_text = trim(p_new_text) WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reply not found';
  END IF;
  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_edit_pucho_reply(UUID, TEXT) TO authenticated;

-- ============================================================
-- 9. ADMIN RPC: Permanent (hard) delete from DB
--    Use when content is irreparable (PII leak, illegal etc.).
--    Different from status='removed' which keeps the row.
-- ============================================================
DROP FUNCTION IF EXISTS admin_permanently_delete_pucho(TEXT, UUID);
CREATE OR REPLACE FUNCTION admin_permanently_delete_pucho(p_type TEXT, p_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  IF p_type = 'question' THEN
    -- ON DELETE CASCADE will also drop the replies via FK
    DELETE FROM community_questions WHERE id = p_id;
  ELSIF p_type = 'reply' THEN
    DELETE FROM community_replies WHERE id = p_id;
  ELSE
    RAISE EXCEPTION 'Invalid type';
  END IF;
  -- Also drop any reports targeting this item
  DELETE FROM community_reports WHERE target_type = p_type AND target_id = p_id;
  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_permanently_delete_pucho(TEXT, UUID) TO authenticated;

-- ============================================================
-- 10. ADMIN RPC: Quick report-count lookup
-- ============================================================
DROP FUNCTION IF EXISTS admin_pucho_item_report_count(TEXT, UUID);
CREATE OR REPLACE FUNCTION admin_pucho_item_report_count(p_type TEXT, p_id UUID)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_cnt INT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  SELECT COUNT(DISTINCT reporter_phone_hash) INTO v_cnt
  FROM community_reports
  WHERE target_type = p_type AND target_id = p_id;
  RETURN coalesce(v_cnt, 0);
END;
$$;
GRANT EXECUTE ON FUNCTION admin_pucho_item_report_count(TEXT, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- 11. Verification block
-- ============================================================
DO $$
DECLARE v_cols INT; v_fns INT;
BEGIN
  SELECT COUNT(*) INTO v_cols FROM information_schema.columns
    WHERE (table_name = 'community_questions' AND column_name IN ('is_pinned','is_resolved','pinned_at'))
       OR (table_name = 'community_replies' AND column_name = 'is_best');
  SELECT COUNT(*) INTO v_fns FROM pg_proc
    WHERE proname IN ('admin_pin_pucho_question','admin_resolve_pucho_question',
                      'admin_mark_best_reply','admin_edit_pucho_question',
                      'admin_edit_pucho_reply','admin_permanently_delete_pucho',
                      'admin_pucho_item_report_count');
  RAISE NOTICE 'Admin pack columns: % of 4', v_cols;
  RAISE NOTICE 'Admin pack functions: % of 7', v_fns;
  IF v_cols < 4 OR v_fns < 7 THEN
    RAISE EXCEPTION 'Admin pack install incomplete';
  END IF;
END $$;

COMMIT;

-- =====================================================
-- ROLLBACK (in case ever needed):
--   ALTER TABLE community_questions DROP COLUMN is_pinned, DROP COLUMN is_resolved, DROP COLUMN pinned_at;
--   ALTER TABLE community_replies DROP COLUMN is_best;
--   DROP FUNCTION admin_pin_pucho_question(UUID, BOOLEAN);
--   DROP FUNCTION admin_resolve_pucho_question(UUID, BOOLEAN);
--   DROP FUNCTION admin_mark_best_reply(UUID, BOOLEAN);
--   DROP FUNCTION admin_edit_pucho_question(UUID, TEXT);
--   DROP FUNCTION admin_edit_pucho_reply(UUID, TEXT);
--   DROP FUNCTION admin_permanently_delete_pucho(TEXT, UUID);
--   DROP FUNCTION admin_pucho_item_report_count(TEXT, UUID);
-- =====================================================
