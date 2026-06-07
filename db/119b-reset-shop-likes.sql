-- =====================================================
-- db/119b-reset-shop-likes.sql
-- =====================================================
-- Reset all shop loves to zero (clean slate for production launch).
-- Run AFTER db/119 has created the table + column.
--
-- DEPLOY:
--   Supabase Dashboard → SQL Editor → paste + Run
-- =====================================================

BEGIN;

-- 1. Clear dedup tracking
TRUNCATE TABLE shop_likes;

-- 2. Reset all denormalized counts to 0
UPDATE businesses SET likes_count = 0 WHERE likes_count <> 0;

COMMIT;

-- Verify (optional):
-- SELECT COUNT(*) AS rows_remaining FROM shop_likes;
-- SELECT SUM(likes_count) AS total_likes FROM businesses;
