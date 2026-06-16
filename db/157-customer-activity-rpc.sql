-- ============================================================
-- db/157 — Customer activity counter (24h call + WhatsApp)
-- ============================================================
-- Bug:
--   business.html's loadCustomerActivity() was doing two HEAD count
--   queries directly against `leads` table:
--     c.from('leads').select('id',{count:'exact',head:true})
--   Two problems:
--     1. The table is actually named `leads_log` (db/01 schema), NOT
--        `leads` — so PostgREST returned 404 (Not Found). Two 404
--        errors per page-load on every public business profile.
--     2. Even with the right name, RLS on leads_log (db/02 line 97)
--        restricts SELECT to the business owner — anon users would
--        get 0 rows back regardless.
--
-- Fix:
--   New SECURITY DEFINER RPC that aggregates counts server-side and
--   returns only the totals (no PII, no PIIable rows). Anon-callable.
--   business.html replaces the two direct queries with one RPC call.
--
-- Privacy:
--   Returned values are tiny non-identifying integers ("5 customers
--   called in last 24h"). No phone, no name, no IP exposed. The RPC
--   filters by business_id only — caller cannot enumerate other
--   businesses' counts unless they already know the UUID, which is
--   public anyway via the listing URL.
--
-- SAFE: No schema change. Re-runnable CREATE OR REPLACE.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public_customer_activity_24h(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_calls INT := 0;
  v_wa    INT := 0;
BEGIN
  IF p_business_id IS NULL THEN
    RETURN jsonb_build_object('calls', 0, 'whatsapp', 0);
  END IF;

  SELECT COUNT(*)::INT INTO v_calls
  FROM leads_log
  WHERE business_id = p_business_id
    AND action = 'call'
    AND created_at >= NOW() - INTERVAL '24 hours';

  SELECT COUNT(*)::INT INTO v_wa
  FROM leads_log
  WHERE business_id = p_business_id
    AND action IN ('whatsapp', 'wa')
    AND created_at >= NOW() - INTERVAL '24 hours';

  RETURN jsonb_build_object(
    'calls',    v_calls,
    'whatsapp', v_wa,
    'total',    v_calls + v_wa
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public_customer_activity_24h(UUID) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/157 installed. public_customer_activity_24h RPC live.';
END $$;
