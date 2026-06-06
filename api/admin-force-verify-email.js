// =====================================================
// api/admin-force-verify-email.js
// =====================================================
// USER REQUEST (2026-05-28):
//   "Most of the time email for verification user ke paas jaati hi nahi hai...
//    Resend email feature bhi hona chahiye, aur agar email even spam me bhi
//    nahi mile to manual override bhi hona chahiye."
//
// FLOW:
//   1. Admin sends their JWT in Authorization header.
//   2. Server verifies that JWT belongs to an admin (via is_admin RPC).
//   3. Server uses SUPABASE_SERVICE_ROLE_KEY to call Supabase Auth Admin API:
//      PATCH auth/v1/admin/users/{user_id}  { email_confirm: true }
//   4. Returns success → user can now login + business becomes visible in
//      admin moderation queue automatically (because email_confirmed_at is now set).
//
// SECURITY:
//   - SERVICE_KEY never leaves the server.
//   - Admin's JWT is verified server-side before any privileged action.
//   - Action is logged via admin_audit_log (if available).
// =====================================================

const SUPABASE_URL =
  process.env.SUPABASE_URL || 'https://qazuyygrpqopwygxmvwq.supabase.co';
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

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

  // Fetch the caller user via their JWT
  const me = await sbFetch('/auth/v1/user', {
    method: 'GET',
    headers: { Authorization: 'Bearer ' + jwt, apikey: SERVICE_KEY }
  });
  if (!me.ok || !me.body || !me.body.id) {
    res.status(401).json({ error: 'Invalid or expired session' });
    return;
  }
  const callerId = me.body.id;

  // Check caller is admin via RPC (using caller JWT — RLS-safe)
  const isAdminRes = await sbFetch('/rest/v1/rpc/is_admin', {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + jwt, apikey: SERVICE_KEY },
    body: '{}'
  });
  if (!isAdminRes.ok || isAdminRes.body !== true) {
    res.status(403).json({ error: 'Admin access required' });
    return;
  }

  // ===== 2. Parse target =====
  let body = req.body;
  if (typeof body === 'string') { try { body = JSON.parse(body); } catch(_){ body = {}; } }
  body = body || {};
  const targetEmail = (body.email || '').trim().toLowerCase();
  if (!targetEmail || targetEmail.indexOf('@') === -1) {
    res.status(400).json({ error: 'Provide a valid target email in body { email }' });
    return;
  }

  // ===== 3. Lookup target user by email (admin-only API) =====
  const lookup = await sbFetch('/auth/v1/admin/users?filter=' + encodeURIComponent('email.eq.' + targetEmail), {
    method: 'GET'
  });
  // Fallback: list users + filter (older Supabase versions)
  let targetUser = null;
  if (lookup.ok && lookup.body && Array.isArray(lookup.body.users)) {
    targetUser = lookup.body.users.find(u => (u.email || '').toLowerCase() === targetEmail);
  } else if (lookup.ok && lookup.body && lookup.body.id) {
    targetUser = lookup.body;
  }
  if (!targetUser) {
    // Last-resort listing scan
    const listRes = await sbFetch('/auth/v1/admin/users?per_page=200', { method: 'GET' });
    if (listRes.ok && listRes.body && Array.isArray(listRes.body.users)) {
      targetUser = listRes.body.users.find(u => (u.email || '').toLowerCase() === targetEmail);
    }
  }
  if (!targetUser) {
    res.status(404).json({ error: 'No user with this email exists in auth' });
    return;
  }

  if (targetUser.email_confirmed_at) {
    res.status(200).json({
      ok: true,
      already_verified: true,
      message: 'This email is already verified — nothing to do.'
    });
    return;
  }

  // ===== 4. Force-confirm email via admin API =====
  const patch = await sbFetch('/auth/v1/admin/users/' + targetUser.id, {
    method: 'PUT',
    body: JSON.stringify({ email_confirm: true })
  });
  if (!patch.ok) {
    res.status(patch.status || 500).json({
      error: 'Failed to mark email as verified',
      detail: patch.body
    });
    return;
  }

  // ===== 5. Log admin action (best-effort) =====
  try {
    await sbFetch('/rest/v1/rpc/log_admin_action', {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + jwt, apikey: SERVICE_KEY },
      body: JSON.stringify({
        p_action: 'force_verify_email',
        p_target_type: 'user',
        p_target_id: targetUser.id,
        p_target_label: targetEmail,
        p_details: { reason: 'manual override — email delivery failed' }
      })
    });
  } catch(_){ /* non-fatal */ }

  res.status(200).json({
    ok: true,
    user_id: targetUser.id,
    email: targetEmail,
    message: 'Email verified manually. User can now login. Their business will appear in the moderation queue automatically.'
  });
};
