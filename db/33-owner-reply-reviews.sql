-- =====================================================
-- db/33-owner-reply-reviews.sql
-- Owner can reply to reviews on their own shop.
-- =====================================================
-- Schema already has reviews.owner_reply + owner_reply_at columns (db/01).
-- This file adds:
--   1. RPC owner_reply_to_review(review_id, reply_text)
--      Verifies caller owns the business via business_owners table.
--   2. Allow UPDATE of owner_reply for owners (via RLS or RPC).
--   3. Notification to customer (optional — skipped for now).
-- =====================================================
BEGIN;

DROP FUNCTION IF EXISTS owner_reply_to_review(UUID, TEXT);

CREATE OR REPLACE FUNCTION owner_reply_to_review(
  p_review_id UUID,
  p_reply_text TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_business_id UUID;
  v_is_owner    BOOLEAN;
  v_caller      UUID;
  v_clean       TEXT;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'login required';
  END IF;

  -- Find the review's business
  SELECT business_id INTO v_business_id
    FROM reviews
    WHERE id = p_review_id
      AND status = 'active'
    LIMIT 1;

  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'review not found';
  END IF;

  -- Verify caller is owner of that business
  SELECT EXISTS (
    SELECT 1 FROM business_owners
      WHERE business_id = v_business_id
        AND auth_user_id = v_caller
  ) INTO v_is_owner;

  IF NOT v_is_owner THEN
    RAISE EXCEPTION 'only shop owner can reply';
  END IF;

  -- Clean reply: trim, NULL out blank, cap length
  v_clean := NULLIF(trim(COALESCE(p_reply_text, '')), '');
  IF v_clean IS NOT NULL AND length(v_clean) > 600 THEN
    v_clean := substring(v_clean from 1 for 600);
  END IF;

  UPDATE reviews
     SET owner_reply    = v_clean,
         owner_reply_at = CASE WHEN v_clean IS NULL THEN NULL ELSE NOW() END
   WHERE id = p_review_id;

  RETURN jsonb_build_object('ok', TRUE, 'review_id', p_review_id, 'cleared', v_clean IS NULL);
END;
$$;

GRANT EXECUTE ON FUNCTION owner_reply_to_review(UUID, TEXT) TO authenticated;

-- ---------- RPC for shopkeeper to list own reviews ----------
DROP FUNCTION IF EXISTS my_shop_reviews(INT);

CREATE OR REPLACE FUNCTION my_shop_reviews(p_limit INT DEFAULT 50)
RETURNS TABLE (
  id              UUID,
  business_id     UUID,
  customer_name   TEXT,
  rating          SMALLINT,
  text            TEXT,
  photos          TEXT[],
  owner_reply     TEXT,
  owner_reply_at  TIMESTAMPTZ,
  helpful_count   INT,
  created_at      TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT r.id, r.business_id, r.customer_name, r.rating, r.text, r.photos,
         r.owner_reply, r.owner_reply_at, r.helpful_count, r.created_at
  FROM reviews r
  WHERE r.status = 'active'
    AND r.business_id IN (
      SELECT business_id FROM business_owners WHERE auth_user_id = auth.uid()
    )
  ORDER BY (r.owner_reply IS NULL) DESC, r.created_at DESC
  LIMIT GREATEST(1, LEAST(p_limit, 200));
$$;

GRANT EXECUTE ON FUNCTION my_shop_reviews(INT) TO authenticated;

COMMIT;
