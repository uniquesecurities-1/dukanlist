-- ============================================================
-- db/223 — ranking v2
--
-- WHY, measured on the live data (202 active shops, 173 reviews):
--
--   Every rated shop sits at exactly 5.0. All 173 reviews are 5 stars.
--   So `rating_avg * 20` handed every rated shop the same 100 points and
--   decided nothing. The single largest term in the score was a constant.
--   What was left deciding rank: review COUNT and how full the profile is.
--
--   Only 11 of 173 reviews arrived in the last 90 days. A shop praised in
--   2024 and silent since ranked exactly like one praised last week — so the
--   list answered "who was good once", not "who is good now".
--
--   22 reviews carry an owner reply. A shopkeeper who answers his customers
--   in public is doing the single most trust-building thing available to him,
--   and it earned him nothing.
--
-- WHAT CHANGES
--   + recency   reviews in the last 90 days are worth real points
--   + replies   answering a review earns points
--   ~ quality   Bayesian average, and only the part ABOVE 4.0 scores, so a
--               shop with one 5-star review no longer counts like one with
--               forty — and an unrated shop does not collect a near-free
--               score just because the prior is generous
--   = unchanged verification, photos, USP, About
--
-- Deliberately NOT included: Call/WhatsApp/Directions clicks. The data is
-- real and recording works (leads_log has rows; anon simply cannot read it),
-- but the volume is tiny — the busiest shop has 10 leads total, 2 this week.
-- Ranking on that today would be ranking on noise. Revisit at ~30 leads/week.
--
-- Safe to re-run. Requires db/221.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- The whole score for one shop, including the parts that need the
-- reviews table. STABLE + SECURITY DEFINER so ranking functions can call it
-- per row; at ~200 shops this is comfortably fast.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.dl_shop_score_v2(p_business_id UUID)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
DECLARE
  b            RECORD;
  v_n          INT := 0;      -- review count
  v_sum        NUMERIC := 0;  -- sum of ratings
  v_recent     INT := 0;      -- reviews in the last 90 days
  v_replies    INT := 0;      -- reviews the owner answered
  v_bayes      NUMERIC;
  v_quality    NUMERIC;
  -- Prior: 5 notional reviews at 4.3. Chosen so a single 5-star review
  -- cannot leap a shop past one with a long, consistent record.
  C   CONSTANT NUMERIC := 5;
  M   CONSTANT NUMERIC := 4.3;
BEGIN
  SELECT rating_avg, rating_count, verified_score, photos, usp_text, about_text
  INTO b
  FROM businesses WHERE id = p_business_id;

  IF NOT FOUND THEN RETURN 0; END IF;

  SELECT COUNT(*),
         COALESCE(SUM(r.rating), 0),
         COUNT(*) FILTER (WHERE r.created_at > NOW() - INTERVAL '90 days'),
         COUNT(*) FILTER (WHERE r.owner_reply IS NOT NULL AND btrim(r.owner_reply) <> '')
  INTO v_n, v_sum, v_recent, v_replies
  FROM reviews r
  WHERE r.business_id = p_business_id
    AND COALESCE(r.status, 'active') = 'active';

  -- Bayesian average, then score only the part above 4.0.
  -- Straight Bayesian would hand a shop with no reviews 4.3 -> 86 points out
  -- of 100, almost as much as a shop with forty. Measuring the distance above
  -- 4.0 instead keeps the reward proportional to what was actually earned.
  v_bayes   := (C * M + v_sum) / (C + v_n);
  v_quality := GREATEST(v_bayes - 4.0, 0) * 30;

  RETURN ROUND((
      v_quality                                             -- earned quality
    + LEAST(v_n, 40) * 1.5                                  -- volume of proof
    + LEAST(v_recent, 8) * 4                                -- still alive now
    + LEAST(v_replies, 8) * 2.5                             -- answers customers
    + COALESCE(b.verified_score, 0) * 12                    -- we checked them
    + LEAST(COALESCE(array_length(b.photos, 1), 0), 10) * 2 -- shows the shop
    + (CASE WHEN length(COALESCE(b.usp_text, ''))   > 10 THEN 5 ELSE 0 END)
    + (CASE WHEN length(COALESCE(b.about_text, '')) > 50 THEN 5 ELSE 0 END)
  )::numeric, 1);
END;
$$;

GRANT EXECUTE ON FUNCTION public.dl_shop_score_v2(UUID) TO anon, authenticated;


-- ------------------------------------------------------------
-- get_shop_rank — same shape as db/221, now on the v2 score, and the
-- "how to move up" tips include the two new levers.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_shop_rank(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
DECLARE
  v_cat_id INT; v_city_id INT; v_cat_name TEXT; v_cat_slug TEXT; v_city_name TEXT;
  v_rank INT; v_total INT; v_score NUMERIC; v_next NUMERIC; v_top NUMERIC;
  v_b RECORD; v_recent INT; v_replies INT; v_unanswered INT;
  v_tips JSONB := '[]'::jsonb;
BEGIN
  SELECT b.category_id, b.city_id, b.rating_avg, b.rating_count,
         b.verified_score, b.photos, b.usp_text, b.about_text
  INTO v_b FROM businesses b WHERE b.id = p_business_id AND b.status = 'active';
  IF NOT FOUND THEN RETURN jsonb_build_object('found', false); END IF;

  v_cat_id := v_b.category_id; v_city_id := v_b.city_id;
  SELECT c.name, c.slug INTO v_cat_name, v_cat_slug FROM categories c WHERE c.id = v_cat_id;
  SELECT g.name          INTO v_city_name          FROM geo_cities g WHERE g.id = v_city_id;

  WITH peers AS (
    SELECT b.id, dl_shop_score_v2(b.id) AS score
    FROM businesses b
    WHERE b.status = 'active'
      AND b.city_id = v_city_id
      AND (b.category_id = v_cat_id OR b.sub_category_id = v_cat_id)
  ), ranked AS (
    SELECT id, score, ROW_NUMBER() OVER (ORDER BY score DESC, id) AS rn FROM peers
  )
  SELECT r.rn, r.score, (SELECT COUNT(*) FROM peers),
         (SELECT r2.score FROM ranked r2 WHERE r2.rn = r.rn - 1),
         (SELECT MAX(score) FROM peers)
  INTO v_rank, v_score, v_total, v_next, v_top
  FROM ranked r WHERE r.id = p_business_id;

  IF v_rank IS NULL THEN RETURN jsonb_build_object('found', false); END IF;

  SELECT COUNT(*) FILTER (WHERE r.created_at > NOW() - INTERVAL '90 days'),
         COUNT(*) FILTER (WHERE r.owner_reply IS NOT NULL AND btrim(r.owner_reply) <> ''),
         COUNT(*) FILTER (WHERE r.owner_reply IS NULL OR btrim(r.owner_reply) = '')
  INTO v_recent, v_replies, v_unanswered
  FROM reviews r
  WHERE r.business_id = p_business_id AND COALESCE(r.status,'active') = 'active';

  -- Tips, most valuable first. Every one names the points it is worth, so the
  -- advice can be checked against the score rather than taken on faith.
  IF v_unanswered > 0 AND v_replies < 8 THEN
    v_tips := v_tips || jsonb_build_object(
      'action','reply',
      'label', 'Reply to ' || LEAST(v_unanswered, 8 - v_replies)::text || ' customer review(s)',
      'points', LEAST(v_unanswered, 8 - v_replies) * 2.5,
      'href','/panel/reviews.html');
  END IF;

  IF v_recent < 8 THEN
    v_tips := v_tips || jsonb_build_object(
      'action','fresh',
      'label', 'Get a fresh review this month',
      'points', 4,
      'href','/panel/get-reviews.html');
  END IF;

  IF COALESCE(array_length(v_b.photos,1),0) < 10 THEN
    v_tips := v_tips || jsonb_build_object(
      'action','photos',
      'label','Add ' || LEAST(10 - COALESCE(array_length(v_b.photos,1),0), 3)::text || ' more photo(s)',
      'points', LEAST(10 - COALESCE(array_length(v_b.photos,1),0), 3) * 2,
      'href','/panel/photos.html');
  END IF;

  IF length(COALESCE(v_b.usp_text,'')) <= 10 THEN
    v_tips := v_tips || jsonb_build_object('action','usp','label','Write your one-line speciality','points',5,'href','/panel/profile.html#usp');
  END IF;

  IF length(COALESCE(v_b.about_text,'')) <= 50 THEN
    v_tips := v_tips || jsonb_build_object('action','about','label','Write an "About us" (50+ characters)','points',5,'href','/panel/profile.html#about');
  END IF;

  IF COALESCE(v_b.verified_score,0) < 3 THEN
    v_tips := v_tips || jsonb_build_object('action','verify','label','Complete verification',
      'points',(3 - COALESCE(v_b.verified_score,0)) * 12,'href','/panel/dashboard.html#verify');
  END IF;

  RETURN jsonb_build_object(
    'found', true, 'rank', v_rank, 'total', v_total, 'score', v_score,
    'top_score', v_top,
    'gap_to_next', CASE WHEN v_next IS NULL THEN 0 ELSE GREATEST(ROUND(v_next - v_score + 0.1, 1), 0) END,
    'category_name', v_cat_name, 'category_slug', v_cat_slug, 'city_name', v_city_name,
    'reviews_90d', v_recent, 'owner_replies', v_replies, 'unanswered_reviews', v_unanswered,
    'tips', v_tips,
    'public_ok', (v_total >= 3) AND (v_rank <= 3 OR v_rank::numeric <= v_total::numeric / 2)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_shop_rank(UUID) TO anon, authenticated;


-- ------------------------------------------------------------
-- The street leaderboard moves to the same score, so /area, /top, the panel
-- and the certificate keep agreeing with one another.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_locality_ranked(
  p_city_slug TEXT, p_locality_slug TEXT, p_limit INT DEFAULT 50
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp STABLE
AS $$
DECLARE v_city_id INT; v_loc_id INT; v_result JSONB;
BEGIN
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 200 THEN p_limit := 50; END IF;

  SELECT c.id INTO v_city_id FROM geo_cities c
  WHERE c.active IS NOT FALSE
    AND lower(regexp_replace(c.name,'\s+','-','g')) = lower(COALESCE(p_city_slug,'')) LIMIT 1;
  IF v_city_id IS NULL THEN RETURN '[]'::jsonb; END IF;

  SELECT l.id INTO v_loc_id FROM geo_localities l
  WHERE l.city_id = v_city_id AND l.slug = p_locality_slug LIMIT 1;
  IF v_loc_id IS NULL THEN RETURN '[]'::jsonb; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'rank', rn, 'id', id, 'slug', slug, 'name', name,
           'usp_text', usp_text, 'photo', photo,
           'rating_avg', rating_avg, 'rating_count', rating_count,
           'verified_score', verified_score,
           'category_name', category_name, 'category_icon', category_icon,
           'score', score) ORDER BY rn), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT b.id, b.slug, b.name, b.usp_text, b.photos[1] AS photo,
           COALESCE(b.rating_avg,0) AS rating_avg,
           COALESCE(b.rating_count,0) AS rating_count,
           COALESCE(b.verified_score,0) AS verified_score,
           cat.name AS category_name, cat.icon AS category_icon,
           dl_shop_score_v2(b.id) AS score,
           ROW_NUMBER() OVER (ORDER BY dl_shop_score_v2(b.id) DESC, b.id) AS rn
    FROM businesses b
    LEFT JOIN categories cat ON cat.id = b.category_id
    WHERE b.status = 'active' AND b.city_id = v_city_id AND b.locality_id = v_loc_id
    LIMIT p_limit
  ) t;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_locality_ranked(TEXT, TEXT, INT) TO anon, authenticated;


-- ------------------------------------------------------------
-- /top must rank on the same number as everything else.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_top_for_seo(
  p_category_slug TEXT,
  p_city_slug     TEXT,
  p_limit         INT DEFAULT 10
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
DECLARE
  v_cat_id      INT;
  v_cat_name    TEXT;
  v_cat_ids     INT[];
  v_city_id     INT;
  v_city_name   TEXT;
  v_state_name  TEXT := '';
  v_items       JSONB := '[]'::jsonb;
  v_limit       INT;
BEGIN
  v_limit := COALESCE(p_limit, 10);
  IF v_limit < 1 OR v_limit > 50 THEN v_limit := 10; END IF;

  -- Category slug -> id, plus every child id when it is a parent.
  IF p_category_slug IS NOT NULL AND p_category_slug <> '' THEN
    SELECT c.id, c.name INTO v_cat_id, v_cat_name
    FROM categories c
    WHERE c.slug = p_category_slug AND c.active IS NOT FALSE
    LIMIT 1;

    IF v_cat_id IS NOT NULL THEN
      SELECT array_agg(x.id) INTO v_cat_ids
      FROM (
        SELECT v_cat_id AS id
        UNION
        SELECT c2.id FROM categories c2 WHERE c2.parent_id = v_cat_id
      ) x;
    END IF;
  END IF;

  -- City slug -> id. geo_cities has no slug column, so match the same
  -- derivation the rest of the site uses: lower(name) with spaces as '-'.
  IF p_city_slug IS NOT NULL AND p_city_slug <> '' THEN
    SELECT c.id, c.name, COALESCE(s.name, '')
    INTO v_city_id, v_city_name, v_state_name
    FROM geo_cities c
    LEFT JOIN geo_districts d ON d.id = c.district_id
    LEFT JOIN geo_states    s ON s.id = d.state_id
    WHERE c.active IS NOT FALSE
      AND lower(regexp_replace(c.name, '\s+', '-', 'g')) = lower(p_city_slug)
    LIMIT 1;
  END IF;

  -- Ranked list. Score: rating, review volume, verification, photos, completeness.
  WITH scored AS (
    SELECT
      b.id, b.name, b.slug, b.mobile, b.whatsapp,
      b.photos, b.usp_text, b.about_text,
      NULLIF(concat_ws(', ', NULLIF(b.address_line1, ''), NULLIF(b.address_line2, '')), '') AS address,
      b.rating_avg, b.rating_count, b.verified_score, b.established_year,
      -- v2: one formula for /top, the owner panel, /area and the certificate.
      -- Leaving the old inline copy here would have put /top back out of step
      -- with the rank a shopkeeper reads in his own panel.
      dl_shop_score_v2(b.id) AS score
    FROM businesses b
    WHERE b.status = 'active'
      AND (v_cat_ids IS NULL
           OR b.category_id     = ANY(v_cat_ids)
           OR b.sub_category_id = ANY(v_cat_ids))
      AND (v_city_id IS NULL OR b.city_id = v_city_id)
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id',               s.id,
      'name',             s.name,
      'slug',             s.slug,
      'mobile',           s.mobile,
      'whatsapp',         s.whatsapp,
      'photo',            s.photos[1],
      -- LEFT(...,140) chopped mid-word ("Family business — perso"). Cut back to
      -- the last space inside the limit and add an ellipsis instead.
      'usp',              CASE
                            WHEN length(COALESCE(s.usp_text, '')) <= 140
                              THEN COALESCE(s.usp_text, '')
                            ELSE rtrim(
                                   COALESCE(
                                     substring(LEFT(s.usp_text, 140) from '^.*\s'),
                                     LEFT(s.usp_text, 140)
                                   ),
                                   ' ,.;:·-'
                                 ) || '…'
                          END,
      'address',          LEFT(COALESCE(s.address, ''), 200),
      'rating_avg',       COALESCE(s.rating_avg, 0),
      'rating_count',     COALESCE(s.rating_count, 0),
      'verified',         COALESCE(s.verified_score, 0) >= 1,
      'verified_score',   COALESCE(s.verified_score, 0),
      'established_year', s.established_year,
      'score',            ROUND(s.score::numeric, 1)
    ) ORDER BY s.score DESC, s.rating_count DESC), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT * FROM scored
    ORDER BY score DESC, rating_count DESC
    LIMIT v_limit
  ) AS s;

  RETURN jsonb_build_object(
    'items',         v_items,
    'count',         jsonb_array_length(v_items),
    'category_name', COALESCE(v_cat_name, 'Local Businesses'),
    'category_slug', p_category_slug,
    'city_name',     COALESCE(v_city_name, ''),
    'city_slug',     p_city_slug,
    'state_name',    v_state_name,
    'computed_at',   NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_top_for_seo(TEXT, TEXT, INT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- Show what actually moved, rather than assuming it worked.
DO $$
DECLARE r RECORD; n INT := 0;
BEGIN
  RAISE NOTICE '--- top 8 in Mandi Dabwali: old score -> new score ---';
  FOR r IN
    SELECT b.name,
           dl_shop_score(b.rating_avg,b.rating_count,b.verified_score,b.photos,b.usp_text,b.about_text) AS old_s,
           dl_shop_score_v2(b.id) AS new_s,
           (SELECT COUNT(*) FROM reviews rv WHERE rv.business_id=b.id
              AND rv.owner_reply IS NOT NULL AND btrim(rv.owner_reply)<>'') AS replies
    FROM businesses b
    WHERE b.status='active' AND b.city_id=1
    ORDER BY dl_shop_score_v2(b.id) DESC
    LIMIT 8
  LOOP
    n := n + 1;
    RAISE NOTICE '%. % | old % -> new % | owner replies: %', n, r.name, r.old_s, r.new_s, r.replies;
  END LOOP;
  RAISE NOTICE 'db/223 installed.';
END $$;
