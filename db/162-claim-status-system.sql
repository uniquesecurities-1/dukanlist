-- ============================================================
-- db/162 — Claim Status System (Pre-list + Owner Claim flow)
-- ============================================================
-- Enables the "Pehle Se Listed Hai" growth strategy: admin pre-lists
-- shops based on local resources (Vyapar Mandal lists, personal
-- contacts, manual walkthroughs). Each pre-listed shop sits with
-- claim_status='unclaimed' until owner verifies via OTP.
--
-- Three new states on businesses.claim_status:
--   • 'unclaimed'         — admin pre-listed, owner hasn't acted
--   • 'claimed_pending'   — owner started OTP flow but didn't finish
--   • 'claimed_verified'  — owner OTP-verified, link to auth.users live
--
-- Existing businesses (already owned via business_owners) get
-- claim_status='claimed_verified' as default — no disruption.
--
-- 6 RPCs introduced:
--   1. admin_pre_list_shop()         — admin adds one shop
--   2. admin_pre_list_stats()        — dashboard counters
--   3. admin_get_unclaimed_list()    — list for WhatsApp blast
--   4. admin_increment_claim_sent()  — track blasts
--   5. claim_lookup_by_token()       — anon-callable, claim page preview
--   6. claim_complete()              — auth'd, after OTP verify
--
-- Plus 2 helper SQL functions: norm_indian_mobile, generate_unique_slug.
--
-- SAFE: All ALTERs use IF NOT EXISTS. Existing data backfilled to
-- 'claimed_verified'. Re-runnable.
-- ============================================================

BEGIN;

-- ============================================================
-- PART 1: Schema additions
-- ============================================================
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS claim_status TEXT
    CHECK (claim_status IN ('unclaimed', 'claimed_pending', 'claimed_verified')),
  ADD COLUMN IF NOT EXISTS pre_listed_by         TEXT,
  ADD COLUMN IF NOT EXISTS pre_listed_at         TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS consent_method        TEXT,
  ADD COLUMN IF NOT EXISTS consent_notes         TEXT,
  ADD COLUMN IF NOT EXISTS claim_token           TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS claim_sent_count      INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_claim_attempt_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS claimed_at            TIMESTAMPTZ;

-- Backfill existing shops to claimed_verified (they already have owners)
UPDATE businesses
   SET claim_status = 'claimed_verified',
       claimed_at = COALESCE(claimed_at, created_at)
 WHERE claim_status IS NULL;

-- Make NOT NULL going forward
ALTER TABLE businesses ALTER COLUMN claim_status SET NOT NULL;
ALTER TABLE businesses ALTER COLUMN claim_status SET DEFAULT 'claimed_verified';

-- Indexes for fast queries
CREATE INDEX IF NOT EXISTS idx_biz_unclaimed
  ON businesses(pre_listed_at DESC)
  WHERE claim_status = 'unclaimed';

CREATE INDEX IF NOT EXISTS idx_biz_claim_token
  ON businesses(claim_token)
  WHERE claim_token IS NOT NULL;


-- ============================================================
-- PART 2: Helper SQL functions
-- ============================================================

-- Normalize Indian mobile to bare 10 digits (or NULL if invalid)
CREATE OR REPLACE FUNCTION norm_indian_mobile(p_phone TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_clean TEXT;
BEGIN
  v_clean := regexp_replace(COALESCE(p_phone, ''), '\D', '', 'g');
  IF LENGTH(v_clean) > 10 THEN v_clean := RIGHT(v_clean, 10); END IF;
  IF LENGTH(v_clean) <> 10 THEN RETURN NULL; END IF;
  IF substring(v_clean, 1, 1) NOT IN ('6','7','8','9') THEN RETURN NULL; END IF;
  RETURN v_clean;
END;
$$;

-- Generate a unique slug (handles duplicates by appending -1, -2...)
CREATE OR REPLACE FUNCTION generate_unique_slug(p_base TEXT)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_base    TEXT;
  v_slug    TEXT;
  v_counter INT := 0;
BEGIN
  v_base := lower(regexp_replace(COALESCE(p_base, 'shop'), '[^a-z0-9]+', '-', 'gi'));
  v_base := regexp_replace(v_base, '^-+|-+$', '', 'g');
  v_base := substring(v_base, 1, 60);
  IF v_base = '' THEN v_base := 'shop'; END IF;

  v_slug := v_base;
  WHILE EXISTS (SELECT 1 FROM businesses WHERE slug = v_slug) LOOP
    v_counter := v_counter + 1;
    v_slug := v_base || '-' || v_counter;
  END LOOP;
  RETURN v_slug;
END;
$$;


-- ============================================================
-- PART 3: admin_pre_list_shop() — single shop entry
-- ============================================================
CREATE OR REPLACE FUNCTION admin_pre_list_shop(
  p_name           TEXT,
  p_mobile         TEXT,
  p_area           TEXT DEFAULT NULL,
  p_category_slug  TEXT DEFAULT NULL,
  p_city_id        INT  DEFAULT NULL,
  p_source         TEXT DEFAULT 'manual',
  p_consent_method TEXT DEFAULT 'verbal',
  p_notes          TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_admin_email   TEXT;
  v_norm_mobile   TEXT;
  v_slug          TEXT;
  v_token         TEXT;
  v_business_id   UUID;
  v_category_id   INT;
  v_city_id       INT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  SELECT email INTO v_admin_email
    FROM admin_users WHERE auth_user_id = auth.uid();

  -- Validate name
  IF p_name IS NULL OR LENGTH(TRIM(p_name)) < 2 THEN
    RAISE EXCEPTION 'Shop name required (min 2 chars)';
  END IF;

  -- Normalize mobile to 10 digits
  v_norm_mobile := norm_indian_mobile(p_mobile);
  IF v_norm_mobile IS NULL THEN
    RAISE EXCEPTION 'Invalid mobile — must be 10-digit Indian (6/7/8/9 prefix)';
  END IF;

  -- Duplicate guard — if a shop already exists with this mobile, skip
  IF EXISTS (SELECT 1 FROM businesses WHERE mobile = v_norm_mobile) THEN
    RAISE EXCEPTION 'A shop with mobile %  already exists — claim or edit it', v_norm_mobile;
  END IF;

  -- Resolve category (fall back to "others"-ish category if not given)
  IF p_category_slug IS NOT NULL THEN
    SELECT id INTO v_category_id FROM categories WHERE slug = p_category_slug LIMIT 1;
  END IF;
  IF v_category_id IS NULL THEN
    SELECT id INTO v_category_id
      FROM categories
     WHERE slug IN ('others','other-services','general-store')
     ORDER BY (slug = 'others') DESC, id ASC
     LIMIT 1;
  END IF;
  IF v_category_id IS NULL THEN
    -- Last resort: pick the first active category
    SELECT id INTO v_category_id FROM categories WHERE active LIMIT 1;
  END IF;

  -- Resolve city — default to Mandi Dabwali if not given
  v_city_id := COALESCE(
    p_city_id,
    (SELECT id FROM geo_cities WHERE name ILIKE 'mandi dabwali' LIMIT 1),
    (SELECT id FROM geo_cities WHERE active LIMIT 1)
  );

  -- Generate slug + secure claim token
  v_slug  := generate_unique_slug(TRIM(p_name) || COALESCE(' ' || TRIM(p_area), ''));
  v_token := encode(extensions.gen_random_bytes(20), 'hex');

  INSERT INTO businesses (
    slug, name, mobile, whatsapp,
    category_id, city_id,
    address_line1,
    status, claim_status,
    pre_listed_by, pre_listed_at,
    consent_method, consent_notes,
    claim_token,
    created_at, updated_at
  ) VALUES (
    v_slug, TRIM(p_name), v_norm_mobile, v_norm_mobile,
    v_category_id, v_city_id,
    COALESCE(NULLIF(TRIM(p_area), ''), ''),
    'active', 'unclaimed',
    COALESCE(v_admin_email, p_source), NOW(),
    p_consent_method, p_notes,
    v_token,
    NOW(), NOW()
  )
  RETURNING id INTO v_business_id;

  RETURN jsonb_build_object(
    'success',     TRUE,
    'business_id', v_business_id,
    'slug',        v_slug,
    'claim_token', v_token,
    'claim_url',   'https://dukanlist.com/claim.html?token=' || v_token,
    'wa_url',      'https://wa.me/91' || v_norm_mobile
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_pre_list_shop(TEXT, TEXT, TEXT, TEXT, INT, TEXT, TEXT, TEXT) TO authenticated;


-- ============================================================
-- PART 4: admin_pre_list_stats() — dashboard counters
-- ============================================================
CREATE OR REPLACE FUNCTION admin_pre_list_stats()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  RETURN jsonb_build_object(
    'total_pre_listed', (SELECT COUNT(*)::INT FROM businesses WHERE pre_listed_at IS NOT NULL),
    'unclaimed',        (SELECT COUNT(*)::INT FROM businesses WHERE claim_status = 'unclaimed'),
    'pending',          (SELECT COUNT(*)::INT FROM businesses WHERE claim_status = 'claimed_pending'),
    'verified',         (SELECT COUNT(*)::INT FROM businesses WHERE claim_status = 'claimed_verified' AND pre_listed_at IS NOT NULL),
    'today_added',      (SELECT COUNT(*)::INT FROM businesses WHERE pre_listed_at >= CURRENT_DATE),
    'today_claimed',    (SELECT COUNT(*)::INT FROM businesses WHERE claimed_at >= CURRENT_DATE AND pre_listed_at IS NOT NULL),
    'week_added',       (SELECT COUNT(*)::INT FROM businesses WHERE pre_listed_at >= CURRENT_DATE - INTERVAL '7 days'),
    'week_claimed',     (SELECT COUNT(*)::INT FROM businesses WHERE claimed_at >= CURRENT_DATE - INTERVAL '7 days' AND pre_listed_at IS NOT NULL),
    'conversion_rate_pct', CASE
      WHEN (SELECT COUNT(*) FROM businesses WHERE pre_listed_at IS NOT NULL) = 0 THEN 0
      ELSE ROUND(100.0 *
        (SELECT COUNT(*) FROM businesses WHERE claim_status = 'claimed_verified' AND pre_listed_at IS NOT NULL) /
        (SELECT COUNT(*) FROM businesses WHERE pre_listed_at IS NOT NULL)
      , 1)
    END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_pre_list_stats() TO authenticated;


-- ============================================================
-- PART 5: admin_get_unclaimed_list() — for WhatsApp blast UI
-- ============================================================
CREATE OR REPLACE FUNCTION admin_get_unclaimed_list(
  p_limit  INT DEFAULT 100,
  p_offset INT DEFAULT 0
)
RETURNS TABLE (
  id                UUID,
  name              TEXT,
  mobile            TEXT,
  area              TEXT,
  category_name     TEXT,
  claim_token       TEXT,
  claim_sent_count  INT,
  pre_listed_at     TIMESTAMPTZ,
  source            TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  RETURN QUERY
  SELECT b.id, b.name, b.mobile, b.address_line1,
         c.name, b.claim_token,
         COALESCE(b.claim_sent_count, 0),
         b.pre_listed_at, b.pre_listed_by
    FROM businesses b
    LEFT JOIN categories c ON c.id = b.category_id
   WHERE b.claim_status = 'unclaimed'
   ORDER BY b.pre_listed_at DESC NULLS LAST
   LIMIT p_limit OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_get_unclaimed_list(INT, INT) TO authenticated;


-- ============================================================
-- PART 6: admin_increment_claim_sent() — track blasts
-- ============================================================
CREATE OR REPLACE FUNCTION admin_increment_claim_sent(p_business_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  UPDATE businesses
     SET claim_sent_count    = COALESCE(claim_sent_count, 0) + 1,
         last_claim_attempt_at = NOW()
   WHERE id = p_business_id;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_increment_claim_sent(UUID) TO authenticated;


-- ============================================================
-- PART 7: claim_lookup_by_token() — anon callable, claim preview
-- ============================================================
CREATE OR REPLACE FUNCTION claim_lookup_by_token(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_row RECORD;
BEGIN
  IF p_token IS NULL OR LENGTH(p_token) < 16 THEN
    RETURN jsonb_build_object('found', FALSE, 'reason', 'invalid_token');
  END IF;

  SELECT b.id, b.slug, b.name, b.mobile, b.claim_status, b.address_line1,
         c.name AS category_name, gc.name AS city_name
    INTO v_row
    FROM businesses b
    LEFT JOIN categories c ON c.id = b.category_id
    LEFT JOIN geo_cities gc ON gc.id = b.city_id
   WHERE b.claim_token = p_token
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('found', FALSE, 'reason', 'not_found');
  END IF;

  -- Mask mobile (first 2 + last 2 visible) — privacy
  RETURN jsonb_build_object(
    'found',           TRUE,
    'business_id',     v_row.id,
    'slug',            v_row.slug,
    'name',            v_row.name,
    'masked_mobile',   CASE
      WHEN v_row.mobile IS NOT NULL AND LENGTH(v_row.mobile) = 10
      THEN substring(v_row.mobile, 1, 2) || 'XXXXXX' || substring(v_row.mobile, 9, 2)
      ELSE NULL
    END,
    'full_mobile',     v_row.mobile,
    'area',            v_row.address_line1,
    'category_name',   v_row.category_name,
    'city_name',       v_row.city_name,
    'claim_status',    v_row.claim_status,
    'already_claimed', v_row.claim_status = 'claimed_verified'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION claim_lookup_by_token(TEXT) TO anon, authenticated;


-- ============================================================
-- PART 8: claim_complete() — finalize claim after OTP verify
-- ============================================================
-- Called from claim.html AFTER Supabase phone-OTP verification
-- succeeded (so auth.uid() is now valid). Links the auth user to
-- the business, flips status to 'claimed_verified', clears token.
CREATE OR REPLACE FUNCTION claim_complete(
  p_token      TEXT,
  p_owner_name TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id   UUID := auth.uid();
  v_user_phone TEXT;
  v_business  RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Must be OTP-authenticated to claim';
  END IF;

  SELECT id, claim_status, mobile, name
    INTO v_business
    FROM businesses
   WHERE claim_token = p_token
   LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired claim link';
  END IF;

  IF v_business.claim_status = 'claimed_verified' THEN
    RAISE EXCEPTION 'This listing has already been claimed';
  END IF;

  -- Pick up the verified user's phone (from auth.users) — this is the
  -- OTP-verified number, so we trust it. If it differs from the
  -- pre-listed mobile, the verified one wins.
  SELECT phone INTO v_user_phone FROM auth.users WHERE id = v_user_id;
  v_user_phone := norm_indian_mobile(v_user_phone);

  -- Link auth user → business
  INSERT INTO business_owners (business_id, auth_user_id, added_at)
  VALUES (v_business.id, v_user_id, NOW())
  ON CONFLICT (business_id, auth_user_id) DO NOTHING;

  -- Flip status; refresh mobile to verified number; set owner name
  UPDATE businesses
     SET claim_status = 'claimed_verified',
         claimed_at   = NOW(),
         owner_name   = COALESCE(NULLIF(TRIM(p_owner_name),''), owner_name),
         mobile       = COALESCE(v_user_phone, mobile),
         whatsapp     = COALESCE(v_user_phone, whatsapp),
         claim_token  = NULL,  -- one-time use, burn it
         updated_at   = NOW()
   WHERE id = v_business.id;

  RETURN jsonb_build_object(
    'success',     TRUE,
    'business_id', v_business.id,
    'shop_name',   v_business.name,
    'redirect_to', '/panel/dashboard.html'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION claim_complete(TEXT, TEXT) TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/162 installed. claim_status system live + 6 RPCs ready.';
END $$;
