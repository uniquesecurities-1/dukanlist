-- =====================================================
-- db/30-add-education-community-cats.sql
-- Add NEW categories (Education expansion + new Community & Social parent)
-- =====================================================
-- ⚠️ ADDITIVE ONLY — no existing rows touched. Existing shops keep their
-- category_id references untouched. Safe to run multiple times (ON CONFLICT).
-- =====================================================
BEGIN;

-- ---------- Schema check ----------
-- Categories table is expected: id (SERIAL PK), slug TEXT UNIQUE,
-- name TEXT, name_hi TEXT, icon TEXT, parent_id INT FK to self,
-- is_parent BOOLEAN, sort_order INT, active BOOLEAN
-- =====================================================

-- ---------- Step 1: Expand Education parent with school/college/etc ----------
-- We look up Education parent by slug 'education'. If your DB uses a
-- different slug, adjust the WHERE.

WITH edu_parent AS (
  SELECT id FROM categories WHERE slug = 'education' AND is_parent = TRUE LIMIT 1
)
INSERT INTO categories (slug, name, name_hi, icon, parent_id, is_parent, sort_order, active)
SELECT v.slug, v.name, v.name_hi, v.icon, ep.id, FALSE, v.sort, TRUE
FROM edu_parent ep
CROSS JOIN (VALUES
  ('school',            'School',                       'स्कूल',                            '🏫', 600),
  ('college',           'College',                      'कॉलेज',                            '🎓', 601),
  ('university',        'University',                   'विश्वविद्यालय',                     '🏛️', 602),
  ('coaching-institute','Coaching Institute',           'कोचिंग संस्थान',                   '📘', 603),
  ('skill-vocational',  'Skill / Vocational Training',  'स्किल / व्यावसायिक प्रशिक्षण',       '🛠️', 604),
  ('library',           'Library / Study Center',       'लाइब्रेरी / स्टडी सेंटर',           '📚', 605)
) AS v(slug, name, name_hi, icon, sort)
ON CONFLICT (slug) DO NOTHING;

-- ---------- Step 2: Insert NEW parent: Community & Social ----------
INSERT INTO categories (slug, name, name_hi, icon, parent_id, is_parent, sort_order, active)
VALUES ('community-social',
        'Community & Social',
        'सामुदायिक एवं सामाजिक',
        '🤝',
        NULL,    -- top-level parent
        TRUE,
        110,     -- after Professional Services
        TRUE)
ON CONFLICT (slug) DO NOTHING;

-- ---------- Step 3: Insert Community & Social sub-categories ----------
WITH com_parent AS (
  SELECT id FROM categories WHERE slug = 'community-social' AND is_parent = TRUE LIMIT 1
)
INSERT INTO categories (slug, name, name_hi, icon, parent_id, is_parent, sort_order, active)
SELECT v.slug, v.name, v.name_hi, v.icon, cp.id, FALSE, v.sort, TRUE
FROM com_parent cp
CROSS JOIN (VALUES
  ('gau-shala',          'Gau Shala / Animal Welfare',       'गौ शाला / पशु कल्याण',          '🐄', 700),
  ('temple-trust',       'Temple / Religious Trust',         'मंदिर / धार्मिक ट्रस्ट',        '🛕', 701),
  ('gurudwara',          'Gurudwara',                        'गुरुद्वारा',                    '🕌', 702),
  ('ngo-charitable',     'NGO / Charitable Trust',           'एनजीओ / धर्मार्थ ट्रस्ट',        '❤️', 703),
  ('social-club',        'Social Club (Rotary, Lions)',      'सामाजिक क्लब',                  '🎗️', 704),
  ('cultural-sanstha',   'Cultural Sanstha / Mahila Mandal', 'सांस्कृतिक संस्था / महिला मंडल', '🌸', 705),
  ('yuvak-mandal',       'Yuvak Mandal / Youth Club',        'युवक मंडल',                     '🤸', 706),
  ('sports-club',        'Sports Club / Akhada',             'खेल क्लब / अखाड़ा',            '🏃', 707),
  ('panchayat-office',   'Panchayat / Community Office',     'पंचायत / सामुदायिक कार्यालय',  '🏛️', 708),
  ('blood-donation-camp','Blood Donation / Welfare Camp',    'रक्तदान / कल्याण शिविर',         '🩸', 709)
) AS v(slug, name, name_hi, icon, sort)
ON CONFLICT (slug) DO NOTHING;

COMMIT;

-- =====================================================
-- VERIFY:
--   SELECT slug, name, icon, is_parent, parent_id
--     FROM categories
--     WHERE slug IN ('school','college','community-social','gau-shala','ngo-charitable')
--     ORDER BY is_parent DESC, sort_order;
--
--   SELECT COUNT(*) FROM categories WHERE active = TRUE AND is_parent = FALSE;
--   -- Should be 88 (was 72)
-- =====================================================
