-- ============================================================
-- ROW-LEVEL SECURITY POLICIES
-- Run AFTER 01-schema.sql
-- ============================================================

-- ===== GEO + CATEGORIES (public read, admin write) =====
ALTER TABLE geo_states     ENABLE ROW LEVEL SECURITY;
ALTER TABLE geo_districts  ENABLE ROW LEVEL SECURITY;
ALTER TABLE geo_cities     ENABLE ROW LEVEL SECURITY;
ALTER TABLE geo_localities ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories     ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS p_geo_states_select     ON geo_states;
DROP POLICY IF EXISTS p_geo_districts_select  ON geo_districts;
DROP POLICY IF EXISTS p_geo_cities_select     ON geo_cities;
DROP POLICY IF EXISTS p_geo_localities_select ON geo_localities;
DROP POLICY IF EXISTS p_categories_select     ON categories;

CREATE POLICY p_geo_states_select     ON geo_states     FOR SELECT TO anon, authenticated USING (active = TRUE);
CREATE POLICY p_geo_districts_select  ON geo_districts  FOR SELECT TO anon, authenticated USING (active = TRUE);
CREATE POLICY p_geo_cities_select     ON geo_cities     FOR SELECT TO anon, authenticated USING (active = TRUE);
CREATE POLICY p_geo_localities_select ON geo_localities FOR SELECT TO anon, authenticated USING (TRUE);
CREATE POLICY p_categories_select     ON categories     FOR SELECT TO anon, authenticated USING (active = TRUE);

-- ===== BUSINESSES =====
ALTER TABLE businesses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS p_biz_public_read   ON businesses;
DROP POLICY IF EXISTS p_biz_owner_read    ON businesses;
DROP POLICY IF EXISTS p_biz_owner_update  ON businesses;
DROP POLICY IF EXISTS p_biz_insert        ON businesses;

-- Public sees only ACTIVE businesses
CREATE POLICY p_biz_public_read ON businesses
  FOR SELECT TO anon, authenticated
  USING (status = 'active');

-- Owners can see their own (any status — pending/flagged etc.)
CREATE POLICY p_biz_owner_read ON businesses
  FOR SELECT TO authenticated
  USING (id IN (
    SELECT business_id FROM business_owners WHERE auth_user_id = auth.uid()
  ));

-- Owners can update their own (cannot change status or verified_* fields directly)
CREATE POLICY p_biz_owner_update ON businesses
  FOR UPDATE TO authenticated
  USING (id IN (
    SELECT business_id FROM business_owners WHERE auth_user_id = auth.uid()
  ))
  WITH CHECK (id IN (
    SELECT business_id FROM business_owners WHERE auth_user_id = auth.uid()
  ));

-- Authenticated user can insert a NEW business — initial status forced to 'pending' via RPC
CREATE POLICY p_biz_insert ON businesses
  FOR INSERT TO authenticated
  WITH CHECK (status = 'pending');

-- ===== BUSINESS_OWNERS =====
ALTER TABLE business_owners ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS p_owners_self_read   ON business_owners;
DROP POLICY IF EXISTS p_owners_self_insert ON business_owners;

CREATE POLICY p_owners_self_read   ON business_owners FOR SELECT TO authenticated USING (auth_user_id = auth.uid());
CREATE POLICY p_owners_self_insert ON business_owners FOR INSERT TO authenticated WITH CHECK (auth_user_id = auth.uid());

-- NOTE: services are stored as JSONB column 'services_json' inside businesses table.
-- No separate business_services table needed — keeps schema simpler.

-- ===== REVIEWS =====
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS p_reviews_public_read ON reviews;
DROP POLICY IF EXISTS p_reviews_anon_insert ON reviews;
DROP POLICY IF EXISTS p_reviews_owner_reply ON reviews;

-- Anyone can read active reviews on active businesses
CREATE POLICY p_reviews_public_read ON reviews
  FOR SELECT TO anon, authenticated
  USING (status = 'active');

-- Anonymous-friendly insert via RPC only (we'll rate-limit + hash phone)
-- Direct insert blocked — use RPC `submit_review()`

-- Owner can update reviews on their own business (only to add reply, not modify rating)
CREATE POLICY p_reviews_owner_reply ON reviews
  FOR UPDATE TO authenticated
  USING (business_id IN (SELECT business_id FROM business_owners WHERE auth_user_id = auth.uid()))
  WITH CHECK (business_id IN (SELECT business_id FROM business_owners WHERE auth_user_id = auth.uid()));

-- ===== LEADS_LOG =====
ALTER TABLE leads_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS p_leads_owner_read ON leads_log;

-- Only the business owner can see their leads
CREATE POLICY p_leads_owner_read ON leads_log
  FOR SELECT TO authenticated
  USING (business_id IN (SELECT business_id FROM business_owners WHERE auth_user_id = auth.uid()));

-- Inserts go via RPC `log_lead()`

-- ===== FLAGS =====
ALTER TABLE flags ENABLE ROW LEVEL SECURITY;
-- Inserts only via RPC `report_business()` — no direct table access
-- Reads: admin only (we'll use service_role for admin dashboard)

NOTIFY pgrst, 'reload schema';
