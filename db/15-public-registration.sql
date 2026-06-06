-- =====================================================
-- 15-public-registration.sql
-- ZERO-COST LAUNCH: Public registration without SMS OTP
-- =====================================================
-- WHAT THIS DOES:
--   1. Allows business_owners.auth_user_id to be NULL
--      (so shops can register without being logged in)
--   2. Adds owner_phone column to business_owners
--      (used later to claim/link the shop when shopkeeper logs in)
--   3. Creates register_business_public() RPC — no auth required
--      Shop goes straight to status='pending' for admin review
--   4. Creates admin_pending_count() — for dashboard badge
--   5. Creates admin_bulk_register() — bulk insert from CSV/Excel
--
-- WORKFLOW:
--   Shopkeeper fills form → no OTP → status='pending'
--   → WhatsApp admin → admin verifies → admin_approve_business()
--   → status='active' → live on site
--
-- PREREQUISITES: 01-14 SQL files executed.
-- HOW TO RUN: Paste in Supabase SQL Editor → Run.
-- IDEMPOTENT: Safe to re-run.
-- =====================================================


-- =====================================================
-- SECTION 1: Reshape business_owners
--   * Drop old composite PK (business_id, auth_user_id)
--   * Add surrogate UUID PK `id`
--   * Allow auth_user_id NULL (phone-only owners for now)
--   * Add owner_phone column
--   * Add partial unique indexes to preserve uniqueness rules
-- =====================================================

DO $$
BEGIN
  -- Only run if the new surrogate `id` column doesn't already exist.
  -- This makes the whole migration idempotent.
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'business_owners' AND column_name = 'id'
  ) THEN

    -- 1) Drop the old composite primary key FIRST.
    --    Without this, ALTER COLUMN ... DROP NOT NULL on a PK column fails.
    ALTER TABLE business_owners
      DROP CONSTRAINT IF EXISTS business_owners_pkey;

    -- 2) Now we can make auth_user_id nullable.
    ALTER TABLE business_owners
      ALTER COLUMN auth_user_id DROP NOT NULL;

    -- 3) Add owner_phone (used for phone-based ownership when no auth yet).
    ALTER TABLE business_owners
      ADD COLUMN IF NOT EXISTS owner_phone TEXT;

    -- 4) Add surrogate UUID id, backfill, then set as PK.
    ALTER TABLE business_owners
      ADD COLUMN id UUID DEFAULT gen_random_uuid();
    UPDATE business_owners SET id = gen_random_uuid() WHERE id IS NULL;
    ALTER TABLE business_owners ALTER COLUMN id SET NOT NULL;
    ALTER TABLE business_owners ADD PRIMARY KEY (id);

    -- 5) Preserve uniqueness: only ONE auth-user row per business,
    --    and only ONE phone-only row per business per phone.
    CREATE UNIQUE INDEX IF NOT EXISTS uq_biz_owner_phone
      ON business_owners(business_id, owner_phone)
      WHERE owner_phone IS NOT NULL;
    CREATE UNIQUE INDEX IF NOT EXISTS uq_biz_owner_authuser
      ON business_owners(business_id, auth_user_id)
      WHERE auth_user_id IS NOT NULL;
  END IF;
END $$;


-- =====================================================
-- SECTION 2: register_business_public() — no auth
-- =====================================================
-- Public-facing RPC. Anyone can call. Shop goes to status='pending'.
-- =====================================================

CREATE OR REPLACE FUNCTION register_business_public(
  p_category_ids        INT[],
  p_primary_category_id INT,
  p_name                TEXT,
  p_name_hi             TEXT,
  p_owner_name          TEXT,
  p_mobile              TEXT,
  p_whatsapp            TEXT,
  p_email               TEXT,
  p_address_line1       TEXT,
  p_address_line2       TEXT,
  p_locality_id         INT,
  p_city_id             INT,
  p_district_id         INT,
  p_state_id            SMALLINT,
  p_pincode             TEXT,
  p_usp_text            TEXT,
  p_usp_hi              TEXT
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_city_name         TEXT;
  v_slug              TEXT;
  v_biz_id            UUID;
  v_pincode_ok        BOOLEAN;
  v_cat_id            INT;
  v_primary_parent_id INT;
  v_n_cats            INT;
  v_invalid_count     INT;
  v_existing_biz      UUID;
BEGIN
  -- ===== Validation =====
  v_n_cats := COALESCE(array_length(p_category_ids, 1), 0);
  IF v_n_cats < 1 THEN
    RAISE EXCEPTION 'At least 1 category required';
  END IF;
  IF v_n_cats > 5 THEN
    RAISE EXCEPTION 'Maximum 5 categories allowed';
  END IF;
  IF NOT (p_primary_category_id = ANY(p_category_ids)) THEN
    RAISE EXCEPTION 'Primary category must be one of the selected categories';
  END IF;

  -- All categories must exist and be active
  SELECT COUNT(*) INTO v_invalid_count
  FROM unnest(p_category_ids) AS cid
  WHERE NOT EXISTS (SELECT 1 FROM categories WHERE id = cid AND active = TRUE);
  IF v_invalid_count > 0 THEN
    RAISE EXCEPTION 'One or more category IDs are invalid or inactive';
  END IF;

  -- Pincode-city match
  SELECT validate_pincode_city(p_pincode, p_city_id) INTO v_pincode_ok;
  IF NOT v_pincode_ok THEN
    RAISE EXCEPTION 'Pincode % does not match selected city', p_pincode;
  END IF;

  -- Basic phone sanity
  IF p_mobile IS NULL OR LENGTH(p_mobile) < 10 THEN
    RAISE EXCEPTION 'Valid mobile number required';
  END IF;

  -- Anti-duplicate: don't allow same phone to register twice in pending state
  SELECT b.id INTO v_existing_biz
  FROM businesses b
  WHERE b.mobile = p_mobile
    AND b.status IN ('pending', 'pending_review')
  LIMIT 1;
  IF v_existing_biz IS NOT NULL THEN
    RAISE EXCEPTION 'A shop with this mobile is already pending review. Please contact admin via WhatsApp +91 9541223377.';
  END IF;

  -- Get primary's parent
  SELECT parent_id INTO v_primary_parent_id
  FROM categories WHERE id = p_primary_category_id;

  -- City name + slug
  SELECT name INTO v_city_name FROM geo_cities WHERE id = p_city_id;
  v_slug := generate_business_slug(p_name, v_city_name);

  -- ===== Insert business (status=pending) =====
  INSERT INTO businesses (
    slug,
    category_id,
    sub_category_id,
    name, name_hi, owner_name,
    mobile, whatsapp, email,
    address_line1, address_line2,
    locality_id, city_id, district_id, state_id, pincode,
    usp_text, usp_hi,
    status,
    verified_mobile, verified_address
  ) VALUES (
    v_slug,
    COALESCE(v_primary_parent_id, p_primary_category_id),
    CASE WHEN v_primary_parent_id IS NOT NULL THEN p_primary_category_id ELSE NULL END,
    p_name, p_name_hi, p_owner_name,
    p_mobile, COALESCE(NULLIF(p_whatsapp,''), p_mobile), p_email,
    p_address_line1, p_address_line2,
    p_locality_id, p_city_id, p_district_id, p_state_id, p_pincode,
    p_usp_text, p_usp_hi,
    'pending',       -- always pending, admin verifies via WhatsApp
    FALSE,           -- not verified (no OTP confirmation)
    v_pincode_ok
  )
  RETURNING id INTO v_biz_id;

  -- ===== Link owner via phone (auth comes later if user logs in) =====
  INSERT INTO business_owners (business_id, auth_user_id, owner_phone, role)
  VALUES (v_biz_id, NULL, p_mobile, 'owner');

  -- ===== Categories =====
  FOREACH v_cat_id IN ARRAY p_category_ids LOOP
    INSERT INTO business_categories (business_id, category_id, is_primary)
    VALUES (v_biz_id, v_cat_id, v_cat_id = p_primary_category_id);
  END LOOP;

  RETURN v_biz_id;
END;
$$;

-- Anonymous users (anon role) need EXECUTE permission
GRANT EXECUTE ON FUNCTION register_business_public(
  INT[], INT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  INT, INT, INT, SMALLINT, TEXT, TEXT, TEXT
) TO anon, authenticated;


-- =====================================================
-- SECTION 3: admin_pending_count() — dashboard badge
-- =====================================================
CREATE OR REPLACE FUNCTION admin_pending_count()
RETURNS INT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT COUNT(*)::INT FROM businesses
  WHERE status IN ('pending', 'pending_review');
$$;

GRANT EXECUTE ON FUNCTION admin_pending_count() TO authenticated;


-- =====================================================
-- SECTION 4: claim_business_by_phone()
-- =====================================================
-- When a shopkeeper later logs in (via email magic link or any auth),
-- they call this RPC with their phone. If a business exists registered
-- with that phone (and no auth_user_id linked yet), it gets linked.
-- =====================================================
CREATE OR REPLACE FUNCTION claim_business_by_phone(p_mobile TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id   UUID;
  v_biz_id    UUID;
  v_owner_row UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Find a business with this phone that has no owner linked yet
  SELECT b.id INTO v_biz_id
  FROM businesses b
  WHERE b.mobile = p_mobile
    AND EXISTS (
      SELECT 1 FROM business_owners bo
      WHERE bo.business_id = b.id
        AND bo.auth_user_id IS NULL
        AND bo.owner_phone = p_mobile
    )
  ORDER BY b.created_at DESC
  LIMIT 1;

  IF v_biz_id IS NULL THEN
    RAISE EXCEPTION 'No shop found for this phone, or already claimed.';
  END IF;

  -- Link this auth user to the existing owner row
  UPDATE business_owners
  SET auth_user_id = v_user_id
  WHERE business_id = v_biz_id
    AND owner_phone = p_mobile
    AND auth_user_id IS NULL;

  RETURN v_biz_id;
END;
$$;

GRANT EXECUTE ON FUNCTION claim_business_by_phone(TEXT) TO authenticated;


-- =====================================================
-- SECTION 5: admin_bulk_register()
-- =====================================================
-- Admin pastes an array of shop objects, bulk-registers all with
-- status='active' + verified flag (since admin personally adds them).
-- =====================================================
CREATE OR REPLACE FUNCTION admin_bulk_register(p_shops JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin     BOOLEAN;
  v_shop      JSONB;
  v_biz_id    UUID;
  v_results   JSONB := '[]'::JSONB;
  v_success   INT := 0;
  v_failed    INT := 0;
  v_cat_id    INT;
  v_primary   INT;
  v_parent_id INT;
  v_slug      TEXT;
  v_city_name TEXT;
  v_err       TEXT;
BEGIN
  -- ===== Admin check =====
  SELECT is_admin() INTO v_admin;
  IF NOT v_admin THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  -- ===== Process each shop =====
  FOR v_shop IN SELECT * FROM jsonb_array_elements(p_shops) LOOP
    BEGIN
      v_primary := (v_shop->>'primary_category_id')::INT;
      SELECT parent_id INTO v_parent_id FROM categories WHERE id = v_primary;
      SELECT name INTO v_city_name FROM geo_cities WHERE id = (v_shop->>'city_id')::INT;
      v_slug := generate_business_slug(v_shop->>'name', v_city_name);

      INSERT INTO businesses (
        slug,
        category_id,
        sub_category_id,
        name, owner_name,
        mobile, whatsapp,
        address_line1,
        city_id, district_id, state_id, pincode,
        usp_text,
        status,
        verified_mobile, verified_address, verified_visit
      ) VALUES (
        v_slug,
        COALESCE(v_parent_id, v_primary),
        CASE WHEN v_parent_id IS NOT NULL THEN v_primary ELSE NULL END,
        v_shop->>'name',
        v_shop->>'owner_name',
        v_shop->>'mobile',
        COALESCE(v_shop->>'whatsapp', v_shop->>'mobile'),
        v_shop->>'address',
        (v_shop->>'city_id')::INT,
        (v_shop->>'district_id')::INT,
        (v_shop->>'state_id')::SMALLINT,
        v_shop->>'pincode',
        v_shop->>'usp',
        'active',  -- admin-added shops are auto-active
        TRUE, TRUE, TRUE  -- admin-verified
      )
      RETURNING id INTO v_biz_id;

      -- Link owner with phone-only (admin can later associate auth)
      INSERT INTO business_owners (business_id, auth_user_id, owner_phone, role)
      VALUES (v_biz_id, NULL, v_shop->>'mobile', 'owner');

      -- Primary category in junction
      INSERT INTO business_categories (business_id, category_id, is_primary)
      VALUES (v_biz_id, v_primary, TRUE);

      v_success := v_success + 1;
      v_results := v_results || jsonb_build_object(
        'name', v_shop->>'name',
        'status', 'success',
        'business_id', v_biz_id
      );
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      v_failed := v_failed + 1;
      v_results := v_results || jsonb_build_object(
        'name', v_shop->>'name',
        'status', 'failed',
        'error', v_err
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success_count', v_success,
    'failed_count', v_failed,
    'results', v_results
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_bulk_register(JSONB) TO authenticated;


-- =====================================================
-- Reload PostgREST schema cache
-- =====================================================
NOTIFY pgrst, 'reload schema';


-- =====================================================
-- VERIFICATION
-- =====================================================
-- 1) New RPCs visible:
--    SELECT proname FROM pg_proc WHERE proname IN
--      ('register_business_public','admin_pending_count','claim_business_by_phone','admin_bulk_register');
--    (expect 4 rows)
--
-- 2) Test public registration (no auth needed):
--    SELECT register_business_public(
--      ARRAY[33], 33,                -- ARRAY of cat IDs + primary id
--      'Test Shop','टेस्ट दुकान','Test Owner','9876543210','9876543210',null,
--      'Address line 1', null, null, 1, 1, 1::smallint, '125104',
--      'Test USP about shop','टेस्ट यूएसपी'
--    );
--
-- 3) Test pending count:
--    SELECT admin_pending_count();
-- =====================================================
