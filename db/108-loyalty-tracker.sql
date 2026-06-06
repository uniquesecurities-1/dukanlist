-- =====================================================
-- db/108-loyalty-tracker.sql
-- =====================================================
-- STRATEGIC PHASE 4 (2026-06-05):
--   Loyalty Tracker — show shopkeepers their REAL community.
--
--   "32 customers have saved your business"
--   "Silver Loyalty tier (50+ followers in reach)"
--   "+5 new followers this week (↑18%)"
--
-- WHY THIS WINS:
--   - Real social proof that DukanList is bringing customers
--   - Tier system gives long-term goal (Bronze → Silver → Gold)
--   - Public count on listing page builds trust for new visitors
--   - Zero cost — counts existing business_favorites rows
--
-- THIS RPC:
--   get_shop_loyalty_stats(business_id) → JSONB
--     Returns: total_followers, this_week, last_week, growth_pct,
--              tier (none/bronze/silver/gold), tier_label,
--              next_tier_at, gap_to_next_tier
--
--   get_public_loyalty_count(business_id) → INT
--     Public, anonymous-callable count for display on business.html
--
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

DROP FUNCTION IF EXISTS get_shop_loyalty_stats(UUID);
CREATE OR REPLACE FUNCTION get_shop_loyalty_stats(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id      UUID;
  v_is_owner     BOOLEAN;
  v_total        INT := 0;
  v_this_week    INT := 0;
  v_last_week    INT := 0;
  v_growth_pct   INT := 0;
  v_tier         TEXT := 'none';
  v_tier_label   TEXT := 'Build your loyalty base';
  v_next_at      INT := 10;
  v_gap          INT := 10;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Owner gate
  SELECT EXISTS (
    SELECT 1 FROM business_owners
    WHERE business_id = p_business_id AND user_id = v_user_id
  ) INTO v_is_owner;
  IF NOT v_is_owner THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Total followers
  BEGIN
    SELECT COUNT(*) INTO v_total
    FROM business_favorites
    WHERE business_id = p_business_id;
  EXCEPTION WHEN OTHERS THEN v_total := 0; END;

  -- This week (last 7 days)
  BEGIN
    SELECT COUNT(*) INTO v_this_week
    FROM business_favorites
    WHERE business_id = p_business_id
      AND created_at >= NOW() - INTERVAL '7 days';
  EXCEPTION WHEN OTHERS THEN v_this_week := 0; END;

  -- Previous week (7-14 days ago)
  BEGIN
    SELECT COUNT(*) INTO v_last_week
    FROM business_favorites
    WHERE business_id = p_business_id
      AND created_at >= NOW() - INTERVAL '14 days'
      AND created_at <  NOW() - INTERVAL '7 days';
  EXCEPTION WHEN OTHERS THEN v_last_week := 0; END;

  -- Growth percentage
  IF v_last_week > 0 THEN
    v_growth_pct := ROUND(((v_this_week - v_last_week)::NUMERIC / v_last_week) * 100);
  ELSIF v_this_week > 0 THEN
    v_growth_pct := 100;
  ELSE
    v_growth_pct := 0;
  END IF;

  -- Tier calculation
  IF v_total >= 100 THEN
    v_tier := 'gold';
    v_tier_label := 'Gold Loyalty';
    v_next_at := 250;
    v_gap := GREATEST(250 - v_total, 0);
  ELSIF v_total >= 50 THEN
    v_tier := 'silver';
    v_tier_label := 'Silver Loyalty';
    v_next_at := 100;
    v_gap := 100 - v_total;
  ELSIF v_total >= 10 THEN
    v_tier := 'bronze';
    v_tier_label := 'Bronze Loyalty';
    v_next_at := 50;
    v_gap := 50 - v_total;
  ELSE
    v_tier := 'none';
    v_tier_label := 'Build your loyalty base';
    v_next_at := 10;
    v_gap := 10 - v_total;
  END IF;

  RETURN jsonb_build_object(
    'total_followers',  v_total,
    'this_week',        v_this_week,
    'last_week',        v_last_week,
    'growth_pct',       v_growth_pct,
    'tier',             v_tier,
    'tier_label',       v_tier_label,
    'next_tier_at',     v_next_at,
    'gap_to_next_tier', v_gap,
    'computed_at',      NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_shop_loyalty_stats(UUID) TO authenticated;


-- ============================================================
-- Public anonymous count — for business.html display
-- ============================================================
DROP FUNCTION IF EXISTS get_public_loyalty_count(UUID);
CREATE OR REPLACE FUNCTION get_public_loyalty_count(p_business_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM business_favorites
  WHERE business_id = p_business_id;
  RETURN COALESCE(v_count, 0);
EXCEPTION WHEN OTHERS THEN RETURN 0;
END;
$$;

GRANT EXECUTE ON FUNCTION get_public_loyalty_count(UUID) TO authenticated, anon;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'db/108 installed.';
  RAISE NOTICE '  RPC: get_shop_loyalty_stats(business_id) — owner only';
  RAISE NOTICE '  RPC: get_public_loyalty_count(business_id) — public anon';
  RAISE NOTICE '';
  RAISE NOTICE '  Tier ladder: Bronze 10+, Silver 50+, Gold 100+';
END $$;
