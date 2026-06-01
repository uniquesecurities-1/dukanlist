// =====================================================
// api/admin-create-owner-account.js
// =====================================================
// USER REQUEST (2026-06-01, Deepak):
//   Many Dabwali shops were bulk-added by admin (e.g. Aashmi Traders) but
//   the shopkeeper never registered. Without an auth account, admin can't
//   help them log in / verify email / reset password / impersonate.
//
// THIS ENDPOINT:
//   POST /api/admin-create-owner-account
//   Body:    { business_id: UUID, email?: string, password?: string }
//   Headers: Authorization: Bearer <admin JWT>
//
//   Creates an auth.users entry for the shop's owner + links it via
//   business_owners table. Email is pre-confirmed (admin bypass).
//   Mobile is copied into user_metadata so future auto-claim works.
//
//   Returns the email + temp password so admin can copy & WhatsApp to owner.
//
// SAFETY:
//   * Refuses if business already has owner_user_id linked
//   * Refuses if the chosen email already exists in auth (caller should use
//     impersonate / reset password on that existing user instead)
//   * Uses caller JWT to verify is_admin() RPC server-side
//   * Logs to admin_audit_log (without password value)
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

function genPassword() {
  // Format: Dukan@NNNN — friendly, easy to type, easy to share via WhatsApp
  return 'Dukan@' + (1000 + Math.floor(Math.random() * 9000));
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
  const businessId = (body.business_id || '').trim();
  const overrideEmail = (body.email || '').trim().toLowerCase();
  const overridePassword = String(body.password || '').trim();

  if (!businessId || !/^[0-9a-f-]{36}$/i.test(businessId)) {
    res.status(400).json({ error: 'Provide a valid business_id in body' });
    return;
  }

  // ===== 3. Fetch business + check it has no owner yet =====
  const bizRes = await sbFetch(
    '/rest/v1/businesses?select=id,name,email,mobile,whatsapp,owner_name,city_id&id=eq.' + encodeURIComponent(businessId),
    { method: 'GET' }
  );
  if (!bizRes.ok || !Array.isArray(bizRes.body) || bizRes.body.length === 0) {
    res.status(404).json({ error: 'Business not found' });
    return;
  }
  const biz = bizRes.body[0];

  // Refuse if owner already linked
  const linkRes = await sbFetch(
    '/rest/v1/business_owners?select=auth_user_id&business_id=eq.' + encodeURIComponent(businessId) + '&limit=1',
    { method: 'GET' }
  );
  if (linkRes.ok && Array.isArray(linkRes.body) && linkRes.body.length > 0) {
    res.status(409).json({
      error: 'This business already has an owner account linked. Use Reset Password or Impersonate instead.'
    });
    return;
  }

  // ===== 4. Decide email + password =====
  const targetEmail = overrideEmail || (biz.email ? String(biz.email).toLowerCase().trim() : '');
  if (!targetEmail || targetEmail.indexOf('@') === -1) {
    res.status(400).json({
      error: 'No email available. The shop has no email and you did not provide one in the body.',
      hint: 'Either update shop_email first or pass {email: "..."} in the request body.'
    });
    return;
  }
  const password = overridePassword || genPassword();
  if (password.length < 8) {
    res.status(400).json({ error: 'Password must be at least 8 characters' });
    return;
  }
  if (password.length > 72) {
    res.status(400).json({ error: 'Password too long — bcrypt limit is 72 chars' });
    return;
  }

  // ===== 5. Check email is not already in auth =====
  const lookup = await sbFetch(
    '/auth/v1/admin/users?filter=' + encodeURIComponent('email.eq.' + targetEmail),
    { method: 'GET' }
  );
  let existingUser = null;
  if (lookup.ok && lookup.body && Array.isArray(lookup.body.users)) {
    existingUser = lookup.body.users.find(u => (u.email || '').toLowerCase() === targetEmail);
  }
  if (!existingUser) {
    // Fallback list scan
    const listRes = await sbFetch('/auth/v1/admin/users?per_page=200', { method: 'GET' });
    if (listRes.ok && listRes.body && Array.isArray(listRes.body.users)) {
      existingUser = listRes.body.users.find(u => (u.email || '').toLowerCase() === targetEmail);
    }
  }
  if (existingUser) {
    res.status(409).json({
      error: 'An account with this email already exists in the auth system.',
      existing_user_id: existingUser.id,
      hint: 'Either link this user to the business via business_owners directly, or use a different email.'
    });
    return;
  }

  // ===== 6. Create auth user — email pre-confirmed =====
  const createRes = await sbFetch('/auth/v1/admin/users', {
    method: 'POST',
    body: JSON.stringify({
      email: targetEmail,
      password: password,
      email_confirm: true,                // admin bypass — no verification needed
      user_metadata: {
        mobile: biz.mobile || null,        // so existing auto-claim by mobile keeps working
        created_by_admin: adminEmail,
        created_for_business_id: businessId,
        created_for_business_name: biz.name || null
      }
    })
  });
  if (!createRes.ok) {
    res.status(createRes.status || 500).json({
      error: 'Failed to create auth user',
      detail: createRes.body
    });
    return;
  }
  const newUserId = (createRes.body && (createRes.body.id || (createRes.body.user && createRes.body.user.id))) || null;
  if (!newUserId) {
    res.status(500).json({ error: 'Auth user created but no id returned', detail: createRes.body });
    return;
  }

  // ===== 7. Link to business_owners =====
  const linkInsert = await sbFetch('/rest/v1/business_owners', {
    method: 'POST',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({
      business_id:  businessId,
      auth_user_id: newUserId,
      role:         'owner'
    })
  });
  if (!linkInsert.ok) {
    // Roll back the auth user so we don't leave orphans
    await sbFetch('/auth/v1/admin/users/' + newUserId, { method: 'DELETE' });
    res.status(linkInsert.status || 500).json({
      error: 'Failed to link auth user to business (auth user rolled back)',
      detail: linkInsert.body
    });
    return;
  }

  // ===== 8. Audit log (never logs the password value) =====
  try {
    await sbFetch('/rest/v1/rpc/log_admin_action', {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + jwt, apikey: SERVICE_KEY },
      body: JSON.stringify({
        p_action: 'create_owner_account',
        p_target_type: 'business',
        p_target_id: businessId,
        p_target_label: biz.name || targetEmail,
        p_details: {
          new_user_id: newUserId,
          email: targetEmail,
          mobile: biz.mobile,
          created_by_admin_email: adminEmail
          // NEVER log password value
        }
      })
    });
  } catch(_){ /* non-fatal */ }

  res.status(200).json({
    ok: true,
    user_id: newUserId,
    email: targetEmail,
    password: password,
    business_id: businessId,
    message: 'Login account created. Share the email + password with the owner via WhatsApp. Advise them to change the password after first login from their panel.'
  });
};
