-- =====================================================
-- db/55-pucho-bhai-detail-fix.sql
-- =====================================================
-- HOTFIX: "operator does not exist: record ->> unknown"
--
-- Triggered when clicking on a question to view its detail
-- (calls get_community_question_detail RPC).
--
-- ROOT CAUSE: db/52 used (r->>'helpful_count')::int inside
--   jsonb_agg(... ORDER BY ...) — but 'r' is a record from
--   a subquery, not a JSONB. The ->> operator only works on
--   JSONB/JSON. Postgres reports the type mismatch.
--
-- FIX: Re-create the function using direct column refs in
--   the jsonb_agg ORDER BY (the columns are exposed by the
--   subquery, so we can use sub.helpful_count etc. directly).
--
-- HOW TO RUN:
--   Supabase Dashboard → SQL Editor → New Query → paste → Run
-- =====================================================

BEGIN;

DROP FUNCTION IF EXISTS get_community_question_detail(UUID);

CREATE OR REPLACE FUNCTION get_community_question_detail(p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_question JSONB;
  v_replies JSONB;
BEGIN
  -- Best-effort view-count increment (only for active questions)
  UPDATE community_questions
    SET view_count = view_count + 1
    WHERE id = p_id AND status = 'active';

  -- ===== Question (top card) =====
  SELECT to_jsonb(t) INTO v_question
  FROM (
    SELECT
      q.id,
      q.city_id,
      c.name        AS city_name,
      q.category_id,
      cat.name      AS category_name,
      q.asker_name,
      q.question_text,
      q.view_count,
      q.reply_count,
      q.created_at
    FROM community_questions q
    LEFT JOIN geo_cities c   ON c.id   = q.city_id
    LEFT JOIN categories cat ON cat.id = q.category_id
    WHERE q.id = p_id AND q.status = 'active'
  ) t;

  IF v_question IS NULL THEN
    RAISE EXCEPTION 'Question not found';
  END IF;

  -- ===== Replies (sorted best-first) =====
  -- Fix: use direct column refs (sub.helpful_count) inside jsonb_agg
  -- ORDER BY — earlier code used (r->>'helpful_count')::int which
  -- treated r as JSONB but r is a record from the subquery.
  SELECT coalesce(
    jsonb_agg(
      to_jsonb(sub)
      ORDER BY sub.helpful_count DESC NULLS LAST, sub.created_at ASC
    ),
    '[]'::jsonb
  ) INTO v_replies
  FROM (
    SELECT
      r.id,
      r.replier_name,
      r.reply_text,
      r.helpful_count,
      r.created_at,
      r.business_id,
      b.name AS business_name,
      b.slug AS business_slug
    FROM community_replies r
    LEFT JOIN businesses b ON b.id = r.business_id
    WHERE r.question_id = p_id AND r.status = 'active'
  ) sub;

  RETURN jsonb_build_object(
    'question', v_question,
    'replies',  v_replies
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_community_question_detail(UUID) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- ===== Smoke test =====
DO $$
DECLARE
  v_test_id UUID;
  v_result JSONB;
BEGIN
  -- Pick the most recent active question (if any) and call the RPC
  SELECT id INTO v_test_id FROM community_questions
    WHERE status='active'
    ORDER BY created_at DESC LIMIT 1;
  IF v_test_id IS NOT NULL THEN
    v_result := get_community_question_detail(v_test_id);
    IF v_result IS NULL OR NOT (v_result ? 'question') THEN
      RAISE EXCEPTION 'detail RPC returned unexpected shape: %', v_result;
    END IF;
    RAISE NOTICE 'detail RPC OK on question %', v_test_id;
  ELSE
    RAISE NOTICE 'No active question found to test — function still recreated';
  END IF;
END $$;

COMMIT;
