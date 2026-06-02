/* ============================================================
   email-verify-banner.js — Email verification reminder
   ============================================================
   Triggers when the logged-in user has email_confirmed_at = null.
   This typically happens when:
     • A new shopkeeper signs up but never clicks the email link.
     • Admin updates the email (new email needs re-verification).
     • Account was created with email_confirm:false in some flow.

   Renders a sticky YELLOW banner at the top of the page with:
     • "Please verify your email" text
     • Resend Verification Link button
     • "Already verified? Refresh" link

   Auto-hides once the user verifies (email_confirmed_at set).
   Only shows on /panel/* pages — skip on public pages and admin.
============================================================ */
(function(){
  'use strict';

  // Run only on panel pages where a shopkeeper is logged in
  if (!/\/panel\//i.test(window.location.pathname)) return;

  // Wait for ShopDB to be ready (loaded by supabase-init.js)
  function whenReady(cb){
    if (window.ShopDB && window.ShopDB.client) return cb(window.ShopDB.client);
    setTimeout(function(){ whenReady(cb); }, 200);
  }

  whenReady(function(c){
    c.auth.getUser().then(function(res){
      var user = res && res.data && res.data.user;
      if (!user) return;
      if (user.email_confirmed_at) return; // already verified
      // Don't show on the verification page itself (avoids redundant CTA)
      if (/resend-verification/i.test(window.location.pathname)) return;

      injectBanner(user.email || '');
    }).catch(function(){ /* ignore */ });
  });

  function injectBanner(email){
    if (document.getElementById('dukanVerifyBanner')) return;
    var bar = document.createElement('div');
    bar.id = 'dukanVerifyBanner';
    bar.style.cssText = [
      'position:sticky',
      'top:0',
      'z-index:9998',
      'background:linear-gradient(135deg,#FEF3C7,#FDE68A)',
      'border-bottom:2px solid #F59E0B',
      'box-shadow:0 2px 8px rgba(245,158,11,0.18)',
      'padding:10px 16px',
      'font-family:Manrope,Inter,-apple-system,sans-serif',
      'font-size:.86rem',
      'color:#7C2D12',
      'display:flex',
      'align-items:center',
      'justify-content:center',
      'gap:14px',
      'flex-wrap:wrap',
      'line-height:1.4'
    ].join(';');

    var safeEmail = (email || '').replace(/[<>"']/g, '');
    var resentMsgId = 'dukanVerifyResentMsg';

    bar.innerHTML = ''
      + '<div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap">'
      +   '<span style="font-size:1.2rem">⚠️</span>'
      +   '<span><b>Please verify your email</b>'
      +     (safeEmail ? ' <span style="color:#92400E;font-weight:600">(' + safeEmail + ')</span>' : '')
      +     ' to unlock all features and get listed publicly.</span>'
      + '</div>'
      + '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">'
      +   '<button id="dukanVerifyResend" type="button" style="background:#D97706;color:#fff;border:none;padding:7px 14px;border-radius:8px;font-weight:800;cursor:pointer;font-family:inherit;font-size:.82rem">📧 Resend Email</button>'
      +   '<a href="#" onclick="window.location.reload();return false" style="color:#7C2D12;font-weight:700;text-decoration:underline;font-size:.78rem">Already verified? Refresh</a>'
      +   '<span id="' + resentMsgId + '" style="display:none;color:#15803D;font-weight:700;font-size:.78rem"></span>'
      + '</div>';

    // Insert at top of body, before any other content
    if (document.body.firstChild) {
      document.body.insertBefore(bar, document.body.firstChild);
    } else {
      document.body.appendChild(bar);
    }

    // Wire up Resend button
    var btn = document.getElementById('dukanVerifyResend');
    var msg = document.getElementById(resentMsgId);
    if (btn){
      btn.addEventListener('click', function(){
        btn.disabled = true;
        btn.textContent = 'Sending…';
        var c = window.ShopDB && window.ShopDB.client;
        if (!c){ btn.textContent = '📧 Resend Email'; btn.disabled = false; return; }

        // Use Supabase Auth resend API. type:'signup' resends the original confirmation.
        c.auth.resend({ type: 'signup', email: email }).then(function(r){
          if (r && r.error){
            btn.textContent = '⚠️ Failed — try again';
            btn.disabled = false;
            if (msg){
              msg.style.display = 'inline';
              msg.style.color = '#991B1B';
              msg.textContent = '⚠️ ' + (r.error.message || 'Could not send. Try again later.');
            }
            return;
          }
          btn.textContent = '✓ Sent — check inbox';
          btn.style.background = '#15803D';
          if (msg){
            msg.style.display = 'inline';
            msg.textContent = 'Check inbox/spam in 1-2 min';
          }
          // Re-enable after 60 seconds so they can try again if needed
          setTimeout(function(){
            btn.disabled = false;
            btn.textContent = '📧 Resend Email';
            btn.style.background = '#D97706';
          }, 60000);
        }).catch(function(e){
          btn.textContent = '⚠️ Network error — retry';
          btn.disabled = false;
          if (msg){
            msg.style.display = 'inline';
            msg.style.color = '#991B1B';
            msg.textContent = 'Network error. Check internet and try again.';
          }
        });
      });
    }
  }
})();
