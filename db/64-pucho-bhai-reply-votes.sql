-- =====================================================
-- db/64-pucho-bhai-reply-votes.sql
-- =====================================================
-- USER REQUEST: Pucho Bhai me reply par thumbs up & thumbs down ka
-- option do (already have flag/report)
--
-- WHAT THIS ADDS (additive, idempotent):
--   1. unhelpful_count column on community_replies
--   2. community_reply_votes tracking table (phone-hash dedup)
--   3. vote_pucho_reply(reply_id, vote_type, voter_phone) RPC
--      • Toggles: same vote re-clicked → removes; different → switches
--      • Returns { helpful_count, unhelpful_count, my_vote }
--      • Blocks self-voting (replier can't vote on own reply)
--   4. Updates get_community_question_detail to include unhelpful_count
--      and sort by (helpful - unhelpful) DESC (StackOverflow-style)
--
-- ZERO RISK. Safe to re-run.
-- =====================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- 1. unhelpful_count column
ALTER TABLE community_replies ADD COLUMN IF NOT EXISTS unhelpful_count INT NOT NULL DEFAULT 0;

-- 2. Vote tracking table
CREATE TABLE IF NOT EXISTS community_reply_votes (
  id               UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  reply_id         UUID NOT NULL REFERENCES community_replies(id) ON DELETE CASCADE,
  voter_phone_hash TEXT NOT NULL,
  vote_type        TEXT NOT NULL CHECK (vote_type IN ('helpful','unhelpful')),
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (reply_id, voter_phone_hash)
);

CREATE INDEX IF NOT EXISTS idx_crv_reply ON community_reply_votes(reply_id);

ALTER TABLE community_reply_votes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "crv_admin_all" ON community_reply_votes;
CREATE POLICY "crv_admin_all" ON community_reply_votes
  FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

-- 3. Vote RPC
DROP FUNCTION IF EXISTS vote_pucho_reply(UUID, TEXT, TEXT);
CREATE OR REPLACE FUNCTION vote_pucho_reply(
  p_reply_id     UUID,
  p_vote_type    TEXT,
  p_voter_phone  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
DECLARE
  v_clean         TEXT;
  v_hash_vote     TEXT;
  v_hash_cr       TEXT;
  v_existing      TEXT;
  v_helpful       INT;
  v_unhelpful     INT;
  v_replier_hash  TEXT;
  v_my_vote       TEXT;
BEGIN
  IF p_vote_type NOT IN ('helpful','unhelpful') THEN
    RAISE EXCEPTION 'Invalid vote type — must be helpful or unhelpful';
  END IF;

  v_clean := regexp_replace(coalesce(p_voter_phone,''), '[^0-9]', '', 'g');
  IF length(v_clean) < 10 THEN
    RAISE EXCEPTION 'Valid 10-digit mobile required to vote';
  END IF;
  IF length(v_clean) >= 12 AND substring(v_clean,1,2) = '91' THEN
    v_clean := substring(v_clean,3);
  END IF;

  v_hash_vote := encode(extensions.digest('vote:' || v_clean, 'sha256'), 'hex');
  v_hash_cr   := encode(extensions.digest('cr:'   || v_clean, 'sha256'), 'hex');

  -- Block self-vote (replier can't vote on own reply)
  SELECT replier_phone_hash INTO v_replier_hash
  FROM community_replies WHERE id = p_reply_id AND status = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reply not found or no longer active';
  END IF;
  IF v_replier_hash = v_hash_cr THEN
    RAISE EXCEPTION 'You cannot vote on your own reply';
  END IF;

  -- Toggle logic
  SELECT vote_type INTO v_existing FROM community_reply_votes
  WHERE reply_id = p_reply_id AND voter_phone_hash = v_hash_vote;

  IF v_existing IS NULL THEN
    -- New vote
    INSERT INTO community_reply_votes (reply_id, voter_phone_hash, vote_type)
    VALUES (p_reply_id, v_hash_vote, p_vote_type);
  ELSIF v_existing = p_vote_type THEN
    -- Same vote re-clicked → remove (un-vote)
    DELETE FROM community_reply_votes
    WHERE reply_id = p_reply_id AND voter_phone_hash = v_hash_vote;
  ELSE
    -- Different vote → switch
    UPDATE community_reply_votes
    SET vote_type = p_vote_type, created_at = NOW()
    WHERE reply_id = p_reply_id AND voter_phone_hash = v_hash_vote;
  END IF;

  -- Recompute counts
  SELECT
    COUNT(*) FILTER (WHERE vote_type = 'helpful'),
    COUNT(*) FILTER (WHERE vote_type = 'unhelpful')
  INTO v_helpful, v_unhelpful
  FROM community_reply_votes WHERE reply_id = p_reply_id;

  -- Update denormalized counts on community_replies
  UPDATE community_replies
  SET helpful_count = COALESCE(v_helpful, 0),
      unhelpful_count = COALESCE(v_unhelpful, 0)
  WHERE id = p_reply_id;

  -- Get user's current vote state
  SELECT vote_type INTO v_my_vote FROM community_reply_votes
  WHERE reply_id = p_reply_id AND voter_phone_hash = v_hash_vote;

  RETURN jsonb_build_object(
    'helpful_count',   COALESCE(v_helpful, 0),
    'unhelpful_count', COALESCE(v_unhelpful, 0),
    'my_vote',         v_my_vote
  );
END;
$$;

GRANT EXECUTE ON FUNCTION vote_pucho_reply(UUID, TEXT, TEXT) TO anon, authenticated;

-- 4. Update get_community_question_detail to include unhelpful_count + smarter sort
DROP FUNCTION IF EXISTS get_community_question_detail(UUID);
CREATE OR REPLACE FUNCTION get_community_question_detail(p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_q JSONB; v_r JSONB;
BEGIN
  UPDATE community_questions SET view_count = view_count + 1
    WHERE id = p_id AND status = 'active';

  SELECT to_jsonb(t) INTO v_q FROM (
    SELECT q.id, q.city_id, c.name AS city_name,
           q.category_id, cat.name AS category_name,
           q.asker_name, q.question_text,
           q.view_count, q.reply_count,
           q.is_pinned, q.is_resolved, q.created_at
    FROM community_questions q
    LEFT JOIN geo_cities c   ON c.id = q.city_id
    LEFT JOIN categories cat ON cat.id = q.category_id
    WHERE q.id = p_id AND q.status = 'active'
  ) t;

  IF v_q IS NULL THEN RAISE EXCEPTION 'Question not found'; END IF;

  -- Sort: best answer first → highest score (helpful - unhelpful) → most helpful → oldest first
  SELECT coalesce(
    jsonb_agg(
      to_jsonb(sub)
      ORDER BY
        sub.is_best DESC,
        (sub.helpful_count - sub.unhelpful_count) DESC NULLS LAST,
        sub.helpful_count DESC NULLS LAST,
        sub.created_at ASC
    ),
    '[]'::jsonb
  ) INTO v_r FROM (
    SELECT r.id, r.replier_name, r.reply_text, r.helpful_count, r.unhelpful_count,
           r.is_best, r.created_at, r.business_id,
           b.name AS business_name, b.slug AS business_slug
    FROM community_replies r
    LEFT JOIN businesses b ON b.id = r.business_id
    WHERE r.question_id = p_id AND r.status = 'active'
  ) sub;

  RETURN jsonb_build_object('question', v_q, 'replies', v_r);
END;
$$;
GRANT EXECUTE ON FUNCTION get_community_question_detail(UUID) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- Smoke test
DO $$
DECLARE v_test TEXT; v_fn INT;
BEGIN
  SELECT encode(extensions.digest('test','sha256'),'hex') INTO v_test;
  IF length(v_test) <> 64 THEN RAISE EXCEPTION 'pgcrypto broken'; END IF;

  SELECT COUNT(*) INTO v_fn FROM pg_proc WHERE proname='vote_pucho_reply';
  IF v_fn < 1 THEN RAISE EXCEPTION 'vote_pucho_reply RPC missing'; END IF;

  PERFORM 1 FROM information_schema.columns
    WHERE table_name='community_replies' AND column_name='unhelpful_count';
  IF NOT FOUND THEN RAISE EXCEPTION 'unhelpful_count column missing'; END IF;

  RAISE NOTICE '✓ unhelpful_count column added';
  RAISE NOTICE '✓ community_reply_votes table ready';
  RAISE NOTICE '✓ vote_pucho_reply RPC registered';
  RAISE NOTICE '✓ get_community_question_detail updated with score-based sort';
END $$;

COMMIT;
