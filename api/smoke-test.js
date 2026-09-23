// =====================================================
// api/smoke-test.js — daily "is anything quietly broken?" check
// =====================================================
// Runs from the Vercel cron (vercel.json). Every failure becomes a row
// in admin_errors (error_type = 'smoke'), which already surfaces on
// /admin/health — so no new screen, no new table, and the admin sees
// it the next time he opens the panel.
//
// Why this exists: on 2026-09-21 a single afternoon of manual checking
// found /compare broken for months on a non-existent column, a live
// shop (786-cosmetic) whose page 404'd, get_homepage_buzz 404-ing on
// every homepage load, and 22 canonical tags pointing at redirects.
// Nobody can look at all of that daily. This can.
//
// WHAT IT CHECKS
//   1. sitemap   every <loc> in /sitemap.xml returns a straight 200
//                (no redirect). Catches broken shop pages and bad
//                routing like the [a-z] slug regex.
//   2. rpcs      the public RPCs the homepage and shop page depend on
//                answer without error. Catches half-applied migrations
//                (db/112b) and dropped functions (db/224 overwrite).
//   3. homepage  / returns 200 and still carries the hero strip and
//                featured grid markers, i.e. the page actually rendered.
//   4. security  the db/225 column locks still hold: anon must NOT be
//                able to read businesses.email. If a future migration
//                re-grants the table this fires the same day, not
//                whenever somebody notices.
//
// AUTH: same rule as rank-snapshot.js — a real shared secret only.
// User-Agent / x-vercel-cron are client-controlled and not trusted.
// =====================================================

const ORIGIN        = 'https://dukanlist.com';
const SUPABASE_URL  = process.env.SUPABASE_URL  || 'https://qazuyygrpqopwygxmvwq.supabase.co';
const ANON_KEY      = process.env.SUPABASE_ANON_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFhenV5eWdycHFvcHd5Z3htdndxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxNTUwOTEsImV4cCI6MjA5NDczMTA5MX0.FR8x2kldC2yelpPnK2QKd5WGwHUAQheCVmxfs6hR00I';
const SERVICE_KEY   = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const MANUAL_SECRET = process.env.DIGEST_CRON_SECRET || '';

// The RPCs the public site cannot live without. Args are the cheapest
// valid call for each; we only care that it answers, not what it says.
const RPCS = [
  ['get_public_stats',          {}],
  ['get_local_pulse',           {}],
  ['get_trending_shops',        {}],
  ['get_top_for_seo',           { p_category_slug: null, p_city_slug: 'mandi-dabwali', p_limit: 3 }],
  ['get_spotlight_of_week',     {}],
  ['get_homepage_buzz',         { p_city_slug: null, p_limit: 3 }],
  ['list_active_announcements', {}],
  ['list_active_deals',         {}],
  ['list_localities_by_city',   { p_city_slug: 'mandi-dabwali' }],   // required arg — verified live, {} is PGRST202
  ['public_unclaimed_listings', {}],
  ['list_seo_combinations',     { p_limit: 5 }],
];

function withTimeout(ms){
  const c = new AbortController();
  const t = setTimeout(() => c.abort(), ms);
  return { signal: c.signal, done: () => clearTimeout(t) };
}

async function checkSitemap(fails){
  const r = await fetch(ORIGIN + '/sitemap.xml');
  if (!r.ok){ fails.push({ check: 'sitemap', msg: 'sitemap.xml returned ' + r.status }); return { total: 0 }; }
  const xml  = await r.text();
  const locs = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map(m => m[1]);
  let done = 0;
  // 12 at a time — polite to the origin, fast enough for the cron window
  for (let i = 0; i < locs.length; i += 12){
    await Promise.all(locs.slice(i, i + 12).map(async (u) => {
      const t = withTimeout(8000);
      try {
        const res = await fetch(u, { redirect: 'manual', signal: t.signal });
        if (res.status !== 200){
          fails.push({ check: 'sitemap', msg: res.status + ' ' + u.replace(ORIGIN, '') });
        }
      } catch (e) {
        fails.push({ check: 'sitemap', msg: 'THREW ' + u.replace(ORIGIN, '') + ' — ' + (e && e.message || e) });
      } finally { t.done(); done++; }
    }));
  }
  return { total: locs.length, checked: done };
}

async function checkRpcs(fails){
  let ok = 0;
  for (const [fn, args] of RPCS){
    const t = withTimeout(8000);
    try {
      const r = await fetch(SUPABASE_URL + '/rest/v1/rpc/' + fn, {
        method: 'POST', signal: t.signal,
        headers: { apikey: ANON_KEY, Authorization: 'Bearer ' + ANON_KEY, 'Content-Type': 'application/json' },
        body: JSON.stringify(args)
      });
      if (r.ok) ok++;
      else fails.push({ check: 'rpc', msg: fn + ' -> ' + r.status + ' ' + (await r.text()).slice(0, 140) });
    } catch (e) {
      fails.push({ check: 'rpc', msg: fn + ' THREW ' + (e && e.message || e) });
    } finally { t.done(); }
  }
  return { total: RPCS.length, ok };
}

async function checkHomepage(fails){
  const r = await fetch(ORIGIN + '/', { redirect: 'manual' });
  if (r.status !== 200){ fails.push({ check: 'homepage', msg: '/ returned ' + r.status }); return; }
  const html = await r.text();
  if (!html.includes('id="heroTopShops"'))  fails.push({ check: 'homepage', msg: 'hero top-shops strip missing from /' });
  if (!html.includes('id="featuredGrid"'))  fails.push({ check: 'homepage', msg: 'featured grid missing from /' });
  if (html.length < 40000)                   fails.push({ check: 'homepage', msg: '/ is only ' + html.length + ' bytes — page shell, not the site' });
}

// v289: on 15 Jul 2026 an automated stylesheet stamp wrote a <link> into
// the middle of a JS string in admin/quick-add-shop.html. The string never
// closed, that page's whole inline script failed to parse, and every button
// on the field team's main tool was dead for ten weeks before anyone
// noticed. A page can return a healthy 200 and still be broken, so check
// that the inline scripts on the pages that matter actually parse.
const PARSE_PAGES = [
  '/admin/quick-add-shop.html',
  '/panel/photos.html',
  '/panel/dashboard.html',
  '/register.html',
  '/business.html',
];

async function checkInlineScripts(fails){
  let checked = 0;
  for (const p of PARSE_PAGES){
    try {
      const r = await fetch(ORIGIN + p);
      if (!r.ok){ fails.push({ check: 'parse', msg: p + ' returned ' + r.status }); continue; }
      const html = await r.text();
      const re = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g;
      let m, block = 0;
      while ((m = re.exec(html))){
        block++;
        const body = m[1];
        if (!body.trim()) continue;
        try { new Function(body); }
        catch (e) {
          fails.push({ check: 'parse', msg: p + ' inline script #' + block + ' does not parse — ' + (e.message || e) });
        }
      }
      checked++;
    } catch (e) {
      fails.push({ check: 'parse', msg: p + ' THREW ' + (e && e.message || e) });
    }
  }
  return { pages: PARSE_PAGES.length, checked };
}

async function checkSecurity(fails){
  // Every one of these must be 401/403 for anon. A 200 means db/225's
  // lock was undone (a table-level GRANT re-applied, most likely).
  const probes = [
    ['businesses',     'id,email'],
    ['businesses',     'id,claim_token'],
    ['reviews',        'id,customer_phone_hash'],
    ['rank_snapshots', 'id'],
  ];
  for (const [table, cols] of probes){
    const r = await fetch(SUPABASE_URL + '/rest/v1/' + table + '?select=' + cols + '&limit=1',
      { headers: { apikey: ANON_KEY, Authorization: 'Bearer ' + ANON_KEY } });
    if (r.status === 200){
      fails.push({ check: 'security', msg: 'anon CAN READ ' + table + '(' + cols + ') — db/225 lock is OFF' });
    }
  }
}

async function recordFailures(fails, summary){
  if (!SERVICE_KEY || !fails.length) return;
  const rows = fails.map(f => ({
    page:          '/api/smoke-test',
    error_type:    'smoke',
    error_message: '[' + f.check + '] ' + f.msg,
    url:           ORIGIN + '/api/smoke-test',
    user_agent:    'vercel-cron/smoke-test',
    payload:       { check: f.check, summary }
  }));
  await fetch(SUPABASE_URL + '/rest/v1/admin_errors', {
    method: 'POST',
    headers: { apikey: SERVICE_KEY, Authorization: 'Bearer ' + SERVICE_KEY,
               'Content-Type': 'application/json', Prefer: 'return=minimal' },
    body: JSON.stringify(rows)
  }).catch(e => console.error('[smoke-test] could not record failures:', e && e.message));
}

module.exports = async (req, res) => {
  const authHeader = req.headers['authorization'] || '';
  const cronSecret = process.env.CRON_SECRET || '';
  const xCronSec   = req.headers['x-cron-secret'] || '';
  const isBearerCron   = cronSecret && authHeader === ('Bearer ' + cronSecret);
  const isManualSecret = MANUAL_SECRET && xCronSec === MANUAL_SECRET;
  if (!isBearerCron && !isManualSecret){ res.status(401).json({ error: 'Unauthorized' }); return; }

  const started = Date.now();
  const fails = [];
  const summary = {};
  try {
    summary.sitemap  = await checkSitemap(fails);
    summary.rpcs     = await checkRpcs(fails);
    await checkHomepage(fails);
    summary.inlineScripts = await checkInlineScripts(fails);
    await checkSecurity(fails);
  } catch (e) {
    fails.push({ check: 'runner', msg: 'smoke test itself threw: ' + (e && e.message || e) });
  }
  summary.ms = Date.now() - started;
  summary.failures = fails.length;

  await recordFailures(fails, summary);

  console.log('[smoke-test]', JSON.stringify({ ...summary, fails: fails.slice(0, 20) }));
  res.status(fails.length ? 500 : 200).json({ ok: fails.length === 0, ...summary, fails });
};
