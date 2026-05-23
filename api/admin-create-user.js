// =====================================================
// api/admin-create-user.js
// Create a new admin auth user + admin_users row in one shot
// =====================================================
// FLOW:
//   1. Caller (super-admin) sends their JWT in Authorization header.
//   2. We call get_admin_scope() with that JWT to verify they're super-admin.
//   3. Then we use SUPABASE_SERVICE_ROLE_KEY to:
//        a) auth.admin.createUser(email, password)  — email_confirm = true
//        b) INSERT admin_users (auth_user_id, role, email, display_name,
//                               assigned_city_ids, disabled = false)
//   4. Return the new auth_user_id + email.
//
// REQUIRED VERCEL ENV VARS:
//   SUPABASE_URL              — https://<project>.supabase.co
//   SUPABASE_SERVICE_ROLE_KEY — Project → Settings → API → service_role
//                               (NEVER expose this client-side!)
// =====================================================

const SUPABASE_URL =
  process.env.SUPABASE_URL || 'https://qazuyygrpqopwygxmvwq.supabase.co';
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

async function sb(path, opts = {}, jwt = null) {
  // apikey MUST always be a project-level key (service_role).
  // The user JWT goes in Authorization for user-scoped operations.
  // Sending a user JWT as apikey triggers "Invalid API key".
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

  // 2. Verify caller is super-admin
  const scope = await sb('/rest/v1/rpc/get_admin_scope', {
    method: 'POST',
    body: '{}'
  }, jwt);
  if (!scope.ok) {
    return res.status(403).json({ error: 'Could not verify caller', details: scope.data });
  }
  if (!scope.data?.is_super) {
    return res.status(403).json({ error: 'Super-admin only' });
  }

  // 3. Parse body
  let body = req.body;
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch { body = {}; }
  }
  const { email, password, display_name, role, assigned_city_ids } = body || {};

  if (!email || !password || !role) {
    return res.status(400).json({ error: 'email, password, role required' });
  }
  if (!['admin', 'super_admin', 'city_moderator', 'moderator'].includes(role)) {
    return res.status(400).json({ error: 'Invalid role' });
  }
  if (password.length < 8) {
    return res.status(400).json({ error: 'Password must be at least 8 characters' });
  }
  if (role === 'city_moderator' &&
      (!Array.isArray(assigned_city_ids) || assigned_city_ids.length === 0)) {
    return res.status(400).json({ error: 'city_moderator needs at least one assigned city' });
  }

  // 4. Create auth user (service_role)
  const createUser = await sb('/auth/v1/admin/users', {
    method: 'POST',
    body: JSON.stringify({
      email: String(email).toLowerCase().trim(),
      password,
      email_confirm: true,
      user_metadata: { display_name: display_name || null, created_by_admin: true }
    })
  });
  if (!createUser.ok) {
    return res.status(createUser.status).json({
      error: 'Failed to create auth user',
      details: createUser.data
    });
  }
  const newUserId = createUser.data?.id || createUser.data?.user?.id;
  if (!newUserId) {
    return res.status(500).json({ error: 'Auth user created but no id returned' });
  }

  // 5. Insert into admin_users via RPC (uses super-admin's JWT for audit trail)
  const upsert = await sb('/rest/v1/rpc/admin_upsert_admin', {
    method: 'POST',
    body: JSON.stringify({
      p_auth_user_id: newUserId,
      p_role: role,
      p_email: String(email).toLowerCase().trim(),
      p_display_name: display_name || email,
      p_assigned_city_ids: role === 'city_moderator' ? assigned_city_ids : null
    })
  }, jwt);

  if (!upsert.ok) {
    // Roll back the auth user so we don't leave orphans
    await sb(`/auth/v1/admin/users/${newUserId}`, { method: 'DELETE' });
    return res.status(upsert.status).json({
      error: 'Failed to register admin row (auth user rolled back)',
      details: upsert.data
    });
  }

  return res.status(200).json({
    success: true,
    auth_user_id: newUserId,
    email,
    role
  });
}
