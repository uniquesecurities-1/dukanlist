-- =====================================================
-- db/113-studio-assist.sql
-- =====================================================
-- STRATEGIC (2026-06-06):
--   Poster Studio "Wonderful Pack" — Server-side assist data.
--
--   Single RPC that returns everything Studio needs to make
--   posters smart + personal:
--     - Top active deal (auto-include as offer banner)
--     - Best recent 5-star review (Customer Voice template)
--     - Shop snapshot (verified, established_year, etc.)
--
-- RPC:
--   get_studio_assist_data(business_id) -> JSONB
--     { "deal":   { "id", "title", "description",
--                    "discount_pct", "expires_at" } | null,
--       "review": { "rating", "text", "customer_name",
--                    "created_at" } | null,
--       "shop":   { "verified", "established_year",
--                    "rating_avg", "rating_count" }
--     }
--
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

DROP FUNCTION IF EXISTS get_studio_assist_data(UUID);
CREATE OR REPLACE FUNCTION get_studio_assist_data(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_user_id    UUID;
  v_is_owner   BOOLEAN := FALSE;
  v_deal       JSONB := NULL;
  v_review     JSONB := NULL;
  v_shop       JSONB := NULL;
BEGIN
  v_user_id := auth.uid();

  -- Owner-only (Studio is an owner tool)
  IF v_user_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM business_owners
      WHERE business_id = p_business_id AND auth_user_id = v_user_id
    ) INTO v_is_owner;
  END IF;

  IF NOT v_is_owner THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- ===== Best active deal =====
  BEGIN
    SELECT jsonb_build_object(
      'id',           d.id,
      'title',        d.title,
      'description',  COALESCE(d.description, ''),
      'discount_pct', d.discount_pct,
      'starts_at',    d.starts_at,
      'expires_at',   d.expires_at
    )
    INTO v_deal
    FROM deals d
    WHERE d.business_id = p_business_id
      AND COALESCE(d.status, 'active') = 'active'
      AND (d.expires_at IS NULL OR d.expires_at > NOW())
      AND (d.starts_at IS NULL OR d.starts_at <= NOW())
    ORDER BY d.created_at DESC
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_deal := NULL; END;

  -- ===== Best recent 5-star review =====
  BEGIN
    SELECT jsonb_build_object(
      'id',            r.id,
      'rating',        r.rating,
      'text',          r.text,
      'customer_name', COALESCE(r.customer_name, 'A customer'),
      'created_at',    r.created_at
    )
    INTO v_review
    FROM reviews r
    WHERE r.business_id = p_business_id
      AND r.rating >= 5
      AND COALESCE(r.status, 'active') NOT IN ('removed', 'hidden')
      AND length(COALESCE(r.text, '')) > 15
    ORDER BY r.created_at DESC
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_review := NULL; END;

  -- Fallback: any 4+ rating with text
  IF v_review IS NULL THEN
    BEGIN
      SELECT jsonb_build_object(
        'id',            r.id,
        'rating',        r.rating,
        'text',          r.text,
        'customer_name', COALESCE(r.customer_name, 'A customer'),
        'created_at',    r.created_at
      )
      INTO v_review
      FROM reviews r
      WHERE r.business_id = p_business_id
        AND r.rating >= 4
        AND COALESCE(r.status, 'active') NOT IN ('removed', 'hidden')
        AND length(COALESCE(r.text, '')) > 15
      ORDER BY r.created_at DESC
      LIMIT 1;
    EXCEPTION WHEN OTHERS THEN v_review := NULL; END;
  END IF;

  -- ===== Shop snapshot =====
  BEGIN
    SELECT jsonb_build_object(
      'verified',         COALESCE(b.verified_score, 0) >= 1,
      'verified_score',   COALESCE(b.verified_score, 0),
      'established_year', b.established_year,
      'rating_avg',       COALESCE(b.rating_avg, 0),
      'rating_count',     COALESCE(b.rating_count, 0),
      'years_active',     CASE
        WHEN b.established_year IS NOT NULL AND b.established_year > 1900
          THEN EXTRACT(YEAR FROM NOW())::INT - b.established_year
        ELSE NULL
      END
    )
    INTO v_shop
    FROM businesses b
    WHERE b.id = p_business_id;
  EXCEPTION WHEN OTHERS THEN v_shop := '{}'::jsonb; END;

  RETURN jsonb_build_object(
    'deal',         v_deal,
    'review',       v_review,
    'shop',         COALESCE(v_shop, '{}'::jsonb),
    'computed_at',  NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_studio_assist_data(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'db/113 installed.';
  RAISE NOTICE '  RPC: get_studio_assist_data(business_id)';
  RAISE NOTICE '  Returns: best active deal + best 5-star review + shop snapshot';
END $$;
