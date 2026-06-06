-- =====================================================
-- db/58-healthcare-restructure.sql
-- =====================================================
-- USER FEEDBACK:
--   "Doctors & Clinic combined hai, Hospital & Nursing Home combined
--    hai. Hospital & Clinic hona chahiye, Nursing Home alag aaye,
--    Doctors alag rakho for multi-specialty type/combined etc."
--
-- ACTION (additive + 2 renames):
--   1. Rename 'doctor' display → "Doctor (General / Multi-specialty)"
--   2. Rename 'hospital' display → "Hospital & Clinic"
--   3. Add 'nursing-home' as a NEW separate category
--   4. Add 13 missing specialist categories
--      (Gynecologist, Pediatrician, Orthopedic, Cardiologist, ENT,
--       Dermatologist, Surgeon, Urologist, Neurologist, Psychiatrist,
--       Diabetologist, X-Ray/Radiology, Ultrasound/Sonography)
--
-- ZERO RISK: all UPDATE/INSERT — no DROP. Existing businesses
--   registered under 'doctor' or 'hospital' slugs continue to work
--   (slug unchanged, only display name updated).
--
-- HOW TO RUN: Supabase SQL Editor → paste → Run
-- =====================================================

BEGIN;

-- ============================================================
-- 1. RENAME existing categories (slug stays — businesses unaffected)
-- ============================================================
UPDATE categories
   SET name = 'Doctor (General / Multi-specialty)',
       name_hi = 'डॉक्टर (जनरल / मल्टी-स्पेशलिटी)',
       description = 'General physicians, MBBS doctors, multi-specialty practitioners, OPD',
       keywords = 'doctor,clinic,physician,mbbs,opd,general doctor,family doctor,multi specialty,multispecialty,dispensary,daktar'
 WHERE slug = 'doctor';

UPDATE categories
   SET name = 'Hospital & Clinic',
       name_hi = 'अस्पताल / क्लिनिक',
       description = 'Multi-specialty hospitals, clinics, ICU, emergency, OPD-IPD',
       keywords = 'hospital,clinic,multi specialty hospital,icu,emergency,opd,ipd,private hospital,trauma center,asptaal'
 WHERE slug = 'hospital';

-- ============================================================
-- 2. ADD new core category: Nursing Home (separate from Hospital)
-- ============================================================
WITH parent AS (SELECT id FROM categories WHERE slug = 'healthcare')
INSERT INTO categories (slug, name, name_hi, icon, color, sort_order, description, keywords, parent_id, active)
SELECT t.slug, t.name, t.name_hi, t.icon, '#0EA5E9', t.sort_order, t.description, t.keywords, p.id, TRUE
FROM (VALUES
  ('nursing-home',           'Nursing Home',                  'नर्सिंग होम',                       '🏥', 13,
   'Smaller in-patient care, maternity, post-op care, observation stay',
   'nursing home,maternity home,prasooti,observation,post operative,small hospital'),

  -- ===== 13 specialist categories =====
  ('gynecologist',           'Gynecologist / Women''s Health','स्त्री रोग विशेषज्ञ (गायनी)',        '🤰', 20,
   'Women health, pregnancy care, infertility, hormonal issues, IVF',
   'gynecologist,gyne,lady doctor,obstetrician,obgyn,women health,pregnancy,prasooti,maternity,infertility,ivf,period'),

  ('pediatrician',           'Pediatrician / Child Specialist','बाल रोग विशेषज्ञ',                  '👶', 21,
   'Child specialist, vaccination, paediatric care, newborn doctor',
   'pediatrician,paediatrician,child specialist,baby doctor,kids doctor,vaccination,paediatric,bachcha doctor'),

  ('orthopedic',             'Orthopedic / Bone & Joint',     'हड्डी रोग विशेषज्ञ (ऑर्थो)',        '🦴', 22,
   'Bone, joint, fracture, knee replacement, sports injury, arthritis',
   'orthopedic,orthopaedic,ortho,bone doctor,joint specialist,fracture,knee,hip,shoulder,arthritis,sports injury,haddi'),

  ('cardiologist',           'Cardiologist / Heart Specialist','हृदय रोग विशेषज्ञ',                 '❤️', 23,
   'Heart specialist, ECG, cardiac, blood pressure, cholesterol',
   'cardiologist,heart specialist,cardiac,ecg,echo,bp doctor,blood pressure,hridya,chest pain'),

  ('dermatologist',          'Dermatologist / Skin Specialist','त्वचा रोग विशेषज्ञ',                '✨', 24,
   'Skin doctor, hair fall, acne, pigmentation, eczema, cosmetic',
   'dermatologist,skin doctor,skin specialist,hair fall,acne,pimple,pigmentation,eczema,psoriasis,cosmetic,twacha'),

  ('ent-specialist',         'ENT Specialist (Ear/Nose/Throat)','कान-नाक-गला विशेषज्ञ',              '👂', 25,
   'Ear-Nose-Throat doctor, hearing, sinus, tonsil, snoring',
   'ent,ear nose throat,otolaryngology,hearing,sinus,tonsil,snoring,kaan,naak,gala'),

  ('surgeon-general',        'General Surgeon',               'जनरल सर्जन',                        '🔪', 26,
   'General surgery, hernia, gallbladder, appendix, laparoscopy',
   'surgeon,surgery,general surgery,hernia,gallbladder,appendix,laparoscopy,operation'),

  ('urologist',              'Urologist / Kidney Specialist', 'मूत्र रोग विशेषज्ञ',                '💧', 27,
   'Kidney, stone, prostate, urinary, dialysis',
   'urologist,kidney doctor,kidney specialist,urinary,stone,prostate,dialysis,gurda'),

  ('neurologist',            'Neurologist / Brain & Nerve',   'न्यूरोलॉजिस्ट (नस / दिमाग)',         '🧠', 28,
   'Brain, nerve, stroke, epilepsy, headache, paralysis',
   'neurologist,brain doctor,nerve specialist,stroke,epilepsy,headache,paralysis,migraine,dimaag,nas'),

  ('psychiatrist',           'Psychiatrist',                  'मनोचिकित्सक (साइकैट्रिस्ट)',         '💊', 29,
   'Mental health doctor (MD), prescriptions, anxiety, depression, OCD',
   'psychiatrist,mental doctor,manochikitsak,depression,anxiety,ocd,bipolar,mental illness,nasha mukti'),

  ('diabetes-specialist',    'Diabetologist / Diabetes Center','मधुमेह विशेषज्ञ',                  '🩸', 30,
   'Diabetes specialist, sugar test, insulin, diabetic foot',
   'diabetes,diabetologist,sugar doctor,madhumeh,insulin,sugar test,hba1c,diabetic foot'),

  ('radiology-xray',         'X-Ray / Radiology Center',      'एक्स-रे / रेडियोलॉजी सेंटर',         '☢️', 31,
   'X-Ray, CT scan, MRI, mammography, digital radiography',
   'x-ray,xray,radiology,ct scan,mri,scan,mammography,digital xray,imaging,radiologist'),

  ('ultrasound-sonography',  'Ultrasound / Sonography Center','अल्ट्रासाउंड / सोनोग्राफी सेंटर',     '🔊', 32,
   'Ultrasound, sonography, pregnancy scan, doppler, anomaly scan',
   'ultrasound,sonography,sonologist,pregnancy scan,doppler,anomaly scan,whole abdomen,fetal scan')

) AS t(slug, name, name_hi, icon, sort_order, description, keywords)
CROSS JOIN parent p
ON CONFLICT (slug) DO UPDATE
  SET name = EXCLUDED.name,
      name_hi = EXCLUDED.name_hi,
      description = EXCLUDED.description,
      keywords = EXCLUDED.keywords,
      parent_id = EXCLUDED.parent_id;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- 3. Verification
-- ============================================================
DO $$
DECLARE
  v_new INT;
  v_doc_name TEXT;
  v_hosp_name TEXT;
BEGIN
  SELECT COUNT(*) INTO v_new FROM categories
    WHERE slug IN (
      'nursing-home','gynecologist','pediatrician','orthopedic','cardiologist',
      'dermatologist','ent-specialist','surgeon-general','urologist','neurologist',
      'psychiatrist','diabetes-specialist','radiology-xray','ultrasound-sonography'
    );

  SELECT name INTO v_doc_name FROM categories WHERE slug = 'doctor';
  SELECT name INTO v_hosp_name FROM categories WHERE slug = 'hospital';

  RAISE NOTICE 'New healthcare categories: % of 14', v_new;
  RAISE NOTICE 'doctor → %', v_doc_name;
  RAISE NOTICE 'hospital → %', v_hosp_name;

  IF v_new < 14 THEN
    RAISE WARNING 'Some categories missing — check healthcare parent slug exists';
  END IF;
  IF v_doc_name NOT ILIKE '%Multi-specialty%' THEN
    RAISE WARNING 'doctor rename did not apply';
  END IF;
  IF v_hosp_name NOT ILIKE '%Clinic%' THEN
    RAISE WARNING 'hospital rename did not apply';
  END IF;
END $$;

COMMIT;

-- =====================================================
-- ROLLBACK (if ever needed):
--   UPDATE categories SET name='Doctors & Clinics', name_hi='डॉक्टर एवं क्लिनिक' WHERE slug='doctor';
--   UPDATE categories SET name='Hospital / Nursing Home', name_hi='अस्पताल / नर्सिंग होम' WHERE slug='hospital';
--   DELETE FROM categories WHERE slug IN (
--     'nursing-home','gynecologist','pediatrician','orthopedic','cardiologist',
--     'dermatologist','ent-specialist','surgeon-general','urologist','neurologist',
--     'psychiatrist','diabetes-specialist','radiology-xray','ultrasound-sonography'
--   );
-- =====================================================
