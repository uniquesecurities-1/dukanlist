-- =====================================================
-- db/83-add-mansa-muktsar-sub-towns.sql
-- =====================================================
-- USER REQUEST (2026-05-31):
--   "Sirsa/Bathinda ke saath sirf Mansa + sub cities, Muktsar + sub cities
--    (Punjab) tak hi update krdo abhi."
--
-- WHAT THIS DOES:
--   1. Activates Mansa + Muktsar districts (Punjab) — were deactivated by db/21
--   2. Adds 6 sub-towns of Mansa district (Sardulgarh, Budhlada, Bhikhi,
--      Jhunir, Boha, Joga) — all with pincode + lat/lng + active=TRUE
--   3. Adds 5 sub-towns of Muktsar district (Malout, Gidderbaha, Doda,
--      Lambi, Badhni Kalan)
--   4. Existing Mansa + Muktsar district HQ cities (added in db/04)
--      are activated (active = TRUE)
--
-- AFTER THIS:
--   register.html / search.html / browse.html dropdowns will show:
--     • Sirsa (HR) — Mandi Dabwali, Sirsa, Ellenabad, Rania, Kalanwali
--     • Fatehabad (HR) — Fatehabad, Ratia  [if active, else inactive]
--     • Bathinda (PB) — Bathinda
--     • Mansa (PB) — Mansa, Sardulgarh, Budhlada, Bhikhi, Jhunir, Boha, Joga
--     • Muktsar (PB) — Muktsar, Malout, Gidderbaha, Doda, Lambi, Badhni Kalan
--
-- IDEMPOTENT: safe to re-run. Uses ON CONFLICT DO NOTHING + WHERE clauses.
-- =====================================================

BEGIN;

-- ============================================================
-- 1. Activate Mansa + Muktsar districts (Punjab)
-- ============================================================
UPDATE geo_districts
  SET active = TRUE
  WHERE name IN ('Mansa', 'Muktsar')
    AND state_id = (SELECT id FROM geo_states WHERE code = 'PB');


-- ============================================================
-- 2. Activate the existing district-HQ cities (Mansa + Muktsar)
--    These were inserted by db/04 but deactivated by db/21
-- ============================================================
UPDATE geo_cities
  SET active = TRUE
  WHERE name IN ('Mansa', 'Muktsar')
    AND district_id IN (
      SELECT id FROM geo_districts
      WHERE name IN ('Mansa', 'Muktsar')
        AND state_id = (SELECT id FROM geo_states WHERE code = 'PB')
    );


-- ============================================================
-- 3. Add sub-towns of MANSA district
-- ============================================================
INSERT INTO geo_cities (district_id, name, name_hi, pincodes, lat, lng, active)
SELECT d.id, v.city, v.city_hi, v.pins::TEXT[], v.lat::numeric, v.lng::numeric, TRUE
FROM (VALUES
  ('Sardulgarh',  'सरदूलगढ़',  '{151507}',  29.6961, 75.2406),
  ('Budhlada',    'बुढलाडा',   '{151502}',  29.9275, 75.5567),
  ('Bhikhi',      'भीखी',     '{151506}',  30.0467, 75.5375),
  ('Jhunir',      'झुनीर',    '{151509}',  29.8167, 75.4500),
  ('Boha',        'बोहा',     '{151501}',  29.8333, 75.3000),
  ('Joga',        'जोगा',     '{151508}',  29.8500, 75.3500)
) AS v(city, city_hi, pins, lat, lng)
JOIN geo_districts d ON d.name = 'Mansa'
  AND d.state_id = (SELECT id FROM geo_states WHERE code = 'PB')
ON CONFLICT (district_id, name) DO UPDATE
  SET active = TRUE,
      name_hi = EXCLUDED.name_hi,
      pincodes = EXCLUDED.pincodes,
      lat = EXCLUDED.lat,
      lng = EXCLUDED.lng;


-- ============================================================
-- 4. Add sub-towns of MUKTSAR district
-- ============================================================
INSERT INTO geo_cities (district_id, name, name_hi, pincodes, lat, lng, active)
SELECT d.id, v.city, v.city_hi, v.pins::TEXT[], v.lat::numeric, v.lng::numeric, TRUE
FROM (VALUES
  ('Malout',        'मलोट',         '{152107}',  30.1981, 74.4842),
  ('Gidderbaha',    'गिद्दड़बाहा',  '{152101}',  30.2025, 74.6628),
  ('Doda',          'डोडा',         '{152111}',  30.1500, 74.3833),
  ('Lambi',         'लंबी',         '{152128}',  30.0419, 74.5836),
  ('Badhni Kalan',  'बढ़नी कलां',   '{152110}',  30.2667, 74.7333)
) AS v(city, city_hi, pins, lat, lng)
JOIN geo_districts d ON d.name = 'Muktsar'
  AND d.state_id = (SELECT id FROM geo_states WHERE code = 'PB')
ON CONFLICT (district_id, name) DO UPDATE
  SET active = TRUE,
      name_hi = EXCLUDED.name_hi,
      pincodes = EXCLUDED.pincodes,
      lat = EXCLUDED.lat,
      lng = EXCLUDED.lng;


NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- VERIFY
-- =====================================================
DO $$
DECLARE
  v_mansa_count   INT;
  v_muktsar_count INT;
BEGIN
  SELECT COUNT(*) INTO v_mansa_count
    FROM geo_cities c
    JOIN geo_districts d ON d.id = c.district_id
    WHERE d.name = 'Mansa'
      AND d.state_id = (SELECT id FROM geo_states WHERE code = 'PB')
      AND c.active = TRUE;

  SELECT COUNT(*) INTO v_muktsar_count
    FROM geo_cities c
    JOIN geo_districts d ON d.id = c.district_id
    WHERE d.name = 'Muktsar'
      AND d.state_id = (SELECT id FROM geo_states WHERE code = 'PB')
      AND c.active = TRUE;

  RAISE NOTICE '✅ Active Mansa cities:   % (expected: 7 — HQ + 6 sub-towns)', v_mansa_count;
  RAISE NOTICE '✅ Active Muktsar cities: % (expected: 6 — HQ + 5 sub-towns)', v_muktsar_count;
END $$;

-- =====================================================
-- POST-DEPLOY SANITY CHECK (run manually if you want)
-- =====================================================
-- See all active cities:
--   SELECT s.code AS state, d.name AS district, c.name AS city, c.pincodes
--   FROM geo_cities c
--   JOIN geo_districts d ON d.id = c.district_id
--   JOIN geo_states s ON s.id = d.state_id
--   WHERE c.active = TRUE
--   ORDER BY s.code, d.name, c.name;
