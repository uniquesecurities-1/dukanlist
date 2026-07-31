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

// ============================================================
// MEGA_SLUGS: user-friendly chip slugs that expand into a SET
// of real category slugs. Mirrors CHIP_TO_SLUGS in
// assets/js/homepage.js — keep both in sync if either changes.
//
// Reason: a "Doctors in Mandi Dabwali" pill should match shops
// registered as dentist, ayurveda, hospital, gynecologist, etc.
// — not just slug=doctor. Same for mechanic, grocery, salon, etc.
//
// When catSlug matches one of these keys, the page treats the
// entire array as the target slug set (uses friendly display
// name and merges results across all member categories).
// Members that don't exist in the categories table are silently
// dropped at resolution time — no error, just fewer ids.
// ============================================================
const MEGA_SLUGS = {
  'doctor':   { slugs: ['doctor','dentist','ayurveda','homeopathy','hospital','physiotherapist','eye-care','gynecologist','pediatrician'],
                name: 'Doctors & Clinics', name_hi: 'डॉक्टर एवं क्लिनिक', icon: '🩺' },
  'mechanic': { slugs: ['mechanic-2w','mechanic-4w','car-service','tyre-shop','spare-parts','cycle-shop','puncture-shop','tractor-parts','battery-shop','car-ac-repair','denting-painting'],
                name: 'Mechanic & Repair', name_hi: 'मैकेनिक एवं रिपेयर', icon: '🔧' },
  'grocery':  { slugs: ['kirana-grocery','general-store','wholesale-dealer'],
                name: 'Grocery / Kirana', name_hi: 'किराना / जनरल स्टोर', icon: '🛒' },
  'salon':    { slugs: ['salon-beauty','unisex-salon','mens-salon','beauty-parlour','salon','spa'],
                name: 'Salon & Beauty', name_hi: 'सैलून एवं ब्यूटी', icon: '💇' },
  'tutor':    { slugs: ['tuition-coaching','coaching-institute','training-institute','skill-vocational','english-speaking','computer-classes','computer-class','art-craft-class'],
                name: 'Tutors & Coaching', name_hi: 'ट्यूटर एवं कोचिंग', icon: '📚' },
  'medical':  { slugs: ['pharmacy'],
                name: 'Medical Store / Pharmacy', name_hi: 'मेडिकल स्टोर / फार्मेसी', icon: '💊' },
  'bakery':   { slugs: ['bakery-cake'],
                name: 'Bakery & Cake Shop', name_hi: 'बेकरी एवं केक शॉप', icon: '🧁' }
};

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

  // Mega-slug path: resolve to all member sub-categories.
  // Returns a synthetic "virtual category" with isMega=true so the
  // handler / renderer / fetcher know to treat catIds as the union.
  const mega = MEGA_SLUGS[catSlug];
  if (mega){
    const inList = mega.slugs.map(s => encodeURIComponent(s)).join(',');
    const rows = await sb('categories?select=id,slug&active=eq.true&slug=in.(' + inList + ')');
    const ids = (rows || []).map(r => r.id);
    if (ids.length === 0) return null;
    return {
      id: ids[0],            // first member — used only as a fallback display id
      ids: ids,              // ALL member ids — used by fetchShops
      name: mega.name,
      name_hi: mega.name_hi,
      icon: mega.icon,
      slug: catSlug,
      parent_id: null,
      isMega: true
    };
  }

  // Normal single-slug path (unchanged).
  const rows = await sb('categories?select=id,name,name_hi,icon,parent_id,slug&active=eq.true&slug=eq.' + encodeURIComponent(catSlug));
  return rows && rows[0] ? rows[0] : null;
}

async function fetchShops(cityId, catId, catIsParent, megaIds){
  // Build list of category IDs to search.
  // - megaIds (from MEGA_SLUGS resolution) → use that union directly
  // - parent  → include all child sub-cat IDs too
  // - leaf    → just the single category id
  let categoryIds;
  if (megaIds && megaIds.length > 0){
    categoryIds = megaIds.slice();
  } else {
    categoryIds = [catId];
    if (catIsParent){
      const subs = await sb('categories?select=id&parent_id=eq.' + catId);
      categoryIds = categoryIds.concat((subs || []).map(s => s.id));
    }
  }
  const catIdsStr = categoryIds.join(',');

  // CRITICAL: DukanList supports multi-category via business_categories join table.
  // A shop's PRIMARY category sits on businesses.category_id, but additional
  // categories live in business_categories(business_id, category_id). If we only
  // query the primary, we miss businesses like Unique Securities where stock-broker
  // is added as a secondary category (their primary is mutual-fund-distributor).
  //
  // Step 1: get all business_ids that have ANY of our target categories linked
  //         in business_categories.
  const bcRows = await sb('business_categories?select=business_id&category_id=in.(' + catIdsStr + ')');
  const linkedIds = Array.from(new Set((bcRows || []).map(r => r.business_id))).filter(Boolean);

  // Step 2: query businesses where EITHER:
  //   (a) primary category_id matches, OR
  //   (b) sub_category_id matches, OR
  //   (c) id is in the multi-category linked list (business_categories).
  const orClauses = [
    'category_id.in.(' + catIdsStr + ')',
    'sub_category_id.in.(' + catIdsStr + ')'
  ];
  if (linkedIds.length > 0){
    orClauses.push('id.in.(' + linkedIds.join(',') + ')');
  }

  const q = 'businesses?select=id,slug,name,name_hi,owner_name,mobile,whatsapp,address_line1,address_line2,pincode,photos,usp_text,rating_avg,rating_count,verified_score,established_year,featured,is_professional_listing,professional_tier,geo_cities(name),categories(name,icon)'
    + '&status=eq.active'
    + '&city_id=eq.' + cityId
    + '&or=(' + orClauses.join(',') + ')'
    + '&order=featured.desc.nullslast,verified_score.desc.nullslast,rating_avg.desc.nullslast'
    + '&limit=40';

  const shops = (await sb(q)) || [];

  // Bulk-fetch Cloudinary photos for all these shops
  if (shops.length) {
    try {
      const bizIds = shops.map(s => s.id).join(',');
      const pq = 'business_photos?select=business_id,cloudinary_url,is_featured'
        + '&business_id=in.(' + bizIds + ')'
        + '&cloudinary_url=not.is.null';
      const photos = (await sb(pq)) || [];
      const map = {};
      photos.forEach(p => {
        if (!p.cloudinary_url) return;
        if (p.is_featured || !map[p.business_id]) {
          map[p.business_id] = p.cloudinary_url;
        }
      });
      shops.forEach(s => { s._cloudPhoto = map[s.id] || null; });
    } catch(pe) { console.warn('[locality] photos fetch skipped', pe); }
  }

  return shops;
}

function pickCardThumb(b){
  if (b._cloudPhoto) {
    return b._cloudPhoto.replace('/upload/', '/upload/w_400,h_240,c_fill,q_auto,f_auto/');
  }
  if (Array.isArray(b.photos) && b.photos.length && typeof b.photos[0] === 'string') {
    return b.photos[0];
  }
  return null;
}

function renderShopCard(b){
  const cityName = b.geo_cities && b.geo_cities.name ? b.geo_cities.name : '';
  const addr = [b.address_line1, b.address_line2].filter(Boolean).join(', ');
  const phone = String(b.whatsapp || b.mobile || '').replace(/\D/g, '').slice(-10);
  const wa = String(b.whatsapp || b.mobile || '').replace(/\D/g, '').slice(-10);
  const waMsg = encodeURIComponent('Hi ' + (b.name || 'there') + ', I found you on DukanList.');
  const thumb = pickCardThumb(b);
  // Fallback placeholder — saffron gradient + category icon + shop name
  const catIcon = (b.categories && b.categories.icon) || '🏪';
  const catName = (b.categories && b.categories.name) || 'Business';
  const thumbHTML = thumb
    ? `<div style="width:100%;position:relative;padding-bottom:62.5%;overflow:hidden;background:#F1F5F9"><img src="${esc(thumb)}" alt="${esc(b.name)}" loading="lazy" style="position:absolute;top:0;left:0;width:100%;height:100%;object-fit:cover;display:block"></div>`
    : `<div style="width:100%;position:relative;padding-bottom:62.5%;overflow:hidden;background:linear-gradient(135deg,#FFF7ED 0%,#FED7AA 40%,#FFB870 100%)"><div style="position:absolute;inset:0;display:flex;align-items:center;justify-content:center;background-image:radial-gradient(circle at 20% 20%, rgba(255,255,255,.5), transparent 45%),radial-gradient(circle at 80% 80%, rgba(255,107,26,.15), transparent 55%)"><div style="font-size:3rem;line-height:1;filter:drop-shadow(0 3px 6px rgba(120,53,15,.20))">${esc(catIcon)}</div></div><div style="position:absolute;bottom:8px;right:10px;font-size:.6rem;font-weight:800;color:#9A3412;letter-spacing:.1em;text-transform:uppercase;opacity:.6">dukanlist</div></div>`;
  const waBtn = wa.length === 10
    ? `<a href="https://wa.me/91${wa}?text=${waMsg}" target="_blank" rel="noopener" onclick="event.stopPropagation()" style="flex:1;display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:10px;border-radius:10px;background:#25D366;color:#fff;font-weight:800;font-size:.85rem;text-decoration:none;border:1.5px solid #25D366">💬 WhatsApp</a>`
    : '';
  const callBtn = phone.length === 10
    ? `<a href="tel:+91${phone}" onclick="event.stopPropagation()" style="flex:1;display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:10px;border-radius:10px;background:#fff;color:#0F2952;font-weight:800;font-size:.85rem;text-decoration:none;border:1.5px solid #E5B84F">📞 Call</a>`
    : '';
  return `
  <article onclick="if(!event.target.closest('a,button')){window.location.href='${ORIGIN}/business.html?slug=${esc(b.slug)}';}" style="background:#fff;border:1px solid rgba(15,23,42,.06);border-radius:14px;padding:0;display:flex;flex-direction:column;gap:0;box-shadow:0 1px 3px rgba(15,23,42,.04);cursor:pointer;overflow:hidden">
    ${thumbHTML}
    <div style="padding:10px 14px;display:flex;flex-direction:column;gap:4px">
      <div style="font-family:'Manrope',sans-serif;font-size:1.1rem;font-weight:900;color:#0F172A;line-height:1.2"><span style="color:#FF6B1A">🏢</span> ${esc(b.name)}</div>
      ${b.owner_name ? `<div style="font-size:.82rem;color:#475569;display:flex;align-items:center;gap:5px"><span>👤</span> <b style="color:#0F172A">${esc(b.owner_name)}</b></div>` : ''}
      ${phone ? `<div style="font-size:.82rem;color:#475569;display:flex;align-items:center;gap:5px;font-family:monospace"><span>📱</span> +91-${phone}</div>` : ''}
      ${addr ? `<div style="font-size:.82rem;color:#475569;display:flex;align-items:flex-start;gap:5px;line-height:1.4"><span style="color:#DC2626;flex-shrink:0">📍</span> ${esc(addr)}</div>` : ''}
      ${cityName ? `<div style="font-size:.78rem;color:#64748B;display:flex;align-items:center;gap:5px"><span>🏙️</span> ${esc(cityName)}</div>` : ''}
      <div style="display:flex;gap:8px;margin-top:8px;padding-top:10px;border-top:1px dashed #E2E8F0">${waBtn}${callBtn}</div>
    </div>
  </article>`;
}

function renderPage(opts){
  const { city, cat, shops, isParent, subCategories } = opts;
  const cityName = city.name;
  const catName  = cat.name;
  const url = `${ORIGIN}/local/${cityName.toLowerCase().replace(/ /g,'-')}/${cat.slug}`;
  const title = `${catName} in ${cityName} — Top ${shops.length}+ Verified Shops · DukanList`;
  const desc  = `Find the best ${catName.toLowerCase()} in ${cityName}. ${shops.length} verified local shops with reviews, ratings, contact details. Real reviews from local people. Updated daily on DukanList — Bharat ka local shop directory.`;

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
        "aggregateRating": (s.rating_count > 0 && !(s.is_professional_listing === true && s.professional_tier === 'strict')) ? { "@type": "AggregateRating", "ratingValue": s.rating_avg, "reviewCount": s.rating_count } : undefined
      }
    }))
  };

  // BreadcrumbList — adds rich-snippet trail in SERPs (CTR +30-50%)
  const citySlug = cityName.toLowerCase().replace(/ /g,'-');
  const breadcrumbSchema = {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    "itemListElement": [
      { "@type": "ListItem", "position": 1, "name": "Home",       "item": `${ORIGIN}/` },
      { "@type": "ListItem", "position": 2, "name": "Browse",     "item": `${ORIGIN}/browse.html` },
      { "@type": "ListItem", "position": 3, "name": catName,      "item": `${ORIGIN}/search.html?cat=${cat.slug}` },
      { "@type": "ListItem", "position": 4, "name": cityName,     "item": url }
    ]
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
<link rel="alternate" hreflang="en-IN" href="${esc(url)}">
<link rel="alternate" hreflang="hi-IN" href="${esc(url)}?lang=hi">
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
<script type="application/ld+json">${JSON.stringify(breadcrumbSchema)}</script>
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
    const isMega = !!cat.isMega;
    // Mega-slug: pass the resolved member-id list straight to fetchShops.
    // Parent: include child sub-cats. Leaf: single category id.
    const shops = await fetchShops(city.id, cat.id, isParent && !isMega, isMega ? cat.ids : null);

    // For real parents (NOT mega), also fetch sub-categories to surface as quick links.
    // Mega-slug pages don't surface a sub-cat strip — the mega already IS the union.
    let subCategories = null;
    if (isParent && !isMega){
      subCategories = await sb('categories?select=slug,name,icon&active=eq.true&parent_id=eq.' + cat.id + '&order=sort_order');
    }

    res.statusCode = 200;
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control', 'public, max-age=60, s-maxage=60, stale-while-revalidate=300');
    return res.end(renderPage({ city, cat, shops, isParent, subCategories }));

  } catch (err){
    console.error('locality endpoint error:', err);
    res.statusCode = 500;
    res.setHeader('Content-Type', 'text/html');
    return res.end('<p>Sorry, something went wrong. <a href="' + ORIGIN + '/">Go to DukanList →</a></p>');
  }
}
