-- ============================================================
-- db/252 — page score: 100% has to mean done
-- ============================================================
-- Deepak, 13 Oct: Sharma Button Traders showed 100% on the owner
-- dashboard but 78 in admin, with work still left. Two different scores
-- (admin list used an older "health" formula) and the new one was too
-- easy: 3 photos and 1 review already counted in full.
-- Same seven items, tougher on the two that matter most:
--   photos  6+ = 25 · 3–5 = 15 · 1–2 = 8
--   reviews 5+ = 10 · 1–4 = 5
-- The owner dashboard (panel/dashboard.html) and the admin shop list use
-- this exact maths from v358. Read-only. Safe to re-run.
-- ============================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.admin_page_completeness(p_filter TEXT DEFAULT 'todo', p_limit INT DEFAULT 300)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp
AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(to_jsonb(r) - 'sort_nudged' ORDER BY r.sort_nudged, r.score DESC, r.name)
    FROM (
    SELECT q.* FROM (
      SELECT x.*,
             CASE WHEN x.last_link_at IS NULL OR x.last_link_at < NOW() - INTERVAL '7 days' THEN 0 ELSE 1 END AS sort_nudged
      FROM (
        SELECT b.id, b.slug, b.name, COALESCE(NULLIF(b.whatsapp, ''), b.mobile) AS whatsapp,
               COALESCE(ph.n, 0) AS photos,
               ( CASE WHEN COALESCE(ph.n, 0) >= 6 THEN 25 WHEN COALESCE(ph.n, 0) >= 3 THEN 15 WHEN COALESCE(ph.n, 0) >= 1 THEN 8 ELSE 0 END
               + CASE WHEN COALESCE(array_length(b.offerings, 1), 0) >= 3 THEN 20 ELSE 0 END
               + CASE WHEN length(btrim(COALESCE(b.why_text, ''))) > 0 THEN 15 ELSE 0 END
               + CASE WHEN length(btrim(COALESCE(b.about_text, ''))) >= 50 THEN 15 ELSE 0 END
               + CASE WHEN b.hours_json IS NOT NULL AND b.hours_json::text NOT IN ('{}', 'null', '[]') THEN 10 ELSE 0 END
               + CASE WHEN COALESCE(b.rating_count, 0) >= 5 THEN 10 WHEN COALESCE(b.rating_count, 0) >= 1 THEN 5 ELSE 0 END
               + CASE WHEN b.established_year IS NOT NULL AND b.established_year > 1900 THEN 5 ELSE 0 END
               ) AS score,
               array_remove(ARRAY[
                 CASE WHEN COALESCE(ph.n, 0) < 6 THEN 'photos (' || COALESCE(ph.n, 0) || '/6)' END,
                 CASE WHEN COALESCE(array_length(b.offerings, 1), 0) < 3 THEN 'kya milta hai' END,
                 CASE WHEN length(btrim(COALESCE(b.why_text, ''))) = 0 THEN 'kyon aate hain' END,
                 CASE WHEN length(btrim(COALESCE(b.about_text, ''))) < 50 THEN 'kahani' END,
                 CASE WHEN b.hours_json IS NULL OR b.hours_json::text IN ('{}', 'null', '[]') THEN 'timing' END,
                 CASE WHEN COALESCE(b.rating_count, 0) < 5 THEN 'reviews (' || COALESCE(b.rating_count, 0) || '/5)' END,
                 CASE WHEN b.established_year IS NULL OR b.established_year <= 1900 THEN 'since' END
               ], NULL) AS missing,
               lk.last_link_at,
               sb.pending AS pending_updates,
               COALESCE(c.name, '') AS category
        FROM businesses b
        LEFT JOIN LATERAL (SELECT COUNT(*)::INT AS n FROM business_photos p WHERE p.business_id = b.id) ph ON TRUE
        LEFT JOIN LATERAL (SELECT MAX(l.created_at) AS last_link_at FROM shop_update_links l WHERE l.business_id = b.id) lk ON TRUE
        LEFT JOIN LATERAL (SELECT COUNT(*)::INT AS pending FROM shop_update_submissions s WHERE s.business_id = b.id AND s.status = 'pending') sb ON TRUE
        LEFT JOIN categories c ON c.id = COALESCE(b.sub_category_id, b.category_id)
        WHERE b.status = 'active'
      ) x
    ) q
    WHERE CASE COALESCE(p_filter, 'todo')
            WHEN 'todo'     THEN q.score < 80 AND q.pending_updates = 0
            WHEN 'nophoto'  THEN q.photos = 0
            WHEN 'sent'     THEN q.last_link_at IS NOT NULL AND q.last_link_at >= NOW() - INTERVAL '7 days'
            WHEN 'done'     THEN q.score >= 80
            ELSE TRUE END
    ORDER BY q.sort_nudged, q.score DESC, q.name
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 300), 1000))
    ) r
  ), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_page_completeness(TEXT, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_page_completeness(TEXT, INT) TO authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/252-page-score-stricter.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Check: Sharma Button Traders should now read 85 (3 photos = 15, 1 review = 5)
SELECT b.name,
       ( CASE WHEN p.n >= 6 THEN 25 WHEN p.n >= 3 THEN 15 WHEN p.n >= 1 THEN 8 ELSE 0 END
       + CASE WHEN COALESCE(array_length(b.offerings, 1), 0) >= 3 THEN 20 ELSE 0 END
       + CASE WHEN length(btrim(COALESCE(b.why_text, ''))) > 0 THEN 15 ELSE 0 END
       + CASE WHEN length(btrim(COALESCE(b.about_text, ''))) >= 50 THEN 15 ELSE 0 END
       + CASE WHEN b.hours_json IS NOT NULL AND b.hours_json::text NOT IN ('{}', 'null', '[]') THEN 10 ELSE 0 END
       + CASE WHEN COALESCE(b.rating_count, 0) >= 5 THEN 10 WHEN COALESCE(b.rating_count, 0) >= 1 THEN 5 ELSE 0 END
       + CASE WHEN b.established_year > 1900 THEN 5 ELSE 0 END ) AS page_score,
       p.n AS photos, b.rating_count AS reviews
  FROM businesses b, LATERAL (SELECT COUNT(*)::INT AS n FROM business_photos WHERE business_id = b.id) p
 WHERE b.slug = 'sharma-button-traders-mandi-dabwali';
