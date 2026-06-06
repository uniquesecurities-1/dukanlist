-- ============================================================
-- RPC FUNCTIONS — Server-side logic
-- Run AFTER 02-rls-policies.sql
-- All callable from anon/authenticated via PostgREST
-- ============================================================

-- ===== Slug generator (URL-friendly business identifier) =====
CREATE OR REPLACE FUNCTION generate_business_slug(p_name TEXT, p_city_name TEXT)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
  v_base TEXT;
  v_slug TEXT;
  v_count INT;
BEGIN
  -- Lowercase, replace non-alphanum with hyphens, collapse multiple hyphens, trim
  v_base := regexp_replace(
              lower(unaccent(p_name || '-' || p_city_name)),
              '[^a-z0-9]+', '-', 'g');
  v_base := regexp_replace(v_base, '^-+|-+$', '', 'g');
  v_base := substring(v_base FROM 1 FOR 60);

  v_slug := v_base;
  SELECT COUNT(*) INTO v_count FROM businesses WHERE slug = v_slug;
  WHILE v_count > 0 LOOP
    v_slug := v_base || '-' || floor(random() * 9000 + 1000)::TEXT;
    SELECT COUNT(*) INTO v_count FROM businesses WHERE slug = v_slug;
  END LOOP;

  RETURN v_slug;
END;
$$;

-- ===== Pincode-City match validator =====
-- Returns: TRUE if pincode is registered for this city
CREATE OR REPLACE FUNCTION validate_pincode_city(p_pincode TEXT, p_city_id INT)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE
  v_match BOOLEAN;
BEGIN
  SELECT (p_pincode = ANY(pincodes)) INTO v_match
  FROM geo_cities WHERE id = p_city_id;
  RETURN COALESCE(v_match, FALSE);
END;
$$;

-- ===== REGISTRATION RPC — single atomic call =====
-- Creates business + business_owners entry in one transaction
-- Initial status = 'pending' (awaits photo + auto-verify)
CREATE OR REPLACE FUNCTION register_business(
  p_category_id   INT,
  p_name          TEXT,
  p_name_hi       TEXT,
  p_owner_name    TEXT,
  p_mobile        TEXT,
  p_whatsapp      TEXT,
  p_email         TEXT,
  p_address_line1 TEXT,
  p_address_line2 TEXT,
  p_locality_id   INT,
  p_city_id       INT,
  p_district_id   INT,
  p_state_id      SMALLINT,
  p_pincode       TEXT,
  p_usp_text      TEXT,
  p_usp_hi        TEXT
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id   UUID;
  v_city_name TEXT;
  v_slug      TEXT;
  v_biz_id    UUID;
  v_pincode_ok BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Check pincode-city match
  SELECT validate_pincode_city(p_pincode, p_city_id) INTO v_pincode_ok;
  IF NOT v_pincode_ok THEN
    RAISE EXCEPTION 'Pincode % does not match selected city', p_pincode;
  END IF;

  -- Get city name for slug
  SELECT name INTO v_city_name FROM geo_cities WHERE id = p_city_id;
  v_slug := generate_business_slug(p_name, v_city_name);

  -- Insert business
  INSERT INTO businesses (
    slug, category_id, name, name_hi, owner_name,
    mobile, whatsapp, email,
    address_line1, address_line2,
    locality_id, city_id, district_id, state_id, pincode,
    usp_text, usp_hi,
    status,
    verified_mobile, verified_address
  ) VALUES (
    v_slug, p_category_id, p_name, p_name_hi, p_owner_name,
    p_mobile, COALESCE(NULLIF(p_whatsapp,''), p_mobile), p_email,
    p_address_line1, p_address_line2,
    p_locality_id, p_city_id, p_district_id, p_state_id, p_pincode,
    p_usp_text, p_usp_hi,
    'pending',
    TRUE,           -- mobile already OTP-verified at this point
    v_pincode_ok    -- TRUE since we validated above
  )
  RETURNING id INTO v_biz_id;

  -- Link owner
  INSERT INTO business_owners (business_id, auth_user_id, role)
  VALUES (v_biz_id, v_user_id, 'owner');

  -- Increment category count
  UPDATE categories SET business_count = business_count + 1 WHERE id = p_category_id;

  RETURN v_biz_id;
END;
$$;

-- ===== ACTIVATE business after photo upload =====
CREATE OR REPLACE FUNCTION activate_business_after_photos(p_business_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_owner_ok BOOLEAN;
  v_photo_count INT;
BEGIN
  -- Verify caller is owner
  SELECT EXISTS(SELECT 1 FROM business_owners
                WHERE business_id = p_business_id AND auth_user_id = auth.uid())
    INTO v_owner_ok;
  IF NOT v_owner_ok THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Count uploaded photos
  SELECT array_length(photos, 1) INTO v_photo_count
  FROM businesses WHERE id = p_business_id;

  IF COALESCE(v_photo_count, 0) >= 1 THEN
    UPDATE businesses
    SET verified_photo = TRUE,
        status = CASE WHEN status = 'pending' THEN 'active' ELSE status END
    WHERE id = p_business_id;
  ELSE
    RAISE EXCEPTION 'At least 1 photo required';
  END IF;
END;
$$;

-- ===== PUBLIC SEARCH — text + filters =====
CREATE OR REPLACE FUNCTION search_businesses(
  p_query     TEXT     DEFAULT NULL,
  p_category  TEXT     DEFAULT NULL,     -- slug
  p_city_id   INT      DEFAULT NULL,
  p_state_id  SMALLINT DEFAULT NULL,
  p_limit     INT      DEFAULT 20,
  p_offset    INT      DEFAULT 0
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
  rating_avg      NUMERIC,
  rating_count    INT,
  verified_score  SMALLINT,
  match_rank      REAL
)
LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN QUERY
  SELECT
    b.id, b.slug, b.name, b.name_hi,
    c.slug AS category_slug, c.name AS category_name, c.icon AS category_icon,
    b.address_line1, gc.name AS city_name, b.pincode,
    b.whatsapp, b.mobile,
    b.usp_text, b.photos,
    b.rating_avg, b.rating_count, b.verified_score,
    CASE
      WHEN p_query IS NULL THEN 1::REAL
      ELSE similarity(b.name || ' ' || COALESCE(b.usp_text,''), p_query)
    END AS match_rank
  FROM businesses b
  JOIN categories  c  ON c.id = b.category_id
  JOIN geo_cities  gc ON gc.id = b.city_id
  WHERE b.status = 'active'
    AND (p_category IS NULL OR c.slug = p_category)
    AND (p_city_id IS NULL OR b.city_id = p_city_id)
    AND (p_state_id IS NULL OR b.state_id = p_state_id)
    AND (p_query IS NULL OR (b.name ILIKE '%' || p_query || '%' OR b.usp_text ILIKE '%' || p_query || '%'))
  ORDER BY match_rank DESC, b.verified_score DESC, b.rating_avg DESC, b.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

-- ===== Lead log (call/whatsapp/view track) =====
CREATE OR REPLACE FUNCTION log_lead(
  p_business_id UUID,
  p_action      TEXT,
  p_ip_hash     TEXT DEFAULT NULL,
  p_ua          TEXT DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_action NOT IN ('view','call','whatsapp','direction','share') THEN
    RAISE EXCEPTION 'Invalid action';
  END IF;
  INSERT INTO leads_log (business_id, action, ip_hash, ua_summary)
  VALUES (p_business_id, p_action, p_ip_hash, p_ua);
  -- Bump counters on business
  IF p_action IN ('call','whatsapp') THEN
    UPDATE businesses SET lead_count = lead_count + 1 WHERE id = p_business_id;
  ELSIF p_action = 'view' THEN
    UPDATE businesses SET view_count = view_count + 1, last_active_at = NOW() WHERE id = p_business_id;
  END IF;
END;
$$;

-- ===== Submit review (anon-friendly via phone hash) =====
CREATE OR REPLACE FUNCTION submit_review(
  p_business_id   UUID,
  p_customer_name TEXT,
  p_phone_hash    TEXT,
  p_rating        SMALLINT,
  p_text          TEXT
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id UUID;
BEGIN
  IF p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'Rating must be 1-5';
  END IF;
  IF length(p_phone_hash) < 32 THEN
    RAISE EXCEPTION 'Invalid phone hash';
  END IF;

  -- Upsert (one review per phone per business)
  INSERT INTO reviews (business_id, customer_name, customer_phone_hash, rating, text)
  VALUES (p_business_id, p_customer_name, p_phone_hash, p_rating, p_text)
  ON CONFLICT (business_id, customer_phone_hash)
    DO UPDATE SET rating = EXCLUDED.rating, text = EXCLUDED.text, created_at = NOW()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- ===== Report business (flag) =====
CREATE OR REPLACE FUNCTION report_business(
  p_business_id  UUID,
  p_phone_hash   TEXT,
  p_reason       TEXT,
  p_text         TEXT DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
  IF p_reason NOT IN ('fake','closed','wrong-info','spam','duplicate','other') THEN
    RAISE EXCEPTION 'Invalid reason';
  END IF;
  INSERT INTO flags (business_id, reporter_phone_hash, reason, text)
  VALUES (p_business_id, p_phone_hash, p_reason, p_text)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- ===== Public stats (hero counters) =====
CREATE OR REPLACE FUNCTION get_public_stats()
RETURNS TABLE (total_shops INT, total_categories INT, total_cities INT, total_states INT)
LANGUAGE sql STABLE AS $$
  SELECT
    (SELECT COUNT(*)::INT FROM businesses WHERE status='active'),
    (SELECT COUNT(*)::INT FROM categories WHERE active),
    (SELECT COUNT(DISTINCT city_id)::INT FROM businesses WHERE status='active'),
    (SELECT COUNT(DISTINCT state_id)::INT FROM businesses WHERE status='active');
$$;

NOTIFY pgrst, 'reload schema';
