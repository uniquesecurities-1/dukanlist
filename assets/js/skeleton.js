/* ============================================================
   skeleton.js — Unified loading skeleton component
   ============================================================
   Generates consistent shimmer placeholders across pages.
   Pairs with .skeleton / .sk-* classes in /assets/css/main.css.

   USAGE:
     const html = DukanSkeleton.cards(8);
     document.getElementById('results').innerHTML = html;

     // or directly inject:
     DukanSkeleton.show('results', 'cards', 8);
============================================================ */
(function(global){
  'use strict';

  // ---------- Building blocks ----------
  function _card(){
    return '<div class="sk-card">'
      + '<div class="skeleton sk-square"></div>'
      + '<div class="skeleton sk-line sm w-50" style="margin-top:10px"></div>'
      + '<div class="skeleton sk-line lg w-70"></div>'
      + '<div class="skeleton sk-line w-90"></div>'
      + '<div class="skeleton sk-line w-50"></div>'
      + '</div>';
  }

  function _row(){
    return '<div style="display:flex;gap:12px;padding:12px;border:1px solid #e2e8f0;border-radius:12px;background:#fff;margin-bottom:10px">'
      + '<span class="skeleton" style="width:64px;height:64px;border-radius:10px;flex-shrink:0"></span>'
      + '<div style="flex:1;min-width:0">'
      +   '<div class="skeleton sk-line sm w-30"></div>'
      +   '<div class="skeleton sk-line lg w-70"></div>'
      +   '<div class="skeleton sk-line w-90"></div>'
      + '</div>'
      + '</div>';
  }

  function _line(width){
    width = width || 90;
    return '<div class="skeleton sk-line w-' + width + '"></div>';
  }

  function _avatar(){
    return '<span class="skeleton sk-circle"></span>';
  }

  function _pill(width){
    width = width || 80;
    return '<span class="skeleton" style="display:inline-block;width:' + width + 'px;height:26px;border-radius:99px;margin:0 6px 6px 0;vertical-align:middle"></span>';
  }

  // ---------- Public API ----------
  // n cards inside a .biz-grid
  function cards(n){
    n = Math.max(1, Number(n) || 6);
    let html = '<div class="biz-grid">';
    for (let i = 0; i < n; i++) html += _card();
    html += '</div>';
    return html;
  }

  // Plain card list (no grid wrapper) — for cases where caller has own layout
  function cardsRaw(n){
    n = Math.max(1, Number(n) || 6);
    let html = '';
    for (let i = 0; i < n; i++) html += _card();
    return html;
  }

  // n list-style rows (e.g., for reviews, leads, deals)
  function rows(n){
    n = Math.max(1, Number(n) || 5);
    let html = '';
    for (let i = 0; i < n; i++) html += _row();
    return html;
  }

  // Generic text block: { lines: 3, withTitle: true }
  function text(opts){
    opts = opts || {};
    const lines = Math.max(1, Number(opts.lines) || 3);
    let html = '';
    if (opts.withTitle){
      html += '<div class="skeleton sk-line lg w-50"></div>';
    }
    for (let i = 0; i < lines; i++){
      const w = [90, 70, 90, 50][i % 4];
      html += _line(w);
    }
    return html;
  }

  // Horizontal strip of pills (chips/tabs loading)
  function pills(n){
    n = Math.max(1, Number(n) || 5);
    let html = '<div style="display:flex;flex-wrap:wrap;gap:6px">';
    for (let i = 0; i < n; i++) html += _pill(60 + (i * 12) % 80);
    html += '</div>';
    return html;
  }

  // KPI block (e.g., analytics dashboard)
  function kpi(n){
    n = Math.max(1, Number(n) || 4);
    let html = '<div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:12px">';
    for (let i = 0; i < n; i++){
      html += '<div style="background:#fff;border:1px solid #e2e8f0;border-radius:12px;padding:16px">'
        + '<div class="skeleton sk-line sm w-50"></div>'
        + '<div class="skeleton sk-line lg w-70" style="height:28px;margin-top:6px"></div>'
        + '<div class="skeleton sk-line w-50"></div>'
        + '</div>';
    }
    html += '</div>';
    return html;
  }

  // Centered "Loading..." block with skeleton lines (use for hero/empty zones)
  function block(opts){
    opts = opts || {};
    return '<div style="padding:30px;background:#fff;border:1px solid #e2e8f0;border-radius:14px">'
      + text({ lines: opts.lines || 4, withTitle: true })
      + '</div>';
  }

  // Shortcut: render into an element by id
  function show(elementId, type, n, opts){
    const el = document.getElementById(elementId);
    if (!el) return;
    let html = '';
    switch (type){
      case 'cards':    html = cards(n); break;
      case 'cardsRaw': html = cardsRaw(n); break;
      case 'rows':     html = rows(n); break;
      case 'text':     html = text(opts || { lines: n }); break;
      case 'pills':    html = pills(n); break;
      case 'kpi':      html = kpi(n); break;
      case 'block':    html = block(opts); break;
      default:         html = cards(n);
    }
    el.innerHTML = html;
  }

  global.DukanSkeleton = {
    cards, cardsRaw, rows, text, pills, kpi, block, show,
    // expose primitives in case a page wants custom composition
    _card, _row, _line, _avatar, _pill
  };
})(window);
