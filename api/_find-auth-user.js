// =====================================================
// api/_find-auth-user.js — find a Supabase auth user by email
// =====================================================
// v357 (Deepak, 13 Oct: "Login as Owner" → "No user with this email
// exists" for Sharma Button Traders, whose owner account is verified).
// The four admin endpoints looked the user up with
//   /auth/v1/admin/users?filter=email.eq.<email>
// — GoTrue has no such filter syntax, so that returned page 1 of all users
// — and then fell back to ONE page of 200. With more than 200 accounts,
// anyone past the first page was "not found". This walks every page.
// (Files starting with "_" are not exposed as Vercel functions.)
// =====================================================
module.exports = async function findAuthUserByEmail(sbFetch, email){
  const target = String(email || '').trim().toLowerCase();
  if (!target) return null;
  const match = (list) => (Array.isArray(list) ? list : []).find(u => String(u.email || '').toLowerCase() === target) || null;

  // 1. GoTrue's free-text filter (matches email / phone) — one quick request
  try {
    const q = await sbFetch('/auth/v1/admin/users?per_page=50&filter=' + encodeURIComponent(target), { method: 'GET' });
    const hit = q.ok && q.body ? match(q.body.users) : null;
    if (hit) return hit;
  } catch(_){}

  // 2. every page, 1000 at a time (stops at the first short page)
  const PER = 1000;
  for (let page = 1; page <= 50; page++){
    const r = await sbFetch('/auth/v1/admin/users?page=' + page + '&per_page=' + PER, { method: 'GET' });
    if (!r.ok || !r.body || !Array.isArray(r.body.users)) break;
    const hit = match(r.body.users);
    if (hit) return hit;
    if (r.body.users.length < PER) break;
  }
  return null;
};
