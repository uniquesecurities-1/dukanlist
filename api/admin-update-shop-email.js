// =====================================================
// api/admin-update-shop-email.js
// Admin updates a shopkeeper's email address
// =====================================================
// FLOW:
//   1. Caller (any admin) sends their JWT in Authorization header.
//   2. Verify is_admin via JWT.
//   3. Look up business → get owner_id.
//   4. Use SUPABASE_SERVICE_ROLE_KEY to PATCH auth.users:
//        - email = new email
//        - email_confirm = true (skip new confirmation flow)
//   5. Return new email.
//
// USE CASE: Shopkeeper changed phone number / lost access to old email,
// or admin needs to re-link their auth to a different verified address.
//
// SECURITY: Requires is_admin() = TRUE (any admin, not just super).
// SERVICE_ROLE never sent to client.
// =====================================================

const SUPABASE_URL =
  process.env.SUPABASE_URL || 'https://qazuyygrpqopwygxmvwq.supabase.co';
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

async function sb(path, opts = {}, jwt = null) {
  const headers = {
    'apikey': SERVICE_KEY,
    'Authorization': `Bearer ${jwt || SERVICE_KEY}`,
    'Content-Type': 'application/json',
    ...(opts.headers || {})
  };
  const res = await fetch(`${SUPABASE_URL}${path}`, { ...opts, headers });
  const text = await res.text();
  let data;
  try { data = JSON.parse(text); } catch { data = text; }
  return { ok: res.ok, status: res.status, data };
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  if (!SERVICE_KEY) {
    return res.status(500).json({
      error: 'SUPABASE_SERVICE_ROLE_KEY not configured on server',
      hint: 'Add it in Vercel → Settings → Environment Variables'
    });
  }

  // 1. Extract caller JWT
  const auth = req.headers['authorization'] || '';
  const jwt = auth.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!jwt) {
    return res.status(401).json({ error: 'Missing Authorization Bearer token' });
  }

  // 2. Verify caller is admin
  const isAdm = await sb('/rest/v1/rpc/is_admin', {
    method: 'POST',
    body: '{}'
  }, jwt);
  if (!isAdm.ok || isAdm.data !== true) {
    return res.status(403).json({ error: 'Admin access required' });
  }

  // 3. Parse body
  let body = req.body;
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch { body = {}; }
  }
  const { business_id, new_email } = body || {};

  if (!business_id) {
    return res.status(400).json({ error: 'business_id required' });
  }
  if (!new_email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(new_email)) {
    return res.status(400).json({ error: 'Valid new_email required' });
  }

  const cleanEmail = String(new_email).toLowerCase().trim();

  // 4. Look up business → owner_id
  const bizLookup = await sb(
    `/rest/v1/businesses?id=eq.${encodeURIComponent(business_id)}&select=id,owner_id,name`,
    { method: 'GET' }
  );
  if (!bizLookup.ok || !Array.isArray(bizLookup.data) || bizLookup.data.length === 0) {
    return res.status(404).json({ error: 'Business not found' });
  }
  const biz = bizLookup.data[0];
  if (!biz.owner_id) {
    return res.status(400).json({
      error: 'This business has no linked owner account yet.',
      hint: 'Owner must register first, or use claim-by-phone flow.'
    });
  }

  // 5. Check email isn't already used by someone else
  const emailCheck = await sb(
    `/auth/v1/admin/users?email=${encodeURIComponent(cleanEmail)}`,
    { method: 'GET' }
  );
  if (emailCheck.ok && Array.isArray(emailCheck.data?.users) && emailCheck.data.users.length > 0) {
    const existing = emailCheck.data.users[0];
    if (existing.id !== biz.owner_id) {
      return res.status(409).json({
        error: 'Email already in use by another account',
        hint: 'Use a different email or merge accounts manually'
      });
    }
  }

  // 6. Update the auth user via admin API
  const updateUser = await sb(
    `/auth/v1/admin/users/${biz.owner_id}`,
    {
      method: 'PUT',
      body: JSON.stringify({
        email: cleanEmail,
        email_confirm: true   // auto-confirm — no re-verification flow
      })
    }
  );

  if (!updateUser.ok) {
    return res.status(updateUser.status).json({
      error: 'Failed to update email',
      details: updateUser.data
    });
  }

  // 7. Log to admin_audit_log (best-effort)
  try {
    await sb('/rest/v1/rpc/admin_log_action', {
      method: 'POST',
      body: JSON.stringify({
        p_action: 'shop_email_change',
        p_target_type: 'business',
        p_target_id: business_id,
        p_details: { new_email: cleanEmail, business_name: biz.name }
      })
    }, jwt);
  } catch(_){}

  return res.status(200).json({
    success: true,
    business_id,
    owner_id: biz.owner_id,
    new_email: cleanEmail,
    business_name: biz.name
  });
}
