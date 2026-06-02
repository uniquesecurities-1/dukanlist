-- =====================================================
-- db/95-owner-notifications.sql
-- =====================================================
-- USER REQUEST (2026-06-02):
--   "Shopkeeper Notifications Center — bell icon + dropdown
--    showing actionable notifications (new lead, review reply,
--    photo missing, verification, featured expiring etc.)"
--
-- WHAT THIS DOES:
--   Adds a single RPC get_owner_notifications() that returns a
--   JSONB array of notifications for the logged-in shopkeeper's
--   linked business. Each notification:
--     {
--       "key":      "review_unreplied"   -- stable identifier
--       "title":    "1 review waiting for your reply",
--       "subtitle": "Reply within 24h to build trust",
--       "icon":     "💬",
--       "tone":     "info" | "warn" | "urgent" | "success",
--       "href":     "/panel/reviews.html",
--       "count":    1,
--       "created_at": ISO timestamp
--     }
--
-- SIGNALS COLLECTED (all best-effort, exception-safe):
--   1. EMAIL UNVERIFIED   — auth.users.email_confirmed_at NULL
--   2. UNANSWERED REVIEWS — reviews without owner_reply
--   3. PHOTO MISSING      — businesses.photos array empty / <3
--   4. FEATURED EXPIRING  — featured_until within next 7 days
--   5. PROFILE INCOMPLETE — missing key fields (about, hours, payment)
--   6. NEW LEADS (24h)    — leads_log recent count
--   7. VERIFICATION REQUESTED but pending — informational
--   8. APPROVED + VERIFIED — celebratory (one-time, dismiss via FE localStorage)
--
-- BACKWARDS COMPATIBLE — purely additive.
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

DROP FUNCTION IF EXISTS get_owner_notifications();

CREATE OR REPLACE FUNCTION get_owner_notifications()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_uid          UUID := auth.uid();
  v_biz_id       UUID;
  v_biz          RECORD;
  v_email_conf   TIMESTAMPTZ;
  v_notifs       JSONB := '[]'::JSONB;
  v_count        INT;
  -- counts
  v_rev_unreplied INT := 0;
  v_photo_n       INT := 0;
  v_leads_24h     INT := 0;
  v_featured_days INT := 999;
BEGIN
  IF v_uid IS NULL THEN
    RETURN '[]'::JSONB;
  END IF;

  -- Resolve linked business (single owner per user)
  SELECT b.* INTO v_biz
  FROM business_owners bo
  JOIN businesses b ON b.id = bo.business_id
  WHERE bo.auth_user_id = v_uid
  ORDER BY b.created_at ASC
  LIMIT 1;

  IF v_biz.id IS NULL THEN
    -- No business linked — only email-verify notif if applicable
    SELECT email_confirmed_at INTO v_email_conf FROM auth.users WHERE id = v_uid;
    IF v_email_conf IS NULL THEN
      v_notifs := v_notifs || jsonb_build_array(jsonb_build_object(
        'key',      'email_unverified',
        'title',    'Confirm your email',
        'subtitle', 'Click the link we sent to activate your account',
        'icon',     '📧',
        'tone',     'urgent',
        'href',     '/panel/resend-verification.html',
        'count',    1,
        'created_at', NOW()
      ));
    END IF;
    RETURN v_notifs;
  END IF;

  -- ============ Signal 1: Email unverified ============
  SELECT email_confirmed_at INTO v_email_conf FROM auth.users WHERE id = v_uid;
  IF v_email_conf IS NULL THEN
    v_notifs := v_notifs || jsonb_build_array(jsonb_build_object(
      'key',      'email_unverified',
      'title',    'Email not verified',
      'subtitle', 'Verify to unlock all features',
      'icon',     '📧',
      'tone',     'urgent',
      'href',     '/panel/resend-verification.html',
      'count',    1,
      'created_at', NOW()
    ));
  END IF;

  -- ============ Signal 2: Unanswered reviews ============
  BEGIN
    SELECT COUNT(*) INTO v_rev_unreplied
    FROM reviews
    WHERE business_id = v_biz.id
      AND (owner_reply IS NULL OR length(trim(owner_reply)) = 0)
      AND created_at >= NOW() - INTERVAL '60 days';
    IF v_rev_unreplied > 0 THEN
      v_notifs := v_notifs || jsonb_build_array(jsonb_build_object(
        'key',      'reviews_unreplied',
        'title',    v_rev_unreplied || ' review' || CASE WHEN v_rev_unreplied = 1 THEN '' ELSE 's' END || ' waiting for reply',
        'subtitle', 'Reply builds customer trust',
        'icon',     '💬',
        'tone',     'info',
        'href',     '/panel/reviews.html',
        'count',    v_rev_unreplied,
        'created_at', NOW()
      ));
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- ============ Signal 3: Photo missing / too few ============
  BEGIN
    v_photo_n := COALESCE(array_length(v_biz.photos, 1), 0);
    IF v_photo_n = 0 THEN
      v_notifs := v_notifs || jsonb_build_array(jsonb_build_object(
        'key',      'photos_missing',
        'title',    'No shop photos yet',
        'subtitle', 'Shops with photos get 4x more visits',
        'icon',     '📷',
        'tone',     'warn',
        'href',     '/panel/photos.html',
        'count',    1,
        'created_at', NOW()
      ));
    ELSIF v_photo_n < 3 THEN
      v_notifs := v_notifs || jsonb_build_array(jsonb_build_object(
        'key',      'photos_few',
        'title',    'Add more photos (only ' || v_photo_n || ' so far)',
        'subtitle', 'Aim for 5+ photos for best visibility',
        'icon',     '📸',
        'tone',     'info',
        'href',     '/panel/photos.html',
        'count',    1,
        'created_at', NOW()
      ));
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- ============ Signal 4: Featured expiring soon ============
  BEGIN
    IF v_biz.featured = TRUE AND v_biz.featured_until IS NOT NULL THEN
      v_featured_days := EXTRACT(DAY FROM (v_biz.featured_until - NOW()))::INT;
      IF v_featured_days BETWEEN 0 AND 7 THEN
        v_notifs := v_notifs || jsonb_build_array(jsonb_build_object(
          'key',      'featured_expiring',
          'title',    'Featured ends in ' || v_featured_days || ' day' || CASE WHEN v_featured_days = 1 THEN '' ELSE 's' END,
          'subtitle', 'Contact admin to renew',
          'icon',     '⭐',
          'tone',     'warn',
          'href',     '/panel/dashboard.html',
          'count',    1,
          'created_at', NOW()
        ));
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- ============ Signal 5: New leads (last 24h) ============
  BEGIN
    SELECT COUNT(*) INTO v_leads_24h
    FROM leads_log
    WHERE business_id = v_biz.id
      AND created_at >= NOW() - INTERVAL '24 hours';
    IF v_leads_24h > 0 THEN
      v_notifs := v_notifs || jsonb_build_array(jsonb_build_object(
        'key',      'leads_24h',
        'title',    v_leads_24h || ' new lead' || CASE WHEN v_leads_24h = 1 THEN '' ELSE 's' END || ' in last 24h',
        'subtitle', 'See who called / WhatsApp''d you',
        'icon',     '📞',
        'tone',     'success',
        'href',     '/panel/analytics.html',
        'count',    v_leads_24h,
        'created_at', NOW()
      ));
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- ============ Signal 6: Profile incomplete (missing key fields) ============
  BEGIN
    IF v_biz.status = 'active' AND (
      (v_biz.about IS NULL OR length(trim(v_biz.about)) < 30)
      OR (v_biz.hours_json IS NULL)
      OR (v_biz.payment_methods IS NULL OR array_length(v_biz.payment_methods, 1) IS NULL)
    ) THEN
      v_notifs := v_notifs || jsonb_build_array(jsonb_build_object(
        'key',      'profile_incomplete',
        'title',    'Complete your profile',
        'subtitle', 'About, hours & payment methods boost ranking',
        'icon',     '📝',
        'tone',     'info',
        'href',     '/panel/profile.html',
        'count',    1,
        'created_at', NOW()
      ));
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- ============ Signal 7: Verification requested but pending ============
  BEGIN
    IF v_biz.verification_requested_at IS NOT NULL
       AND COALESCE(v_biz.verified_score, 0) < 5 THEN
      v_notifs := v_notifs || jsonb_build_array(jsonb_build_object(
        'key',      'verification_pending',
        'title',    'Verification requested',
        'subtitle', 'Admin will review your shop shortly',
        'icon',     '⏳',
        'tone',     'info',
        'href',     '/panel/dashboard.html',
        'count',    1,
        'created_at', v_biz.verification_requested_at
      ));
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- ============ Signal 8: Approved + verified (celebratory) ============
  BEGIN
    IF v_biz.status = 'active' AND COALESCE(v_biz.verified_score, 0) >= 5 THEN
      v_notifs := v_notifs || jsonb_build_array(jsonb_build_object(
        'key',      'shop_verified',
        'title',    'Your shop is verified! 🎉',
        'subtitle', 'Verified shops rank higher in search',
        'icon',     '✅',
        'tone',     'success',
        'href',     '/panel/dashboard.html',
        'count',    1,
        'created_at', NOW()
      ));
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN v_notifs;
END;
$$;

GRANT EXECUTE ON FUNCTION get_owner_notifications() TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'db/95 installed.';
  RAISE NOTICE '  RPC: get_owner_notifications() returns JSONB array of actionable notifications';
  RAISE NOTICE '  Test: SELECT get_owner_notifications();  -- as authenticated user';
END $$;
