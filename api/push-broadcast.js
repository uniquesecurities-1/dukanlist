// =====================================================
// api/push-broadcast.js
// Send a Web Push notification to all matching subscribers
// =====================================================
// Hand-rolled — no npm 'web-push' dependency.
// Uses Node 18+ crypto for VAPID JWT signing + AES-128-GCM
// payload encryption per RFC 8291.
//
// REQUIRED Vercel env vars:
//   VAPID_PUBLIC_KEY   — base64url-encoded EC P-256 public key
//   VAPID_PRIVATE_KEY  — base64url-encoded EC P-256 private key
//   VAPID_SUBJECT      — mailto:contact@dukanlist.com (any contact URL)
//   SUPABASE_URL
//   SUPABASE_SERVICE_ROLE_KEY
//
// Request body (POST):
//   { title, body, url, image?, audience? }
// =====================================================

import crypto from 'crypto';

const VAPID_PUBLIC_KEY  = process.env.VAPID_PUBLIC_KEY  || '';
const VAPID_PRIVATE_KEY = process.env.VAPID_PRIVATE_KEY || '';
const VAPID_SUBJECT     = process.env.VAPID_SUBJECT     || 'mailto:admin@dukanlist.com';
const SUPABASE_URL      = process.env.SUPABASE_URL      || 'https://qazuyygrpqopwygxmvwq.supabase.co';
const SERVICE_KEY       = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

// ---------- base64url helpers ----------
function b64urlEncode(buf){
  return Buffer.from(buf).toString('base64url');
}
function b64urlDecode(s){
  return Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}

// ---------- VAPID JWT (ES256) ----------
function vapidJwt(audience){
  if (!VAPID_PRIVATE_KEY || !VAPID_PUBLIC_KEY) throw new Error('VAPID keys not configured');
  const header  = { typ: 'JWT', alg: 'ES256' };
  const payload = {
    aud: audience,
    exp: Math.floor(Date.now() / 1000) + 12 * 3600,
    sub: VAPID_SUBJECT
  };
  const signingInput = b64urlEncode(JSON.stringify(header)) + '.' + b64urlEncode(JSON.stringify(payload));

  // Reconstruct EC P-256 key from raw private bytes
  const d = b64urlDecode(VAPID_PRIVATE_KEY);
  const pub = b64urlDecode(VAPID_PUBLIC_KEY);
  // Build JWK
  const jwk = {
    kty: 'EC',
    crv: 'P-256',
    d:   b64urlEncode(d),
    x:   b64urlEncode(pub.slice(1, 33)),   // first byte is 0x04 (uncompressed marker)
    y:   b64urlEncode(pub.slice(33, 65))
  };
  const keyObj = crypto.createPrivateKey({ key: jwk, format: 'jwk' });
  const sigDer = crypto.sign('SHA256', Buffer.from(signingInput), keyObj);
  // Convert DER signature to raw r||s (64 bytes)
  const sigRaw = derToJose(sigDer, 32);
  return signingInput + '.' + b64urlEncode(sigRaw);
}

function derToJose(der, keyLen){
  // DER: 0x30 L 0x02 Lr R 0x02 Ls S
  let offset = 2; // skip 0x30 L
  if (der[1] & 0x80) offset += der[1] & 0x7f; // long length
  if (der[offset++] !== 0x02) throw new Error('bad DER sig');
  const rLen = der[offset++]; const r = der.slice(offset, offset + rLen); offset += rLen;
  if (der[offset++] !== 0x02) throw new Error('bad DER sig');
  const sLen = der[offset++]; const s = der.slice(offset, offset + sLen);
  // Strip leading zeros
  const rTrim = trimLeadingZeros(r), sTrim = trimLeadingZeros(s);
  const out = Buffer.alloc(2 * keyLen);
  Buffer.from(rTrim).copy(out, keyLen - rTrim.length);
  Buffer.from(sTrim).copy(out, 2 * keyLen - sTrim.length);
  return out;
}
function trimLeadingZeros(buf){
  let i = 0;
  while (i < buf.length - 1 && buf[i] === 0) i++;
  return buf.slice(i);
}

// ---------- AES-128-GCM payload encryption (aes128gcm scheme) ----------
async function encryptPayload(plaintext, recipientP256dh, recipientAuth){
  // 1. Generate one-time ECDH key pair
  const ec = crypto.createECDH('prime256v1');
  ec.generateKeys();
  const senderPub  = ec.getPublicKey();             // 65 bytes uncompressed
  const recipPub   = b64urlDecode(recipientP256dh);
  const sharedSecret = ec.computeSecret(recipPub);

  // 2. HKDF-extract / expand per RFC 8291
  const salt = crypto.randomBytes(16);
  const auth = b64urlDecode(recipientAuth);

  // PRK_key = HMAC-SHA256(auth, sharedSecret)
  // keyInfo = "WebPush: info\0" || recipPub || senderPub
  const keyInfo = Buffer.concat([
    Buffer.from('WebPush: info\0', 'utf8'),
    recipPub,
    senderPub
  ]);
  const prkKey = crypto.createHmac('sha256', auth).update(sharedSecret).digest();
  const ikm    = crypto.createHmac('sha256', prkKey).update(Buffer.concat([keyInfo, Buffer.from([0x01])])).digest();

  // PRK = HMAC-SHA256(salt, IKM)
  const prk = crypto.createHmac('sha256', salt).update(ikm).digest();
  // CEK = HMAC-SHA256(PRK, "Content-Encoding: aes128gcm\0\x01") [first 16 bytes]
  const cek = crypto.createHmac('sha256', prk).update(Buffer.concat([Buffer.from('Content-Encoding: aes128gcm\0', 'utf8'), Buffer.from([0x01])])).digest().slice(0, 16);
  // NONCE = HMAC-SHA256(PRK, "Content-Encoding: nonce\0\x01") [first 12 bytes]
  const nonce = crypto.createHmac('sha256', prk).update(Buffer.concat([Buffer.from('Content-Encoding: nonce\0', 'utf8'), Buffer.from([0x01])])).digest().slice(0, 12);

  // 3. Encrypt with AES-128-GCM
  // Plaintext gets padding byte 0x02 appended
  const padded = Buffer.concat([Buffer.from(plaintext, 'utf8'), Buffer.from([0x02])]);
  const cipher = crypto.createCipheriv('aes-128-gcm', cek, nonce);
  const ct = Buffer.concat([cipher.update(padded), cipher.final()]);
  const tag = cipher.getAuthTag();
  const ciphertext = Buffer.concat([ct, tag]);

  // 4. Build encrypted Content-Encoding header block
  // Format: salt(16) || rs(4 BE) || idlen(1) || keyid(idlen bytes) || ciphertext
  const recordSize = 4096; // max
  const idlen = senderPub.length;
  const header = Buffer.alloc(16 + 4 + 1);
  salt.copy(header, 0);
  header.writeUInt32BE(recordSize, 16);
  header.writeUInt8(idlen, 20);
  const body = Buffer.concat([header, senderPub, ciphertext]);
  return body;
}

// ---------- send to single subscription ----------
async function sendOne(sub, payloadStr){
  const url = new URL(sub.endpoint);
  const aud = url.origin;
  const jwt = vapidJwt(aud);
  const body = await encryptPayload(payloadStr, sub.p256dh, sub.auth);

  const r = await fetch(sub.endpoint, {
    method: 'POST',
    headers: {
      'TTL': '86400',
      'Content-Encoding': 'aes128gcm',
      'Content-Type': 'application/octet-stream',
      'Authorization': 'vapid t=' + jwt + ', k=' + VAPID_PUBLIC_KEY,
      'Urgency': 'normal'
    },
    body: body
  });
  return { ok: r.ok, status: r.status, endpoint: sub.endpoint };
}

// ---------- Supabase helper ----------
async function sbFetch(path){
  const r = await fetch(SUPABASE_URL + path, {
    headers: {
      'apikey': SERVICE_KEY,
      'Authorization': 'Bearer ' + SERVICE_KEY,
      'Content-Type': 'application/json'
    }
  });
  if (!r.ok) return null;
  return r.json();
}

async function markFailed(endpoint){
  await fetch(SUPABASE_URL + '/rest/v1/rpc/mark_push_failed', {
    method: 'POST',
    headers: {
      'apikey': SERVICE_KEY,
      'Authorization': 'Bearer ' + SERVICE_KEY,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ p_endpoint: endpoint })
  });
}

export default async function handler(req, res){
  try {
    if (req.method !== 'POST'){ res.status(405).end('POST only'); return; }
    if (!VAPID_PRIVATE_KEY){ res.status(500).json({ error: 'VAPID keys not configured in Vercel env' }); return; }

    // Auth: caller must send their own JWT in Authorization header,
    // then we verify they are admin via SECURITY DEFINER RPC.
    const callerJwt = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    if (!callerJwt){ res.status(401).json({ error: 'auth required' }); return; }

    const adminCheck = await fetch(SUPABASE_URL + '/rest/v1/rpc/is_admin', {
      method: 'POST',
      headers: {
        'apikey': callerJwt,
        'Authorization': 'Bearer ' + callerJwt,
        'Content-Type': 'application/json'
      },
      body: '{}'
    });
    const isAdminBody = await adminCheck.json().catch(() => false);
    if (!isAdminBody){ res.status(403).json({ error: 'admin only' }); return; }

    const b = req.body || {};
    const message = {
      title: String(b.title || 'DukanList').slice(0, 100),
      body:  String(b.body  || '').slice(0, 280),
      url:   String(b.url   || '/').slice(0, 500),
      image: b.image ? String(b.image).slice(0, 500) : undefined,
      tag:   'dukanlist-' + Date.now()
    };
    const audience = b.audience || null;

    // Fetch subscribers via service key
    const subsPath = '/rest/v1/push_subscriptions?failed_count=lt.5'
      + (audience && audience !== 'all' ? '&audience=eq.' + encodeURIComponent(audience) : '')
      + '&select=endpoint,p256dh,auth';
    const subs = await sbFetch(subsPath);
    if (!subs){ res.status(500).json({ error: 'subscribers fetch failed' }); return; }

    const payloadStr = JSON.stringify(message);
    let sent = 0, failed = 0;
    for (const s of subs){
      try {
        const r = await sendOne(s, payloadStr);
        if (r.ok || r.status === 201) sent++;
        else { failed++; if (r.status === 404 || r.status === 410) await markFailed(s.endpoint); }
      } catch (err){ failed++; await markFailed(s.endpoint); }
    }
    res.status(200).json({ ok: true, total: subs.length, sent, failed });
  } catch (err){
    console.error('push-broadcast:', err);
    res.status(500).json({ error: err.message || 'internal error' });
  }
}
