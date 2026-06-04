-- =====================================================
-- db/98-review-spam-filter.sql
-- =====================================================
-- USER REQUEST (2026-06-04):
--   "Review spam ML — Pucho Bhai jaisa blocked-keywords filter
--    reviews pe bhi laga do"
--
-- DESIGN:
--   * Reuses existing `blocked_keywords` table (no duplication)
--   * Adds `applies_to` column — controls which surface a rule
--     applies on: 'reviews', 'pucho_bhai', 'all', 'shop_content'
--   * Adds review-specific rules (review-fraud patterns)
--   * Adds check_review_content() function — validates new reviews
--   * Adds INSERT trigger on reviews — auto-flag suspicious content
--   * Adds RPC admin_get_flagged_reviews() — moderation queue
--
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. Extend blocked_keywords with applies_to surface
-- ============================================================
ALTER TABLE blocked_keywords
  ADD COLUMN IF NOT EXISTS applies_to TEXT NOT NULL DEFAULT 'all'
  CHECK (applies_to IN ('all', 'shop_content', 'reviews', 'pucho_bhai'));

CREATE INDEX IF NOT EXISTS blocked_keywords_applies_idx
  ON blocked_keywords (applies_to, active) WHERE active = TRUE;


-- ============================================================
-- 2. Add review-specific spam patterns (idempotent inserts)
-- ============================================================
INSERT INTO blocked_keywords (pattern, severity, reason, is_regex, applies_to) VALUES
  -- Promotional / fake review patterns
  ('best (shop|service|store) in (town|city|world|india)',
    'flag', 'Generic promotional language — likely fake review', TRUE, 'reviews'),
  ('5 ?star|five[- ]star|highly recommend(ed)?',
    'flag', 'Common fake review template — verify', TRUE, 'reviews'),
  ('amazing experience|wonderful service|excellent staff',
    'flag', 'Generic praise — likely template review', TRUE, 'reviews'),
  -- Review-bombing / negative attack patterns
  ('cheat(er|ing)?|fraud|scam(mer)?|thief|chor',
    'flag', 'Accusation — review-attack possibility, manual check', TRUE, 'reviews'),
  ('worst (shop|service)|never (go|buy)|stay away|don.?t (visit|buy)',
    'flag', 'Strong negative language — verify', TRUE, 'reviews'),
  -- Contact-info dumping in review text
  ('contact (me|us) at|call me at|whatsapp me',
    'block', 'Review used as ad — contains contact CTA', TRUE, 'reviews'),
  ('@gmail\.com|@yahoo\.com|@hotmail\.com',
    'block', 'Email address in review text not allowed', TRUE, 'reviews'),
  -- Suspicious script patterns
  ('<[a-z]+|javascript:|onerror=|onclick=',
    'block', 'XSS attempt blocked', TRUE, 'reviews'),
  -- Repetitive characters (bots)
  ('(.)\1{6,}',
    'flag', 'Repetitive characters — bot suspicion', TRUE, 'reviews'),
  -- Other-shop name dropping (competitive review spam)
  ('justdial|sulekha|indiamart|google business',
    'flag', 'Competitor mention — verify if relevant', TRUE, 'reviews')
ON CONFLICT DO NOTHING;

-- Update existing all-purpose rules to mark them as 'all'
UPDATE blocked_keywords SET applies_to = 'all' WHERE applies_to IS NULL;


-- ============================================================
-- 3. check_review_content() — runs at insert time
--    Returns 'ok' | 'flag:<reason>' | 'block:<reason>'
-- ============================================================
DROP FUNCTION IF EXISTS check_review_content(TEXT);
CREATE OR REPLACE FUNCTION check_review_content(p_text TEXT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_rec RECORD;
  v_match BOOLEAN;
  v_text TEXT := COALESCE(p_text, '');
BEGIN
  IF length(trim(v_text)) = 0 THEN RETURN 'ok'; END IF;

  FOR v_rec IN
    SELECT pattern, severity, reason, is_regex
      FROM blocked_keywords
     WHERE active = TRUE
       AND applies_to IN ('all', 'reviews')
     ORDER BY CASE severity WHEN 'block' THEN 1 WHEN 'flag' THEN 2 ELSE 3 END
  LOOP
    BEGIN
      IF v_rec.is_regex THEN
        v_match := v_text ~* v_rec.pattern;
      ELSE
        v_match := lower(v_text) LIKE '%' || lower(v_rec.pattern) || '%';
      END IF;
      IF v_match THEN
        RETURN v_rec.severity || ':' || COALESCE(v_rec.reason, v_rec.pattern);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      CONTINUE;  -- malformed regex — skip
    END;
  END LOOP;
  RETURN 'ok';
END;
$$;

GRANT EXECUTE ON FUNCTION check_review_content(TEXT) TO authenticated, anon;


-- ============================================================
-- 4. Trigger — auto-flag/block on review insert
--    Assumes reviews table has a 'status' or 'flagged' column.
--    If not, we add a flagged_reason column safely.
-- ============================================================
ALTER TABLE reviews
  ADD COLUMN IF NOT EXISTS flagged_reason TEXT,
  ADD COLUMN IF NOT EXISTS auto_flagged_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION reviews_spam_filter_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_check TEXT;
BEGIN
  v_check := check_review_content(COALESCE(NEW.comment, NEW.review_text, ''));
  IF v_check LIKE 'block:%' THEN
    RAISE EXCEPTION 'Review blocked: %', substring(v_check from 7)
      USING ERRCODE = 'check_violation';
  ELSIF v_check LIKE 'flag:%' THEN
    NEW.flagged_reason := substring(v_check from 6);
    NEW.auto_flagged_at := NOW();
  END IF;
  RETURN NEW;
END;
$$;

-- Drop old trigger if any, then attach
DROP TRIGGER IF EXISTS reviews_spam_filter ON reviews;
CREATE TRIGGER reviews_spam_filter
  BEFORE INSERT ON reviews
  FOR EACH ROW
  EXECUTE FUNCTION reviews_spam_filter_trigger();


-- ============================================================
-- 5. Admin RPC — list flagged reviews awaiting moderation
-- ============================================================
DROP FUNCTION IF EXISTS admin_get_flagged_reviews(INT);
CREATE OR REPLACE FUNCTION admin_get_flagged_reviews(p_limit INT DEFAULT 50)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  IF p_limit NOT BETWEEN 1 AND 500 THEN p_limit := 50; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id',              r.id,
    'business_id',     r.business_id,
    'business_name',   b.name,
    'business_slug',   b.slug,
    'rating',          r.rating,
    'comment',         COALESCE(r.comment, r.review_text),
    'reviewer_name',   r.reviewer_name,
    'flagged_reason',  r.flagged_reason,
    'auto_flagged_at', r.auto_flagged_at,
    'created_at',      r.created_at
  ) ORDER BY r.auto_flagged_at DESC NULLS LAST), '[]'::jsonb)
  INTO v_result
  FROM reviews r
  LEFT JOIN businesses b ON b.id = r.business_id
  WHERE r.flagged_reason IS NOT NULL
    AND COALESCE(r.status, 'pending') NOT IN ('rejected', 'deleted')
  LIMIT p_limit;

  RETURN jsonb_build_object(
    'count', (SELECT COUNT(*) FROM reviews WHERE flagged_reason IS NOT NULL),
    'rows',  v_result
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_get_flagged_reviews(INT) TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'db/98 installed.';
  RAISE NOTICE '  Added 10 review-specific spam patterns to blocked_keywords';
  RAISE NOTICE '  Trigger reviews_spam_filter active on reviews insert';
  RAISE NOTICE '  Admin RPC: admin_get_flagged_reviews(limit)';
END $$;
