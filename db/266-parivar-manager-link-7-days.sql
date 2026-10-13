-- ============================================================
-- db/266 — Sanstha Manager link: 7 days instead of 30
-- ============================================================
-- Deepak, 13 Oct: 30 days is too long. New manager links last 7 days (never more),
-- and links already sent are cut to 7 days from when they were sent
-- (one sent more than 7 days ago stops working now). Safe to re-run.

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_parivar_create_manager_link(p_org_id UUID, p_person_id UUID, p_days INT DEFAULT 7)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE p parivar_people; v_token TEXT; v_exp TIMESTAMPTZ;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF NOT EXISTS (SELECT 1 FROM parivar_orgs WHERE id = p_org_id) THEN RAISE EXCEPTION 'organisation not found'; END IF;
  SELECT * INTO p FROM parivar_people WHERE id = p_person_id;
  IF p.id IS NULL THEN RAISE EXCEPTION 'pick the person who will manage it'; END IF;
  IF p.mobile IS NULL THEN RAISE EXCEPTION 'add their mobile number first — the link is sent to it'; END IF;
  UPDATE parivar_org_manager_links SET revoked_at = NOW() WHERE org_id = p_org_id AND revoked_at IS NULL;
  v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  v_exp := NOW() + make_interval(days => GREATEST(1, LEAST(COALESCE(p_days, 7), 7)));
  INSERT INTO parivar_org_manager_links (org_id, person_id, sent_to_name, token_hash, created_by, expires_at)
  VALUES (p_org_id, p.id, p.full_name, encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), auth.uid(), v_exp);
  INSERT INTO parivar_org_changes (org_id, by_name, action, detail)
  VALUES (p_org_id, 'Office', 'manager_link_sent', jsonb_build_object('to', p.full_name, 'expires', v_exp));
  RETURN jsonb_build_object('token', v_token, 'name', p.full_name, 'mobile', p.mobile, 'expires_at', v_exp);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_create_manager_link(UUID, UUID, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_create_manager_link(UUID, UUID, INT) TO authenticated;

UPDATE public.parivar_org_manager_links
   SET expires_at = created_at + INTERVAL '7 days'
 WHERE revoked_at IS NULL AND expires_at > created_at + INTERVAL '7 days';

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/266-parivar-manager-link-7-days.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Checks — first row yes; second lists the live manager links and when they end
SELECT 'new manager links last at most 7 days' AS check,
       CASE WHEN pg_get_functiondef('public.admin_parivar_create_manager_link(uuid,uuid,integer)'::regprocedure) LIKE '%LEAST(COALESCE(p_days, 7), 7)%' THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'live links now end',
       COALESCE((SELECT string_agg(o.name || ' → ' || l.sent_to_name || ' till ' || to_char(l.expires_at AT TIME ZONE 'Asia/Kolkata', 'DD Mon HH24:MI'), '; ')
                   FROM public.parivar_org_manager_links l JOIN public.parivar_orgs o ON o.id = l.org_id
                  WHERE l.revoked_at IS NULL AND l.expires_at > NOW()), 'none');
