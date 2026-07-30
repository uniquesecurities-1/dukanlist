-- =========================================================================
-- Migration 202: Enable Reviews for Professional Listings (v46 RELAUNCH)
-- Created: 2026-07-30
--
-- BACKGROUND:
--   db/149-professional-compliance-guards.sql created a BEFORE INSERT
--   trigger that BLOCKS reviews on business_photos where
--   is_professional_listing=TRUE and professional_tier='strict'.
--
--   Similarly blocks shop_questions (Q&A).
--
--   These were added out of over-caution about ICAI/NMC/BCI/etc rules.
--
-- REALITY CHECK:
--   Google Maps, JustDial, Practo, Sulekha — ALL show reviews for CAs,
--   doctors, advocates, MFDs, insurance agents. Regulators don't prohibit
--   patient/client reviews on third-party platforms — they prohibit
--   SELF-ADVERTISING by the professional themselves.
--
--   DukanList is a third-party directory. User-generated reviews are OK.
--
-- WHAT THIS MIGRATION DOES:
--   1. DROP guard_review_on_professional trigger (reviews now allowed for all)
--   2. DROP guard_question_on_professional trigger (Q&A now allowed for all)
--   3. Keeps guard_featured_on_professional (paid promotion still blocked)
--
-- SAFE TO RE-RUN.
-- =========================================================================

BEGIN;

-- Drop the trigger that blocks reviews for strict professional listings
DROP TRIGGER IF EXISTS trg_guard_review_on_professional ON public.reviews;

-- Drop the function (idempotent — safe if function is used elsewhere via CASCADE)
DROP FUNCTION IF EXISTS public.guard_review_on_professional() CASCADE;

-- Drop the trigger that blocks Q&A for strict professional listings
DROP TRIGGER IF EXISTS trg_guard_question_on_professional ON public.shop_questions;

-- Drop the function
DROP FUNCTION IF EXISTS public.guard_question_on_professional() CASCADE;

-- Note: guard_featured_on_professional is INTENTIONALLY KEPT.
-- Paid "featured" promotion on professional listings could be construed as
-- advertising and is still blocked. User-generated reviews are fine though.

COMMIT;

-- =========================================================================
-- HOW TO RUN
-- =========================================================================
-- 1. Supabase Dashboard → SQL Editor
-- 2. Paste this entire file
-- 3. Click "Run"
-- 4. Should see "Success. No rows returned"
--
-- VERIFY:
--   -- Try inserting a test review on a strict professional listing:
--   -- INSERT INTO reviews (business_id, reviewer_name, rating, comment)
--   -- VALUES ('<some-strict-pro-business-uuid>', 'Test', 5, 'Great service');
--   -- Should now succeed (previously would fail with regulatory exception).
-- =========================================================================
