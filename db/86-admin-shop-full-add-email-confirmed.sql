-- =====================================================
-- db/86-admin-shop-full-add-email-confirmed.sql
-- =====================================================
-- USER FEEDBACK (2026-06-01):
--   "Jiski email already verified hai uspar to Force Verify dikha raha hai...
--    Jiski verified nahi hai, aur jaha iski jrurat hai waha dikha nahi raha."
--
-- FIX:
--   admin_get_shop_full() did NOT return whether the linked auth user has
--   confirmed their email. Without that info, the admin/shop.html UI has
--   no way to decide whether to show the "Force Verify Email" button.
--
--   This patch extends the RPC return JSONB with TWO new fields:
--     • owner_email_confirmed  BOOLEAN  — TRUE if email_confirmed_at IS NOT NULL
--     • owner_email_confirmed_at  TIMESTAMPTZ  — the actual timestamp (for display)
--
--   Frontend (admin/shop.html) then:
--     • Hides Force Verify button when owner_email_confirmed === TRUE
--     • Shows a "✓ Email verified" pill instead
--     • For shops with no auth account at all, shows a different empty-state card
--
-- IDEMPOTENT — safe to re-run. Preserves all existing return columns.
-- =====================================================

BEGIN;

DROP FUNCTION IF EXISTS admin_get_shop_full(UUID);

CREATE OR REPLACE FUNCTION admin_get_shop_full(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin           BOOLEAN;
  v_row             businesses%ROWTYPE;
  v_owner_uid       UUID;
  v_login_email     TEXT;
  v_email_conf_at   TIMESTAMPTZ;
  v_city_name       TEXT;
  v_cat_name        TEXT;
  v_sub_name        TEXT;
  v_views           INT;
  v_leads_30d       INT;
  v_leads_7d        INT;
  v_flags_pending   INT;
  v_categories      JSONB;
  v_featured_pays   JSONB;
  v_audit           JSONB;
BEGIN
  SELECT is_admin() INTO v_admin;
  IF NOT v_admin THEN RAISE EXCEPTION 'Admin only'; END IF;

  SELECT * INTO v_row FROM businesses WHERE id = p_business_id;
  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Business not found';
  END IF;

  IF NOT _admin_has_city_access(v_row.city_id) THEN
    RAISE EXCEPTION 'Not authorised — this shop is outside your city scope';
  END IF;

  -- Linked auth user
  SELECT auth_user_id INTO v_owner_uid
    FROM business_owners
    WHERE business_id = p_business_id
    ORDER BY created_at DESC NULLS LAST
    LIMIT 1;

  IF v_owner_uid IS NOT NULL THEN
    SELECT email, email_confirmed_at
      INTO v_login_email, v_email_conf_at
      FROM auth.users
      WHERE id = v_owner_uid;
  END IF;

  -- City + categories
  SELECT name INTO v_city_name FROM geo_cities WHERE id = v_row.city_id;
  SELECT name INTO v_cat_name  FROM categories WHERE id = v_row.category_id;
  SELECT name INTO v_sub_name  FROM categories WHERE id = v_row.sub_category_id;

  -- Multi-category badges
  SELECT COALESCE(
    jsonb_agg(jsonb_build_object(
      'id',        c.id,
      'name',      c.name,
      'slug',      c.slug,
      'icon',      c.icon,
      'is_primary', bc.is_primary
    ) ORDER BY bc.is_primary DESC, c.name),
    '[]'::jsonb
  ) INTO v_categories
  FROM business_categories bc
  JOIN categories c ON c.id = bc.category_id
  WHERE bc.business_id = p_business_id;

  -- Engagement counts
  SELECT COALESCE(view_count, 0) INTO v_views FROM businesses WHERE id = p_business_id;

  SELECT COUNT(*)::INT INTO v_leads_30d
    FROM leads_log
    WHERE business_id = p_business_id
      AND created_at >= NOW() - INTERVAL '30 days';

  SELECT COUNT(*)::INT INTO v_leads_7d
    FROM leads_log
    WHERE business_id = p_business_id
      AND created_at >= NOW() - INTERVAL '7 days';

  SELECT COUNT(*)::INT INTO v_flags_pending
    FROM reports
    WHERE business_id = p_business_id
      AND status = 'pending';

  -- Featured payments (last 5)
  SELECT COALESCE(
    jsonb_agg(jsonb_build_object(
      'id',         id,
      'amount',     amount_inr,
      'days',       days,
      'method',     method,
      'notes',      notes,
      'starts_at',  starts_at,
      'ends_at',    ends_at,
      'revoked_at', revoked_at,
      'created_at', created_at
    ) ORDER BY created_at DESC),
    '[]'::jsonb
  ) INTO v_featured_pays
  FROM featured_payments
  WHERE business_id = p_business_id;

  -- Recent audit log (last 10 admin actions on this business)
  SELECT COALESCE(
    jsonb_agg(jsonb_build_object(
      'action',       action,
      'admin_email',  admin_email,
      'details',      details,
      'created_at',   created_at
    ) ORDER BY created_at DESC),
    '[]'::jsonb
  ) INTO v_audit
  FROM (
    SELECT action, admin_email, details, created_at
    FROM admin_audit_log
    WHERE target_id = p_business_id::TEXT
    ORDER BY created_at DESC
    LIMIT 10
  ) recent;

  RETURN jsonb_build_object(
    'id',                v_row.id,
    'slug',              v_row.slug,
    'name',              v_row.name,
    'name_hi',           v_row.name_hi,
    'status',            v_row.status,
    'owner_name',        v_row.owner_name,
    'owner_role',        v_row.owner_role,

    -- AUTH user info
    'owner_email',                v_login_email,    -- LOGIN email (auth.users)
    'owner_email_confirmed',      (v_email_conf_at IS NOT NULL),  -- NEW: verified?
    'owner_email_confirmed_at',   v_email_conf_at,                -- NEW: when?
    'owner_user_id',              v_owner_uid,

    -- public/shop email
    'shop_email',        v_row.email,
    'email',             v_row.email,  -- legacy alias

    'mobile',            v_row.mobile,
    'whatsapp',          v_row.whatsapp,
    'address_line1',     v_row.address_line1,
    'pincode',           v_row.pincode,
    'city_id',           v_row.city_id,
    'city_name',         v_city_name,
    'category_id',       v_row.category_id,
    'category_name',     v_cat_name,
    'sub_category_id',   v_row.sub_category_id,
    'sub_category_name', v_sub_name,
    'categories',        v_categories,

    'usp_text',          v_row.usp_text,
    'about_text',        v_row.about_text,
    'faqs',              v_row.faqs,
    'photos',            v_row.photos,
    'photos_count',      COALESCE(array_length(v_row.photos, 1), 0),
    'hours_json',        v_row.hours_json,

    -- Verification flags
    'verified_mobile',   v_row.verified_mobile,
    'verified_address',  v_row.verified_address,
    'verified_photo',    v_row.verified_photo,
    'verified_visit',    v_row.verified_visit,
    'verified_score',    v_row.verified_score,

    'verification_requested_at', v_row.verification_requested_at,

    -- Stats
    'view_count',        v_views,
    'leads_30d',         v_leads_30d,
    'leads_7d',          v_leads_7d,
    'flags_pending',     v_flags_pending,
    'rating_avg',        v_row.rating_avg,
    'rating_count',      v_row.rating_count,

    -- Featured + payments
    'featured',          v_row.is_featured,
    'is_featured',       v_row.is_featured,
    'featured_until',    v_row.featured_until,
    'featured_payments', v_featured_pays,

    -- Trust signals
    'established_year',  v_row.established_year,
    'payment_methods',   v_row.payment_methods,
    'features',          v_row.features,
    'social_links',      v_row.social_links,

    -- Timestamps
    'created_at',        v_row.created_at,
    'updated_at',        v_row.updated_at,

    -- Audit trail
    'audit_log',         v_audit
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_get_shop_full(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
DECLARE v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count FROM pg_proc WHERE proname = 'admin_get_shop_full';
  RAISE NOTICE 'admin_get_shop_full installed: % (now returns owner_email_confirmed)', v_count;
END $$;
