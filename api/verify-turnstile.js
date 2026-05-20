// =====================================================
// /api/verify-turnstile.js
// Cloudflare Turnstile token verification endpoint
// =====================================================
// Verifies a Turnstile token against Cloudflare's siteverify API.
// Frontend posts { token, action } -> returns { success, ... }
//
// TO ENABLE:
//   1. Get site at https://dash.cloudflare.com → Turnstile → Add site
//   2. Choose "Invisible" mode for dukanlist.com
//   3. Copy Site Key + Secret Key
//   4. In Vercel project settings, add env var:
//        TURNSTILE_SECRET_KEY = <your secret key>
//   5. In register.html, add Site Key constant + uncomment Turnstile loader.
//
// Until enabled, this endpoint returns { success: true, skipped: true }
// so it doesn't block existing registration flow.
// =====================================================

export default async function handler(req, res) {
  // Only allow POST
  if (req.method !== 'POST') {
    return res.status(405).json({ success: false, error: 'Method not allowed' });
  }

  const SECRET = process.env.TURNSTILE_SECRET_KEY;

  // If not configured, allow (defense remains: honeypot + rate limit + admin review)
  if (!SECRET) {
    return res.status(200).json({
      success: true,
      skipped: true,
      reason: 'Turnstile not configured; allowing request'
    });
  }

  const { token } = req.body || {};
  if (!token) {
    return res.status(400).json({ success: false, error: 'Missing token' });
  }

  // Client IP from Vercel header
  const ip =
    req.headers['cf-connecting-ip'] ||
    req.headers['x-real-ip'] ||
    req.headers['x-forwarded-for']?.split(',')[0]?.trim() ||
    null;

  try {
    const params = new URLSearchParams();
    params.append('secret', SECRET);
    params.append('response', token);
    if (ip) params.append('remoteip', ip);

    const cfResp = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params.toString()
    });

    const cfData = await cfResp.json();
    if (cfData.success) {
      return res.status(200).json({ success: true });
    }
    return res.status(403).json({
      success: false,
      error: 'Turnstile verification failed',
      details: cfData['error-codes'] || []
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Verification service unavailable' });
  }
}
