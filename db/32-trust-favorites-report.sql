-- =====================================================
-- db/32-trust-favorites-report.sql
-- Phase 3 — Trust + UX bundle backend
-- =====================================================
-- 1. Auto-grant verified_photo when 3+ photos uploaded (trigger)
-- 2. business_favorites table + RPCs (customer can heart a shop)
-- 3. business_reports table (Report incorrect info)
-- =====================================================
BEGIN;

-- ---------- 1. Auto-grant verified_photo ----------
CREATE OR REPLACE FUNCTION auto_grant_photo_badge()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.photos IS NOT NULL
     AND array_length(NEW.photos, 1) >= 3
     AND COALESCE(NEW.verified_photo, FALSE) = FALSE THEN
    NEW.verified_photo := TRUE;
  END IF;
  -- If photos go below 1, revoke the photo badge (clean state)
  IF (NEW.photos IS NULL OR array_length(NEW.photos, 1) IS NULL)
     AND NEW.verified_photo = TRUE THEN
    NEW.verified_photo := FALSE;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_grant_photo_badge ON businesses;
CREATE TRIGGER trg_auto_grant_photo_badge
  BEFORE INSERT OR UPDATE OF photos ON businesses
  FOR EACH ROW
  EXECUTE FUNCTION auto_grant_photo_badge();

-- Back-fill: any existing shops with 3+ photos but missing badge
UPDATE businesses
   SET verified_photo = TRUE
 WHERE photos IS NOT NULL
   AND array_length(photos, 1) >= 3
   AND COALESCE(verified_photo, FALSE) = FALSE;


-- ---------- 2. Favorites table ----------
CREATE TABLE IF NOT EXISTS business_favorites (
  business_id  UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL,                       -- auth.users.id (no FK to avoid cross-schema)
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (business_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_favs_user ON business_favorites(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_favs_biz  ON business_favorites(business_id);

ALTER TABLE business_favorites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "favs_read_own"   ON business_favorites;
DROP POLICY IF EXISTS "favs_insert_own" ON business_favorites;
DROP POLICY IF EXISTS "favs_delete_own" ON business_favorites;

CREATE POLICY "favs_read_own"   ON business_favorites FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "favs_insert_own" ON business_favorites FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "favs_delete_own" ON business_favorites FOR DELETE TO authenticated USING (user_id = auth.uid());

DROP FUNCTION IF EXISTS toggle_favorite(UUID);
CREATE OR REPLACE FUNCTION toggle_favorite(p_business_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_exists BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'login required';
  END IF;
  SELECT EXISTS(SELECT 1 FROM business_favorites WHERE business_id = p_business_id AND user_id = auth.uid())
    INTO v_exists;
  IF v_exists THEN
    DELETE FROM business_favorites WHERE business_id = p_business_id AND user_id = auth.uid();
    RETURN FALSE;
  ELSE
    INSERT INTO business_favorites(business_id, user_id) VALUES (p_business_id, auth.uid());
    RETURN TRUE;
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION toggle_favorite(UUID) TO authenticated;

DROP FUNCTION IF EXISTS my_favorites();
CREATE OR REPLACE FUNCTION my_favorites()
RETURNS TABLE (
  business_id UUID, slug TEXT, name TEXT, photos TEXT[],
  rating_avg NUMERIC, rating_count INT, created_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT b.id, b.slug, b.name, b.photos, b.rating_avg, b.rating_count, f.created_at
  FROM business_favorites f
  JOIN businesses b ON b.id = f.business_id
  WHERE f.user_id = auth.uid()
    AND b.status = 'active'
  ORDER BY f.created_at DESC;
$$;
GRANT EXECUTE ON FUNCTION my_favorites() TO authenticated;


-- ---------- 3. Business reports (Report incorrect info) ----------
CREATE TABLE IF NOT EXISTS business_reports (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id  UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  reporter_id  UUID,                                   -- null = anonymous
  category     TEXT NOT NULL,                          -- 'wrong_phone'|'closed_permanently'|'wrong_address'|'fake_listing'|'other'
  details      TEXT,
  resolved_at  TIMESTAMPTZ,
  resolved_by  UUID,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_reports_biz  ON business_reports(business_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reports_open ON business_reports(created_at DESC) WHERE resolved_at IS NULL;

ALTER TABLE business_reports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "reports_insert_anon" ON business_reports;
DROP POLICY IF EXISTS "reports_read_own"    ON business_reports;
CREATE POLICY "reports_insert_anon" ON business_reports FOR INSERT TO anon, authenticated WITH CHECK (TRUE);
CREATE POLICY "reports_read_own"    ON business_reports FOR SELECT TO authenticated USING (reporter_id = auth.uid());

DROP FUNCTION IF EXISTS report_business(UUID, TEXT, TEXT);
CREATE OR REPLACE FUNCTION report_business(p_business_id UUID, p_category TEXT, p_details TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF p_category NOT IN ('wrong_phone','closed_permanently','wrong_address','fake_listing','other') THEN
    RAISE EXCEPTION 'invalid category';
  END IF;
  INSERT INTO business_reports(business_id, reporter_id, category, details)
    VALUES (p_business_id, auth.uid(), p_category, NULLIF(trim(COALESCE(p_details,'')), ''))
    RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION report_business(UUID, TEXT, TEXT) TO anon, authenticated;

COMMIT;

-- =====================================================
-- VERIFY:
--  -- Auto-photo badge: take any active shop and add 3 photos
--  UPDATE businesses SET photos = ARRAY['url1','url2','url3'] WHERE id = '<biz-uuid>';
--  SELECT verified_photo FROM businesses WHERE id = '<biz-uuid>';  -- TRUE
--
--  -- Favorites: as customer login →
--  SELECT toggle_favorite('<biz-uuid>');     -- true (added)
--  SELECT toggle_favorite('<biz-uuid>');     -- false (removed)
--  SELECT * FROM my_favorites();
--
--  -- Report:
--  SELECT report_business('<biz-uuid>', 'wrong_phone', 'Number out of service');
-- =====================================================
