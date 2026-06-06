-- =====================================================
-- db/104-hotfix-suspicious-unnest-alias.sql
-- =====================================================
-- USER REPORT (2026-06-04):
--   admin/suspicious.html shows:
--     "Failed to fetch suspicious shops.
--      column 'unnest' does not exist"
--   400 Bad Request on POST /rpc/admin_get_suspicious_shops
--
-- ROOT CAUSE:
--   db/101 fixed photos_count column, but introduced a second issue:
--
--     ARRAY(
--       SELECT unnest(ARRAY[...])
--       WHERE unnest IS NOT NULL    ← THIS FAILS
--     )
--
--   PostgreSQL does NOT guarantee `unnest` becomes a referenceable
--   column name in the WHERE clause. The proper pattern is to give
--   the unnested value an explicit alias.
--
-- FIX:
--   Rewrite using `unnest(...) AS u` with `WHERE u IS NOT NULL`.
--
-- IDEMPOTENT — safe to re-run.
-- =====================================================

BEGIN;

DROP FUNCTION IF EXISTS admin_get_suspicious_shops();
CREATE OR REPLACE FUNCTION admin_get_suspicious_shops()
RETURNS TABLE (
  id              UUID,
  slug            TEXT,
  name            TEXT,
  mobile          TEXT,
  owner_name      TEXT,
  status          TEXT,
  pincode         TEXT,
  photos_count    INT,
  flagged_count   INT,
  rating_count    INT,
  verified_score  INT,
  created_at      TIMESTAMPTZ,
  risk_score      INT,
  flags           TEXT[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  RETURN QUERY
  WITH base AS (
    SELECT
      b.id, b.slug, b.name, b.mobile, b.owner_name, b.created_at,
      b.status, b.pincode,
      COALESCE(array_length(b.photos, 1), 0) AS photos_count,
      COALESCE(b.flagged_count, 0)            AS flagged_count,
      COALESCE(b.rating_count, 0)             AS rating_count,
      COALESCE(b.verified_score, 0)           AS verified_score,
      b.email, b.usp_text, b.about_text
    FROM businesses b
    WHERE b.status IN ('active', 'pending', 'pending_review', 'flagged')
  ),
  scored AS (
    SELECT
      base.*,
      -- Risk score (sum of risk patterns)
      (
        CASE WHEN EXISTS (
          SELECT 1 FROM businesses b2
           WHERE b2.id != base.id
             AND norm_mobile_10(b2.mobile) = norm_mobile_10(base.mobile)
             AND b2.status IN ('active','pending','pending_review')
        ) THEN 25 ELSE 0 END
        +
        CASE WHEN base.photos_count = 0 THEN 12 ELSE 0 END
        +
        CASE WHEN length(coalesce(base.owner_name, '')) < 3 THEN 18 ELSE 0 END
        +
        CASE WHEN base.owner_name IS NOT NULL
              AND base.owner_name ~* '(test|asdf|aaaa|xxx|abc)' THEN 25 ELSE 0 END
        +
        CASE WHEN base.flagged_count >= 3 THEN 22 ELSE 0 END
        +
        CASE WHEN base.created_at > NOW() - INTERVAL '24 hours'
              AND base.photos_count = 0
              AND base.rating_count = 0 THEN 15 ELSE 0 END
        +
        CASE WHEN base.verified_score >= 3 AND base.photos_count = 0 THEN 20 ELSE 0 END
      ) AS risk_score,
      -- Flag list — FIXED: explicit alias on unnest
      ARRAY(
        SELECT f
        FROM unnest(ARRAY[
          CASE WHEN EXISTS (
            SELECT 1 FROM businesses b3
             WHERE b3.id != base.id
               AND norm_mobile_10(b3.mobile) = norm_mobile_10(base.mobile)
               AND b3.status IN ('active','pending','pending_review')
          ) THEN 'duplicate_mobile' END,
          CASE WHEN base.photos_count = 0 THEN 'no_photos' END,
          CASE WHEN length(coalesce(base.owner_name, '')) < 3 THEN 'short_owner_name' END,
          CASE WHEN base.owner_name ~* '(test|asdf|aaaa|xxx|abc)' THEN 'fake_owner_name' END,
          CASE WHEN base.flagged_count >= 3 THEN 'multiple_flags' END,
          CASE WHEN base.created_at > NOW() - INTERVAL '24 hours'
                AND base.photos_count = 0
                AND base.rating_count = 0 THEN 'bulk_new_empty' END,
          CASE WHEN base.verified_score >= 3 AND base.photos_count = 0 THEN 'verified_no_photos' END
        ]) AS f
        WHERE f IS NOT NULL
      ) AS flags
    FROM base
  )
  SELECT
    s.id, s.slug, s.name, s.mobile, s.owner_name,
    s.status, s.pincode, s.photos_count::INT, s.flagged_count::INT,
    s.rating_count::INT, s.verified_score::INT, s.created_at,
    s.risk_score::INT, s.flags
  FROM scored s
  WHERE s.risk_score > 0
  ORDER BY s.risk_score DESC, s.created_at DESC
  LIMIT 200;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_get_suspicious_shops() TO authenticated;


NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'db/104 hotfix installed.';
  RAISE NOTICE '  admin_get_suspicious_shops — unnest now properly aliased as f';
  RAISE NOTICE '  /admin/suspicious page should now load without 400 error';
END $$;
