-- ============================================================
-- 5-STATE GEO SEED — Haryana, Punjab, Rajasthan, Delhi, UP
-- Focus: Dabwali region full coverage; others starter only
-- ============================================================

-- ===== STATES =====
INSERT INTO geo_states (code, name, name_hi, sort_order) VALUES
  ('HR', 'Haryana',       'हरियाणा',      10),
  ('PB', 'Punjab',        'पंजाब',        20),
  ('RJ', 'Rajasthan',     'राजस्थान',      30),
  ('DL', 'Delhi',         'दिल्ली',        40),
  ('UP', 'Uttar Pradesh', 'उत्तर प्रदेश',  50)
ON CONFLICT (code) DO NOTHING;

-- ===== HARYANA DISTRICTS (full) =====
INSERT INTO geo_districts (state_id, name, name_hi)
SELECT s.id, d.name, d.name_hi FROM geo_states s, (VALUES
  ('Sirsa',         'सिरसा'),
  ('Fatehabad',     'फतेहाबाद'),
  ('Hisar',         'हिसार'),
  ('Bhiwani',       'भिवानी'),
  ('Charkhi Dadri', 'चरखी दादरी'),
  ('Rohtak',        'रोहतक'),
  ('Jhajjar',       'झज्जर'),
  ('Sonipat',       'सोनीपत'),
  ('Panipat',       'पानीपत'),
  ('Karnal',        'करनाल'),
  ('Kurukshetra',   'कुरुक्षेत्र'),
  ('Kaithal',       'कैथल'),
  ('Jind',          'जींद'),
  ('Ambala',        'अंबाला'),
  ('Yamunanagar',   'यमुनानगर'),
  ('Panchkula',     'पंचकूला'),
  ('Faridabad',     'फरीदाबाद'),
  ('Gurugram',      'गुरुग्राम'),
  ('Rewari',        'रेवाड़ी'),
  ('Mahendragarh',  'महेंद्रगढ़'),
  ('Nuh',           'नूंह'),
  ('Palwal',        'पलवल')
) AS d(name, name_hi)
WHERE s.code = 'HR'
ON CONFLICT (state_id, name) DO NOTHING;

-- ===== PUNJAB DISTRICTS (starter) =====
INSERT INTO geo_districts (state_id, name, name_hi)
SELECT s.id, d.name, d.name_hi FROM geo_states s, (VALUES
  ('Bathinda',  'बठिंडा'),
  ('Mansa',     'मानसा'),
  ('Muktsar',   'मुक्तसर'),
  ('Faridkot',  'फरीदकोट'),
  ('Patiala',   'पटियाला'),
  ('Ludhiana',  'लुधियाना'),
  ('Amritsar',  'अमृतसर'),
  ('Jalandhar', 'जालंधर'),
  ('Sangrur',   'संगरूर'),
  ('Barnala',   'बरनाला')
) AS d(name, name_hi)
WHERE s.code = 'PB'
ON CONFLICT (state_id, name) DO NOTHING;

-- ===== RAJASTHAN (starter, Dabwali border) =====
INSERT INTO geo_districts (state_id, name, name_hi)
SELECT s.id, d.name, d.name_hi FROM geo_states s, (VALUES
  ('Hanumangarh', 'हनुमानगढ़'),
  ('Sri Ganganagar','श्री गंगानगर'),
  ('Churu',       'चूरू'),
  ('Bikaner',     'बीकानेर'),
  ('Jaipur',      'जयपुर')
) AS d(name, name_hi)
WHERE s.code = 'RJ'
ON CONFLICT (state_id, name) DO NOTHING;

-- ===== DELHI =====
INSERT INTO geo_districts (state_id, name, name_hi)
SELECT s.id, d.name, d.name_hi FROM geo_states s, (VALUES
  ('New Delhi',    'नई दिल्ली'),
  ('North Delhi',  'उत्तरी दिल्ली'),
  ('South Delhi',  'दक्षिणी दिल्ली'),
  ('East Delhi',   'पूर्वी दिल्ली'),
  ('West Delhi',   'पश्चिमी दिल्ली')
) AS d(name, name_hi)
WHERE s.code = 'DL'
ON CONFLICT (state_id, name) DO NOTHING;

-- ===== UTTAR PRADESH (starter — top cities) =====
INSERT INTO geo_districts (state_id, name, name_hi)
SELECT s.id, d.name, d.name_hi FROM geo_states s, (VALUES
  ('Lucknow',  'लखनऊ'),
  ('Kanpur',   'कानपुर'),
  ('Agra',     'आगरा'),
  ('Varanasi', 'वाराणसी'),
  ('Meerut',   'मेरठ'),
  ('Noida',    'नोएडा'),
  ('Ghaziabad','गाज़ियाबाद')
) AS d(name, name_hi)
WHERE s.code = 'UP'
ON CONFLICT (state_id, name) DO NOTHING;

-- ===== KEY CITIES (focus: Sirsa district = Dabwali home) =====
INSERT INTO geo_cities (district_id, name, name_hi, pincodes, lat, lng)
SELECT d.id, c.name, c.name_hi, c.pincodes, c.lat, c.lng
FROM geo_districts d
JOIN geo_states s ON s.id = d.state_id
JOIN (VALUES
  ('HR','Sirsa','Mandi Dabwali', 'मंडी डबवाली', '{125104,125103}'::TEXT[], 29.9491::numeric, 74.7448::numeric),
  ('HR','Sirsa','Sirsa',         'सिरसा',        '{125055,125054}'::TEXT[], 29.5326::numeric, 75.0186::numeric),
  ('HR','Sirsa','Ellenabad',     'ऐलनाबाद',     '{125102}'::TEXT[],          29.5408::numeric, 74.6750::numeric),
  ('HR','Sirsa','Rania',         'रानिया',       '{125102}'::TEXT[],          29.5167::numeric, 74.8167::numeric),
  ('HR','Sirsa','Kalanwali',     'कालांवाली',    '{125201}'::TEXT[],          29.8167::numeric, 75.1500::numeric),
  ('HR','Fatehabad','Fatehabad', 'फतेहाबाद',     '{125050}'::TEXT[],          29.5167::numeric, 75.4500::numeric),
  ('HR','Fatehabad','Ratia',     'रतिया',        '{125051}'::TEXT[],          29.6917::numeric, 75.5611::numeric),
  ('PB','Bathinda','Bathinda',   'बठिंडा',       '{151001}'::TEXT[],          30.2110::numeric, 74.9455::numeric),
  ('PB','Mansa','Mansa',         'मानसा',        '{151505}'::TEXT[],          29.9988::numeric, 75.3933::numeric),
  ('PB','Muktsar','Muktsar',     'मुक्तसर',      '{152026}'::TEXT[],          30.4761::numeric, 74.5161::numeric),
  ('RJ','Hanumangarh','Hanumangarh','हनुमानगढ़', '{335512}'::TEXT[],          29.5811::numeric, 74.3294::numeric),
  ('RJ','Sri Ganganagar','Sri Ganganagar','श्री गंगानगर','{335001}'::TEXT[],   29.9094::numeric, 73.8800::numeric)
) AS c(state_code, district_name, name, name_hi, pincodes, lat, lng)
ON d.name = c.district_name AND s.code = c.state_code
ON CONFLICT (district_id, name) DO NOTHING;

-- ===== KEY LOCALITIES IN MANDI DABWALI =====
INSERT INTO geo_localities (city_id, name, name_hi, pincode)
SELECT c.id, l.name, l.name_hi, l.pincode
FROM geo_cities c
JOIN geo_districts d ON d.id = c.district_id
JOIN (VALUES
  ('Mandi Dabwali','Mandi Bazar',         'मंडी बाज़ार',       '125104'),
  ('Mandi Dabwali','Chotala Road',        'चोटाला रोड',       '125104'),
  ('Mandi Dabwali','Sirsa Road',          'सिरसा रोड',        '125104'),
  ('Mandi Dabwali','Bus Stand',           'बस स्टैंड',         '125104'),
  ('Mandi Dabwali','Old Grain Market',    'पुरानी अनाज मंडी', '125104'),
  ('Mandi Dabwali','Railway Road',        'रेलवे रोड',         '125104'),
  ('Mandi Dabwali','Hospital Road',       'अस्पताल रोड',      '125104'),
  ('Mandi Dabwali','Court Road',          'कोर्ट रोड',         '125104'),
  ('Mandi Dabwali','School Road',         'स्कूल रोड',         '125104'),
  ('Mandi Dabwali','Civil Lines',         'सिविल लाइन्स',     '125104')
) AS l(city_name, name, name_hi, pincode)
ON c.name = l.city_name AND d.name = 'Sirsa'
ON CONFLICT (city_id, name) DO NOTHING;

NOTIFY pgrst, 'reload schema';
