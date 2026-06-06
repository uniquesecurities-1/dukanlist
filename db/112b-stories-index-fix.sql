-- =====================================================
-- db/112b-stories-index-fix.sql
-- =====================================================
-- HOTFIX for db/112-shop-stories.sql
--
-- THREE BUGS FIXED:
--   1. CREATE INDEX with `WHERE expires_at > NOW()` — failed
--      because NOW() is STABLE, not IMMUTABLE.
--      FIX: Remove WHERE clause; index covers all rows.
--   2. business_owners.user_id used — actual column is
--      auth_user_id. RLS policy and 2 RPC SELECT clauses
--      affected.
--      FIX: Replace user_id with auth_user_id.
--   3. DROP POLICY/INDEX order — previous hotfix dropped
--      objects BEFORE creating the table, failing on fresh
--      installs.
--      FIX: Create table FIRST, then drop existing objects,
--      then re-create cleanly.
--
-- This file is IDEMPOTENT and safe on fresh OR partial state.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. Table FIRST (so DROP POLICY can find it)
-- ============================================================
CREATE TABLE IF NOT EXISTS shop_stories (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id   UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  text          TEXT NOT NULL,
  image_url     TEXT,
  accent_color  TEXT,
  bg_style      TEXT NOT NULL DEFAULT 'gradient-1',
  view_count    INT  NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at    TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
  CONSTRAINT story_text_len CHECK (length(text) BETWEEN 1 AND 280)
);

-- ============================================================
-- 2. Drop legacy objects (table exists now, so safe)
-- ============================================================
DROP INDEX IF EXISTS idx_stories_biz_active;
DROP INDEX IF EXISTS idx_stories_recent;

DROP POLICY IF EXISTS shop_stories_public_read ON shop_stories;
DROP POLICY IF EXISTS shop_stories_owner_write ON shop_stories;

DROP FUNCTION IF EXISTS create_shop_story(TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS delete_my_story(UUID);
DROP FUNCTION IF EXISTS get_shop_active_stories(UUID);
DROP FUNCTION IF EXISTS get_stories_from_my_favorites(INT);
DROP FUNCTION IF EXISTS get_homepage_buzz(TEXT, INT);
DROP FUNCTION IF EXISTS cleanup_expired_stories();
DROP FUNCTION IF EXISTS story_inc_view(UUID);

-- ============================================================
-- 3. Indexes WITHOUT partial WHERE NOW() — query filter handles it
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_stories_biz_active
  ON shop_stories (business_id, expires_at DESC);
CREATE INDEX IF NOT EXISTS idx_stories_recent
  ON shop_stories (expires_at DESC, created_at DESC);

-- ============================================================
-- 4. RLS — uses auth_user_id (corrected)
-- ============================================================
ALTER TABLE shop_stories ENABLE ROW LEVEL SECURITY;

CREATE POLICY shop_stories_public_read ON shop_stories
  FOR SELECT USING (expires_at > NOW());

CREATE POLICY shop_stories_owner_write ON shop_stories
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM business_owners
      WHERE business_id = shop_stories.business_id
        AND auth_user_id = auth.uid()
    )
  );

-- ============================================================
-- 5. RPCs
-- ============================================================
CREATE OR REPLACE FUNCTION create_shop_story(
  p_text         TEXT,
  p_image_url    TEXT DEFAULT NULL,
  p_bg_style     TEXT DEFAULT 'gradient-1',
  p_accent_color TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_user_id      UUID;
  v_business_id  UUID;
  v_story_id     UUID;
  v_active_count INT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

  SELECT business_id INTO v_business_id
  FROM business_owners
  WHERE auth_user_id = v_user_id
  LIMIT 1;

  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'No business linked to your account';
  END IF;

  IF length(trim(COALESCE(p_text, ''))) = 0 THEN
    RAISE EXCEPTION 'Story text cannot be empty';
  END IF;
  IF length(p_text) > 280 THEN
    RAISE EXCEPTION 'Story text too long (max 280 chars)';
  END IF;

  SELECT COUNT(*) INTO v_active_count
  FROM shop_stories
  WHERE business_id = v_business_id AND expires_at > NOW();

  IF v_active_count >= 3 THEN
    RAISE EXCEPTION 'Max 3 active stories. Delete an old one first.';
  END IF;

  IF p_bg_style NOT IN ('gradient-1','gradient-2','gradient-3','gradient-4','gradient-5','gradient-6','photo') THEN
    p_bg_style := 'gradient-1';
  END IF;

  INSERT INTO shop_stories (business_id, text, image_url, bg_style, accent_color)
  VALUES (v_business_id, trim(p_text), p_image_url, p_bg_style,
          NULLIF(trim(COALESCE(p_accent_color, '')), ''))
  RETURNING id INTO v_story_id;

  RETURN jsonb_build_object(
    'story_id', v_story_id,
    'business_id', v_business_id,
    'expires_at', NOW() + INTERVAL '24 hours',
    'success', true
  );
END;
$$;
GRANT EXECUTE ON FUNCTION create_shop_story(TEXT, TEXT, TEXT, TEXT) TO authenticated;


CREATE OR REPLACE FUNCTION delete_my_story(p_story_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_user_id    UUID;
  v_story_biz  UUID;
  v_is_owner   BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

  SELECT business_id INTO v_story_biz FROM shop_stories WHERE id = p_story_id;
  IF v_story_biz IS NULL THEN RETURN FALSE; END IF;

  SELECT EXISTS (
    SELECT 1 FROM business_owners
    WHERE business_id = v_story_biz AND auth_user_id = v_user_id
  ) INTO v_is_owner;

  IF NOT v_is_owner THEN RAISE EXCEPTION 'Not authorized'; END IF;

  DELETE FROM shop_stories WHERE id = p_story_id;
  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION delete_my_story(UUID) TO authenticated;


CREATE OR REPLACE FUNCTION get_shop_active_stories(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE
AS $$
DECLARE v_items JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id',           s.id,
    'text',         s.text,
    'image_url',    s.image_url,
    'bg_style',     s.bg_style,
    'accent_color', s.accent_color,
    'view_count',   s.view_count,
    'created_at',   s.created_at,
    'expires_at',   s.expires_at,
    'hours_left',   EXTRACT(EPOCH FROM (s.expires_at - NOW())) / 3600
  ) ORDER BY s.created_at DESC), '[]'::jsonb)
  INTO v_items
  FROM shop_stories s
  WHERE s.business_id = p_business_id AND s.expires_at > NOW();
  RETURN v_items;
END;
$$;
GRANT EXECUTE ON FUNCTION get_shop_active_stories(UUID) TO authenticated, anon;


CREATE OR REPLACE FUNCTION get_stories_from_my_favorites(p_limit INT DEFAULT 20)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE
AS $$
DECLARE v_user_id UUID; v_items JSONB;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN '[]'::jsonb; END IF;
  IF p_limit < 1 OR p_limit > 100 THEN p_limit := 20; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', s.id, 'business_id', s.business_id, 'shop_name', b.name,
    'shop_slug', b.slug, 'shop_photo', b.photos[1],
    'text', s.text, 'image_url', s.image_url, 'bg_style', s.bg_style,
    'accent_color', s.accent_color,
    'created_at', s.created_at, 'expires_at', s.expires_at
  ) ORDER BY s.created_at DESC), '[]'::jsonb)
  INTO v_items
  FROM shop_stories s
  JOIN businesses b ON b.id = s.business_id
  WHERE s.expires_at > NOW()
    AND s.business_id IN (SELECT business_id FROM business_favorites WHERE user_id = v_user_id)
  LIMIT p_limit;
  RETURN v_items;
END;
$$;
GRANT EXECUTE ON FUNCTION get_stories_from_my_favorites(INT) TO authenticated;


CREATE OR REPLACE FUNCTION get_homepage_buzz(p_city_slug TEXT DEFAULT NULL, p_limit INT DEFAULT 12)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE
AS $$
DECLARE v_city_id UUID; v_items JSONB;
BEGIN
  IF p_limit < 1 OR p_limit > 50 THEN p_limit := 12; END IF;
  IF p_city_slug IS NOT NULL AND length(p_city_slug) > 0 THEN
    BEGIN SELECT id INTO v_city_id FROM geo_cities WHERE slug = p_city_slug LIMIT 1;
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', s.id, 'business_id', s.business_id, 'shop_name', b.name,
    'shop_slug', b.slug, 'shop_photo', b.photos[1],
    'text', s.text, 'image_url', s.image_url, 'bg_style', s.bg_style,
    'accent_color', s.accent_color, 'created_at', s.created_at,
    'hours_left', EXTRACT(EPOCH FROM (s.expires_at - NOW())) / 3600
  ) ORDER BY s.created_at DESC), '[]'::jsonb)
  INTO v_items
  FROM shop_stories s
  JOIN businesses b ON b.id = s.business_id
  WHERE s.expires_at > NOW() AND b.status = 'active'
    AND (v_city_id IS NULL OR b.city_id = v_city_id)
  LIMIT p_limit;
  RETURN v_items;
END;
$$;
GRANT EXECUTE ON FUNCTION get_homepage_buzz(TEXT, INT) TO authenticated, anon;


CREATE OR REPLACE FUNCTION cleanup_expired_stories()
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_deleted INT;
BEGIN
  WITH del AS (DELETE FROM shop_stories WHERE expires_at < NOW() - INTERVAL '1 day' RETURNING 1)
  SELECT COUNT(*) INTO v_deleted FROM del;
  RETURN v_deleted;
END;
$$;
GRANT EXECUTE ON FUNCTION cleanup_expired_stories() TO authenticated;


CREATE OR REPLACE FUNCTION story_inc_view(p_story_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  UPDATE shop_stories SET view_count = view_count + 1
  WHERE id = p_story_id AND expires_at > NOW();
  RETURN FOUND;
END;
$$;
GRANT EXECUTE ON FUNCTION story_inc_view(UUID) TO authenticated, anon;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'db/112b hotfix complete — full Daily Buzz install.';
  RAISE NOTICE '  Fixed: NOW() in partial index predicate';
  RAISE NOTICE '  Fixed: business_owners.user_id -> auth_user_id';
  RAISE NOTICE '  Fixed: DROP/CREATE order (table-first)';
  RAISE NOTICE '';
  RAISE NOTICE 'Installed: shop_stories table + 7 RPCs + 2 RLS policies';
  RAISE NOTICE 'Safe to run on fresh or partial state.';
END $$;
