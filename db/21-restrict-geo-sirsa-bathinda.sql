-- =====================================================
-- 21-restrict-geo-sirsa-bathinda.sql
-- Restrict launch to Sirsa (HR) + Bathinda (PB) districts
-- =====================================================
-- WHAT THIS DOES:
--   1. Deactivates ALL existing cities/districts/states (active = FALSE)
--   2. Reactivates ONLY: Haryana → Sirsa district, Punjab → Bathinda district
--   3. Adds MISSING cities under both districts
--   4. Adds 8-10 major localities per city
--
-- AFTER THIS, register form will only show Sirsa + Bathinda areas.
-- Other states can be re-activated later via SQL (set active = TRUE).
--
-- PREREQUISITES: 01-20 SQL files executed
-- HOW TO RUN: Paste in Supabase SQL Editor → Run
-- IDEMPOTENT: Uses ON CONFLICT, safe to re-run.
-- =====================================================


-- =====================================================
-- SECTION 1: Deactivate all geo (we'll selectively reactivate)
-- =====================================================
UPDATE geo_states     SET active = FALSE WHERE active = TRUE;
UPDATE geo_districts  SET active = FALSE WHERE active = TRUE;
UPDATE geo_cities     SET active = FALSE WHERE active = TRUE;


-- =====================================================
-- SECTION 2: Reactivate Haryana + Sirsa district
-- =====================================================
UPDATE geo_states
  SET active = TRUE
  WHERE code = 'HR';

UPDATE geo_districts
  SET active = TRUE
  WHERE name = 'Sirsa'
    AND state_id = (SELECT id FROM geo_states WHERE code = 'HR');


-- =====================================================
-- SECTION 3: Reactivate Punjab + Bathinda district
-- =====================================================
UPDATE geo_states
  SET active = TRUE
  WHERE code = 'PB';

UPDATE geo_districts
  SET active = TRUE
  WHERE name = 'Bathinda'
    AND state_id = (SELECT id FROM geo_states WHERE code = 'PB');


-- =====================================================
-- SECTION 4: Add MISSING cities under Sirsa district
-- =====================================================
INSERT INTO geo_cities (district_id, name, name_hi, pincodes, lat, lng, active)
SELECT d.id, v.city, v.city_hi, v.pins::TEXT[], v.lat::numeric, v.lng::numeric, TRUE
FROM (VALUES
  ('Mandi Dabwali',      'मंडी डबवाली',  '{125104,125103}',         29.9491, 74.7448),
  ('Sirsa',              'सिरसा',         '{125055,125054,125001}', 29.5326, 75.0186),
  ('Ellenabad',          'ऐलनाबाद',      '{125102}',                29.5408, 74.6750),
  ('Rania',              'रानिया',        '{125102,125076}',         29.5167, 74.8167),
  ('Kalanwali',          'कालांवाली',     '{125201}',                29.8167, 75.1500),
  ('Odhan',              'ओढ़ान',         '{125106}',                29.8167, 75.0333),
  ('Nathusari Chopta',   'नाथूसरी चोपटा', '{125075}',               29.3667, 75.2500),
  ('Baragudha',          'बड़ागुढ़ा',     '{125051}',                29.6500, 75.3667),
  ('Chautala',           'चौटाला',        '{125102}',                29.6833, 74.6667),
  ('Naharpur',           'नाहरपुर',       '{125104}',                29.9333, 74.7167)
) AS v(city, city_hi, pins, lat, lng)
INNER JOIN geo_districts d ON d.name = 'Sirsa'
INNER JOIN geo_states s ON s.id = d.state_id AND s.code = 'HR'
ON CONFLICT DO NOTHING;

-- Ensure all Sirsa cities are active (in case they existed)
UPDATE geo_cities
  SET active = TRUE
  WHERE district_id = (
    SELECT d.id FROM geo_districts d
    JOIN geo_states s ON s.id = d.state_id
    WHERE d.name = 'Sirsa' AND s.code = 'HR'
  );


-- =====================================================
-- SECTION 5: Add MISSING cities under Bathinda district
-- =====================================================
INSERT INTO geo_cities (district_id, name, name_hi, pincodes, lat, lng, active)
SELECT d.id, v.city, v.city_hi, v.pins::TEXT[], v.lat::numeric, v.lng::numeric, TRUE
FROM (VALUES
  ('Bathinda',           'बठिंडा',        '{151001,151002,151005}', 30.2110, 74.9455),
  ('Rampura Phul',       'रामपुरा फूल',   '{151103}',                30.2667, 75.2333),
  ('Talwandi Sabo',      'तलवंडी साबो',   '{151302}',                29.9833, 75.0833),
  ('Maur',               'मौड़',           '{151509}',                30.0789, 75.2350),
  ('Sangat',             'संगत',          '{151401}',                30.1167, 74.8500),
  ('Goniana',            'गोनियाना',      '{151201}',                30.3000, 75.0167),
  ('Nathana',            'नथाना',         '{151102}',                30.3667, 75.1167),
  ('Bhagta Bhai Ka',     'भगता भाई का',   '{151206}',                30.2667, 75.0667),
  ('Phul',               'फूल',           '{151213}',                30.5833, 75.2333),
  ('Raman Mandi',        'रमन मंडी',      '{151301}',                30.0333, 75.2667)
) AS v(city, city_hi, pins, lat, lng)
INNER JOIN geo_districts d ON d.name = 'Bathinda'
INNER JOIN geo_states s ON s.id = d.state_id AND s.code = 'PB'
ON CONFLICT DO NOTHING;

-- Ensure all Bathinda cities are active
UPDATE geo_cities
  SET active = TRUE
  WHERE district_id = (
    SELECT d.id FROM geo_districts d
    JOIN geo_states s ON s.id = d.state_id
    WHERE d.name = 'Bathinda' AND s.code = 'PB'
  );


-- =====================================================
-- SECTION 6: Localities for Sirsa district cities
-- =====================================================
INSERT INTO geo_localities (city_id, name, name_hi, pincode)
SELECT c.id, l.locality, l.locality_hi, l.pincode
FROM (VALUES
  -- Mandi Dabwali (10 — already there but ensure)
  ('Mandi Dabwali','Mandi Bazar',         'मंडी बाज़ार',          '125104'),
  ('Mandi Dabwali','Chotala Road',        'चोटाला रोड',          '125104'),
  ('Mandi Dabwali','Sirsa Road',          'सिरसा रोड',           '125104'),
  ('Mandi Dabwali','Bus Stand',           'बस स्टैंड',           '125104'),
  ('Mandi Dabwali','Old Grain Market',    'पुरानी अनाज मंडी',    '125104'),
  ('Mandi Dabwali','Railway Road',        'रेलवे रोड',           '125104'),
  ('Mandi Dabwali','Hospital Road',       'अस्पताल रोड',         '125104'),
  ('Mandi Dabwali','Court Road',          'कोर्ट रोड',           '125104'),
  ('Mandi Dabwali','School Road',         'स्कूल रोड',           '125104'),
  ('Mandi Dabwali','Civil Lines',         'सिविल लाइन्स',        '125104'),
  ('Mandi Dabwali','Mahesh Nagar',        'महेश नगर',            '125104'),
  ('Mandi Dabwali','Aastha Hospital St',  'आस्था हॉस्पिटल स्ट्रीट','125104'),
  -- Sirsa city
  ('Sirsa','Anaj Mandi',                  'अनाज मंडी',            '125055'),
  ('Sirsa','Subhash Chowk',               'सुभाष चौक',            '125055'),
  ('Sirsa','Rania Road',                  'रानिया रोड',           '125055'),
  ('Sirsa','Hisar Road',                  'हिसार रोड',            '125055'),
  ('Sirsa','Court Road',                  'कोर्ट रोड',            '125055'),
  ('Sirsa','Civil Lines',                 'सिविल लाइन्स',         '125055'),
  ('Sirsa','Khairpur',                    'खैरपुर',               '125055'),
  ('Sirsa','Sangwan Chowk',               'सांगवान चौक',          '125055'),
  ('Sirsa','Sector 19',                   'सेक्टर 19',            '125055'),
  -- Ellenabad
  ('Ellenabad','Main Bazaar',             'मुख्य बाज़ार',          '125102'),
  ('Ellenabad','Bus Stand',               'बस स्टैंड',            '125102'),
  ('Ellenabad','Sirsa Road',              'सिरसा रोड',            '125102'),
  ('Ellenabad','Hospital Road',           'अस्पताल रोड',          '125102'),
  ('Ellenabad','Mandi Road',              'मंडी रोड',             '125102'),
  -- Rania
  ('Rania','Main Bazaar',                 'मुख्य बाज़ार',          '125102'),
  ('Rania','Bus Stand',                   'बस स्टैंड',            '125102'),
  ('Rania','Hospital Road',               'अस्पताल रोड',          '125102'),
  -- Kalanwali
  ('Kalanwali','Main Bazaar',             'मुख्य बाज़ार',          '125201'),
  ('Kalanwali','Bus Stand',               'बस स्टैंड',            '125201'),
  ('Kalanwali','Dabwali Road',            'डबवाली रोड',           '125201'),
  ('Kalanwali','Mandi',                   'मंडी',                 '125201'),
  -- Odhan
  ('Odhan','Main Bazaar',                 'मुख्य बाज़ार',          '125106'),
  ('Odhan','Bus Stand',                   'बस स्टैंड',            '125106')
) AS l(city_name, locality, locality_hi, pincode)
INNER JOIN geo_cities c ON c.name = l.city_name
INNER JOIN geo_districts d ON d.id = c.district_id AND d.name = 'Sirsa'
ON CONFLICT DO NOTHING;


-- =====================================================
-- SECTION 7: Localities for Bathinda district cities
-- =====================================================
INSERT INTO geo_localities (city_id, name, name_hi, pincode)
SELECT c.id, l.locality, l.locality_hi, l.pincode
FROM (VALUES
  -- Bathinda city (major localities)
  ('Bathinda','Mall Road',                'मॉल रोड',              '151001'),
  ('Bathinda','Civil Lines',              'सिविल लाइन्स',          '151001'),
  ('Bathinda','Power House Road',         'पावर हाउस रोड',         '151001'),
  ('Bathinda','Bibi Wala Road',           'बीबी वाला रोड',         '151001'),
  ('Bathinda','Goniana Road',             'गोनियाना रोड',          '151001'),
  ('Bathinda','Hazi Rattan',              'हाजी रत्तन',            '151001'),
  ('Bathinda','Multania Road',            'मुल्तानिया रोड',         '151002'),
  ('Bathinda','GT Road',                  'जीटी रोड',              '151001'),
  ('Bathinda','Old Cantt',                'पुरानी छावनी',          '151005'),
  ('Bathinda','Model Town',               'मॉडल टाउन',             '151001'),
  ('Bathinda','Bazar Number 22',          'बाज़ार नंबर 22',        '151001'),
  ('Bathinda','Sirki Bazar',              'सिर्की बाज़ार',          '151001'),
  -- Rampura Phul
  ('Rampura Phul','Main Bazaar',          'मुख्य बाज़ार',          '151103'),
  ('Rampura Phul','Bus Stand',            'बस स्टैंड',            '151103'),
  ('Rampura Phul','Mandi Road',           'मंडी रोड',             '151103'),
  ('Rampura Phul','Civil Lines',          'सिविल लाइन्स',          '151103'),
  -- Talwandi Sabo
  ('Talwandi Sabo','Main Bazaar',         'मुख्य बाज़ार',          '151302'),
  ('Talwandi Sabo','Damdama Sahib Road',  'दमदमा साहिब रोड',      '151302'),
  ('Talwandi Sabo','Bus Stand',           'बस स्टैंड',            '151302'),
  -- Maur
  ('Maur','Main Bazaar',                  'मुख्य बाज़ार',          '151509'),
  ('Maur','Bus Stand',                    'बस स्टैंड',            '151509'),
  ('Maur','Mandi Road',                   'मंडी रोड',             '151509'),
  -- Sangat
  ('Sangat','Main Bazaar',                'मुख्य बाज़ार',          '151401'),
  ('Sangat','Bus Stand',                  'बस स्टैंड',            '151401'),
  -- Goniana
  ('Goniana','Main Bazaar',               'मुख्य बाज़ार',          '151201'),
  ('Goniana','Bus Stand',                 'बस स्टैंड',            '151201'),
  -- Nathana
  ('Nathana','Main Bazaar',               'मुख्य बाज़ार',          '151102'),
  ('Nathana','Bus Stand',                 'बस स्टैंड',            '151102')
) AS l(city_name, locality, locality_hi, pincode)
INNER JOIN geo_cities c ON c.name = l.city_name
INNER JOIN geo_districts d ON d.id = c.district_id AND d.name = 'Bathinda'
ON CONFLICT DO NOTHING;


-- =====================================================
-- SECTION 8: Reload PostgREST cache
-- =====================================================
NOTIFY pgrst, 'reload schema';


-- =====================================================
-- VERIFICATION
-- =====================================================
-- 1) Active states (expect 2: Haryana, Punjab):
--    SELECT name, code FROM geo_states WHERE active = TRUE ORDER BY name;
--
-- 2) Active districts (expect 2: Sirsa, Bathinda):
--    SELECT d.name, s.code FROM geo_districts d JOIN geo_states s ON s.id = d.state_id WHERE d.active = TRUE;
--
-- 3) Active cities count by district:
--    SELECT d.name AS district, COUNT(c.id) AS cities
--    FROM geo_districts d
--    LEFT JOIN geo_cities c ON c.district_id = d.id AND c.active = TRUE
--    WHERE d.active = TRUE
--    GROUP BY d.name;
--    (expect: Sirsa ≈ 10, Bathinda ≈ 10)
--
-- 4) Total localities:
--    SELECT COUNT(*) FROM geo_localities;
-- =====================================================
                                      