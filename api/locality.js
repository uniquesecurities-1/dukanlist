// =====================================================
// api/locality.js
// SEO landing pages for /local/:city/:cat URLs.
//
// Returns fully server-rendered HTML so Google can index the shop
// listings directly (no JS required). Aggressively edge-cached.
//
// Example URLs:
//   /local/mandi-dabwali/medical-stores
//   /local/sirsa/insurance
//   /local/bathinda/coaching-institute
// =====================================================

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://qazuyygrpqopwygxmvwq.supabase.co';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFhenV5eWdycHFvcHd5Z3htdndxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxNTUwOTEsImV4cCI6MjA5NDczMTA5MX0.FR8x2kldC2yelpPnK2QKd5WGwHUAQheCVmxfs6hR00I';

const ORIGIN = 'https://dukanlist.com';

function esc(s){
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

async function sb(path){
  const r = await fetch(SUPABASE_URL + '/rest/v1/' + path, {
    headers: {
      'apikey': SUPABASE_ANON_KEY,
      'Authorization': 'Bearer ' + SUPABASE_ANON_KEY,
      'Accept': 'application/json'
    }
  });
  if (!r.ok) return null;
  return r.json();
}

async function findCity(citySlug){
  if (!citySlug) return null;
  const name = citySlug.replace(/-/g, ' ');
  const rows = await sb('geo_cities?select=id,name,district_id&active=eq.true&name=ilike.' + encodeURIComponent(name));
  return rows && rows[0] ? rows[0] : null;
}

async function findCategory(catSlug){
  if (!catSlug) return null;
  const rows = await sb('categories?select=id,name,name_hi,icon,parent_id,slug&active=eq.true&slug=eq.' + encodeURIComponent(catSlug));
  return rows && rows[0] ? rows[0] : null;
}

async function fetchShops(cityId, catId, catIsParent){
  // For a parent: match either category_id OR any sub of this parent
  let q;
  if (catIsParent){
    // Get all sub-cat IDs
    const subs = await sb('categories?select=id&parent_id=eq.' + catId);
    const subIds = (subs || []).map(s => s.id);
    const idsForOr = [catId].concat(subIds).join(',');
    q = 'businesses?select=id,slug,name,name_hi,mobile,whatsapp,address_line1,pincode,photos,usp_text,rating_avg,rating_count,verified_score,established_year,featured,geo_cities(name)'
      + '&status=eq.active'
      + '&city_id=eq.' + cityId
      + '&or=(category_id.in.(' + idsForOr + '),sub_category_id.in.(' + idsForOr + '))'
      + '&order=featured.desc.nullslast,verified_score.desc.nullslast,rating_avg.desc.nullslast'
      + '&limit=40';
  } else {
    q = 'businesses?select=id,slug,name,name_hi,mobile,whatsapp,address_line1,pincode,photos,usp_text,rating_avg,rating_count,verified_score,established_year,featured,geo_cities(name)'
      + '&status=eq.active'
      + '&city_id=eq.' + cityId
      + '&or=(category_id.eq.' + catId + ',sub_category_id.eq.' + catId + ')'
      + '&order=featured.desc.nullslast,verified_score.desc.nullslast,rating_avg.desc.nullslast'
      + '&limit=40';
  }
  return (await sb(q)) || [];
}

function renderShopCard(b){
  const cityName = b.geo_cities && b.geo_cities.name ? b.geo_cities.name : '';
  const photo = (b.photos && b.photos.length) ? b.photos[0] : null;
  const rating = b.rating_avg > 0
    ? `<span style="color:#0F172A;font-weight:700">⭐ ${Number(b.rating_avg).toFixed(1)} <span style="font-weight:500;color:#64748b">(${b.rating_count || 0})</span></span>`
    : '<span style="color:#94a3b8">No reviews yet</span>';
  const since = b.established_year && b.established_year > 1900
    ? `<span style="background:#FEF3C7;color:#92400E;padding:2px 8px;border-radius:99px;font-size:11px;font-weight:700">Since ${b.established_year}</span>`
    : '';
  const featuredBadge = b.featured
    ? `<span style="background:linear-gradient(135deg,#FFC93D,#FF8C00);color:#1A1A1A;padding:2px 8px;border-radius:99px;font-size:11px;font-weight:800;letter-spacing:.03em">★ FEATURED</span>`
    : '';
  return `
  <a href="${ORIGIN}/business.html?slug=${esc(b.slug)}" style="background:#fff;border:1px solid rgba(15,23,42,.06);border-radius:14px;overflow:hidden;text-decoration:none;color:inherit;display:flex;flex-direction:column;box-shadow:0 1px 3px rgba(15,23,42,.04);transition:transform .2s,box-shadow .2s" onmouseover="this.style.transform='translateY(-2px)';this.style.boxShadow='0 14px 30px rgba(15,23,42,.08)'" onmouseout="this.style.transform='';this.style.boxShadow='0 1px 3px rgba(15,23,42,.04)'">
    ${photo
      ? `<img src="${esc(photo)}" alt="${esc(b.name)}" style="width:100%;aspect-ratio:16/10;object-fit:cover" loading="lazy">`
      : `<div style="width:100%;aspect-ratio:16/10;background:linear-gradient(135deg,#FAFAFA,#F1F5F9);display:grid;place-items:center;font-size:3rem;opacity:.5">🏪</div>`
    }
    <div style="padding:14px;display:flex;flex-direction:column;gap:6px">
      <div style="display:flex;gap:6px;flex-wrap:wrap">${featuredBadge}${since}</div>
      <div style="font-weight:700;font-size:1.05rem;color:#0F172A;line-height:1.3;letter-spacing:-.01em">${esc(b.name)}</div>
      ${b.usp_text ? `<div style="font-size:.85rem;color:#5A6573;line-height:1.4;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden">${esc(b.usp_text)}</div>` : ''}
      <div style="display:flex;justify-content:space-between;align-items:center;font-size:.82rem;color:#64748b;margin-top:6px;padding-top:8px;border-top:1px solid #f1f5f9">
        ${rating}
        <span>📍 ${esc(cityName)}</span>
      </div>
    </div>
  </a>`;
}

function renderPage(opts){
  const { city, cat, shops, isParent, subCategories } = opts;
  const cityName = city.name;
  const catName  = cat.name;
  const url = `${ORIGIN}/local/${cityName.toLowerCase().replace(/ /g,'-')}/${cat.slug}`;
  const title = `${catName} in ${cityName} — Top ${shops.length}+ Verified Shops · DukanList`;
  const desc  = `Find the best ${catName.toLowerCase()} in ${cityName}. ${shops.length} verified local shops with reviews, ratings, contact details. Free customer reviews. Updated daily on DukanList — Bharat ka local shop directory.`;

  // Schema.org ItemList for SEO
  const itemListSchema = {
    "@context": "https://schema.org",
    "@type": "ItemList",
    "itemListElement": shops.slice(0, 10).map((s, i) => ({
      "@type": "ListItem",
      "position": i + 1,
      "item": {
        "@type": "LocalBusiness",
        "name": s.name,
        "url": `${ORIGIN}/business.html?slug=${s.slug}`,
        "telephone": s.mobile || undefined,
        "address": { "@type": "PostalAddress", "addressLocality": cityName, "postalCode": s.pincode },
        "aggregateRating": s.rating_count > 0 ? { "@type": "AggregateRating", "ratingValue": s.rating_avg, "reviewCount": s.rating_count } : undefined
      }
    }))
  };

  const otherCats = isParent && subCategories && subCategories.length
    ? `<section style="max-width:1180px;margin:48px auto 0;padding:0 20px">
         <h2 style="font-size:1.3rem;font-weight:800;color:#0F172A;margin-bottom:14px">Browse ${esc(catName)} by sub-category</h2>
         <div style="display:flex;gap:8px;flex-wrap:wrap">
           ${subCategories.map(s => `<a href="${ORIGIN}/local/${cityName.toLowerCase().replace(/ /g,'-')}/${esc(s.slug)}" style="background:#fff;border:1px solid #e2e8f0;padding:9px 16px;border-radius:99px;text-decoration:none;color:#0F172A;font-size:.88rem;font-weight:600;transition:.15s">${esc(s.icon || '')} ${esc(s.name)}</a>`).join('')}
         </div>
       </section>` : '';

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="theme-color" content="#FF6B1A">
<title>${esc(title)}</title>
<meta name="description" content="${esc(desc)}">
<link rel="canonical" href="${esc(url)}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="DukanList">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:url" content="${esc(url)}">
<meta property="og:image" content="${ORIGIN}/assets/og-default.png">
<meta property="og:locale" content="en_IN">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${esc(title)}">
<meta name="twitter:description" content="${esc(desc)}">
<meta name="twitter:image" content="${ORIGIN}/assets/og-default.png">
<link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>🏪</text></svg>">
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@500;600;700;800&family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
<script type="application/ld+json">${JSON.stringify(itemListSchema)}</script>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:'Manrope','Inter',-apple-system,sans-serif;background:#FFFBF5;color:#0F172A;line-height:1.55;-webkit-font-smoothing:antialiased}
  .topbar{background:linear-gradient(135deg,#1E1B4B,#1E3A8A);color:#fff;padding:14px 20px;display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:12px}
  .topbar .brand{display:flex;align-items:center;gap:10px;font-weight:800;font-size:1.1rem;text-decoration:none;color:#fff}
  .topbar .brand .logo{width:36px;height:36px;background:linear-gradient(135deg,#FF6B1A,#E55100);border-radius:10px;display:grid;place-items:center;font-size:1.15rem;box-shadow:0 2px 8px rgba(255,107,26,.4)}
  .topbar nav a{color:rgba(255,255,255,.86);text-decoration:none;padding:7px 13px;border-radius:8px;font-size:.9rem;font-weight:600;margin-left:4px}
  .topbar nav a:hover{background:rgba(255,255,255,.12)}
  .hero{background:radial-gradient(ellipse at top,#FFE9D6,transparent 60%),#FFFBF5;padding:48px 20px 32px;text-align:center}
  .hero h1{font-size:clamp(1.7rem,4.2vw,2.4rem);font-weight:800;letter-spacing:-.02em;color:#0F172A;margin-bottom:8px;line-height:1.15}
  .hero .sub{color:#5A6573;font-size:1rem;max-width:580px;margin:0 auto}
  .crumbs{font-size:.84rem;color:#64748b;margin-bottom:14px}
  .crumbs a{color:#FF6B1A;text-decoration:none;font-weight:600}
  .grid{max-width:1180px;margin:0 auto;padding:24px 20px 64px;display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:18px}
  @media (max-width:560px){ .grid{grid-template-columns:1fr;gap:14px;padding:16px 14px 48px} .hero{padding:36px 16px 24px} }
  .empty{max-width:560px;margin:48px auto;padding:36px 24px;text-align:center;background:#fff;border:1px dashed #cbd5e1;border-radius:14px}
  .empty h2{font-size:1.2rem;font-weight:800;margin-bottom:8px}
  .empty p{color:#5A6573;margin-bottom:16px;font-size:.95rem}
  .btn{display:inline-block;background:linear-gradient(135deg,#FF6B1A,#E55100);color:#fff;padding:10px 22px;border-radius:99px;font-weight:700;font-size:.9rem;text-decoration:none;box-shadow:0 4px 12px rgba(255,107,26,.35)}
  .btn-sec{display:inline-block;background:#fff;color:#0F172A;border:1.5px solid #e2e8f0;padding:9px 20px;border-radius:99px;font-weight:700;font-size:.9rem;text-decoration:none;margin-left:8px}
  footer{background:#0F172A;color:#94a3b8;padding:24px 20px;text-align:center;font-size:.82rem;line-height:1.55}
  footer a{color:#FF6B1A;text-decoration:none;font-weight:600}
</style>
</head>
<body>

<header class="topbar">
  <a href="${ORIGIN}/" class="brand"><span class="logo">🏪</span><span>Dukan<em style="font-style:normal;color:#FFB088">List</em></span></a>
  <nav>
    <a href="${ORIGIN}/browse">Browse</a>
    <a href="${ORIGIN}/search">Search</a>
    <a href="${ORIGIN}/register.html">Register Shop</a>
  </nav>
</header>

<section class="hero">
  <div class="crumbs"><a href="${ORIGIN}/">Home</a> › <a href="${ORIGIN}/browse">Categories</a> › ${esc(catName)} › ${esc(cityName)}</div>
  <h1>${esc(cat.icon || '🏪')} ${esc(catName)} in ${esc(cityName)}</h1>
  <p class="sub">${shops.length > 0 ? shops.length + '+ verified ' + catName.toLowerCase() + ' in ' + cityName + '. Free contact, reviews, ratings.' : 'Be the first ' + catName.toLowerCase() + ' to register in ' + cityName + '!'}</p>
</section>

${shops.length > 0
  ? `<main class="grid">${shops.map(renderShopCard).join('')}</main>`
  : `<div class="empty">
       <h2>No ${esc(catName)} listed yet in ${esc(cityName)}</h2>
       <p>Be the first — register your shop free in 2 minutes and rank #1 in your area.</p>
       <a class="btn" href="${ORIGIN}/register.html?city=${esc(cityName.toLowerCase().replace(/ /g,'-'))}&cat=${esc(cat.slug)}">Register your shop</a>
       <a class="btn-sec" href="${ORIGIN}/browse">Browse all categories</a>
     </div>`
}

${otherCats}

<footer>
  <div style="max-width:680px;margin:0 auto">
    <strong style="color:#fff">DukanList</strong> · Bharat ka local shop directory · हर दुकान, एक पहचान<br>
    DigiMutual Goals Pvt. Ltd. · Mandi Dabwali, Haryana ·
    <a href="${ORIGIN}/about">About</a> · <a href="${ORIGIN}/contact">Contact</a> · <a href="${ORIGIN}/privacy">Privacy</a>
  </div>
</footer>

</body>
</html>`;

  return html;
}

export default async function handler(req, res){
  try {
    let citySlug = (req.query && req.query.city) || null;
    let catSlug  = (req.query && req.query.cat) || null;

    if (!citySlug || !catSlug){
      res.statusCode = 302;
      res.setHeader('Location', ORIGIN + '/browse');
      return res.end();
    }

    citySlug = String(citySlug).toLowerCase();
    catSlug  = String(catSlug).toLowerCase();

    const [city, cat] = await Promise.all([findCity(citySlug), findCategory(catSlug)]);

    if (!city || !cat){
      res.statusCode = 404;
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      return res.end('<!doctype html><meta charset=UTF-8><title>Page not found · DukanList</title><meta http-equiv="refresh" content="0;url=' + ORIGIN + '/browse"><p>Page not found. <a href="' + ORIGIN + '/browse">Browse categories</a></p>');
    }

    const isParent = cat.parent_id === null;
    const shops = await fetchShops(city.id, cat.id, isParent);

    // For parents, also fetch sub-categories to surface as quick links
    let subCategories = null;
    if (isParent){
      subCategories = await sb('categories?select=slug,name,icon&active=eq.true&parent_id=eq.' + cat.id + '&order=sort_order');
    }

    res.statusCode = 200;
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control', 'public, max-age=900, s-maxage=3600, stale-while-revalidate=86400');
    return res.end(renderPage({ city, cat, shops, isParent, subCategories }));

  } catch (err){
    console.error('locality endpoint error:', err);
    res.statusCode = 500;
    res.setHeader('Content-Type', 'text/html');
    return res.end('<p>Sorry, something went wrong. <a href="' + ORIGIN + '/">Go to DukanList →</a></p>');
  }
}
