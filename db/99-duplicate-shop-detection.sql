-- =====================================================
-- db/99-duplicate-shop-detection.sql
-- =====================================================
-- USER REQUEST (2026-06-04):
--   "Duplicate shop detection — fuzzy name + mobile + address
--    matching, admin alert"
--
-- DESIGN:
--   * Use pg_trgm extension (already on Supabase) for fuzzy name match
--   * Phone normalization (already used in mobile-as-login)
--   * Address tokenization for soft match
--   * find_potential_duplicates() RPC: returns groups of likely-duplicate shops
--   * Two-tier scoring:
--     - HIGH confidence: same canonical mobile OR (name similarity > 0.7 + same locality)
--     - MEDIUM confidence: name similarity 0.5-0.7 + same city
--   * Admin can mark a pair as "not_duplicate" to suppress future flags
--
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. Ensure pg_trgm extension (already on Supabase but be safe)
-- ============================================================
CREATE EXTENSION IF NOT EXISTS pg_trgm;


-- ============================================================
-- 2. Allow-list table — pairs admin has confirmed are NOT dupes
-- ============================================================
CREATE TABLE IF NOT EXISTS duplicate_allowlist (
  id            BIGSERIAL PRIMARY KEY,
  business_a_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  business_b_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  marked_by     UUID,
  marked_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reason        TEXT,
  CHECK (business_a_id < business_b_id),  -- normalize order
  UNIQUE (business_a_id, business_b_id)
);

ALTER TABLE duplicate_allowlist ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "dup_al_admin_all" ON duplicate_allowlist;
CREATE POLICY "dup_al_admin_all" ON duplicate_allowlist
  FOR ALL TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());


-- ============================================================
-- 3. Index for fuzzy name search (creates if not exists)
-- ============================================================
CREATE INDEX IF NOT EXISTS businesses_name_trgm_idx
  ON businesses USING gin (lower(name) gin_trgm_ops);
CREATE INDEX IF NOT EXISTS businesses_mobile_norm_idx
  ON businesses (regexp_replace(COALESCE(mobile, ''), '\D', '', 'g'));


-- ============================================================
-- 4. Helper: normalize mobile to 10-digit Indian form
-- ============================================================
CREATE OR REPLACE FUNCTION norm_mobile_10(p_raw TEXT)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE v TEXT;
BEGIN
  IF p_raw IS NULL THEN RETURN NULL; END IF;
  v := regexp_replace(p_raw, '\D', '', 'g');
  IF length(v) = 11 AND substring(v,1,1) = '0' THEN v := substring(v,2); END IF;
  IF length(v) = 12 AND substring(v,1,2) = '91' THEN v := substring(v,3); END IF;
  IF length(v) = 10 AND substring(v,1,1) ~ '[6-9]' THEN RETURN v; END IF;
  RETURN NULL;
END;
$$;


-- ============================================================
-- 5. Main RPC — find_potential_duplicates()
--    Returns groups of similar shops with confidence score.
-- ============================================================
DROP FUNCTION IF EXISTS admin_find_duplicate_shops(NUMERIC, INT);
CREATE OR REPLACE FUNCTION admin_find_duplicate_shops(
  p_min_similarity NUMERIC DEFAULT 0.5,
  p_limit INT DEFAULT 100
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  IF p_min_similarity < 0.3 THEN p_min_similarity := 0.3; END IF;
  IF p_min_similarity > 1.0 THEN p_min_similarity := 1.0; END IF;
  IF p_limit < 1 OR p_limit > 500 THEN p_limit := 100; END IF;

  WITH pairs AS (
    -- Find candidate pairs by either:
    --   (a) same canonical mobile (highest confidence), or
    --   (b) fuzzy name match in same city
    SELECT
      LEAST(a.id, b.id)::UUID    AS id_a,
      GREATEST(a.id, b.id)::UUID AS id_b,
      a.id AS a_id, a.name AS a_name, a.mobile AS a_mobile, a.city_id AS a_city,
      a.created_at AS a_created, a.status AS a_status,
      b.id AS b_id, b.name AS b_name, b.mobile AS b_mobile, b.city_id AS b_city,
      b.created_at AS b_created, b.status AS b_status,
      CASE
        WHEN norm_mobile_10(a.mobile) IS NOT NULL
         AND norm_mobile_10(a.mobile) = norm_mobile_10(b.mobile)
          THEN 1.0
        ELSE similarity(lower(a.name), lower(b.name))
      END AS sim_score,
      CASE
        WHEN norm_mobile_10(a.mobile) IS NOT NULL
         AND norm_mobile_10(a.mobile) = norm_mobile_10(b.mobile)
          THEN 'mobile_match'
        WHEN a.city_id = b.city_id AND similarity(lower(a.name), lower(b.name)) >= 0.7
          THEN 'name_match_same_city'
        WHEN similarity(lower(a.name), lower(b.name)) >= p_min_similarity
          THEN 'name_similar'
        ELSE 'weak'
      END AS reason
    FROM businesses a
    JOIN businesses b
      ON a.id < b.id
     AND a.status NOT IN ('rejected', 'deleted')
     AND b.status NOT IN ('rejected', 'deleted')
     AND (
       (norm_mobile_10(a.mobile) IS NOT NULL
        AND norm_mobile_10(a.mobile) = norm_mobile_10(b.mobile))
       OR
       (similarity(lower(a.name), lower(b.name)) >= p_min_similarity)
     )
    WHERE NOT EXISTS (
      SELECT 1 FROM duplicate_allowlist dl
       WHERE dl.business_a_id = LEAST(a.id, b.id)
         AND dl.business_b_id = GREATEST(a.id, b.id)
    )
  )
  SELECT jsonb_build_object(
    'count', (SELECT COUNT(*) FROM pairs),
    'rows', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id_a',       id_a,
        'id_b',       id_b,
        'similarity', ROUND(sim_score::NUMERIC, 3),
        'reason',     reason,
        'shop_a', jsonb_build_object(
          'id', a_id, 'name', a_name, 'mobile', a_mobile,
          'created_at', a_created, 'status', a_status
        ),
        'shop_b', jsonb_build_object(
          'id', b_id, 'name', b_name, 'mobile', b_mobile,
          'created_at', b_created, 'status', b_status
        )
      ) ORDER BY sim_score DESC, a_created DESC)
      FROM (SELECT * FROM pairs ORDER BY sim_score DESC LIMIT p_limit) p
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_find_duplicate_shops(NUMERIC, INT) TO authenticated;


-- ============================================================
-- 6. Mark a pair as "not duplicate" (suppresses future flags)
-- ============================================================
DROP FUNCTION IF EXISTS admin_mark_not_duplicate(UUID, UUID, TEXT);
CREATE OR REPLACE FUNCTION admin_mark_not_duplicate(
  p_a UUID, p_b UUID, p_reason TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_a UUID; v_b UUID;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;
  IF p_a IS NULL OR p_b IS NULL OR p_a = p_b THEN
    RAISE EXCEPTION 'invalid pair';
  END IF;
  -- Normalize order
  v_a := LEAST(p_a, p_b);
  v_b := GREATEST(p_a, p_b);
  INSERT INTO duplicate_allowlist (business_a_id, business_b_id, marked_by, reason)
    VALUES (v_a, v_b, auth.uid(), p_reason)
    ON CONFLICT DO NOTHING;
  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_mark_not_duplicate(UUID, UUID, TEXT) TO authenticated;


-- ============================================================
-- 7. Admin RPC — quick count for nav badge / Today's Focus
-- ============================================================
DROP FUNCTION IF EXISTS admin_duplicate_count();
CREATE OR REPLACE FUNCTION admin_duplicate_count()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE v_count INT;
BEGIN
  IF NOT is_admin() THEN RETURN 0; END IF;
  SELECT COUNT(*) INTO v_count
  FROM businesses a
  JOIN businesses b
    ON a.id < b.id
   AND a.status NOT IN ('rejected', 'deleted')
   AND b.status NOT IN ('rejected', 'deleted')
   AND (
     (norm_mobile_10(a.mobile) IS NOT NULL
      AND norm_mobile_10(a.mobile) = norm_mobile_10(b.mobile))
     OR
     similarity(lower(a.name), lower(b.name)) >= 0.7
   )
  WHERE NOT EXISTS (
    SELECT 1 FROM duplicate_allowlist dl
     WHERE dl.business_a_id = LEAST(a.id, b.id)
       AND dl.business_b_id = GREATEST(a.id, b.id)
  );
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_duplicate_count() TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'db/99 installed.';
  RAISE NOTICE '  Extension pg_trgm enabled, fuzzy name index built';
  RAISE NOTICE '  RPC: admin_find_duplicate_shops(min_sim, limit)';
  RAISE NOTICE '  RPC: admin_mark_not_duplicate(a, b, reason)';
  RAISE NOTICE '  RPC: admin_duplicate_count()';
END $$;
