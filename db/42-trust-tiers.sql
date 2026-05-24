-- db/42-trust-tiers.sql
-- Power Features Pack: Verified Shop Tiers (Bronze / Silver / Gold)
--
-- Mirrors the client-side logic in assets/js/trust-tier.js so admin
-- queries and reports use the same tier definitions.
--
-- Tiers:
--   bronze = verified_score >= 3
--   silver = bronze + rating_avg >= 3.5 + rating_count >= 5 + photos >= 2
--   gold   = silver + rating_avg >= 4.2 + rating_count >= 20
--            + established_year set with >= 1 year of operation
--
-- Run once in Supabase SQL Editor.

CREATE OR REPLACE FUNCTION public.shop_trust_tier(
  p_verified_score   INT,
  p_rating_avg       NUMERIC,
  p_rating_count     INT,
  p_photo_count      INT,
  p_established_year SMALLINT
) RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_age INT;
  v_is_bronze BOOLEAN;
  v_is_silver BOOLEAN;
  v_is_gold   BOOLEAN;
BEGIN
  v_is_bronze := COALESCE(p_verified_score, 0) >= 3;
  v_is_silver := v_is_bronze
              AND COALESCE(p_rating_avg, 0)  >= 3.5
              AND COALESCE(p_rating_count, 0) >= 5
              AND COALESCE(p_photo_count, 0) >= 2;
  v_age := CASE
             WHEN p_established_year IS NULL OR p_established_year <= 0 THEN 0
             ELSE GREATEST(0, EXTRACT(YEAR FROM CURRENT_DATE)::INT - p_established_year)
           END;
  v_is_gold := v_is_silver
            AND COALESCE(p_rating_avg, 0)  >= 4.2
            AND COALESCE(p_rating_count, 0) >= 20
            AND v_age >= 1;

  IF v_is_gold THEN RETURN 'gold';
  ELSIF v_is_silver THEN RETURN 'silver';
  ELSIF v_is_bronze THEN RETURN 'bronze';
  ELSE RETURN NULL;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.shop_trust_tier(INT, NUMERIC, INT, INT, SMALLINT) TO anon, authenticated;

-- Convenience: compute tier for a single business by id
CREATE OR REPLACE FUNCTION public.shop_trust_tier_for(p_business_id BIGINT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  b RECORD;
BEGIN
  SELECT verified_score, rating_avg, rating_count,
         COALESCE(array_length(photos, 1), 0) AS photo_count,
         established_year
  INTO b
  FROM businesses
  WHERE id = p_business_id;

  IF NOT FOUND THEN RETURN NULL; END IF;

  RETURN shop_trust_tier(
    b.verified_score::INT,
    b.rating_avg::NUMERIC,
    b.rating_count::INT,
    b.photo_count::INT,
    b.established_year::SMALLINT
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.shop_trust_tier_for(BIGINT) TO anon, authenticated;

-- Admin summary: tier distribution across all live businesses
CREATE OR REPLACE FUNCTION public.admin_trust_tier_summary()
RETURNS TABLE(tier TEXT, shop_count BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Reuses is_super_admin from db/41 if present; else falls back to is_admin
  IF NOT (EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'is_super_admin')
          AND public.is_super_admin())
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'forbidden: admin only';
  END IF;

  RETURN QUERY
  SELECT COALESCE(shop_trust_tier(
           b.verified_score::INT,
           b.rating_avg::NUMERIC,
           b.rating_count::INT,
           COALESCE(array_length(b.photos, 1), 0),
           b.established_year::SMALLINT
         ), 'none') AS tier,
         COUNT(*)::BIGINT AS shop_count
  FROM businesses b
  WHERE b.status = 'live'
  GROUP BY 1
  ORDER BY CASE COALESCE(shop_trust_tier(
                  b.verified_score::INT,
                  b.rating_avg::NUMERIC,
                  b.rating_count::INT,
                  COALESCE(array_length(b.photos, 1), 0),
                  b.established_year::SMALLINT
                ), 'none')
            WHEN 'gold'   THEN 1
            WHEN 'silver' THEN 2
            WHEN 'bronze' THEN 3
            ELSE 4
          END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_trust_tier_summary() TO authenticated;
