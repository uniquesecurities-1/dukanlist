// =====================================================
// api/admin-delete-user.js
// Hard-delete an admin user (auth.users + admin_users row)
// =====================================================
// Use sparingly — soft-disable is preferred. This wipes the auth user
// from Supabase entirely.
//
// Flow:
//   1. Caller's JWT verified as super-admin via get_admin_scope().
//   2. admin_remove_admin RPC deletes admin_users row + logs action.
//   3. service_role deletes the auth.users entry.
//
// REQUIRED VERCEL ENV VARS:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
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
    return res.status(500).json({ error: 'SUPABASE_SERVICE_ROLE_KEY missing' });
  }

  const auth = req.headers['authorization'] || '';
  const jwt = auth.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!jwt) return res.status(401).json({ error: 'Missing Authorization' });

  const scope = await sb('/rest/v1/rpc/get_admin_scope', {
    method: 'POST', body: '{}'
  }, jwt);
  if (!scope.ok || !scope.data?.is_super) {
    return res.status(403).json({ error: 'Super-admin only' });
  }

  let body = req.body;
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch { body = {}; }
  }
  const { auth_user_id } = body || {};
  if (!auth_user_id) {
    return res.status(400).json({ error: 'auth_user_id required' });
  }

  // 1. Remove admin_users row via RPC (logs the action)
  const remove = await sb('/rest/v1/rpc/admin_remove_admin', {
    method: 'POST',
    body: JSON.stringify({ p_auth_user_id: auth_user_id })
  }, jwt);
  if (!remove.ok) {
    return res.status(remove.status).json({
      error: 'Failed to remove admin row', details: remove.data
    });
  }

  // 2. Delete from auth.users (service_role)
  const del = await sb(`/auth/v1/admin/users/${auth_user_id}`, { method: 'DELETE' });
  if (!del.ok) {
    return res.status(207).json({
      success: false,
      partial: true,
      message: 'admin_users row removed, but auth.users delete failed',
      details: del.data
    });
  }

  return res.status(200).json({ success: true, auth_user_id });
}
