// =====================================================
// api/claim-via-link.js — DEPRECATED (db/163 supersedes)
// =====================================================
// Previously: synthetic-email magic link flow. Replaced by Option B
// in db/163 — claim.html now does Supabase signUp directly with a
// REAL email + password, which aligns with the existing
// email-mandatory + user-verify setup (db/80, db/93).
//
// This endpoint is kept as a stub that returns a clear deprecation
// notice in case any old WhatsApp claim links still POST to it.
// Will be removed in a future cleanup pass.
// =====================================================
module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  res.status(410).json({
    error: 'This endpoint has been retired',
    message: 'Use the new claim flow at /claim.html?token=YOUR_TOKEN — Supabase email signup is now done client-side.',
    deprecated_at: '2026-06-22',
    new_flow: 'db/163 Option B (email + password at claim time)'
  });
};

// =====================================================
// v227 SECURITY FIX
// -----------------------------------------------------
// Everything below this point used to be a SECOND
//     module.exports = async (req, res) => { ... }
// which silently REPLACED the 410 stub above. The comment
// claiming it was "never reached" was wrong — it was the
// live handler.
//
// That handler accepted an UNAUTHENTICATED POST, created a
// confirmed auth user with the service-role key, minted a
// magic link, and RETURNED IT IN THE RESPONSE BODY. Anyone
// who saw a claim token (forwarded WhatsApp message, browser
// history, shoulder-surf) could take over that listing's
// account with a single curl.
//
// The whole block has been deleted. The retired-endpoint
// stub above is now the only export, as always intended.
// Git history has the original if it is ever needed.
// =====================================================

