// =====================================================
// api/area.js
// Hyperlocal SEO landing pages — /area/:city/:locality
//
// Server-rendered (Google can index without JS).
// Aggressively edge-cached. Empty pages still render (with CTA).
//
// Example URLs:
//   /area/mandi-dabwali/meena-bazaar
//   /area/mandi-dabwali/chotala-road
//   /area/sirsa/main-bazaar
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

async function rpc(fn, body){
  const r = await fetch(SUPABASE_URL + '/rest/v1/rpc/' + fn, {
    method: 'POST',
    headers: {
      'apikey': SUPABASE_ANON_KEY,
      'Authorization': 'Bearer ' + SUPABASE_ANON_KEY,
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    },
    body: JSON.stringify(body || {})
  });
  if (!r.ok) return null;
  return r.json();
}

async function siblingLocalities(citySlug, excludeSlug){
  const all = await rpc('list_localities_by_city', { p_city_slug: citySlug });
  if (!Array.isArray(all)) return [];
  return all.filter(l => l.slug !== excludeSlug).slice(0, 12);
}

function renderShopCard(b){
  const photo = (b.photos && b.photos.length) ? b.photos[0] : null;
  const rating = b.rating_avg > 0
    ? `<span style="color:#0F172A;font-weight:700">⭐ ${Number(b.rating_avg).toFixed(1)} <span style="font-weight:500;color:#64748b">(${b.rating_count || 0})</span></span>`
    : '<span style="color:#94a3b8;font-size:.8rem">New listing</span>';
  const verifPill = (b.verified_score >= 3)
    ? `<span style="background:#DCFCE7;color:#166534;padding:2px 8px;border-radius:99px;font-size:11px;font-weight:800;letter-spacing:.03em">✓ VERIFIED</span>`
    : '';
  return `
  <a href="${ORIGIN}/business.html?slug=${esc(b.slug)}" style="background:#fff;border:1px solid rgba(15,23,42,.06);border-radius:14px;overflow:hidden;text-decoration:none;color:inherit;display:flex;flex-direction:column;box-shadow:0 1px 3px rgba(15,23,42,.04)">
    ${photo
      ? `<img src="${esc(photo)}" alt="${esc(b.name)}" style="width:100%;aspect-ratio:16/10;object-fit:cover" loading="lazy">`
      : `<div style="width:100%;aspect-ratio:16/10;background:linear-gradient(135deg,#FAFAFA,#F1F5F9);display:grid;place-items:center;font-size:3rem;opacity:.5">${esc(b.category_icon || '🏪')}</div>`
    }
    <div style="padding:14px;display:flex;flex-direction:column;gap:6px">
      <div style="display:flex;gap:6px;flex-wrap:wrap">${verifPill}</div>
      <div style="font-weight:700;font-size:1.05rem;color:#0F172A;line-height:1.3">${esc(b.name)}</div>
      ${b.category_name ? `<div style="font-size:.78rem;color:#FF6B1A;font-weight:700">${esc(b.category_icon || '')} ${esc(b.category_name)}</div>` : ''}
      ${b.usp_text ? `<div style="font-size:.85rem;color:#5A6573;line-height:1.4;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden">${esc(b.usp_text)}</div>` : ''}
      <div style="display:flex;justify-content:space-between;align-items:center;font-size:.82rem;color:#64748b;margin-top:6px;padding-top:8px;border-top:1px solid #f1f5f9">
        ${rating}
        <span>📍 ${esc(b.locality_name || '')}</span>
      </div>
    </div>
  </a>`;
}

function renderPage(opts){
  const { citySlug, localitySlug, shops, siblings } = opts;
  // Title-case the slugs for display when we don't have a canonical name (empty result page)
  const titleCase = (s) => s.replace(/-/g, ' ').replace(/\b\w/g, ch => ch.toUpperCase());
  const cityName     = shops.length ? shops[0].city_name     : titleCase(citySlug);
  const localityName = shops.length ? shops[0].locality_name : titleCase(localitySlug);

  const url   = `${ORIGIN}/area/${citySlug}/${localitySlug}`;
  const title = `Shops in ${localityName}, ${cityName} — ${shops.length} Verified Local Businesses · DukanList`;
  const desc  = shops.length
    ? `Browse ${shops.length} verified shops in ${localityName}, ${cityName} — direct contact, photos, ratings. Doctor, grocery, repair, mobile shops and more. Free local directory on DukanList.`
    : `${localityName} in ${cityName} — be the first to list your shop here! 100% free, lifetime listing. Direct WhatsApp + call leads from your area.`;

  const breadcrumbSchema = {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    "itemListElement": [
      { "@type": "ListItem", "position": 1, "name": "Home",     "item": `${ORIGIN}/` },
      { "@type": "ListItem", "position": 2, "name": cityName,   "item": `${ORIGIN}/search.html?city=${citySlug}` },
      { "@type": "ListItem", "position": 3, "name": localityName, "item": url }
    ]
  };

  const itemListSchema = shops.length ? {
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
        "address": { "@type": "PostalAddress", "addressLocality": cityName, "streetAddress": localityName },
        "aggregateRating": s.rating_count > 0
          ? { "@type": "AggregateRating", "ratingValue": s.rating_avg, "reviewCount": s.rating_count }
          : undefined
      }
    }))
  } : null;

  const siblingChips = (siblings || []).map(l => `
    <a href="${ORIGIN}/area/${citySlug}/${esc(l.slug)}" style="background:#fff;border:1px solid #FED7AA;color:#9A3412;padding:7px 14px;border-radius:99px;font-size:.85rem;font-weight:600;text-decoration:none">
      📍 ${esc(l.name)} ${l.shop_count > 0 ? `<span style="background:#FEF3C7;color:#92400E;padding:1px 7px;border-radius:99px;font-size:.7rem;font-weight:700;margin-left:4px">${l.shop_count}</span>` : ''}
    </a>`).join('');

  const emptyState = shops.length === 0
    ? `<div style="background:#FFF7ED;border:1px dashed #FB923C;border-radius:18px;padding:40px 24px;text-align:center;margin:24px 0">
         <div style="font-size:3rem;margin-bottom:10px">📍</div>
         <h2 style="font-size:1.4rem;font-weight:800;color:#0F172A;margin:0 0 8px">No shops in ${esc(localityName)} yet</h2>
         <p style="color:#64748B;margin:0 0 20px;font-size:.95rem">Be the first to list your shop in this area — 100% free, takes 2 minutes.</p>
         <a href="${ORIGIN}/register.html" style="display:inline-block;background:linear-gradient(135deg,#FF6B1A,#E55100);color:#fff;padding:12px 28px;border-radius:99px;font-weight:800;text-decoration:none;font-size:.95rem;box-shadow:0 8px 20px rgba(255,107,26,.3)">List your shop FREE →</a>
       </div>`
    : '';

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${esc(title)}</title>
<meta name="description" content="${esc(desc)}">
<link rel="canonical" href="${esc(url)}">

<!-- Open Graph -->
<meta property="og:type" content="website">
<meta property="og:url" content="${esc(url)}">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:image" content="${ORIGIN}/assets/og-default.png">
<meta property="og:site_name" content="DukanList">

<!-- Twitter -->
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${esc(title)}">
<meta name="twitter:description" content="${esc(desc)}">

<!-- Schema.org -->
<script type="application/ld+json">${JSON.stringify(breadcrumbSchema)}</script>
${itemListSchema ? `<script type="application/ld+json">${JSON.stringify(itemListSchema)}</script>` : ''}

<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800;900&family=Manrope:wght@500;700;800;900&display=swap" rel="stylesheet">
<style>
  *,*::before,*::after{box-sizing:border-box}
  body{margin:0;font-family:'Plus Jakarta Sans','Manrope',-apple-system,sans-serif;background:#FAFAFA;color:#0F172A;line-height:1.6}
  .topbar{background:#fff;border-bottom:1px solid #e2e8f0;padding:12px 20px;display:flex;align-items:center;justify-content:space-between}
  .topbar a.brand{font-weight:900;font-size:1.1rem;color:#0F172A;text-decoration:none;letter-spacing:-.02em}
  .topbar a.brand .badge{background:#FFF7ED;color:#9A3412;font-size:.6rem;font-weight:800;padding:2px 7px;border-radius:5px;margin-left:5px;letter-spacing:.06em}
  .topbar .actions a{margin-left:14px;color:#475569;font-size:.85rem;text-decoration:none;font-weight:600}
  .crumb{max-width:1180px;margin:0 auto;padding:14px 20px 0;font-size:.85rem;color:#64748B}
  .crumb a{color:#FF6B1A;text-decoration:none;font-weight:700}
  .hero{max-width:1180px;margin:0 auto;padding:14px 20px 28px}
  .hero h1{font-family:'Manrope',sans-serif;font-size:2rem;font-weight:900;letter-spacing:-.025em;color:#0F172A;margin:6px 0 10px;line-height:1.2}
  .hero h1 .grad{background:linear-gradient(135deg,#FF6B1A,#E55100);-webkit-background-clip:text;background-clip:text;color:transparent}
  .hero .sub{color:#475569;font-size:1rem;max-width:780px}
  .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:18px;max-width:1180px;margin:0 auto;padding:0 20px}
  .sib-strip{max-width:1180px;margin:36px auto 0;padding:0 20px}
  .sib-strip h3{font-size:1.05rem;font-weight:800;color:#0F172A;margin:0 0 12px}
  .sib-chips{display:flex;gap:8px;flex-wrap:wrap}
  .footer{margin-top:60px;padding:30px 20px;background:#0F172A;color:#94A3B8;font-size:.85rem;text-align:center}
  .footer a{color:#FFB68A;text-decoration:none}
  @media(max-width:560px){
    .hero h1{font-size:1.6rem}
    .grid{grid-template-columns:1fr}
  }
</style>
</head>
<body>

<header class="topbar">
  <a class="brand" href="${ORIGIN}/">DukanList<span class="badge">LOCAL</span></a>
  <div class="actions">
    <a href="${ORIGIN}/search.html?city=${citySlug}">Search ${esc(cityName)}</a>
    <a href="${ORIGIN}/register.html">+ List Free</a>
  </div>
</header>

<nav class="crumb" aria-label="Breadcrumb">
  <a href="${ORIGIN}/">Home</a> ›
  <a href="${ORIGIN}/search.html?city=${citySlug}">${esc(cityName)}</a> ›
  <span style="color:#0F172A;font-weight:600">${esc(localityName)}</span>
</nav>

<section class="hero">
  <div style="display:inline-block;background:#FFF7ED;color:#9A3412;padding:4px 12px;border-radius:99px;font-size:.78rem;font-weight:800;letter-spacing:.04em">📍 HYPERLOCAL · ${esc(cityName).toUpperCase()}</div>
  <h1>Shops in <span class="grad">${esc(localityName)}</span></h1>
  <p class="sub">${shops.length > 0
    ? `${shops.length} verified shops in ${esc(localityName)}, ${esc(cityName)} — direct contact, photos, real reviews. One tap to call or WhatsApp.`
    : `Be the first shop listed in ${esc(localityName)}. Free forever, takes just 2 minutes.`}</p>
</section>

${emptyState}

${shops.length > 0 ? `<section class="grid">${shops.map(renderShopCard).join('')}</section>` : ''}

${siblingChips ? `
<section class="sib-strip">
  <h3>Other areas in ${esc(cityName)}</h3>
  <div class="sib-chips">${siblingChips}</div>
</section>` : ''}

<footer class="footer">
  <p>© ${new Date().getFullYear()} <b>DukanList</b> · Bharat ka local business directory · <a href="${ORIGIN}/">Home</a> · <a href="${ORIGIN}/register.html">List Your Shop FREE</a></p>
</footer>

</body>
</html>`;
}

module.exports = async (req, res) => {
  try {
    const url = new URL(req.url, `http://${req.headers.host}`);
    const citySlug     = (url.searchParams.get('city')     || '').toLowerCase().trim();
    const localitySlug = (url.searchParams.get('locality') || '').toLowerCase().trim();

    if (!citySlug || !localitySlug){
      res.statusCode = 400;
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      return res.end('<h1>Bad request</h1><p>Missing city or locality slug.</p>');
    }

    // Fetch shops + sibling areas in parallel
    const [shops, siblings] = await Promise.all([
      rpc('get_shops_by_locality', { p_city_slug: citySlug, p_locality_slug: localitySlug, p_limit: 50 }),
      siblingLocalities(citySlug, localitySlug)
    ]);

    const html = renderPage({
      citySlug,
      localitySlug,
      shops: Array.isArray(shops) ? shops : [],
      siblings: Array.isArray(siblings) ? siblings : []
    });

    res.statusCode = 200;
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control', 's-maxage=3600, stale-while-revalidate=86400');
    res.end(html);
  } catch (e) {
    res.statusCode = 500;
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.end('<h1>Something went wrong</h1><p>' + (e && e.message ? esc(e.message) : 'Unknown error') + '</p>');
  }
};
