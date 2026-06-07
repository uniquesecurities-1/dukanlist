-- =====================================================
-- db/119-shop-likes.sql
-- =====================================================
-- VIRAL FEATURE (2026-06-07):
--   Add ❤️ Love button to Discover (TikTok-style) feed.
--   Shopkeepers share their shop link, get more loves → social proof.
--   Loves visible publicly = competitive incentive to share.
--
-- TABLE   shop_likes  — dedup per session (1 like per session per shop)
-- COLUMN  businesses.likes_count — denormalised running total
-- RPC     bump_shop_like(p_business_id, p_session_id) — insert + bump count
-- RPC     get_shop_likes(p_business_id) — return count
--
-- DEPLOY:
--   Supabase Dashboard → SQL Editor → paste + Run
-- =====================================================

BEGIN;

-- 1. Add denormalised column to businesses
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS likes_count INT NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_businesses_likes_count
  ON businesses(likes_count DESC) WHERE likes_count > 0;

-- 2. Dedup table — one like per session per shop
CREATE TABLE IF NOT EXISTS shop_likes (
  business_id   UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  session_id    TEXT NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (business_id, session_id)
);

CREATE INDEX IF NOT EXISTS idx_shop_likes_business
  ON shop_likes(business_id);

-- RLS — anon can INSERT (anti-spam via PRIMARY KEY), nobody reads
ALTER TABLE shop_likes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS shop_likes_anon_insert ON shop_likes;
CREATE POLICY shop_likes_anon_insert ON shop_likes
  FOR INSERT TO anon, authenticated
  WITH CHECK (true);

-- 3. RPC — bump like (handles dedup atomically)
DROP FUNCTION IF EXISTS bump_shop_like(UUID, TEXT);

CREATE OR REPLACE FUNCTION bump_shop_like(
  p_business_id UUID,
  p_session_id  TEXT
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted BOOLEAN := FALSE;
  v_count    INT;
BEGIN
  -- Validate session id (anti-spam — reject empty / very short)
  IF p_session_id IS NULL OR LENGTH(p_session_id) < 8 THEN
    RAISE EXCEPTION 'Invalid session';
  END IF;

  -- Validate business exists + is active
  IF NOT EXISTS (
    SELECT 1 FROM businesses WHERE id = p_business_id AND status::TEXT = 'active'
  ) THEN
    RAISE EXCEPTION 'Shop not found or not active';
  END IF;

  -- Try insert — dedup via PK
  BEGIN
    INSERT INTO shop_likes (business_id, session_id)
    VALUES (p_business_id, p_session_id);
    v_inserted := TRUE;
  EXCEPTION WHEN unique_violation THEN
    v_inserted := FALSE;
  END;

  -- If new like, bump denorm count
  IF v_inserted THEN
    UPDATE businesses
      SET likes_count = likes_count + 1
      WHERE id = p_business_id
      RETURNING likes_count INTO v_count;
  ELSE
    SELECT likes_count INTO v_count FROM businesses WHERE id = p_business_id;
  END IF;

  RETURN COALESCE(v_count, 0);
END $$;

GRANT EXECUTE ON FUNCTION bump_shop_like(UUID, TEXT) TO anon, authenticated;

-- 4. Read RPC (optional — likes_count is also on businesses table)
DROP FUNCTION IF EXISTS get_shop_likes(UUID);

CREATE OR REPLACE FUNCTION get_shop_likes(p_business_id UUID)
RETURNS INT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(likes_count, 0) FROM businesses WHERE id = p_business_id;
$$;

GRANT EXECUTE ON FUNCTION get_shop_likes(UUID) TO anon, authenticated;

COMMIT;
