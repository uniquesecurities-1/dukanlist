-- =====================================================
-- db/37-featured-listings.sql
-- Featured Listings (paid promotion) — full revenue model
-- =====================================================
-- BUILDS ON: db/26 added businesses.featured BOOLEAN
-- ADDS:
--   1. businesses.featured_until        — auto-expire timestamp (NULL = forever)
--   2. businesses.featured_started_at   — when current featured cycle started
--   3. featured_payments table          — audit trail of every paid promotion
--   4. admin_set_featured()             — mark featured + record payment
--   5. admin_unset_featured()           — manual revoke
--   6. admin_featured_summary()         — dashboard stats (active, expiring, revenue)
--   7. search_businesses() v3           — featured-first ordering + auto-expire
-- =====================================================
BEGIN;

-- ---------- 1. Schema additions ----------
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS featured_until      TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS featured_started_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_biz_featured_active
  ON businesses(featured_until)
  WHERE featured = TRUE;

-- ---------- 2. featured_payments audit table ----------
CREATE TABLE IF NOT EXISTS featured_payments (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id    UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  admin_id       UUID NOT NULL,
  days           INT  NOT NULL CHECK (days > 0 AND days <= 730),
  amount_inr     NUMERIC(10,2) NOT NULL CHECK (amount_inr >= 0),
  payment_method TEXT CHECK (payment_method IN ('cash','upi','bank_transfer','cheque','complimentary','other')),
  notes          TEXT,
  started_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at     TIMESTAMPTZ NOT NULL,
  revoked_at     TIMESTAMPTZ,
  revoked_reason TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fp_business ON featured_payments(business_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_fp_active   ON featured_payments(expires_at) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_fp_created  ON featured_payments(created_at DESC);

ALTER TABLE featured_payments ENABLE ROW LEVEL SECURITY;

-- Only admins can read/write directly; all access via RPCs
DROP POLICY IF EXISTS "fp_admin_all" ON featured_payments;
CREATE POLICY "fp_admin_all" ON featured_payments
  FOR ALL TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());

-- ---------- 3. admin_set_featured ----------
DROP FUNCTION IF EXISTS admin_set_featured(UUID, INT, NUMERIC, TEXT, TEXT);

CREATE OR REPLACE FUNCTION admin_set_featured(
  p_business_id    UUID,
  p_days           INT,
  p_amount         NUMERIC DEFAULT 0,
  p_payment_method TEXT    DEFAULT 'cash',
  p_notes          TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID := auth.uid();
  v_starts   TIMESTAMPTZ := NOW();
  v_expires  TIMESTAMPTZ;
  v_payment_id UUID;
BEGIN
  -- Auth check
  IF v_admin_id IS NULL OR NOT is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  -- Sanity
  IF p_days IS NULL OR p_days <= 0 OR p_days > 730 THEN
    RAISE EXCEPTION 'days must be between 1 and 730';
  END IF;
  IF p_amount IS NULL OR p_amount < 0 THEN
    RAISE EXCEPTION 'amount must be >= 0';
  END IF;

  v_expires := v_starts + (p_days || ' days')::INTERVAL;

  -- Mark business as featured + set expiry
  UPDATE businesses
     SET featured            = TRUE,
         featured_started_at = v_starts,
         featured_until      = v_expires
   WHERE id = p_business_id
     AND status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Business not found or not active';
  END IF;

  -- Record payment
  INSERT INTO featured_payments (
    business_id, admin_id, days, amount_inr, payment_method, notes,
    started_at, expires_at
  ) VALUES (
    p_business_id, v_admin_id, p_days, p_amount,
    COALESCE(p_payment_method, 'cash'), p_notes,
    v_starts, v_expires
  ) RETURNING id INTO v_payment_id;

  RETURN jsonb_build_object(
    'ok',            TRUE,
    'business_id',   p_business_id,
    'payment_id',    v_payment_id,
    'started_at',    v_starts,
    'expires_at',    v_expires,
    'days',          p_days,
    'amount_inr',    p_amount
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_set_featured(UUID, INT, NUMERIC, TEXT, TEXT) TO authenticated;

-- ---------- 4. admin_unset_featured ----------
DROP FUNCTION IF EXISTS admin_unset_featured(UUID, TEXT);

CREATE OR REPLACE FUNCTION admin_unset_featured(
  p_business_id UUID,
  p_reason      TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  UPDATE businesses
     SET featured       = FALSE,
         featured_until = NULL
   WHERE id = p_business_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Business not found';
  END IF;

  -- Mark latest active payment as revoked
  UPDATE featured_payments
     SET revoked_at     = NOW(),
         revoked_reason = p_reason
   WHERE business_id = p_business_id
     AND revoked_at IS NULL
     AND expires_at > NOW();

  RETURN jsonb_build_object('ok', TRUE, 'business_id', p_business_id);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_unset_featured(UUID, TEXT) TO authenticated;

-- ---------- 5. admin_featured_summary ----------
DROP FUNCTION IF EXISTS admin_featured_summary();

CREATE OR REPLACE FUNCTION admin_featured_summary()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  SELECT jsonb_build_object(
    'active_count', (
      SELECT COUNT(*) FROM businesses
       WHERE featured = TRUE
         AND (featured_until IS NULL OR featured_until > NOW())
         AND status = 'active'
    ),
    'expiring_7days', (
      SELECT COUNT(*) FROM businesses
       WHERE featured = TRUE
         AND featured_until BETWEEN NOW() AND NOW() + INTERVAL '7 days'
         AND status = 'active'
    ),
    'revenue_this_month', COALESCE((
      SELECT SUM(amount_inr) FROM featured_payments
       WHERE created_at >= date_trunc('month', NOW())
         AND revoked_at IS NULL
    ), 0),
    'revenue_this_year', COALESCE((
      SELECT SUM(amount_inr) FROM featured_payments
       WHERE created_at >= date_trunc('year', NOW())
         AND revoked_at IS NULL
    ), 0),
    'revenue_all_time', COALESCE((
      SELECT SUM(amount_inr) FROM featured_payments
       WHERE revoked_at IS NULL
    ), 0),
    'active_list', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id',             b.id,
        'slug',           b.slug,
        'name',           b.name,
        'city_name',      gc.name,
        'featured_until', b.featured_until,
        'days_left',      GREATEST(0, EXTRACT(EPOCH FROM (b.featured_until - NOW()))/86400)::INT,
        'photo',          (b.photos)[1]
      ) ORDER BY b.featured_until ASC NULLS LAST)
        FROM businesses b
        LEFT JOIN geo_cities gc ON gc.id = b.city_id
       WHERE b.featured = TRUE
         AND (b.featured_until IS NULL OR b.featured_until > NOW())
         AND b.status = 'active'
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_featured_summary() TO authenticated;

-- ---------- 6. search_businesses v3 — featured-first ordering ----------
DROP FUNCTION IF EXISTS search_businesses(TEXT, TEXT, INT, SMALLINT, INT, INT);
DROP FUNCTION IF EXISTS search_businesses(TEXT, TEXT, INT, SMALLINT, INT, INT, TEXT);

CREATE OR REPLACE FUNCTION search_businesses(
  p_query     TEXT     DEFAULT NULL,
  p_category  TEXT     DEFAULT NULL,
  p_city_id   INT      DEFAULT NULL,
  p_state_id  SMALLINT DEFAULT NULL,
  p_limit     INT      DEFAULT 20,
  p_offset    INT      DEFAULT 0,
  p_pincode   TEXT     DEFAULT NULL
)
RETURNS TABLE (
  id              UUID,
  slug            TEXT,
  name            TEXT,
  name_hi         TEXT,
  category_slug   TEXT,
  category_name   TEXT,
  category_icon   TEXT,
  address_line1   TEXT,
  city_name       TEXT,
  pincode         TEXT,
  whatsapp        TEXT,
  mobile          TEXT,
  usp_text        TEXT,
  photos          TEXT[],
  hours_json      JSONB,
  rating_avg      NUMERIC,
  rating_count    INT,
  verified_score  SMALLINT,
  is_featured     BOOLEAN,
  match_rank      REAL
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_cat_id   INT;
  v_pin_norm TEXT;
BEGIN
  IF p_category IS NOT NULL THEN
    SELECT cat.id INTO v_cat_id FROM categories cat
    WHERE cat.slug = p_category AND cat.active = TRUE;
  END IF;

  IF p_pincode IS NOT NULL AND length(trim(p_pincode)) > 0 THEN
    v_pin_norm := regexp_replace(p_pincode, '\D', '', 'g');
    IF length(v_pin_norm) = 0 THEN v_pin_norm := NULL; END IF;
  END IF;

  RETURN QUERY
  SELECT
    b.id, b.slug, b.name, b.name_hi,
    COALESCE(pc.slug, fc.slug)  AS category_slug,
    COALESCE(pc.name, fc.name)  AS category_name,
    COALESCE(pc.icon, fc.icon)  AS category_icon,
    b.address_line1, gc.name AS city_name, b.pincode,
    b.whatsapp, b.mobile,
    b.usp_text, b.photos,
    b.hours_json,
    b.rating_avg, b.rating_count, b.verified_score,
    (b.featured = TRUE AND (b.featured_until IS NULL OR b.featured_until > NOW())) AS is_featured,
    CASE
      WHEN p_query IS NULL THEN 1::REAL
      ELSE similarity(b.name || ' ' || COALESCE(b.usp_text,''), p_query)
    END AS match_rank
  FROM businesses b
  JOIN geo_cities gc ON gc.id = b.city_id
  LEFT JOIN business_categories bcp ON bcp.business_id = b.id AND bcp.is_primary = TRUE
  LEFT JOIN categories pc ON pc.id = bcp.category_id
  LEFT JOIN categories fc ON fc.id = b.category_id
  WHERE b.status = 'active'
    AND (p_city_id  IS NULL OR b.city_id  = p_city_id)
    AND (p_state_id IS NULL OR b.state_id = p_state_id)
    AND (v_pin_norm IS NULL OR b.pincode = v_pin_norm)
    AND (p_query    IS NULL OR (b.name ILIKE '%' || p_query || '%' OR b.usp_text ILIKE '%' || p_query || '%'))
    AND (
      p_category IS NULL
      OR EXISTS (
        SELECT 1 FROM business_categories bc
        WHERE bc.business_id = b.id
          AND (
            bc.category_id = v_cat_id
            OR bc.category_id IN (SELECT categories.id FROM categories WHERE categories.parent_id = v_cat_id)
          )
      )
      OR (
        NOT EXISTS (SELECT 1 FROM business_categories bc2 WHERE bc2.business_id = b.id)
        AND (b.category_id = v_cat_id OR b.sub_category_id = v_cat_id)
      )
    )
  ORDER BY
    (b.featured = TRUE AND (b.featured_until IS NULL OR b.featured_until > NOW())) DESC,
    match_rank DESC NULLS LAST,
    b.verified_score DESC NULLS LAST,
    b.rating_avg DESC NULLS LAST,
    b.name
  LIMIT GREATEST(1, LEAST(p_limit, 60))
  OFFSET GREATEST(0, p_offset);
END;
$$;

GRANT EXECUTE ON FUNCTION search_businesses(TEXT, TEXT, INT, SMALLINT, INT, INT, TEXT) TO anon, authenticated;

-- ---------- 7. Extend admin_get_shop_full with featured_until + featured_started_at ----------
-- (Recreate the same function but include the new featured columns in the response.)
DROP FUNCTION IF EXISTS admin_get_shop_full(UUID);

CREATE OR REPLACE FUNCTION admin_get_shop_full(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row     businesses%ROWTYPE;
  v_email   TEXT;
  v_owner_uid UUID;
  v_cat     JSONB;
  v_city    JSONB;
  v_loc     JSONB;
  v_state_code TEXT;
  v_city_name  TEXT;
  v_lead7   INT := 0;
  v_lead30  INT := 0;
  v_rev     INT := 0;
  v_flags   INT := 0;
  v_payments JSONB := '[]'::jsonb;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT * INTO v_row FROM businesses WHERE id = p_business_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'shop not found';
  END IF;

  SELECT bo.auth_user_id, au.email
    INTO v_owner_uid, v_email
  FROM business_owners bo
  LEFT JOIN auth.users au ON au.id = bo.auth_user_id
  WHERE bo.business_id = p_business_id
  LIMIT 1;

  SELECT jsonb_build_object('id', id, 'name', name, 'slug', slug, 'icon', icon)
    INTO v_cat
  FROM categories WHERE id = COALESCE(v_row.sub_category_id, v_row.category_id);

  SELECT name INTO v_city_name FROM geo_cities WHERE id = v_row.city_id;
  SELECT code INTO v_state_code FROM geo_states WHERE id = v_row.state_id;

  v_city := jsonb_build_object(
    'id', v_row.city_id,
    'name', COALESCE(v_city_name, '—'),
    'state_code', COALESCE(v_state_code, '')
  );

  IF v_row.locality_id IS NOT NULL THEN
    SELECT jsonb_build_object('id', id, 'name', name)
      INTO v_loc FROM geo_localities WHERE id = v_row.locality_id;
  END IF;

  BEGIN
    SELECT COUNT(*) INTO v_lead7  FROM leads_log
      WHERE business_id = p_business_id AND created_at >= NOW() - INTERVAL '7 days';
    SELECT COUNT(*) INTO v_lead30 FROM leads_log
      WHERE business_id = p_business_id AND created_at >= NOW() - INTERVAL '30 days';
  EXCEPTION WHEN OTHERS THEN NULL; END;

  BEGIN
    SELECT COUNT(*) INTO v_rev FROM reviews WHERE business_id = p_business_id;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  BEGIN
    SELECT COUNT(*) INTO v_flags FROM flags
      WHERE business_id = p_business_id AND status = 'pending';
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- Recent featured payment history (last 5)
  BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id',             id,
      'days',           days,
      'amount_inr',     amount_inr,
      'payment_method', payment_method,
      'notes',          notes,
      'started_at',     started_at,
      'expires_at',     expires_at,
      'revoked_at',     revoked_at,
      'revoked_reason', revoked_reason,
      'created_at',     created_at
    ) ORDER BY created_at DESC), '[]'::jsonb)
    INTO v_payments
    FROM (SELECT * FROM featured_payments WHERE business_id = p_business_id ORDER BY created_at DESC LIMIT 5) sub;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object(
    'id',             v_row.id,
    'slug',           v_row.slug,
    'name',           v_row.name,
    'status',         v_row.status,
    'featured',       COALESCE(v_row.featured, FALSE),
    'featured_until', v_row.featured_until,
    'featured_started_at', v_row.featured_started_at,
    'featured_payments',   v_payments,
    'owner_name',     v_row.owner_name,
    'owner_email',    v_email,
    'owner_user_id',  v_owner_uid,
    'mobile',         v_row.mobile,
    'whatsapp',       v_row.whatsapp,
    'category',       v_cat,
    'category_id',    v_row.category_id,
    'sub_category_id',v_row.sub_category_id,
    'city',           v_city,
    'locality',       v_loc,
    'pincode',        v_row.pincode,
    'address_line1',  v_row.address_line1,
    'address_line2',  v_row.address_line2,
    'lat',            v_row.lat,
    'lng',            v_row.lng,
    'usp_text',       v_row.usp_text,
    'usp_hi',         v_row.usp_hi,
    'about_text',     v_row.about_text,
    'hours_json',     v_row.hours_json,
    'photos',         v_row.photos,
    'video_url',      v_row.video_url,
    'services_json',  v_row.services_json,
    'verified_mobile',  COALESCE(v_row.verified_mobile,  FALSE),
    'verified_address', COALESCE(v_row.verified_address, FALSE),
    'verified_photo',   COALESCE(v_row.verified_photo,   FALSE),
    'verified_visit',   COALESCE(v_row.verified_visit,   FALSE),
    'verified_score',   COALESCE(v_row.verified_score,   0),
    'rating_avg',     COALESCE(v_row.rating_avg, 0),
    'rating_count',   COALESCE(v_row.rating_count, 0),
    'view_count',     COALESCE(v_row.view_count, 0),
    'lead_count',     COALESCE(v_row.lead_count, 0),
    'leads_7d',       v_lead7,
    'leads_30d',      v_lead30,
    'reviews_total',  v_rev,
    'flags_pending',  v_flags,
    'admin_notes',    v_row.admin_notes,
    'created_at',     v_row.created_at,
    'updated_at',     v_row.updated_at
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_get_shop_full(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- VERIFY:
-- SELECT admin_featured_summary();
-- SELECT id, name, is_featured FROM search_businesses(NULL,NULL,NULL,NULL,20,0,NULL);
-- =====================================================
