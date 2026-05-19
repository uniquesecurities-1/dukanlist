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
  { path: '/search.html',  priority: '0.9', freq: 'daily'   },
  { path: '/register.html',priority: '0.8', freq: 'monthly' },
  { path: '/about.html',   priority: '0.7', freq: 'monthly' },
  { path: '/contact.html', priority: '0.7', freq: 'monthly' },
  { path: '/privacy.html', priority: '0.4', freq: 'yearly'  },
  { path: '/terms.html',   priority: '0.4', freq: 'yearly'  },
];

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
    const [categories, businesses] = await Promise.all([
      fetchFromSupabase('categories?active=eq.true&select=slug,sort_order&order=sort_order'),
      fetchFromSupabase('businesses?status=eq.active&select=slug,updated_at,created_at'),
    ]);

    const urls = [];

    // 1. Static pages
    STATIC_PAGES.forEach(p => {
      urls.push(urlBlock(ORIGIN + p.path, p.priority, p.freq));
    });

    // 2. Categories — each as a search filter URL
    categories.forEach(c => {
      urls.push(urlBlock(
        ORIGIN + '/search.html?cat=' + encodeURIComponent(c.slug),
        '0.6',
        'weekly'
      ));
    });

    // 3. Business profiles (highest SEO value)
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
