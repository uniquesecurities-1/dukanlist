// =====================================================
// api/sms-hook.js
// Supabase Send SMS Hook → MSG91 Flow API
// =====================================================
// This is called by Supabase when an OTP needs to be sent.
// We forward the OTP to MSG91 which delivers it to the user's mobile.
//
// REQUIRED VERCEL ENV VARS (set in Vercel dashboard → Settings → Env):
//   MSG91_AUTH_KEY      — from MSG91 dashboard → API → Auth Key
//   MSG91_TEMPLATE_ID   — from MSG91 → Templates → your approved template
//   MSG91_FLOW_ID       — same as template_id for Flow API (often identical)
//   SMS_HOOK_SECRET     — random string you also set in Supabase Auth Hook
//   SMS_FALLBACK_LOG    — set to "1" to log OTP in console (testing only)
//
// SUPABASE CONFIG (Authentication → Hooks → Send SMS Hook):
//   URL: https://dukanlist.com/api/sms-hook
//   Secret: same value as SMS_HOOK_SECRET
//   Method: POST
// =====================================================

const MSG91_AUTH_KEY      = process.env.MSG91_AUTH_KEY;
const MSG91_TEMPLATE_ID   = process.env.MSG91_TEMPLATE_ID;
const SMS_HOOK_SECRET     = process.env.SMS_HOOK_SECRET;
const FALLBACK_LOG        = process.env.SMS_FALLBACK_LOG === '1';

function normalizeIndianMobile(phone){
  // Accept "919541223377", "+919541223377", "9541223377"
  // Return "919541223377" (no +, with 91 prefix)
  const digits = String(phone || '').replace(/\D/g, '');
  if (digits.length === 10) return '91' + digits;
  if (digits.length === 12 && digits.startsWith('91')) return digits;
  if (digits.length === 13 && digits.startsWith('091')) return digits.slice(1);
  return digits;
}

export default async function handler(req, res){
  // Only allow POST
  if (req.method !== 'POST'){
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // Verify webhook secret
  const incomingSecret = req.headers['x-supabase-hook-secret']
                      || req.headers['supabase-signature']
                      || req.headers['authorization']?.replace(/^Bearer\s+/i, '');

  if (!SMS_HOOK_SECRET){
    return res.status(500).json({ error: 'SMS_HOOK_SECRET not configured on server' });
  }
  if (incomingSecret !== SMS_HOOK_SECRET){
    return res.status(401).json({ error: 'Invalid webhook secret' });
  }

  // Parse Supabase Hook payload
  // Format: { user: { phone: "..." }, sms: { otp: "...", channel: "sms" } }
  let body = req.body;
  if (typeof body === 'string'){
    try { body = JSON.parse(body); } catch(_) { /* keep as string */ }
  }

  const phone = body?.user?.phone || body?.sms?.phone || body?.phone;
  const otp   = body?.sms?.otp || body?.otp;

  if (!phone || !otp){
    return res.status(400).json({ error: 'Missing phone or otp in payload', received: body });
  }

  const normalizedPhone = normalizeIndianMobile(phone);

  // Sanity: Indian mobile (91XXXXXXXXXX)
  if (!/^91[6-9]\d{9}$/.test(normalizedPhone)){
    return res.status(400).json({ error: 'Invalid Indian mobile', phone: normalizedPhone });
  }

  // Optional: log OTP in dev mode (NEVER enable in production)
  if (FALLBACK_LOG){
    console.log(`[SMS-HOOK] OTP for ${normalizedPhone}: ${otp}`);
  }

  // Send via MSG91 Flow API
  if (!MSG91_AUTH_KEY || !MSG91_TEMPLATE_ID){
    return res.status(500).json({ error: 'MSG91 credentials not configured on server' });
  }

  try {
    const msg91Res = await fetch('https://control.msg91.com/api/v5/flow/', {
      method: 'POST',
      headers: {
        'authkey': MSG91_AUTH_KEY,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: JSON.stringify({
        template_id: MSG91_TEMPLATE_ID,
        short_url: '0',
        recipients: [
          {
            mobiles: normalizedPhone,
            // The variable name 'var' or 'var1' must match what's in your MSG91 template
            var: otp,
          },
        ],
      }),
    });

    const msg91Body = await msg91Res.text();

    if (!msg91Res.ok){
      console.error('MSG91 send failed:', msg91Res.status, msg91Body);
      return res.status(502).json({
        error: 'MSG91 send failed',
        status: msg91Res.status,
        details: msg91Body.slice(0, 500),
      });
    }

    return res.status(200).json({ success: true, provider: 'msg91' });

  } catch (err){
    console.error('SMS hook error:', err);
    return res.status(500).json({ error: 'Internal error', message: err.message });
  }
}
