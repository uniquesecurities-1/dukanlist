-- ============================================================
-- db/224 — rank history, so a shopkeeper can see MOVEMENT
--
-- WHY
--   Today the rank is computed live and nothing remembers yesterday. A
--   shopkeeper opens his panel, sees "#5", and it says the same thing next
--   week whether he worked on his listing or ignored it entirely. A number
--   that never visibly responds to effort stops being a reason to make any.
--
--   Movement is what people actually respond to. "#7 -> #5, two places up
--   this week" is a reward for something he did. "Someone passed you" is
--   sharper still — losing a place you held stings more than gaining one
--   pleases, which is exactly why it gets a shopkeeper to act.
--
--   None of that is possible without storing where he stood before. This
--   file is that memory.
--
-- WHAT IT ADDS
--   rank_snapshots        one row per shop per run
--   snapshot_all_ranks()  writes today's standings for every active shop
--   get_shop_rank()       now also returns rank_prev, rank_change and a
--                         plain-language movement label
--
-- Requires db/223. Safe to re-run.
-- ============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.rank_snapshots (
  id           BIGSERIAL PRIMARY KEY,
  business_id  UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
  category_id  INT,
  city_id      INT,
  rank         INT NOT NULL,
  total        INT NOT NULL,
  score        NUMERIC NOT NULL,
  taken_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rank_snapshots_biz_time
  ON public.rank_snapshots (business_id, taken_at DESC);
CREATE INDEX IF NOT EXISTS idx_rank_snapshots_time
  ON public.rank_snapshots (taken_at DESC);

-- A shop's standing history is its own business. Nothing is readable
-- directly; it reaches the owner only through get_shop_rank below, which
-- already decides what may be shown.
ALTER TABLE public.rank_snapshots ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rank_snapshots FROM anon, authenticated;


-- ------------------------------------------------------------
-- Take today's standings for every active shop, ranked within its own
-- city + category, using the same v2 score as everything else.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.snapshot_all_ranks()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_rows INT;
BEGIN
  WITH scored AS (
    SELECT b.id, b.category_id, b.city_id, dl_shop_score_v2(b.id) AS score
    FROM businesses b
    WHERE b.status = 'active' AND b.category_id IS NOT NULL AND b.city_id IS NOT NULL
  ), ranked AS (
    SELECT id, category_id, city_id, score,
           ROW_NUMBER() OVER (PARTITION BY city_id, category_id ORDER BY score DESC, id) AS rnk,
           COUNT(*)     OVER (PARTITION BY city_id, category_id) AS tot
    FROM scored
  )
  INSERT INTO rank_snapshots (business_id, category_id, city_id, rank, total, score)
  SELECT id, category_id, city_id, rnk, tot, score FROM ranked;

  GET DIAGNOSTICS v_rows = ROW_COUNT;

  -- Half a year of history is plenty for "last week" and a small chart.
  DELETE FROM rank_snapshots WHERE taken_at < NOW() - INTERVAL '26 weeks';

  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.snapshot_all_ranks() FROM PUBLIC, anon, authenticated;


-- ------------------------------------------------------------
-- get_shop_rank — everything db/223 returned, plus movement.
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
  v_prev_rank INT; v_prev_at TIMESTAMPTZ; v_change INT; v_move TEXT;
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

  -- Movement. Compare against the newest snapshot at least 3 days old, so a
  -- second snapshot taken the same week cannot report "no change" and make
  -- the whole thing look broken.
  SELECT s.rank, s.taken_at INTO v_prev_rank, v_prev_at
  FROM rank_snapshots s
  WHERE s.business_id = p_business_id
    AND s.taken_at < NOW() - INTERVAL '3 days'
  ORDER BY s.taken_at DESC
  LIMIT 1;

  IF v_prev_rank IS NOT NULL THEN
    v_change := v_prev_rank - v_rank;      -- positive = climbed
    v_move := CASE
      WHEN v_change > 0 THEN 'up'
      WHEN v_change < 0 THEN 'down'
      ELSE 'same'
    END;
  ELSE
    v_change := NULL;
    v_move := 'new';                       -- no history yet
  END IF;

  IF v_unanswered > 0 AND v_replies < 8 THEN
    v_tips := v_tips || jsonb_build_object('action','reply',
      'label','Reply to ' || LEAST(v_unanswered, 8 - v_replies)::text || ' customer review(s)',
      'points', LEAST(v_unanswered, 8 - v_replies) * 2.5, 'href','/panel/reviews.html');
  END IF;
  IF v_recent < 8 THEN
    v_tips := v_tips || jsonb_build_object('action','fresh',
      'label','Get a fresh review this month','points',4,'href','/panel/get-reviews.html');
  END IF;
  IF COALESCE(array_length(v_b.photos,1),0) < 10 THEN
    v_tips := v_tips || jsonb_build_object('action','photos',
      'label','Add ' || LEAST(10 - COALESCE(array_length(v_b.photos,1),0), 3)::text || ' more photo(s)',
      'points', LEAST(10 - COALESCE(array_length(v_b.photos,1),0), 3) * 2, 'href','/panel/photos.html');
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
    'rank_prev', v_prev_rank, 'rank_change', v_change, 'movement', v_move,
    'compared_since', v_prev_at,
    'tips', v_tips,
    'public_ok', (v_total >= 3) AND (v_rank <= 3 OR v_rank::numeric <= v_total::numeric / 2)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_shop_rank(UUID) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- Take the first snapshot straight away, so there is a baseline to compare
-- against a week from now. Movement stays "new" until this is a few days old.
DO $$
DECLARE n INT;
BEGIN
  SELECT public.snapshot_all_ranks() INTO n;
  RAISE NOTICE 'db/224 installed. First baseline snapshot written for % shops.', n;
  RAISE NOTICE 'Movement will start showing once this baseline is 3+ days old.';
  RAISE NOTICE 'Schedule snapshot_all_ranks() weekly — /api/rank-snapshot is wired to the Vercel cron.';
END $$;
