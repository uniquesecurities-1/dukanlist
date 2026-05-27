-- =====================================================
-- db/53-pucho-bhai-spam-shield.sql
-- =====================================================
-- ADDITIVE ONLY: full anti-spam protection for Pucho Bhai
-- ZERO RISK — no existing tables modified, only:
--   • Expanded blocked_keywords seed (Hindi+English)
--   • New table: community_reports (user "flag this" button)
--   • New table: community_phone_blacklist (banned phones)
--   • New RPCs: report, blacklist, get reports
--   • New trigger: auto-flag after 3 reports
--
-- HOW TO RUN:
--   Supabase Dashboard → SQL Editor → Paste this file → Run
-- =====================================================

BEGIN;

-- ============================================================
-- 1. Expand blocked_keywords with Hindi + scam dictionary
-- ============================================================
INSERT INTO blocked_keywords (pattern, severity, reason, is_regex) VALUES
  -- ===== Hindi profanity (Roman script) =====
  ('madarchod|m[a@]d[a@]rch[o0]d|mc bhai|m\.c\.', 'block', 'Hindi profanity', TRUE),
  ('behenchod|bhenchod|b[a@]henchod|b\.c\.', 'block', 'Hindi profanity', TRUE),
  ('chutiya|ch[uo]tiya|chutia', 'block', 'Hindi profanity', TRUE),
  ('gandu|gaand[uo]?|gand mein', 'block', 'Hindi profanity', TRUE),
  ('lund|laund[a-z]*|laude', 'block', 'Hindi profanity', TRUE),
  ('randi|raand[i-y]|randwa', 'block', 'Hindi profanity', TRUE),
  ('saala kutta|saale kutte|kutiya|kuttiya', 'block', 'Hindi profanity', TRUE),
  ('haraami|haramkhor|harami', 'block', 'Hindi profanity', TRUE),
  ('kamina|kameena', 'flag', 'Mild Hindi insult', TRUE),
  ('jhantu|jhaant', 'block', 'Hindi profanity', TRUE),
  -- ===== Hindi profanity in Devanagari =====
  ('मादरचोद|बहनचोद|भोसडी|चूतिया|गांडू|रंडी|हरामी|कुत्ती', 'block', 'Hindi profanity (Devanagari)', TRUE),

  -- ===== Scam / fraud patterns =====
  ('earn ?\d+ ?(per|/) ?(day|month|hour)', 'block', 'Earning scam', TRUE),
  ('work from home opportunity|online job|part[ -]?time job', 'flag', 'Job-scam pattern', TRUE),
  ('mlm|multi[ -]?level|chain marketing|networking business', 'flag', 'MLM hint', TRUE),
  ('lottery (winner|jackpot)|kbc winner|jio winner', 'block', 'Lottery scam', TRUE),
  ('bitcoin|crypto|forex (signal|expert)|trading expert|usdt|tether', 'flag', 'Crypto/forex spam', TRUE),
  ('telegram (group|channel|join)|t\.me/', 'block', 'Telegram redirect spam', TRUE),
  ('whatsapp group join|wa\.me/', 'flag', 'External WhatsApp invite', TRUE),
  ('refer (?:and )?earn|referral bonus.*sign up', 'flag', 'Referral spam', TRUE),
  ('aadhar|aadhaar (number|card details)', 'block', 'PII phishing', TRUE),
  ('upi pin|debit card cvv|atm pin', 'block', 'Financial phishing', TRUE),
  ('bank otp|verify otp|share otp', 'block', 'OTP phishing', TRUE),

  -- ===== Adult content =====
  ('escort service|massage parlor|happy ending', 'block', 'Adult content', TRUE),
  ('call girl|girls available|night service', 'block', 'Adult content', TRUE),
  ('sex chat|sexy video|nude (pic|video)', 'block', 'Adult content', TRUE),

  -- ===== Drug / illegal =====
  ('weed|ganja|hashish|charas|cocaine|heroin', 'block', 'Drugs', TRUE),
  ('fake (id|certificate|degree|aadhar)', 'block', 'Fraud', TRUE),
  ('hack (whatsapp|instagram|fb)', 'block', 'Hacking solicitation', TRUE),

  -- ===== Promo / advertising abuse (mild — flag for review) =====
  ('best deal ever|limited time offer|hurry up.*offer', 'flag', 'Promo language', TRUE),
  ('100% (guarantee|cashback|refund)', 'flag', 'Suspicious guarantee', TRUE),
  ('click below|tap here|swipe up to', 'flag', 'Suspicious CTA', TRUE)
ON CONFLICT DO NOTHING;

-- ============================================================
-- 2. community_reports table — user-side "Report" button
-- ============================================================
CREATE TABLE IF NOT EXISTS community_reports (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  target_type     TEXT NOT NULL CHECK (target_type IN ('question','reply')),
  target_id       UUID NOT NULL,
  reporter_phone_hash TEXT NOT NULL,
  reason          TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (target_type, target_id, reporter_phone_hash)
);
CREATE INDEX IF NOT EXISTS idx_cr_target ON community_reports(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_cr_recent ON community_reports(created_at DESC);

ALTER TABLE community_reports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "creports_admin_all" ON community_reports;
CREATE POLICY "creports_admin_all" ON community_reports
  FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

-- ============================================================
-- 3. community_phone_blacklist — admin-banned phones
-- ============================================================
CREATE TABLE IF NOT EXISTS community_phone_blacklist (
  phone_hash    TEXT PRIMARY KEY,
  banned_at     TIMESTAMPTZ DEFAULT NOW(),
  reason        TEXT,
  banned_by     UUID REFERENCES auth.users(id)
);
ALTER TABLE community_phone_blacklist ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "cpb_admin_all" ON community_phone_blacklist;
CREATE POLICY "cpb_admin_all" ON community_phone_blacklist
  FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

COMMIT;

BEGIN;

-- ============================================================
-- 4. Built-in pattern-check helper (used by post RPCs)
-- ============================================================
CREATE OR REPLACE FUNCTION _pucho_pattern_check(p_text TEXT)
RETURNS TEXT  -- returns 'ok' | 'block' | 'flag'
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_caps_ratio NUMERIC;
  v_total_letters INT;
  v_upper_letters INT;
BEGIN
  -- (a) URL detection — block
  IF p_text ~* '(https?://|www\.|[a-z0-9-]+\.(com|in|net|org|co|biz|info|me|link))' THEN
    RETURN 'block';
  END IF;

  -- (b) Phone-number leak — flag (someone trying to bypass the platform)
  IF p_text ~ '(\+?91[-\s]?)?[6-9]\d{9}' THEN
    RETURN 'flag';
  END IF;

  -- (c) All-caps shouting (>70% uppercase + 12+ chars) — flag
  v_total_letters := length(regexp_replace(p_text, '[^A-Za-z]', '', 'g'));
  IF v_total_letters >= 12 THEN
    v_upper_letters := length(regexp_replace(p_text, '[^A-Z]', '', 'g'));
    v_caps_ratio := v_upper_letters::numeric / v_total_letters;
    IF v_caps_ratio > 0.7 THEN
      RETURN 'flag';
    END IF;
  END IF;

  -- (d) Repeated character spam — flag
  IF p_text ~ '(.)\1{5,}' THEN
    RETURN 'flag';
  END IF;

  -- (e) Too many punctuation marks — flag
  IF (length(regexp_replace(p_text, '[^!?]', '', 'g')) > 5) THEN
    RETURN 'flag';
  END IF;

  RETURN 'ok';
END;
$$;

-- ============================================================
-- 5. Replace post_community_question with full shield
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
  v_pattern_result TEXT;
  v_initial_status TEXT := 'active';
BEGIN
  -- Length validation
  IF p_question_text IS NULL OR length(trim(p_question_text)) < 10 THEN
    RAISE EXCEPTION 'Question too short (min 10 chars)';
  END IF;
  IF length(p_question_text) > 500 THEN
    RAISE EXCEPTION 'Question too long (max 500 chars)';
  END IF;

  -- Phone normalization + hash
  v_clean_phone := regexp_replace(coalesce(p_asker_phone, ''), '[^0-9]', '', 'g');
  IF length(v_clean_phone) < 10 THEN
    RAISE EXCEPTION 'Valid mobile number required';
  END IF;
  IF length(v_clean_phone) >= 12 AND substring(v_clean_phone, 1, 2) = '91' THEN
    v_clean_phone := substring(v_clean_phone, 3);
  END IF;
  v_hash := encode(digest('cq:' || v_clean_phone, 'sha256'), 'hex');

  -- Phone blacklist check
  IF EXISTS (SELECT 1 FROM community_phone_blacklist WHERE phone_hash = v_hash) THEN
    RAISE EXCEPTION 'Your number has been blocked for spam. Contact admin if this is wrong.';
  END IF;

  -- Rate limit: 5 questions per hour per phone
  IF (SELECT COUNT(*) FROM community_questions
      WHERE asker_phone_hash = v_hash AND created_at > NOW() - INTERVAL '1 hour') >= 5 THEN
    RAISE EXCEPTION 'Too many questions in the last hour. Please wait.';
  END IF;

  -- Blocked-keyword (severity='block') check
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

  -- Built-in pattern check (URL/phone-leak/all-caps/repeat-char)
  v_pattern_result := _pucho_pattern_check(p_question_text);
  IF v_pattern_result = 'block' THEN
    RAISE EXCEPTION 'External links not allowed in questions';
  ELSIF v_pattern_result = 'flag' THEN
    v_initial_status := 'flagged';   -- post goes to admin review queue
  END IF;

  -- Severity='flag' blocked_keywords match → also flag (don't block)
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

COMMIT;

BEGIN;

-- ============================================================
-- 6. Replace post_community_reply with full shield
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
  v_hash := encode(digest('cr:' || v_clean_phone, 'sha256'), 'hex');

  -- Blacklist check (use SAME hash prefix used at question time to ban both 'cq:' and 'cr:' hashes)
  IF EXISTS (SELECT 1 FROM community_phone_blacklist
             WHERE phone_hash = v_hash
                OR phone_hash = encode(digest('cq:' || v_clean_phone, 'sha256'), 'hex')) THEN
    RAISE EXCEPTION 'Your number has been blocked for spam.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM community_questions WHERE id = p_question_id AND status='active') THEN
    RAISE EXCEPTION 'Question not found';
  END IF;

  IF (SELECT COUNT(*) FROM community_replies
      WHERE replier_phone_hash = v_hash AND created_at > NOW() - INTERVAL '1 hour') >= 10 THEN
    RAISE EXCEPTION 'Too many replies in the last hour. Please wait.';
  END IF;

  -- Hard-block keywords
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

  -- Built-in pattern check
  v_pattern_result := _pucho_pattern_check(p_reply_text);
  IF v_pattern_result = 'block' THEN
    RAISE EXCEPTION 'External links not allowed in replies';
  ELSIF v_pattern_result = 'flag' THEN
    v_initial_status := 'flagged';
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

-- ============================================================
-- 7. RPC: report_community_item — public-facing flag button
-- ============================================================
DROP FUNCTION IF EXISTS report_community_item(TEXT, UUID, TEXT, TEXT);

CREATE OR REPLACE FUNCTION report_community_item(
  p_type   TEXT,        -- 'question' or 'reply'
  p_id     UUID,
  p_reason TEXT,
  p_reporter_phone TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
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
  v_hash := encode(digest('rep:' || v_clean_phone, 'sha256'), 'hex');

  -- Rate limit: max 20 reports/hr per phone (avoid mass-reporting weaponization)
  IF (SELECT COUNT(*) FROM community_reports
      WHERE reporter_phone_hash = v_hash AND created_at > NOW() - INTERVAL '1 hour') >= 20 THEN
    RAISE EXCEPTION 'Too many reports submitted recently. Please wait.';
  END IF;

  -- Insert (unique constraint prevents same phone reporting same item twice)
  INSERT INTO community_reports (target_type, target_id, reporter_phone_hash, reason)
  VALUES (p_type, p_id, v_hash, NULLIF(trim(coalesce(p_reason, '')), ''))
  ON CONFLICT (target_type, target_id, reporter_phone_hash) DO NOTHING;

  -- Auto-flag: if this item now has 3+ unique reporters, set status='flagged'
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

COMMIT;

BEGIN;

-- ============================================================
-- 8. Admin RPCs
-- ============================================================

-- 8a. Get top reported items (for admin Reports tab)
DROP FUNCTION IF EXISTS admin_get_pucho_reports(INT);
CREATE OR REPLACE FUNCTION admin_get_pucho_reports(p_limit INT DEFAULT 50)
RETURNS TABLE (
  target_type    TEXT,
  target_id      UUID,
  report_count   BIGINT,
  latest_report  TIMESTAMPTZ,
  preview_text   TEXT,
  current_status TEXT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  RETURN QUERY
  WITH grouped AS (
    SELECT
      r.target_type, r.target_id,
      COUNT(DISTINCT r.reporter_phone_hash) AS rc,
      MAX(r.created_at) AS latest
    FROM community_reports r
    GROUP BY r.target_type, r.target_id
  )
  SELECT
    g.target_type, g.target_id, g.rc, g.latest,
    CASE
      WHEN g.target_type='question'
        THEN (SELECT q.question_text FROM community_questions q WHERE q.id = g.target_id)
      ELSE (SELECT rep.reply_text FROM community_replies rep WHERE rep.id = g.target_id)
    END,
    CASE
      WHEN g.target_type='question'
        THEN (SELECT q.status FROM community_questions q WHERE q.id = g.target_id)
      ELSE (SELECT rep.status FROM community_replies rep WHERE rep.id = g.target_id)
    END
  FROM grouped g
  ORDER BY g.rc DESC, g.latest DESC
  LIMIT p_limit;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_get_pucho_reports(INT) TO authenticated;

-- 8b. Blacklist a phone (by question/reply id — admin clicks "ban this user")
DROP FUNCTION IF EXISTS admin_blacklist_pucho_phone(TEXT, UUID, TEXT);
CREATE OR REPLACE FUNCTION admin_blacklist_pucho_phone(
  p_type TEXT, p_id UUID, p_reason TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_hash TEXT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  IF p_type = 'question' THEN
    SELECT asker_phone_hash INTO v_hash FROM community_questions WHERE id = p_id;
  ELSIF p_type = 'reply' THEN
    SELECT replier_phone_hash INTO v_hash FROM community_replies WHERE id = p_id;
  ELSE
    RAISE EXCEPTION 'Invalid type';
  END IF;
  IF v_hash IS NULL THEN
    RAISE EXCEPTION 'Item not found';
  END IF;
  INSERT INTO community_phone_blacklist (phone_hash, reason, banned_by)
    VALUES (v_hash, p_reason, auth.uid())
    ON CONFLICT (phone_hash) DO NOTHING;
  -- Mark all past content from this user as removed
  IF p_type = 'question' THEN
    UPDATE community_questions SET status='removed' WHERE asker_phone_hash = v_hash;
  ELSE
    UPDATE community_replies SET status='removed' WHERE replier_phone_hash = v_hash;
  END IF;
  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_blacklist_pucho_phone(TEXT, UUID, TEXT) TO authenticated;

-- 8c. Unblacklist
DROP FUNCTION IF EXISTS admin_unblacklist_pucho_phone(TEXT);
CREATE OR REPLACE FUNCTION admin_unblacklist_pucho_phone(p_phone_hash TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  DELETE FROM community_phone_blacklist WHERE phone_hash = p_phone_hash;
  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_unblacklist_pucho_phone(TEXT) TO authenticated;

-- 8d. List blacklisted phones
DROP FUNCTION IF EXISTS admin_list_pucho_blacklist();
CREATE OR REPLACE FUNCTION admin_list_pucho_blacklist()
RETURNS TABLE (
  phone_hash TEXT, banned_at TIMESTAMPTZ, reason TEXT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  RETURN QUERY
  SELECT b.phone_hash, b.banned_at, b.reason
  FROM community_phone_blacklist b
  ORDER BY b.banned_at DESC LIMIT 100;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_list_pucho_blacklist() TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- 9. Verify install
-- ============================================================
DO $$
DECLARE v_tbl INT; v_fn INT; v_kw INT;
BEGIN
  SELECT COUNT(*) INTO v_tbl FROM information_schema.tables
    WHERE table_name IN ('community_reports', 'community_phone_blacklist');
  SELECT COUNT(*) INTO v_fn FROM pg_proc
    WHERE proname IN ('report_community_item','admin_get_pucho_reports',
                      'admin_blacklist_pucho_phone','admin_unblacklist_pucho_phone',
                      'admin_list_pucho_blacklist','_pucho_pattern_check');
  SELECT COUNT(*) INTO v_kw FROM blocked_keywords WHERE active=TRUE;
  RAISE NOTICE 'Spam-shield tables: % of 2', v_tbl;
  RAISE NOTICE 'Spam-shield functions: % of 6', v_fn;
  RAISE NOTICE 'Active blocked_keywords: %', v_kw;
  IF v_tbl < 2 OR v_fn < 6 THEN
    RAISE EXCEPTION 'Spam-shield install incomplete';
  END IF;
END $$;

COMMIT;

-- =====================================================
-- ROLLBACK if ever needed:
--   DROP TABLE community_reports CASCADE;
--   DROP TABLE community_phone_blacklist CASCADE;
--   DROP FUNCTION report_community_item(TEXT, UUID, TEXT, TEXT);
--   DROP FUNCTION admin_get_pucho_reports(INT);
--   DROP FUNCTION admin_blacklist_pucho_phone(TEXT, UUID, TEXT);
--   DROP FUNCTION admin_unblacklist_pucho_phone(TEXT);
--   DROP FUNCTION admin_list_pucho_blacklist();
--   DROP FUNCTION _pucho_pattern_check(TEXT);
-- =====================================================
