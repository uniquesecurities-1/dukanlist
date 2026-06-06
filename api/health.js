// =====================================================
// api/health.js
// Health-check endpoint for uptime monitors (UptimeRobot etc.)
//
// Returns 200 + JSON when everything is OK. Returns 503 if a
// critical dependency (Supabase) is down.
//
// Sample monitor config:
//   URL    : https://dukanlist.com/api/health
//   Method : GET
//   Expect : HTTP 200 + body contains '"ok":true'
//   Every  : 5 minutes
// =====================================================

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://qazuyygrpqopwygxmvwq.supabase.co';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFhenV5eWdycHFvcHd5Z3htdndxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxNTUwOTEsImV4cCI6MjA5NDczMTA5MX0.FR8x2kldC2yelpPnK2QKd5WGwHUAQheCVmxfs6hR00I';

module.exports = async (req, res) => {
  const startedAt = Date.now();
  const result = {
    ok:        true,
    service:   'dukanlist',
    timestamp: new Date().toISOString(),
    checks:    {}
  };

  // Check 1: Supabase reachability (lightweight HEAD on REST root)
  try {
    const controller = new AbortController();
    const t = setTimeout(() => controller.abort(), 4000);
    const r = await fetch(SUPABASE_URL + '/rest/v1/?select=1', {
      method: 'HEAD',
      headers: {
        'apikey':        SUPABASE_ANON_KEY,
        'Authorization': 'Bearer ' + SUPABASE_ANON_KEY
      },
      signal: controller.signal
    });
    clearTimeout(t);
    result.checks.supabase = {
      ok:        r.ok || r.status === 200 || r.status === 204 || r.status === 404,
      status:    r.status,
      latency_ms: Date.now() - startedAt
    };
  } catch (e) {
    result.checks.supabase = { ok: false, error: String(e.message || e).slice(0, 200) };
    result.ok = false;
  }

  // Check 2: Vercel runtime version (for visibility)
  result.checks.runtime = {
    ok:        true,
    region:    process.env.VERCEL_REGION || 'unknown',
    node:      process.version
  };

  result.duration_ms = Date.now() - startedAt;

  res.statusCode = result.ok ? 200 : 503;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store, must-revalidate');
  res.end(JSON.stringify(result));
};
