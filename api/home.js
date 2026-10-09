// =====================================================
// api/home.js — the home page, with the hero strip already in it
//
// v323. Lighthouse (mobile) scored the home page 51, then 84 after
// v322. What was left was LCP: the largest thing on a phone's first
// screen is the first "Top rated" photo, and a static page can only
// discover it after supabase-js loads and an RPC answers (~1.7 s on
// slow 4G). This function serves home.html with the four cards —
// and a <link rel=preload> for the first photo — already in the
// HTML, so the browser starts fetching the LCP image with the page.
//
// Shape of the trust: the client code in home.html is untouched. It
// still runs, compares the slugs it gets from the network with the
// ones already rendered (data-slugs) and leaves the DOM alone when
// they match. If anything in here fails, the untouched template is
// served as-is — the page can never be worse than it was.
//
// Edge-cached 10 minutes, served stale for a day while revalidating,
// so Supabase sees a handful of calls an hour, not one per visitor.
// =====================================================
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://qazuyygrpqopwygxmvwq.supabase.co';
const ANON_KEY     = process.env.SUPABASE_ANON_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFhenV5eWdycHFvcHd5Z3htdndxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxNTUwOTEsImV4cCI6MjA5NDczMTA5MX0.FR8x2kldC2yelpPnK2QKd5WGwHUAQheCVmxfs6hR00I';
const ORIGIN       = process.env.PUBLIC_SITE_URL || 'https://dukanlist.com';
const DEFAULT_CITY = 'mandi-dabwali';

let TEMPLATE = null;
async function getTemplate(){
  if (TEMPLATE) return TEMPLATE;
  const r = await fetch(ORIGIN + '/home.html', { headers: { 'User-Agent': 'dukanlist-ssr' } });
  if (!r.ok) throw new Error('template fetch failed: ' + r.status);
  let html = await r.text();
  // v324: the two stylesheets that block first paint (Lighthouse: 600 ms on
  // slow 4G — one round trip each) are inlined at serve time, so they stay
  // one file on disk for every other page and never drift. If a fetch
  // fails the <link> stays as it was.
  for (const m of html.matchAll(/<link rel="stylesheet" href="(\/assets\/css\/(?:public-premium|dl-simple-mode)\.css\?v=[^"]+)">/g)){
    try {
      const c = await fetch(ORIGIN + m[1], { headers: { 'User-Agent': 'dukanlist-ssr' } });
      if (c.ok) html = html.replace(m[0], '<style data-inlined="' + m[1].split('?')[0] + '">' + (await c.text()).replace(/<\/style/gi, '<\\/style') + '</style>');
    } catch(_){}
  }
  TEMPLATE = html;
  return TEMPLATE;
}

function esc(s){
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

// Same transform DukanImg.strip() applies in the browser (500x312 fill),
// so the SSR'd <img src> is byte-identical to what the client would set
// and the browser never re-requests it.
function stripUrl(url){
  if (!url || !/res\.cloudinary\.com/.test(url)) return url;
  const seg = 'w_500,h_312,c_fill,q_auto,f_auto';
  const m = url.match(/^(.*\/image\/upload\/)(?:[^/]*[,_][^/]*\/)?(v\d+\/.+)$/);
  if (m) return m[1] + seg + '/' + m[2];
  return url.replace('/image/upload/', '/image/upload/' + seg + '/');
}

async function topShops(citySlug){
  const r = await fetch(SUPABASE_URL + '/rest/v1/rpc/get_top_for_seo', {
    method: 'POST',
    headers: { apikey: ANON_KEY, Authorization: 'Bearer ' + ANON_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_category_slug: null, p_city_slug: citySlug, p_limit: 12 })
  });
  if (!r.ok) throw new Error('rpc ' + r.status);
  const j = await r.json();
  return ((j && j.items) || []).filter(x => !!x.photo).slice(0, 4);   // v338: photo shops only, same as the client
}

// Mirrors the client renderer in home.html (hero-top-shops) — keep in step.
function card(b, i){
  const img = b.photo
    ? '<img class="hts-img" data-fit-skip="1" width="250" height="156" src="' + esc(stripUrl(b.photo)) + '" alt="' + esc(b.name) + '"' + (i < 2 ? ' loading="eager" fetchpriority="high"' : ' loading="lazy"') + '>'
    : '<div class="hts-ph">\u{1F3EA}</div>';
  const rating = (b.rating_count > 0)
    ? '★ ' + Number(b.rating_avg).toFixed(1) + ' (' + b.rating_count + ')'
    : 'New listing';
  return '<a class="hts-card" href="/' + encodeURIComponent(b.slug || '') + '">' +
    img +
    '<div class="hts-body">' +
      '<span class="hts-rank">#' + (i + 1) + '</span>' +
      '<div class="hts-name">' + esc(b.name) + '</div>' +
      '<div class="hts-meta">' + rating + '</div>' +
    '</div></a>';
}

module.exports = async (req, res) => {
  let html;
  try {
    html = await getTemplate();
  } catch (e) {
    // No template → let the static file answer instead of a blank page.
    res.statusCode = 302;
    res.setHeader('Location', '/home.html');
    res.end();
    return;
  }

  let out = html;
  try {
    const items = await topShops(DEFAULT_CITY);
    if (items.length){
      const slugs = items.map(x => x.slug).join(',');
      const rowRe = /<div class="hts-row" id="htsRow">[\s\S]*?<\/div>\n/;
      if (rowRe.test(out)){
        out = out.replace(rowRe, '<div class="hts-row" id="htsRow" data-slugs="' + esc(slugs) + '">' + items.map(card).join('') + '</div>\n');
        const first = items.find(x => x.photo);
        if (first){
          // v324: at the TOP of <head>, inside the first packet. Appended
          // before </head> it sat 42 KB down (inline CSS) and on slow 4G the
          // browser reached it ~2 s in — Lighthouse: "resource load delay
          // 1,960 ms" with the preload already in place.
          const tag = '<link rel="preload" as="image" href="' + esc(stripUrl(first.photo)) + '" fetchpriority="high">';
          const vp = out.indexOf('<meta name="viewport"');
          const cut = vp >= 0 ? out.indexOf('>', vp) + 1 : -1;
          out = cut > 0 ? out.slice(0, cut) + '\n' + tag + out.slice(cut) : out.replace('</head>', tag + '\n</head>');
        }
      }
    }
  } catch (e) {
    console.error('[api/home] hero strip skipped:', e && e.message);
    // out stays the untouched template
  }

  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'public, max-age=0, s-maxage=600, stale-while-revalidate=86400');
  res.end(out);
};
