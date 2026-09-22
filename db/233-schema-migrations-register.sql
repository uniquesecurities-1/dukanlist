-- ============================================================
-- db/233 — the migration register: which db/*.sql actually ran
-- ============================================================
--
-- WHY
--   There are 240 files in db/ and, until now, no record of which
--   were applied. That is not a tidiness problem — it cost real
--   bugs this week:
--     db/219  ran, half of it silently did nothing
--     db/112b table created, five functions never landed
--     db/224  ran, then db/223 was run AFTER it and overwrote
--             get_shop_rank, losing the movement fields
--   Every one of those was "did it run?" guesswork. This ends that.
--
-- WHAT IT ADDS
--   schema_migrations       one row per applied file
--   record_migration(name)  every future migration calls this as its
--                           LAST statement. Idempotent. If the file is
--                           re-run it just updates applied_at.
--
-- HOW THE REGISTER STARTS TRUTHFUL
--   It does NOT trust memory. For each recent migration it DETECTS
--   the object that only exists if that file ran — a function, a
--   table, a grant, a phrase in a function body — and records it
--   only if found, tagged 'inferred'. So the first row of this table
--   is evidence, not an assumption.
--
-- CONVENTION FROM HERE ON
--   End every db/NNN-*.sql with:
--       SELECT public.record_migration('db/NNN-name.sql');
--   and check the register with:
--       SELECT * FROM public.schema_migrations ORDER BY applied_at DESC;
--
-- Safe to re-run.
-- ============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.schema_migrations (
  filename    TEXT PRIMARY KEY,
  applied_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  source      TEXT NOT NULL DEFAULT 'recorded',   -- 'recorded' | 'inferred'
  notes       TEXT
);

-- The register is the admin's business only.
ALTER TABLE public.schema_migrations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.schema_migrations FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.record_migration(p_filename TEXT, p_notes TEXT DEFAULT NULL)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.schema_migrations (filename, source, notes)
  VALUES (p_filename, 'recorded', p_notes)
  ON CONFLICT (filename) DO UPDATE
    SET applied_at = NOW(), source = 'recorded',
        notes = COALESCE(EXCLUDED.notes, public.schema_migrations.notes);
  RETURN 'recorded ' || p_filename;
END;
$$;
-- Only ever called from the SQL editor by the admin — not from the app.
REVOKE ALL ON FUNCTION public.record_migration(TEXT, TEXT) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- Inferred backfill: record a migration ONLY if its fingerprint
-- is present. Absence means "not applied" and nothing is written.
-- ------------------------------------------------------------
DO $$
DECLARE
  hit BOOLEAN;
  fn_body TEXT;
BEGIN
  -- db/112b — the five story RPCs
  SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_shop_active_stories') INTO hit;
  IF hit THEN INSERT INTO schema_migrations(filename,source,notes) VALUES
    ('db/112b-stories-index-fix.sql','inferred','get_shop_active_stories exists') ON CONFLICT DO NOTHING; END IF;

  -- db/219 — open write policies dropped (verified 21-Sep via db/227 PASS)
  SELECT NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname IN ('shop_likes_anon_insert','p_owners_self_insert')) INTO hit;
  IF hit THEN INSERT INTO schema_migrations(filename,source,notes) VALUES
    ('db/219-security-hardening.sql','inferred','open policies absent; note: its column REVOKEs were no-ops, fixed by db/225') ON CONFLICT DO NOTHING; END IF;

  -- db/221 — ranking v1 engine
  SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'dl_shop_score') INTO hit;
  IF hit THEN INSERT INTO schema_migrations(filename,source,notes) VALUES
    ('db/221-ranking-engine.sql','inferred','dl_shop_score exists') ON CONFLICT DO NOTHING; END IF;

  -- db/222 — photo single source
  SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'sync_business_photos_array') INTO hit;
  IF hit THEN INSERT INTO schema_migrations(filename,source,notes) VALUES
    ('db/222-photo-single-source.sql','inferred','sync_business_photos_array exists') ON CONFLICT DO NOTHING; END IF;

  -- db/223 — ranking v2
  SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'dl_shop_score_v2') INTO hit;
  IF hit THEN INSERT INTO schema_migrations(filename,source,notes) VALUES
    ('db/223-ranking-v2.sql','inferred','dl_shop_score_v2 exists') ON CONFLICT DO NOTHING; END IF;

  -- db/224 — rank history table (+ movement fields, re-run after 223 overwrote them)
  SELECT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'rank_snapshots') INTO hit;
  IF hit THEN
    SELECT prosrc INTO fn_body FROM pg_proc WHERE proname = 'get_shop_rank' LIMIT 1;
    INSERT INTO schema_migrations(filename,source,notes) VALUES
      ('db/224-rank-history.sql','inferred',
       CASE WHEN fn_body LIKE '%rank_change%' THEN 'rank_snapshots exists; get_shop_rank has movement fields'
            ELSE 'rank_snapshots exists BUT get_shop_rank lacks movement — 223 ran after 224; re-run 224' END)
    ON CONFLICT DO NOTHING;
  END IF;

  -- db/225 — column locks actually applied (anon cannot SELECT businesses.email)
  SELECT NOT EXISTS (SELECT 1 FROM information_schema.column_privileges
                      WHERE table_schema='public' AND table_name='businesses'
                        AND column_name='email' AND grantee='anon' AND privilege_type='SELECT') INTO hit;
  IF hit THEN INSERT INTO schema_migrations(filename,source,notes) VALUES
    ('db/225-column-grants-actually-apply.sql','inferred','anon lacks SELECT on businesses.email') ON CONFLICT DO NOTHING; END IF;

  -- db/226 — get_homepage_buzz fixed (v_city_id INT)
  SELECT prosrc INTO fn_body FROM pg_proc WHERE proname = 'get_homepage_buzz' LIMIT 1;
  IF fn_body LIKE '%v_city_id INT%' THEN INSERT INTO schema_migrations(filename,source,notes) VALUES
    ('db/226-fix-homepage-buzz.sql','inferred','get_homepage_buzz declares v_city_id INT') ON CONFLICT DO NOTHING; END IF;

  -- db/228 — /top card data
  SELECT prosrc INTO fn_body FROM pg_proc WHERE proname = 'get_top_for_seo' LIMIT 1;
  IF fn_body LIKE '%cat_rank%' THEN INSERT INTO schema_migrations(filename,source,notes) VALUES
    ('db/228-top-cards-data.sql','inferred','get_top_for_seo returns cat_rank') ON CONFLICT DO NOTHING; END IF;

  -- db/229 — Restaurants rename
  SELECT EXISTS (SELECT 1 FROM categories WHERE slug='restaurant' AND name='Restaurants') INTO hit;
  IF hit THEN INSERT INTO schema_migrations(filename,source,notes) VALUES
    ('db/229-rename-restaurant-category.sql','inferred','categories.restaurant name = Restaurants') ON CONFLICT DO NOTHING; END IF;

  -- db/230 — soft-listed claimed flag fixed
  SELECT prosrc INTO fn_body FROM pg_proc WHERE proname = 'admin_recent_soft_listed' LIMIT 1;
  IF fn_body LIKE '%auth_user_id IS NOT NULL%' THEN INSERT INTO schema_migrations(filename,source,notes) VALUES
    ('db/230-fix-soft-listed-claimed-flag.sql','inferred','admin_recent_soft_listed checks auth_user_id IS NOT NULL') ON CONFLICT DO NOTHING; END IF;

  -- db/231 — photo limit 8
  SELECT prosrc INTO fn_body FROM pg_proc WHERE proname = 'enforce_photo_limit' LIMIT 1;
  IF fn_body LIKE '%>= 8%' THEN INSERT INTO schema_migrations(filename,source,notes) VALUES
    ('db/231-raise-photo-limit-to-8.sql','inferred','enforce_photo_limit says >= 8') ON CONFLICT DO NOTHING; END IF;

  -- db/232 — bad mobiles cleanup (only detectable if it unverified at least one)
  SELECT EXISTS (SELECT 1 FROM businesses WHERE mobile_verified_by = 'auto-cleanup:db-232') INTO hit;
  IF hit THEN INSERT INTO schema_migrations(filename,source,notes) VALUES
    ('db/232-unverify-bad-mobiles.sql','inferred','rows tagged auto-cleanup:db-232') ON CONFLICT DO NOTHING; END IF;
END $$;

COMMIT;

-- This file records itself, as every file from now on will.
SELECT public.record_migration('db/233-schema-migrations-register.sql', 'register created; earlier rows inferred from live objects');

-- The register, newest first. Anything from db/219 onward that is
-- MISSING here was not detected in the database — i.e. not applied.
SELECT filename, source, applied_at, notes
FROM public.schema_migrations
ORDER BY filename DESC;
