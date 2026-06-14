-- ============================================================
-- db/131 — Recommendations Phase 2: reciprocal badge + recipient control
-- ============================================================
-- Two improvements on top of db/130:
--
-- 1. RECIPROCAL DISPLAY
--    When A recommends B, B's public page should show
--    "★ Recommended by A on DukanList". This builds two-way
--    trust transfer (the Doctor-Optical Effect both directions).
--    Existing get_recommenders_of_business() already supports
--    this — Phase 2 just exposes it cleanly.
--
-- 2. RECIPIENT CONTROL
--    If a non-reputed shop recommends me without my consent,
--    I should be able to hide it from MY public profile.
--    New column: recipient_hidden BOOLEAN. New RPCs to hide/unhide.
--    Hidden recommendations stay in the recommender's panel
--    (with a note) but disappear from the recipient's public page
--    AND from the recommender's public list (because trust is
--    consensual — if you don't want to be associated, you shouldn't be).
--
-- Idempotent migration, forward-only.
-- ============================================================

BEGIN;

-- =============================================================
-- 1. Add recipient_hidden column to existing table
-- =============================================================
ALTER TABLE business_recommendations
  ADD COLUMN IF NOT EXISTS recipient_hidden BOOLEAN NOT NULL DEFAULT FALSE;

-- Index for fast "is this hidden by recipient" check
CREATE INDEX IF NOT EXISTS idx_recs_recipient_hidden
  ON business_recommendations (recommended_business_id, recipient_hidden)
  WHERE status = 'active';

-- =============================================================
-- 2. RECREATE get_recommendations_for_business — exclude hidden
-- =============================================================
-- Return type unchanged but DROP defensively in case PostgREST cached
DROP FUNCTION IF EXISTS get_recommendations_for_business(TEXT);
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
     AND r.recipient_hidden = FALSE   -- NEW: respect recipient's choice
     AND b.status = 'active'
   ORDER BY r.display_order ASC, r.created_at ASC;
END $$;

GRANT EXECUTE ON FUNCTION get_recommendations_for_business(TEXT) TO anon, authenticated;

-- =============================================================
-- 3. RECREATE get_recommenders_of_business — exclude hidden
-- Return type CHANGED (added recommender_city, recommender_verified_score,
-- relationship_label). Must DROP first — Postgres won't let CREATE OR
-- REPLACE change OUT parameter shape.
-- =============================================================
DROP FUNCTION IF EXISTS get_recommenders_of_business(TEXT);
CREATE OR REPLACE FUNCTION get_recommenders_of_business(p_business_slug TEXT)
RETURNS TABLE (
  recommender_id     UUID,
  recommender_name   TEXT,
  recommender_slug   TEXT,
  recommender_cat    TEXT,
  recommender_icon   TEXT,
  recommender_city   TEXT,
  recommender_verified_score INT,
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
    r.recommender_business_id,
    b.name,
    b.slug,
    COALESCE(c.name, ''),
    COALESCE(c.icon, '🏪'),
    COALESCE(gc.name, ''),
    COALESCE(b.verified_score, 0)::INT,
    r.relationship_label
   FROM business_recommendations r
   JOIN businesses b ON b.id = r.recommender_business_id
   LEFT JOIN geo_cities gc ON gc.id = b.city_id
   LEFT JOIN categories c ON c.id = COALESCE(b.sub_category_id, b.category_id)
   WHERE r.recommended_business_id = v_biz_id
     AND r.status = 'active'
     AND r.recipient_hidden = FALSE   -- NEW
     AND b.status = 'active'
   ORDER BY b.verified_score DESC NULLS LAST, b.created_at ASC
   LIMIT 8;
END $$;

GRANT EXECUTE ON FUNCTION get_recommenders_of_business(TEXT) TO anon, authenticated;

-- =============================================================
-- 4. NEW: get_my_incoming_recommendations()
-- Returns businesses that recommend ME (logged-in owner)
-- including hidden ones so I can manage them
-- =============================================================
CREATE OR REPLACE FUNCTION get_my_incoming_recommendations()
RETURNS TABLE (
  id                 UUID,
  recommender_id     UUID,
  recommender_name   TEXT,
  recommender_slug   TEXT,
  recommender_city   TEXT,
  recommender_cat    TEXT,
  recommender_icon   TEXT,
  recommender_verified_score INT,
  relationship_label TEXT,
  recipient_hidden   BOOLEAN,
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
  IF v_biz_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    r.id,
    r.recommender_business_id,
    b.name,
    b.slug,
    COALESCE(gc.name, ''),
    COALESCE(c.name, ''),
    COALESCE(c.icon, '🏪'),
    COALESCE(b.verified_score, 0)::INT,
    r.relationship_label,
    r.recipient_hidden,
    r.created_at
   FROM business_recommendations r
   JOIN businesses b ON b.id = r.recommender_business_id
   LEFT JOIN geo_cities gc ON gc.id = b.city_id
   LEFT JOIN categories c ON c.id = COALESCE(b.sub_category_id, b.category_id)
   WHERE r.recommended_business_id = v_biz_id
     AND r.status = 'active'
     AND b.status = 'active'
   ORDER BY r.recipient_hidden ASC, b.verified_score DESC NULLS LAST, r.created_at DESC;
END $$;

GRANT EXECUTE ON FUNCTION get_my_incoming_recommendations() TO authenticated;

-- =============================================================
-- 5. NEW: set_incoming_recommendation_hidden(id, hidden)
-- Recipient can hide/unhide a recommendation TARGETING them
-- =============================================================
CREATE OR REPLACE FUNCTION set_incoming_recommendation_hidden(
  p_id      UUID,
  p_hidden  BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_biz_id UUID;
  v_target_biz_id UUID;
BEGIN
  -- Find my business
  SELECT bo.business_id INTO v_biz_id
    FROM business_owners bo
   WHERE bo.auth_user_id = auth.uid()
   LIMIT 1;
  IF v_biz_id IS NULL THEN
    RAISE EXCEPTION 'No business associated with current user';
  END IF;

  -- Find target rec and confirm I am the RECIPIENT (not the recommender)
  SELECT recommended_business_id INTO v_target_biz_id
    FROM business_recommendations
   WHERE id = p_id;
  IF v_target_biz_id IS NULL THEN
    RAISE EXCEPTION 'Recommendation not found';
  END IF;
  IF v_target_biz_id <> v_biz_id THEN
    RAISE EXCEPTION 'You can only hide recommendations directed at your own business';
  END IF;

  UPDATE business_recommendations
     SET recipient_hidden = p_hidden,
         updated_at = NOW()
   WHERE id = p_id;
END $$;

GRANT EXECUTE ON FUNCTION set_incoming_recommendation_hidden(UUID, BOOLEAN) TO authenticated;

NOTIFY pgrst, 'reload schema';

DO $$
BEGIN
  RAISE NOTICE '✓ db/131 — Reciprocal display + recipient control ready';
END $$;

COMMIT;
