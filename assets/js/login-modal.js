/* ============================================================
   login-modal.js — In-place login (no full-page redirect)
   ============================================================
   USAGE:
     // Show modal; resolves with { user } when logged in, or null if cancelled
     const result = await DukanLoginModal.open({
       reason: 'Save shops by creating a free account.',  // optional message
       title:  'Login to continue'                        // optional title
     });
     if (result && result.user){
       // user is now logged in; retry your action
     }

   Built on Supabase auth.signInWithPassword. Includes:
     - Email + password fields with show-toggle
     - 'Forgot password?' link → opens password reset flow
     - 'Register a new account' link → /panel/login.html?mode=signup
     - Friendly error messages
============================================================ */
(function(global){
  'use strict';

  let _resolve = null;

  function open(opts){
    opts = opts || {};
    return new Promise((resolve) => {
      _resolve = resolve;
      build(opts);
    });
  }

  function build(opts){
    let bg = document.getElementById('dukanLoginModal');
    if (bg) bg.remove();

    const reason = opts.reason || '';
    const title  = opts.title  || 'Login to DukanList';

    bg = document.createElement('div');
    bg.id = 'dukanLoginModal';
    bg.style.cssText = 'position:fixed;inset:0;background:rgba(15,23,42,.55);display:flex;align-items:center;justify-content:center;z-index:99999;padding:18px;font-family:\'Plus Jakarta Sans\',\'Manrope\',-apple-system,sans-serif;animation:dlmFade .2s ease';

    bg.innerHTML = '<style>'
      + '@keyframes dlmFade{from{opacity:0}to{opacity:1}}'
      + '@keyframes dlmSlide{from{transform:translateY(24px);opacity:0}to{transform:translateY(0);opacity:1}}'
      + '.dlm-field{display:flex;flex-direction:column;gap:5px;margin-bottom:12px}'
      + '.dlm-field label{font-size:11px;font-weight:800;color:#475569;text-transform:uppercase;letter-spacing:.05em}'
      + '.dlm-field input{padding:11px 13px;border:1.5px solid #cbd5e1;border-radius:10px;font-size:15px;font-family:inherit;color:#0F172A;background:#fff;width:100%}'
      + '.dlm-field input:focus{outline:0;border-color:#FF6B1A;box-shadow:0 0 0 3px rgba(255,107,26,.12)}'
      + '.dlm-err{background:#FEF2F2;border:1px solid #FECACA;color:#991B1B;padding:10px 14px;border-radius:9px;font-size:13px;font-weight:600;margin-bottom:12px;display:none}'
      + '.dlm-ok{background:#D1FAE5;border:1px solid #6EE7B7;color:#065F46;padding:10px 14px;border-radius:9px;font-size:13px;font-weight:600;margin-bottom:12px;display:none}'
      + '</style>'
      + '<div style="background:#fff;border-radius:18px;max-width:420px;width:100%;padding:24px 22px;box-shadow:0 24px 60px rgba(0,0,0,.25);animation:dlmSlide .25s cubic-bezier(.22,.61,.36,1);max-height:90vh;overflow-y:auto">'
        + '<div style="display:flex;justify-content:space-between;align-items:flex-start;gap:10px;margin-bottom:14px">'
          + '<div>'
            + '<div style="display:inline-flex;align-items:center;gap:8px;margin-bottom:6px;font-weight:800;font-size:1.05rem"><span style="font-size:24px">🏪</span><span>DukanList</span></div>'
            + '<h3 style="font-size:18px;font-weight:800;color:#0F172A;letter-spacing:-.01em;margin:0">' + esc(title) + '</h3>'
            + (reason ? '<p style="font-size:13px;color:#64748b;margin-top:6px;line-height:1.5">' + esc(reason) + '</p>' : '')
          + '</div>'
          + '<button onclick="DukanLoginModal._cancel()" style="background:#F1F5F9;border:0;width:32px;height:32px;border-radius:50%;font-size:18px;font-weight:700;color:#475569;cursor:pointer;flex-shrink:0;line-height:1">×</button>'
        + '</div>'
        + '<div id="dlmErr" class="dlm-err"></div>'
        + '<div id="dlmOk"  class="dlm-ok"></div>'
        + '<form id="dlmForm" onsubmit="return DukanLoginModal._submit(event)">'
          + '<div class="dlm-field"><label>Email</label><input id="dlmEmail" type="email" autocomplete="email" required placeholder="you@example.com"></div>'
          + '<div class="dlm-field"><label>Password</label>'
            + '<div style="display:flex;gap:6px">'
              + '<input id="dlmPwd" type="password" autocomplete="current-password" required placeholder="••••••••" style="flex:1">'
              + '<button type="button" onclick="DukanLoginModal._togglePwd()" style="background:#F1F5F9;border:0;border-radius:10px;padding:0 14px;cursor:pointer;font-size:16px">👁</button>'
            + '</div>'
          + '</div>'
          + '<button type="submit" id="dlmSubmit" style="width:100%;background:linear-gradient(135deg,#FF6B1A,#E55100);color:#fff;border:0;padding:13px;border-radius:11px;font-weight:800;font-size:15px;cursor:pointer;box-shadow:0 4px 14px rgba(255,107,26,.35);margin-top:4px">Login →</button>'
        + '</form>'
        + '<div style="margin-top:14px;display:flex;justify-content:space-between;font-size:13px">'
          + '<a href="/panel/forgot-password.html" style="color:#FF6B1A;font-weight:700;text-decoration:none">Forgot password?</a>'
          + '<a href="/register.html" style="color:#0F172A;font-weight:700;text-decoration:none">Register shop →</a>'
        + '</div>'
      + '</div>';

    bg.addEventListener('click', function(e){ if (e.target === bg) cancel(); });
    document.body.appendChild(bg);
    setTimeout(() => document.getElementById('dlmEmail')?.focus(), 80);
  }

  function _togglePwd(){
    const i = document.getElementById('dlmPwd');
    if (i) i.type = i.type === 'password' ? 'text' : 'password';
  }

  async function _submit(ev){
    ev.preventDefault();
    const err = document.getElementById('dlmErr');
    const ok  = document.getElementById('dlmOk');
    const btn = document.getElementById('dlmSubmit');
    err.style.display = 'none'; ok.style.display = 'none';
    const email = document.getElementById('dlmEmail').value.trim();
    const pwd   = document.getElementById('dlmPwd').value;
    if (!email || !pwd){ err.textContent = 'Enter email and password.'; err.style.display = 'block'; return false; }

    btn.disabled = true; btn.innerHTML = '⏳ Logging in…';
    const c = window.ShopDB && ShopDB.client;
    if (!c){ err.textContent = 'Backend not configured.'; err.style.display = 'block'; btn.disabled = false; btn.innerHTML = 'Login →'; return false; }

    const res = await c.auth.signInWithPassword({ email, password: pwd });
    if (res.error){
      let msg = res.error.message || 'Login failed';
      if (/invalid login credentials/i.test(msg)) msg = 'Wrong email or password.';
      if (/email not confirmed/i.test(msg))      msg = '📧 Please confirm your email first. Check inbox AND spam folder for noreply@dukanlist.com.';
      err.textContent = msg; err.style.display = 'block';
      btn.disabled = false; btn.innerHTML = 'Login →';
      return false;
    }

    ok.textContent = '✓ Logged in successfully';
    ok.style.display = 'block';
    btn.innerHTML = '✓ Success';
    setTimeout(() => {
      close();
      if (typeof _resolve === 'function') _resolve({ user: res.data.user });
      _resolve = null;
    }, 600);
    return false;
  }

  function _cancel(){ cancel(); }
  function cancel(){
    close();
    if (typeof _resolve === 'function') _resolve(null);
    _resolve = null;
  }

  function close(){
    const bg = document.getElementById('dukanLoginModal');
    if (bg) bg.remove();
  }

  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]); }

  global.DukanLoginModal = { open, close, _submit, _togglePwd, _cancel };
})(window);
