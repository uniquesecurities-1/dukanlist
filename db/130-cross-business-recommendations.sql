-- ============================================================
-- db/130 — Cross-Business Referral Network
-- ============================================================
-- The "Doctor-Optical Effect" — owners can recommend up to 8
-- trusted partner businesses. Creates a referral graph that
-- transfers trust between connected businesses.
--
-- Public viewers see:
--   On Dr. Sharma's page: "Also recommended by Dr. Sharma:
--                          → Sharma Optical, Bansal Pharmacy..."
--   On Sharma Optical's page: "★ Recommended by Dr. Sharma"
--
-- Max 8 recommendations per business to keep curation high.
-- Idempotent migration, forward-only.
-- ============================================================

BEGIN;

-- =============================================================
-- TABLE
-- =============================================================
CREATE TABLE IF NOT EXISTS business_recommendations (
  id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recommender_business_id    UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  recommended_business_id    UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  relationship_label         TEXT,        -- e.g., "For glasses", "Our preferred lab", "Trusted neighbor"
  display_order              INT NOT NULL DEFAULT 0,
  status                     TEXT NOT NULL DEFAULT 'active'
                             CHECK (status IN ('active','hidden','removed')),
  created_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Cannot recommend yourself, no duplicates
  CONSTRAINT no_self_recommendation
    CHECK (recommender_business_id <> recommended_business_id),
  CONSTRAINT unique_recommendation
    UNIQUE (recommender_business_id, recommended_business_id)
);

-- Indexes for fast lookup in both directions
CREATE INDEX IF NOT EXISTS idx_recs_by_recommender
  ON business_recommendations (recommender_business_id, display_order)
  WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_recs_by_recommended
  ON business_recommendations (recommended_business_id)
  WHERE status = 'active';

-- =============================================================
-- RLS POLICIES
-- =============================================================
ALTER TABLE business_recommendations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "recs_public_read" ON business_recommendations;
CREATE POLICY "recs_public_read"
  ON business_recommendations
  FOR SELECT TO anon, authenticated
  USING (status = 'active');

-- Owners can modify their OWN recommendations (recommender side only)
DROP POLICY IF EXISTS "recs_owner_write" ON business_recommendations;
CREATE POLICY "recs_owner_write"
  ON business_recommendations
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM business_owners bo
       WHERE bo.business_id = business_recommendations.recommender_business_id
         AND bo.auth_user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM business_owners bo
       WHERE bo.business_id = business_recommendations.recommender_business_id
         AND bo.auth_user_id = auth.uid()
    )
  );

-- Admins can do anything
DROP POLICY IF EXISTS "recs_admin_all" ON business_recommendations;
CREATE POLICY "recs_admin_all"
  ON business_recommendations
  FOR ALL TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

-- =============================================================
-- RPC: get_my_recommendations()
-- Returns the businesses *I* have recommended (with their details)
-- =============================================================
CREATE OR REPLACE FUNCTION get_my_recommendations()
RETURNS TABLE (
  id                 UUID,
  recommended_id     UUID,
  recommended_name   TEXT,
  recommended_slug   TEXT,
  recommended_city   TEXT,
  recommended_cat    TEXT,
  recommended_icon   TEXT,
  relationship_label TEXT,
  display_order      INT,
  created_at         TIMESTAMPTZ
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_biz_id UUID;
BEGIN
  SELECT bo.business_id INTO v_biz_id
    FROM business_owners bo
   WHERE bo.auth_user_id = auth.uid()
   LIMIT 1;
  IF v_biz_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    r.id,
    r.recommended_business_id,
    b.name,
    b.slug,
    COALESCE(gc.name, ''),
    COALESCE(c.name, ''),
    COALESCE(c.icon, '🏪'),
    r.relationship_label,
    r.display_order,
    r.created_at
   FROM business_recommendations r
   JOIN businesses b ON b.id = r.recommended_business_id
   LEFT JOIN geo_cities gc ON gc.id = b.city_id
   LEFT JOIN categories c ON c.id = COALESCE(b.sub_category_id, b.category_id)
   WHERE r.recommender_business_id = v_biz_id
     AND r.status = 'active'
   ORDER BY r.display_order ASC, r.created_at ASC;
END $$;

GRANT EXECUTE ON FUNCTION get_my_recommendations() TO authenticated;

-- =============================================================
-- RPC: get_recommendations_for_business(slug)
-- Returns businesses recommended BY the given business (public read)
-- =============================================================
CREATE OR REPLACE FUNCTION get_recommendations_for_business(p_business_slug TEXT)
RETURNS TABLE (
  recommended_id     UUID,
  recommended_name   TEXT,
  recommended_slug   TEXT,
  recommended_city   TEXT,
  recommended_cat    TEXT,
  recommended_icon   TEXT,
  recommended_photo  TEXT,
  recommended_rating NUMERIC,
  relationship_label TEXT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_biz_id UUID;
BEGIN
  SELECT id INTO v_biz_id FROM businesses
   WHERE slug = p_business_slug AND status = 'active' LIMIT 1;
  IF v_biz_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    r.recommended_business_id,
    b.name,
    b.slug,
    COALESCE(gc.name, ''),
    COALESCE(c.name, ''),
    COALESCE(c.icon, '🏪'),
    CASE WHEN b.photos IS NOT NULL AND array_length(b.photos, 1) > 0
         THEN b.photos[1] ELSE NULL END,
    COALESCE(b.rating_avg, 0)::NUMERIC,
    r.relationship_label
   FROM business_recommendations r
   JOIN businesses b ON b.id = r.recommended_business_id
   LEFT JOIN geo_cities gc ON gc.id = b.city_id
   LEFT JOIN categories c ON c.id = COALESCE(b.sub_category_id, b.category_id)
   WHERE r.recommender_business_id = v_biz_id
     AND r.status = 'active'
     AND b.status = 'active'
   ORDER BY r.display_order ASC, r.created_at ASC;
END $$;

GRANT EXECUTE ON FUNCTION get_recommendations_for_business(TEXT) TO anon, authenticated;

-- =============================================================
-- RPC: get_recommenders_of_business(slug)
-- Returns businesses that recommend the given business (reverse lookup)
-- Used for showing "Recommended by Dr. Sharma" trust badges
-- =============================================================
CREATE OR REPLACE FUNCTION get_recommenders_of_business(p_business_slug TEXT)
RETURNS TABLE (
  recommender_id    UUID,
  recommender_name  TEXT,
  recommender_slug  TEXT,
  recommender_cat   TEXT,
  recommender_icon  TEXT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_biz_id UUID;
BEGIN
  SELECT id INTO v_biz_id FROM businesses
   WHERE slug = p_business_slug AND status = 'active' LIMIT 1;
  IF v_biz_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    r.recommender_business_id,
    b.name,
    b.slug,
    COALESCE(c.name, ''),
    COALESCE(c.icon, '🏪')
   FROM business_recommendations r
   JOIN businesses b ON b.id = r.recommender_business_id
   LEFT JOIN categories c ON c.id = COALESCE(b.sub_category_id, b.category_id)
   WHERE r.recommended_business_id = v_biz_id
     AND r.status = 'active'
     AND b.status = 'active'
   ORDER BY b.verified_score DESC NULLS LAST, b.created_at ASC
   LIMIT 8;  -- cap to keep page clean
END $$;

GRANT EXECUTE ON FUNCTION get_recommenders_of_business(TEXT) TO anon, authenticated;

-- =============================================================
-- RPC: add_recommendation(recommended_business_id, relationship_label)
-- =============================================================
CREATE OR REPLACE FUNCTION add_recommendation(
  p_recommended_business_id UUID,
  p_relationship_label      TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_biz_id UUID;
  v_existing UUID;
  v_count INT;
  v_new_id UUID;
BEGIN
  -- Find calling user's business
  SELECT bo.business_id INTO v_biz_id
    FROM business_owners bo
   WHERE bo.auth_user_id = auth.uid()
   LIMIT 1;
  IF v_biz_id IS NULL THEN
    RAISE EXCEPTION 'No business associated with current user';
  END IF;

  -- Can't recommend self
  IF v_biz_id = p_recommended_business_id THEN
    RAISE EXCEPTION 'Cannot recommend your own business';
  END IF;

  -- Verify the recommended business exists and is active
  IF NOT EXISTS (
    SELECT 1 FROM businesses
     WHERE id = p_recommended_business_id AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Recommended business not found or not active';
  END IF;

  -- Cap at 8 recommendations per business
  SELECT COUNT(*) INTO v_count FROM business_recommendations
   WHERE recommender_business_id = v_biz_id
     AND status = 'active';
  IF v_count >= 8 THEN
    RAISE EXCEPTION 'Maximum 8 recommendations allowed. Remove one first.';
  END IF;

  -- Insert or reactivate
  INSERT INTO business_recommendations (
    recommender_business_id, recommended_business_id,
    relationship_label, display_order, status
  ) VALUES (
    v_biz_id, p_recommended_business_id,
    NULLIF(TRIM(p_relationship_label), ''),
    v_count, 'active'
  )
  ON CONFLICT (recommender_business_id, recommended_business_id)
  DO UPDATE SET
    status = 'active',
    relationship_label = EXCLUDED.relationship_label,
    updated_at = NOW()
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END $$;

GRANT EXECUTE ON FUNCTION add_recommendation(UUID, TEXT) TO authenticated;

-- =============================================================
-- RPC: remove_recommendation(recommendation_id)
-- =============================================================
CREATE OR REPLACE FUNCTION remove_recommendation(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_biz_id UUID;
BEGIN
  SELECT bo.business_id INTO v_biz_id
    FROM business_owners bo
   WHERE bo.auth_user_id = auth.uid()
   LIMIT 1;
  IF v_biz_id IS NULL THEN
    RAISE EXCEPTION 'No business associated with current user';
  END IF;

  DELETE FROM business_recommendations
   WHERE id = p_id
     AND recommender_business_id = v_biz_id;
END $$;

GRANT EXECUTE ON FUNCTION remove_recommendation(UUID) TO authenticated;

-- =============================================================
-- RPC: search_businesses_for_recommendation(query)
-- Lightweight search to populate the "Add recommendation" picker.
-- Excludes the caller's own business.
-- =============================================================
CREATE OR REPLACE FUNCTION search_businesses_for_recommendation(p_query TEXT)
RETURNS TABLE (
  id        UUID,
  name      TEXT,
  slug      TEXT,
  city_name TEXT,
  cat_name  TEXT,
  cat_icon  TEXT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_my_biz_id UUID;
  v_q TEXT;
BEGIN
  v_q := LOWER(TRIM(COALESCE(p_query, '')));
  IF LENGTH(v_q) < 2 THEN
    RETURN;
  END IF;

  SELECT bo.business_id INTO v_my_biz_id
    FROM business_owners bo
   WHERE bo.auth_user_id = auth.uid()
   LIMIT 1;

  RETURN QUERY
  SELECT
    b.id, b.name, b.slug,
    COALESCE(gc.name, '')::TEXT,
    COALESCE(c.name, '')::TEXT,
    COALESCE(c.icon, '🏪')::TEXT
   FROM businesses b
   LEFT JOIN geo_cities gc ON gc.id = b.city_id
   LEFT JOIN categories c ON c.id = COALESCE(b.sub_category_id, b.category_id)
   WHERE b.status = 'active'
     AND (v_my_biz_id IS NULL OR b.id <> v_my_biz_id)
     AND (LOWER(b.name) LIKE '%' || v_q || '%'
          OR LOWER(b.slug) LIKE '%' || v_q || '%')
   ORDER BY b.verified_score DESC NULLS LAST, b.name ASC
   LIMIT 15;
END $$;

GRANT EXECUTE ON FUNCTION search_businesses_for_recommendation(TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';

DO $$
BEGIN
  RAISE NOTICE '✓ db/130 — Cross-business recommendation network ready';
END $$;

COMMIT;
