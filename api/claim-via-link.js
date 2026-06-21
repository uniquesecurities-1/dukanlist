// =====================================================
// api/claim-via-link.js — DEPRECATED (db/163 supersedes)
// =====================================================
// Previously: synthetic-email magic link flow. Replaced by Option B
// in db/163 — claim.html now does Supabase signUp directly with a
// REAL email + password, which aligns with the existing
// email-mandatory + user-verify setup (db/80, db/93).
//
// This endpoint is kept as a stub that returns a clear deprecation
// notice in case any old WhatsApp claim links still POST to it.
// Will be removed in a future cleanup pass.
// =====================================================
module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  res.status(410).json({
    error: 'This endpoint has been retired',
    message: 'Use the new claim flow at /claim.html?token=YOUR_TOKEN — Supabase email signup is now done client-side.',
    deprecated_at: '2026-06-22',
    new_flow: 'db/163 Option B (email + password at claim time)'
  });
};

// =====================================================
// ORIGINAL CODE BELOW — KEPT AS REFERENCE, NOT EXECUTED
// =====================================================
// (Below module.exports — never reached.)
//
// WhatsApp Magic Link claim flow (NO SMS / NO email OTP required).
//
// FLOW:
//   1. Admin pre-listed shop with mobile 98XXXXXX10 and sent claim
//      URL to that exact WhatsApp number.
//   2. Owner clicks the URL → claim.html loads with ?token=XXX.
//   3. Owner taps "Yes, mein owner hu" → claim.html POSTs to this
//      endpoint with { token }.
//   4. This endpoint:
//        a) Validates token via claim_lookup_by_token RPC
//        b) Creates/finds an auth.users row for that mobile (using
//           a synthetic email mobile_NNNNNNNNNN@owners.dukanlist.local
//           — never user-visible) with email_confirm + phone_confirm
//           BOTH true (admin bypass, no SMS/email sent).
//        c) Generates a Supabase magic-link with redirect_to pointing
//           to /claim-success.html?ct=ORIGINAL_TOKEN so the success
//           page can finalize the claim after Supabase auto-signs in.
//        d) Returns { magicLink } to the browser.
//   5. Browser navigates to magicLink → Supabase verify endpoint sets
//      session cookies → redirects to /claim-success.html?ct=XXX.
//   6. /claim-success.html (authenticated) calls claim_complete RPC
//      which links the auth user to the business and burns the token.
//
// WHY THIS IS SAFE WITHOUT OTP:
//   • The claim URL contains a 40-char random hex token (unguessable).
//   • Admin sends the URL via WhatsApp ONLY to the mobile number that
//     was pre-listed on the shop. Only the phone-holder sees it.
//   • Token is one-time use (claim_complete burns it after success).
//   • Re-running the link after a successful claim returns
//     "already_claimed" — no privilege creep.
//
// PRODUCTION REQUIREMENTS:
//   • SUPABASE_URL                env var
//   • SUPABASE_SERVICE_ROLE_KEY   env var (NEVER expose to client)
//   • PUBLIC_SITE_URL             env var (e.g. https://dukanlist.com)
// =====================================================

const SUPABASE_URL =
  process.env.SUPABASE_URL || 'https://qazuyygrpqopwygxmvwq.supabase.co';
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const REDIRECT_BASE = process.env.PUBLIC_SITE_URL || 'https://dukanlist.com';

// Synthetic email pattern — never user-facing. Used purely as a stable
// key inside auth.users for phone-based owners. Domain is intentionally
// .local so it cannot accidentally route real email.
const SYNTH_EMAIL_DOMAIN = 'owners.dukanlist.local';

async function sbFetch(path, opts = {}, key = SERVICE_KEY) {
  const headers = {
    apikey: key,
    Authorization: 'Bearer ' + key,
    'Content-Type': 'application/json',
    ...(opts.headers || {})
  };
  const url = SUPABASE_URL.replace(/\/$/, '') + path;
  const res = await fetch(url, { ...opts, headers });
  const txt = await res.text();
  let body = null;
  try { body = txt ? JSON.parse(txt) : null; } catch (_) { body = txt; }
  return { ok: res.ok, status: res.status, body };
}

function syntheticEmail(mobile) {
  return 'mobile_' + mobile + '@' + SYNTH_EMAIL_DOMAIN;
}

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');

  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed — use POST' });
    return;
  }

  if (!SERVICE_KEY) {
    res.status(500).json({
      error: 'SUPABASE_SERVICE_ROLE_KEY not configured on server',
      hint: 'Add it in Vercel → Settings → Environment Variables'
    });
    return;
  }

  // ===== 1. Parse body =====
  let body = req.body;
  if (typeof body === 'string') { try { body = JSON.parse(body); } catch (_) { body = {}; } }
  body = body || {};
  const token = (body.token || '').trim();
  if (!token || token.length < 16 || token.length > 80 || !/^[a-z0-9]+$/i.test(token)) {
    res.status(400).json({ error: 'Invalid claim token format' });
    return;
  }

  // ===== 2. Validate token via RPC (anon-safe) =====
  const lookup = await sbFetch('/rest/v1/rpc/claim_lookup_by_token', {
    method: 'POST',
    body: JSON.stringify({ p_token: token })
  });
  if (!lookup.ok) {
    res.status(500).json({ error: 'Token lookup failed', detail: lookup.body });
    return;
  }
  const shop = lookup.body || {};
  if (!shop.found) {
    res.status(404).json({ error: 'Claim link invalid or expired' });
    return;
  }
  if (shop.already_claimed) {
    res.status(409).json({ error: 'This shop has already been claimed', already_claimed: true });
    return;
  }

  const mobile = shop.full_mobile;
  if (!mobile || !/^[6789]\d{9}$/.test(mobile)) {
    res.status(400).json({ error: 'Pre-listed mobile is malformed — admin needs to fix' });
    return;
  }

  // ===== 3. Find or create the auth user for this mobile =====
  // Synthetic email is the stable key. Phone column is set for downstream
  // RPCs (claim_complete reads auth.users.phone).
  const synEmail = syntheticEmail(mobile);
  const phoneE164 = '+91' + mobile;

  let userId = null;

  // Try to find by synthetic email (cheap precise lookup)
  const find = await sbFetch(
    '/auth/v1/admin/users?filter=' + encodeURIComponent('email.eq.' + synEmail),
    { method: 'GET' }
  );
  if (find.ok && find.body && Array.isArray(find.body.users)) {
    const u = find.body.users.find(x => (x.email || '').toLowerCase() === synEmail);
    if (u) userId = u.id;
  }

  // If not found, also try by phone (in case a previous admin tool created
  // the user via /api/admin-create-owner-account with same mobile)
  if (!userId) {
    const findByPhone = await sbFetch(
      '/auth/v1/admin/users?filter=' + encodeURIComponent('phone.eq.' + phoneE164),
      { method: 'GET' }
    );
    if (findByPhone.ok && findByPhone.body && Array.isArray(findByPhone.body.users)) {
      const u = findByPhone.body.users[0];
      if (u) userId = u.id;
    }
  }

  // If still not found, create a fresh user
  if (!userId) {
    const create = await sbFetch('/auth/v1/admin/users', {
      method: 'POST',
      body: JSON.stringify({
        email: synEmail,
        phone: phoneE164,
        email_confirm: true,
        phone_confirm: true,
        user_metadata: {
          source: 'claim_via_link',
          mobile: mobile,
          shop_name: shop.name,
          claimed_at: new Date().toISOString()
        }
      })
    });
    if (!create.ok) {
      res.status(500).json({ error: 'Failed to create owner account', detail: create.body });
      return;
    }
    userId = (create.body && (create.body.id || (create.body.user && create.body.user.id))) || null;
    if (!userId) {
      res.status(500).json({ error: 'Created user but no ID returned', detail: create.body });
      return;
    }
  }

  // ===== 4. Generate magic link for that synthetic email =====
  // After click, Supabase verifies session and redirects to our
  // success page with the claim token in the URL so we can finalize.
  const redirectTo = REDIRECT_BASE.replace(/\/$/, '') +
    '/claim-success.html?ct=' + encodeURIComponent(token);

  const genLink = await sbFetch('/auth/v1/admin/generate_link', {
    method: 'POST',
    body: JSON.stringify({
      type: 'magiclink',
      email: synEmail,
      options: { redirect_to: redirectTo }
    })
  });

  if (!genLink.ok) {
    res.status(genLink.status || 500).json({
      error: 'Failed to generate sign-in link',
      detail: genLink.body
    });
    return;
  }

  const linkUrl =
    (genLink.body && genLink.body.properties && genLink.body.properties.action_link) ||
    (genLink.body && genLink.body.action_link) ||
    null;
  if (!linkUrl) {
    res.status(500).json({
      error: 'Sign-in link not returned by Supabase',
      detail: genLink.body
    });
    return;
  }

  // ===== 5. Bookkeeping: track that a claim attempt happened =====
  // Best-effort; do not block on failure.
  try {
    await sbFetch('/rest/v1/rpc/admin_increment_claim_sent', {
      method: 'POST',
      body: JSON.stringify({ p_business_id: shop.business_id })
    });
  } catch (_) {}

  // ===== 6. Return magic link to client =====
  res.status(200).json({
    success: true,
    magicLink: linkUrl,
    shop_name: shop.name
  });
};
