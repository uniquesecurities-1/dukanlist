/* ============================================================
   dl-shown.js — one list of "already on this screen"
   ============================================================
   v282. The homepage has five places that show shops: the hero
   "Top rated" strip, Featured Listings, Trending This Week, Top 5 of
   the Month and Spotlight of the Week. Measured on the live page on
   2026-09-22: 43 card slots holding only 31 different shops — eleven
   shops twice, Unique Securities three times — while 217 listings
   never appeared at all.

   The rankings must stay honest: if a shop really is #1 this month it
   belongs in Top 5 even though the hero strip already named it. So
   the rankings CLAIM the shops they show, and the one section that is
   a feed rather than a ranking — Featured Listings — fills its slots
   from shops nobody has claimed. Paid/featured shops are never
   dropped; only the "newest" and "random fill" padding behind them.

     DLShown.claim(['slug-a', 'slug-b'])   a section announces its shops
     DLShown.has('slug-a')                 already on screen?
     await DLShown.ready()                 wait briefly for claims to land

   ready() waits for the sections that said they were coming, and
   gives up after a short grace period so a failed section can never
   stall the grid.
   ============================================================ */
(function (global) {
  'use strict';

  var claimed = new Set();
  var expected = 0, arrived = 0;
  var pending = [];

  function flush(){
    if (arrived < expected) return;
    var list = pending; pending = [];
    list.forEach(function (fn){ try { fn(); } catch(_){} });
  }

  // A section calls this as soon as the page loads, before it fetches,
  // so ready() knows how many claims are still on their way.
  function expect(n){ expected += (n || 1); }

  function claim(slugs){
    (slugs || []).forEach(function (s){ if (s) claimed.add(String(s)); });
    arrived++;
    flush();
  }

  function has(s){ return !!s && claimed.has(String(s)); }

  function ready(maxWaitMs){
    return new Promise(function (resolve){
      if (arrived >= expected) return resolve();
      var done = false;
      var finish = function (){ if (!done){ done = true; resolve(); } };
      pending.push(finish);
      setTimeout(finish, maxWaitMs || 900);   // never block the page on a slow section
    });
  }

  global.DLShown = {
    expect: expect, claim: claim, has: has, ready: ready,
    all: function (){ var out = []; claimed.forEach(function (s){ out.push(s); }); return out; }
  };
})(window);
