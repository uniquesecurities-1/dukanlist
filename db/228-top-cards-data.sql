-- ============================================================
-- db/228 — get_top_for_seo: three more fields for the /top cards
-- ============================================================
--
-- /top is getting photos, a podium, a "why this rank" strip, rank
-- movement and a share button. Three of those need data the RPC does
-- not return today:
--
--   photo_count   how many photos the shop has (the strip shows it)
--   cat_rank      the shop's rank INSIDE its own city + category
--   rank_change   how that rank moved since the last snapshot >= 3 days
--                 old (db/224). Positive = climbed. NULL = no history yet.
--
-- WHY cat_rank AND NOT THE LIST POSITION
--   On the all-categories view, #1 in the list is "best shop in town",
--   but the snapshots (db/224) are taken PER city + category. Comparing
--   a list position against a category snapshot would show nonsense
--   movement. So movement is always "within your category" — a true
--   fact about the shop whichever view you are on — and the card says
--   so: "↑2 in Grocery this week".
--
--   cat_rank is computed with the SAME partition and ordering as
--   snapshot_all_ranks(), so this week's number and last week's are
--   like for like.
--
-- Everything the RPC returned before is returned unchanged, in the
-- same shape, so nothing that already reads it (homepage hero strip,
-- api/biz.js rank badge, /local, /area) is affected.
--
-- Requires db/223 and db/224. Safe to re-run.
-- ============================================================

BEGIN;

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

  -- geo_cities has no slug column: derive it from the name (db/220).
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

  WITH
  -- Every active shop's rank inside its own city + category. Same
  -- partition and ordering as snapshot_all_ranks(), on purpose.
  cat_ranks AS (
    SELECT b.id,
           ROW_NUMBER() OVER (
             PARTITION BY b.city_id, b.category_id
             ORDER BY dl_shop_score_v2(b.id) DESC, b.id
           ) AS cat_rank
    FROM businesses b
    WHERE b.status = 'active' AND b.category_id IS NOT NULL AND b.city_id IS NOT NULL
  ),
  scored AS (
    SELECT
      b.id, b.name, b.slug, b.mobile, b.whatsapp,
      b.photos, b.usp_text, b.about_text,
      NULLIF(concat_ws(', ', NULLIF(b.address_line1, ''), NULLIF(b.address_line2, '')), '') AS address,
      b.rating_avg, b.rating_count, b.verified_score, b.established_year,
      dl_shop_score_v2(b.id) AS score,
      COALESCE(array_length(b.photos, 1), 0) AS photo_count,
      cr.cat_rank,
      -- newest snapshot at least 3 days old — same rule as get_shop_rank
      (SELECT s.rank FROM rank_snapshots s
        WHERE s.business_id = b.id
          AND s.taken_at < NOW() - INTERVAL '3 days'
        ORDER BY s.taken_at DESC
        LIMIT 1) AS prev_cat_rank
    FROM businesses b
    LEFT JOIN cat_ranks cr ON cr.id = b.id
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
      'score',            ROUND(s.score::numeric, 1),
      -- new in db/228
      'photo_count',      s.photo_count,
      'cat_rank',         s.cat_rank,
      'rank_change',      CASE WHEN s.prev_cat_rank IS NULL OR s.cat_rank IS NULL THEN NULL
                               ELSE s.prev_cat_rank - s.cat_rank END
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

-- Prove it. Returns one row per top shop with the three new fields, so
-- the Supabase editor shows something instead of swallowing a NOTICE.
SELECT
  x->>'name'                       AS shop,
  (x->>'photo_count')::int         AS photos,
  (x->>'cat_rank')::int            AS rank_in_category,
  x->>'rank_change'                AS change_since_snapshot,
  (x->>'score')::numeric           AS score
FROM jsonb_array_elements(
  (public.get_top_for_seo(NULL, 'mandi-dabwali', 6))->'items'
) AS x;
