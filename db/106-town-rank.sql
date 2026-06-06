-- =====================================================
-- db/106-town-rank.sql
-- =====================================================
-- STRATEGIC FEATURE (2026-06-05):
--   Town Rank Card — show every shopkeeper their position
--   within their city + primary category.
--
--   "Your Position: Rank 4 of 23 in Mandi Dabwali Kirana"
--   "2 positions to Top 3"
--   "#1 leader: Ramesh Kirana (12 reviews, 9 photos)"
--
-- THIS RPC:
--   get_town_rank(business_id) → JSONB
--   Returns: rank, total_in_segment, city_name, category_name,
--            leader_name, leader_score, gap_to_top3,
--            improvement_tips (array of actionable next steps)
--
-- RANKING FORMULA (transparent, points-based):
--   + 3 points per verified review
--   + 2 points per photo (capped at 10 = 20 pts)
--   + 5 points per verified status tier (verified_score)
--   + 1 point per FAQ
--   + 2 points if has hours_json
--   + 2 points if has USP text
--   + 1 point if has About text
--   + 1 point per payment method (capped at 5)
--
-- Tied scores: older shops rank higher.
-- Only ACTIVE shops counted.
--
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

DROP FUNCTION IF EXISTS get_town_rank(UUID);
CREATE OR REPLACE FUNCTION get_town_rank(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id        UUID;
  v_is_owner       BOOLEAN;
  v_my_city_id     UUID;
  v_my_cat_id      UUID;
  v_my_city_name   TEXT;
  v_my_cat_name    TEXT;
  v_my_score       INT;
  v_my_rank        INT;
  v_total          INT;
  v_leader_id      UUID;
  v_leader_name    TEXT;
  v_leader_score   INT;
  v_top3_score     INT;
  v_gap_to_top3    INT;
  v_tips           JSONB := '[]'::jsonb;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Owner gate
  SELECT EXISTS (
    SELECT 1 FROM business_owners
    WHERE business_id = p_business_id AND user_id = v_user_id
  ) INTO v_is_owner;
  IF NOT v_is_owner THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Get this business's city + primary category
  BEGIN
    SELECT b.city_id, b.primary_category_id
    INTO v_my_city_id, v_my_cat_id
    FROM businesses b
    WHERE b.id = p_business_id;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  IF v_my_city_id IS NULL THEN
    RETURN jsonb_build_object(
      'available', false,
      'reason',    'Add your city to your profile to see your rank'
    );
  END IF;

  -- City + category names for display
  BEGIN
    SELECT name INTO v_my_city_name FROM geo_cities WHERE id = v_my_city_id;
  EXCEPTION WHEN OTHERS THEN v_my_city_name := 'Your city'; END;

  BEGIN
    SELECT name INTO v_my_cat_name FROM categories WHERE id = v_my_cat_id;
  EXCEPTION WHEN OTHERS THEN v_my_cat_name := 'Your category'; END;

  -- ===== Score formula =====
  -- (CTE: compute every shop's score in this segment)
  WITH segment AS (
    SELECT
      b.id, b.name, b.slug, b.created_at,
      -- Points
      (COALESCE(b.rating_count, 0) * 3) +
      LEAST(COALESCE(array_length(b.photos, 1), 0), 10) * 2 +
      (COALESCE(b.verified_score, 0) * 5) +
      LEAST(COALESCE(jsonb_array_length(b.faqs_json), 0), 10) +
      (CASE WHEN b.hours_json IS NOT NULL AND b.hours_json::TEXT != '{}' THEN 2 ELSE 0 END) +
      (CASE WHEN b.usp_text IS NOT NULL AND length(b.usp_text) > 10 THEN 2 ELSE 0 END) +
      (CASE WHEN b.about_text IS NOT NULL AND length(b.about_text) > 50 THEN 1 ELSE 0 END) +
      LEAST(COALESCE(array_length(b.payment_methods, 1), 0), 5)
      AS score
    FROM businesses b
    WHERE b.city_id = v_my_city_id
      AND (b.primary_category_id = v_my_cat_id OR v_my_cat_id IS NULL)
      AND b.status = 'active'
  ),
  ranked AS (
    SELECT
      id, name, slug, score,
      ROW_NUMBER() OVER (ORDER BY score DESC, created_at ASC) AS rk
    FROM segment
  )
  SELECT
    rk, score INTO v_my_rank, v_my_score
  FROM ranked WHERE id = p_business_id;

  -- Total in segment
  SELECT COUNT(*) INTO v_total
  FROM businesses
  WHERE city_id = v_my_city_id
    AND (primary_category_id = v_my_cat_id OR v_my_cat_id IS NULL)
    AND status = 'active';

  -- Leader (rank 1)
  WITH segment AS (
    SELECT
      b.id, b.name, b.created_at,
      (COALESCE(b.rating_count, 0) * 3) +
      LEAST(COALESCE(array_length(b.photos, 1), 0), 10) * 2 +
      (COALESCE(b.verified_score, 0) * 5) +
      LEAST(COALESCE(jsonb_array_length(b.faqs_json), 0), 10) +
      (CASE WHEN b.hours_json IS NOT NULL AND b.hours_json::TEXT != '{}' THEN 2 ELSE 0 END) +
      (CASE WHEN b.usp_text IS NOT NULL AND length(b.usp_text) > 10 THEN 2 ELSE 0 END) +
      (CASE WHEN b.about_text IS NOT NULL AND length(b.about_text) > 50 THEN 1 ELSE 0 END) +
      LEAST(COALESCE(array_length(b.payment_methods, 1), 0), 5)
      AS score
    FROM businesses b
    WHERE b.city_id = v_my_city_id
      AND (b.primary_category_id = v_my_cat_id OR v_my_cat_id IS NULL)
      AND b.status = 'active'
  )
  SELECT id, name, score INTO v_leader_id, v_leader_name, v_leader_score
  FROM segment ORDER BY score DESC, created_at ASC LIMIT 1;

  -- Top-3 cutoff score
  WITH segment AS (
    SELECT
      b.id, b.created_at,
      (COALESCE(b.rating_count, 0) * 3) +
      LEAST(COALESCE(array_length(b.photos, 1), 0), 10) * 2 +
      (COALESCE(b.verified_score, 0) * 5) +
      LEAST(COALESCE(jsonb_array_length(b.faqs_json), 0), 10) +
      (CASE WHEN b.hours_json IS NOT NULL AND b.hours_json::TEXT != '{}' THEN 2 ELSE 0 END) +
      (CASE WHEN b.usp_text IS NOT NULL AND length(b.usp_text) > 10 THEN 2 ELSE 0 END) +
      (CASE WHEN b.about_text IS NOT NULL AND length(b.about_text) > 50 THEN 1 ELSE 0 END) +
      LEAST(COALESCE(array_length(b.payment_methods, 1), 0), 5)
      AS score
    FROM businesses b
    WHERE b.city_id = v_my_city_id
      AND (b.primary_category_id = v_my_cat_id OR v_my_cat_id IS NULL)
      AND b.status = 'active'
  )
  SELECT score INTO v_top3_score
  FROM segment ORDER BY score DESC, created_at ASC LIMIT 1 OFFSET 2;

  v_gap_to_top3 := GREATEST(COALESCE(v_top3_score, 0) - COALESCE(v_my_score, 0), 0);

  RETURN jsonb_build_object(
    'available',         true,
    'rank',              COALESCE(v_my_rank, 0),
    'total',             COALESCE(v_total, 0),
    'my_score',          COALESCE(v_my_score, 0),
    'city_name',         v_my_city_name,
    'category_name',     v_my_cat_name,
    'leader_name',       v_leader_name,
    'leader_score',      COALESCE(v_leader_score, 0),
    'gap_to_top3',       v_gap_to_top3,
    'is_top3',           (COALESCE(v_my_rank, 999) <= 3),
    'is_leader',         (v_my_rank = 1),
    'computed_at',       NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_town_rank(UUID) TO authenticated;


-- =====================================================
-- get_smart_tips(business_id) — Smart Tips Engine
-- =====================================================
-- SQL-based rules engine returning top 3 actionable tips
-- for the shopkeeper based on their profile gaps + local
-- patterns. No external API, no LLM. Pure SQL.
-- =====================================================
DROP FUNCTION IF EXISTS get_smart_tips(UUID);
CREATE OR REPLACE FUNCTION get_smart_tips(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id      UUID;
  v_is_owner     BOOLEAN;
  v_biz          RECORD;
  v_peak_hour    INT;
  v_cat_avg_photos NUMERIC;
  v_cat_avg_reviews NUMERIC;
  v_tips         JSONB := '[]'::jsonb;
  v_tip          JSONB;
  v_days_since_update INT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM business_owners
    WHERE business_id = p_business_id AND user_id = v_user_id
  ) INTO v_is_owner;
  IF NOT v_is_owner THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Load business snapshot
  SELECT
    b.id, b.name, b.city_id, b.primary_category_id,
    b.usp_text, b.about_text, b.faqs_json, b.photos,
    b.hours_json, b.payment_methods, b.special_features,
    b.established_year, b.rating_count, b.rating_avg,
    b.verified_score, b.updated_at, b.created_at,
    b.facebook_url, b.instagram_url, b.website_url
  INTO v_biz
  FROM businesses b WHERE b.id = p_business_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('tips', '[]'::jsonb);
  END IF;

  -- ===== RULE 1: Photo count vs category average =====
  BEGIN
    SELECT AVG(COALESCE(array_length(photos, 1), 0))
    INTO v_cat_avg_photos
    FROM businesses
    WHERE primary_category_id = v_biz.primary_category_id
      AND status = 'active';
  EXCEPTION WHEN OTHERS THEN v_cat_avg_photos := 0; END;

  IF COALESCE(array_length(v_biz.photos, 1), 0) < COALESCE(v_cat_avg_photos, 0) THEN
    v_tip := jsonb_build_object(
      'icon',     '📸',
      'priority', 'high',
      'title',    'Add more photos to compete',
      'detail',   'Similar listings in your category average ' || ROUND(v_cat_avg_photos, 0) || ' photos. You have ' || COALESCE(array_length(v_biz.photos, 1), 0) || '. More photos increase clicks.',
      'cta',      'Add Photos',
      'href',     '/panel/photos.html'
    );
    v_tips := v_tips || v_tip;
  END IF;

  -- ===== RULE 2: Peak search hour =====
  BEGIN
    SELECT EXTRACT(HOUR FROM created_at)::INT
    INTO v_peak_hour
    FROM leads_log
    WHERE business_id = p_business_id
      AND created_at >= NOW() - INTERVAL '14 days'
    GROUP BY EXTRACT(HOUR FROM created_at)
    ORDER BY COUNT(*) DESC
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_peak_hour := NULL; END;

  IF v_peak_hour IS NOT NULL THEN
    v_tip := jsonb_build_object(
      'icon',     '⏰',
      'priority', 'medium',
      'title',    'Your busiest hour is ' || v_peak_hour || ':00',
      'detail',   'Most customers view your listing around ' || v_peak_hour || ':00. Make sure your shop is open and ready.',
      'cta',      'View Analytics',
      'href',     '/panel/analytics.html'
    );
    v_tips := v_tips || v_tip;
  END IF;

  -- ===== RULE 3: Stale profile (no update in 14+ days) =====
  v_days_since_update := COALESCE(
    EXTRACT(DAY FROM NOW() - v_biz.updated_at)::INT, 0
  );
  IF v_days_since_update >= 14 THEN
    v_tip := jsonb_build_object(
      'icon',     '🔄',
      'priority', 'medium',
      'title',    'Profile not updated in ' || v_days_since_update || ' days',
      'detail',   'Fresh listings rank higher in search. Update your USP, photos, or offers to stay visible.',
      'cta',      'Update Profile',
      'href',     '/panel/profile.html'
    );
    v_tips := v_tips || v_tip;
  END IF;

  -- ===== RULE 4: Missing FAQs =====
  IF COALESCE(jsonb_array_length(v_biz.faqs_json), 0) < 3 THEN
    v_tip := jsonb_build_object(
      'icon',     '❓',
      'priority', 'medium',
      'title',    'Add FAQs to answer customer questions',
      'detail',   'FAQ section helps customers decide without calling. Top-ranked listings have 3 or more FAQs.',
      'cta',      'Add FAQs',
      'href',     '/panel/profile.html#faqs'
    );
    v_tips := v_tips || v_tip;
  END IF;

  -- ===== RULE 5: No social media =====
  IF v_biz.facebook_url IS NULL AND v_biz.instagram_url IS NULL
     AND v_biz.website_url IS NULL THEN
    v_tip := jsonb_build_object(
      'icon',     '🌐',
      'priority', 'low',
      'title',    'Connect your social media',
      'detail',   'Customers trust businesses with verified online presence. Link your Facebook, Instagram, or website.',
      'cta',      'Add Social Links',
      'href',     '/panel/profile.html#social'
    );
    v_tips := v_tips || v_tip;
  END IF;

  -- ===== RULE 6: No established year =====
  IF v_biz.established_year IS NULL OR v_biz.established_year < 1900 THEN
    v_tip := jsonb_build_object(
      'icon',     '📅',
      'priority', 'low',
      'title',    'Show how long you have been in business',
      'detail',   'Established year builds trust. Customers prefer experienced businesses.',
      'cta',      'Add Year',
      'href',     '/panel/profile.html#trust'
    );
    v_tips := v_tips || v_tip;
  END IF;

  -- ===== RULE 7: Low rating count =====
  BEGIN
    SELECT AVG(COALESCE(rating_count, 0))
    INTO v_cat_avg_reviews
    FROM businesses
    WHERE primary_category_id = v_biz.primary_category_id
      AND status = 'active';
  EXCEPTION WHEN OTHERS THEN v_cat_avg_reviews := 0; END;

  IF COALESCE(v_biz.rating_count, 0) < COALESCE(v_cat_avg_reviews, 0) AND v_cat_avg_reviews > 0 THEN
    v_tip := jsonb_build_object(
      'icon',     '⭐',
      'priority', 'high',
      'title',    'Request reviews from happy customers',
      'detail',   'Similar listings average ' || ROUND(v_cat_avg_reviews, 0) || ' reviews. You have ' || COALESCE(v_biz.rating_count, 0) || '. Reviews boost ranking.',
      'cta',      'Get Reviews Pack',
      'href',     '/panel/qr-code.html'
    );
    v_tips := v_tips || v_tip;
  END IF;

  RETURN jsonb_build_object(
    'tips',         v_tips,
    'total_tips',   jsonb_array_length(v_tips),
    'computed_at',  NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_smart_tips(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'db/106 installed.';
  RAISE NOTICE '  RPC: get_town_rank(business_id)';
  RAISE NOTICE '  RPC: get_smart_tips(business_id)';
  RAISE NOTICE '  Both are SQL-based, ZERO external API cost';
END $$;
