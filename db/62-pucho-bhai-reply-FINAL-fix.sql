-- =====================================================
-- db/62-pucho-bhai-reply-FINAL-fix.sql
-- =====================================================
-- USER REPORTED: 'Reply post nahi ho raha abhi bhi'
-- + 'Self-Q&A abuse — koi apna khud sawal puch ke khud reply kare?'
--
-- THIS FILE:
--   1. Minimal, bullet-proof post_community_reply RPC
--   2. Inline URL check (no helper function dependency)
--   3. Crystal-clear error messages user can act on
--   4. NEW: Self-reply block — asker cannot reply to own question
--      (community honesty + abuse prevention)
--
-- 100% idempotent. Safe to re-run on any state.
-- =====================================================

BEGIN;

-- Ensure pgcrypto
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- Drop + recreate cleanly
DROP FUNCTION IF EXISTS post_community_reply(UUID, TEXT, TEXT, TEXT, UUID);

CREATE OR REPLACE FUNCTION post_community_reply(
  p_question_id  UUID,
  p_reply_text   TEXT,
  p_replier_name TEXT,
  p_replier_phone TEXT,
  p_business_id  UUID
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
DECLARE
  v_clean TEXT;
  v_hash_cr TEXT;
  v_hash_cq TEXT;
  v_q_asker_hash TEXT;
  v_id UUID;
BEGIN
  -- Validate inputs
  IF p_question_id IS NULL THEN
    RAISE EXCEPTION 'Question ID is required';
  END IF;

  IF p_reply_text IS NULL OR length(trim(p_reply_text)) < 4 THEN
    RAISE EXCEPTION 'Reply must be at least 4 characters';
  END IF;

  IF length(p_reply_text) > 1000 THEN
    RAISE EXCEPTION 'Reply too long (max 1000 chars)';
  END IF;

  -- Phone normalize
  v_clean := regexp_replace(coalesce(p_replier_phone,''), '[^0-9]', '', 'g');
  IF length(v_clean) < 10 THEN
    RAISE EXCEPTION 'Valid 10-digit mobile number required';
  END IF;
  IF length(v_clean) >= 12 AND substring(v_clean,1,2) = '91' THEN
    v_clean := substring(v_clean,3);
  END IF;

  -- Hash this user with both prefixes (cr: for replier, cq: for asker compare)
  v_hash_cr := encode(extensions.digest('cr:' || v_clean, 'sha256'), 'hex');
  v_hash_cq := encode(extensions.digest('cq:' || v_clean, 'sha256'), 'hex');

  -- Verify question exists + get asker hash
  SELECT asker_phone_hash INTO v_q_asker_hash
  FROM community_questions
  WHERE id = p_question_id AND status='active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Question not found or no longer active';
  END IF;

  -- ===== SELF-REPLY BLOCK =====
  -- If this user's cq: hash matches the question's asker hash → same person.
  -- Block to keep community Q&A honest (prevent self-promotion).
  IF v_q_asker_hash = v_hash_cq THEN
    RAISE EXCEPTION 'You posted this question yourself. To add more info, edit your question — don''t reply to your own post.';
  END IF;

  -- Blacklist check (idempotent — table from db/53)
  IF EXISTS (
    SELECT 1 FROM community_phone_blacklist
    WHERE phone_hash IN (v_hash_cr, v_hash_cq)
  ) THEN
    RAISE EXCEPTION 'Your number is blocked from posting';
  END IF;

  -- Rate limit: 10 replies / hour
  IF (SELECT COUNT(*) FROM community_replies
      WHERE replier_phone_hash = v_hash_cr
        AND created_at > NOW() - INTERVAL '1 hour') >= 10 THEN
    RAISE EXCEPTION 'Too many replies in the last hour. Please wait.';
  END IF;

  -- Block external URLs (inline regex — no helper dependency)
  IF p_reply_text ~* '(https?://|www\.|[a-z0-9-]+\.(com|in|net|org|co|biz|info|me|link))' THEN
    RAISE EXCEPTION 'External links not allowed in replies. Share contact number only.';
  END IF;

  -- Block 'block' severity keywords (graceful if table missing)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='blocked_keywords') THEN
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
  END IF;

  -- All checks passed → INSERT as ACTIVE (no auto-flag for phones — feature)
  INSERT INTO community_replies (
    question_id, replier_name, replier_phone_hash,
    business_id, reply_text, status
  ) VALUES (
    p_question_id,
    NULLIF(trim(coalesce(p_replier_name,'')),''),
    v_hash_cr,
    p_business_id,
    trim(p_reply_text),
    'active'
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION post_community_reply(UUID, TEXT, TEXT, TEXT, UUID) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- ===== Smoke test =====
DO $$
DECLARE
  v_test TEXT;
  v_fn_count INT;
BEGIN
  -- pgcrypto check
  SELECT encode(extensions.digest('test','sha256'),'hex') INTO v_test;
  IF length(v_test) <> 64 THEN
    RAISE EXCEPTION 'pgcrypto extensions.digest broken — check Supabase Extensions tab';
  END IF;
  RAISE NOTICE '✓ pgcrypto.digest works (sample: %)', substring(v_test,1,16);

  -- Function exists
  SELECT COUNT(*) INTO v_fn_count FROM pg_proc WHERE proname = 'post_community_reply';
  IF v_fn_count < 1 THEN
    RAISE EXCEPTION 'post_community_reply function not registered';
  END IF;
  RAISE NOTICE '✓ post_community_reply registered (% versions)', v_fn_count;

  RAISE NOTICE '═══ Reply RPC FINAL fix applied. Test by posting a reply now. ═══';
END $$;

COMMIT;
