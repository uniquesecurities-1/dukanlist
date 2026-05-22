-- =====================================================
-- db/30b-add-education-community-cats-fixed.sql
-- FIX: original db/30 used "is_parent" column which doesn't exist
-- in actual schema. Schema uses parent_id IS NULL to indicate
-- top-level parents. This version uses the correct column.
-- =====================================================
-- IDEMPOTENT: ON CONFLICT DO NOTHING — safe to run even if
-- partial inserts happened in failed earlier attempt.
-- =====================================================
BEGIN;

-- ---------- Step 1: Expand Education with 6 new subs ----------
WITH edu_parent AS (
  SELECT id FROM categories
  WHERE slug = 'education' AND parent_id IS NULL
  LIMIT 1
)
INSERT INTO categories (slug, name, name_hi, icon, parent_id, sort_order, active)
SELECT v.slug, v.name, v.name_hi, v.icon, ep.id, v.sort, TRUE
FROM edu_parent ep
CROSS JOIN (VALUES
  ('school',            'School',                       'स्कूल',                              '🏫', 600),
  ('college',           'College',                      'कॉलेज',                              '🎓', 601),
  ('university',        'University',                   'विश्वविद्यालय',                       '🏛️', 602),
  ('coaching-institute','Coaching Institute',           'कोचिंग संस्थान',                     '📘', 603),
  ('skill-vocational',  'Skill / Vocational Training',  'स्किल / व्यावसायिक प्रशिक्षण',         '🛠️', 604),
  ('library',           'Library / Study Center',       'लाइब्रेरी / स्टडी सेंटर',             '📚', 605)
) AS v(slug, name, name_hi, icon, sort)
ON CONFLICT (slug) DO NOTHING;

-- ---------- Step 2: Insert NEW parent: Community & Social ----------
INSERT INTO categories (slug, name, name_hi, icon, parent_id, sort_order, active)
VALUES ('community-social',
        'Community & Social',
        'सामुदायिक एवं सामाजिक',
        '🤝',
        NULL,    -- top-level parent
        110,
        TRUE)
ON CONFLICT (slug) DO NOTHING;

-- ---------- Step 3: Insert Community & Social sub-categories ----------
WITH com_parent AS (
  SELECT id FROM categories
  WHERE slug = 'community-social' AND parent_id IS NULL
  LIMIT 1
)
INSERT INTO categories (slug, name, name_hi, icon, parent_id, sort_order, active)
SELECT v.slug, v.name, v.name_hi, v.icon, cp.id, v.sort, TRUE
FROM com_parent cp
CROSS JOIN (VALUES
  ('gau-shala',          'Gau Shala / Animal Welfare',       'गौ शाला / पशु कल्याण',          '🐄', 700),
  ('temple-trust',       'Temple / Religious Trust',         'मंदिर / धार्मिक ट्रस्ट',        '🛕', 701),
  ('gurudwara',          'Gurudwara',                        'गुरुद्वारा',                    '🕌', 702),
  ('ngo-charitable',     'NGO / Charitable Trust',           'एनजीओ / धर्मार्थ ट्रस्ट',        '❤️', 703),
  ('social-club',        'Social Club (Rotary, Lions)',      'सामाजिक क्लब',                  '🎗️', 704),
  ('cultural-sanstha',   'Cultural Sanstha / Mahila Mandal', 'सांस्कृतिक संस्था / महिला मंडल',  '🌸', 705),
  ('yuvak-mandal',       'Yuvak Mandal / Youth Club',        'युवक मंडल',                     '🤸', 706),
  ('sports-club',        'Sports Club / Akhada',             'खेल क्लब / अखाड़ा',             '🏃', 707),
  ('panchayat-office',   'Panchayat / Community Office',     'पंचायत / सामुदायिक कार्यालय',   '🏛️', 708),
  ('blood-donation-camp','Blood Donation / Welfare Camp',    'रक्तदान / कल्याण शिविर',         '🩸', 709)
) AS v(slug, name, name_hi, icon, sort)
ON CONFLICT (slug) DO NOTHING;

COMMIT;

-- =====================================================
-- VERIFY:
--   SELECT slug, name, icon, parent_id
--     FROM categories
--     WHERE slug IN ('school','college','university','coaching-institute',
--                    'community-social','gau-shala','ngo-charitable')
--     ORDER BY parent_id NULLS FIRST, sort_order;
--
--   SELECT COUNT(*) FROM categories WHERE active = TRUE AND parent_id IS NOT NULL;
--   -- Should be 88 (was 72)
-- =====================================================
