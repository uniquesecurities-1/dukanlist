-- =====================================================
-- db/119c-toggle-shop-like.sql
-- =====================================================
-- UPGRADE (2026-06-07):
--   Allow users to UN-like a shop by tapping the 🔥 button again.
--   Returns both the new count AND the current liked state.
--
-- DEPLOY:
--   Supabase Dashboard → SQL Editor → paste + Run
-- =====================================================

BEGIN;

DROP FUNCTION IF EXISTS toggle_shop_like(UUID, TEXT);

CREATE OR REPLACE FUNCTION toggle_shop_like(
  p_business_id UUID,
  p_session_id  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists BOOLEAN;
  v_count  INT;
  v_liked  BOOLEAN;
BEGIN
  IF p_session_id IS NULL OR LENGTH(p_session_id) < 8 THEN
    RAISE EXCEPTION 'Invalid session';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM businesses
    WHERE id = p_business_id AND status::TEXT = 'active'
  ) THEN
    RAISE EXCEPTION 'Shop not found or not active';
  END IF;

  -- Already liked from this session?
  SELECT EXISTS (
    SELECT 1 FROM shop_likes
    WHERE business_id = p_business_id AND session_id = p_session_id
  ) INTO v_exists;

  IF v_exists THEN
    -- UNLIKE
    DELETE FROM shop_likes
      WHERE business_id = p_business_id AND session_id = p_session_id;
    UPDATE businesses
      SET likes_count = GREATEST(likes_count - 1, 0)
      WHERE id = p_business_id
      RETURNING likes_count INTO v_count;
    v_liked := FALSE;
  ELSE
    -- LIKE
    INSERT INTO shop_likes (business_id, session_id)
      VALUES (p_business_id, p_session_id);
    UPDATE businesses
      SET likes_count = likes_count + 1
      WHERE id = p_business_id
      RETURNING likes_count INTO v_count;
    v_liked := TRUE;
  END IF;

  RETURN jsonb_build_object(
    'liked', v_liked,
    'count', COALESCE(v_count, 0)
  );
END $$;

GRANT EXECUTE ON FUNCTION toggle_shop_like(UUID, TEXT) TO anon, authenticated;

COMMIT;
