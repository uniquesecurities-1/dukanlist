// =====================================================
// api/admin-reset-password.js
// =====================================================
// USER REQUEST (2026-06-01):
//   "Admin ko user ka password dekhne ka right do, Dabwali me bahut se user
//    password bhul rahe hai aur forget wala process na karke mujhse hi password
//    maangte hai."
//
// WHY NOT "SHOW PASSWORD":
//   Supabase (and every modern auth system) stores passwords as one-way
//   bcrypt hashes. The plaintext password is *cryptographically impossible*
//   to recover — even Supabase staff cannot read it. So instead of "showing",
//   this endpoint LETS THE ADMIN SET A NEW TEMP PASSWORD that they can share
//   with the user verbally or over WhatsApp. The user can then login with
//   that temp password and change it from their panel.
//
// THIS ENDPOINT:
//   POST /api/admin-reset-password
//   Body:    { email: "user@example.com", new_password: "Dabwali@2026" }
//   Headers: Authorization: Bearer <admin JWT>
//   Returns: { ok: true, message: "Password reset successfully." }
//
// SECURITY:
//   * Service-role key never leaves the server.
//   * Caller JWT verified server-side, must pass is_admin() RPC check.
//   * Action logged via log_admin_action (best-effort).
//   * Minimum 8 chars enforced; max 72 chars (bcrypt limit).
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

  // ===== 1. Verify caller JWT + admin status =====
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
  const callerId = me.body.id;
  const callerEmail = me.body.email || '';

  const isAdminRes = await sbFetch('/rest/v1/rpc/is_admin', {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + jwt, apikey: SERVICE_KEY },
    body: '{}'
  });
  if (!isAdminRes.ok || isAdminRes.body !== true) {
    res.status(403).json({ error: 'Admin access required' });
    return;
  }

  // ===== 2. Parse + validate body =====
  let body = req.body;
  if (typeof body === 'string') { try { body = JSON.parse(body); } catch(_){ body = {}; } }
  body = body || {};
  const targetEmail = (body.email || '').trim().toLowerCase();
  const newPassword = String(body.new_password || '');

  if (!targetEmail || targetEmail.indexOf('@') === -1) {
    res.status(400).json({ error: 'Provide a valid target email in body { email }' });
    return;
  }
  if (newPassword.length < 8) {
    res.status(400).json({ error: 'New password must be at least 8 characters' });
    return;
  }
  if (newPassword.length > 72) {
    res.status(400).json({ error: 'Password too long — bcrypt limit is 72 characters' });
    return;
  }

  // Don't allow admin to reset their own password through this endpoint
  // (could be a phishing vector via XSS). Admin can use the regular flow.
  if (targetEmail === (callerEmail || '').toLowerCase()) {
    res.status(400).json({
      error: 'Cannot reset your own password here. Use the regular reset flow on /forgot-password.html'
    });
    return;
  }

  // ===== 3. Lookup target user =====
  const lookup = await sbFetch('/auth/v1/admin/users?filter=' + encodeURIComponent('email.eq.' + targetEmail), {
    method: 'GET'
  });
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

  // Refuse to reset password of another admin (prevent privilege escalation
  // via lower-tier admin resetting super_admin's password)
  const otherIsAdmin = await sbFetch(
    '/rest/v1/admin_users?select=role&auth_user_id=eq.' + encodeURIComponent(targetUser.id),
    { method: 'GET' }
  );
  if (otherIsAdmin.ok && Array.isArray(otherIsAdmin.body) && otherIsAdmin.body.length > 0) {
    res.status(403).json({
      error: 'This user is also an admin. Use the admin management page to handle admin accounts.'
    });
    return;
  }

  // ===== 4. Set new password via admin API =====
  const patch = await sbFetch('/auth/v1/admin/users/' + targetUser.id, {
    method: 'PUT',
    body: JSON.stringify({ password: newPassword })
  });
  if (!patch.ok) {
    res.status(patch.status || 500).json({
      error: 'Failed to reset password',
      detail: patch.body
    });
    return;
  }

  // ===== 5. Audit log (best-effort, never leaks the actual password) =====
  try {
    await sbFetch('/rest/v1/rpc/log_admin_action', {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + jwt, apikey: SERVICE_KEY },
      body: JSON.stringify({
        p_action: 'reset_user_password',
        p_target_type: 'user',
        p_target_id: targetUser.id,
        p_target_label: targetEmail,
        p_details: {
          reason: 'admin-set temporary password — user requested help',
          password_length: newPassword.length
          // NEVER log the actual password value
        }
      })
    });
  } catch(_){ /* non-fatal */ }

  res.status(200).json({
    ok: true,
    user_id: targetUser.id,
    email: targetEmail,
    message: 'Password reset successfully. Share the new password with the user via WhatsApp or phone. Advise them to change it once logged in.'
  });
};
