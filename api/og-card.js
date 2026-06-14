// =====================================================
// api/og-card.js
// Dynamic SVG-based OG card for shops without a photo.
//
// Used by /api/share when isReview=true AND the shop has no photo
// in their listing. Returns a warm orange gradient card with the
// shop name, location, and a 5-star row — NO DukanList branding.
//
// WhatsApp, Telegram, Twitter, Facebook, iMessage all render SVG
// og:image correctly in modern apps (2022+). Older WhatsApp iOS may
// fall back to text-only preview, which still shows the shop name in
// the title.
//
// Inputs:
//   ?slug=unique-securities    (preferred)
//   ?id=<uuid>
//   &noStars=1                  (optional: hide rating stars)
//
// Output: image/svg+xml, 1200×630 px
// =====================================================

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://qazuyygrpqopwygxmvwq.supabase.co';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFhenV5eWdycHFvcHd5Z3htdndxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxNTUwOTEsImV4cCI6MjA5NDczMTA5MX0.FR8x2kldC2yelpPnK2QKd5WGwHUAQheCVmxfs6hR00I';

function xmlEscape(s){
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function truncate(s, n){
  s = String(s || '').trim().replace(/\s+/g, ' ');
  return s.length > n ? s.slice(0, n - 1) + '…' : s;
}

// Smart font size based on shop name length
function fitFontSize(name){
  const n = name.length;
  if (n <= 12) return 130;
  if (n <= 18) return 100;
  if (n <= 26) return 78;
  if (n <= 34) return 64;
  return 54;
}

// Deterministic gradient pick based on shop name (so same shop = same colors)
const GRADIENTS = [
  { from: '#FF6B1A', via: '#F97316', to: '#EA580C' },   // saffron-orange
  { from: '#EF4444', via: '#DC2626', to: '#991B1B' },   // red-warm
  { from: '#F59E0B', via: '#D97706', to: '#B45309' },   // amber-gold
  { from: '#10B981', via: '#059669', to: '#047857' },   // emerald
  { from: '#3B82F6', via: '#2563EB', to: '#1D4ED8' },   // blue
  { from: '#8B5CF6', via: '#7C3AED', to: '#6D28D9' },   // violet
  { from: '#EC4899', via: '#DB2777', to: '#BE185D' }    // pink-fuchsia
];
function gradFor(name){
  let h = 0;
  for (let i = 0; i < name.length; i++) h = ((h << 5) - h + name.charCodeAt(i)) | 0;
  return GRADIENTS[Math.abs(h) % GRADIENTS.length];
}

async function fetchBusiness(field, value){
  const url = SUPABASE_URL + '/rest/v1/businesses' +
    '?select=name,slug,id,rating_avg,rating_count,owner_name,owner_role,geo_cities(name),geo_localities(name)' +
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

function buildSvg(biz, opts){
  opts = opts || {};
  const mode = opts.mode || 'review';  // 'review' (default) | 'share'
  const isShare = (mode === 'share');
  const name = biz.name || 'Our Shop';
  const city = biz.geo_cities && biz.geo_cities.name ? biz.geo_cities.name : '';
  const locality = biz.geo_localities && biz.geo_localities.name ? biz.geo_localities.name : '';
  const place = [locality, city].filter(Boolean).join(', ');
  const ratingAvg = Number(biz.rating_avg) || 0;
  const ratingCount = Number(biz.rating_count) || 0;
  const hasRating = !opts.noStars && ratingCount > 0 && ratingAvg > 0;

  // Owner identity (dignity line): "Owner: Rajesh Sharma" or "Founder: ..." etc.
  const ownerName = (biz.owner_name || '').trim();
  const ownerRoleRaw = (biz.owner_role || '').trim();
  const ownerRole = ownerRoleRaw || 'Owner';
  const ownerLine = ownerName ? (ownerRole + ': ' + ownerName) : '';
  const displayOwner = truncate(ownerLine, 46);

  const displayName = truncate(name, 38);
  const displayPlace = truncate(place, 50);
  const fontSize = fitFontSize(displayName);
  const grad = gradFor(name);

  // Initial letter for the soft badge top-left (no DukanList branding)
  const initial = (name.trim()[0] || 'S').toUpperCase();

  // Build 5 stars row
  let stars = '';
  for (let i = 0; i < 5; i++){
    const cx = 360 + i * 96;
    const filled = !hasRating || (i + 1 <= Math.round(ratingAvg));
    stars += '<path d="M ' + (cx - 28) + ' 530 L ' + cx + ' 470 L ' + (cx + 28) + ' 530 L ' + (cx + 78) + ' 538 L ' + (cx + 42) + ' 580 L ' + (cx + 50) + ' 638 L ' + cx + ' 612 L ' + (cx - 50) + ' 638 L ' + (cx - 42) + ' 580 L ' + (cx - 78) + ' 538 Z" ' +
             'transform="translate(0,-65) scale(0.55) translate(0,118)" ' +
             'fill="' + (filled ? '#FBBF24' : 'rgba(255,255,255,0.30)') + '" ' +
             'stroke="rgba(0,0,0,0.06)" stroke-width="1"/>';
  }

  let ratingText;
  if (hasRating){
    ratingText = '⭐ ' + ratingAvg.toFixed(1) + ' (' + ratingCount + ' review' + (ratingCount === 1 ? '' : 's') + ')';
  } else if (isShare){
    ratingText = 'Photos · Business hours · Direct call';
  } else {
    ratingText = 'Rate your experience';
  }

  // 1200x630 spec for OG cards
  return '<?xml version="1.0" encoding="UTF-8"?>\n' +
'<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">\n' +
'  <defs>\n' +
'    <linearGradient id="bgGrad" x1="0" y1="0" x2="1" y2="1">\n' +
'      <stop offset="0%" stop-color="' + grad.from + '"/>\n' +
'      <stop offset="60%" stop-color="' + grad.via + '"/>\n' +
'      <stop offset="100%" stop-color="' + grad.to + '"/>\n' +
'    </linearGradient>\n' +
'    <radialGradient id="bloom" cx="80%" cy="-10%" r="70%">\n' +
'      <stop offset="0%" stop-color="rgba(255,255,255,0.35)"/>\n' +
'      <stop offset="60%" stop-color="rgba(255,255,255,0)"/>\n' +
'    </radialGradient>\n' +
'    <filter id="shadow"><feGaussianBlur stdDeviation="3"/></filter>\n' +
'  </defs>\n' +
'  <!-- Background -->\n' +
'  <rect width="1200" height="630" fill="url(#bgGrad)"/>\n' +
'  <rect width="1200" height="630" fill="url(#bloom)"/>\n' +
'  <!-- Decorative circles -->\n' +
'  <circle cx="1100" cy="100" r="180" fill="rgba(255,255,255,0.08)"/>\n' +
'  <circle cx="80" cy="540" r="130" fill="rgba(255,255,255,0.06)"/>\n' +
'  <!-- Initial badge -->\n' +
'  <circle cx="120" cy="120" r="58" fill="rgba(255,255,255,0.22)" stroke="rgba(255,255,255,0.40)" stroke-width="3"/>\n' +
'  <text x="120" y="148" font-family="ui-rounded,-apple-system,Segoe UI,Roboto,Arial,sans-serif" font-size="68" font-weight="800" fill="#ffffff" text-anchor="middle">' + xmlEscape(initial) + '</text>\n' +
'  <!-- Top-right pill: brand tag -->\n' +
'  <rect x="' + (isShare ? 880 : 940) + '" y="86" width="' + (isShare ? 240 : 180) + '" height="56" rx="28" fill="rgba(255,255,255,0.20)" stroke="rgba(255,255,255,0.30)" stroke-width="2"/>\n' +
'  <text x="' + (isShare ? 1000 : 1030) + '" y="123" font-family="ui-rounded,-apple-system,Segoe UI,Roboto,Arial,sans-serif" font-size="' + (isShare ? 20 : 22) + '" font-weight="800" fill="#ffffff" letter-spacing="2" text-anchor="middle">' + (isShare ? 'LOCAL · VERIFIED' : 'RATE US') + '</text>\n' +
'  <!-- Shop name (huge) -->\n' +
'  <text x="80" y="' + (320 + (fontSize > 100 ? 0 : 12)) + '" font-family="ui-rounded,-apple-system,Segoe UI,Roboto,Arial,sans-serif" font-size="' + fontSize + '" font-weight="900" fill="#ffffff" letter-spacing="-2">' + xmlEscape(displayName) + '</text>\n' +
'  <!-- Location subtitle -->\n' +
'  ' + (displayPlace ? '<text x="80" y="390" font-family="ui-rounded,-apple-system,Segoe UI,Roboto,Arial,sans-serif" font-size="32" font-weight="600" fill="rgba(255,255,255,0.92)">📍 ' + xmlEscape(displayPlace) + '</text>' : '') + '\n' +
'  <!-- Owner attribution line (dignity) -->\n' +
'  ' + (displayOwner ? '<text x="80" y="' + (displayPlace ? 428 : 390) + '" font-family="ui-rounded,-apple-system,Segoe UI,Roboto,Arial,sans-serif" font-size="26" font-weight="600" fill="rgba(255,255,255,0.85)">👤 ' + xmlEscape(displayOwner) + '</text>' : '') + '\n' +
'  <!-- Stars row -->\n' +
'  ' + stars + '\n' +
'  <!-- Rating text -->\n' +
'  <text x="80" y="555" font-family="ui-rounded,-apple-system,Segoe UI,Roboto,Arial,sans-serif" font-size="30" font-weight="700" fill="#ffffff">' + xmlEscape(ratingText) + '</text>\n' +
'  <!-- CTA -->\n' +
'  <text x="80" y="595" font-family="ui-rounded,-apple-system,Segoe UI,Roboto,Arial,sans-serif" font-size="22" font-weight="600" fill="rgba(255,255,255,0.78)" letter-spacing="1">' + (isShare ? 'Tap to view photos, hours, and direct contact →' : 'Tap to share your feedback — takes 10 seconds') + '</text>\n' +
'  <!-- Subtle DukanList watermark (share mode only) -->\n' +
'  ' + (isShare ? '<text x="1120" y="600" font-family="ui-rounded,Arial,sans-serif" font-size="18" font-weight="600" fill="rgba(255,255,255,0.55)" text-anchor="end" letter-spacing="1">dukanlist.com</text>' : '') + '\n' +
'</svg>\n';
}

// Generic fallback when no business is found
function buildGenericSvg(){
  return '<?xml version="1.0" encoding="UTF-8"?>\n' +
'<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">\n' +
'  <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">\n' +
'    <stop offset="0%" stop-color="#FF6B1A"/><stop offset="100%" stop-color="#EA580C"/>\n' +
'  </linearGradient></defs>\n' +
'  <rect width="1200" height="630" fill="url(#g)"/>\n' +
'  <text x="600" y="320" font-family="ui-rounded,-apple-system,Segoe UI,Roboto,Arial,sans-serif" font-size="84" font-weight="900" fill="#ffffff" text-anchor="middle">Rate Your Experience</text>\n' +
'  <text x="600" y="395" font-family="ui-rounded,-apple-system,Segoe UI,Roboto,Arial,sans-serif" font-size="32" font-weight="600" fill="rgba(255,255,255,0.92)" text-anchor="middle">⭐⭐⭐⭐⭐</text>\n' +
'</svg>\n';
}

export default async function handler(req, res){
  try {
    const slug = (req.query && req.query.slug) || null;
    const id   = (req.query && req.query.id)   || null;
    const noStars = !!(req.query && req.query.noStars);
    const mode = (req.query && req.query.mode === 'share') ? 'share' : 'review';

    let biz = null;
    if (slug) biz = await fetchBusiness('slug', slug);
    if (!biz && id) biz = await fetchBusiness('id', id);

    res.setHeader('Content-Type', 'image/svg+xml; charset=utf-8');
    // Cache aggressively on edge (shops don't change name/location often)
    res.setHeader('Cache-Control', 'public, max-age=3600, s-maxage=86400, stale-while-revalidate=86400');
    res.setHeader('X-Robots-Tag', 'noindex');

    const svg = biz ? buildSvg(biz, { noStars, mode }) : buildGenericSvg();
    res.statusCode = 200;
    return res.end(svg);

  } catch (err){
    console.error('og-card endpoint error:', err);
    res.statusCode = 500;
    res.setHeader('Content-Type', 'image/svg+xml');
    return res.end(buildGenericSvg());
  }
}
