-- ============================================================
-- db/239 — a shop's district, state and pincode follow its city
-- ============================================================
--
-- Reported 2026-09-29, adding "Delphia Constructions" through Quick Add:
--   null value in column "district_id" of relation "businesses"
--   violates not-null constraint
--
-- businesses.district_id, state_id and pincode are all NOT NULL
-- (db/01-schema lines 104-107), and admin_pre_list_shop — the function
-- behind Quick Add — inserts city_id and none of the other three.
-- Quick Add had been dead since July for an unrelated reason, so nobody
-- hit this until the page started working again last week.
--
-- This is the THIRD time this exact bug has been fixed:
--   db/171  admin_soft_add_shop, district_id + state_id
--   db/172  admin_soft_add_shop, pincode
--   here    admin_pre_list_shop — and whatever writes shops next
--
-- So this one is not another per-function patch. All three values are
-- derivable from the city that is already on the row, and a trigger
-- fills them once, for every path that inserts a shop — Quick Add,
-- bulk upload, the public register form, anything added later.
--
-- It only fills what is missing. A caller that sets district_id itself
-- (db/171's soft-add does) is left completely alone, so nothing that
-- works today changes behaviour.
--
-- If the city has no district mapped, it still raises — but now with a
-- sentence that says which city to fix, instead of a constraint name.
--
-- Safe to re-run.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fill_geo_from_city()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_district INT;
  v_state    SMALLINT;
  v_pin      TEXT;
BEGIN
  -- Everything already supplied? Nothing to do.
  IF NEW.district_id IS NOT NULL
     AND NEW.state_id IS NOT NULL
     AND NULLIF(TRIM(COALESCE(NEW.pincode, '')), '') IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.city_id IS NULL THEN
    RAISE EXCEPTION 'Shop "%" has no city, so district/state/pincode cannot be worked out', NEW.name;
  END IF;

  SELECT c.district_id, d.state_id, COALESCE(c.pincodes[1], '000000')
    INTO v_district, v_state, v_pin
    FROM public.geo_cities c
    JOIN public.geo_districts d ON d.id = c.district_id
   WHERE c.id = NEW.city_id
   LIMIT 1;

  IF v_district IS NULL THEN
    RAISE EXCEPTION
      'City id % is not mapped to a district in geo_cities — fix the geo table before adding shops there',
      NEW.city_id;
  END IF;

  NEW.district_id := COALESCE(NEW.district_id, v_district);
  NEW.state_id    := COALESCE(NEW.state_id,    v_state);
  NEW.pincode     := COALESCE(NULLIF(TRIM(COALESCE(NEW.pincode, '')), ''), v_pin);

  RETURN NEW;
END;
$$;

-- Name chosen so it sorts before the existing business triggers
-- (prevent_dup_active_mobile, trg_auto_flag_professional_biz,
--  trg_biz_one_per_mobile): the row should be complete before anything
-- else inspects it.
DROP TRIGGER IF EXISTS trg_biz_a_fill_geo ON public.businesses;
CREATE TRIGGER trg_biz_a_fill_geo
  BEFORE INSERT ON public.businesses
  FOR EACH ROW
  EXECUTE FUNCTION public.fill_geo_from_city();

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/239-fill-geo-from-city-trigger.sql');
  END IF;
END $$;

COMMIT;

-- ============================================================
-- Checks. Both read-only — nothing is inserted, nothing to clean up.
--
-- 1. the trigger is installed
-- 2. every city that has shops (or could get one) can actually supply
--    a district, a state and a pincode. If a city shows 'NO DISTRICT'
--    or 'NO PINCODE' here, adding a shop there would still fail, and
--    the geo table is what needs fixing — not the code.
-- ============================================================
SELECT 'trigger installed' AS check,
       CASE WHEN EXISTS (
              SELECT 1 FROM pg_trigger
               WHERE tgname = 'trg_biz_a_fill_geo'
                 AND tgrelid = 'public.businesses'::regclass
                 AND NOT tgisinternal
            ) THEN 'yes' ELSE 'NO — tell Claude' END AS result;

SELECT c.name                                   AS city,
       c.district_id,
       d.state_id,
       COALESCE(c.pincodes[1], '(none)')        AS pincode_that_will_be_used,
       CASE WHEN c.district_id IS NULL THEN 'NO DISTRICT — fix geo_cities'
            WHEN d.state_id IS NULL    THEN 'NO STATE — fix geo_districts'
            WHEN COALESCE(c.pincodes[1], '') = '' THEN 'no pincode — will use 000000'
            ELSE 'ok' END                       AS result
FROM public.geo_cities c
LEFT JOIN public.geo_districts d ON d.id = c.district_id
WHERE c.active
ORDER BY (c.district_id IS NULL OR d.state_id IS NULL) DESC, c.name;
