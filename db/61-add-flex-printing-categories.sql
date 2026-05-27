-- =====================================================
-- db/61-add-flex-printing-categories.sql
-- =====================================================
-- USER FEEDBACK:
--   1. 'Flex Printing nahi hai' — flex / vinyl board printing missing
--   2. Chip in register shows 'Printing Press / Vi...' — text truncated
--      (chip CSS fix in register.html separately)
--
-- This SQL adds 5 missing print/sign categories:
--   • Flex / Vinyl Banner Printing
--   • Photocopy / Xerox / Print-out shop
--   • Lamination / Spiral Binding
--   • Sign Board / Hoarding maker
--   • Wedding Card / Invitation printing
--
-- ZERO RISK — additive only.
-- =====================================================

BEGIN;

WITH parent AS (SELECT id FROM categories WHERE slug = 'professional-services')
INSERT INTO categories (slug, name, name_hi, icon, color, sort_order, description, keywords, parent_id, default_listing_type, active)
SELECT t.slug, t.name, t.name_hi, t.icon, '#1F2937', t.sort_order, t.description, t.keywords, p.id, 'service', TRUE
FROM (VALUES
  ('flex-printing',         'Flex / Vinyl Banner Printing',  'फ्लेक्स / विनाइल प्रिंटिंग',     '🪧', 108,
   'Flex banner, vinyl board, hoarding, shop name board, custom signage',
   'flex,vinyl,banner,hoarding,sign board,signboard,naam board,name plate,flex board,vinyl banner,signage,wedding banner,shop board'),

  ('photocopy-xerox',       'Photocopy / Xerox / Print-out',  'फोटोकॉपी / जेरॉक्स',             '📑', 109,
   'Photocopy, xerox, print-out, scanning, B&W and colour prints',
   'photocopy,xerox,print out,printout,scan,scanning,black and white,colour print,b/w,a4 print,document print,jerox'),

  ('lamination-binding',    'Lamination / Spiral Binding',    'लेमिनेशन / बाइंडिंग',            '📎', 110,
   'Lamination (hot/cold), spiral binding, hard bound, file folder, jacket cover',
   'lamination,laminate,spiral binding,hard binding,thesis binding,file binding,book binding,plastic cover,jacket'),

  ('sign-board',            'Sign Board / Hoarding Maker',    'साइन बोर्ड / होर्डिंग',           '🪧', 111,
   'Custom sign board, LED board, glow sign, ACP board, neon sign, name plate',
   'sign board,signboard,hoarding,led board,glow sign,acp,acp board,neon sign,led sign,3d sign,name plate'),

  ('wedding-cards',         'Wedding Card / Invitation Print','शादी कार्ड / इनविटेशन',           '💌', 112,
   'Wedding cards, invitation cards, birthday invites, custom design',
   'wedding card,shadi card,invitation,nimantran,invite,birthday card,reception card,save the date,custom card design')
) AS t(slug, name, name_hi, icon, sort_order, description, keywords)
CROSS JOIN parent p
ON CONFLICT (slug) DO UPDATE
  SET keywords = EXCLUDED.keywords,
      description = EXCLUDED.description,
      parent_id = EXCLUDED.parent_id,
      default_listing_type = EXCLUDED.default_listing_type;

-- Also expand existing printing-press keywords so 'flex' still finds it
UPDATE categories SET
  keywords = 'printing,visiting card,business card,wedding card,brochure,pamphlet,letterhead,banner,flex,offset print,digital print,letter pad'
WHERE slug = 'printing-press';

NOTIFY pgrst, 'reload schema';

DO $$
DECLARE v_new INT;
BEGIN
  SELECT COUNT(*) INTO v_new FROM categories WHERE slug IN (
    'flex-printing','photocopy-xerox','lamination-binding','sign-board','wedding-cards'
  );
  RAISE NOTICE 'New print/sign categories: % of 5', v_new;
END $$;

COMMIT;
