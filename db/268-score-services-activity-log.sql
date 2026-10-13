-- ============================================================
-- db/268 — two fixes: page score counts Services, Activity Log loads again
-- ============================================================
-- 1. Deepak, 13 Oct: GNC Amazon Store has 7 items on its Services page, but the score
--    still said "What do you sell? Add 3+ items". The score only looked at the
--    "kya milta hai" list (offerings). Services (services_json) are shown on the shop
--    page too, so 3+ named services now count as well. Photos: the larger of the two
--    photo lists counts (business_photos / businesses.photos), the same list the shop
--    cards read. Same rule in the owner panel (v380).
-- 2. Admin → Activity Log said "structure of query does not match function result type":
--    admin_recent_activity returned auth.users.email (varchar) where it promised text.
--    Every column is now cast to exactly the declared type.
-- Safe to re-run.

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
               + CASE WHEN GREATEST(COALESCE(array_length(b.offerings, 1), 0), (SELECT COUNT(*) FROM jsonb_array_elements(CASE WHEN jsonb_typeof(COALESCE(b.services_json, '[]'::jsonb)) = 'array' THEN b.services_json ELSE '[]'::jsonb END) e WHERE length(btrim(COALESCE(e->>'name', ''))) > 0)) >= 3 THEN 20 ELSE 0 END
               + CASE WHEN length(btrim(COALESCE(b.why_text, ''))) > 0 THEN 15 ELSE 0 END
               + CASE WHEN length(btrim(COALESCE(b.about_text, ''))) >= 50 THEN 15 ELSE 0 END
               + CASE WHEN b.hours_json IS NOT NULL AND b.hours_json::text NOT IN ('{}', 'null', '[]') THEN 10 ELSE 0 END
               + CASE WHEN COALESCE(b.rating_count, 0) >= 5 THEN 10 WHEN COALESCE(b.rating_count, 0) >= 1 THEN 5 ELSE 0 END
               + CASE WHEN b.established_year IS NOT NULL AND b.established_year > 1900 THEN 5 ELSE 0 END
               ) AS score,
               array_remove(ARRAY[
                 CASE WHEN COALESCE(ph.n, 0) < 6 THEN 'photos (' || COALESCE(ph.n, 0) || '/6)' END,
                 CASE WHEN GREATEST(COALESCE(array_length(b.offerings, 1), 0), (SELECT COUNT(*) FROM jsonb_array_elements(CASE WHEN jsonb_typeof(COALESCE(b.services_json, '[]'::jsonb)) = 'array' THEN b.services_json ELSE '[]'::jsonb END) e WHERE length(btrim(COALESCE(e->>'name', ''))) > 0)) < 3 THEN 'kya milta hai' END,
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
        LEFT JOIN LATERAL (SELECT GREATEST((SELECT COUNT(*)::INT FROM business_photos p WHERE p.business_id = b.id), COALESCE(array_length(b.photos, 1), 0)) AS n) ph ON TRUE
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

CREATE OR REPLACE FUNCTION public.admin_recent_activity(
  p_limit       INT  DEFAULT 50,
  p_offset      INT  DEFAULT 0,
  p_action      TEXT DEFAULT NULL,
  p_admin_id    UUID DEFAULT NULL
)
RETURNS TABLE (
  id            BIGINT,
  admin_user_id UUID,
  admin_email   TEXT,
  action        TEXT,
  target_type   TEXT,
  target_id     TEXT,
  target_name   TEXT,
  details       JSONB,
  created_at    TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  RETURN QUERY
    SELECT a.id::BIGINT, a.admin_user_id::UUID,
           COALESCE(au.email::TEXT, '(deleted user)')::TEXT,
           a.action::TEXT, a.target_type::TEXT, a.target_id::TEXT, a.target_name::TEXT,
           a.details::JSONB, a.created_at::TIMESTAMPTZ
      FROM admin_audit_log a
      LEFT JOIN auth.users au ON au.id = a.admin_user_id
     WHERE (p_action IS NULL OR a.action = p_action)
       AND (p_admin_id IS NULL OR a.admin_user_id = p_admin_id)
     ORDER BY a.created_at DESC
     LIMIT GREATEST(1, LEAST(p_limit, 200))
     OFFSET GREATEST(0, p_offset);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_recent_activity(INT, INT, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_recent_activity(INT, INT, TEXT, UUID) TO authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/268-score-services-activity-log.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Checks — first row yes; second shows GNC Amazon Store's score and what is still missing
SELECT 'score counts services' AS check,
       CASE WHEN pg_get_functiondef('public.admin_page_completeness(text,integer)'::regprocedure) LIKE '%services_json%' THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'GNC Amazon Store',
       COALESCE((SELECT b.name || ': services ' ||
                        (SELECT COUNT(*) FROM jsonb_array_elements(CASE WHEN jsonb_typeof(COALESCE(b.services_json, '[]'::jsonb)) = 'array' THEN b.services_json ELSE '[]'::jsonb END) e WHERE length(btrim(COALESCE(e->>'name', ''))) > 0)
                        || ', offerings ' || COALESCE(array_length(b.offerings, 1), 0)
                   FROM businesses b WHERE b.slug ILIKE 'g-n-c-amazon-store%' LIMIT 1), '(not found)');
