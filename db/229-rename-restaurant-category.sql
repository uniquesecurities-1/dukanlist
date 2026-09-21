-- ============================================================
-- db/229 — "Restaurants & Dhaba" -> "Restaurants"
-- ============================================================
--
-- WHY
--   Restaurant owners do not want to be labelled "dhaba". The
--   top-level Food & Beverage category #10 was named
--   "Restaurants & Dhaba" / "रेस्टोरेंट एवं ढाबा", so every
--   restaurant listed under it carried the word "Dhaba".
--
--   Dhaba already has its own separate category — #142
--   "Dhaba / Roadside Food" (slug `dhaba`) — so nothing needs to be
--   merged or moved. This is purely a rename of the display label.
--
-- WHAT CHANGES
--   Only categories.name and categories.name_hi on id 10.
--
-- WHAT DOES NOT CHANGE, ON PURPOSE
--   * slug stays `restaurant`. The slug is the URL —
--     /local/mandi-dabwali/restaurant, the sitemap entry, /search
--     links, and anything a shopkeeper has shared. Changing it would
--     404 all of them.
--   * The 3 shops in this category (Aroma House of Flavours,
--     Hotel Red Heart, Regal Foods) stay exactly where they are —
--     all three are restaurants/hotels, none is a dhaba.
--   * keywords are left as-is (they still include "dhaba" so a
--     customer typing "dhaba" still finds food places). Those are
--     invisible search-matching text, not the label anyone sees.
--     Verified: the name is NOT hardcoded in any HTML/JS — it comes
--     from this table at runtime — so this rename is sufficient.
--
-- Idempotent: matched by slug, and safe to re-run.
-- ============================================================

BEGIN;

UPDATE public.categories
   SET name    = 'Restaurants',
       name_hi = 'रेस्टोरेंट'
 WHERE slug = 'restaurant'
   AND parent_id = (SELECT id FROM public.categories WHERE slug = 'food-beverage');

NOTIFY pgrst, 'reload schema';

COMMIT;

-- Show the result. Should read: restaurant | Restaurants | रेस्टोरेंट
SELECT id, slug, name, name_hi, icon
FROM public.categories
WHERE slug IN ('restaurant', 'dhaba')
ORDER BY slug;
