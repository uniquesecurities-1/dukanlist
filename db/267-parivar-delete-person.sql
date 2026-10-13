-- ============================================================
-- db/267 — Dabwali Parivar: office can delete a person (with Undo)
-- ============================================================
-- Deepak, 13 Oct: someone added by mistake, with no organisation, can't be deleted.
--   * admin_parivar_delete_person(id): only when the person is in NO organisation
--     (any session) — otherwise it says which ones to remove them from first
--   * before deleting, the person and their firm links are copied into
--     parivar_deleted_people, so the office can bring them back (Undo / Recently deleted)
--   * their personal profile links stop working (they belonged to that person);
--     an organisation that had them as contact person keeps its contact name/number
-- Safe to re-run.

BEGIN;

CREATE TABLE IF NOT EXISTS public.parivar_deleted_people (
  id          BIGSERIAL PRIMARY KEY,
  person_id   UUID        NOT NULL,
  full_name   TEXT,
  snapshot    JSONB       NOT NULL,
  firms       JSONB       NOT NULL DEFAULT '[]'::jsonb,
  deleted_by  UUID,
  deleted_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  restored_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_pv_deleted_at ON public.parivar_deleted_people (deleted_at DESC);
ALTER TABLE public.parivar_deleted_people ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.parivar_deleted_people FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_delete_person(p_person_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE p parivar_people; v_orgs TEXT; v_id BIGINT;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO p FROM parivar_people WHERE id = p_person_id FOR UPDATE;
  IF p.id IS NULL THEN RAISE EXCEPTION 'person not found'; END IF;
  SELECT string_agg(DISTINCT o.name, ', ') INTO v_orgs
    FROM parivar_org_roles r JOIN parivar_orgs o ON o.id = r.org_id WHERE r.person_id = p.id;
  IF v_orgs IS NOT NULL THEN
    RAISE EXCEPTION '% is still in: %. Remove them from there first (organisation → ✕), then delete.', p.full_name, v_orgs;
  END IF;
  INSERT INTO parivar_deleted_people (person_id, full_name, snapshot, firms, deleted_by)
  VALUES (p.id, p.full_name, to_jsonb(p),
          COALESCE((SELECT jsonb_agg(to_jsonb(f)) FROM parivar_firm_roles f WHERE f.person_id = p.id), '[]'::jsonb), auth.uid())
  RETURNING id INTO v_id;
  DELETE FROM parivar_people WHERE id = p.id;
  RETURN jsonb_build_object('ok', TRUE, 'archive_id', v_id, 'name', p.full_name);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_delete_person(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_delete_person(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_restore_person(p_archive_id BIGINT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
DECLARE a parivar_deleted_people; v parivar_people;
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO a FROM parivar_deleted_people WHERE id = p_archive_id FOR UPDATE;
  IF a.id IS NULL THEN RAISE EXCEPTION 'not found'; END IF;
  IF a.restored_at IS NOT NULL THEN RAISE EXCEPTION 'already brought back'; END IF;
  v := jsonb_populate_record(NULL::parivar_people, a.snapshot);
  IF EXISTS (SELECT 1 FROM parivar_people WHERE id = v.id) THEN RAISE EXCEPTION 'this person already exists'; END IF;
  IF v.mobile IS NOT NULL AND EXISTS (SELECT 1 FROM parivar_people WHERE mobile = v.mobile) THEN
    RAISE EXCEPTION 'mobile % now belongs to someone else in Dabwali Parivar', v.mobile;
  END IF;
  IF EXISTS (SELECT 1 FROM parivar_people WHERE slug = v.slug) THEN v.slug := public._parivar_slug(v.full_name, 'parivar_people'); END IF;
  INSERT INTO parivar_people SELECT v.*;
  INSERT INTO parivar_firm_roles
  SELECT f.* FROM jsonb_populate_recordset(NULL::parivar_firm_roles, a.firms) f
   WHERE f.business_id IS NULL OR EXISTS (SELECT 1 FROM businesses b WHERE b.id = f.business_id)
  ON CONFLICT DO NOTHING;
  UPDATE parivar_deleted_people SET restored_at = NOW() WHERE id = a.id;
  RETURN jsonb_build_object('ok', TRUE, 'id', v.id, 'name', v.full_name, 'slug', v.slug);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_restore_person(BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_restore_person(BIGINT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_parivar_recently_deleted()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp AS $$
BEGIN
  IF NOT public._dl_is_admin_uid() THEN RAISE EXCEPTION 'admin only'; END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id', d.id, 'name', d.full_name, 'mobile', d.snapshot->>'mobile', 'at', d.deleted_at) ORDER BY d.deleted_at DESC)
                     FROM (SELECT * FROM parivar_deleted_people WHERE restored_at IS NULL AND deleted_at > NOW() - INTERVAL '90 days'
                            ORDER BY deleted_at DESC LIMIT 30) d), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_parivar_recently_deleted() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_parivar_recently_deleted() TO authenticated;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/267-parivar-delete-person.sql');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Checks — every row should say yes
SELECT 'delete keeps a copy for Undo' AS check,
       CASE WHEN to_regclass('public.parivar_deleted_people') IS NOT NULL AND to_regprocedure('public.admin_parivar_restore_person(bigint)') IS NOT NULL THEN 'yes' ELSE 'NO — tell Claude' END AS result
UNION ALL
SELECT 'only the office can delete',
       CASE WHEN NOT has_function_privilege('anon', 'public.admin_parivar_delete_person(uuid)', 'EXECUTE')
             AND NOT has_table_privilege('anon', 'public.parivar_deleted_people', 'SELECT') THEN 'yes' ELSE 'NO — tell Claude' END;
