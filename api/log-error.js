// =====================================================
// api/log-error.js
// Self-hosted client-side error capture endpoint.
//
// Frontend `assets/js/error-reporter.js` POSTs error events here.
// We hash the requestor's IP (no PII), forward to Supabase via the
// log_client_error RPC, and return 204 (no content) regardless of
// outcome so the client never blocks on this.
//
// Rate limiting + de-dup is handled INSIDE the RPC (see db/97).
//
// SECURITY:
//   - Accepts POST only
//   - Size-capped body (max 8 KB) prevents abuse
//   - IP hashed with daily salt — cannot be reversed
//   - Optional user JWT decoded for user_id (no enforcement)
//   - No service_role key used; anon key is enough since the RPC
//     is SECURITY DEFINER and idempotent
// =====================================================

const crypto = require('crypto');

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://qazuyygrpqopwygxmvwq.supabase.co';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFhenV5eWdycHFvcHd5Z3htdndxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxNTUwOTEsImV4cCI6MjA5NDczMTA5MX0.FR8x2kldC2yelpPnK2QKd5WGwHUAQheCVmxfs6hR00I';

const MAX_BODY_BYTES = 8 * 1024;  // 8 KB
const IP_SALT = process.env.LOG_IP_SALT || 'dukanlist-rotating-ip-salt-2026';

function hashIp(ip) {
  if (!ip) return 'unknown';
  // Day-rotated salt: any given user's hash changes after 24h
  const day = new Date().toISOString().slice(0, 10);
  return crypto.createHash('sha256')
    .update(IP_SALT + ':' + day + ':' + ip)
    .digest('hex')
    .slice(0, 32);
}

function getIp(req) {
  return (
    (req.headers['x-forwarded-for'] || '').split(',')[0].trim() ||
    req.headers['x-real-ip'] ||
    req.socket?.remoteAddress ||
    ''
  );
}

// Decode JWT payload (no signature verification — RPC will validate)
function decodeJwtPayload(authHeader) {
  if (!authHeader || !authHeader.startsWith('Bearer ')) return null;
  try {
    const parts = authHeader.slice(7).split('.');
    if (parts.length !== 3) return null;
    const json = Buffer.from(parts[1].replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8');
    return JSON.parse(json);
  } catch (e) {
    return null;
  }
}

module.exports = async (req, res) => {
  // Always return 204 — never block the client even on internal errors
  const respondNoContent = () => {
    res.statusCode = 204;
    res.setHeader('Cache-Control', 'no-store');
    res.end();
  };

  try {
    if (req.method !== 'POST') {
      res.statusCode = 405;
      return res.end('Method not allowed');
    }

    // Read body with size limit
    const chunks = [];
    let totalBytes = 0;
    for await (const chunk of req) {
      totalBytes += chunk.length;
      if (totalBytes > MAX_BODY_BYTES) {
        res.statusCode = 413;
        return res.end('Payload too large');
      }
      chunks.push(chunk);
    }
    const rawBody = Buffer.concat(chunks).toString('utf8');
    let body;
    try {
      body = rawBody ? JSON.parse(rawBody) : {};
    } catch (e) {
      // Bad JSON — swallow silently (client may have sent garbage)
      return respondNoContent();
    }

    if (!body || typeof body !== 'object') {
      return respondNoContent();
    }

    // Build payload for the RPC
    const ip = getIp(req);
    const ipHash = hashIp(ip);
    const authPayload = decodeJwtPayload(req.headers['authorization']);
    const userId = authPayload?.sub || null;

    const payload = {
      source:      body.source || 'js',
      severity:    body.severity || 'error',
      error_msg:   String(body.error_msg || body.message || 'unknown').slice(0, 1000),
      error_stack: String(body.error_stack || body.stack || '').slice(0, 4000),
      page_url:    String(body.page_url || body.url || '').slice(0, 500),
      user_agent:  String(req.headers['user-agent'] || '').slice(0, 500),
      ip_hash:     ipHash,
      session_id:  String(body.session_id || '').slice(0, 64),
      user_id:     userId,
      // Stash a few extra fields under meta for forensics
      meta:        {
        line:     body.line,
        col:      body.col,
        ts:       new Date().toISOString(),
        referrer: String(body.referrer || '').slice(0, 200)
      }
    };

    // Fire and forget — call the RPC, don't await response
    fetch(SUPABASE_URL + '/rest/v1/rpc/log_client_error', {
      method: 'POST',
      headers: {
        'apikey':        SUPABASE_ANON_KEY,
        'Authorization': 'Bearer ' + SUPABASE_ANON_KEY,
        'Content-Type':  'application/json',
        'Prefer':        'return=minimal'
      },
      body: JSON.stringify({ p_data: payload })
    }).catch(() => { /* silent — error endpoint must never throw */ });

  } catch (_) {
    // Swallow everything — endpoint must be a no-op fail
  }

  return respondNoContent();
};
