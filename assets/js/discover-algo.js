/* ============================================================
   DukanList — Discover "For You" Algorithm
   ============================================================
   Privacy-first, client-side personalization for the Discover feed.

   ALL tracking lives in localStorage — NEVER sent to server.
   No PII collected. User can wipe via DukanAlgo.resetProfile().

   SCORING (each shop gets 0..100):
     proximity (30)         — distance from user (or city match if no geo)
     category match (25)    — categories the user has viewed/liked before
     recently active (15)   — updated_at decay
     engagement (15)        — log-scaled views + leads + likes
     time of day (10)       — food at meal-times, services at biz-hours
     freshness/random (5)   — prevents stagnant ranking

   USAGE:
     const profile = DukanAlgo.getUserProfile();
     const { score, reasons } = DukanAlgo.scoreShop(shop, profile);
     // sort shops by score desc
     // show reasons in "Why am I seeing this?" tooltip

     DukanAlgo.track('view',  { shop_id, category_ids, ms_on_card });
     DukanAlgo.track('like',  { shop_id, category_ids });
     DukanAlgo.track('skip',  { shop_id, category_ids });

   Tracked keys in localStorage:
     dl_algo_v1 = {
       categoryAffinity:  { catId: weighted_score },
       shopHistory:       { shopId: { lastSeen, totalMs, liked, skipped } },
       userArea:          { lat, lng, last_set_at },
       boost:             [catIds...],   // explicit "show more like this"
       hide:              [shopIds...]   // explicit "don't show this"
     }
============================================================ */
(function(global){
  'use strict';

  var STORAGE_KEY    = 'dl_algo_v1';
  var MAX_AGE_MS     = 90 * 24 * 60 * 60 * 1000; // affinity decays after 90 days
  var VIEW_MIN_MS    = 3000;  // <3s = skip; >3s = real interest
  var STRONG_VIEW_MS = 8000;  // >8s = strong signal

  // ============================================================
  // Storage helpers
  // ============================================================
  function load(){
    try {
      var raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return defaultProfile();
      var p = JSON.parse(raw);
      // Backfill missing keys gracefully
      var d = defaultProfile();
      Object.keys(d).forEach(function(k){
        if (p[k] == null) p[k] = d[k];
      });
      return p;
    } catch(_){
      return defaultProfile();
    }
  }
  function save(p){
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(p)); } catch(_){}
  }
  function defaultProfile(){
    return {
      categoryAffinity: {},
      shopHistory:      {},
      userArea:         null,
      boost:            [],
      hide:             [],
      sessionsCount:    0,
      lastSessionAt:    null
    };
  }

  // ============================================================
  // Tracking API
  // ============================================================
  function track(action, data){
    var p = load();
    data = data || {};
    var now = Date.now();

    // Bump session counter once per 30-min window
    if (!p.lastSessionAt || (now - p.lastSessionAt) > 30 * 60 * 1000){
      p.sessionsCount = (p.sessionsCount || 0) + 1;
    }
    p.lastSessionAt = now;

    var shopId = data.shop_id || data.shopId;
    var cats   = data.category_ids || data.cats || [];

    if (shopId){
      var h = p.shopHistory[shopId] || { lastSeen: 0, totalMs: 0, viewCount: 0, liked: false, skipped: false };
      h.lastSeen = now;
      h.viewCount = (h.viewCount || 0) + 1;
      p.shopHistory[shopId] = h;

      if (action === 'view'){
        var ms = Math.min(60000, Math.max(0, data.ms_on_card || data.ms || 0));
        h.totalMs = (h.totalMs || 0) + ms;
        // Strong view → boost categories
        if (ms >= STRONG_VIEW_MS){
          bumpCategories(p, cats, 3);
        } else if (ms >= VIEW_MIN_MS){
          bumpCategories(p, cats, 1);
        }
      } else if (action === 'like'){
        h.liked = true;
        bumpCategories(p, cats, 5);  // strongest signal
      } else if (action === 'skip'){
        h.skipped = true;
        // Mild negative signal on categories (we DON'T zero them, just reduce growth)
        bumpCategories(p, cats, -0.5);
      } else if (action === 'contact'){  // call/whatsapp from card
        h.contacted = true;
        bumpCategories(p, cats, 4);
      }
    }

    save(p);
    return p;
  }

  function bumpCategories(p, catIds, delta){
    if (!Array.isArray(catIds) || !catIds.length) return;
    catIds.forEach(function(cid){
      if (cid == null) return;
      var k = String(cid);
      var cur = p.categoryAffinity[k] || 0;
      cur = Math.max(0, Math.min(100, cur + delta));
      p.categoryAffinity[k] = cur;
    });
  }

  // ============================================================
  // User area helpers (optional — graceful if no geo)
  // ============================================================
  function setUserArea(lat, lng){
    var p = load();
    p.userArea = { lat: lat, lng: lng, set_at: Date.now() };
    save(p);
  }
  function getUserArea(){
    var p = load();
    return p.userArea || null;
  }

  function distanceKm(lat1, lng1, lat2, lng2){
    if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) return null;
    var R = 6371;
    var toRad = function(d){ return d * Math.PI / 180; };
    var dLat = toRad(lat2 - lat1);
    var dLng = toRad(lng2 - lng1);
    var a = Math.sin(dLat/2) * Math.sin(dLat/2) +
            Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
            Math.sin(dLng/2) * Math.sin(dLng/2);
    var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    return R * c;
  }

  // ============================================================
  // Time of day relevance
  // ============================================================
  // Each category type has peak windows. We score 0..1 based on
  // how well the current hour matches.
  var TIME_WINDOWS = {
    // Food / restaurants peak at meal times
    food: [[7,10],[12,15],[18,22]],
    // Sweets shops peak in evening + festivals
    sweets: [[16,21]],
    // Services peak during business hours
    service: [[9,19]],
    // Shops peak during day
    shop: [[9,20]],
    // Healthcare peaks morning + evening
    health: [[8,11],[17,20]],
    // Default — moderate score all day
    default: [[8,22]]
  };

  function timeOfDayBucket(catName, catSlug){
    var s = ((catName || '') + ' ' + (catSlug || '')).toLowerCase();
    if (/restaurant|dhaba|food|tiffin|hotel|cafe|canteen/.test(s)) return 'food';
    if (/sweet|mithai|halwai|bakery|chocolate|ice cream/.test(s)) return 'sweets';
    if (/doctor|clinic|hospital|pharmac|chemist|medical|dental|optical/.test(s)) return 'health';
    if (/repair|service|tailor|plumber|electrician|salon|parlour|mechanic|carpenter/.test(s)) return 'service';
    return 'shop';
  }

  function timeOfDayScore(catName, catSlug, hourOfDay){
    var bucket = timeOfDayBucket(catName, catSlug);
    var windows = TIME_WINDOWS[bucket] || TIME_WINDOWS.default;
    for (var i=0; i<windows.length; i++){
      var w = windows[i];
      if (hourOfDay >= w[0] && hourOfDay <= w[1]) return 1.0;
    }
    // Out of window — partial credit (not zero, so we don't fully suppress)
    return 0.3;
  }

  // ============================================================
  // Scoring engine
  // ============================================================
  function scoreShop(shop, profile){
    profile = profile || load();
    var reasons = [];   // human-readable strings for "Why?" tooltip
    var subScores = {};

    if (!shop || !shop.id){
      return { score: 0, reasons: [], subScores: {} };
    }

    // Hard skip — explicit hide list
    if (profile.hide && profile.hide.indexOf(shop.id) >= 0){
      return { score: -1, reasons: ['hidden'], subScores: { hidden: true } };
    }

    // Avoid showing the same shop too often in one session
    var hist = profile.shopHistory[shop.id];
    var recentlyShown = hist && hist.lastSeen && (Date.now() - hist.lastSeen) < 15 * 60 * 1000;
    var alreadyContacted = hist && hist.contacted;

    // ------- Sub-score 1: proximity (30%) -------
    var proxScore = 0;
    if (profile.userArea && shop.lat && shop.lng){
      var km = distanceKm(profile.userArea.lat, profile.userArea.lng, shop.lat, shop.lng);
      if (km != null){
        if (km < 1)       proxScore = 1.0;
        else if (km < 3)  proxScore = 0.8;
        else if (km < 8)  proxScore = 0.5;
        else if (km < 20) proxScore = 0.25;
        else              proxScore = 0.1;
        if (km < 2) reasons.push('📍 Aapse sirf ' + km.toFixed(1) + ' km dur');
      }
    } else {
      // No geo — fall back to "same city" check via STATE.cityFilter (if any)
      proxScore = 0.6;  // neutral mid
    }
    subScores.proximity = proxScore;

    // ------- Sub-score 2: category match (25%) -------
    var catScore = 0;
    var shopCats = collectShopCategoryIds(shop);
    var topCatBoost = 0;
    var topCatName = null;
    shopCats.forEach(function(cid){
      var aff = profile.categoryAffinity[String(cid)] || 0;
      if (aff > topCatBoost){
        topCatBoost = aff;
        topCatName = cid;
      }
    });
    // Explicit boost list adds big bonus
    if (profile.boost && profile.boost.length){
      shopCats.forEach(function(cid){
        if (profile.boost.indexOf(cid) >= 0 || profile.boost.indexOf(String(cid)) >= 0){
          topCatBoost += 25;
        }
      });
    }
    catScore = Math.min(1, topCatBoost / 50);  // 50 affinity = max
    if (catScore > 0.5){
      reasons.push('🎯 Aap is type ki shops dekh rahe the');
    }
    subScores.category = catScore;

    // ------- Sub-score 3: recently active (15%) -------
    var recScore = 0;
    if (shop.updated_at){
      var ageDays = (Date.now() - new Date(shop.updated_at).getTime()) / 86400000;
      if (ageDays < 1)       recScore = 1.0;
      else if (ageDays < 7)  recScore = 0.8;
      else if (ageDays < 30) recScore = 0.5;
      else if (ageDays < 90) recScore = 0.3;
      else                   recScore = 0.1;
      if (ageDays < 7 && shop.created_at){
        var newDays = (Date.now() - new Date(shop.created_at).getTime()) / 86400000;
        if (newDays < 14) reasons.push('🆕 Yeh shop ' + Math.round(newDays) + ' din pehle join hui');
      }
    }
    subScores.recent = recScore;

    // ------- Sub-score 4: engagement (15%) -------
    var engScore = 0;
    var views = Number(shop.view_count || 0);
    var likes = Number(shop.likes_count || 0);
    var rating = Number(shop.rating_avg || 0);
    var ratingCount = Number(shop.rating_count || 0);
    var raw = Math.log10(views + likes * 5 + ratingCount * 3 + 1);
    engScore = Math.min(1, raw / 3);  // raw=3 = 1000ish total = max
    if (rating >= 4.5 && ratingCount >= 3){
      engScore = Math.max(engScore, 0.8);
      reasons.push('⭐ Top rated (' + rating.toFixed(1) + '★)');
    }
    if (views >= 100){
      reasons.push('🔥 ' + views + ' logon ne dekha');
    }
    subScores.engagement = engScore;

    // ------- Sub-score 5: time of day match (10%) -------
    var hour = new Date().getHours();
    var catName  = (shop._category_name || '').toLowerCase();
    var catSlug  = (shop._category_slug || '').toLowerCase();
    var todScore = timeOfDayScore(catName, catSlug, hour);
    if (todScore === 1.0){
      var bucket = timeOfDayBucket(catName, catSlug);
      if (bucket === 'food' || bucket === 'sweets'){
        reasons.push('🍱 Abhi food time hai');
      } else if (bucket === 'service'){
        reasons.push('🛠 Abhi service hours hain');
      }
    }
    subScores.time = todScore;

    // ------- Sub-score 6: random freshness (5%) -------
    // Deterministic per-session-per-shop so order doesn't reshuffle on each render
    var seed = (shop.id + '|' + new Date().toDateString()).split('').reduce(function(a,c){ return a + c.charCodeAt(0); }, 0);
    var rnd = ((seed * 9301 + 49297) % 233280) / 233280;
    subScores.random = rnd;

    // ------- Combine -------
    var score =
        proxScore   * 30
      + catScore    * 25
      + recScore    * 15
      + engScore    * 15
      + todScore    * 10
      + rnd         * 5;

    // Recently shown penalty — don't show same shop in same session
    if (recentlyShown) score *= 0.4;
    if (alreadyContacted) score *= 0.7;  // they already have the contact

    return { score: score, reasons: reasons, subScores: subScores };
  }

  function collectShopCategoryIds(shop){
    var out = [];
    if (shop.category_id) out.push(shop.category_id);
    if (shop.sub_category_id) out.push(shop.sub_category_id);
    if (shop._all_category_ids && shop._all_category_ids.length){
      shop._all_category_ids.forEach(function(c){ out.push(c); });
    }
    return out;
  }

  // ============================================================
  // Sort a list of shops by score (mutates a copy)
  // ============================================================
  function rankShops(shops){
    var profile = load();
    var withScores = (shops || []).map(function(s){
      var r = scoreShop(s, profile);
      return { shop: s, score: r.score, reasons: r.reasons };
    });
    withScores.sort(function(a, b){ return b.score - a.score; });
    // Attach reasons to the shop object for downstream UI use
    withScores.forEach(function(w){
      w.shop._algoScore = w.score;
      w.shop._algoReasons = w.reasons;
    });
    return withScores.map(function(w){ return w.shop; });
  }

  // ============================================================
  // Explicit user signals — "Show me more like this" / "Stop showing"
  // ============================================================
  function boostCategory(catId){
    if (catId == null) return;
    var p = load();
    if (p.boost.indexOf(catId) < 0) p.boost.push(catId);
    save(p);
  }
  function hideShop(shopId){
    if (!shopId) return;
    var p = load();
    if (p.hide.indexOf(shopId) < 0) p.hide.push(shopId);
    save(p);
  }
  function resetProfile(){
    try { localStorage.removeItem(STORAGE_KEY); } catch(_){}
  }
  function getUserProfile(){ return load(); }

  // ============================================================
  // Snapshot of user's top affinities (for explainer in tooltip)
  // ============================================================
  function getTopCategories(catMap, limit){
    var p = load();
    var arr = Object.keys(p.categoryAffinity).map(function(k){
      return { cat_id: k, score: p.categoryAffinity[k], name: (catMap && catMap[k]) ? catMap[k].name : null };
    });
    arr.sort(function(a,b){ return b.score - a.score; });
    return arr.slice(0, limit || 5);
  }

  // ============================================================
  // Public API
  // ============================================================
  global.DukanAlgo = {
    track:           track,
    setUserArea:     setUserArea,
    getUserArea:     getUserArea,
    scoreShop:       scoreShop,
    rankShops:       rankShops,
    boostCategory:   boostCategory,
    hideShop:        hideShop,
    resetProfile:    resetProfile,
    getUserProfile:  getUserProfile,
    getTopCategories: getTopCategories,
    _version:        'v1'
  };

})(window);
