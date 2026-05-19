-- ============================================================
-- 15 STARTER CATEGORIES — Dabwali optimised
-- ============================================================
INSERT INTO categories (slug, name, name_hi, icon, color, sort_order, description) VALUES
  ('doctor',       'Doctors & Clinics',        'डॉक्टर एवं क्लिनिक',     '🩺', '#0EA5E9',  10, 'General physicians, specialists, clinics, hospitals'),
  ('pharmacy',     'Medical Store / Pharmacy', 'मेडिकल स्टोर',            '💊', '#10B981',  20, 'Chemists, pharmacies, surgical, medical supplies'),
  ('lawyer',       'Lawyers & Notaries',       'वकील एवं नोटरी',         '⚖️', '#7C2D12',  30, 'Advocates, notary, legal documentation, court matters'),
  ('ca',           'CA / Tax Consultants',     'CA / टैक्स कंसल्टेंट',     '🧮', '#1E40AF',  40, 'Chartered accountants, GST, ITR, audit'),
  ('carpenter',    'Carpenter (Lakdi-Mistri)', 'बढ़ई / लकड़ी का मिस्त्री','🔨', '#92400E',  50, 'Woodwork, furniture, doors, windows, custom'),
  ('plumber',      'Plumber',                  'प्लंबर / नलसाज़',         '🚰', '#0891B2',  60, 'Water, sewage, RO, geyser repair'),
  ('electrician',  'Electrician',              'इलेक्ट्रीशियन / बिजली मिस्त्री','⚡', '#F59E0B', 70, 'House wiring, fans, AC, inverter repair'),
  ('used-car',     'Second-hand Car Dealers',  'सेकंड हैंड कार डीलर',    '🚗', '#7C3AED',  80, 'Used cars, exchange, finance, RC transfer'),
  ('new-car',      'New Car / Bike Showroom',  'नई कार / बाइक शोरूम',   '🚙', '#DB2777',  90, 'Authorized dealers — cars, two-wheelers, EVs'),
  ('restaurant',   'Restaurants & Dhaba',      'रेस्टोरेंट एवं ढाबा',      '🍴', '#DC2626', 100, 'Dine-in, takeaway, dhaba, fast food, family restaurants'),
  ('sweets',       'Sweets & Caterers',        'मिठाई एवं केटरर',        '🍬', '#F97316', 110, 'Halwai, mithai shops, marriage caterers, snacks'),
  ('grocery',      'Grocery / Kirana Store',   'किराना स्टोर',           '🛒', '#16A34A', 120, 'Daily essentials, FMCG, household goods'),
  ('clothes',      'Clothes / Tailor',         'कपड़ा / दर्ज़ी',           '👔', '#A855F7', 130, 'Garments shop, ladies/gents tailoring, alterations, designer wear'),
  ('jewellery',    'Jewellery',                'जौहरी / सोना-चाँदी',     '💍', '#D97706', 140, 'Gold, silver, diamond, gold loan, repair'),
  ('salon',        'Salon / Beauty Parlour',   'सैलून / ब्यूटी पार्लर',   '💇', '#EC4899', 150, 'Mens salon, ladies parlour, bridal makeup, spa')
ON CONFLICT (slug) DO NOTHING;

NOTIFY pgrst, 'reload schema';
