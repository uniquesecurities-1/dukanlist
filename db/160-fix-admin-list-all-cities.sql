-- ============================================================
-- db/160 — Hotfix: admin_list_all_cities references nonexistent column
-- ============================================================
-- Problem:
--   db/19's admin_list_all_cities() does:
--     SELECT c.id, c.name, c.district_id, d.name, c.state_id, s.name
--     FROM geo_cities c
--     LEFT JOIN geo_states s ON s.id = c.state_id
--   But geo_cities (db/01 schema) has NO state_id column — only
--   district_id. state_id lives on geo_districts. So the function
--   has been returning 400 (Bad Request) silently since day one.
--   Frontend caught the error and treated ALL_CITIES as empty, so
--   the City Moderator picker was always empty too.
--
--   Now that db/158 + db/159 cleared the OTHER admin-page errors,
--   this long-hidden 400 is the only console noise left.
--
-- Fix:
--   Route state_id through geo_districts:
--     LEFT JOIN geo_states s ON s.id = d.state_id  ← d not c
--   Result column "state_id" now sourced from d.state_id (SMALLINT,
--   matching the RETURN TABLE type).
--
-- SAFE: CREATE OR REPLACE. No schema changes. Signature unchanged.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION admin_list_all_cities()
RETURNS TABLE (
  id            INT,
  name          TEXT,
  district_id   INT,
  district_name TEXT,
  state_id      SMALLINT,
  state_name    TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  RETURN QUERY
  SELECT
    c.id,
    c.name,
    c.district_id,
    d.name,
    d.state_id,        -- ← was c.state_id (column doesn't exist)
    s.name
  FROM geo_cities c
  LEFT JOIN geo_districts d ON d.id = c.district_id
  LEFT JOIN geo_states s    ON s.id = d.state_id
  WHERE c.active = TRUE
  ORDER BY s.name, d.name, c.name;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_list_all_cities() TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE 'db/160 hotfix applied. admin_list_all_cities now routes state_id via geo_districts.';
END $$;
