-- ============================================================
-- db/243 — admin_create_deal(): the field team posts a shop's offer
-- ============================================================
--
-- create_deal (db/40b) posts for the signed-in OWNER's business. The
-- field team stands in the shop with Quick Add open and the owner says
-- "10% off this week" — there is no owner login there. This lets an
-- admin post an offer for any active business, with the same content
-- check and the same columns, so it shows on the home page Offers tile,
-- the shop page and the owner's own Deals panel (where they can edit
-- or delete it like their own).
--
-- Admin-only (is_admin()). Safe to re-run.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_create_deal(p_business_id UUID, p_data JSONB)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_deal_id UUID;
  v_check   JSONB;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'login required'; END IF;
  IF NOT is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF p_business_id IS NULL OR NOT EXISTS (SELECT 1 FROM businesses WHERE id = p_business_id) THEN
    RAISE EXCEPTION 'business not found';
  END IF;
  IF NULLIF(trim(COALESCE(p_data->>'title', '')), '') IS NULL THEN
    RAISE EXCEPTION 'title required';
  END IF;
  IF (p_data->>'valid_until') IS NULL THEN
    RAISE EXCEPTION 'valid_until required';
  END IF;

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
    p_business_id,
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

REVOKE ALL ON FUNCTION public.admin_create_deal(UUID, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_create_deal(UUID, JSONB) TO authenticated;

DO $$ BEGIN
  IF to_regproc('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/243-admin-create-deal.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

SELECT 'admin_create_deal exists' AS check,
       CASE WHEN to_regproc('public.admin_create_deal(uuid,jsonb)') IS NOT NULL THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'anon cannot call it',
       CASE WHEN has_function_privilege('anon', 'public.admin_create_deal(uuid,jsonb)', 'EXECUTE') THEN 'NO — tell Claude' ELSE 'yes' END;
