// =====================================================
// api/upload-shop-photo.js
// =====================================================
// MASTER FIX — LAYER 2 (server-side upload bypassing storage RLS)
//
// PURPOSE:
//   Direct supabase.storage.upload() from the browser depends on
//   Supabase Storage RLS policies + a fresh JWT + a valid
//   business_owners link. Any of those failing manifests as "Upload
//   permission issue / database schema is invalid" which has been
//   blocking shopkeepers for weeks.
//
//   This endpoint runs server-side with the service-role key, so it
//   bypasses storage RLS entirely. Security is enforced at the API
//   layer instead:
//
//     1. Caller must present a valid Supabase JWT (Authorization: Bearer)
//     2. Caller's email must be confirmed
//     3. Caller must own at least one business (lookup business_owners)
//     4. If no link yet, attempt self-heal via RPC try_self_heal_owner_link()
//     5. Caller's business must not be 'disabled'
//
// REQUEST (POST):
//   Headers: Authorization: Bearer <user_jwt>
//   Body (application/json):
//     { file: "data:image/jpeg;base64,/9j/4AAQ...", filename: "photo.jpg" }
//
// RESPONSE:
//   200 OK  { ok: true, url, path, business_id, photos_now: number }
//   4xx/5xx { error: "...", detail?: ... }
//
// PROD ENV NEEDED:
//   SUPABASE_URL                (public — but used here for fetch URLs)
//   SUPABASE_SERVICE_ROLE_KEY   (server-only, never expose)
// =====================================================

const SUPABASE_URL =
  process.env.SUPABASE_URL || 'https://qazuyygrpqopwygxmvwq.supabase.co';
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const BUCKET      = 'shop-photos';
const MAX_PHOTOS  = 6;
const MAX_BYTES   = 10 * 1024 * 1024; // 10 MB hard cap
const ALLOWED_MIME = ['image/jpeg','image/jpg','image/png','image/webp'];

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
  if (!me.email_confirmed_at) {
    return res.status(403).json({ error: 'Please verify your email first' });
  }
  const userId = me.id;

  // ===== 2. Lookup business_owners link =====
  // (use service-role REST so RLS doesn't filter the lookup)
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

  let ownerRows = await sbAdmin(
    '/rest/v1/business_owners?auth_user_id=eq.' + encodeURIComponent(userId)
    + '&select=business_id'
  );

  let businessId = null;
  if (ownerRows.ok && Array.isArray(ownerRows.body) && ownerRows.body.length) {
    businessId = ownerRows.body[0].business_id;
  }

  // ===== 3. Self-heal if no link =====
  if (!businessId) {
    const healRes = await sbAdmin('/rest/v1/rpc/try_self_heal_owner_link', {
      method: 'POST',
      body: JSON.stringify({ p_user_id: userId })
    });
    if (healRes.ok && healRes.body === true) {
      // Re-fetch
      ownerRows = await sbAdmin(
        '/rest/v1/business_owners?auth_user_id=eq.' + encodeURIComponent(userId)
        + '&select=business_id'
      );
      if (ownerRows.ok && Array.isArray(ownerRows.body) && ownerRows.body.length) {
        businessId = ownerRows.body[0].business_id;
      }
    }
  }

  if (!businessId) {
    return res.status(403).json({
      error: 'no_shop_linked',
      message: 'Your account is not linked to any shop yet. Please contact admin to link your account.'
    });
  }

  // ===== 4. Check business status =====
  const bizRes = await sbAdmin(
    '/rest/v1/businesses?id=eq.' + encodeURIComponent(businessId)
    + '&select=id,status,photos'
  );
  if (!bizRes.ok || !Array.isArray(bizRes.body) || !bizRes.body.length) {
    return res.status(404).json({ error: 'Business not found' });
  }
  const biz = bizRes.body[0];
  if (biz.status === 'disabled') {
    return res.status(403).json({ error: 'Your business has been disabled. Contact admin.' });
  }

  const currentPhotos = Array.isArray(biz.photos) ? biz.photos : [];
  if (currentPhotos.length >= MAX_PHOTOS) {
    return res.status(400).json({ error: 'Maximum ' + MAX_PHOTOS + ' photos already uploaded. Remove one to add new.' });
  }

  // ===== 5. Parse body =====
  let body = req.body;
  if (typeof body === 'string') { try { body = JSON.parse(body); } catch(_){ body = {}; } }
  body = body || {};
  const dataUrl = body.file;
  const origName = (body.filename || 'photo.jpg').toString();

  if (!dataUrl || typeof dataUrl !== 'string') {
    return res.status(400).json({ error: 'Missing "file" in body (base64 data URL expected)' });
  }
  const m = dataUrl.match(/^data:([^;]+);base64,(.+)$/);
  if (!m) {
    return res.status(400).json({ error: 'Invalid file format — must be base64 data URL' });
  }
  const mime = m[1].toLowerCase();
  if (!ALLOWED_MIME.includes(mime)) {
    return res.status(400).json({ error: 'Unsupported file type: ' + mime + '. Use JPG/PNG/WebP only.' });
  }
  let fileBuf;
  try {
    fileBuf = Buffer.from(m[2], 'base64');
  } catch (e) {
    return res.status(400).json({ error: 'Could not decode base64 file' });
  }
  if (fileBuf.length === 0) return res.status(400).json({ error: 'Empty file' });
  if (fileBuf.length > MAX_BYTES) {
    return res.status(400).json({
      error: 'File too large',
      detail: 'Size ' + (fileBuf.length/1048576).toFixed(2) + 'MB — max 10MB allowed.'
    });
  }

  // ===== 5.5 MIME magic-byte verification =====
  // Don't trust the declared mime — sniff the first few bytes to confirm
  // it's actually a real image. Prevents disguised binary uploads.
  function detectMime(buf) {
    if (!buf || buf.length < 12) return null;
    // JPEG: FF D8 FF
    if (buf[0] === 0xFF && buf[1] === 0xD8 && buf[2] === 0xFF) return 'image/jpeg';
    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4E && buf[3] === 0x47) return 'image/png';
    // WebP: RIFF .... WEBP
    if (buf[0] === 0x52 && buf[1] === 0x49 && buf[2] === 0x46 && buf[3] === 0x46 &&
        buf[8] === 0x57 && buf[9] === 0x45 && buf[10] === 0x42 && buf[11] === 0x50) return 'image/webp';
    return null;
  }
  const realMime = detectMime(fileBuf);
  if (!realMime) {
    return res.status(400).json({
      error: 'File is not a valid image',
      detail: 'Only JPEG, PNG, or WebP images are allowed. Magic-byte check failed.'
    });
  }
  // Normalize declared mime to detected one (handle image/jpg alias)
  if (realMime !== mime.replace('image/jpg', 'image/jpeg')) {
    // Declared mime doesn't match actual bytes — use detected one and continue
    console.warn('[upload] declared mime', mime, 'but detected', realMime, '— using detected.');
  }

  // ===== 5.5 OPTIONAL: AI image moderation =====
  // Only runs if both env vars are set (Cloudflare Worker deployed).
  // See workers/image-moderation/worker.js + IMAGE-MODERATION-SETUP.md
  // Fails OPEN: if the worker is down/slow, upload proceeds normally.
  const MOD_URL    = process.env.IMG_MOD_WORKER_URL;
  const MOD_SECRET = process.env.IMG_MOD_SECRET;
  if (MOD_URL && MOD_SECRET) {
    try {
      const controller = new AbortController();
      const t = setTimeout(() => controller.abort(), 8000); // 8s max wait
      const modRes = await fetch(MOD_URL, {
        method: 'POST',
        headers: {
          'Authorization': 'Bearer ' + MOD_SECRET,
          'Content-Type': mime
        },
        body: fileBuf,
        signal: controller.signal
      });
      clearTimeout(t);
      if (modRes.ok) {
        const verdict = await modRes.json();
        if (verdict && verdict.verdict === 'block') {
          return res.status(400).json({
            error: 'Image rejected by content safety check',
            detail: 'Reasons: ' + (verdict.reasons || []).join(', '),
            verdict
          });
        }
        // 'flag' → allow but log (admin reviews via /admin/moderation)
        if (verdict && verdict.verdict === 'flag') {
          console.warn('[upload] image flagged:', verdict.reasons);
        }
      }
      // Non-ok response from worker → fail open (allow upload)
    } catch (e) {
      // Worker unavailable / timed out — fail open, log to console
      console.warn('[upload] moderation skipped:', String(e.message || e).slice(0, 200));
    }
  }

  // ===== 6. Build storage path =====
  const ext = (mime === 'image/png') ? 'png'
            : (mime === 'image/webp') ? 'webp'
            : 'jpg';
  const rand = Math.random().toString(36).slice(2, 8);
  const storagePath = businessId + '/' + Date.now() + '-' + rand + '.' + ext;

  // ===== 7. Upload via service role (bypasses RLS) =====
  const uploadRes = await fetch(
    SUPABASE_URL + '/storage/v1/object/' + BUCKET + '/' + storagePath,
    {
      method: 'POST',
      headers: {
        apikey: SERVICE_KEY,
        Authorization: 'Bearer ' + SERVICE_KEY,
        'Content-Type': mime,
        'x-upsert': 'false'
      },
      body: fileBuf
    }
  );
  if (!uploadRes.ok) {
    const errTxt = await uploadRes.text();
    return res.status(500).json({
      error: 'Storage upload failed',
      detail: errTxt,
      status: uploadRes.status
    });
  }

  // ===== 8. Build public URL =====
  const publicUrl = SUPABASE_URL.replace(/\/$/, '')
    + '/storage/v1/object/public/' + BUCKET + '/' + storagePath;

  // ===== 9. Append to businesses.photos — ATOMIC via RPC =====
  // Old version did read-then-PATCH-whole-array which had a lost-update
  // race when 2 photos uploaded concurrently. db/100 added
  // owner_append_shop_photo() which does the append in a single
  // SELECT FOR UPDATE → array_append → UPDATE transaction.
  // Call the atomic RPC with the user's JWT so auth.uid() resolves
  // correctly inside the SECURITY DEFINER function (it checks the
  // business_owners table to verify the caller owns this business).
  const rpcRes = await sbAdmin('/rest/v1/rpc/owner_append_shop_photo', {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + jwt },  // override service-role with user JWT
    body: JSON.stringify({
      p_business_id: businessId,
      p_url:         publicUrl,
      p_max_photos:  MAX_PHOTOS
    })
  });
  if (!rpcRes.ok) {
    // Race-aware fallback: clean up the uploaded storage blob
    try {
      await fetch(SUPABASE_URL + '/storage/v1/object/' + BUCKET + '/' + storagePath, {
        method: 'DELETE',
        headers: { apikey: SERVICE_KEY, Authorization: 'Bearer ' + SERVICE_KEY }
      });
    } catch(_){}
    return res.status(500).json({
      error: 'Failed to update business photos',
      detail: (rpcRes.body && rpcRes.body.message) || rpcRes.body || 'RPC error'
    });
  }
  const updatedPhotos = (rpcRes.body && rpcRes.body.photos) || null;

  // ===== 10. Best-effort activate pending business after first photo =====
  try {
    if (biz.status === 'pending' && currentPhotos.length === 0) {
      await sbAdmin('/rest/v1/rpc/activate_business_after_photos', {
        method: 'POST',
        body: JSON.stringify({ p_business_id: businessId })
      });
    }
  } catch(_){}

  // photos_now: prefer the atomic RPC's authoritative count
  const photosNow = Array.isArray(updatedPhotos)
    ? updatedPhotos.length
    : (currentPhotos.length + 1);

  return res.status(200).json({
    ok: true,
    url: publicUrl,
    path: storagePath,
    business_id: businessId,
    photos_now: photosNow
  });
};

// Allow up to 15MB JSON body (10MB raw file = ~13.3MB base64)
module.exports.config = {
  api: {
    bodyParser: {
      sizeLimit: '15mb'
    }
  }
};
