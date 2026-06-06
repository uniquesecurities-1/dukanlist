/* ============================================================
   OTP — Supabase Phone Auth wrapper
   Sends SMS OTP via Supabase Auth (provider must be enabled
   in Supabase dashboard → Authentication → Providers → Phone)
   ============================================================ */
(function(global){
  'use strict';

  function cleanMobile(m){
    if (!m) return '';
    m = String(m).replace(/[^\d+]/g,'');
    // Ensure +91 country code for India
    if (m.length === 10) m = '+91' + m;
    else if (m.length === 12 && m.startsWith('91')) m = '+' + m;
    else if (m.length === 13 && m.startsWith('+91')) { /* ok */ }
    else if (!m.startsWith('+')) m = '+91' + m;
    return m;
  }

  function isValidIndianMobile(m){
    const cleaned = cleanMobile(m);
    return /^\+91[6-9]\d{9}$/.test(cleaned);
  }

  // Send OTP — returns { ok, error }
  async function sendOTP(mobile){
    const c = ShopDB.client;
    if (!c) return { ok:false, error:'Supabase not configured' };
    const phone = cleanMobile(mobile);
    if (!isValidIndianMobile(phone)) {
      return { ok:false, error:'Please enter a valid 10-digit Indian mobile' };
    }
    const { data, error } = await c.auth.signInWithOtp({
      phone,
      options: { channel: 'sms' }   // change to 'whatsapp' if you enable WA provider
    });
    if (error) return { ok:false, error: error.message };
    return { ok:true };
  }

  // Verify OTP — returns { ok, user, error }
  async function verifyOTP(mobile, token){
    const c = ShopDB.client;
    if (!c) return { ok:false, error:'Supabase not configured' };
    const phone = cleanMobile(mobile);
    const { data, error } = await c.auth.verifyOtp({
      phone, token, type: 'sms'
    });
    if (error) return { ok:false, error: error.message };
    return { ok:true, user: data?.user || null, session: data?.session || null };
  }

  global.OTP = { sendOTP, verifyOTP, cleanMobile, isValidIndianMobile };

})(window);
