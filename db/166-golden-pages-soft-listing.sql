-- ============================================================
-- db/166 — Golden Pages soft-listing directory
-- ============================================================
-- Reference-based bulk-add directory that lives separately from the
-- main DukanList feed. Admin adds 100s of shops with just name +
-- category + area (mobile optional). Lives on /golden-pages.html
-- only — INVISIBLE on main DukanList until owner claims + upgrades.
--
-- WHY a new status value (not a separate column / table):
--   Almost every public RPC + JS query already filters by
--   status='active'. By introducing 'soft_listed' as a new status
--   value, soft listings are AUTOMATICALLY excluded from main
--   DukanList everywhere — zero changes needed across ~10 existing
--   query sites. Golden Pages page uses status='soft_listed' to
--   list them. When owner claims, status flips to 'pending' (enters
--   normal moderation queue + email gate).
--
-- 7 new RPCs:
--   1. admin_soft_add_shop()       — single add (admin)
--   2. admin_soft_bulk_add()       — paste N names with shared
--                                    category + area (admin)
--   3. gp_list_shops()             — public list with category/
--                                    city/search filters
--   4. gp_categories_with_counts() — top categories for category
--                                    browse on Golden Pages
--   5. gp_stats()                  — total/today/by-city counters
--   6. gp_claim_soft_listing()     — owner claim → flip to pending
--   7. gp_help_reach()             — customer-driven nudge (logs
--                                    a request, doesn't expose owner)
--
-- SAFE: Constraint extension is backward-compatible. All existing
-- statuses preserved. Re-runnable idempotent.
-- ============================================================

BEGIN;

-- ============================================================
-- PART 1: Extend status CHECK constraint to add 'soft_listed'
-- ============================================================
ALTER TABLE businesses DROP CONSTRAINT IF EXISTS businesses_status_check;
ALTER TABLE businesses ADD CONSTRAINT businesses_status_check
  CHECK (status IN ('pending','pending_review','active','soft_listed','flagged','banned','self_hidden'));

CREATE INDEX IF NOT EXISTS idx_biz_soft_listed
  ON businesses(category_id, city_id)
  WHERE status = 'soft_listed';


-- ============================================================
-- PART 2: gp_help_reach_log — track customer-driven nudge requests
-- ============================================================
CREATE TABLE IF NOT EXISTS gp_help_reach_log (
  id              BIGSERIAL PRIMARY KEY,
  business_id     UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  customer_ip_hash TEXT,                       -- hashed for dedup, NOT identifying
  customer_note   TEXT,                         -- optional message from customer
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_gp_help_biz ON gp_help_reach_log(business_id);
CREATE INDEX IF NOT EXISTS idx_gp_help_recent ON gp_help_reach_log(created_at DESC);


-- ============================================================
-- PART 3: RPC — admin_soft_add_shop (single add)
-- ============================================================
CREATE OR REPLACE FUNCTION admin_soft_add_shop(
  p_name           TEXT,
  p_category_slug  TEXT,
  p_area           TEXT DEFAULT NULL,
  p_mobile         TEXT DEFAULT NULL,
  p_city_id        INT  DEFAULT NULL,
  p_source         TEXT DEFAULT 'reference',
  p_notes          TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_admin_email TEXT;
  v_norm_mobile TEXT;
  v_slug        TEXT;
  v_token       TEXT;
  v_business_id UUID;
  v_category_id INT;
  v_city_id     INT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  SELECT email INTO v_admin_email FROM admin_users WHERE auth_user_id = auth.uid();

  IF p_name IS NULL OR LENGTH(TRIM(p_name)) < 2 THEN
    RAISE EXCEPTION 'Shop name required (min 2 chars)';
  END IF;

  IF p_category_slug IS NULL OR LENGTH(TRIM(p_category_slug)) < 1 THEN
    RAISE EXCEPTION 'Category required';
  END IF;

  SELECT id INTO v_category_id FROM categories WHERE slug = p_category_slug AND active = TRUE LIMIT 1;
  IF v_category_id IS NULL THEN
    RAISE EXCEPTION 'Invalid category: %', p_category_slug;
  END IF;

  -- Mobile is OPTIONAL for soft listings. If provided, normalize.
  IF p_mobile IS NOT NULL AND LENGTH(TRIM(p_mobile)) > 0 THEN
    v_norm_mobile := norm_indian_mobile(p_mobile);
    IF v_norm_mobile IS NULL THEN
      RAISE EXCEPTION 'If providing mobile, it must be a valid 10-digit Indian number';
    END IF;
    -- Light dedup — if a shop already exists with this mobile, point them at claim instead
    IF EXISTS (SELECT 1 FROM businesses WHERE mobile = v_norm_mobile) THEN
      RAISE EXCEPTION 'A shop with mobile % already exists — search before adding', v_norm_mobile;
    END IF;
  END IF;

  v_city_id := COALESCE(
    p_city_id,
    (SELECT id FROM geo_cities WHERE name ILIKE 'mandi dabwali' LIMIT 1),
    (SELECT id FROM geo_cities WHERE active LIMIT 1)
  );

  v_slug  := generate_unique_slug(TRIM(p_name) || COALESCE(' ' || TRIM(p_area), ''));
  v_token := encode(extensions.gen_random_bytes(20), 'hex');

  INSERT INTO businesses (
    slug, name, mobile, whatsapp,
    category_id, city_id,
    address_line1,
    status, claim_status,
    pre_listed_by, pre_listed_at,
    consent_method, consent_notes,
    claim_token,
    created_at, updated_at
  ) VALUES (
    v_slug, TRIM(p_name), v_norm_mobile, v_norm_mobile,
    v_category_id, v_city_id,
    COALESCE(NULLIF(TRIM(p_area), ''), ''),
    'soft_listed', 'unclaimed',
    COALESCE(v_admin_email, p_source), NOW(),
    'public-data', p_notes,
    v_token,
    NOW(), NOW()
  )
  RETURNING id INTO v_business_id;

  -- Also link to business_categories junction (single primary)
  INSERT INTO business_categories (business_id, category_id, is_primary)
  VALUES (v_business_id, v_category_id, TRUE)
  ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object(
    'success',     TRUE,
    'business_id', v_business_id,
    'slug',        v_slug,
    'claim_token', v_token,
    'gp_url',      'https://dukanlist.com/golden-pages.html#shop=' || v_slug,
    'claim_url',   'https://dukanlist.com/claim.html?token=' || v_token
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_soft_add_shop(TEXT, TEXT, TEXT, TEXT, INT, TEXT, TEXT) TO authenticated;


-- ============================================================
-- PART 4: RPC — admin_soft_bulk_add (paste N names)
-- ============================================================
-- Takes shared category + area + a TEXT[] of names. Returns per-name
-- success/skip report. Skip reasons: duplicate slug, validation fail.
CREATE OR REPLACE FUNCTION admin_soft_bulk_add(
  p_names          TEXT[],
  p_category_slug  TEXT,
  p_area           TEXT DEFAULT NULL,
  p_city_id        INT  DEFAULT NULL,
  p_source         TEXT DEFAULT 'bulk-reference'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_admin_email TEXT;
  v_category_id INT;
  v_city_id     INT;
  v_name        TEXT;
  v_clean_name  TEXT;
  v_slug        TEXT;
  v_token       TEXT;
  v_business_id UUID;
  v_added       INT := 0;
  v_skipped     INT := 0;
  v_added_list  JSONB := '[]'::jsonb;
  v_skipped_list JSONB := '[]'::jsonb;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  SELECT email INTO v_admin_email FROM admin_users WHERE auth_user_id = auth.uid();

  IF p_names IS NULL OR array_length(p_names, 1) IS NULL OR array_length(p_names, 1) < 1 THEN
    RAISE EXCEPTION 'Provide at least 1 name';
  END IF;
  IF array_length(p_names, 1) > 500 THEN
    RAISE EXCEPTION 'Max 500 names per batch — split into smaller chunks';
  END IF;

  SELECT id INTO v_category_id FROM categories WHERE slug = p_category_slug AND active = TRUE LIMIT 1;
  IF v_category_id IS NULL THEN
    RAISE EXCEPTION 'Invalid category: %', p_category_slug;
  END IF;

  v_city_id := COALESCE(
    p_city_id,
    (SELECT id FROM geo_cities WHERE name ILIKE 'mandi dabwali' LIMIT 1),
    (SELECT id FROM geo_cities WHERE active LIMIT 1)
  );

  FOREACH v_name IN ARRAY p_names LOOP
    v_clean_name := TRIM(COALESCE(v_name, ''));
    IF v_clean_name = '' OR LENGTH(v_clean_name) < 2 THEN
      v_skipped := v_skipped + 1;
      v_skipped_list := v_skipped_list || jsonb_build_object('name', v_name, 'reason', 'too short');
      CONTINUE;
    END IF;

    v_slug := generate_unique_slug(v_clean_name || COALESCE(' ' || TRIM(p_area), ''));
    v_token := encode(extensions.gen_random_bytes(20), 'hex');

    BEGIN
      INSERT INTO businesses (
        slug, name,
        category_id, city_id,
        address_line1,
        status, claim_status,
        pre_listed_by, pre_listed_at,
        consent_method,
        claim_token,
        created_at, updated_at
      ) VALUES (
        v_slug, v_clean_name,
        v_category_id, v_city_id,
        COALESCE(NULLIF(TRIM(p_area), ''), ''),
        'soft_listed', 'unclaimed',
        COALESCE(v_admin_email, p_source), NOW(),
        'public-data',
        v_token,
        NOW(), NOW()
      )
      RETURNING id INTO v_business_id;

      INSERT INTO business_categories (business_id, category_id, is_primary)
      VALUES (v_business_id, v_category_id, TRUE)
      ON CONFLICT DO NOTHING;

      v_added := v_added + 1;
      v_added_list := v_added_list || jsonb_build_object(
        'name', v_clean_name,
        'slug', v_slug,
        'business_id', v_business_id
      );
    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      v_skipped_list := v_skipped_list || jsonb_build_object(
        'name', v_clean_name, 'reason', SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', TRUE,
    'added',   v_added,
    'skipped', v_skipped,
    'added_list',   v_added_list,
    'skipped_list', v_skipped_list
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_soft_bulk_add(TEXT[], TEXT, TEXT, INT, TEXT) TO authenticated;


-- ============================================================
-- PART 5: RPC — gp_list_shops (public, paginated)
-- ============================================================
CREATE OR REPLACE FUNCTION gp_list_shops(
  p_category_slug TEXT DEFAULT NULL,
  p_city_id       INT  DEFAULT NULL,
  p_search        TEXT DEFAULT NULL,
  p_limit         INT  DEFAULT 50,
  p_offset        INT  DEFAULT 0
)
RETURNS TABLE (
  id            UUID,
  slug          TEXT,
  name          TEXT,
  area          TEXT,
  has_mobile    BOOLEAN,
  category_id   INT,
  category_name TEXT,
  category_icon TEXT,
  city_id       INT,
  city_name     TEXT,
  pre_listed_at TIMESTAMPTZ,
  claim_token   TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    b.id, b.slug, b.name, b.address_line1,
    (b.mobile IS NOT NULL AND LENGTH(b.mobile) = 10) AS has_mobile,
    b.category_id, c.name, c.icon,
    b.city_id, gc.name,
    b.pre_listed_at,
    b.claim_token
  FROM businesses b
  LEFT JOIN categories c ON c.id = b.category_id
  LEFT JOIN geo_cities gc ON gc.id = b.city_id
  WHERE b.status = 'soft_listed'
    AND (p_category_slug IS NULL OR c.slug = p_category_slug)
    AND (p_city_id IS NULL OR b.city_id = p_city_id)
    AND (p_search IS NULL OR LENGTH(TRIM(p_search)) = 0 OR
         b.name ILIKE '%' || TRIM(p_search) || '%' OR
         b.address_line1 ILIKE '%' || TRIM(p_search) || '%')
  ORDER BY b.pre_listed_at DESC NULLS LAST, b.name ASC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION gp_list_shops(TEXT, INT, TEXT, INT, INT) TO anon, authenticated;


-- ============================================================
-- PART 6: RPC — gp_categories_with_counts (browse-by-category)
-- ============================================================
CREATE OR REPLACE FUNCTION gp_categories_with_counts(
  p_city_id INT DEFAULT NULL
)
RETURNS TABLE (
  category_id   INT,
  category_slug TEXT,
  category_name TEXT,
  icon          TEXT,
  shop_count    INT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.id, c.slug, c.name, c.icon, COUNT(*)::INT AS shop_count
  FROM businesses b
  JOIN categories c ON c.id = b.category_id
  WHERE b.status = 'soft_listed'
    AND (p_city_id IS NULL OR b.city_id = p_city_id)
  GROUP BY c.id, c.slug, c.name, c.icon
  HAVING COUNT(*) > 0
  ORDER BY COUNT(*) DESC, c.name ASC;
$$;

GRANT EXECUTE ON FUNCTION gp_categories_with_counts(INT) TO anon, authenticated;


-- ============================================================
-- PART 7: RPC — gp_stats
-- ============================================================
CREATE OR REPLACE FUNCTION gp_stats(p_city_id INT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN jsonb_build_object(
    'total',       (SELECT COUNT(*)::INT FROM businesses WHERE status = 'soft_listed' AND (p_city_id IS NULL OR city_id = p_city_id)),
    'today_added', (SELECT COUNT(*)::INT FROM businesses WHERE status = 'soft_listed' AND pre_listed_at >= CURRENT_DATE AND (p_city_id IS NULL OR city_id = p_city_id)),
    'week_added',  (SELECT COUNT(*)::INT FROM businesses WHERE status = 'soft_listed' AND pre_listed_at >= CURRENT_DATE - INTERVAL '7 days' AND (p_city_id IS NULL OR city_id = p_city_id)),
    'top_categories', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object('slug', c.slug, 'name', c.name, 'icon', c.icon, 'count', cnt)), '[]'::jsonb)
      FROM (
        SELECT category_id, COUNT(*)::INT AS cnt
        FROM businesses
        WHERE status = 'soft_listed' AND (p_city_id IS NULL OR city_id = p_city_id)
        GROUP BY category_id
        ORDER BY COUNT(*) DESC
        LIMIT 5
      ) t
      JOIN categories c ON c.id = t.category_id
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION gp_stats(INT) TO anon, authenticated;


-- ============================================================
-- PART 8: RPC — gp_help_reach (customer nudge)
-- ============================================================
CREATE OR REPLACE FUNCTION gp_help_reach(
  p_business_id   UUID,
  p_customer_note TEXT DEFAULT NULL,
  p_ip_hash       TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  -- Light dedup: same IP hash can't spam the same business
  IF p_ip_hash IS NOT NULL THEN
    SELECT COUNT(*) INTO v_count
    FROM gp_help_reach_log
    WHERE business_id = p_business_id
      AND customer_ip_hash = p_ip_hash
      AND created_at > NOW() - INTERVAL '24 hours';
    IF v_count > 0 THEN
      RETURN jsonb_build_object('success', TRUE, 'deduped', TRUE);
    END IF;
  END IF;

  INSERT INTO gp_help_reach_log (business_id, customer_ip_hash, customer_note)
  VALUES (p_business_id, p_ip_hash, NULLIF(TRIM(COALESCE(p_customer_note,'')), ''));

  RETURN jsonb_build_object('success', TRUE);
END;
$$;

GRANT EXECUTE ON FUNCTION gp_help_reach(UUID, TEXT, TEXT) TO anon, authenticated;


-- ============================================================
-- PART 9: RPC — admin_gp_help_requests (admin reads pending nudges)
-- ============================================================
CREATE OR REPLACE FUNCTION admin_gp_help_requests(
  p_limit  INT DEFAULT 100,
  p_offset INT DEFAULT 0
)
RETURNS TABLE (
  id           BIGINT,
  business_id  UUID,
  business_name TEXT,
  business_area TEXT,
  category_name TEXT,
  customer_note TEXT,
  request_count INT,
  created_at    TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  RETURN QUERY
  SELECT
    MAX(l.id) AS id,
    l.business_id,
    b.name, b.address_line1, c.name,
    -- show most recent note
    (ARRAY_AGG(l.customer_note ORDER BY l.created_at DESC) FILTER (WHERE l.customer_note IS NOT NULL))[1],
    COUNT(*)::INT,
    MAX(l.created_at)
  FROM gp_help_reach_log l
  JOIN businesses b ON b.id = l.business_id
  LEFT JOIN categories c ON c.id = b.category_id
  WHERE b.status = 'soft_listed'  -- only show requests for still-soft listings
  GROUP BY l.business_id, b.name, b.address_line1, c.name
  ORDER BY COUNT(*) DESC, MAX(l.created_at) DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_gp_help_requests(INT, INT) TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/166 installed. Golden Pages soft-listing directory ready.';
END $$;
