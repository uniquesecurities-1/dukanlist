-- =====================================================
-- 13-faqs-column.sql
-- Add faqs_json column to businesses table
-- =====================================================
-- WHAT THIS DOES:
--   1. Adds faqs_json JSONB column to businesses table (default '[]')
--   2. Format: [{"q": "Question text", "a": "Answer text"}, ...]
--   3. Reloads PostgREST schema cache
--
-- PREREQUISITES: 01-12 SQL files executed
-- HOW TO RUN: Paste in Supabase SQL Editor → Run
-- IDEMPOTENT: Uses IF NOT EXISTS, safe to re-run
-- =====================================================
-- Note: usp_text, usp_hi, about_text already exist in businesses table.
-- This file ONLY adds the missing faqs_json column.
-- =====================================================


-- =====================================================
-- SECTION 1: Add faqs_json column
-- =====================================================

ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS faqs_json JSONB DEFAULT '[]'::JSONB;

COMMENT ON COLUMN businesses.faqs_json IS
  'Array of FAQ objects: [{"q":"Question","a":"Answer"}, ...]. Max ~10 FAQs per business.';


-- =====================================================
-- SECTION 2: Optional GIN index for fast JSON search
-- =====================================================
-- Useful if you ever want to search inside FAQ text.
-- Comment out if you do not need full-text search across FAQs.

CREATE INDEX IF NOT EXISTS idx_biz_faqs_gin
  ON businesses USING GIN (faqs_json);


-- =====================================================
-- SECTION 3: Reload PostgREST schema cache
-- =====================================================

NOTIFY pgrst, 'reload schema';


-- =====================================================
-- VERIFICATION
-- =====================================================
-- 1) Confirm column exists:
--    SELECT column_name, data_type, column_default
--    FROM information_schema.columns
--    WHERE table_name = 'businesses' AND column_name = 'faqs_json';
--    (expect 1 row, type = jsonb, default = '[]'::jsonb)
--
-- 2) Test write (replace UUID with your business id):
--    UPDATE businesses SET faqs_json = '[
--      {"q":"Kya home delivery available hai?","a":"Haan, 5 km tak free home delivery."},
--      {"q":"Kya cash on delivery available hai?","a":"Haan, COD available hai."}
--    ]'::jsonb WHERE id = 'YOUR-UUID-HERE';
--
-- 3) Test read:
--    SELECT name, faqs_json FROM businesses
--    WHERE jsonb_array_length(faqs_json) > 0 LIMIT 5;
-- =====================================================
