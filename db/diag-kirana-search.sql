-- =====================================================
-- DIAGNOSTIC: Why does Kirana/Grocery search return empty?
-- =====================================================
-- Run this in Supabase SQL Editor.
-- Each query has its own purpose. Share the output.
-- =====================================================


-- Q1: What 'grocery' or 'kirana' related categories exist?
SELECT
  '🔍 Q1 — categories'  AS check_type,
  id,
  slug,
  name,
  parent_id,
  (SELECT slug FROM categories WHERE id = c.parent_id) AS parent_slug,
  business_count
FROM categories c
WHERE LOWER(name) LIKE '%kirana%'
   OR LOWER(name) LIKE '%grocery%'
   OR slug IN ('grocery','kirana-grocery');


-- Q2: How many shops are in each category?
SELECT
  '🔍 Q2 — shops per category' AS check_type,
  c.slug              AS category_slug,
  c.name              AS category_name,
  COUNT(b.id)         AS total_shops,
  COUNT(b.id) FILTER (WHERE b.status::TEXT = 'active') AS active_shops
FROM categories c
LEFT JOIN businesses b
  ON (b.category_id = c.id OR b.sub_category_id = c.id)
WHERE c.slug IN ('grocery','kirana-grocery')
   OR LOWER(c.name) LIKE '%kirana%'
   OR LOWER(c.name) LIKE '%grocery%'
GROUP BY c.id, c.slug, c.name
ORDER BY total_shops DESC;


-- Q3: Show the actual shops under kirana-grocery / grocery
SELECT
  '🔍 Q3 — actual shops' AS check_type,
  b.id::TEXT             AS business_id,
  b.name                 AS shop_name,
  b.status,
  c1.slug                AS primary_cat_slug,
  c1.name                AS primary_cat_name,
  c2.slug                AS sub_cat_slug,
  c2.name                AS sub_cat_name
FROM businesses b
LEFT JOIN categories c1 ON c1.id = b.category_id
LEFT JOIN categories c2 ON c2.id = b.sub_category_id
WHERE c1.slug IN ('grocery','kirana-grocery')
   OR c2.slug IN ('grocery','kirana-grocery')
   OR LOWER(c1.name) LIKE '%kirana%'
   OR LOWER(c2.name) LIKE '%kirana%'
ORDER BY b.created_at DESC
LIMIT 20;


-- Q4: Test the actual search_businesses RPC call
SELECT
  '🔍 Q4 — RPC result for kirana-grocery' AS check_type,
  COUNT(*) AS shops_returned
FROM search_businesses(NULL, 'kirana-grocery', NULL, NULL, 250, 0, NULL);


-- Q5: Same RPC test for old 'grocery' slug (should return 0 if dedup worked)
SELECT
  '🔍 Q5 — RPC result for old grocery slug' AS check_type,
  COUNT(*) AS shops_returned
FROM search_businesses(NULL, 'grocery', NULL, NULL, 250, 0, NULL);


-- Q6: What's the category_id of kirana-grocery?
SELECT
  '🔍 Q6 — kirana-grocery details' AS check_type,
  id,
  slug,
  name,
  parent_id,
  active,
  business_count
FROM categories
WHERE slug = 'kirana-grocery';
