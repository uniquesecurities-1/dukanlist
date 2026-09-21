// =====================================================
// api/sitemap.js
// Dynamic sitemap.xml generator for DukanList
// Vercel serverless function — Node 18+
// Routes:  /sitemap.xml  → (via vercel.json rewrite) → /api/sitemap
// =====================================================

const SUPABASE_URL = 'https://qazuyygrpqopwygxmvwq.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFhenV5eWdycHFvcHd5Z3htdndxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxNTUwOTEsImV4cCI6MjA5NDczMTA5MX0.FR8x2kldC2yelpPnK2QKd5WGwHUAQheCVmxfs6hR00I';

const ORIGIN = 'https://dukanlist.com';

// Static high-priority pages.
// NOTE: no ".html" suffixes. vercel.json sets cleanUrls:true, so "/about.html"
// 308-redirects to "/about" — and Google drops sitemap entries that redirect
// rather than following them ("Page with redirect" in the indexing report).
const STATIC_PAGES = [
  { path: '/',            priority: '1.0',  freq: 'daily'   },
  { path: '/browse',      priority: '0.9',  freq: 'daily'   },
  { path: '/top',         priority: '0.9',  freq: 'daily'   },
  { path: '/search',      priority: '0.9',  freq: 'daily'   },
  { path: '/pucho-bhai',  priority: '0.9',  freq: 'hourly'  },
  { path: '/register',    priority: '0.8',  freq: 'monthly' },
  { path: '/about',       priority: '0.7',  freq: 'monthly' },
  { path: '/contact',     priority: '0.7',  freq: 'monthly' },
  { path: '/privacy',     priority: '0.4',  freq: 'yearly'  },
  { path: '/terms',       priority: '0.4',  freq: 'yearly'  },
  { path: '/welcome-pro', priority: '0.9',  freq: 'weekly'  },
  { path: '/how-ranking-works', priority: '0.7', freq: 'monthly' }
  // '/pro' is deliberately NOT here: pro.html is a 757-byte noindex stub that
  // redirects to /welcome-pro. Listing a noindex redirect in the sitemap is a
  // contradiction, and it is what the "Excluded by 'noindex' tag" row in the
  // indexing report was counting.
];



// Phase 7: Fetch /top/:cat/:city SEO combinations
async function fetchSeoTopUrls(){
  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/list_seo_combinations`, {
      method: 'POST',
      headers: {
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ p_limit: 200 })
    });
    if (!res.ok){
      // db/111 shipped this RPC referencing columns that do not exist, and
      // this function swallowed the 400 for months — /top/ silently produced
      // zero sitemap URLs and nobody could tell. db/220 fixes the SQL; this
      // log makes sure the next breakage is visible.
      console.error('[api/sitemap] list_seo_combinations ' + res.status + ': ' +
                    (await res.text().catch(() => '')).slice(0, 300));
      return [];
    }
    const arr = await res.json();
    if (!Array.isArray(arr)) return [];
    return arr.map(x => ({
      // no trailing slash — vercel.json sets trailingSlash:false, so "/top/a/b/"
      // 308-redirects to "/top/a/b" and Google discards the sitemap entry
      path: `/top/${x.category_slug}/${x.city_slug}`,
      priority: '0.8',
      freq: 'weekly'
    }));
  } catch(e){
    console.error('[api/sitemap] fetchSeoTopUrls threw:', e && e.message);
    return [];
  }
}

async function fetchFromSupabase(endpoint){
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${endpoint}`, {
    headers: {
      'apikey': SUPABASE_ANON_KEY,
      'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
    },
  });
  if (!res.ok) throw new Error(`Supabase ${endpoint} failed: ${res.status}`);
  return await res.json();
}

function escapeXml(s){
  return String(s || '').replace(/[<>&'"]/g, c => ({
    '<':'&lt;', '>':'&gt;', '&':'&amp;', "'":'&apos;', '"':'&quot;'
  }[c]));
}

function urlBlock(loc, priority, freq, lastmod){
  let block = `  <url>\n    <loc>${escapeXml(loc)}</loc>\n    <changefreq>${freq}</changefreq>\n    <priority>${priority}</priority>`;
  if (lastmod){
    const date = lastmod.split('T')[0]; // YYYY-MM-DD
    block += `\n    <lastmod>${date}</lastmod>`;
  }
  block += `\n  </url>`;
  return block;
}

export default async function handler(req, res){
  try {
    // One query carries everything: each active business brings its own city,
    // category and locality with it, so the landing pages below are derived
    // from real listings instead of being multiplied out blindly.
    const businesses = await fetchFromSupabase(
      'businesses?status=eq.active' +
      '&select=slug,updated_at,created_at,categories:category_id(slug),' +
      'geo_cities(name),geo_localities(slug)'
    );

    const citySlug = n => String(n || '').toLowerCase().replace(/\s+/g, '-');

    // Only the combinations that actually have at least one listing.
    const localCombos = new Set();   // "city/category"
    const areaCombos  = new Set();   // "city/locality"
    businesses.forEach(b => {
      const cat  = b.categories && b.categories.slug;
      const city = b.geo_cities && citySlug(b.geo_cities.name);
      const loc  = b.geo_localities && b.geo_localities.slug;
      if (city && cat) localCombos.add(city + '/' + cat);
      if (city && loc) areaCombos.add(city + '/' + loc);
    });

    const urls = [];

    // 1. Static pages
    STATIC_PAGES.forEach(p => {
      urls.push(urlBlock(ORIGIN + p.path, p.priority, p.freq));
    });

    // 1b. Phase 7 SEO honeypot — Top X in [city] dynamic URLs
    try {
      const seoUrls = await fetchSeoTopUrls();
      seoUrls.forEach(u => {
        urls.push(urlBlock(ORIGIN + u.path, u.priority, u.freq));
      });
    } catch(e){ console.error('[api/sitemap] /top block failed:', e && e.message); }

    // 2. Hometown landing
    urls.push(urlBlock(ORIGIN + '/dabwali', '0.9', 'weekly'));

    // 3. NOTE: /search.html?cat=... used to be listed here — one URL per
    // category. robots.txt disallows "/search.html?", so we were handing Google
    // 368 URLs and blocking every one of them in the same breath. Category
    // browsing is covered by /local/:city/:cat below, which is server-rendered.

    // 4. Category landing pages — ONLY where a listing actually exists.
    // This used to be every city x every category: 33 x 368 = 12,144 URLs, of
    // which 12,125 were empty pages. Google crawled a sample, found nothing,
    // and stopped trusting the sitemap ("Crawled - currently not indexed").
    [...localCombos].sort().forEach(combo => {
      const [city, cat] = combo.split('/');
      urls.push(urlBlock(
        ORIGIN + '/local/' + encodeURIComponent(city) + '/' + encodeURIComponent(cat),
        '0.7',
        'weekly'
      ));
    });

    // 4b. Hyperlocal AREA landing pages — /area/:city/:locality
    // Long-tail value ("chotala road dukan"), but again only for localities
    // that have a listing to show.
    [...areaCombos].sort().forEach(combo => {
      const [city, loc] = combo.split('/');
      urls.push(urlBlock(
        ORIGIN + '/area/' + encodeURIComponent(city) + '/' + encodeURIComponent(loc),
        '0.7',
        'weekly'
      ));
    });

    // 5. Business profiles (highest SEO value)
    businesses.forEach(b => {
      urls.push(urlBlock(
        ORIGIN + '/' + encodeURIComponent(b.slug),   // v228: clean URL — the old form 308-redirects, and Google drops redirecting sitemap entries
        '0.8',
        'weekly',
        b.updated_at || b.created_at
      ));
    });

    const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls.join('\n')}
</urlset>`;

    res.setHeader('Content-Type', 'application/xml; charset=utf-8');
    res.setHeader('Cache-Control', 'public, max-age=3600, s-maxage=3600');
    res.setHeader('X-Robots-Tag', 'noindex'); // don't index the sitemap itself
    return res.status(200).send(xml);

  } catch (err){
    console.error('Sitemap generation failed:', err);
    // Fallback: static-only sitemap
    const fallback = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${STATIC_PAGES.map(p => urlBlock(ORIGIN + p.path, p.priority, p.freq)).join('\n')}
</urlset>`;
    res.setHeader('Content-Type', 'application/xml; charset=utf-8');
    return res.status(200).send(fallback);
  }
}
