-- =====================================================
-- db/47-trust-cols-ensure.sql
-- =====================================================
-- DEFENSIVE FIX: Payment methods, special features, and
-- established_year not saving from panel/profile.html.
--
-- Root cause: db/41-trust-hardening.sql either wasn't
-- applied OR was overwritten by a later RPC version that
-- doesn't whitelist these fields.
--
-- This script is IDEMPOTENT — safe to run multiple times.
-- It only:
--   1. Adds the 3 columns if they don't exist
--   2. Confirms the columns are visible to the API
--
-- It DOES NOT touch any existing data. Zero risk to DB.
--
-- HOW TO RUN:
--   Supabase Dashboard → SQL Editor → New Query
--   Paste this file → Run
--   Expected: NOTICE messages about cols added or skipped
--
-- AFTER RUNNING: Re-test on profile page — tick Cash/UPI,
-- click Save, refresh page. Boxes should stay ticked.
-- =====================================================

BEGIN;

-- ===== 1. Add columns idempotently =====
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS payment_methods   TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS special_features  TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS established_year  SMALLINT
    CHECK (established_year IS NULL OR (established_year BETWEEN 1800 AND 2100));

-- ===== 2. Force PostgREST schema cache reload so the
--          REST API and RPC see the new columns instantly.
NOTIFY pgrst, 'reload schema';

-- ===== 3. Verify — these should all return TRUE =====
DO $$
DECLARE
  v_has_payment BOOLEAN;
  v_has_features BOOLEAN;
  v_has_year BOOLEAN;
BEGIN
  SELECT EXISTS(SELECT 1 FROM information_schema.columns
    WHERE table_name='businesses' AND column_name='payment_methods')
    INTO v_has_payment;
  SELECT EXISTS(SELECT 1 FROM information_schema.columns
    WHERE table_name='businesses' AND column_name='special_features')
    INTO v_has_features;
  SELECT EXISTS(SELECT 1 FROM information_schema.columns
    WHERE table_name='businesses' AND column_name='established_year')
    INTO v_has_year;

  RAISE NOTICE 'payment_methods column exists  : %', v_has_payment;
  RAISE NOTICE 'special_features column exists : %', v_has_features;
  RAISE NOTICE 'established_year column exists : %', v_has_year;

  IF NOT (v_has_payment AND v_has_features AND v_has_year) THEN
    RAISE EXCEPTION 'Trust columns missing — manual investigation required';
  END IF;
END $$;

COMMIT;

-- =====================================================
-- IMPORTANT — after this runs, also run db/41-trust-hardening.sql
-- if you haven't already. That file installs the
-- update_my_business RPC that whitelists these fields.
--
-- If you suspect db/41 wasn't applied:
--   1. Open db/41-trust-hardening.sql
--   2. Copy entire contents
--   3. Paste into Supabase SQL Editor → Run
-- =====================================================
