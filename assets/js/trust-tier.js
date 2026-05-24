/* ============================================================
   trust-tier.js — Verified Shop Tier computation
   ============================================================
   Computes Bronze / Silver / Gold tier from existing shop fields.
   No extra DB calls — uses verified_score, rating_avg, rating_count,
   established_year, photos already returned by search_businesses RPC
   and businesses table.

   API:
     DukanTier.compute(shop)
       -> { tier: 'gold'|'silver'|'bronze'|null,
            label: 'Gold Trusted' | 'Silver Verified' | 'Verified',
            badgeHTML: '<span class=...>★ Gold</span>',
            nextTier: { tier, missing: [...] } | null }
     DukanTier.badge(shop)   -> badgeHTML string (or '')
     DukanTier.roadmap(shop) -> array of plain-text gap descriptions

   Tiers (industry-standard for local directories):
     Bronze   = verified_score >= 3
     Silver   = Bronze + rating_avg >= 3.5 + rating_count >= 5 + photos >= 2
     Gold     = Silver + rating_avg >= 4.2 + rating_count >= 20
                + established_year set with at least 1 year of operation
============================================================ */
(function(global){
  'use strict';

  var THRESHOLDS = {
    bronze: { verified_score: 3 },
    silver: { verified_score: 3, rating_avg: 3.5, rating_count: 5, photos: 2 },
    gold:   { verified_score: 3, rating_avg: 4.2, rating_count: 20, photos: 2, year_min_age: 1 }
  };

  function num(x){ return Number(x) || 0; }

  function compute(shop){
    if (!shop) return { tier:null, label:'Not verified', badgeHTML:'', nextTier:null };
    var vs   = num(shop.verified_score);
    var ravg = num(shop.rating_avg);
    var rcnt = num(shop.rating_count);
    var phs  = Array.isArray(shop.photos) ? shop.photos.length : num(shop.photo_count);
    var yr   = num(shop.established_year);
    var nowYr = new Date().getFullYear();
    var age  = yr > 0 ? Math.max(0, nowYr - yr) : 0;

    var T = THRESHOLDS;
    var isBronze = vs >= T.bronze.verified_score;
    var isSilver = isBronze
                && ravg >= T.silver.rating_avg
                && rcnt >= T.silver.rating_count
                && phs  >= T.silver.photos;
    var isGold   = isSilver
                && ravg >= T.gold.rating_avg
                && rcnt >= T.gold.rating_count
                && yr > 0 && age >= T.gold.year_min_age;

    var tier = isGold ? 'gold' : (isSilver ? 'silver' : (isBronze ? 'bronze' : null));
    var label, badgeHTML;
    switch (tier){
      case 'gold':
        label = 'Gold Trusted';
        badgeHTML = '<span class="trust-tier trust-gold" title="Gold Trusted Shop">\u{1F3C5} '
          + '<span data-i18n-en>Gold Trusted</span><span data-i18n-hi>गोल्ड ट्रस्टेड</span>'
          + '</span>';
        break;
      case 'silver':
        label = 'Silver Verified';
        badgeHTML = '<span class="trust-tier trust-silver" title="Silver Verified">\u{1F948} '
          + '<span data-i18n-en>Silver Verified</span><span data-i18n-hi>सिल्वर वेरिफाइड</span>'
          + '</span>';
        break;
      case 'bronze':
        label = 'Verified';
        badgeHTML = '<span class="trust-tier trust-bronze" title="Verified">\u2713 '
          + '<span data-i18n-en>Verified</span><span data-i18n-hi>वेरिफाइड</span>'
          + '</span>';
        break;
      default:
        label = 'Not verified';
        badgeHTML = '';
    }

    // Roadmap to next tier
    var nextTier = null;
    var missing = [];
    if (!isBronze){
      if (vs < T.bronze.verified_score) missing.push('Get admin verification (request callback)');
      nextTier = { tier:'bronze', missing: missing };
    } else if (!isSilver){
      if (ravg < T.silver.rating_avg) missing.push('Improve average rating to ' + T.silver.rating_avg + ' (current ' + ravg.toFixed(1) + ')');
      if (rcnt < T.silver.rating_count) missing.push('Get ' + (T.silver.rating_count - rcnt) + ' more review' + (T.silver.rating_count - rcnt === 1 ? '' : 's'));
      if (phs < T.silver.photos) missing.push('Add ' + (T.silver.photos - phs) + ' more photo' + (T.silver.photos - phs === 1 ? '' : 's'));
      nextTier = { tier:'silver', missing: missing };
    } else if (!isGold){
      if (ravg < T.gold.rating_avg) missing.push('Improve average rating to ' + T.gold.rating_avg + ' (current ' + ravg.toFixed(1) + ')');
      if (rcnt < T.gold.rating_count) missing.push('Get ' + (T.gold.rating_count - rcnt) + ' more review' + (T.gold.rating_count - rcnt === 1 ? '' : 's'));
      if (!yr) missing.push('Set your shop\'s established year in profile');
      else if (age < T.gold.year_min_age) missing.push('At least 1 year of operation required (current age: ' + age + ' year' + (age === 1 ? '' : 's') + ')');
      nextTier = { tier:'gold', missing: missing };
    }

    return { tier: tier, label: label, badgeHTML: badgeHTML, nextTier: nextTier };
  }

  function badge(shop){
    var r = compute(shop);
    return r.badgeHTML;
  }

  function roadmap(shop){
    var r = compute(shop);
    return r.nextTier ? r.nextTier.missing : [];
  }

  global.DukanTier = { compute: compute, badge: badge, roadmap: roadmap, THRESHOLDS: THRESHOLDS };
})(window);
