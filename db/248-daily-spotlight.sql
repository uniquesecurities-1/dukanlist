-- ============================================================
-- db/248 — Spotlight of the Day
-- ============================================================
-- Deepak, 9 Oct: "Spotlight of the week" changed after 3 days one time,
-- stayed 10 days another. The pick was made in each visitor's browser
-- from three fallbacks (review buzz → featured → top-rated), minus
-- whatever else that visitor's page had already shown — so it moved
-- whenever review activity or the rest of the page moved, and two
-- visitors could see different shops.
--
-- Now one decision per day, stored, the same for everyone:
--   • a shop qualifies if it is active, has at least one photo and at
--     least one active 5-star review (Deepak's rule), and is not a
--     strict-tier professional (no promotion rules)
--   • each day (India time) the qualifying shop spotlighted longest ago
--     — never-spotlighted first — is chosen and written to
--     spotlight_daily, so every shop gets its day before any repeats
--   • the first visitor of the day makes the choice; everyone after
--     reads the same row
-- 32 shops qualify on 9 Oct 2026: a month without a repeat.
-- Safe to re-run.
-- ============================================================
BEGIN;

CREATE TABLE IF NOT EXISTS public.spotlight_daily (
  day          DATE PRIMARY KEY,
  business_id  UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
  picked_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.spotlight_daily ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS spotlight_daily_read ON public.spotlight_daily;
CREATE POLICY spotlight_daily_read ON public.spotlight_daily FOR SELECT USING (TRUE);
GRANT SELECT ON public.spotlight_daily TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_daily_spotlight()
RETURNS TABLE (
  id UUID, slug TEXT, name TEXT, owner_name TEXT, usp_text TEXT, photos TEXT[],
  rating_avg NUMERIC, rating_count INT, verified_score INT, city_name TEXT, spotlight_day DATE
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_day DATE := (NOW() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_biz UUID;
BEGIN
  SELECT s.business_id INTO v_biz
    FROM spotlight_daily s
    JOIN businesses b ON b.id = s.business_id AND b.status = 'active'
   WHERE s.day = v_day;

  IF v_biz IS NULL THEN
    SELECT b.id INTO v_biz
      FROM businesses b
      LEFT JOIN LATERAL (SELECT MAX(day) AS last_day FROM spotlight_daily sd WHERE sd.business_id = b.id) l ON TRUE
     WHERE b.status = 'active'
       AND COALESCE(b.professional_tier, '') <> 'strict'
       AND COALESCE(array_length(b.photos, 1), 0) >= 1
       AND EXISTS (SELECT 1 FROM reviews r WHERE r.business_id = b.id AND r.status = 'active' AND r.rating = 5)
     ORDER BY l.last_day ASC NULLS FIRST, md5(b.id::text || v_day::text)
     LIMIT 1;

    IF v_biz IS NULL THEN RETURN; END IF;

    INSERT INTO spotlight_daily (day, business_id) VALUES (v_day, v_biz)
    ON CONFLICT (day) DO UPDATE SET business_id = EXCLUDED.business_id
      WHERE NOT EXISTS (SELECT 1 FROM businesses x WHERE x.id = spotlight_daily.business_id AND x.status = 'active');
    SELECT s.business_id INTO v_biz FROM spotlight_daily s WHERE s.day = v_day;
  END IF;

  RETURN QUERY
  SELECT b.id, b.slug, b.name, b.owner_name, b.usp_text, b.photos,
         b.rating_avg::NUMERIC, b.rating_count::INT, b.verified_score::INT,
         c.name, v_day
    FROM businesses b
    LEFT JOIN geo_cities c ON c.id = b.city_id
   WHERE b.id = v_biz;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_daily_spotlight() TO anon, authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/248-daily-spotlight.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Today's pick, and how many shops are in the rotation
SELECT name, rating_avg, rating_count, spotlight_day FROM public.get_daily_spotlight();
SELECT COUNT(*) AS shops_in_rotation
  FROM businesses b
 WHERE b.status = 'active' AND COALESCE(b.professional_tier, '') <> 'strict'
   AND COALESCE(array_length(b.photos, 1), 0) >= 1
   AND EXISTS (SELECT 1 FROM reviews r WHERE r.business_id = b.id AND r.status = 'active' AND r.rating = 5);
