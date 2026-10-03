-- ============================================================
-- db/238 — search looks inside what the shop actually sells
-- ============================================================
--
-- Deepak, 2026-09-29: open any shop and there is no sign of its
-- products. Unique Securities says "financial planning" but never SIP,
-- ELSS, NPS, fixed deposit.
--
-- Checked first, because half of this already exists:
--   * businesses.services_json holds up to 15 items {name, desc,
--     price_min, price_max}; panel/services.html writes them and the
--     shop page renders them. Built, working, and used by 7 shops
--     out of 268. Unique Securities has an empty list.
--   * search_businesses does NOT look at it. So even those 7 are
--     unfindable by product: "Delux room" returns nothing although
--     Ranveer Hotel lists exactly that.
--
-- This migration fixes the second half — the part no amount of data
-- entry could have fixed. Filling the lists is the other half, and
-- that is a people job, not a code one.
--
-- Rebuilt from db/146 (the live version — its 24 returned columns
-- match what the live RPC answers with today; db/85 is older and does
-- not have the locality or professional columns). The ONLY change is
-- the services_json clause marked v298 below; everything else is
-- db/146 byte for byte.
-- ============================================================

CREATE OR REPLACE FUNCTION search_businesses(
  p_query         TEXT     DEFAULT NULL,
  p_category      TEXT     DEFAULT NULL,
  p_city_id       INT      DEFAULT NULL,
  p_state_id      SMALLINT DEFAULT NULL,
  p_limit         INT      DEFAULT 20,
  p_offset        INT      DEFAULT 0,
  p_pincode       TEXT     DEFAULT NULL,
  p_locality_slug TEXT     DEFAULT NULL
)
RETURNS TABLE (
  id                      UUID,
  slug                    TEXT,
  name                    TEXT,
  name_hi                 TEXT,
  category_slug           TEXT,
  category_name           TEXT,
  category_icon           TEXT,
  address_line1           TEXT,
  city_name               TEXT,
  locality_name           TEXT,
  locality_slug           TEXT,
  pincode                 TEXT,
  whatsapp                TEXT,
  mobile                  TEXT,
  usp_text                TEXT,
  photos                  TEXT[],
  hours_json              JSONB,
  rating_avg              NUMERIC,
  rating_count            INT,
  verified_score          SMALLINT,
  verified_visit          BOOLEAN,
  match_rank              REAL,
  is_professional_listing BOOLEAN,    -- NEW (db/146)
  professional_tier       TEXT        -- NEW (db/146)
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_cat_id   INT;
  v_pin_norm TEXT;
  v_q_lc     TEXT;
  v_loc_lc   TEXT;
BEGIN
  IF p_category IS NOT NULL THEN
    SELECT c.id INTO v_cat_id FROM categories c WHERE c.slug = p_category;
  END IF;

  IF p_pincode IS NOT NULL THEN
    v_pin_norm := regexp_replace(p_pincode, '\D', '', 'g');
    IF LENGTH(v_pin_norm) <> 6 THEN v_pin_norm := NULL; END IF;
  END IF;

  v_q_lc   := LOWER(TRIM(COALESCE(p_query, '')));
  v_loc_lc := LOWER(TRIM(COALESCE(p_locality_slug, '')));

  RETURN QUERY
  SELECT
    b.id, b.slug, b.name, b.name_hi,
    COALESCE(pc.slug, fc.slug)  AS category_slug,
    COALESCE(pc.name, fc.name)  AS category_name,
    COALESCE(pc.icon, fc.icon)  AS category_icon,
    b.address_line1, gc.name AS city_name,
    gl.name AS locality_name,
    gl.slug AS locality_slug,
    b.pincode,
    b.whatsapp, b.mobile,
    b.usp_text, b.photos,
    b.hours_json,
    b.rating_avg, b.rating_count,
    b.verified_score,
    COALESCE(b.verified_visit, FALSE) AS verified_visit,
    CASE
      WHEN p_query IS NULL THEN 1::REAL
      ELSE similarity(
        b.name || ' ' || COALESCE(b.usp_text,'') || ' ' || COALESCE(pc.name, fc.name, ''),
        p_query
      )
    END AS match_rank,
    COALESCE(b.is_professional_listing, FALSE) AS is_professional_listing,   -- NEW (db/146)
    b.professional_tier                                                       -- NEW (db/146)
  FROM businesses b
  JOIN geo_cities gc ON gc.id = b.city_id
  LEFT JOIN geo_localities gl ON gl.id = b.locality_id
  LEFT JOIN business_categories bcp ON bcp.business_id = b.id AND bcp.is_primary = TRUE
  LEFT JOIN categories pc ON pc.id = bcp.category_id
  LEFT JOIN categories fc ON fc.id = b.category_id
  WHERE b.status = 'active'
    AND (p_city_id  IS NULL OR b.city_id  = p_city_id)
    AND (p_state_id IS NULL OR b.state_id = p_state_id)
    AND (v_pin_norm IS NULL OR b.pincode = v_pin_norm)
    AND (v_loc_lc = '' OR gl.slug = v_loc_lc)
    AND (p_query IS NULL OR v_q_lc = '' OR (
         b.name           ILIKE '%' || p_query || '%'
      OR b.usp_text       ILIKE '%' || p_query || '%'
      OR COALESCE(b.about_text,'')   ILIKE '%' || p_query || '%'
      OR COALESCE(b.address_line1,'') ILIKE '%' || p_query || '%'
      OR LOWER(COALESCE(pc.name,''))     LIKE '%' || v_q_lc || '%'
      OR LOWER(COALESCE(pc.name_hi,''))  LIKE '%' || v_q_lc || '%'
      OR LOWER(COALESCE(pc.keywords,'')) LIKE '%' || v_q_lc || '%'
      OR LOWER(COALESCE(fc.name,''))     LIKE '%' || v_q_lc || '%'
      OR LOWER(COALESCE(fc.name_hi,''))  LIKE '%' || v_q_lc || '%'
      OR LOWER(COALESCE(fc.keywords,'')) LIKE '%' || v_q_lc || '%'
      -- v298: what the shop actually sells. Up to 15 products/services per
      -- shop already live in businesses.services_json and already show on the
      -- shop's own page — but searching for one never found the shop, so a
      -- customer looking for "ELSS" or "Delux room" got nothing. Match the
      -- item name and its description.
      OR EXISTS (
        SELECT 1
        FROM jsonb_array_elements(
               CASE WHEN jsonb_typeof(COALESCE(b.services_json, '[]'::jsonb)) = 'array'
                    THEN COALESCE(b.services_json, '[]'::jsonb)
                    ELSE '[]'::jsonb END
             ) AS sv
        WHERE LOWER(COALESCE(sv->>'name', '')) LIKE '%' || v_q_lc || '%'
           OR LOWER(COALESCE(sv->>'desc', '')) LIKE '%' || v_q_lc || '%'
      )
      OR EXISTS (
        SELECT 1 FROM business_categories bcx
        JOIN categories cx ON cx.id = bcx.category_id
        WHERE bcx.business_id = b.id
          AND (
            LOWER(COALESCE(cx.name,''))     LIKE '%' || v_q_lc || '%'
            OR LOWER(COALESCE(cx.name_hi,''))  LIKE '%' || v_q_lc || '%'
            OR LOWER(COALESCE(cx.keywords,'')) LIKE '%' || v_q_lc || '%'
          )
      )
    ))
    AND (
      p_category IS NULL
      OR EXISTS (
        SELECT 1 FROM business_categories bc
        WHERE bc.business_id = b.id
          AND (
            bc.category_id = v_cat_id
            OR bc.category_id IN (SELECT categories.id FROM categories WHERE categories.parent_id = v_cat_id)
          )
      )
      OR (
        NOT EXISTS (SELECT 1 FROM business_categories bc2 WHERE bc2.business_id = b.id)
        AND (b.category_id = v_cat_id OR b.sub_category_id = v_cat_id)
      )
    )
  ORDER BY
    match_rank DESC NULLS LAST,
    COALESCE(b.verified_visit, FALSE) DESC,
    (COALESCE(b.verified_score, 0)
      + CASE WHEN b.created_at > NOW() - INTERVAL '14 days' THEN 2 ELSE 0 END
    ) DESC,
    b.rating_avg DESC NULLS LAST,
    b.name
  LIMIT GREATEST(1, LEAST(p_limit, 60))
  OFFSET GREATEST(0, p_offset);
END;
$$;

GRANT EXECUTE ON FUNCTION search_businesses(TEXT, TEXT, INT, SMALLINT, INT, INT, TEXT, TEXT)
  TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/146 installed.';
  RAISE NOTICE '  search_businesses now returns is_professional_listing + professional_tier.';
END $$;


-- Record in the register (db/233); guarded so this file also runs on a
-- database where 233 was never applied.
DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/238-search-inside-products.sql');
  END IF;
END $$;

-- ============================================================
-- Proof. Before this migration both of these returned nothing;
-- 'Delux room' is a real item on Ranveer Hotel's list.
-- ============================================================
-- (named arguments on purpose: the signature is
--  p_query, p_category, p_city_id, p_state_id, p_limit, p_offset,
--  p_pincode, p_locality_slug — easy to line up wrongly by position)
SELECT 'Delux room' AS searched_for, name AS found_shop
FROM search_businesses(p_query => 'Delux room', p_limit => 5)
UNION ALL
SELECT 'ELSS', name
FROM search_businesses(p_query => 'ELSS', p_limit => 5);
