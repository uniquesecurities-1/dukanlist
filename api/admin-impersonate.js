// =====================================================
// api/admin-impersonate.js
// =====================================================
// USER REQUEST (2026-06-01):
//   "Ek system bhi generate kro jisse admin sidha shopkeeper ke login me
//    chala jaye taki exact issue ka pata chal sake agar user ko koi issue ho."
//
// HOW IT WORKS:
//   1. Admin clicks "Login as Owner" in admin/shop.html.
//   2. This endpoint generates a single-use magic link for the target user
//      via Supabase Admin API.
//   3. We URL-encode the impersonating admin's email into the redirect_to
//      query string so the panel can show a sticky banner.
//   4. Endpoint returns the URL — admin opens it in a new tab and is
//      instantly signed in as the shopkeeper.
//
// SAFETY GUARDRAILS:
//   * Service-role key never leaves the server.
//   * Caller JWT verified server-side, must pass is_admin() RPC.
//   * Cannot impersonate another admin (prevents privilege escalation).
//   * Audit log writes BOTH the impersonating admin's id AND the target's id.
//   * The receiving panel page shows an ALWAYS-ON RED BANNER on top so admin
//     never forgets they're in someone else's account.
//   * Magic link expires per Supabase default (1 hour).
//
// USAGE:
//   POST /api/admin-impersonate
//   Headers: Authorization: Bearer <admin JWT>
//   Body:    { email: "owner@example.com" }
//   Returns: { ok: true, url: "https://...supabase.co/auth/v1/verify?token=..." }
// =====================================================

const SUPABASE_URL =
  process.env.SUPABASE_URL || 'https://qazuyygrpqopwygxmvwq.supabase.co';
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

// Where the magic link should redirect after sign-in. The query params
// trigger the impersonation banner on the dashboard.
const REDIRECT_BASE = process.env.PUBLIC_SITE_URL || 'https://dukanlist.com';

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
  try { body = txt ? JSON.parse(txt) : null; } catch(_) { body = txt; }
  return { ok: res.ok, status: res.status, body };
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

  // ===== 1. Verify caller JWT =====
  const auth = req.headers.authorization || '';
  const jwt = auth.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!jwt) {
    res.status(401).json({ error: 'Missing Authorization header' });
    return;
  }

  const me = await sbFetch('/auth/v1/user', {
    method: 'GET',
    headers: { Authorization: 'Bearer ' + jwt, apikey: SERVICE_KEY }
  });
  if (!me.ok || !me.body || !me.body.id) {
    res.status(401).json({ error: 'Invalid or expired session' });
    return;
  }
  const adminId = me.body.id;
  const adminEmail = me.body.email || '';

  const isAdminRes = await sbFetch('/rest/v1/rpc/is_admin', {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + jwt, apikey: SERVICE_KEY },
    body: '{}'
  });
  if (!isAdminRes.ok || isAdminRes.body !== true) {
    res.status(403).json({ error: 'Admin access required' });
    return;
  }

  // ===== 2. Parse body =====
  let body = req.body;
  if (typeof body === 'string') { try { body = JSON.parse(body); } catch(_){ body = {}; } }
  body = body || {};
  const targetEmail = (body.email || '').trim().toLowerCase();
  if (!targetEmail || targetEmail.indexOf('@') === -1) {
    res.status(400).json({ error: 'Provide a valid target email in body { email }' });
    return;
  }
  if (targetEmail === (adminEmail || '').toLowerCase()) {
    res.status(400).json({ error: 'Cannot impersonate yourself' });
    return;
  }

  // ===== 3. Look up target — must not be another admin =====
  const lookup = await sbFetch(
    '/auth/v1/admin/users?filter=' + encodeURIComponent('email.eq.' + targetEmail),
    { method: 'GET' }
  );
  let targetUser = null;
  if (lookup.ok && lookup.body && Array.isArray(lookup.body.users)) {
    targetUser = lookup.body.users.find(u => (u.email || '').toLowerCase() === targetEmail);
  }
  if (!targetUser) {
    const listRes = await sbFetch('/auth/v1/admin/users?per_page=200', { method: 'GET' });
    if (listRes.ok && listRes.body && Array.isArray(listRes.body.users)) {
      targetUser = listRes.body.users.find(u => (u.email || '').toLowerCase() === targetEmail);
    }
  }
  if (!targetUser) {
    res.status(404).json({ error: 'No user with this email exists' });
    return;
  }

  // Block impersonating another admin
  const otherIsAdmin = await sbFetch(
    '/rest/v1/admin_users?select=role&auth_user_id=eq.' + encodeURIComponent(targetUser.id),
    { method: 'GET' }
  );
  if (otherIsAdmin.ok && Array.isArray(otherIsAdmin.body) && otherIsAdmin.body.length > 0) {
    res.status(403).json({
      error: 'Cannot impersonate another admin account.'
    });
    return;
  }

  // ===== 4. Generate magic link =====
  // We pass redirect_to with query params so the panel knows to show banner.
  // Param names are deliberately verbose to be obvious in any URL inspection.
  const redirectTo = REDIRECT_BASE.replace(/\/$/, '') +
    '/panel/dashboard.html' +
    '?dukan_impersonating=1' +
    '&dukan_impersonating_by=' + encodeURIComponent(adminEmail);

  const genLink = await sbFetch('/auth/v1/admin/generate_link', {
    method: 'POST',
    body: JSON.stringify({
      type: 'magiclink',
      email: targetEmail,
      options: { redirect_to: redirectTo }
    })
  });

  if (!genLink.ok) {
    res.status(genLink.status || 500).json({
      error: 'Failed to generate impersonation link',
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
      error: 'Magic link not returned by Supabase',
      detail: genLink.body
    });
    return;
  }

  // ===== 5. Audit log — critical for impersonation =====
  try {
    await sbFetch('/rest/v1/rpc/log_admin_action', {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + jwt, apikey: SERVICE_KEY },
      body: JSON.stringify({
        p_action: 'impersonate_user',
        p_target_type: 'user',
        p_target_id: targetUser.id,
        p_target_label: targetEmail,
        p_details: {
          impersonating_admin_id: adminId,
          impersonating_admin_email: adminEmail,
          reason: 'admin diagnostics — login as user to reproduce issue'
        }
      })
    });
  } catch(_){ /* non-fatal */ }

  res.status(200).json({
    ok: true,
    user_id: targetUser.id,
    email: targetEmail,
    url: linkUrl,
    expires_in_minutes: 60,
    warning: 'This is a privileged impersonation link. Open in a new private/incognito window so you don\'t mix sessions. Every action you take is logged against this user.'
  });
};
