-- ============================================================
-- db/234 — the shop types Mandi Dabwali has and DukanList didn't
-- ============================================================
--
-- Deepak asked for Bag / Luggage. Checking the live list (368 rows,
-- 15 parents) turned up eleven more shop types that exist on every
-- bazaar street here and had nowhere to sit. Each one below was
-- searched for first — by slug and by name, in English and Hindi —
-- and is genuinely absent:
--
--   bag-luggage        nothing matched bag / luggage / suitcase
--   tailor-darzi       only "clothes | Clothes / Tailor" — a tailor is
--                      a service, not a cloth shop, and every street
--                      here has three of them
--   dry-cleaner        nothing matched laundry / dry clean
--   courier-parcel     nothing matched courier / parcel — DTDC and
--                      Blue Dart agents are in every market
--   cobbler-mochi      nothing matched mochi / cobbler
--   locksmith          nothing matched lock / key / chabi
--   cable-internet     nothing matched cable / broadband / internet
--   water-supplier     nothing matched tanker / jar (ro-repair and
--                      borewell are different trades)
--   ambulance          nothing matched ambulance
--   labour-contractor  nothing matched thekedar / labour
--   security-agency    only cctv-camera matched — guards are not cameras
--   hosiery-woollen    nothing matched hosiery / woollen / sweater
--
-- Nothing is renamed or deleted here; only inserts, and every one is
-- guarded by ON CONFLICT (slug) so re-running is harmless.
--
-- sort_order: 900+ inside each parent so these land after the
-- categories that already have shops in them.
-- ============================================================

BEGIN;

INSERT INTO public.categories (parent_id, slug, name, name_hi, icon, color, sort_order, active)
SELECT p.id, v.slug, v.name, v.name_hi, v.icon, p.color, v.sort_order, TRUE
FROM (VALUES
  -- ---------- Retail & Shopping ----------
  ('retail-shopping', 'bag-luggage',       'Bag, Suitcase & Luggage',      'बैग, सूटकेस और लगेज',        '🧳', 900::SMALLINT),
  ('retail-shopping', 'hosiery-woollen',   'Hosiery & Woollen / Sweaters',  'होज़री और ऊनी कपड़े',        '🧶', 901::SMALLINT),

  -- ---------- Home Services ----------
  ('home-services',   'tailor-darzi',      'Tailor / Darzi',                'दर्जी / सिलाई',              '✂️', 900::SMALLINT),
  ('home-services',   'dry-cleaner',       'Dry Cleaner & Laundry',         'ड्राई क्लीनर और लॉन्ड्री',    '🧺', 901::SMALLINT),
  ('home-services',   'cobbler-mochi',     'Cobbler / Mochi',               'मोची / जूता मरम्मत',         '👞', 902::SMALLINT),
  ('home-services',   'locksmith',         'Locksmith / Key Maker',         'ताला-चाबी वाला',             '🔑', 903::SMALLINT),
  ('home-services',   'water-supplier',    'Water Supplier (Jar / Tanker)', 'पानी सप्लाई (जार/टैंकर)',    '🚰', 904::SMALLINT),
  ('home-services',   'cable-internet',    'Cable TV & Internet / Broadband','केबल टीवी और इंटरनेट',      '📡', 905::SMALLINT),

  -- ---------- Professional Services ----------
  ('professional-services', 'courier-parcel',     'Courier & Parcel Service', 'कूरियर और पार्सल सेवा',    '📦', 900::SMALLINT),
  ('professional-services', 'labour-contractor',  'Labour Contractor / Thekedar','लेबर ठेकेदार',          '👷', 901::SMALLINT),
  ('professional-services', 'security-agency',    'Security Guard Agency',    'सिक्योरिटी गार्ड एजेंसी',   '🛡️', 902::SMALLINT),

  -- ---------- Healthcare & Medical ----------
  ('healthcare',      'ambulance',         'Ambulance Service',             'एम्बुलेंस सेवा',             '🚑', 900::SMALLINT)
) AS v(parent_slug, slug, name, name_hi, icon, sort_order)
JOIN public.categories p
  ON p.slug = v.parent_slug AND p.parent_id IS NULL
ON CONFLICT (slug) DO NOTHING;

-- Record this migration in the register (db/233). Guarded so the file
-- still runs cleanly on a database where 233 has not been applied.
DO $$ BEGIN
  IF to_regproc('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/234-add-missing-town-categories.sql');
  END IF;
END $$;

COMMIT;

-- ============================================================
-- All twelve should be listed below, each under the right parent.
-- (business_count is 0 for a brand-new category and stays 0 until a
-- shop picks it — it is not a sign of whether this run inserted it.)
-- ============================================================
SELECT
  c.slug,
  c.name,
  p.name          AS under,
  c.business_count AS shops
FROM public.categories c
JOIN public.categories p ON p.id = c.parent_id
WHERE c.slug IN (
  'bag-luggage','hosiery-woollen','tailor-darzi','dry-cleaner','cobbler-mochi',
  'locksmith','water-supplier','cable-internet','courier-parcel',
  'labour-contractor','security-agency','ambulance'
)
ORDER BY p.sort_order, c.sort_order;
