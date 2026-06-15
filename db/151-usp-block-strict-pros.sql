-- ============================================================
-- db/151 — Block promotional USP on strict professional listings
-- ============================================================
-- User feedback (2026-06-15): Dhaliwal Hospital (gynecologist, strict tier)
-- was displaying USP text "20+ saal se isi jagah par · Honest pricing —
-- no bargain needed · 1000+ families ka bharosa". The "1000+ families ka
-- bharosa" phrasing is a soliciting claim (numerical client count =
-- testimonial-like advertising), explicitly prohibited by NMC Code of
-- Ethics 2002 for doctors. Similar restrictions apply to ICAI/BCI/ICSI/
-- ICMAI strict-tier professions.
--
-- Even though business.html hides the USP UI in strict mode, the raw
-- usp_text + usp_hi columns:
--   (a) leak into SEO metadata (JSON-LD description, HTML meta description)
--   (b) leak into gallery placeholder quote (.ph-fb-quote)
--   (c) are pulled by external API consumers and the search RPC
--
-- This migration enforces a DB-level guarantee: usp_text and usp_hi are
-- NULL for any business where is_professional_listing=TRUE AND
-- professional_tier='strict'. Future writes are intercepted by a BEFORE
-- INSERT/UPDATE trigger; existing data is cleaned by a one-time UPDATE.
--
-- PARTIAL tier (MFD, Stock Broker, Insurance, Financial Advisor) keeps
-- their USP — AMFI/SEBI/IRDAI permit limited promotion with disclaimers.
-- about_text is also NOT cleared — owners can still describe themselves
-- factually in About; only the marketing-style USP is restricted.
--
-- SAFE: Trigger + idempotent UPDATE. Rollback only possible by manually
-- restoring from a backup — but the data being cleared is non-compliant
-- anyway, so this is the intended behaviour.
-- ============================================================

BEGIN;

-- ============================================================
-- Part 1: Trigger — block strict pros from setting USP
-- ============================================================
CREATE OR REPLACE FUNCTION block_usp_on_strict_professional()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  -- Only act on STRICT pro listings. PARTIAL tier can keep USP.
  IF NEW.is_professional_listing = TRUE
     AND NEW.professional_tier = 'strict'
     AND (NEW.usp_text IS NOT NULL OR NEW.usp_hi IS NOT NULL) THEN
    -- Silently nullify. Don't raise an exception — UI-side flows like
    -- copy-from-template would break loudly. Log via NOTICE for debugging.
    RAISE NOTICE 'usp_text/usp_hi suppressed on strict pro listing % (id %) per regulatory compliance',
      NEW.name, NEW.id;
    NEW.usp_text := NULL;
    NEW.usp_hi   := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_block_usp_on_strict_professional ON businesses;
CREATE TRIGGER trg_block_usp_on_strict_professional
  BEFORE INSERT OR UPDATE OF usp_text, usp_hi, is_professional_listing, professional_tier
  ON businesses
  FOR EACH ROW
  EXECUTE FUNCTION block_usp_on_strict_professional();

-- ============================================================
-- Part 2: One-time cleanup — clear existing soliciting USP on strict pros
-- ============================================================
-- Backup data is captured first (for audit trail / possible recovery)
-- into a one-off table that admin can review.
CREATE TABLE IF NOT EXISTS _usp_cleanup_audit_db151 (
  business_id    UUID PRIMARY KEY,
  business_name  TEXT,
  prior_usp_text TEXT,
  prior_usp_hi   TEXT,
  cleared_at     TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO _usp_cleanup_audit_db151 (business_id, business_name, prior_usp_text, prior_usp_hi)
SELECT id, name, usp_text, usp_hi
FROM businesses
WHERE is_professional_listing = TRUE
  AND professional_tier = 'strict'
  AND (usp_text IS NOT NULL OR usp_hi IS NOT NULL)
ON CONFLICT (business_id) DO NOTHING;

-- Now clear them
UPDATE businesses
SET usp_text = NULL,
    usp_hi   = NULL,
    updated_at = NOW()
WHERE is_professional_listing = TRUE
  AND professional_tier = 'strict'
  AND (usp_text IS NOT NULL OR usp_hi IS NOT NULL);

-- ============================================================
-- Verification (read-only)
-- ============================================================
SELECT
  'Strict pros with non-null USP (should be 0)' AS check,
  COUNT(*)::TEXT AS value
FROM businesses
WHERE is_professional_listing = TRUE
  AND professional_tier = 'strict'
  AND (usp_text IS NOT NULL OR usp_hi IS NOT NULL)
UNION ALL
SELECT
  'Rows preserved in audit table',
  COUNT(*)::TEXT
FROM _usp_cleanup_audit_db151
UNION ALL
SELECT
  'Trigger installed',
  CASE WHEN EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_block_usp_on_strict_professional')
       THEN 'yes' ELSE 'no' END;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/151 installed.';
  RAISE NOTICE '  usp_text + usp_hi auto-nullified on strict professional listings';
  RAISE NOTICE '  Existing soliciting content backed up to _usp_cleanup_audit_db151';
  RAISE NOTICE '  Trigger enforces it on all future writes';
END $$;
