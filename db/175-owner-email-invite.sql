-- ============================================================
-- db/175 — Owner email-invite flow
-- ============================================================
-- USER FLOW (from db/174 strategic pivot):
--   1. Admin bulk-publishes account-less listings (db/174)
--   2. Owner organically finds their listing → WhatsApps admin
--   3. Admin opens manage page → clicks "Send Owner Email"
--   4. JS calls Supabase auth.signInWithOtp(email, redirectTo=/claim.html?token=XXX)
--   5. Owner receives magic link → clicks → authenticated
--   6. Lands on /claim.html → existing claim_register_owner(token) fires
--   7. business_owners row created → owner can now login + manage
--
-- Without email verification: NO LOGIN. (User's anti-fake guardrail.)
--
-- THIS MIGRATION ADDS:
--   1. owner_invite_log table — audit trail of invites admin has sent
--   2. admin_log_email_invite RPC — write to log after JS sends magic link
--   3. admin_unclaimed_list — paginated list of ALL account-less listings
--      (status IN ('soft_listed','active') AND no business_owners row).
--      Replaces using admin_gp_list_all for this purpose, because we
--      need to cover bulk-published 'active' listings from db/174 too.
-- ============================================================

BEGIN;

-- ============================================================
-- PART 1: owner_invite_log audit table
-- ============================================================
CREATE TABLE IF NOT EXISTS owner_invite_log (
  id              BIGSERIAL PRIMARY KEY,
  business_id     UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  email           TEXT NOT NULL,
  sent_by_admin   TEXT,                                   -- admin email
  sent_via        TEXT DEFAULT 'magic-link',              -- magic-link | manual-share
  notes           TEXT,
  sent_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_invite_log_biz  ON owner_invite_log(business_id);
CREATE INDEX IF NOT EXISTS idx_invite_log_sent ON owner_invite_log(sent_at DESC);

ALTER TABLE owner_invite_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS p_invite_log_admin_select ON owner_invite_log;
CREATE POLICY p_invite_log_admin_select ON owner_invite_log
  FOR SELECT TO authenticated
  USING (is_admin());


-- ============================================================
-- PART 2: admin_log_email_invite — record after JS sends magic link
-- ============================================================
-- JS calls supabase.auth.signInWithOtp() then this RPC for audit only.
-- We don't actually send the email server-side because the magic-link
-- send happens through Supabase's anon client (auth endpoint).
-- ============================================================
CREATE OR REPLACE FUNCTION admin_log_email_invite(
  p_business_id UUID,
  p_email       TEXT,
  p_notes       TEXT DEFAULT NULL,
  p_sent_via    TEXT DEFAULT 'magic-link'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_email TEXT;
  v_business    RECORD;
  v_invite_id   BIGINT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  IF p_email IS NULL OR NOT (p_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') THEN
    RAISE EXCEPTION 'Invalid email format';
  END IF;

  -- Verify the business exists and is account-less
  SELECT id, name, status, claim_token
    INTO v_business
    FROM businesses WHERE id = p_business_id LIMIT 1;
  IF v_business.id IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  IF v_business.status NOT IN ('soft_listed','active') THEN
    RAISE EXCEPTION 'Cannot invite for status=% — only soft_listed or active listings', v_business.status;
  END IF;

  IF EXISTS (SELECT 1 FROM business_owners WHERE business_id = v_business.id) THEN
    RAISE EXCEPTION 'This listing already has an owner linked';
  END IF;

  SELECT email INTO v_admin_email FROM admin_users WHERE auth_user_id = auth.uid();

  INSERT INTO owner_invite_log (business_id, email, sent_by_admin, sent_via, notes)
  VALUES (v_business.id, LOWER(TRIM(p_email)), v_admin_email, COALESCE(p_sent_via,'magic-link'), p_notes)
  RETURNING id INTO v_invite_id;

  -- Bump claim_status to claimed_pending so manage view reflects "invite sent"
  UPDATE businesses
     SET claim_status = 'claimed_pending',
         claim_sent_count = COALESCE(claim_sent_count, 0) + 1,
         last_claim_attempt_at = NOW(),
         updated_at = NOW()
   WHERE id = v_business.id
     AND claim_status = 'unclaimed';

  RETURN jsonb_build_object(
    'success',     TRUE,
    'invite_id',   v_invite_id,
    'business_id', v_business.id,
    'email',       LOWER(TRIM(p_email)),
    -- /claim-complete.html is the magic-link-friendly landing that
    -- expects an already-authenticated user and immediately calls
    -- claim_register_owner. Different from /claim.html which is for
    -- password-based signup flows.
    'claim_url',   'https://dukanlist.com/claim-complete.html?token=' || v_business.claim_token,
    'sent_at',     NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_log_email_invite(UUID, TEXT, TEXT, TEXT) TO authenticated;


-- ============================================================
-- PART 3: admin_unclaimed_list — all account-less listings, both
-- statuses (soft_listed for Golden Pages, active for Main DukanList)
-- ============================================================
CREATE OR REPLACE FUNCTION admin_unclaimed_list(
  p_search         TEXT    DEFAULT NULL,
  p_status_filter  TEXT    DEFAULT NULL,  -- NULL=both, 'soft_listed', or 'active'
  p_city_id        INT     DEFAULT NULL,
  p_limit          INT     DEFAULT 50,
  p_offset         INT     DEFAULT 0
)
RETURNS TABLE (
  id              UUID,
  slug            TEXT,
  name            TEXT,
  name_hi         TEXT,
  owner_name      TEXT,
  mobile          TEXT,
  area            TEXT,
  status          TEXT,
  claim_status    TEXT,
  category_name   TEXT,
  category_icon   TEXT,
  city_name       TEXT,
  pre_listed_at   TIMESTAMPTZ,
  claim_token     TEXT,
  invite_count    INT,
  last_invite_at  TIMESTAMPTZ,
  last_invite_to  TEXT,
  total_count     BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total BIGINT;
  v_status TEXT;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  v_status := NULLIF(LOWER(TRIM(COALESCE(p_status_filter,''))), '');
  IF v_status IS NOT NULL AND v_status NOT IN ('soft_listed','active') THEN
    RAISE EXCEPTION 'Invalid status filter: % (use soft_listed, active, or null for both)', v_status;
  END IF;

  SELECT COUNT(*) INTO v_total
    FROM businesses b
   WHERE b.status IN ('soft_listed','active')
     AND (v_status IS NULL OR b.status = v_status)
     AND NOT EXISTS (SELECT 1 FROM business_owners bo WHERE bo.business_id = b.id)
     AND (p_city_id IS NULL OR b.city_id = p_city_id)
     AND (p_search IS NULL OR LENGTH(TRIM(p_search)) = 0 OR
          b.name ILIKE '%' || TRIM(p_search) || '%' OR
          b.address_line1 ILIKE '%' || TRIM(p_search) || '%' OR
          COALESCE(b.owner_name,'') ILIKE '%' || TRIM(p_search) || '%' OR
          COALESCE(b.mobile,'') ILIKE '%' || TRIM(p_search) || '%');

  RETURN QUERY
  SELECT
    b.id, b.slug, b.name, b.name_hi, b.owner_name, b.mobile, b.address_line1,
    b.status, b.claim_status,
    c.name, c.icon,
    gc.name,
    b.pre_listed_at,
    b.claim_token,
    (SELECT COUNT(*)::INT FROM owner_invite_log l WHERE l.business_id = b.id),
    (SELECT MAX(l.sent_at)  FROM owner_invite_log l WHERE l.business_id = b.id),
    (SELECT l.email FROM owner_invite_log l WHERE l.business_id = b.id ORDER BY l.sent_at DESC LIMIT 1),
    v_total
  FROM businesses b
  LEFT JOIN categories c  ON c.id = b.category_id
  LEFT JOIN geo_cities gc ON gc.id = b.city_id
  WHERE b.status IN ('soft_listed','active')
    AND (v_status IS NULL OR b.status = v_status)
    AND NOT EXISTS (SELECT 1 FROM business_owners bo WHERE bo.business_id = b.id)
    AND (p_city_id IS NULL OR b.city_id = p_city_id)
    AND (p_search IS NULL OR LENGTH(TRIM(p_search)) = 0 OR
         b.name ILIKE '%' || TRIM(p_search) || '%' OR
         b.address_line1 ILIKE '%' || TRIM(p_search) || '%' OR
         COALESCE(b.owner_name,'') ILIKE '%' || TRIM(p_search) || '%' OR
         COALESCE(b.mobile,'') ILIKE '%' || TRIM(p_search) || '%')
  ORDER BY
    -- Recently invited first (since admin will follow up), then newest
    (SELECT MAX(l.sent_at) FROM owner_invite_log l WHERE l.business_id = b.id) DESC NULLS LAST,
    b.pre_listed_at DESC NULLS LAST
  LIMIT p_limit OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_unclaimed_list(TEXT, TEXT, INT, INT, INT) TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/175 installed. Owner-invite log + admin_unclaimed_list ready.';
END $$;
