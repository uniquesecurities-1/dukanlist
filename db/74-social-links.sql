-- =====================================================
-- db/74-social-links.sql
-- =====================================================
-- USER REQUEST (2026-05-28):
--   "Shopkeeper ka social media details vagerah abhi hamne kahin bhi
--    nahi dikhayi hain.. unke liye bhi kuch acche provision hone chahiye."
--
-- WHAT THIS ADDS:
--   6 new TEXT columns on `businesses` for social / online presence:
--     facebook_url, instagram_url, youtube_url, x_twitter_url,
--     linkedin_url, website_url
--
--   1 owner-side RPC `update_my_social_links(p_links JSONB)` that the
--   shopkeeper panel calls — validates URLs, strips spaces, accepts
--   blank to clear. RLS-safe via SECURITY DEFINER + auth.uid() check.
--
--   1 admin-side RPC `admin_set_social_links(p_business_id, p_links)`
--   for admin/shop.html in future.
--
-- All inserts/updates are idempotent — safe to re-run.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. ADD COLUMNS
-- ============================================================
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS facebook_url    TEXT,
  ADD COLUMN IF NOT EXISTS instagram_url   TEXT,
  ADD COLUMN IF NOT EXISTS youtube_url     TEXT,
  ADD COLUMN IF NOT EXISTS x_twitter_url   TEXT,
  ADD COLUMN IF NOT EXISTS linkedin_url    TEXT,
  ADD COLUMN IF NOT EXISTS website_url     TEXT;

COMMENT ON COLUMN businesses.facebook_url   IS 'Shopkeeper public Facebook page URL';
COMMENT ON COLUMN businesses.instagram_url  IS 'Shopkeeper public Instagram profile URL';
COMMENT ON COLUMN businesses.youtube_url    IS 'Shopkeeper YouTube channel URL';
COMMENT ON COLUMN businesses.x_twitter_url  IS 'Shopkeeper X (Twitter) profile URL';
COMMENT ON COLUMN businesses.linkedin_url   IS 'Shopkeeper LinkedIn profile/company URL';
COMMENT ON COLUMN businesses.website_url    IS 'Shop / business own website URL';


-- ============================================================
-- 2. HELPER — light URL sanity check (must start with http(s)://)
-- ============================================================
CREATE OR REPLACE FUNCTION _sanitize_social_url(p_url TEXT)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  v TEXT;
BEGIN
  IF p_url IS NULL THEN RETURN NULL; END IF;
  v := trim(p_url);
  IF v = '' THEN RETURN NULL; END IF;
  -- Auto-prepend https:// if user just typed instagram.com/xyz
  IF v !~* '^https?://' THEN
    v := 'https://' || v;
  END IF;
  -- Basic shape check — reject anything > 300 chars or with whitespace inside
  IF length(v) > 300 OR v ~ '\s' THEN
    RAISE EXCEPTION 'Invalid URL: %', p_url;
  END IF;
  RETURN v;
END;
$$;


-- ============================================================
-- 3. OWNER RPC — update social links for shopkeeper's own business
-- Input JSONB keys (any subset):
--   facebook_url, instagram_url, youtube_url, x_twitter_url,
--   linkedin_url, website_url
-- Missing keys are left untouched. Pass empty string to clear.
-- ============================================================
DROP FUNCTION IF EXISTS update_my_social_links(JSONB);

CREATE OR REPLACE FUNCTION update_my_social_links(p_links JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id  UUID;
  v_biz_id   UUID;
  v_fb       TEXT;
  v_ig       TEXT;
  v_yt       TEXT;
  v_x        TEXT;
  v_li       TEXT;
  v_web      TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT business_id INTO v_biz_id
  FROM business_owners
  WHERE auth_user_id = v_user_id
  LIMIT 1;

  IF v_biz_id IS NULL THEN
    RAISE EXCEPTION 'No business linked to this account';
  END IF;

  IF p_links ? 'facebook_url' THEN
    v_fb := _sanitize_social_url(p_links->>'facebook_url');
    UPDATE businesses SET facebook_url = v_fb WHERE id = v_biz_id;
  END IF;
  IF p_links ? 'instagram_url' THEN
    v_ig := _sanitize_social_url(p_links->>'instagram_url');
    UPDATE businesses SET instagram_url = v_ig WHERE id = v_biz_id;
  END IF;
  IF p_links ? 'youtube_url' THEN
    v_yt := _sanitize_social_url(p_links->>'youtube_url');
    UPDATE businesses SET youtube_url = v_yt WHERE id = v_biz_id;
  END IF;
  IF p_links ? 'x_twitter_url' THEN
    v_x := _sanitize_social_url(p_links->>'x_twitter_url');
    UPDATE businesses SET x_twitter_url = v_x WHERE id = v_biz_id;
  END IF;
  IF p_links ? 'linkedin_url' THEN
    v_li := _sanitize_social_url(p_links->>'linkedin_url');
    UPDATE businesses SET linkedin_url = v_li WHERE id = v_biz_id;
  END IF;
  IF p_links ? 'website_url' THEN
    v_web := _sanitize_social_url(p_links->>'website_url');
    UPDATE businesses SET website_url = v_web WHERE id = v_biz_id;
  END IF;

  RETURN v_biz_id;
END;
$$;

GRANT EXECUTE ON FUNCTION update_my_social_links(JSONB) TO authenticated;


-- ============================================================
-- 4. ADMIN RPC — admin can edit any shop's social links
-- ============================================================
DROP FUNCTION IF EXISTS admin_set_social_links(UUID, JSONB);

CREATE OR REPLACE FUNCTION admin_set_social_links(p_business_id UUID, p_links JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;

  IF p_links ? 'facebook_url' THEN
    UPDATE businesses SET facebook_url = _sanitize_social_url(p_links->>'facebook_url')
      WHERE id = p_business_id;
  END IF;
  IF p_links ? 'instagram_url' THEN
    UPDATE businesses SET instagram_url = _sanitize_social_url(p_links->>'instagram_url')
      WHERE id = p_business_id;
  END IF;
  IF p_links ? 'youtube_url' THEN
    UPDATE businesses SET youtube_url = _sanitize_social_url(p_links->>'youtube_url')
      WHERE id = p_business_id;
  END IF;
  IF p_links ? 'x_twitter_url' THEN
    UPDATE businesses SET x_twitter_url = _sanitize_social_url(p_links->>'x_twitter_url')
      WHERE id = p_business_id;
  END IF;
  IF p_links ? 'linkedin_url' THEN
    UPDATE businesses SET linkedin_url = _sanitize_social_url(p_links->>'linkedin_url')
      WHERE id = p_business_id;
  END IF;
  IF p_links ? 'website_url' THEN
    UPDATE businesses SET website_url = _sanitize_social_url(p_links->>'website_url')
      WHERE id = p_business_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_set_social_links(UUID, JSONB) TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- VERIFY
-- =====================================================
DO $$
DECLARE
  v_cols INT;
  v_rpc1 INT;
  v_rpc2 INT;
BEGIN
  SELECT COUNT(*) INTO v_cols FROM information_schema.columns
    WHERE table_name = 'businesses' AND column_name IN
      ('facebook_url','instagram_url','youtube_url','x_twitter_url','linkedin_url','website_url');
  SELECT COUNT(*) INTO v_rpc1 FROM pg_proc WHERE proname = 'update_my_social_links';
  SELECT COUNT(*) INTO v_rpc2 FROM pg_proc WHERE proname = 'admin_set_social_links';

  RAISE NOTICE '✅ Social columns: % of 6', v_cols;
  RAISE NOTICE '✅ update_my_social_links RPC: % of 1', v_rpc1;
  RAISE NOTICE '✅ admin_set_social_links RPC:  % of 1', v_rpc2;
END $$;
