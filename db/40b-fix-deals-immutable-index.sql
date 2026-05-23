-- =====================================================
-- db/40b-fix-deals-immutable-index.sql
-- HOTFIX for db/40 — IMMUTABLE function error in partial index
-- =====================================================
-- BUG: db/40 had partial indexes like:
--   CREATE INDEX ... WHERE valid_until > NOW();
-- PostgreSQL rejects this — index predicates must use IMMUTABLE functions only,
-- and NOW() is STABLE (not IMMUTABLE).
-- Error: 42P17 — functions in index predicate must be marked IMMUTABLE
--
-- FIX: drop the partial WHERE clauses and create regular indexes instead.
-- The query planner still uses (business_id, valid_until DESC) effectively
-- when queries filter by valid_until > NOW() at run time.
-- =====================================================
BEGIN;

-- ---------- 1. deals TABLE (create if it doesn't exist — idempotent) ----------
CREATE TABLE IF NOT EXISTS deals (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id   UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  title         TEXT NOT NULL CHECK (length(title) BETWEEN 3 AND 80),
  body          TEXT CHECK (body IS NULL OR length(body) <= 280),
  discount_pct  SMALLINT CHECK (discount_pct IS NULL OR (discount_pct > 0 AND discount_pct <= 99)),
  discount_text TEXT CHECK (discount_text IS NULL OR length(discount_text) <= 40),
  image_url     TEXT CHECK (image_url IS NULL OR length(image_url) <= 500),
  cta_label     TEXT CHECK (cta_label IS NULL OR length(cta_label) <= 30),
  valid_from    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  valid_until   TIMESTAMPTZ NOT NULL,
  view_count    INT NOT NULL DEFAULT 0,
  click_count   INT NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (valid_until > valid_from)
);

-- ---------- 2. Drop any existing partial indexes (cleanup from failed run) ----------
DROP INDEX IF EXISTS idx_deals_active;
DROP INDEX IF EXISTS idx_deals_global;
DROP INDEX IF EXISTS idx_deals_business;

-- ---------- 3. Recreate as regular (non-partial) indexes ----------
CREATE INDEX IF NOT EXISTS idx_deals_active   ON deals(business_id, valid_until DESC);
CREATE INDEX IF NOT EXISTS idx_deals_global   ON deals(valid_until DESC);
CREATE INDEX IF NOT EXISTS idx_deals_business ON deals(business_id, created_at DESC);

-- ---------- 4. RLS (idempotent) ----------
ALTER TABLE deals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "deals_public_read"  ON deals;
DROP POLICY IF EXISTS "deals_owner_all"    ON deals;
DROP POLICY IF EXISTS "deals_admin_all"    ON deals;

CREATE POLICY "deals_public_read" ON deals
  FOR SELECT TO anon, authenticated
  USING (valid_until > NOW() AND valid_from <= NOW());

CREATE POLICY "deals_owner_all" ON deals
  FOR ALL TO authenticated
  USING (business_id IN (SELECT bo.business_id FROM business_owners bo WHERE bo.auth_user_id = auth.uid()))
  WITH CHECK (business_id IN (SELECT bo.business_id FROM business_owners bo WHERE bo.auth_user_id = auth.uid()));

CREATE POLICY "deals_admin_all" ON deals
  FOR ALL TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());

-- ---------- 5. Max 5 active deals trigger ----------
CREATE OR REPLACE FUNCTION trg_deals_max_per_shop()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_count INT;
BEGIN
  IF NEW.valid_until <= NOW() THEN RETURN NEW; END IF;
  SELECT COUNT(*) INTO v_count
    FROM deals
   WHERE business_id = NEW.business_id
     AND valid_until > NOW()
     AND id <> COALESCE(NEW.id, gen_random_uuid());
  IF v_count >= 5 THEN
    RAISE EXCEPTION 'Maximum 5 active deals per shop. Delete or expire an existing deal first.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_deals_max ON deals;
CREATE TRIGGER trg_deals_max
  BEFORE INSERT OR UPDATE OF valid_until ON deals
  FOR EACH ROW EXECUTE FUNCTION trg_deals_max_per_shop();

-- ---------- 6. updated_at touch trigger ----------
CREATE OR REPLACE FUNCTION trg_deals_touch_updated()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_deals_touched ON deals;
CREATE TRIGGER trg_deals_touched
  BEFORE UPDATE ON deals
  FOR EACH ROW EXECUTE FUNCTION trg_deals_touch_updated();

-- ---------- 7. RPCs ----------
DROP FUNCTION IF EXISTS my_deals();
CREATE OR REPLACE FUNCTION my_deals()
RETURNS TABLE (
  id            UUID,
  business_id   UUID,
  title         TEXT,
  body          TEXT,
  discount_pct  SMALLINT,
  discount_text TEXT,
  image_url     TEXT,
  cta_label     TEXT,
  valid_from    TIMESTAMPTZ,
  valid_until   TIMESTAMPTZ,
  is_active     BOOLEAN,
  view_count    INT,
  click_count   INT,
  created_at    TIMESTAMPTZ
)
LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT d.id, d.business_id, d.title, d.body, d.discount_pct, d.discount_text,
         d.image_url, d.cta_label, d.valid_from, d.valid_until,
         (d.valid_until > NOW() AND d.valid_from <= NOW()) AS is_active,
         d.view_count, d.click_count, d.created_at
    FROM deals d
   WHERE d.business_id IN (SELECT bo.business_id FROM business_owners bo WHERE bo.auth_user_id = auth.uid())
     AND d.valid_until > NOW() - INTERVAL '30 days'
   ORDER BY d.valid_until DESC;
$$;
GRANT EXECUTE ON FUNCTION my_deals() TO authenticated;

DROP FUNCTION IF EXISTS create_deal(JSONB);
CREATE OR REPLACE FUNCTION create_deal(p_data JSONB)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id     UUID := auth.uid();
  v_business_id UUID;
  v_deal_id     UUID;
  v_check       JSONB;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'login required'; END IF;
  SELECT bo.business_id INTO v_business_id FROM business_owners bo WHERE bo.auth_user_id = v_user_id LIMIT 1;
  IF v_business_id IS NULL THEN RAISE EXCEPTION 'no business linked'; END IF;

  BEGIN
    v_check := check_content_violations(COALESCE(p_data->>'title','') || ' ' || COALESCE(p_data->>'body',''));
    IF (v_check->>'blocked')::BOOLEAN THEN
      RAISE EXCEPTION 'Content blocked: %', v_check->'violations';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'Content blocked%' THEN RAISE; END IF;
  END;

  INSERT INTO deals (
    business_id, title, body, discount_pct, discount_text, image_url, cta_label,
    valid_from, valid_until
  ) VALUES (
    v_business_id,
    trim(p_data->>'title'),
    NULLIF(trim(COALESCE(p_data->>'body','')), ''),
    NULLIF((p_data->>'discount_pct')::INT, 0)::SMALLINT,
    NULLIF(trim(COALESCE(p_data->>'discount_text','')), ''),
    NULLIF(trim(COALESCE(p_data->>'image_url','')), ''),
    NULLIF(trim(COALESCE(p_data->>'cta_label','')), ''),
    COALESCE((p_data->>'valid_from')::TIMESTAMPTZ, NOW()),
    (p_data->>'valid_until')::TIMESTAMPTZ
  ) RETURNING id INTO v_deal_id;
  RETURN v_deal_id;
END;
$$;
GRANT EXECUTE ON FUNCTION create_deal(JSONB) TO authenticated;

DROP FUNCTION IF EXISTS update_deal(UUID, JSONB);
CREATE OR REPLACE FUNCTION update_deal(p_deal_id UUID, p_data JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_business_id UUID;
  v_owner       BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'login required'; END IF;
  SELECT d.business_id INTO v_business_id FROM deals d WHERE d.id = p_deal_id;
  IF v_business_id IS NULL THEN RAISE EXCEPTION 'deal not found'; END IF;
  SELECT EXISTS(SELECT 1 FROM business_owners bo WHERE bo.business_id = v_business_id AND bo.auth_user_id = auth.uid())
    INTO v_owner;
  IF NOT v_owner AND NOT is_admin() THEN RAISE EXCEPTION 'not your deal'; END IF;

  IF p_data ? 'title'         THEN UPDATE deals SET title         = trim(p_data->>'title')                   WHERE id = p_deal_id; END IF;
  IF p_data ? 'body'          THEN UPDATE deals SET body          = NULLIF(trim(COALESCE(p_data->>'body','')),'') WHERE id = p_deal_id; END IF;
  IF p_data ? 'discount_pct'  THEN UPDATE deals SET discount_pct  = NULLIF((p_data->>'discount_pct')::INT, 0)::SMALLINT WHERE id = p_deal_id; END IF;
  IF p_data ? 'discount_text' THEN UPDATE deals SET discount_text = NULLIF(trim(COALESCE(p_data->>'discount_text','')),'') WHERE id = p_deal_id; END IF;
  IF p_data ? 'image_url'     THEN UPDATE deals SET image_url     = NULLIF(trim(COALESCE(p_data->>'image_url','')),'') WHERE id = p_deal_id; END IF;
  IF p_data ? 'cta_label'     THEN UPDATE deals SET cta_label     = NULLIF(trim(COALESCE(p_data->>'cta_label','')),'') WHERE id = p_deal_id; END IF;
  IF p_data ? 'valid_from'    THEN UPDATE deals SET valid_from    = (p_data->>'valid_from')::TIMESTAMPTZ    WHERE id = p_deal_id; END IF;
  IF p_data ? 'valid_until'   THEN UPDATE deals SET valid_until   = (p_data->>'valid_until')::TIMESTAMPTZ   WHERE id = p_deal_id; END IF;
  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION update_deal(UUID, JSONB) TO authenticated;

DROP FUNCTION IF EXISTS delete_deal(UUID);
CREATE OR REPLACE FUNCTION delete_deal(p_deal_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_business_id UUID;
  v_owner       BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'login required'; END IF;
  SELECT d.business_id INTO v_business_id FROM deals d WHERE d.id = p_deal_id;
  IF v_business_id IS NULL THEN RETURN FALSE; END IF;
  SELECT EXISTS(SELECT 1 FROM business_owners bo WHERE bo.business_id = v_business_id AND bo.auth_user_id = auth.uid())
    INTO v_owner;
  IF NOT v_owner AND NOT is_admin() THEN RAISE EXCEPTION 'not your deal'; END IF;
  DELETE FROM deals WHERE id = p_deal_id;
  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION delete_deal(UUID) TO authenticated;

DROP FUNCTION IF EXISTS list_active_deals(INT, TEXT);
CREATE OR REPLACE FUNCTION list_active_deals(p_limit INT DEFAULT 6, p_business_slug TEXT DEFAULT NULL)
RETURNS TABLE (
  id            UUID,
  business_id   UUID,
  business_slug TEXT,
  business_name TEXT,
  city_name     TEXT,
  category_icon TEXT,
  title         TEXT,
  body          TEXT,
  discount_pct  SMALLINT,
  discount_text TEXT,
  image_url     TEXT,
  cta_label     TEXT,
  valid_until   TIMESTAMPTZ
)
LANGUAGE sql STABLE AS $$
  SELECT
    d.id,
    d.business_id,
    b.slug    AS business_slug,
    b.name    AS business_name,
    gc.name   AS city_name,
    COALESCE(pc.icon, fc.icon) AS category_icon,
    d.title, d.body, d.discount_pct, d.discount_text, d.image_url, d.cta_label,
    d.valid_until
  FROM deals d
  JOIN businesses b ON b.id = d.business_id AND b.status = 'active'
  LEFT JOIN geo_cities gc ON gc.id = b.city_id
  LEFT JOIN business_categories bcp ON bcp.business_id = b.id AND bcp.is_primary = TRUE
  LEFT JOIN categories pc ON pc.id = bcp.category_id
  LEFT JOIN categories fc ON fc.id = b.category_id
  WHERE d.valid_from <= NOW()
    AND d.valid_until > NOW()
    AND (p_business_slug IS NULL OR b.slug = p_business_slug)
  ORDER BY d.created_at DESC
  LIMIT GREATEST(1, LEAST(p_limit, 50));
$$;
GRANT EXECUTE ON FUNCTION list_active_deals(INT, TEXT) TO anon, authenticated;

DROP FUNCTION IF EXISTS business_deals_count(UUID[]);
CREATE OR REPLACE FUNCTION business_deals_count(p_business_ids UUID[])
RETURNS TABLE (business_id UUID, deals_count INT)
LANGUAGE sql STABLE AS $$
  SELECT d.business_id, COUNT(*)::INT
    FROM deals d
   WHERE d.business_id = ANY(p_business_ids)
     AND d.valid_from <= NOW()
     AND d.valid_until > NOW()
   GROUP BY d.business_id;
$$;
GRANT EXECUTE ON FUNCTION business_deals_count(UUID[]) TO anon, authenticated;

DROP FUNCTION IF EXISTS track_deal_click(UUID);
CREATE OR REPLACE FUNCTION track_deal_click(p_deal_id UUID)
RETURNS VOID
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE deals SET click_count = click_count + 1 WHERE id = p_deal_id;
$$;
GRANT EXECUTE ON FUNCTION track_deal_click(UUID) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- VERIFY:
-- SELECT list_active_deals(6, NULL);
-- SELECT my_deals();
-- =====================================================
