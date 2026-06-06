-- =====================================================
-- db/84-decouple-approval-from-verification.sql
-- =====================================================
-- USER VISION (2026-06-01):
--   "Hm jis bhi shop ko approve karte hai uspar verified badge aa jata hai,
--    kyunki ab Muktsar Mansa live hai to waha ke users verified likhna thik
--    nahi hoga. Verified ka alag se rights hone chahiye admin ke paas.
--    Admin team shop visit karke jab ok ho jayegi tab verified kar denge."
--
-- THE PROBLEM:
--   Current admin_approve_business() RPC (from db/19 + db/20 + db/17)
--   sets verified_visit = TRUE on approval. That conflates:
--     • Approval = 'genuine business, not spam' (paperwork verified)
--     • Verification = 'we visited and physically confirmed' (in-person trust)
--   As we expand beyond Dabwali (Mansa, Muktsar live now), we cannot
--   honestly call every approved shop 'verified' since we have not been
--   to those cities. This dilutes the badge and breaks trust.
--
-- THIS PATCH:
--   1. Rewrites admin_approve_business() to ONLY set status='active'.
--      verified_visit is NOT touched. Approval is purely a moderation
--      decision: 'this is a real business, let it be public'.
--
--   2. Adds admin_set_verified(p_business_id, p_verified) RPC.
--      Super_admin OR city-scoped admin can toggle verified_visit.
--      Logs the action via log_admin_action so we have an audit trail.
--
--   3. Adds verification_requested_at column on businesses + RPC
--      shopkeeper_request_verification() so owners can ask the admin
--      team to come visit. Creates an internal queue.
--
--   4. Adds get_verification_queue() admin RPC — shows shops that
--      requested a visit, sorted by request date, with quick mark-verified
--      buttons.
--
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. Add verification_requested_at column
-- ============================================================
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS verification_requested_at TIMESTAMPTZ;

COMMENT ON COLUMN businesses.verification_requested_at IS
  'Set when shop owner clicks Request Verification in their panel. '
  'Cleared when admin marks them verified or rejects the request.';


-- ============================================================
-- 2. Replace admin_approve_business — NO verified_visit set
-- ============================================================
DROP FUNCTION IF EXISTS admin_approve_business(UUID);

CREATE OR REPLACE FUNCTION admin_approve_business(p_business_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin BOOLEAN;
  v_name  TEXT;
  v_city  INT;
BEGIN
  SELECT is_admin() INTO v_admin;
  IF NOT v_admin THEN RAISE EXCEPTION 'Admin only'; END IF;

  SELECT name, city_id INTO v_name, v_city
    FROM businesses
    WHERE id = p_business_id;

  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Business not found';
  END IF;

  -- Scope check (city_moderator can only approve in their cities)
  IF NOT _admin_has_city_access(v_city) THEN
    RAISE EXCEPTION 'Not authorised — this shop is outside your city scope';
  END IF;

  -- 🚨 APPROVAL ONLY — verified_visit stays as-is (default FALSE).
  -- This is the key behavior change: approval makes the shop LIVE
  -- on the public site, but does NOT mark it as physically verified.
  -- A separate admin_set_verified() call (after a physical visit or
  -- trusted reference) is required to give the shop the blue tick.
  UPDATE businesses
    SET status = 'active'
    WHERE id = p_business_id;

  PERFORM log_admin_action('approve_business', 'business', p_business_id::TEXT, v_name, NULL);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_approve_business(UUID) TO authenticated;


-- ============================================================
-- 3. admin_set_verified — toggle the blue tick (separate action)
-- ============================================================
DROP FUNCTION IF EXISTS admin_set_verified(UUID, BOOLEAN, TEXT);

CREATE OR REPLACE FUNCTION admin_set_verified(
  p_business_id UUID,
  p_verified    BOOLEAN,
  p_note        TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin BOOLEAN;
  v_name  TEXT;
  v_city  INT;
  v_prev  BOOLEAN;
BEGIN
  SELECT is_admin() INTO v_admin;
  IF NOT v_admin THEN RAISE EXCEPTION 'Admin only'; END IF;

  SELECT name, city_id, verified_visit
    INTO v_name, v_city, v_prev
    FROM businesses
    WHERE id = p_business_id;

  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Business not found';
  END IF;

  IF NOT _admin_has_city_access(v_city) THEN
    RAISE EXCEPTION 'Not authorised — this shop is outside your city scope';
  END IF;

  UPDATE businesses
    SET verified_visit          = p_verified,
        verification_requested_at = NULL,         -- clear pending request
        verified_score          = GREATEST(
                                    COALESCE(verified_score, 0)
                                    + CASE WHEN p_verified AND NOT COALESCE(v_prev, FALSE) THEN 10
                                           WHEN COALESCE(v_prev, FALSE) AND NOT p_verified THEN -10
                                           ELSE 0
                                      END,
                                    0)::SMALLINT
    WHERE id = p_business_id;

  PERFORM log_admin_action(
    CASE WHEN p_verified THEN 'mark_verified' ELSE 'unmark_verified' END,
    'business',
    p_business_id::TEXT,
    v_name,
    jsonb_build_object('previous', v_prev, 'note', p_note)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_set_verified(UUID, BOOLEAN, TEXT) TO authenticated;


-- ============================================================
-- 4. Shopkeeper-side: request a verification visit
-- ============================================================
DROP FUNCTION IF EXISTS shopkeeper_request_verification();

CREATE OR REPLACE FUNCTION shopkeeper_request_verification()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id  UUID;
  v_biz_id   UUID;
  v_status   TEXT;
  v_verified BOOLEAN;
  v_existing TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  SELECT business_id INTO v_biz_id
    FROM business_owners
    WHERE auth_user_id = v_user_id
    LIMIT 1;

  IF v_biz_id IS NULL THEN
    RAISE EXCEPTION 'No business linked to your account';
  END IF;

  SELECT status::TEXT, verified_visit, verification_requested_at
    INTO v_status, v_verified, v_existing
    FROM businesses
    WHERE id = v_biz_id;

  IF v_status <> 'active' THEN
    RAISE EXCEPTION 'Aapki listing pehle admin approval ke baad active honi chahiye';
  END IF;

  IF v_verified THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'message', 'Aapki listing already verified hai — koi action zaroori nahi.'
    );
  END IF;

  IF v_existing IS NOT NULL AND v_existing > NOW() - INTERVAL '7 days' THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'message', 'Aapne abhi haal hi me request bheji hai. Admin team jaldi contact karegi.',
      'requested_at', v_existing
    );
  END IF;

  UPDATE businesses
    SET verification_requested_at = NOW()
    WHERE id = v_biz_id;

  RETURN jsonb_build_object(
    'success', TRUE,
    'message', 'Verification visit requested. Admin team aapko 3-7 din me contact karegi.',
    'business_id', v_biz_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION shopkeeper_request_verification() TO authenticated;


-- ============================================================
-- 5. Admin RPC — get verification queue (shops that want a visit)
-- ============================================================
DROP FUNCTION IF EXISTS get_verification_queue(INT);

CREATE OR REPLACE FUNCTION get_verification_queue(p_limit INT DEFAULT 100)
RETURNS TABLE (
  business_id        UUID,
  business_name      TEXT,
  owner_name         TEXT,
  mobile             TEXT,
  whatsapp           TEXT,
  city_name          TEXT,
  pincode            TEXT,
  address_line1      TEXT,
  primary_cat        TEXT,
  requested_at       TIMESTAMPTZ,
  days_waiting       INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role   TEXT;
  v_cities INT[];
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;

  SELECT role, assigned_city_ids INTO v_role, v_cities
    FROM admin_users WHERE auth_user_id = auth.uid();

  RETURN QUERY
  SELECT
    b.id,
    b.name::TEXT,
    b.owner_name::TEXT,
    b.mobile::TEXT,
    b.whatsapp::TEXT,
    gc.name::TEXT,
    b.pincode::TEXT,
    b.address_line1::TEXT,
    COALESCE(pc.name, fc.name)::TEXT,
    b.verification_requested_at,
    GREATEST(0, EXTRACT(DAY FROM NOW() - b.verification_requested_at)::INT)
  FROM businesses b
  LEFT JOIN geo_cities  gc ON gc.id = b.city_id
  LEFT JOIN business_categories bcp ON bcp.business_id = b.id AND bcp.is_primary = TRUE
  LEFT JOIN categories pc ON pc.id = bcp.category_id
  LEFT JOIN categories fc ON fc.id = b.sub_category_id
  WHERE b.verification_requested_at IS NOT NULL
    AND b.verified_visit = FALSE
    AND b.status = 'active'
    AND (v_role = 'super_admin' OR v_cities IS NULL OR v_cities = '{}' OR b.city_id = ANY(v_cities))
  ORDER BY b.verification_requested_at ASC
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION get_verification_queue(INT) TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- POST-DEPLOY: revoke verified status from previously-auto-verified
-- shops that haven't been physically visited. Run manually if you
-- want to reset the badge across existing data:
--
-- UPDATE businesses
--   SET verified_visit = FALSE
--   WHERE verified_visit = TRUE
--     AND id NOT IN (
--       SELECT target_id::UUID FROM admin_audit_log
--       WHERE action = 'mark_verified'
--     );
--
-- Then mark known-verified ones individually:
--   SELECT admin_set_verified('unique-securities-id'::UUID, TRUE, 'founder shop');
-- =====================================================

DO $$
DECLARE
  v_rpc1 INT; v_rpc2 INT; v_rpc3 INT; v_rpc4 INT;
BEGIN
  SELECT COUNT(*) INTO v_rpc1 FROM pg_proc WHERE proname = 'admin_approve_business';
  SELECT COUNT(*) INTO v_rpc2 FROM pg_proc WHERE proname = 'admin_set_verified';
  SELECT COUNT(*) INTO v_rpc3 FROM pg_proc WHERE proname = 'shopkeeper_request_verification';
  SELECT COUNT(*) INTO v_rpc4 FROM pg_proc WHERE proname = 'get_verification_queue';

  RAISE NOTICE '✅ admin_approve_business: % (no longer sets verified_visit)', v_rpc1;
  RAISE NOTICE '✅ admin_set_verified: %', v_rpc2;
  RAISE NOTICE '✅ shopkeeper_request_verification: %', v_rpc3;
  RAISE NOTICE '✅ get_verification_queue: %', v_rpc4;
END $$;
