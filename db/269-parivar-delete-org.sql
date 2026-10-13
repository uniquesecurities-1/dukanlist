-- ============================================================
-- db/269 — Dabwali Parivar: office can delete an organisation (with Undo)
-- ============================================================
-- Deepak, 13 Oct: a demo organisation can't be deleted.
--   * admin_parivar_delete_org(id, typed_name): the office must type the organisation's
--     exact name to confirm (protects real organisations from a slip of the mouse)
--   * before deleting, the organisation, its member/office-bearer list (all sessions) and its
--     change log are copied into parivar_deleted_orgs, so it can be brought back
--   * the PEOPLE stay in Dabwali Parivar — only their membership of this organisation goes;
--     its manager link stops working
-- Safe to re-run.

BEGIN;

CREATE TABLE IF NOT EXISTS public.parivar_deleted_orgs (
  id          BIGSERIAL PRIMARY KEY,
  org_id      UUID        NOT NULL,
  name        TEXT,
  snapshot    JSONB       NOT NULL,
  roles       JSONB       NOT NULL DEFAULT '[]'::jsonb,
  changes     JSONB       NOT NULL DEFAULT '[]'::jsonb,
  deleted_by  UUID,
  deleted_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  restored_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_pv_deleted_orgs_at ON public.parivar_deleted_orgs (deleted_at DESC);
ALTER TABLE public.parivar_deleted_orgs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.parivar_deleted_orgs FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_delete_org(p_org_id UUID, p_confirm_name TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE o parivar_orgs; v_id BIGINT; v_n INT;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO o FROM parivar_orgs WHERE id = p_org_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'organisation not found'; END IF;
  IF lower(btrim(COALESCE(p_confirm_name, ''))) <> lower(btrim(o.name)) THEN
    RAISE EXCEPTION 'The name you typed does not match "%". Nothing was deleted.', o.name;
  END IF;
  SELECT COUNT(DISTINCT person_id) INTO v_n FROM parivar_org_roles WHERE org_id = o.id;
  INSERT INTO parivar_deleted_orgs (org_id, name, snapshot, roles, changes, deleted_by)
  VALUES (o.id, o.name, to_jsonb(o),
          COALESCE((SELECT jsonb_agg(to_jsonb(r)) FROM parivar_org_roles r WHERE r.org_id = o.id), '[]'::jsonb),
          COALESCE((SELECT jsonb_agg(to_jsonb(c)) FROM parivar_org_changes c WHERE c.org_id = o.id), '[]'::jsonb),
          auth.uid())
  RETURNING id INTO v_id;
  DELETE FROM parivar_orgs WHERE id = o.id;
  RETURN jsonb_build_object('ok', TRUE, 'archive_id', v_id, 'name', o.name, 'members', v_n);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_delete_org(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_delete_org(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_restore_org(p_archive_id BIGINT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE a parivar_deleted_orgs; v parivar_orgs; v_n INT;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO a FROM parivar_deleted_orgs WHERE id = p_archive_id FOR UPDATE;
  IF a.id IS NULL THEN RAISE EXCEPTION 'not found'; END IF;
  IF a.restored_at IS NOT NULL THEN RAISE EXCEPTION 'already brought back'; END IF;
  v := jsonb_populate_record(NULL::parivar_orgs, a.snapshot);
  IF EXISTS (SELECT 1 FROM parivar_orgs WHERE id = v.id) THEN RAISE EXCEPTION 'this organisation already exists'; END IF;
  IF EXISTS (SELECT 1 FROM parivar_orgs WHERE slug = v.slug) THEN v.slug := public._parivar_slug(v.name, 'parivar_orgs'); END IF;
  IF v.contact_person_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM parivar_people WHERE id = v.contact_person_id) THEN v.contact_person_id := NULL; END IF;
  IF v.contact_business_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM businesses WHERE id = v.contact_business_id) THEN v.contact_business_id := NULL; END IF;
  INSERT INTO parivar_orgs SELECT v.*;
  -- members come back only if the person still exists
  INSERT INTO parivar_org_roles
  SELECT r.* FROM jsonb_populate_recordset(NULL::parivar_org_roles, a.roles) r
   WHERE EXISTS (SELECT 1 FROM parivar_people p WHERE p.id = r.person_id)
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  INSERT INTO parivar_org_changes
  SELECT c.* FROM jsonb_populate_recordset(NULL::parivar_org_changes, a.changes) c
  ON CONFLICT DO NOTHING;
  INSERT INTO parivar_org_changes (org_id, by_name, action) VALUES (v.id, 'Office', 'organisation_restored');
  UPDATE parivar_deleted_orgs SET restored_at = NOW() WHERE id = a.id;
  RETURN jsonb_build_object('ok', TRUE, 'id', v.id, 'name', v.name, 'slug', v.slug, 'roles_back', v_n);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_restore_org(BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_restore_org(BIGINT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_recently_deleted_orgs()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name, 'at', d.deleted_at,
                                   'members', (SELECT COUNT(DISTINCT e->>'person_id') FROM jsonb_array_elements(d.roles) e)) ORDER BY d.deleted_at DESC)
                     FROM (SELECT * FROM parivar_deleted_orgs WHERE restored_at IS NULL AND deleted_at > NOW() - INTERVAL '90 days'
                            ORDER BY deleted_at DESC LIMIT 30) d), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_recently_deleted_orgs() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_recently_deleted_orgs() TO authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/269-parivar-delete-org.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Checks — every row should say yes
SELECT 'delete keeps a copy for Undo' AS check,
       CASE WHEN to_regclass('public.parivar_deleted_orgs') IS NOT NULL AND to_regprocedure('public.admin_parivar_restore_org(bigint)') IS NOT NULL THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'only the office can delete',
       CASE WHEN NOT has_function_privilege('anon', 'public.admin_parivar_delete_org(uuid,text)', 'EXECUTE')
             AND NOT has_table_privilege('anon', 'public.parivar_deleted_orgs', 'SELECT') THEN 'yes' ELSE 'NO — tell Claude' END;
