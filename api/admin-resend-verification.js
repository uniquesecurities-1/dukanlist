// =====================================================
// api/admin-resend-verification.js
// =====================================================
// Admin endpoint to RESEND the Supabase signup confirmation email to a user
// who hasn't verified their email yet. Used from /admin/moderation.html
// "📧 Resend Email" button in the pending-email-verify list.
//
// FLOW:
//   1. Verify admin JWT (Authorization: Bearer)
//   2. Check the caller is an admin (RPC is_admin)
//   3. Call Supabase Admin Auth API to re-trigger the confirmation email
//      via the public /auth/v1/resend endpoint with apikey=service-role
//      so we can resend on behalf of the user.
//
// REQUEST (POST):
//   Headers: Authorization: Bearer <admin_jwt>
//   Body: { email: "user@example.com" }
//
// RESPONSE:
//   200 { ok: true, message: "Verification email sent again" }
//   4xx/5xx { error, detail }
// =====================================================

const SUPABASE_URL =
  process.env.SUPABASE_URL || 'https://qazuyygrpqopwygxmvwq.supabase.co';
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY    = process.env.SUPABASE_ANON_KEY;

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'POST only' });
  }
  if (!SERVICE_KEY) {
    return res.status(500).json({ error: 'SUPABASE_SERVICE_ROLE_KEY missing on server' });
  }

  // ===== 1. Auth =====
  const auth = req.headers.authorization || '';
  const jwt  = auth.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!jwt) return res.status(401).json({ error: 'Missing Authorization header' });

  // Verify JWT and get user info
  const meRes = await fetch(SUPABASE_URL + '/auth/v1/user', {
    method: 'GET',
    headers: { Authorization: 'Bearer ' + jwt, apikey: SERVICE_KEY }
  });
  if (!meRes.ok) return res.status(401).json({ error: 'Invalid session' });
  const me = await meRes.json();
  if (!me || !me.id) return res.status(401).json({ error: 'Invalid session' });

  // ===== 2. Check admin =====
  async function sbAdmin(path, opts = {}) {
    const headers = {
      apikey: SERVICE_KEY,
      Authorization: 'Bearer ' + SERVICE_KEY,
      'Content-Type': 'application/json',
      ...(opts.headers || {})
    };
    const r = await fetch(SUPABASE_URL + path, { ...opts, headers });
    const t = await r.text();
    let body = null; try { body = t ? JSON.parse(t) : null; } catch(_){ body = t; }
    return { ok: r.ok, status: r.status, body };
  }
  async function sbAsUser(path, opts = {}) {
    // Calls REST as the caller's JWT, so RLS rules apply normally
    const headers = {
      apikey: SERVICE_KEY,
      Authorization: 'Bearer ' + jwt,
      'Content-Type': 'application/json',
      ...(opts.headers || {})
    };
    const r = await fetch(SUPABASE_URL + path, { ...opts, headers });
    const t = await r.text();
    let body = null; try { body = t ? JSON.parse(t) : null; } catch(_){ body = t; }
    return { ok: r.ok, status: r.status, body };
  }

  // Use the is_admin() RPC, evaluated under the caller's JWT
  const adminCheck = await sbAsUser('/rest/v1/rpc/is_admin', {
    method: 'POST',
    body: JSON.stringify({})
  });
  if (!adminCheck.ok || adminCheck.body !== true) {
    return res.status(403).json({ error: 'Not an admin' });
  }

  // ===== 3. Parse body =====
  let body = req.body;
  if (typeof body === 'string') { try { body = JSON.parse(body); } catch(_){ body = {}; } }
  body = body || {};
  const email = (body.email || '').toString().trim().toLowerCase();
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return res.status(400).json({ error: 'Valid email required' });
  }

  // ===== 4. Look up the user — must exist and NOT yet be confirmed =====
  // Use Admin REST to find the user by email
  const lookupRes = await sbAdmin(
    '/auth/v1/admin/users?email=' + encodeURIComponent(email),
    { method: 'GET' }
  );
  let targetUser = null;
  if (lookupRes.ok && lookupRes.body && Array.isArray(lookupRes.body.users) && lookupRes.body.users.length) {
    targetUser = lookupRes.body.users[0];
  }
  if (!targetUser) {
    return res.status(404).json({ error: 'No account found with this email' });
  }
  if (targetUser.email_confirmed_at) {
    return res.status(409).json({ error: 'Email already verified — no need to resend' });
  }

  // ===== 5. Generate a fresh signup confirmation link AND send email =====
  // Supabase Admin Auth API: /auth/v1/admin/generate_link
  //   type: 'signup' → re-issues the confirm-signup email
  //   The link is also EMAILED by Supabase's SMTP automatically (when
  //   the email template + SMTP are configured in the dashboard).
  const generateRes = await sbAdmin('/auth/v1/admin/generate_link', {
    method: 'POST',
    body: JSON.stringify({
      type: 'signup',
      email: email,
      options: {
        redirect_to: 'https://dukanlist.com/login.html?verified=1'
      }
    })
  });

  if (!generateRes.ok) {
    return res.status(generateRes.status || 500).json({
      error: 'Could not regenerate verification link',
      detail: generateRes.body
    });
  }

  // Audit log (best-effort, ignored if log table doesn't exist)
  try {
    await sbAdmin('/rest/v1/admin_audit_log', {
      method: 'POST',
      body: JSON.stringify({
        admin_user_id: me.id,
        action: 'resend_verification_email',
        target_email: email,
        target_user_id: targetUser.id,
        notes: 'Manual resend via admin/moderation pending-email-verify list'
      })
    });
  } catch(_){ /* ignore */ }

  return res.status(200).json({
    ok: true,
    message: 'Verification email re-sent to ' + email,
    user_id: targetUser.id
  });
};
