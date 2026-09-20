// =====================================================
// api/biz.js — SERVER-RENDERED business page (SEO)
// =====================================================
// WHY THIS EXISTS
// ---------------
// business.html is a client-rendered page: the raw HTML that a
// crawler receives on its FIRST pass contains
//     <title>Business Details — dukanlist.com</title>
//     <link rel="canonical" href="">
//     <meta name="description" content="">
//     <h1 id="bizName"></h1>
//     …and the visible text "Business not found"
// Everything real is filled in later by JS from Supabase.
//
// With ~2,500 URLs in the sitemap, Google was being served 2,500
// byte-identical empty pages with the same title. That reads as
// duplicate/soft-404 content, so nothing indexed and nothing ranked.
// Googlebot CAN execute JS, but it is a separate, slow queue that a
// young low-authority domain rarely gets much of.
//
// WHAT THIS DOES
// --------------
// Fetches the business server-side, then injects the real values into
// the EXISTING business.html template — same markup, same script tags,
// same look. The client JS still runs and overwrites the same elements
// with identical content, so there is no flash and no duplication.
// Humans get exactly the page they got before; crawlers now get a page
// with a title, a description, a canonical, an <h1>, an address, hours
// and JSON-LD.
//
// Wired up in vercel.json:  /:slug  ->  /api/biz?slug=:slug
// =====================================================

// Same fallbacks api/share.js uses — the anon key is public by design (it is
// already shipped to every browser in assets/js/supabase-init.js). Without
// these, an unset env var in Vercel silently made every page a 404.
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://qazuyygrpqopwygxmvwq.supabase.co';
const ANON_KEY     = process.env.SUPABASE_ANON_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFhenV5eWdycHFvcHd5Z3htdndxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxNTUwOTEsImV4cCI6MjA5NDczMTA5MX0.FR8x2kldC2yelpPnK2QKd5WGwHUAQheCVmxfs6hR00I';
const ORIGIN       = process.env.PUBLIC_SITE_URL || 'https://dukanlist.com';

// Template cached per cold start (277 KB — fetched once, not per request)
let TEMPLATE = null;

function esc(s){
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}
// For text placed inside an HTML attribute we also kill newlines
function attr(s){ return esc(s).replace(/\s+/g, ' ').trim(); }

async function getTemplate(){
  if (TEMPLATE) return TEMPLATE;
  const r = await fetch(ORIGIN + '/business.html', {
    headers: { 'User-Agent': 'dukanlist-ssr' }
  });
  if (!r.ok) throw new Error('template fetch failed: ' + r.status);
  TEMPLATE = await r.text();
  return TEMPLATE;
}

// Returns an array on success. THROWS on transport/HTTP failure so the
// caller can tell "this slug does not exist" (real 404) apart from "our
// backend hiccuped" (must NOT be reported to Google as a 404).
async function sb(path){
  const r = await fetch(SUPABASE_URL + '/rest/v1' + path, {
    headers: { apikey: ANON_KEY, Authorization: 'Bearer ' + ANON_KEY }
  });
  if (!r.ok) throw new Error('supabase ' + r.status + ': ' + (await r.text()).slice(0, 200));
  return r.json();
}

function hoursToSchema(hours){
  // hours_json: { mon:{open:'09:00',close:'21:00',closed:false}, ... }
  if (!hours || typeof hours !== 'object') return null;
  const MAP = { mon:'Monday', tue:'Tuesday', wed:'Wednesday', thu:'Thursday',
                fri:'Friday', sat:'Saturday', sun:'Sunday' };
  const out = [];
  Object.keys(MAP).forEach(function(k){
    const d = hours[k];
    if (!d || d.closed || !d.open || !d.close) return;
    out.push({
      '@type': 'OpeningHoursSpecification',
      dayOfWeek: 'https://schema.org/' + MAP[k],
      opens: d.open, closes: d.close
    });
  });
  return out.length ? out : null;
}

function hoursToText(hours){
  if (!hours || typeof hours !== 'object') return '';
  const MAP = { mon:'Mon', tue:'Tue', wed:'Wed', thu:'Thu', fri:'Fri', sat:'Sat', sun:'Sun' };
  const parts = [];
  Object.keys(MAP).forEach(function(k){
    const d = hours[k];
    if (!d) return;
    parts.push(MAP[k] + ': ' + (d.closed || !d.open ? 'Closed' : d.open + '–' + d.close));
  });
  return parts.join(' · ');
}

module.exports = async (req, res) => {
  const url  = new URL(req.url, 'http://' + (req.headers.host || 'dukanlist.com'));
  const slug = (url.searchParams.get('slug') || '').toLowerCase().trim();

  // Same shape the vercel rewrite guarantees, but never trust it blindly
  if (!/^[a-z0-9-]{3,80}$/.test(slug)){
    res.statusCode = 404;
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.end('<!doctype html><meta charset="utf-8"><title>Not found</title><p>Invalid listing link.</p>');
    return;
  }

  let html;
  try {
    html = await getTemplate();
  } catch (e) {
    // Template unavailable — fall back to a plain redirect so the page
    // still works for humans even if SSR is broken.
    res.statusCode = 302;
    res.setHeader('Location', '/business?slug=' + encodeURIComponent(slug));
    res.end();
    return;
  }

  let rows = null;
  let backendFailed = false;
  try {
    rows = await sb('/businesses?slug=eq.' + encodeURIComponent(slug) +
      '&status=eq.active&limit=1' +
      '&select=id,name,name_hi,slug,usp_text,about_text,address_line1,address_line2,pincode,' +
      'mobile,whatsapp,photos,rating_avg,rating_count,established_year,hours_json,lat,lng,' +
      'claim_status,is_professional_listing,professional_tier,og_image_url,' +
      'categories:category_id(name,name_hi,slug),geo_cities(name,name_hi),geo_localities(name)');
  } catch (e) {
    rows = null;
    backendFailed = true;
    console.error('[api/biz] supabase lookup failed for', slug, '-', e && e.message);
  }

  const b = Array.isArray(rows) && rows[0] ? rows[0] : null;

  // If OUR backend broke, serve the normal client-rendered page with a 200.
  // The visitor's browser will fetch the data itself and the page works as
  // before. Critically, we must never answer 404 for a live listing just
  // because Supabase blipped — Google would deindex it.
  if (!b && backendFailed){
    res.statusCode = 200;
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.end(html);
    return;
  }

  if (!b){
    // Genuinely no such active listing → real 404 so Google drops dead slugs
    res.statusCode = 404;
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control', 'public, s-maxage=300');
    res.end(html
      .replace('<title>Business Details — dukanlist.com</title>',
               '<title>Listing not found — dukanlist.com</title>')
      .replace('</head>', '<meta name="robots" content="noindex, follow">\n</head>'));
    return;
  }

  // ---------- derive the SEO strings ----------
  const cat      = (b.categories && b.categories.name) || 'Local Business';
  const city     = (b.geo_cities && b.geo_cities.name) || 'Mandi Dabwali';
  const locality = (b.geo_localities && b.geo_localities.name) || '';
  const addr     = [b.address_line1, b.address_line2, locality, city, b.pincode]
                     .filter(Boolean).join(', ');
  const canon    = ORIGIN + '/' + b.slug;
  const rating   = Number(b.rating_avg) || 0;
  const rcount   = Number(b.rating_count) || 0;
  const photo    = (Array.isArray(b.photos) && b.photos[0]) || (ORIGIN + '/assets/og-default.png');

  const title = b.name + ' — ' + cat + ' in ' + city + ' | DukanList';

  let desc = b.usp_text || b.about_text || '';
  desc = String(desc).replace(/\s+/g, ' ').trim();
  if (!desc){
    desc = b.name + ' is a ' + cat + ' in ' + city + '.';
  }
  if (addr) desc += ' Address: ' + addr + '.';
  if (rcount > 0) desc += ' Rated ' + rating.toFixed(1) + '/5 from ' + rcount + ' review' + (rcount === 1 ? '' : 's') + '.';
  desc += ' Contact details, timings and directions on DukanList.';
  if (desc.length > 300) desc = desc.slice(0, 297).trim() + '…';

  // ---------- JSON-LD ----------
  const ld = {
    '@context': 'https://schema.org',
    '@type': 'LocalBusiness',
    '@id': canon,
    name: b.name,
    url: canon,
    image: photo,
    description: desc,
    address: {
      '@type': 'PostalAddress',
      streetAddress: [b.address_line1, b.address_line2].filter(Boolean).join(', ') || undefined,
      addressLocality: locality || city,
      addressRegion: city,
      postalCode: b.pincode || undefined,
      addressCountry: 'IN'
    }
  };
  // Claim-locked listings hide contact details on the page — don't leak them in schema either
  const contactVisible = b.claim_status !== 'claimed_pending';
  if (contactVisible && b.mobile) ld.telephone = '+91' + String(b.mobile).replace(/\D/g, '').slice(-10);
  if (b.lat && b.lng) ld.geo = { '@type': 'GeoCoordinates', latitude: b.lat, longitude: b.lng };
  if (b.established_year) ld.foundingDate = String(b.established_year);
  if (rcount > 0){
    ld.aggregateRating = {
      '@type': 'AggregateRating',
      ratingValue: rating.toFixed(1),
      reviewCount: rcount,
      bestRating: '5', worstRating: '1'
    };
  }
  const oh = hoursToSchema(b.hours_json);
  if (oh) ld.openingHoursSpecification = oh;

  const breadcrumb = {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: [
      { '@type':'ListItem', position:1, name:'DukanList', item: ORIGIN },
      { '@type':'ListItem', position:2, name: city, item: ORIGIN + '/search.html?city=' + encodeURIComponent(city) },
      { '@type':'ListItem', position:3, name: b.name, item: canon }
    ]
  };

  // JSON-LD must not be able to break out of the <script> block
  const ldJson = JSON.stringify([ld, breadcrumb]).replace(/</g, '\\u003c');

  // Social preview image. Same priority share.js uses: shopkeeper-set og_image_url,
  // then the shop's own first photo, else the branded PNG default. WhatsApp's
  // crawler cannot render SVG, so an SVG og_image_url is skipped here.
  let ogImage = 'https://dukanlist.com/assets/og-default.png';
  if (b.og_image_url && typeof b.og_image_url === 'string' && !/\.svg(\?|$)/i.test(b.og_image_url)){
    ogImage = b.og_image_url;
  } else if (Array.isArray(b.photos) && typeof b.photos[0] === 'string' && b.photos[0]){
    ogImage = b.photos[0];
  }

  // ---------- inject ----------
  html = html
    .replace('<title>Business Details — dukanlist.com</title>',
             '<title>' + esc(title) + '</title>')
    .replace('<meta name="description" id="metaDesc" content="">',
             '<meta name="description" id="metaDesc" content="' + attr(desc) + '">')
    .replace('<link rel="canonical" id="canonicalLink" href="">',
             '<link rel="canonical" id="canonicalLink" href="' + attr(canon) + '">')
    .replace('<meta property="og:title" id="ogTitle" content="DukanList — Every Business, One Identity">',
             '<meta property="og:title" id="ogTitle" content="' + attr(title) + '">')
    .replace('<meta property="og:description" id="ogDesc" content="Discover this business on DukanList — Mandi Dabwali ka local listings directory.">',
             '<meta property="og:description" id="ogDesc" content="' + attr(desc) + '">')
    .replace('<meta property="og:image" id="ogImage" content="https://dukanlist.com/assets/og-default.png">',
             '<meta property="og:image" id="ogImage" content="' + attr(ogImage) + '">')
    // Twitter reads its own tags before falling back to og:*, and ours carried
    // the generic site copy — so a shared link showed "Every Business, One Identity".
    .replace('<meta name="twitter:title" id="twTitle" content="DukanList — Every Business, One Identity">',
             '<meta name="twitter:title" id="twTitle" content="' + attr(title) + '">')
    .replace('<meta name="twitter:description" id="twDesc" content="Discover this business on DukanList.">',
             '<meta name="twitter:description" id="twDesc" content="' + attr(desc) + '">')
    .replace('<meta name="twitter:image" id="twImage" content="https://dukanlist.com/assets/og-default.png">',
             '<meta name="twitter:image" id="twImage" content="' + attr(ogImage) + '">')
    // fill the heading the crawler currently sees empty
    .replace('<h1 class="biz-title" id="bizName"></h1>',
             '<h1 class="biz-title" id="bizName">' + esc(b.name) + '</h1>')
    .replace('<span class="biz-cat-pill" id="bizCatPill"></span>',
             '<span class="biz-cat-pill" id="bizCatPill">' + esc(cat) + '</span>');

  // A crawlable summary of the same facts the page renders. It sits at the
  // END of <body> in normal flow (NOT hidden with CSS — hidden text can read
  // as cloaking) and is removed by the inline script below as soon as the
  // real UI is up, so a human never sees it.
  const ssrBlock =
    '<div id="ssrSeoSummary" style="max-width:1100px;margin:0 auto;padding:16px;color:#475569;font:14px/1.6 system-ui,sans-serif">' +
      '<h2>' + esc(b.name) + (b.name_hi ? ' / ' + esc(b.name_hi) : '') + '</h2>' +
      '<p>' + esc(cat) + ' in ' + esc(city) + (locality ? ', ' + esc(locality) : '') + '</p>' +
      (addr ? '<p>Address: ' + esc(addr) + '</p>' : '') +
      (rcount > 0 ? '<p>Rating ' + rating.toFixed(1) + ' out of 5 from ' + rcount + ' reviews</p>' : '') +
      (b.usp_text ? '<p>' + esc(b.usp_text) + '</p>' : '') +
      (b.about_text ? '<p>' + esc(String(b.about_text).slice(0, 600)) + '</p>' : '') +
      (b.hours_json ? '<p>Hours: ' + esc(hoursToText(b.hours_json)) + '</p>' : '') +
      (b.established_year ? '<p>Serving since ' + esc(b.established_year) + '</p>' : '') +
    '</div>';

  html = html
    .replace('</head>',
      '<script type="application/ld+json">' + ldJson + '</script>\n</head>')
    .replace('</body>',
      ssrBlock +
      '<script>(function(){function go(){var e=document.getElementById("ssrSeoSummary");if(e&&e.parentNode)e.parentNode.removeChild(e);}' +
      'if(document.readyState==="loading"){document.addEventListener("DOMContentLoaded",function(){setTimeout(go,50)});}else{setTimeout(go,50);}})();</script>' +
      '\n</body>');

  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  // Cache at the edge so we are not hitting Supabase on every crawl
  res.setHeader('Cache-Control', 'public, s-maxage=600, stale-while-revalidate=86400');
  res.end(html);
};
