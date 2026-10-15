-- ============================================================
-- db/275 — Dabwali Parivar phase 4: pages Google (and WhatsApp previews) can read
-- ============================================================
-- Deepak, 15 Oct (phase 4):
--   * parivar_sitemap(): organisation pages + the pages of people who CONFIRMED their own page
--     (same rule as the page itself: an unconfirmed person stays out of search engines)
--   * the server now fills each organisation / person page's title, description, share image and
--     structured data (api/parivar.js) — it reads the existing public functions, nothing new exposed
-- Safe to re-run.

BEGIN;

CREATE OR REPLACE FUNCTION public.parivar_sitemap()
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT jsonb_build_object(
    'orgs', COALESCE((SELECT jsonb_agg(jsonb_build_object('slug', slug, 'updated_at', updated_at) ORDER BY name)
                        FROM parivar_orgs WHERE status = 'active'), '[]'::jsonb),
    'people', COALESCE((SELECT jsonb_agg(jsonb_build_object('slug', slug, 'updated_at', updated_at) ORDER BY full_name)
                          FROM parivar_people WHERE status = 'active' AND mobile_verified_at IS NOT NULL), '[]'::jsonb));
$$;
REVOKE ALL ON FUNCTION public.parivar_sitemap() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.parivar_sitemap() TO anon, authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/275-parivar-seo.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Check — how many Parivar pages go to Google
SELECT 'pages for Google' AS check,
       (SELECT jsonb_array_length(s->'orgs') || ' organisations · ' || jsonb_array_length(s->'people') || ' confirmed people'
          FROM (SELECT public.parivar_sitemap() s) x) AS result;
