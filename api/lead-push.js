// =====================================================
// api/lead-push.js
// Fire a Web Push to shop owner(s) when a lead happens
// =====================================================
// Triggered from public business.html after a Call/WhatsApp click.
// No caller auth (page is public), but:
//   - Action must be 'call' or 'whatsapp'
//   - Rate-limited via recent_lead_count() RPC (max 3 pushes per
//     IP+business in last 1 minute) — prevents spam
//   - Body is small + server-constructed, no caller-controlled payload
//
// Required Vercel env vars (same as push-broadcast):
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// Request body (POST):
//   { business_id: 'uuid', action: 'call'|'whatsapp', shop_name?: 'string' }
// =====================================================

import crypto from 'crypto';

const VAPID_PUBLIC_KEY  = process.env.VAPID_PUBLIC_KEY  || '';
const VAPID_PRIVATE_KEY = process.env.VAPID_PRIVATE_KEY || '';
const VAPID_SUBJECT     = process.env.VAPID_SUBJECT     || 'mailto:admin@dukanlist.com';
const SUPABASE_URL      = process.env.SUPABASE_URL      || 'https://qazuyygrpqopwygxmvwq.supabase.co';
const SERVICE_KEY       = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

// ---------- base64url helpers ----------
function b64urlEncode(buf){ return Buffer.from(buf).toString('base64url'); }
function b64urlDecode(s){ return Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64'); }

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
  const d = b64urlDecode(VAPID_PRIVATE_KEY);
  const pub = b64urlDecode(VAPID_PUBLIC_KEY);
  const jwk = {
    kty: 'EC', crv: 'P-256',
    d: b64urlEncode(d),
    x: b64urlEncode(pub.slice(1, 33)),
    y: b64urlEncode(pub.slice(33, 65))
  };
  const keyObj = crypto.createPrivateKey({ key: jwk, format: 'jwk' });
  const sigDer = crypto.sign('SHA256', Buffer.from(signingInput), keyObj);
  const sigRaw = derToJose(sigDer, 32);
  return signingInput + '.' + b64urlEncode(sigRaw);
}

function derToJose(der, keyLen){
  let offset = 2;
  if (der[1] & 0x80) offset += der[1] & 0x7f;
  if (der[offset++] !== 0x02) throw new Error('bad DER sig');
  const rLen = der[offset++]; const r = der.slice(offset, offset + rLen); offset += rLen;
  if (der[offset++] !== 0x02) throw new Error('bad DER sig');
  const sLen = der[offset++]; const s = der.slice(offset, offset + sLen);
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

// ---------- AES-128-GCM payload encryption (RFC 8291) ----------
async function encryptPayload(plaintext, recipientP256dh, recipientAuth){
  const ec = crypto.createECDH('prime256v1');
  ec.generateKeys();
  const senderPub  = ec.getPublicKey();
  const recipPub   = b64urlDecode(recipientP256dh);
  const sharedSecret = ec.computeSecret(recipPub);
  const salt = crypto.randomBytes(16);
  const auth = b64urlDecode(recipientAuth);
  const keyInfo = Buffer.concat([Buffer.from('WebPush: info\0', 'utf8'), recipPub, senderPub]);
  const prkKey = crypto.createHmac('sha256', auth).update(sharedSecret).digest();
  const ikm    = crypto.createHmac('sha256', prkKey).update(Buffer.concat([keyInfo, Buffer.from([0x01])])).digest();
  const prk = crypto.createHmac('sha256', salt).update(ikm).digest();
  const cek = crypto.createHmac('sha256', prk).update(Buffer.concat([Buffer.from('Content-Encoding: aes128gcm\0', 'utf8'), Buffer.from([0x01])])).digest().slice(0, 16);
  const nonce = crypto.createHmac('sha256', prk).update(Buffer.concat([Buffer.from('Content-Encoding: nonce\0', 'utf8'), Buffer.from([0x01])])).digest().slice(0, 12);
  const padded = Buffer.concat([Buffer.from(plaintext, 'utf8'), Buffer.from([0x02])]);
  const cipher = crypto.createCipheriv('aes-128-gcm', cek, nonce);
  const ct = Buffer.concat([cipher.update(padded), cipher.final()]);
  const tag = cipher.getAuthTag();
  const ciphertext = Buffer.concat([ct, tag]);
  const recordSize = 4096;
  const idlen = senderPub.length;
  const header = Buffer.alloc(16 + 4 + 1);
  salt.copy(header, 0);
  header.writeUInt32BE(recordSize, 16);
  header.writeUInt8(idlen, 20);
  return Buffer.concat([header, senderPub, ciphertext]);
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
      'Urgency': 'high'
    },
    body: body
  });
  return { ok: r.ok, status: r.status, endpoint: sub.endpoint };
}

// ---------- Supabase helpers ----------
async function sbRpc(name, args){
  const r = await fetch(SUPABASE_URL + '/rest/v1/rpc/' + name, {
    method: 'POST',
    headers: {
      'apikey': SERVICE_KEY,
      'Authorization': 'Bearer ' + SERVICE_KEY,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(args || {})
  });
  if (!r.ok) return null;
  return r.json();
}

// Hash an IP same way leads_log expects (for rate limit lookup)
function ipHash(ip){
  if (!ip) return null;
  const today = new Date().toISOString().slice(0, 10);
  return crypto.createHash('sha256').update(ip + ':' + today).digest('hex').slice(0, 32);
}

export default async function handler(req, res){
  // CORS — allow same-origin only
  res.setHeader('Cache-Control', 'no-store');

  if (req.method !== 'POST'){ res.status(405).json({ error: 'POST only' }); return; }
  if (!VAPID_PRIVATE_KEY || !SERVICE_KEY){
    res.status(500).json({ error: 'Server not configured' });
    return;
  }

  const b = req.body || {};
  const business_id = String(b.business_id || '').trim();
  const action      = String(b.action || '').trim();
  const shop_name   = String(b.shop_name || 'A customer').slice(0, 60);

  if (!business_id || !/^[0-9a-f-]{36}$/i.test(business_id)){
    res.status(400).json({ error: 'invalid business_id' });
    return;
  }
  const ALLOWED_ACTIONS = ['call','whatsapp','favorite','review','view_burst'];
  if (!ALLOWED_ACTIONS.includes(action)){
    res.status(400).json({ error: 'invalid action — allowed: ' + ALLOWED_ACTIONS.join(',') });
    return;
  }

  // Rate limit: max 3 leads from this IP for this business in last minute
  const fwd = req.headers['x-forwarded-for'] || req.socket?.remoteAddress || '';
  const ip  = String(fwd).split(',')[0].trim();
  const ipH = ipHash(ip);
  if (ipH){
    try {
      const count = await sbRpc('recent_lead_count', {
        p_business_id: business_id,
        p_ip_hash: ipH,
        p_window: '1 minute'
      });
      if (typeof count === 'number' && count > 3){
        return res.status(429).json({ error: 'Rate limited' });
      }
    } catch(_){}
  }

  // Call notify_owner_event RPC — checks throttle + returns subs in one call
  let notifyResult;
  try {
    notifyResult = await sbRpc('notify_owner_event', {
      p_business_id: business_id,
      p_event_type:  action
    });
  } catch(e){
    return res.status(500).json({ error: 'notify rpc failed', detail: String(e) });
  }

  if (!notifyResult || notifyResult.allowed === false){
    return res.status(200).json({
      sent: 0, total: 0,
      throttled: true,
      reason: notifyResult?.reason || 'unknown',
      cooldown_minutes_remaining: notifyResult?.cooldown_minutes_remaining
    });
  }

  const subs = Array.isArray(notifyResult.subscriptions) ? notifyResult.subscriptions : [];
  if (!subs.length){
    return res.status(200).json({ sent: 0, total: 0, note: 'no owner subscribed' });
  }

  // Use shop_name from server (RPC-provided) instead of caller-controlled
  const liveShopName = notifyResult.shop_name || shop_name;
  const shopSlug     = notifyResult.shop_slug || '';

  // Per-event title and body
  const messages = {
    'call':       { title: '\u{1F4DE} Call interest received',
                    body:  'Someone tapped your phone number on ' + liveShopName + '. Open dashboard.' },
    'whatsapp':   { title: '\u{1F4AC} WhatsApp interest received',
                    body:  'Someone tapped WhatsApp on ' + liveShopName + '. Open dashboard.' },
    'favorite':   { title: '\u{2764}\uFE0F New favorite',
                    body:  'A customer saved ' + liveShopName + ' to favorites.' },
    'review':     { title: '\u{2B50} New review received',
                    body:  'New review posted for ' + liveShopName + '. Open and reply.' },
    'view_burst': { title: '\u{1F525} Activity surge',
                    body:  liveShopName + ' is getting noticed. Multiple views in the last 30 minutes.' }
  };
  const m = messages[action] || messages.call;
  const message = {
    title: m.title,
    body:  m.body,
    url:   '/panel/dashboard.html',
    tag:   action + '-' + business_id.slice(0, 8),
    requireInteraction: false
  };
  const payloadStr = JSON.stringify(message);

  // Send to each owner subscription
  let sent = 0, failed = 0;
  for (const s of subs){
    try {
      const r = await sendOne(s, payloadStr);
      if (r.ok || r.status === 201) sent++;
      else failed++;
    } catch(_){ failed++; }
  }
  return res.status(200).json({ sent, failed, total: subs.length });
}
