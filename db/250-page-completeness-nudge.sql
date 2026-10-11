-- ============================================================
-- db/250 — "page kitna poora hai" + the admin nudge list
-- ============================================================
--
-- Kadam 3 of the office-only plan (Deepak, 11 Oct). One score, the
-- same everywhere (owner dashboard meter, admin nudge list), built only
-- from what a CUSTOMER sees on the shop page:
--
--   photos      3+ = 25   (1–2 = 12)
--   offerings   3+ items "what you get here"          20
--   why_text    "why people come here"                 15
--   about_text  50+ characters, the owner's story      15
--   hours_json  opening hours set                      10
--   reviews     at least one active review             10
--   established_year                                    5
--                                                     ----
--                                                      100
--
-- admin_page_completeness() lists active shops with their score, what is
-- missing, their WhatsApp number and when the office last sent them a
-- "page sudhaaro" link (db/249 shop_update_links.created_at — making a
-- link IS the nudge, so no extra table). Read-only. Safe to re-run.
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
             -- never nudged / nudged over 7 days ago first
             CASE WHEN x.last_link_at IS NULL OR x.last_link_at < NOW() - INTERVAL '7 days' THEN 0 ELSE 1 END AS sort_nudged
      FROM (
        SELECT b.id, b.slug, b.name, COALESCE(NULLIF(b.whatsapp, ''), b.mobile) AS whatsapp,
               COALESCE(ph.n, 0) AS photos,
               ( CASE WHEN COALESCE(ph.n, 0) >= 3 THEN 25 WHEN COALESCE(ph.n, 0) >= 1 THEN 12 ELSE 0 END
               + CASE WHEN COALESCE(array_length(b.offerings, 1), 0) >= 3 THEN 20 ELSE 0 END
               + CASE WHEN length(btrim(COALESCE(b.why_text, ''))) > 0 THEN 15 ELSE 0 END
               + CASE WHEN length(btrim(COALESCE(b.about_text, ''))) >= 50 THEN 15 ELSE 0 END
               + CASE WHEN b.hours_json IS NOT NULL AND b.hours_json::text NOT IN ('{}', 'null', '[]') THEN 10 ELSE 0 END
               + CASE WHEN COALESCE(b.rating_count, 0) > 0 THEN 10 ELSE 0 END
               + CASE WHEN b.established_year IS NOT NULL AND b.established_year > 1900 THEN 5 ELSE 0 END
               ) AS score,
               array_remove(ARRAY[
                 CASE WHEN COALESCE(ph.n, 0) < 3 THEN 'photos' END,
                 CASE WHEN COALESCE(array_length(b.offerings, 1), 0) < 3 THEN 'kya milta hai' END,
                 CASE WHEN length(btrim(COALESCE(b.why_text, ''))) = 0 THEN 'kyon aate hain' END,
                 CASE WHEN length(btrim(COALESCE(b.about_text, ''))) < 50 THEN 'kahani' END,
                 CASE WHEN b.hours_json IS NULL OR b.hours_json::text IN ('{}', 'null', '[]') THEN 'timing' END,
                 CASE WHEN COALESCE(b.rating_count, 0) = 0 THEN 'review' END,
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
    PERFORM public.record_migration('db/250-page-completeness-nudge.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- Checks — first two rows should say yes; the last shows today's picture
-- ============================================================
SELECT 'admin_page_completeness exists' AS check,
       CASE WHEN to_regprocedure('public.admin_page_completeness(text,integer)') IS NOT NULL THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'anon cannot call it',
       CASE WHEN NOT has_function_privilege('anon', 'public.admin_page_completeness(text,integer)', 'EXECUTE') THEN 'yes' ELSE 'NO — tell Claude' END
UNION ALL
SELECT 'active shops with photo / with 3+ "kya milta hai" / with "kyon aate hain"',
       (SELECT COUNT(*) FILTER (WHERE EXISTS (SELECT 1 FROM business_photos p WHERE p.business_id = b.id)) || ' / '
            || COUNT(*) FILTER (WHERE COALESCE(array_length(b.offerings, 1), 0) >= 3) || ' / '
            || COUNT(*) FILTER (WHERE length(btrim(COALESCE(b.why_text, ''))) > 0)
            || '  (of ' || COUNT(*) || ')'
          FROM businesses b WHERE b.status = 'active');
