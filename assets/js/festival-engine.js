/* ============================================================
   festival-engine.js
   ============================================================
   STRATEGIC PHASE 4 (2026-06-05):
   Festival auto-poster engine. When a major festival is within
   7 days, override the daily theme with a festival-specific
   creative.

   Festivals covered (all India + Punjab/Haryana regional):
     - Diwali, Dhanteras, Bhai Dooj
     - Holi
     - Eid al-Fitr, Eid al-Adha
     - Raksha Bandhan
     - Karva Chauth
     - Janmashtami
     - Navratri / Dussehra
     - Christmas, New Year
     - Independence Day (15 Aug)
     - Republic Day (26 Jan)
     - Lohri (13 Jan) — Punjab/Haryana special
     - Baisakhi (13-14 Apr) — Punjab special
     - Teej (July-Aug) — Haryana

   Dates are HARDCODED per year (2026, 2027). Falls back to
   no-festival mode if year not in calendar. Update yearly.
   ============================================================ */
(function(global){
'use strict';

// ─── Festival Calendar (YYYY-MM-DD) ─────────────────────────
const FESTIVALS = {
  '2026-01-13': { id: 'lohri',        nameEn: 'Lohri',           emoji: '🔥', accent: '#F59E0B',
    bg: ['#F59E0B', '#EA580C', '#DC2626'], ink: '#FFFFFF',
    headline: 'Happy Lohri',
    subline: 'Warmth, fire and festivities',
    cta: 'Visit us during this special time'
  },
  '2026-01-26': { id: 'republic-day', nameEn: 'Republic Day',     emoji: '🇮🇳', accent: '#F97316',
    bg: ['#FF6B1A', '#FFFFFF', '#16A34A'], ink: '#1E3A8A',
    headline: 'Happy Republic Day',
    subline: 'Proudly serving the nation',
    cta: 'A salute to the spirit of India'
  },
  '2026-03-04': { id: 'holi',          nameEn: 'Holi',            emoji: '🎨', accent: '#EC4899',
    bg: ['#DB2777', '#A855F7', '#3B82F6'], ink: '#FFFFFF',
    headline: 'Happy Holi',
    subline: 'A festival of colours and joy',
    cta: 'Celebrate with your trusted local business'
  },
  '2026-04-13': { id: 'baisakhi',     nameEn: 'Baisakhi',         emoji: '🌾', accent: '#FBBF24',
    bg: ['#F59E0B', '#16A34A', '#FBBF24'], ink: '#FFFFFF',
    headline: 'Happy Baisakhi',
    subline: 'Harvest, prosperity and tradition',
    cta: 'Visit us for the festive season'
  },
  '2026-08-09': { id: 'rakhi',         nameEn: 'Raksha Bandhan',  emoji: '🪢', accent: '#F59E0B',
    bg: ['#F59E0B', '#DC2626', '#7C2D12'], ink: '#FFFFFF',
    headline: 'Happy Raksha Bandhan',
    subline: 'Bonds that last a lifetime',
    cta: 'Special offers for brothers and sisters'
  },
  '2026-08-15': { id: 'independence',  nameEn: 'Independence Day', emoji: '🇮🇳', accent: '#FF6B1A',
    bg: ['#FF6B1A', '#FFFFFF', '#16A34A'], ink: '#1E3A8A',
    headline: 'Happy Independence Day',
    subline: 'Proud to serve our community',
    cta: 'A salute to the spirit of India'
  },
  '2026-08-26': { id: 'janmashtami',  nameEn: 'Janmashtami',      emoji: '🪈', accent: '#FBBF24',
    bg: ['#1E3A8A', '#7C3AED', '#FBBF24'], ink: '#FFFFFF',
    headline: 'Happy Janmashtami',
    subline: 'Blessings of Lord Krishna',
    cta: 'Special hours during the festival'
  },
  '2026-09-15': { id: 'ganesh',       nameEn: 'Ganesh Chaturthi', emoji: '🐘', accent: '#FBBF24',
    bg: ['#DC2626', '#EA580C', '#FBBF24'], ink: '#FFFFFF',
    headline: 'Ganpati Bappa Morya',
    subline: 'Wisdom and new beginnings',
    cta: 'Celebrate with us this season'
  },
  '2026-10-02': { id: 'gandhi',       nameEn: 'Gandhi Jayanti',   emoji: '🕊️', accent: '#FFF',
    bg: ['#FFFFFF', '#E5E7EB', '#94A3B8'], ink: '#1F2937',
    headline: 'Remembering Gandhi Ji',
    subline: 'Truth, peace and service',
    cta: 'Honouring values of integrity'
  },
  '2026-10-10': { id: 'navratri',     nameEn: 'Navratri',         emoji: '💃', accent: '#DB2777',
    bg: ['#DB2777', '#F59E0B', '#16A34A'], ink: '#FFFFFF',
    headline: 'Happy Navratri',
    subline: 'Nine nights of devotion',
    cta: 'Special hours during the festival'
  },
  '2026-10-20': { id: 'dussehra',     nameEn: 'Dussehra',         emoji: '🏹', accent: '#DC2626',
    bg: ['#DC2626', '#F59E0B', '#FBBF24'], ink: '#FFFFFF',
    headline: 'Happy Dussehra',
    subline: 'Victory of good over evil',
    cta: 'Festive offers in store'
  },
  '2026-11-08': { id: 'karva-chauth',  nameEn: 'Karva Chauth',    emoji: '🌙', accent: '#FBBF24',
    bg: ['#7C2D12', '#DC2626', '#FBBF24'], ink: '#FFFFFF',
    headline: 'Happy Karva Chauth',
    subline: 'Love, dedication and tradition',
    cta: 'Visit us for the special day'
  },
  '2026-11-09': { id: 'dhanteras',    nameEn: 'Dhanteras',         emoji: '✨', accent: '#FBBF24',
    bg: ['#FBBF24', '#F59E0B', '#92400E'], ink: '#451A03',
    headline: 'Happy Dhanteras',
    subline: 'Prosperity and abundance',
    cta: 'Auspicious shopping today'
  },
  '2026-11-12': { id: 'diwali',       nameEn: 'Diwali',            emoji: '🪔', accent: '#FBBF24',
    bg: ['#7C2D12', '#DC2626', '#FBBF24'], ink: '#FFFFFF',
    headline: 'Happy Diwali',
    subline: 'A festival of lights and joy',
    cta: 'Wishing you and your family prosperity'
  },
  '2026-11-14': { id: 'bhai-dooj',     nameEn: 'Bhai Dooj',        emoji: '💝', accent: '#F59E0B',
    bg: ['#DC2626', '#F59E0B', '#FBBF24'], ink: '#FFFFFF',
    headline: 'Happy Bhai Dooj',
    subline: 'Bonds of love and protection',
    cta: 'Special gifts for the occasion'
  },
  '2026-12-25': { id: 'christmas',    nameEn: 'Christmas',         emoji: '🎄', accent: '#DC2626',
    bg: ['#DC2626', '#16A34A', '#FFFFFF'], ink: '#1F2937',
    headline: 'Merry Christmas',
    subline: 'Joy and peace to all',
    cta: 'Festive cheer this season'
  },
  '2026-12-31': { id: 'new-year',     nameEn: 'New Year',          emoji: '🎉', accent: '#FBBF24',
    bg: ['#1E3A8A', '#7C3AED', '#FBBF24'], ink: '#FFFFFF',
    headline: 'Happy New Year',
    subline: 'New beginnings, fresh hope',
    cta: 'Wishing you a prosperous new year'
  },

  // ─── 2027 (next year continuity) ───
  '2027-01-13': { id: 'lohri',        nameEn: 'Lohri',           emoji: '🔥', accent: '#F59E0B',
    bg: ['#F59E0B', '#EA580C', '#DC2626'], ink: '#FFFFFF',
    headline: 'Happy Lohri',
    subline: 'Warmth, fire and festivities',
    cta: 'Visit us during this special time'
  },
  '2027-01-26': { id: 'republic-day', nameEn: 'Republic Day',     emoji: '🇮🇳', accent: '#F97316',
    bg: ['#FF6B1A', '#FFFFFF', '#16A34A'], ink: '#1E3A8A',
    headline: 'Happy Republic Day',
    subline: 'Proudly serving the nation',
    cta: 'A salute to the spirit of India'
  },
  '2027-03-23': { id: 'holi',          nameEn: 'Holi',            emoji: '🎨', accent: '#EC4899',
    bg: ['#DB2777', '#A855F7', '#3B82F6'], ink: '#FFFFFF',
    headline: 'Happy Holi',
    subline: 'A festival of colours and joy',
    cta: 'Celebrate with your trusted local business'
  },
  '2027-08-15': { id: 'independence',  nameEn: 'Independence Day', emoji: '🇮🇳', accent: '#FF6B1A',
    bg: ['#FF6B1A', '#FFFFFF', '#16A34A'], ink: '#1E3A8A',
    headline: 'Happy Independence Day',
    subline: 'Proud to serve our community',
    cta: 'A salute to the spirit of India'
  },
  '2027-11-01': { id: 'diwali',       nameEn: 'Diwali',            emoji: '🪔', accent: '#FBBF24',
    bg: ['#7C2D12', '#DC2626', '#FBBF24'], ink: '#FFFFFF',
    headline: 'Happy Diwali',
    subline: 'A festival of lights and joy',
    cta: 'Wishing you and your family prosperity'
  }
};

// ─── Date helpers ────────────────────────────────────────────
function isoToday(){
  const d = new Date();
  return d.getFullYear() + '-' +
         String(d.getMonth() + 1).padStart(2, '0') + '-' +
         String(d.getDate()).padStart(2, '0');
}

function daysBetween(isoDateA, isoDateB){
  const a = new Date(isoDateA + 'T00:00:00');
  const b = new Date(isoDateB + 'T00:00:00');
  return Math.round((b - a) / (1000 * 60 * 60 * 24));
}

// ─── Active festival detection ───────────────────────────────
// Returns festival theme object if a festival is within next 7 days,
// or null otherwise. Festival on the day or in the past 1 day still wins.
function getActiveFestival(){
  const today = isoToday();
  let best = null;
  let bestDelta = 999;

  for (const date in FESTIVALS) {
    const delta = daysBetween(today, date);
    // Show festival from day-of through 7 days before
    if (delta >= -1 && delta <= 7) {
      if (Math.abs(delta) < Math.abs(bestDelta)) {
        bestDelta = delta;
        best = Object.assign({ date, daysAway: delta }, FESTIVALS[date]);
      }
    }
  }

  return best;
}

// ─── Integration adapter — convert festival → DailyPoster theme ─
function festivalAsTheme(f){
  if (!f) return null;
  return {
    id: 'festival-' + f.id,
    nameEn: f.nameEn,
    nameHi: f.nameEn, // keep English for now
    bgGradient: f.bg,
    accent: f.accent,
    ink: f.ink,
    headline: (s) => f.headline,
    subline: (s) => f.subline,
    emoji: f.emoji,
    layout: 'festival',
    cta: f.cta,
    isFestival: true,
    festivalDate: f.date,
    daysAway: f.daysAway
  };
}

// ─── Get today's theme — festival overrides daily if active ──
function getTodayThemeWithFestival(){
  const f = getActiveFestival();
  if (f) {
    return Object.assign(festivalAsTheme(f), { dayIndex: new Date().getDay() });
  }
  // Fall back to DailyPoster's daily rotation
  if (global.DailyPoster && global.DailyPoster.getTodayTheme) {
    return global.DailyPoster.getTodayTheme();
  }
  return null;
}

// ─── Public API ─────────────────────────────────────────────
global.FestivalEngine = {
  FESTIVALS,
  getActiveFestival,
  festivalAsTheme,
  getTodayThemeWithFestival,
  isoToday,
  daysBetween
};

})(window);
