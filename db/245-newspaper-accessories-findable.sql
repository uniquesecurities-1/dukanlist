-- ============================================================
-- db/245 — "Newspaper" and "Accessories" findable by their own word
-- ============================================================
-- Both exist since db/235 (newspaper-agency under Professional
-- Services, fashion-accessories under Retail). Deepak could not find
-- them: Browse sorts a parent's subs by shop count, so a 0-shop trade
-- sits at the bottom of ~100 Retail tiles, and "Belts, Wallets &
-- Fashion Accessories" does not start with the word people look for.
-- Rename so the key word leads, add the search words. Safe to re-run.
-- ============================================================
BEGIN;

UPDATE public.categories
   SET name     = 'Accessories — Belts, Wallets, Watches',
       name_hi  = 'एक्सेसरीज़ — बेल्ट, वॉलेट, घड़ी',
       keywords = 'accessories,fashion accessories,belt,belts,wallet,wallets,watch,watches,purse,ladies purse,hand bag,sunglasses,goggles,cap,tie,cufflinks,एक्सेसरीज़,बेल्ट,वॉलेट,घड़ी,पर्स'
 WHERE slug = 'fashion-accessories';

UPDATE public.categories
   SET name     = 'Newspaper Agency / Hawker',
       name_hi  = 'अख़बार एजेंसी / हॉकर',
       keywords = 'newspaper,news paper,akhbar,akhbaar,paper agency,hawker,magazine,dainik bhaskar,dainik jagran,punjab kesari,amar ujala,tribune,hindustan times,times of india,अख़बार,अखबार,समाचार पत्र,पेपर'
 WHERE slug = 'newspaper-agency';

UPDATE public.categories
   SET keywords = 'media,news channel,reporter,journalist,patrakar,press,news,youtube channel,local news,मीडिया,पत्रकार,न्यूज़'
 WHERE slug = 'media-news' AND NULLIF(TRIM(COALESCE(keywords,'')),'') IS NULL;

DO $$ BEGIN
  IF to_regprocedure('public.record_migration(text,text)') IS NOT NULL THEN
    PERFORM public.record_migration('db/245-newspaper-accessories-findable.sql');
  END IF;
END $$;

COMMIT;

SELECT slug, name, LEFT(keywords, 60) AS keywords FROM public.categories
 WHERE slug IN ('fashion-accessories','newspaper-agency','media-news') ORDER BY slug;
