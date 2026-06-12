// =====================================================
// api/share.js
// Shareable preview endpoint for WhatsApp / Facebook / Twitter.
//
// Crawlers don't run JS, so business.html (a static page) can't have
// per-shop og:image / og:title.  This endpoint:
//   1. Reads ?slug=X or ?id=X
//   2. Fetches that business from Supabase via REST (anon key, RLS-safe)
//   3. Returns an HTML stub with dynamic OG / Twitter meta tags
//   4. Auto-redirects (meta refresh + JS) the real human to /business.html
//
// When a user shares  https://dukanlist.com/share?slug=sharma-medical
// on WhatsApp:
//   - WhatsApp's crawler hits this endpoint, sees the rich OG meta,
//     renders a beautiful card with name + city + description.
//   - The recipient who taps the link is instantly redirected to the
//     full business profile.
// =====================================================

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://qazuyygrpqopwygxmvwq.supabase.co';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFhenV5eWdycHFvcHd5Z3htdndxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxNTUwOTEsImV4cCI6MjA5NDczMTA5MX0.FR8x2kldC2yelpPnK2QKd5WGwHUAQheCVmxfs6hR00I';

const SITE_ORIGIN = 'https://dukanlist.com';
const DEFAULT_OG_IMAGE = SITE_ORIGIN + '/assets/og-default.png';

function escapeHtml(s){
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function escapeAttr(s){ return escapeHtml(s); }

function truncate(s, n){
  s = String(s || '').trim().replace(/\s+/g, ' ');
  return s.length > n ? s.slice(0, n - 1) + '…' : s;
}

async function fetchBusiness(field, value){
  const url = SUPABASE_URL + '/rest/v1/businesses' +
    '?select=name,slug,id,usp_text,about_text,photos,rating_avg,rating_count,mobile,owner_name,og_image_url,geo_cities(name),geo_localities(name)' +
    '&' + field + '=eq.' + encodeURIComponent(value) +
    '&status=eq.active' +
    '&limit=1';
  const r = await fetch(url, {
    headers: {
      'apikey': SUPABASE_ANON_KEY,
      'Authorization': 'Bearer ' + SUPABASE_ANON_KEY,
      'Accept': 'application/json'
    }
  });
  if (!r.ok) return null;
  const rows = await r.json();
  return rows && rows.length ? rows[0] : null;
}

function renderHtml(biz, targetUrl, isReview){
  // ----- SHOP-FIRST title with star rating
  const name = biz.name || 'Local Shop';
  const city = biz.geo_cities && biz.geo_cities.name ? biz.geo_cities.name : '';
  const locality = biz.geo_localities && biz.geo_localities.name ? biz.geo_localities.name : '';
  const place = [locality, city].filter(Boolean).join(', ');
  const ratingAvg = Number(biz.rating_avg) || 0;
  const ratingCount = Number(biz.rating_count) || 0;
  const hasRating = ratingCount > 0 && ratingAvg > 0;
  const ratingStr = hasRating
    ? ('\u2b50 ' + ratingAvg.toFixed(1) + ' (' + ratingCount + ' review' + (ratingCount === 1 ? '' : 's') + ')')
    : '';

  // Title: shop-first; review-prompt leads with a soft ask
  let title;
  if (isReview){
    let parts = ['\u2728 ' + name];
    if (place) parts.push(place);
    title = truncate(parts.join(' \u00b7 ') + ' \u2014 Rate your experience', 100);
  } else {
    let titleParts = [name];
    if (hasRating) titleParts.push('\u2b50 ' + ratingAvg.toFixed(1));
    if (place)     titleParts.push(place);
    title = truncate(titleParts.join(' \u00b7 '), 100);
  }

  // ----- SHOP-FIRST description with rating up front
  let descParts = [];
  if (isReview){
    descParts.push('Hi! Thank you for choosing ' + name + '.');
    descParts.push('Tap to share a quick rating \u2014 it takes 10 seconds and means a lot to us.');
  } else {
    if (ratingStr) descParts.push(ratingStr + '.');
    if (biz.usp_text)         descParts.push(biz.usp_text);
    else if (biz.about_text)  descParts.push(biz.about_text);
    if (biz.owner_name && biz.mobile){
      descParts.push('Call ' + biz.owner_name + ' at +91-' + biz.mobile + '.');
    } else if (biz.mobile){
      descParts.push('Call +91-' + biz.mobile + '.');
    }
    if (place) descParts.push(place + '.');
    if (!descParts.length) descParts.push(name + ' \u2014 your local shop. Tap to view photos, ratings & contact.');
  }
  const desc = truncate(descParts.join(' '), 200);

  // ----- IMAGE preference
  // For review-prompt shares: PREFER shop's own photo (no DukanList branding).
  // Standard shares: use generated OG card if available, else photo, else default.
  let image = DEFAULT_OG_IMAGE;
  let imageType = 'image/png';
  const hasShopPhoto = biz.photos && Array.isArray(biz.photos) && biz.photos.length && typeof biz.photos[0] === 'string';
  if (isReview){
    if (hasShopPhoto){
      // Best: shop's own photo (clean, no branding)
      image = biz.photos[0];
      imageType = 'image/jpeg';
    } else {
      // Fallback: dynamic shop-branded card with shop name + city + stars
      // (NEVER falls back to DukanList default for review shares)
      image = SITE_ORIGIN + '/api/og-card?slug=' + encodeURIComponent(biz.slug || '');
      imageType = 'image/svg+xml';
    }
  } else {
    if (biz.og_image_url && typeof biz.og_image_url === 'string'){
      image = biz.og_image_url;
    } else if (hasShopPhoto){
      image = biz.photos[0];
      imageType = 'image/jpeg';
    }
  }

  const canonical = SITE_ORIGIN + targetUrl;

  return '<!DOCTYPE html>\n' +
'<html lang="en">\n' +
'<head>\n' +
'<meta charset="UTF-8">\n' +
'<meta name="viewport" content="width=device-width, initial-scale=1">\n' +
'<title>' + escapeHtml(title) + '</title>\n' +
'<meta name="description" content="' + escapeAttr(desc) + '">\n' +
'<link rel="canonical" href="' + escapeAttr(canonical) + '">\n' +
// Open Graph
'<meta property="og:type" content="business.business">\n' +
'<meta property="og:site_name" content="DukanList">\n' +
'<meta property="og:title" content="' + escapeAttr(title) + '">\n' +
'<meta property="og:description" content="' + escapeAttr(desc) + '">\n' +
'<meta property="og:url" content="' + escapeAttr(canonical) + '">\n' +
'<meta property="og:image" content="' + escapeAttr(image) + '">\n' +
'<meta property="og:image:type" content="' + escapeAttr(imageType) + '">\n' +
'<meta property="og:image:width" content="1200">\n' +
'<meta property="og:image:height" content="630">\n' +
'<meta property="og:image:alt" content="' + escapeAttr(name) + '">\n' +
'<meta property="og:locale" content="en_IN">\n' +
// Twitter card
'<meta name="twitter:card" content="summary_large_image">\n' +
'<meta name="twitter:title" content="' + escapeAttr(title) + '">\n' +
'<meta name="twitter:description" content="' + escapeAttr(desc) + '">\n' +
'<meta name="twitter:image" content="' + escapeAttr(image) + '">\n' +
// Redirect to real profile for human visitors
'<meta http-equiv="refresh" content="0; url=' + escapeAttr(canonical) + '">\n' +
'<script>window.location.replace(' + JSON.stringify(canonical) + ');</script>\n' +
'<style>body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#FFFBF5;color:#0F172A;text-align:center;padding:80px 20px}a{color:#FF6B1A;text-decoration:none;font-weight:700}</style>\n' +
'</head>\n' +
'<body>\n' +
'<p>Redirecting you to <strong>' + escapeHtml(name) + '</strong> on DukanList…</p>\n' +
'<p><a href="' + escapeAttr(canonical) + '">Tap here if not redirected</a></p>\n' +
'</body>\n' +
'</html>\n';
}

function renderNotFound(){
  return '<!DOCTYPE html>\n' +
'<html><head>\n' +
'<meta charset="UTF-8">\n' +
'<title>Shop not found — DukanList</title>\n' +
'<meta property="og:title" content="DukanList — Every Shop, One Identity">\n' +
'<meta property="og:description" content="Bharat ka local shop directory.">\n' +
'<meta property="og:image" content="' + DEFAULT_OG_IMAGE + '">\n' +
'<meta http-equiv="refresh" content="0; url=' + SITE_ORIGIN + '/">\n' +
'<script>window.location.replace(' + JSON.stringify(SITE_ORIGIN + '/') + ');</script>\n' +
'</head><body>Shop not found. <a href="' + SITE_ORIGIN + '/">Go to DukanList →</a></body></html>\n';
}

export default async function handler(req, res){
  try {
    // Vercel parses ?foo=bar into req.query.foo
    const slug = (req.query && req.query.slug) || null;
    const id   = (req.query && req.query.id)   || null;
    // Preserve review-prompt flag through the redirect (?r=1 or ?review=1)
    const isReview = !!(req.query && (req.query.r || req.query.review));

    if (!slug && !id){
      res.statusCode = 302;
      res.setHeader('Location', SITE_ORIGIN + '/');
      return res.end();
    }

    let biz = null;
    if (slug) biz = await fetchBusiness('slug', slug);
    if (!biz && id) biz = await fetchBusiness('id', id);

    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    // Cache for 1 hour on edge — refresh when shop updates
    res.setHeader('Cache-Control', 'public, max-age=300, s-maxage=3600, stale-while-revalidate=86400');

    if (!biz){
      res.statusCode = 404;
      return res.end(renderNotFound());
    }

    const target = '/business.html?slug=' + encodeURIComponent(biz.slug || '') +
                   '&utm_source=share&utm_medium=link' +
                   (isReview ? '&review=1' : '');
    res.statusCode = 200;
    return res.end(renderHtml(biz, target, isReview));

  } catch (err){
    console.error('share endpoint error:', err);
    res.statusCode = 500;
    res.setHeader('Content-Type', 'text/html');
    return res.end(renderNotFound());
  }
}
