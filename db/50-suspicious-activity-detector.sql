-- =====================================================
-- db/50-suspicious-activity-detector.sql
-- =====================================================
-- ADDITIVE ONLY: creates admin_get_suspicious_shops() RPC
-- that auto-flags shops with suspicious patterns.
--
-- ZERO RISK to existing data:
--   • No new tables — only a function
--   • Function only READS — never UPDATEs or DELETEs anything
--   • Function does NOT auto-act on detected shops — admin
--     reviews flagged shops manually
--
-- DETECTION RULES (all 8 enabled):
--   1. duplicate_mobile     — same mobile across 2+ shops    (+30 / +50 pts)
--   2. spam_keyword         — matches blocked_keywords table (+40 pts)
--   3. fake_owner_name      — only digits / too short / gibb (+20 pts)
--   4. low_completeness     — no photos/about/usp/email      (+15 pts)
--   5. bulk_registration    — 3+ shops same hour same city   (+25 pts)
--   6. multiple_flags       — flagged_count >= 3             (+30 / +50 pts)
--   7. inactive_verified    — verified, not updated 30+ days (+10 pts)
--   8. mismatched_data      — whatsapp/mobile/pincode issue  (+10 pts)
--
-- Risk score capped at 100. Returns shops with score >= 10.
--
-- HOW TO RUN:
--   Supabase Dashboard → SQL Editor → New Query
--   Paste this file → Run
--
-- HOW TO REMOVE (if you ever want to):
--   DROP FUNCTION admin_get_suspicious_shops();
-- =====================================================

BEGIN;

DROP FUNCTION IF EXISTS admin_get_suspicious_shops();

CREATE OR REPLACE FUNCTION admin_get_suspicious_shops()
RETURNS TABLE (
  business_id     UUID,
  name            TEXT,
  slug            TEXT,
  owner_name      TEXT,
  mobile          TEXT,
  whatsapp        TEXT,
  status          TEXT,
  city_name       TEXT,
  pincode         TEXT,
  primary_cat     TEXT,
  photos_count    INT,
  flagged_count   INT,
  rating_count    INT,
  verified_score  INT,
  created_at      TIMESTAMPTZ,
  updated_at      TIMESTAMPTZ,
  risk_score      INT,
  reasons         TEXT[]
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  RETURN QUERY
  WITH
  -- Normalise mobile/whatsapp by stripping +91/91/leading 0
  base AS (
    SELECT
      b.id, b.name, b.slug, b.owner_name,
      b.mobile, b.whatsapp,
      b.status, b.pincode,
      b.photos_count, b.flagged_count, b.rating_count, b.verified_score,
      b.usp_text, b.about_text, b.email,
      b.created_at, b.updated_at,
      regexp_replace(coalesce(b.mobile, ''),   '^(\+?91|0)', '') AS norm_mobile,
      regexp_replace(coalesce(b.whatsapp, ''), '^(\+?91|0)', '') AS norm_wa
    FROM businesses b
    WHERE b.status NOT IN ('banned', 'self_hidden')
  ),

  -- Rule 1: duplicate mobile
  dup_mob AS (
    SELECT norm_mobile, COUNT(*) AS cnt
    FROM base
    WHERE norm_mobile <> ''
    GROUP BY norm_mobile
    HAVING COUNT(*) >= 2
  ),

  -- Rule 2: spam keyword matches (name / usp / about against blocked_keywords)
  spam_hits AS (
    SELECT DISTINCT b.id
    FROM base b
    CROSS JOIN LATERAL (
      SELECT 1 FROM blocked_keywords k
      WHERE k.active = TRUE
        AND k.severity IN ('block', 'flag')
        AND (
          (k.is_regex AND (
            coalesce(b.name, '')       ~* k.pattern OR
            coalesce(b.usp_text, '')   ~* k.pattern OR
            coalesce(b.about_text, '') ~* k.pattern
          )) OR
          (NOT k.is_regex AND (
            position(lower(k.pattern) IN lower(coalesce(b.name, ''))) > 0 OR
            position(lower(k.pattern) IN lower(coalesce(b.usp_text, ''))) > 0 OR
            position(lower(k.pattern) IN lower(coalesce(b.about_text, ''))) > 0
          ))
        )
      LIMIT 1
    ) AS m
  ),

  -- Rule 5: bulk registrations (3+ shops in same hour)
  bulk_hits AS (
    SELECT b.id
    FROM base b
    WHERE EXISTS (
      SELECT 1 FROM base b2
      WHERE b2.id <> b.id
        AND b2.created_at BETWEEN b.created_at - INTERVAL '30 minutes'
                              AND b.created_at + INTERVAL '30 minutes'
      GROUP BY b2.id
      HAVING COUNT(*) >= 0
    )
    GROUP BY b.id
    HAVING (
      SELECT COUNT(*) FROM base b3
      WHERE b3.created_at BETWEEN b.created_at - INTERVAL '30 minutes'
                              AND b.created_at + INTERVAL '30 minutes'
    ) >= 3
  ),

  -- Per-shop scoring
  scored AS (
    SELECT
      b.id, b.name, b.slug, b.owner_name, b.mobile, b.whatsapp,
      b.status, b.pincode, b.photos_count, b.flagged_count,
      b.rating_count, b.verified_score, b.created_at, b.updated_at,

      -- Rule 1: duplicate mobile
      CASE
        WHEN b.norm_mobile <> '' AND EXISTS (SELECT 1 FROM dup_mob d WHERE d.norm_mobile = b.norm_mobile AND d.cnt >= 3) THEN 50
        WHEN b.norm_mobile <> '' AND EXISTS (SELECT 1 FROM dup_mob d WHERE d.norm_mobile = b.norm_mobile) THEN 30
        ELSE 0
      END AS pts_dup_mobile,

      -- Rule 2: spam keyword
      CASE WHEN EXISTS (SELECT 1 FROM spam_hits s WHERE s.id = b.id) THEN 40 ELSE 0 END AS pts_spam,

      -- Rule 3: fake-looking owner name
      CASE
        WHEN b.owner_name IS NULL OR length(trim(b.owner_name)) < 2 THEN 20
        WHEN trim(b.owner_name) ~ '^[0-9]+$' THEN 20            -- only digits
        WHEN trim(b.owner_name) ~ '^[a-zA-Z]{1,2}$' THEN 20     -- 1-2 letters
        WHEN length(trim(b.owner_name)) <= 4
             AND b.owner_name ~ '^[A-Z]+$' THEN 15              -- all caps very short
        ELSE 0
      END AS pts_fake_name,

      -- Rule 4: low completeness
      CASE WHEN
            coalesce(b.photos_count, 0) = 0
        AND (b.usp_text IS NULL OR trim(b.usp_text) = '')
        AND (b.about_text IS NULL OR trim(b.about_text) = '')
        AND (b.email IS NULL OR trim(b.email) = '')
      THEN 15 ELSE 0 END AS pts_low_complete,

      -- Rule 5: bulk registration
      CASE WHEN EXISTS (SELECT 1 FROM bulk_hits bh WHERE bh.id = b.id) THEN 25 ELSE 0 END AS pts_bulk,

      -- Rule 6: multiple flags
      CASE
        WHEN coalesce(b.flagged_count, 0) >= 5 THEN 50
        WHEN coalesce(b.flagged_count, 0) >= 3 THEN 30
        ELSE 0
      END AS pts_flags,

      -- Rule 7: inactive verified
      CASE
        WHEN coalesce(b.verified_score, 0) >= 3
         AND b.updated_at < NOW() - INTERVAL '30 days'
        THEN 10 ELSE 0
      END AS pts_inactive,

      -- Rule 8: mismatched data
      CASE
        WHEN b.norm_wa <> '' AND b.norm_mobile <> '' AND b.norm_wa <> b.norm_mobile
             AND length(b.norm_wa) <> 10
        THEN 10
        WHEN b.pincode IS NOT NULL AND b.pincode <> ''
             AND b.pincode !~ '^[1-9][0-9]{5}$'
        THEN 10
        ELSE 0
      END AS pts_mismatch
    FROM base b
  ),

  -- Build reasons array
  with_reasons AS (
    SELECT
      s.*,
      LEAST(100, s.pts_dup_mobile + s.pts_spam + s.pts_fake_name + s.pts_low_complete
                + s.pts_bulk + s.pts_flags + s.pts_inactive + s.pts_mismatch) AS total_score,
      ARRAY_REMOVE(ARRAY[
        CASE WHEN s.pts_dup_mobile > 0 THEN 'duplicate_mobile' END,
        CASE WHEN s.pts_spam > 0 THEN 'spam_keyword' END,
        CASE WHEN s.pts_fake_name > 0 THEN 'fake_owner_name' END,
        CASE WHEN s.pts_low_complete > 0 THEN 'low_completeness' END,
        CASE WHEN s.pts_bulk > 0 THEN 'bulk_registration' END,
        CASE WHEN s.pts_flags > 0 THEN 'multiple_flags' END,
        CASE WHEN s.pts_inactive > 0 THEN 'inactive_verified' END,
        CASE WHEN s.pts_mismatch > 0 THEN 'mismatched_data' END
      ], NULL) AS rs
    FROM scored s
  )

  SELECT
    w.id,
    w.name,
    w.slug,
    w.owner_name,
    w.mobile,
    w.whatsapp,
    w.status,
    (SELECT gc.name FROM geo_cities gc
       JOIN businesses bb ON bb.city_id = gc.id WHERE bb.id = w.id) AS city_name,
    w.pincode,
    (SELECT c.name FROM categories c
       JOIN businesses bb ON bb.sub_category_id = c.id WHERE bb.id = w.id) AS primary_cat,
    w.photos_count::INT,
    w.flagged_count::INT,
    w.rating_count::INT,
    w.verified_score::INT,
    w.created_at,
    w.updated_at,
    w.total_score::INT,
    w.rs
  FROM with_reasons w
  WHERE w.total_score >= 10
  ORDER BY w.total_score DESC, w.created_at DESC
  LIMIT 200;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_get_suspicious_shops() TO authenticated;

-- =====================================================
-- Lightweight summary function for the admin dashboard
-- badge — returns just the count of high-risk shops.
-- =====================================================
DROP FUNCTION IF EXISTS admin_count_suspicious();

CREATE OR REPLACE FUNCTION admin_count_suspicious()
RETURNS TABLE (high_risk INT, medium_risk INT, low_risk INT, total INT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_high INT; v_med INT; v_low INT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE risk_score >= 60),
    COUNT(*) FILTER (WHERE risk_score >= 30 AND risk_score < 60),
    COUNT(*) FILTER (WHERE risk_score < 30)
  INTO v_high, v_med, v_low
  FROM admin_get_suspicious_shops();

  RETURN QUERY SELECT v_high, v_med, v_low, (v_high + v_med + v_low);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_count_suspicious() TO authenticated;

NOTIFY pgrst, 'reload schema';

DO $$
DECLARE v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count FROM admin_get_suspicious_shops();
  RAISE NOTICE 'admin_get_suspicious_shops returned % rows (suspicious shops detected)', v_count;
END $$;

COMMIT;

-- =====================================================
-- Verify deployment by calling from SQL Editor:
--   SELECT * FROM admin_get_suspicious_shops() LIMIT 20;
--   SELECT * FROM admin_count_suspicious();
--
-- To remove this feature entirely (rollback):
--   DROP FUNCTION admin_get_suspicious_shops();
--   DROP FUNCTION admin_count_suspicious();
-- =====================================================
