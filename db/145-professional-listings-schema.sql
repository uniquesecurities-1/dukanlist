-- ============================================================
-- db/145 — Professional Listings Compliance Schema
-- ============================================================
-- Per user feedback: CA refused to register on DukanList because ICAI rules
-- prohibit "advertising / soliciting" — applies similarly to Doctors (NMC),
-- Lawyers (BCI), Company Secretaries (ICSI), Cost Accountants (ICMAI).
-- Mutual Fund Distributors (AMFI), Stock Brokers/AP (SEBI) and Insurance
-- Advisors (IRDAI) have partial restrictions (mandatory disclaimers,
-- no return-promise USPs, no "Top Rated" badges).
--
-- This migration adds infrastructure for a "Professional Listing" mode:
--
--   STRICT tier  (CA, Doctor, Lawyer, CS, ICMAI):
--     - Reviews, ratings, "Top Rated" badge, Featured promotion all hidden
--     - Show only: name, firm, membership number, qualification, address,
--       contact, areas of practice, office hours, founding year
--     - Compliance disclaimer footer mandatory
--
--   PARTIAL tier (MFD, Stock Broker, Insurance, Financial Advisor):
--     - Reviews allowed but mandatory regulatory disclaimer
--     - "Top Rated" badge hidden, no return-promise USPs
--     - Membership/ARN/SEBI reg number visible
--
-- All schema changes are ADDITIVE — existing data untouched, columns
-- nullable with safe defaults. Forward-only migration. Re-runnable.
-- ============================================================

BEGIN;

-- ============================================================
-- Part 1: New columns on `businesses` table
-- ============================================================
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS is_professional_listing    BOOLEAN     DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS professional_tier          TEXT,                     -- NULL | 'strict' | 'partial'
  ADD COLUMN IF NOT EXISTS membership_no              TEXT,                     -- ICAI No / MCI Reg / BAR Council No / ARN / SEBI Reg
  ADD COLUMN IF NOT EXISTS membership_authority       TEXT,                     -- 'ICAI' | 'NMC' | 'BCI' | 'ICSI' | 'ICMAI' | 'AMFI' | 'SEBI' | 'IRDAI'
  ADD COLUMN IF NOT EXISTS professional_qualification TEXT,                     -- 'CA' | 'MD' | 'MBBS' | 'LLB' | 'CS' | 'CMA' | etc.
  ADD COLUMN IF NOT EXISTS practice_areas             TEXT[] DEFAULT '{}',      -- ['Tax', 'Audit', 'GST'] or ['Cardiology', 'Internal Medicine']
  ADD COLUMN IF NOT EXISTS disclaimer_accepted_at     TIMESTAMPTZ,              -- when owner accepted compliance disclaimer
  ADD COLUMN IF NOT EXISTS prof_verified_at           TIMESTAMPTZ,              -- when admin verified membership
  ADD COLUMN IF NOT EXISTS prof_verified_by           UUID REFERENCES admin_users(auth_user_id),
  ADD COLUMN IF NOT EXISTS prof_verification_notes    TEXT;                     -- admin's verification notes

-- Quick lookup index for professional listings (frequently filtered)
CREATE INDEX IF NOT EXISTS idx_biz_professional
  ON businesses(is_professional_listing)
  WHERE is_professional_listing = TRUE;

-- ============================================================
-- Part 2: New column on `categories` table — drives professional mode
-- ============================================================
-- When a business is assigned a category that has professional_tier set,
-- registration form auto-enables professional onboarding. The business's
-- own professional_tier mirrors this.
ALTER TABLE categories
  ADD COLUMN IF NOT EXISTS professional_tier TEXT;   -- NULL | 'strict' | 'partial'

-- ============================================================
-- Part 3: Add 3 missing professional categories (advocate, CS, CMA)
-- ============================================================
WITH p AS (SELECT id FROM categories WHERE slug = 'professional-services')
INSERT INTO categories (slug, name, name_hi, icon, parent_id, sort_order)
SELECT v.slug, v.name, v.name_hi, v.icon, p.id, v.sort
FROM p, (VALUES
  ('advocate',          'Advocate / Lawyer',           'अधिवक्ता / वकील',          '⚖️',  300),
  ('company-secretary', 'Company Secretary (CS)',      'कंपनी सेक्रेटरी',           '📜',  301),
  ('cost-accountant',   'Cost Accountant (CMA)',       'कॉस्ट अकाउंटेंट',           '🧮',  302)
) AS v(slug, name, name_hi, icon, sort)
ON CONFLICT (slug) DO NOTHING;

-- ============================================================
-- Part 4: Set professional_tier on existing + new categories
-- ============================================================

-- STRICT tier — total advertising/soliciting ban under their regulator
UPDATE categories SET professional_tier = 'strict'
WHERE slug IN (
  -- ICAI: Chartered Accountants
  'ca', 'tax-consultant',
  -- NMC: Medical practitioners
  'doctor', 'dentist', 'pediatrician', 'gynecologist', 'orthopedic',
  'cardiologist', 'dermatologist', 'ent-specialist', 'surgeon-general',
  'urologist', 'neurologist', 'psychiatrist', 'diabetes-specialist',
  'physiotherapist', 'ayurveda', 'homeopathy',
  -- BCI: Advocates
  'advocate',
  -- ICSI: Company Secretaries
  'company-secretary',
  -- ICMAI: Cost Accountants
  'cost-accountant'
);

-- PARTIAL tier — restrictions exist but disclaimer + limited promotion allowed
UPDATE categories SET professional_tier = 'partial'
WHERE slug IN (
  -- AMFI
  'mutual-fund-distributor',
  -- SEBI
  'stock-broker',
  -- IRDAI
  'insurance-life', 'insurance-health', 'insurance-general',
  -- Generic financial planner
  'financial-advisor'
);

-- ============================================================
-- Part 5: Backfill — auto-flag existing listings in professional categories
-- ============================================================
-- For listings whose CURRENT primary or sub-category is professional,
-- set the listing's professional flag + tier to match.
-- Reviews / ratings on these listings stay in DB but UI hides them.
UPDATE businesses b
SET is_professional_listing = TRUE,
    professional_tier       = c.professional_tier
FROM categories c
WHERE c.id IN (b.category_id, b.sub_category_id)
  AND c.professional_tier IS NOT NULL
  AND b.is_professional_listing = FALSE;

-- Also backfill via multi-category join table (business_categories)
UPDATE businesses b
SET is_professional_listing = TRUE,
    -- strict wins over partial when both apply
    professional_tier = (
      SELECT CASE WHEN bool_or(c.professional_tier = 'strict') THEN 'strict' ELSE 'partial' END
      FROM business_categories bc2
      JOIN categories c ON c.id = bc2.category_id
      WHERE bc2.business_id = b.id AND c.professional_tier IS NOT NULL
    )
FROM business_categories bc
JOIN categories c2 ON c2.id = bc.category_id
WHERE bc.business_id = b.id
  AND c2.professional_tier IS NOT NULL
  AND b.is_professional_listing = FALSE;

-- ============================================================
-- Part 6: Verification (read-only)
-- ============================================================
SELECT
  'Categories with professional_tier' AS metric,
  professional_tier,
  COUNT(*) AS count
FROM categories
WHERE professional_tier IS NOT NULL
GROUP BY professional_tier
UNION ALL
SELECT
  'Listings auto-flagged as professional',
  professional_tier,
  COUNT(*)
FROM businesses
WHERE is_professional_listing = TRUE
GROUP BY professional_tier;

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/145 installed.';
  RAISE NOTICE '  Schema extensions for professional listings — 8 cols on businesses + flag on categories';
  RAISE NOTICE '  3 new sub-cats added (advocate, company-secretary, cost-accountant)';
  RAISE NOTICE '  Backfill applied — existing listings in pro categories auto-flagged';
END $$;
