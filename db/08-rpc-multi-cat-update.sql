-- =====================================================
-- 08-rpc-multi-cat-update.sql
-- Multi-Category Support: register_business_v2 + smarter search
-- =====================================================
-- Prerequisites: 01–07 SQL files already executed
-- HOW TO RUN: Paste in Supabase SQL Editor → Run
-- IDEMPOTENT: CREATE OR REPLACE, safe to re-run
-- =====================================================
-- WHAT THIS DOES:
--   1. New RPC `register_business_v2` — accepts category array (1–5) + primary
--   2. Replaces `search_businesses` — supports parent/sub category search
--      via business_categories junction table
--   3. Old `register_business` left UNTOUCHED for backward compat
-- =====================================================


-- =====================================================
-- SECTION 1: register_business_v2 — multi-category insert
-- =====================================================

CREATE OR REPLACE FUNCTION register_business_v2(
  p_category_ids        INT[],          -- 1 to 5 category IDs
  p_primary_category_id INT,            -- must be one of the above
  p_name                TEXT,
  p_name_hi             TEXT,
  p_owner_name          TEXT,
  p_mobile              TEXT,
  p_whatsapp            TEXT,
  p_email               TEXT,
  p_address_line1       TEXT,
  p_address_line2       TEXT,
  p_locality_id         INT,
  p_city_id             INT,
  p_district_id         INT,
  p_state_id            SMALLINT,
  p_pincode             TEXT,
  p_usp_text            TEXT,
  p_usp_hi              TEXT
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id           UUID;
  v_city_name         TEXT;
  v_slug              TEXT;
  v_biz_id            UUID;
  v_pincode_ok        BOOLEAN;
  v_cat_id            INT;
  v_primary_parent_id INT;
  v_n_cats            INT;
  v_invalid_count     INT;
BEGIN
  -- Auth
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Validate category array
  v_n_cats := COALESCE(array_length(p_category_ids, 1), 0);
  IF v_n_cats < 1 THEN
    RAISE EXCEPTION 'At least 1 category required';
  END IF;
  IF v_n_cats > 5 THEN
    RAISE EXCEPTION 'Maximum 5 categories allowed';
  END IF;

  -- Primary must be in the array
  IF NOT (p_primary_category_id = ANY(p_category_ids)) THEN
    RAISE EXCEPTION 'Primary category must be one of the selected categories';
  END IF;

  -- All categories must exist and be active
  SELECT COUNT(*) INTO v_invalid_count
  FROM unnest(p_category_ids) AS cid
  WHERE NOT EXISTS (SELECT 1 FROM categories WHERE id = cid AND active = TRUE);
  IF v_invalid_count > 0 THEN
    RAISE EXCEPTION 'One or more category IDs are invalid or inactive';
  END IF;

  -- Pincode-city match
  SELECT validate_pincode_city(p_pincode, p_city_id) INTO v_pincode_ok;
  IF NOT v_pincode_ok THEN
    RAISE EXCEPTION 'Pincode % does not match selected city', p_pincode;
  END IF;

  -- Get primary's parent (for businesses.category_id / sub_category_id mapping)
  SELECT parent_id INTO v_primary_parent_id
  FROM categories WHERE id = p_primary_category_id;

  -- City name for slug generation
  SELECT name INTO v_city_name FROM geo_cities WHERE id = p_city_id;
  v_slug := generate_business_slug(p_name, v_city_name);

  -- Insert business
  -- businesses.category_id   = parent of primary (if sub-cat) OR primary (if top-level)
  -- businesses.sub_category_id = primary (if sub-cat) OR NULL
  INSERT INTO businesses (
    slug,
    category_id,
    sub_category_id,
    name, name_hi, owner_name,
    mobile, whatsapp, email,
    address_line1, address_line2,
    locality_id, city_id, district_id, state_id, pincode,
    usp_text, usp_hi,
    status,
    verified_mobile, verified_address
  ) VALUES (
    v_slug,
    COALESCE(v_primary_parent_id, p_primary_category_id),
    CASE WHEN v_primary_parent_id IS NOT NULL THEN p_primary_category_id ELSE NULL END,
    p_name, p_name_hi, p_owner_name,
    p_mobile, COALESCE(NULLIF(p_whatsapp,''), p_mobile), p_email,
    p_address_line1, p_address_line2,
    p_locality_id, p_city_id, p_district_id, p_state_id, p_pincode,
    p_usp_text, p_usp_hi,
    'pending',
    TRUE,
    v_pincode_ok
  )
  RETURNING id INTO v_biz_id;

  -- Link owner
  INSERT INTO business_owners (business_id, auth_user_id, role)
  VALUES (v_biz_id, v_user_id, 'owner');

  -- Insert all selected categories into junction table.
  -- trg_update_cat_count auto-increments categories.business_count per insert.
  -- trg_sync_primary_cat auto-mirrors primary to businesses.category_id (no-op since
  -- we already set correct values above, but kept for any manual edits later).
  FOREACH v_cat_id IN ARRAY p_category_ids LOOP
    INSERT INTO business_categories (business_id, category_id, is_primary)
    VALUES (v_biz_id, v_cat_id, v_cat_id = p_primary_category_id);
  END LOOP;

  RETURN v_biz_id;
END;
$$;


-- =====================================================
-- SECTION 2: search_businesses — updated for multi-cat
-- =====================================================
-- Improvements:
--   * Reads PRIMARY category from junction (consistent display)
--   * Matches when ANY of business's categories matches the search slug
--   * Searching a PARENT slug returns businesses in any of its sub-categories
-- =====================================================

CREATE OR REPLACE FUNCTION search_businesses(
  p_query     TEXT     DEFAULT NULL,
  p_category  TEXT     DEFAULT NULL,     -- slug (parent or sub)
  p_city_id   INT      DEFAULT NULL,
  p_state_id  SMALLINT DEFAULT NULL,
  p_limit     INT      DEFAULT 20,
  p_offset    INT      DEFAULT 0
)
RETURNS TABLE (
  id              UUID,
  slug            TEXT,
  name            TEXT,
  name_hi         TEXT,
  category_slug   TEXT,
  category_name   TEXT,
  category_icon   TEXT,
  address_line1   TEXT,
  city_name       TEXT,
  pincode         TEXT,
  whatsapp        TEXT,
  mobile          TEXT,
  usp_text        TEXT,
  photos          TEXT[],
  rating_avg      NUMERIC,
  rating_count    INT,
  verified_score  SMALLINT,
  match_rank      REAL
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_cat_id INT;
BEGIN
  -- Resolve category slug to ID (if filter provided)
  IF p_category IS NOT NULL THEN
    SELECT cat.id INTO v_cat_id FROM categories cat
    WHERE cat.slug = p_category AND cat.active = TRUE;
  END IF;

  RETURN QUERY
  SELECT
    b.id, b.slug, b.name, b.name_hi,
    -- Show PRIMARY category from junction (with safe fallback to businesses.category_id)
    COALESCE(pc.slug, fc.slug) AS category_slug,
    COALESCE(pc.name, fc.name) AS category_name,
    COALESCE(pc.icon, fc.icon) AS category_icon,
    b.address_line1, gc.name AS city_name, b.pincode,
    b.whatsapp, b.mobile,
    b.usp_text, b.photos,
    b.rating_avg, b.rating_count, b.verified_score,
    CASE
      WHEN p_query IS NULL THEN 1::REAL
      ELSE similarity(b.name || ' ' || COALESCE(b.usp_text,''), p_query)
    END AS match_rank
  FROM businesses b
  JOIN geo_cities gc ON gc.id = b.city_id
  -- Primary category lookup via junction (preferred)
  LEFT JOIN business_categories bcp ON bcp.business_id = b.id AND bcp.is_primary = TRUE
  LEFT JOIN categories pc ON pc.id = bcp.category_id
  -- Fallback to businesses.category_id (for businesses inserted without junction)
  LEFT JOIN categories fc ON fc.id = b.category_id
  WHERE b.status = 'active'
    AND (p_city_id  IS NULL OR b.city_id  = p_city_id)
    AND (p_state_id IS NULL OR b.state_id = p_state_id)
    AND (p_query    IS NULL OR (b.name ILIKE '%' || p_query || '%' OR b.usp_text ILIKE '%' || p_query || '%'))
    AND (
      p_category IS NULL
      OR EXISTS (
        -- Match if business has the exact category OR any sub-category of the parent
        SELECT 1 FROM business_categories bc
        WHERE bc.business_id = b.id
          AND (
            bc.category_id = v_cat_id
            OR bc.category_id IN (SELECT id FROM categories WHERE parent_id = v_cat_id)
          )
      )
      -- Fallback for legacy rows without junction entries
      OR (
        NOT EXISTS (SELECT 1 FROM business_categories WHERE business_id = b.id)
        AND (b.category_id = v_cat_id OR b.sub_category_id = v_cat_id)
      )
    )
  ORDER BY match_rank DESC, b.verified_score DESC, b.rating_avg DESC, b.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;


-- =====================================================
-- SECTION 3: Helper RPC — get business with all categories
-- =====================================================
-- Useful for business.html (public profile) — returns full cat list with primary marked
-- =====================================================

CREATE OR REPLACE FUNCTION get_business_categories(p_business_id UUID)
RETURNS TABLE (
  category_id    INT,
  slug           TEXT,
  name           TEXT,
  name_hi        TEXT,
  icon           TEXT,
  color          TEXT,
  parent_slug    TEXT,
  parent_name    TEXT,
  is_primary     BOOLEAN
)
LANGUAGE sql STABLE AS $$
  SELECT
    c.id, c.slug, c.name, c.name_hi, c.icon, c.color,
    p.slug, p.name,
    bc.is_primary
  FROM business_categories bc
  JOIN categories c       ON c.id = bc.category_id
  LEFT JOIN categories p  ON p.id = c.parent_id
  WHERE bc.business_id = p_business_id
  ORDER BY bc.is_primary DESC, c.sort_order;
$$;


-- =====================================================
-- SECTION 4: Reload PostgREST schema cache
-- =====================================================

NOTIFY pgrst, 'reload schema';


-- =====================================================
-- VERIFICATION QUERIES — run separately to test
-- =====================================================
-- 1) Confirm new RPC visible:
--    SELECT proname FROM pg_proc WHERE proname IN
--    ('register_business_v2','search_businesses','get_business_categories');
--    (expect 3 rows)
--
-- 2) Test categories query (returns 10 parents + their subs):
--    SELECT p.slug AS parent, COUNT(c.id) AS sub_count
--    FROM categories p LEFT JOIN categories c ON c.parent_id = p.id
--    WHERE p.parent_id IS NULL
--    GROUP BY p.slug, p.sort_order
--    ORDER BY p.sort_order;
-- =====================================================
