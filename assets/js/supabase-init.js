/* ============================================================
   dukanlist.com — Supabase Client (single source of truth)
   ------------------------------------------------------------
   Project: mfdtools-shop (Shop Directory org)
   Dashboard: https://supabase.com/dashboard/project/qazuyygrpqopwygxmvwq
   ============================================================ */
(function(global){
  'use strict';

  // === LIVE SUPABASE PROJECT (mfdtools-shop) ===
  const SUPABASE_URL      = 'https://qazuyygrpqopwygxmvwq.supabase.co';
  const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFhenV5eWdycHFvcHd5Z3htdndxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxNTUwOTEsImV4cCI6MjA5NDczMTA5MX0.FR8x2kldC2yelpPnK2QKd5WGwHUAQheCVmxfs6hR00I';

  // Lazy-load the Supabase JS client from CDN
  let _client = null;
  function getClient(){
    if (_client) return _client;
    if (typeof supabase === 'undefined') {
      console.error('[supabase-init] Supabase JS library not loaded. Include https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2 before this script.');
      return null;
    }
    if (SUPABASE_URL.startsWith('REPLACE_')) {
      console.warn('[supabase-init] Supabase URL not configured. Edit /assets/js/supabase-init.js');
      return null;
    }
    _client = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        storageKey: 'dukanlist_auth',
        flowType: 'pkce'
      }
    });
    return _client;
  }

  // ============================================================
  // Session helpers
  // ============================================================
  async function getUser(){
    const c = getClient(); if (!c) return null;
    const { data } = await c.auth.getUser();
    return data?.user || null;
  }

  async function signOut(){
    const c = getClient(); if (!c) return;
    await c.auth.signOut();
    location.href = '/';
  }

  async function requireAuth(redirectTo='/panel/login.html'){
    const u = await getUser();
    if (!u) { location.href = redirectTo + '?next=' + encodeURIComponent(location.pathname); return null; }
    return u;
  }

  // ============================================================
  // Public API
  // ============================================================
  global.ShopDB = {
    get client(){ return getClient(); },
    getUser, signOut, requireAuth,
    URL: SUPABASE_URL
  };

})(window);
