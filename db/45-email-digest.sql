-- db/45-email-digest.sql
-- Weekly Email Digest infrastructure
--
-- Adds:
--   1. businesses.email_digest_enabled column (default TRUE — opt-out model)
--   2. owner_digest_data(business_id) — generates per-shop weekly summary
--   3. list_active_owners_for_digest() — admin-only, returns owners to email
--
-- Run AFTER db/01-44.

BEGIN;

-- 1. Opt-out column on businesses (default opted-in)
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS email_digest_enabled BOOLEAN DEFAULT TRUE NOT NULL;
CREATE INDEX IF NOT EXISTS idx_biz_digest_enabled
  ON businesses(email_digest_enabled)
  WHERE email_digest_enabled = TRUE;

-- 2. owner_digest_data — per-shop weekly summary used by /api/send-digest
DROP FUNCTION IF EXISTS owner_digest_data(UUID);
CREATE OR REPLACE FUNCTION owner_digest_data(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE
AS $$
DECLARE
  v_biz             RECORD;
  v_w1_views        INT;
  v_w1_leads        INT;
  v_w2_views        INT;
  v_w2_leads        INT;
  v_new_reviews     INT;
  v_avg_rating      NUMERIC;
  v_total_reviews   INT;
  v_recent_reviews  JSONB;
  v_photo_count     INT;
  v_actions         JSONB;
BEGIN
  -- Pull base business info
  SELECT id, slug, name, mobile, status, verified_score, is_featured,
         usp_text, about_text, hours_json, established_year,
         COALESCE(array_length(photos, 1), 0) AS photo_count,
         rating_avg, rating_count
    INTO v_biz
    FROM businesses
   WHERE id = p_business_id;

  IF NOT FOUND THEN RETURN NULL; END IF;

  -- This week (last 7 days)
  SELECT
    COUNT(*) FILTER (WHERE action = 'view'),
    COUNT(*) FILTER (WHERE action IN ('call','whatsapp','direction'))
  INTO v_w1_views, v_w1_leads
  FROM leads_log
  WHERE business_id = p_business_id
    AND created_at >= NOW() - INTERVAL '7 days';

  -- Previous week (8-14 days ago)
  SELECT
    COUNT(*) FILTER (WHERE action = 'view'),
    COUNT(*) FILTER (WHERE action IN ('call','whatsapp','direction'))
  INTO v_w2_views, v_w2_leads
  FROM leads_log
  WHERE business_id = p_business_id
    AND created_at >= NOW() - INTERVAL '14 days'
    AND created_at <  NOW() - INTERVAL '7 days';

  -- New reviews this week (count + 3 most recent)
  SELECT COUNT(*) INTO v_new_reviews
  FROM reviews WHERE business_id = p_business_id AND created_at >= NOW() - INTERVAL '7 days';

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'rating', rating,
           'text', text,
           'customer_name', customer_name,
           'created_at', created_at
         ) ORDER BY created_at DESC), '[]'::JSONB)
    INTO v_recent_reviews
    FROM (
      SELECT rating, text, customer_name, created_at
        FROM reviews
       WHERE business_id = p_business_id AND created_at >= NOW() - INTERVAL '7 days'
       ORDER BY created_at DESC
       LIMIT 3
    ) r;

  -- Suggested actions — computed server-side, top 2
  WITH cands AS (
    SELECT 1 AS prio, 'add_photos' AS code,
           ('Add ' || (3 - v_biz.photo_count) || ' more photos to reach 3+ total') AS msg,
           '/panel/photos.html' AS link
     WHERE v_biz.photo_count < 3
    UNION ALL
    SELECT 2, 'write_usp', 'Write a one-line USP to stand out in search results',
           '/panel/profile.html#usp'
     WHERE v_biz.usp_text IS NULL OR length(v_biz.usp_text) < 10
    UNION ALL
    SELECT 3, 'write_about', 'Write an About section (customers love shop stories)',
           '/panel/profile.html#about'
     WHERE v_biz.about_text IS NULL OR length(v_biz.about_text) < 50
    UNION ALL
    SELECT 4, 'set_hours', 'Set your business hours so customers see Open/Closed',
           '/panel/profile.html#hours'
     WHERE v_biz.hours_json IS NULL OR jsonb_typeof(v_biz.hours_json) <> 'object' OR v_biz.hours_json = '{}'::JSONB
    UNION ALL
    SELECT 5, 'add_year', 'Add your established year to unlock Gold Trusted tier',
           '/panel/profile.html'
     WHERE v_biz.established_year IS NULL
    UNION ALL
    SELECT 6, 'reply_reviews', 'Reply to your recent reviews — owner replies build trust',
           '/panel/reviews.html'
     WHERE v_new_reviews > 0
    UNION ALL
    SELECT 7, 'post_deal', 'Post a weekly deal/offer to attract new customers',
           '/panel/deals.html'
     WHERE v_w1_leads < 3
  )
  SELECT jsonb_agg(jsonb_build_object('code', code, 'msg', msg, 'link', link))
    INTO v_actions
    FROM (SELECT * FROM cands ORDER BY prio LIMIT 2) t;

  RETURN jsonb_build_object(
    'business_id',        v_biz.id,
    'slug',               v_biz.slug,
    'name',               v_biz.name,
    'status',             v_biz.status,
    'photo_count',        v_biz.photo_count,
    'verified_score',     v_biz.verified_score,
    'rating_avg',         v_biz.rating_avg,
    'rating_count',       v_biz.rating_count,
    'this_week', jsonb_build_object(
      'views', COALESCE(v_w1_views, 0),
      'leads', COALESCE(v_w1_leads, 0)
    ),
    'last_week', jsonb_build_object(
      'views', COALESCE(v_w2_views, 0),
      'leads', COALESCE(v_w2_leads, 0)
    ),
    'new_reviews',        COALESCE(v_new_reviews, 0),
    'recent_reviews',     v_recent_reviews,
    'actions',            COALESCE(v_actions, '[]'::JSONB)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION owner_digest_data(UUID) TO authenticated, service_role;

-- 3. list_active_owners_for_digest — used by cron to iterate
-- Returns rows of (business_id, owner_email, owner_name, shop_name)
-- Only includes:
--   - live businesses
--   - email_digest_enabled = TRUE
--   - at least one owner with a valid auth.users email
DROP FUNCTION IF EXISTS list_active_owners_for_digest();
CREATE OR REPLACE FUNCTION list_active_owners_for_digest()
RETURNS TABLE (
  business_id   UUID,
  shop_name     TEXT,
  shop_slug     TEXT,
  owner_email   TEXT,
  owner_id      UUID
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE
AS $$
BEGIN
  -- service_role bypasses RLS; for safety we also allow super_admin
  IF current_setting('role') <> 'service_role'
     AND NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'is_super_admin')
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'forbidden: service_role or admin only';
  END IF;

  RETURN QUERY
  SELECT b.id, b.name, b.slug, au.email, bo.auth_user_id
    FROM businesses b
    JOIN business_owners bo ON bo.business_id = b.id
    JOIN auth.users au ON au.id = bo.auth_user_id
   WHERE b.status = 'live'
     AND b.email_digest_enabled = TRUE
     AND au.email IS NOT NULL
     AND au.email <> ''
   ORDER BY b.id;
END;
$$;

GRANT EXECUTE ON FUNCTION list_active_owners_for_digest() TO service_role;

-- 4. Owner self-service: toggle digest preference from panel
DROP FUNCTION IF EXISTS toggle_my_email_digest(UUID, BOOLEAN);
CREATE OR REPLACE FUNCTION toggle_my_email_digest(p_business_id UUID, p_enabled BOOLEAN)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM business_owners
     WHERE business_id = p_business_id AND auth_user_id = auth.uid()
  ) THEN RAISE EXCEPTION 'not your business'; END IF;

  UPDATE businesses SET email_digest_enabled = p_enabled WHERE id = p_business_id;
  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION toggle_my_email_digest(UUID, BOOLEAN) TO authenticated;

COMMIT;
