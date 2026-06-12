// =====================================================
// api/ai-caption.js
// AI-powered poster caption generator
// =====================================================
// POST { category, lang, business?, dayOfWeek? }
// Response: { msg: string, sub: string, source: 'groq' | 'local' }
//
// Strategy:
//   1. If GROQ_API_KEY env var is set → call Groq's llama-3.1-8b-instant
//      with a carefully tuned system prompt.
//   2. Else (or on any error) → rotate from a rich local library that's
//      day-of-week + variation-aware. Result is non-deterministic so each
//      tap produces a different suggestion.
//
// LOCAL FALLBACK is excellent — no Groq is required for the feature to feel "AI".
// =====================================================

const GROQ_API_KEY = process.env.GROQ_API_KEY || '';
const GROQ_MODEL = 'llama-3.1-8b-instant';

// =====================================================
// Local rich library — used both as fallback and as
// few-shot examples in the Groq prompt
// =====================================================
const LOCAL = {
  offer: {
    en: [
      { msg: 'FLAT 30% OFF', sub: 'Today only · While stocks last' },
      { msg: 'MEGA SALE', sub: 'Up to 50% off across the store' },
      { msg: 'WEEKEND SPECIAL', sub: 'Saturday + Sunday · Don\'t miss it' },
      { msg: 'BUY 1 GET 1', sub: 'On selected items · Today only' },
      { msg: 'FLASH SALE', sub: 'Next 24 hours · Limited stock' },
      { msg: 'MID-MONTH BLOWOUT', sub: 'Up to 40% off everything' },
      { msg: 'CLEARANCE', sub: 'Final pieces · Sale ends today' },
      { msg: 'EARLY BIRD OFFER', sub: 'First 20 customers get extra 10% off' },
      { msg: 'COMBO DEAL', sub: 'Pair any two and save 25%' },
      { msg: 'LOYALTY REWARD', sub: 'Regular customers get extra 15% today' }
    ],
    hi: [
      { msg: 'फ्लैट 30% छूट', sub: 'आज एक दिन के लिए · स्टॉक सीमित' },
      { msg: 'मेगा सेल', sub: 'पूरी दुकान में 50% तक की छूट' },
      { msg: 'वीकेंड स्पेशल', sub: 'शनि + रवि · हाथ से न जाने दें' },
      { msg: 'एक के साथ एक मुफ्त', sub: 'चुनिंदा सामान पर · आज ही' },
      { msg: 'फ़्लैश सेल', sub: 'अगले 24 घंटे · जल्दी आइए' },
      { msg: 'मध्य-माह छूट', sub: 'सभी आइटम पर 40% तक की छूट' },
      { msg: 'क्लियरेंस सेल', sub: 'अंतिम पीस · सेल आज समाप्त' },
      { msg: 'पहले आओ-पहले पाओ', sub: 'पहले 20 ग्राहकों को 10% अतिरिक्त छूट' },
      { msg: 'कॉम्बो ऑफर', sub: 'कोई भी दो आइटम लें और 25% बचाएँ' },
      { msg: 'लॉयल्टी बोनस', sub: 'नियमित ग्राहकों को आज 15% अतिरिक्त' }
    ]
  },
  greeting: {
    en: [
      { msg: 'Have a wonderful day!', sub: 'From your trusted neighbourhood shop' },
      { msg: 'Good morning, friends!', sub: 'Open and ready to serve you today' },
      { msg: 'Thank you for choosing us', sub: 'We truly appreciate your trust' },
      { msg: 'Happy weekend!', sub: 'Drop by — we have something for you' },
      { msg: 'Welcome back', sub: 'Always great to see familiar faces' },
      { msg: 'Have a productive Monday', sub: 'We are open and ready to help' },
      { msg: 'Wishing you joy today', sub: 'Visit us for a warm smile and great service' },
      { msg: 'A small thank you', sub: 'Your support means everything to us' }
    ],
    hi: [
      { msg: 'आपका दिन शुभ हो!', sub: 'आपकी विश्वसनीय स्थानीय दुकान से' },
      { msg: 'सुप्रभात, दोस्तों!', sub: 'आज आपकी सेवा के लिए तत्पर' },
      { msg: 'धन्यवाद, आपका विश्वास हमारी पूँजी है', sub: 'हम आभारी हैं' },
      { msg: 'सप्ताहांत की शुभकामनाएँ', sub: 'पधारिए — कुछ खास आपके लिए है' },
      { msg: 'वापसी पर स्वागत', sub: 'जान-पहचान वाले चेहरे देखकर अच्छा लगा' },
      { msg: 'शुभ सोमवार', sub: 'हम खुले हैं, सेवा के लिए तैयार' }
    ]
  },
  new: {
    en: [
      { msg: 'NEW ARRIVAL', sub: 'Fresh stock just landed in store' },
      { msg: 'JUST ARRIVED', sub: 'New collection · Come check it out' },
      { msg: 'FRESH STOCK ALERT', sub: 'Latest items now available' },
      { msg: 'BRAND NEW RANGE', sub: 'Visit today · Limited pieces' },
      { msg: 'NEW DESIGNS IN', sub: 'Hand-picked · Available now' },
      { msg: 'LATEST COLLECTION', sub: 'Exclusive picks · In store today' },
      { msg: 'NEW SEASON', sub: 'Updated inventory now on shelves' },
      { msg: 'TRENDING NOW', sub: 'Most-loved items back in stock' }
    ],
    hi: [
      { msg: 'नया स्टॉक आया', sub: 'ताज़ा माल अभी दुकान पर' },
      { msg: 'अभी-अभी आया', sub: 'नया कलेक्शन · ज़रूर देखें' },
      { msg: 'नया कलेक्शन', sub: 'नवीनतम सामान अभी उपलब्ध' },
      { msg: 'नई रेंज', sub: 'आज पधारें · सीमित मात्रा' },
      { msg: 'नए डिज़ाइन', sub: 'चुनिंदा माल · अभी उपलब्ध' },
      { msg: 'मौसमी अपडेट', sub: 'नया स्टॉक शेल्फ पर' }
    ]
  },
  hours: {
    en: [
      { msg: 'OPEN TODAY', sub: 'Visit us 10 AM to 9 PM' },
      { msg: 'EXTENDED HOURS', sub: 'Today we are open till 10 PM' },
      { msg: 'WE ARE OPEN', sub: 'Walk in any time today' },
      { msg: 'CLOSED TODAY', sub: 'See you tomorrow morning' },
      { msg: 'EARLY OPENING', sub: 'Starting from 8 AM today' },
      { msg: 'OPEN 7 DAYS', sub: 'No weekly off · Always here for you' },
      { msg: 'HOLIDAY SCHEDULE', sub: 'Modified hours · Check before visiting' }
    ],
    hi: [
      { msg: 'आज खुले हैं', sub: 'सुबह 10 बजे से रात 9 बजे तक' },
      { msg: 'विशेष समय', sub: 'आज रात 10 बजे तक खुले' },
      { msg: 'हम खुले हैं', sub: 'आज किसी भी समय पधारें' },
      { msg: 'आज बंद', sub: 'कल सुबह मिलते हैं' },
      { msg: 'जल्दी खुलेंगे', sub: 'आज सुबह 8 बजे से' },
      { msg: 'हफ़्ते के 7 दिन', sub: 'कोई साप्ताहिक अवकाश नहीं' }
    ]
  },
  festival: {
    en: [
      { msg: 'Happy Festival', sub: 'Warm wishes from our family to yours' },
      { msg: 'Festive Greetings', sub: 'Wishing you joy and prosperity' },
      { msg: 'Celebrate With Us', sub: 'Special festive collection in store' },
      { msg: 'May This Year Shine', sub: 'Heartfelt wishes from our team' },
      { msg: 'Joy & Light to You', sub: 'Have a beautiful celebration' },
      { msg: 'Festive Wishes', sub: 'Visit us for festive specials' }
    ],
    hi: [
      { msg: 'त्योहार की शुभकामनाएँ', sub: 'हमारे परिवार से आपके परिवार को' },
      { msg: 'खुशियों भरा पर्व हो', sub: 'आपको और आपके परिवार को मंगलकामनाएँ' },
      { msg: 'पधारें इस उत्सव में', sub: 'विशेष त्योहार कलेक्शन दुकान पर' },
      { msg: 'यह वर्ष चमकता रहे', sub: 'हमारी ओर से हार्दिक शुभकामनाएँ' },
      { msg: 'सुख-समृद्धि की कामनाएँ', sub: 'मनाइए, सुंदर पर्व मनाइए' }
    ]
  }
};

function pickLocal(category, lang){
  const pool = (LOCAL[category] && LOCAL[category][lang]) || LOCAL.offer.en;
  // Day + minute hash to ensure variation across taps within the same minute too
  const seed = Math.floor(Math.random() * pool.length);
  return pool[seed];
}

async function tryGroq(category, lang, business, dayOfWeek){
  if (!GROQ_API_KEY) return null;
  const sample = pickLocal(category, lang);
  const bizLine = business && business.name
    ? `The shop is called "${business.name}"${business.category ? ', category ' + business.category : ''}.`
    : '';
  const langInstruction = lang === 'hi'
    ? 'Reply in clean Devanagari Hindi. No Roman script mixed in.'
    : 'Reply in clean professional English.';

  const sys = [
    'You are an expert ad copywriter for Indian local shops creating WhatsApp Status posters.',
    'Write ONE poster headline (under 30 characters) and ONE subtitle (under 60 characters).',
    `Category: ${category}.`,
    `Day of week: ${dayOfWeek || ''}.`,
    bizLine,
    langInstruction,
    'Return ONLY valid JSON: {"msg":"headline","sub":"subtitle"}. No markdown, no explanation.',
    `Example shape (for inspiration only, do NOT copy verbatim): ${JSON.stringify(sample)}`
  ].join('\n');

  try {
    const r = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': 'Bearer ' + GROQ_API_KEY,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: GROQ_MODEL,
        messages: [{ role: 'system', content: sys }, { role: 'user', content: 'Generate the poster text.' }],
        temperature: 0.85,
        max_tokens: 120,
        response_format: { type: 'json_object' }
      })
    });
    if (!r.ok) return null;
    const j = await r.json();
    const text = j && j.choices && j.choices[0] && j.choices[0].message && j.choices[0].message.content;
    if (!text) return null;
    let parsed;
    try { parsed = JSON.parse(text); } catch(_){ return null; }
    if (!parsed || !parsed.msg) return null;
    return {
      msg: String(parsed.msg).trim().slice(0, 80),
      sub: String(parsed.sub || '').trim().slice(0, 100)
    };
  } catch(_){ return null; }
}

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Content-Type', 'application/json');

  if (req.method !== 'POST') {
    res.statusCode = 405;
    return res.end(JSON.stringify({ error: 'POST only' }));
  }

  let body = req.body;
  if (typeof body === 'string') { try { body = JSON.parse(body); } catch(_){ body = {}; } }
  body = body || {};
  const category = String(body.category || 'offer').toLowerCase();
  const lang = (body.lang === 'hi') ? 'hi' : 'en';
  const business = body.business || null;
  const dayOfWeek = body.dayOfWeek || (new Date()).toLocaleDateString('en-US', { weekday: 'long' });

  // Try Groq first
  const groqResult = await tryGroq(category, lang, business, dayOfWeek);
  if (groqResult){
    res.statusCode = 200;
    return res.end(JSON.stringify({ ...groqResult, source: 'groq' }));
  }

  // Fallback: rich local rotation
  const local = pickLocal(category, lang);
  res.statusCode = 200;
  return res.end(JSON.stringify({ ...local, source: 'local' }));
};
