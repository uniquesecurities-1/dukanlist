// =====================================================
// api/sitemap.js
// Dynamic sitemap.xml generator for DukanList
// Vercel serverless function — Node 18+
// Routes:  /sitemap.xml  → (via vercel.json rewrite) → /api/sitemap
// =====================================================

const SUPABASE_URL = 'https://qazuyygrpqopwygxmvwq.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFhenV5eWdycHFvcHd5Z3htdndxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxNTUwOTEsImV4cCI6MjA5NDczMTA5MX0.FR8x2kldC2yelpPnK2QKd5WGwHUAQheCVmxfs6hR00I';

const ORIGIN = 'https://dukanlist.com';

// Static high-priority pages
const STATIC_PAGES = [
  { path: '/',             priority: '1.0', freq: 'daily'   },
  { path: '/browse.html',  priority: '0.9', freq: 'daily'   },
  { path: '/top.html',     priority: '0.9', freq: 'daily'   },
  { path: '/search.html',  priority: '0.9', freq: 'daily'   },
  { path: '/pucho-bhai.html', priority: '0.9', freq: 'hourly' },
  { path: '/register.html',priority: '0.8', freq: 'monthly' },
  { path: '/about.html',   priority: '0.7', freq: 'monthly' },
  { path: '/contact.html', priority: '0.7', freq: 'monthly' },
  { path: '/privacy.html', priority: '0.4', freq: 'yearly'  },
  { path: '/terms.html',   priority: '0.4', freq: 'yearly'  },
,
  { path: '/welcome-pro.html', priority: '0.9', changefreq: 'weekly' },
  { path: '/pro.html', priority: '0.85', changefreq: 'weekly' }
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
    if (!res.ok) return [];
    const arr = await res.json();
    if (!Array.isArray(arr)) return [];
    return arr.map(x => ({
      path: `/top/${x.category_slug}/${x.city_slug}/`,
      priority: '0.8',
      freq: 'weekly'
    }));
  } catch(_){ return []; }
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
    // Fetch live data in parallel
    const [categories, businesses, cities, localities] = await Promise.all([
      fetchFromSupabase('categories?active=eq.true&select=slug,sort_order&order=sort_order'),
      fetchFromSupabase('businesses?status=eq.active&select=slug,updated_at,created_at'),
      fetchFromSupabase('geo_cities?active=eq.true&select=name'),
      // Hyperlocal landing pages: every locality is a SEO long-tail page
      fetchFromSupabase('geo_localities?select=slug,city_id,geo_cities(name)').catch(() => []),
    ]);

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
    } catch(_){}

    // 2. Hometown landing
    urls.push(urlBlock(ORIGIN + '/dabwali.html', '0.9', 'weekly'));

    // 3. Categories — each as a search filter URL
    categories.forEach(c => {
      urls.push(urlBlock(
        ORIGIN + '/search.html?cat=' + encodeURIComponent(c.slug),
        '0.6',
        'weekly'
      ));
    });

    // 4. Locality landing pages — city × category combinations (huge SEO surface)
    const citySlugs = cities.map(c => String(c.name || '').toLowerCase().replace(/\s+/g, '-'));
    citySlugs.forEach(citySlug => {
      categories.forEach(cat => {
        urls.push(urlBlock(
          ORIGIN + '/local/' + encodeURIComponent(citySlug) + '/' + encodeURIComponent(cat.slug),
          '0.7',
          'weekly'
        ));
      });
    });

    // 4b. Hyperlocal AREA landing pages — /area/:city/:locality
    // Highest long-tail SEO value: "meena bazaar mandi dabwali", "chotala road dukan"
    try {
      (localities || []).forEach(l => {
        const cityName = l.geo_cities && l.geo_cities.name;
        if (!cityName || !l.slug) return;
        const citySlug = String(cityName).toLowerCase().replace(/\s+/g, '-');
        urls.push(urlBlock(
          ORIGIN + '/area/' + encodeURIComponent(citySlug) + '/' + encodeURIComponent(l.slug),
          '0.7',
          'weekly'
        ));
      });
    } catch(_){}

    // 5. Business profiles (highest SEO value)
    businesses.forEach(b => {
      urls.push(urlBlock(
        ORIGIN + '/business.html?slug=' + encodeURIComponent(b.slug),
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
