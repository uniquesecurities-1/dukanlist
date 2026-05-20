/* ============================================================
   DukanList — Profile Templates Library
   ============================================================
   Provides ready-made About Us, USP, and FAQ templates for
   each of the 67 sub-categories. User picks one, fills blanks
   inside [square brackets], saves.

   Usage:
     window.PROFILE_TEMPLATES[categorySlug]?.about    -> Array<string>
     window.PROFILE_TEMPLATES[categorySlug]?.usp      -> Array<string>
     window.PROFILE_TEMPLATES[categorySlug]?.faqs     -> Array<{q, a}>

   Fallback chain inside getTemplates():
     1. Sub-category slug (e.g., "mutual-fund-distributor")
     2. Parent category slug (e.g., "financial-services")
     3. "default" set

   All editable placeholders are wrapped in [brackets] so users
   immediately see what to replace.
   ============================================================ */

(function(){
  'use strict';

  const T = window.PROFILE_TEMPLATES = {};

  // =========================================================
  //  DEFAULT  (fallback when no sub or parent match found)
  // =========================================================
  T['default'] = {
    about: [
      "We are [Shop Name], serving [City] since [Year]. Our mission is to offer the best products and services at fair prices with complete customer satisfaction. Friendly staff, honest dealings, and quality work have made us a trusted name in the area.",
      "[Shop Name] is a family-run business in [City] managed by [Owner Name]. With [X] years of experience, we focus on personal attention, transparent pricing, and timely delivery. Walk in any time — we love meeting new customers.",
      "Established in [Year], [Shop Name] has built a reputation for reliability and value. Whether you're a first-time customer or a regular, you'll find our team ready to help with patience and honesty. We treat every customer like family.",
      "At [Shop Name], we believe local service should be the best service. Located conveniently in [Locality], we cater to nearby residents with care and consistency. No hidden charges, no false promises — just genuine work.",
      "Welcome to [Shop Name] — your neighbourhood [category] in [City]. We are committed to fair pricing, prompt response, and quality you can trust. Visit us in person or reach us on WhatsApp for any need."
    ],
    usp: [
      "[X]+ years in business · Trusted by 1000+ families · Fair pricing · No hidden charges",
      "Quality work + honest pricing + on-time delivery — that's our promise to every customer.",
      "Family-owned since [Year]. Personal service. Transparent dealings. WhatsApp ready.",
      "Best rates in [City] · Local & loyal · Quick response on call / WhatsApp",
      "Genuine work, fair prices, friendly service — three things we never compromise on."
    ],
    faqs: [
      { q: "What are your working hours?",
        a: "We are open from [opening time] to [closing time], [days of the week]. Closed on [weekly off day]." },
      { q: "Do you accept UPI / cash / cards?",
        a: "Yes, we accept UPI (PhonePe / GPay / Paytm), cash, and [debit/credit cards if applicable]." },
      { q: "Where is your shop located?",
        a: "We are located at [full address with landmark]. Easy to find — near [nearby landmark]. Tap 'Directions' on Google Maps." },
      { q: "Do you provide home service / delivery?",
        a: "[Yes — within X km radius for free / Paid for outside city / Not at the moment]. Call us to confirm." },
      { q: "How do I book an appointment / place an order?",
        a: "Just WhatsApp us at [WhatsApp number] or call directly. We respond within [X] minutes during business hours." },
      { q: "Do you provide GST bill?",
        a: "Yes, GST invoice is provided on request for all eligible transactions. Please share your GSTIN." },
      { q: "How long have you been in business?",
        a: "We have been serving [City] since [Year] — over [X] years of trust and quality." },
      { q: "What makes you different from competitors?",
        a: "[Your honest answer — e.g., 'Personal attention, no middleman, lifetime support, transparent pricing']." }
    ]
  };

  // =========================================================
  //  PARENT CATEGORY FALLBACKS
  // =========================================================
  // These run when a sub-category doesn't have its own templates.
  // (Most sub-categories do, but parents catch edge cases.)

  T['healthcare'] = {
    about: [
      "We are committed to your health and well-being. With qualified staff, modern equipment, and patient-first care, we treat every patient with empathy, dignity, and the medical attention they deserve.",
      "[Clinic Name] is led by Dr. [Name], with [X] years of experience in [specialty]. Our practice combines proven medical methods with personal care. Walk-in and appointment-based consultations available.",
      "Trusted by families in [City] for over [X] years, our clinic offers comprehensive healthcare services. We focus on accurate diagnosis, ethical treatment, and clear explanation so patients always understand their care plan.",
      "Health is our priority. At [Clinic Name], we maintain hygiene, follow standard protocols, and use quality medicines/equipment. Affordable consultation, transparent billing — no unnecessary tests, no inflated bills.",
      "Our team of qualified healthcare professionals serves [City] with compassion. We treat each patient like family — patient consultations, clear answers, follow-up calls, and genuine after-care."
    ],
    usp: [
      "Qualified Dr. · [X] yrs experience · Modern equipment · Walk-in & appointment",
      "Honest diagnosis · No unnecessary tests · Transparent billing · Patient-first care",
      "Trusted by 1000+ families in [City] · Affordable fees · Hygienic clinic",
      "Quality care + personal attention + clear explanation — health you can trust.",
      "Modern facilities · Experienced staff · Emergency support · Insurance accepted"
    ],
    faqs: [
      { q: "Do I need an appointment or can I walk in?",
        a: "[Both available — walk-in welcome, but appointments preferred for less waiting time. Book via WhatsApp.]" },
      { q: "What is your consultation fee?",
        a: "Consultation fee is [₹X]. Follow-up within [X days] is [free / discounted]." },
      { q: "Do you accept insurance / cashless treatment?",
        a: "[Yes — empanelled with X, Y, Z insurers. Reimbursement bills also provided. / Currently cash + UPI only]." },
      { q: "What are your clinic timings?",
        a: "Morning: [9 AM – 1 PM], Evening: [5 PM – 8 PM]. Closed on [Sunday / weekly off]." },
      { q: "Do you offer home visits?",
        a: "[Yes — for elderly / emergency patients within X km, fee ₹Y. / Not at the moment.]" },
      { q: "Is your clinic hygienic and follows safety protocols?",
        a: "Yes — we follow strict hygiene, sterilized instruments, and standard medical protocols. Masks and sanitizer available." },
      { q: "What payment methods do you accept?",
        a: "Cash, UPI (PhonePe/GPay/Paytm), [debit/credit card]. Receipt and prescription provided for every visit." },
      { q: "How do I book an appointment?",
        a: "Simply WhatsApp us at [number] with your name and preferred time. We confirm within [X] minutes." }
    ]
  };

  T['financial-services'] = {
    about: [
      "We are AMFI / SEBI registered investment professionals serving [City] since [Year]. Our goal is to help families create wealth through honest, goal-based investment planning — no commission-chasing, no mis-selling, just sound advice.",
      "[Firm Name] is a trusted name in financial services across [City] and nearby areas. With [X]+ years of experience and ₹[Y] crore AUM, we serve [number]+ families with personalised investment planning and lifetime support.",
      "Founded in [Year] by [Founder Name], we specialize in mutual funds, SIP, broking, and tax-efficient investments. Our clients trust us because we put their goals before our income. Education first, investment second.",
      "We are a SEBI / AMFI authorised investment partner with [X] years of industry experience. From your first SIP to your retirement planning, our team handhelds you through every decision — clearly explained, no jargon.",
      "Investment is a journey of trust. At [Firm Name], we treat every rupee of yours like our own — careful, patient, and long-term focused. Free portfolio review, lifetime service, no hidden charges."
    ],
    usp: [
      "AMFI / SEBI registered · [X] yrs experience · ₹[Y] cr AUM · 1000+ happy families",
      "Goal-based investment planning · Tax-efficient strategies · Lifetime free service",
      "No commission games · Transparent advice · Honest recommendations · Local trust",
      "Financial experts in [City] · SIP, MF, broking, insurance — one trusted partner",
      "Free portfolio review · Risk profiling · Personalised plan · 24x7 WhatsApp support"
    ],
    faqs: [
      { q: "Are you registered / authorised by AMFI / SEBI?",
        a: "Yes — AMFI ARN: [ARN-XXXXX]. SEBI authorised person under [Broker Name]. Full credentials available at the office." },
      { q: "Is your service free for investors?",
        a: "Yes, our service is FREE for you. We earn commission directly from the AMC / broker, not from your investment." },
      { q: "What is the minimum investment amount?",
        a: "SIP starts from ₹500 / month. Lumpsum from ₹5,000. We tailor plans to every budget — no minimum portfolio size." },
      { q: "Do you provide tax-saving investment options?",
        a: "Yes — ELSS mutual funds, PPF, NPS, tax-saving FDs, and 80C/80D-eligible insurance. Full tax planning available." },
      { q: "Can I track my investments online?",
        a: "Yes — you get app + web dashboard access (MFCentral / broker app). We also send monthly portfolio reports on WhatsApp." },
      { q: "What if my fund performs badly?",
        a: "We review every portfolio quarterly. If a fund underperforms its benchmark for 2+ quarters, we suggest switching — your call." },
      { q: "Do you also help with insurance and FD?",
        a: "Yes — life insurance, health insurance, FD, bonds, government-backed schemes. One-stop investment partner." },
      { q: "How do I get started?",
        a: "WhatsApp us at [number] for a free portfolio review. Bring your existing statements — we'll show you exactly where you stand." }
    ]
  };

  T['insurance'] = {
    about: [
      "We are authorised insurance advisors representing top insurers in India. With [X] years in the industry, we help families pick the right plan — not the costliest one. Honest recommendations, lifetime claim support.",
      "[Advisor Name] has been advising families in [City] on insurance since [Year]. We specialise in [life / health / motor] insurance and guide you through every step — purchase, premium reminders, and claims.",
      "Insurance is not about premium — it's about cover when you need it. We compare plans across insurers, explain inclusions/exclusions in simple language, and stay with you through claim time.",
      "Authorised advisor for [Insurer 1, 2, 3]. We offer no-pressure consultation, IRDAI-compliant advice, and 24x7 claim assistance. Our motto: 'Sell less, serve more'.",
      "Insurance done right. We help [number]+ families in [City] make confident insurance decisions. Free policy review, claims help, and renewal reminders — all part of our service."
    ],
    usp: [
      "IRDAI-licensed · Authorised for [Insurer 1, 2, 3] · [X] yrs experience · 24x7 claim help",
      "Compare 10+ insurers · Best plan for your need · Honest advice · Lifetime service",
      "Free policy review · No pressure selling · Claim support guaranteed",
      "Tax-saving cover · Family floater · Term plan · Critical illness — all in one place",
      "Trusted insurance partner in [City] · Reminder calls · Claim handheld · No paperwork stress"
    ],
    faqs: [
      { q: "How is your service free for me?",
        a: "Our commission comes from the insurance company — you pay only the standard premium. No hidden advisor fee." },
      { q: "Which insurance companies do you represent?",
        a: "We are authorised for [Bajaj, SBI Life, HDFC Life, ICICI Pru, Tata, Aditya Birla Health] and others." },
      { q: "Can you help me if my claim is rejected?",
        a: "Yes — we guide you through appeal, ombudsman process, and documentation. Claim support is part of our service." },
      { q: "How do I know if I need life or health insurance more?",
        a: "Depends on age, family, income, existing cover. We do a free needs analysis — no obligation to buy." },
      { q: "Can I buy through you online?",
        a: "Yes — completely paperless. Aadhaar + PAN + medical (if needed). Policy in 24–48 hours." },
      { q: "Do you remind me about premium due dates?",
        a: "Yes — we send WhatsApp reminders 7 days and 1 day before due date. No policy lapses on our watch." },
      { q: "What is the difference between term plan and ULIP?",
        a: "Term plan = pure cover, cheap, no return. ULIP = cover + investment, costlier. We help you pick what fits your goal." },
      { q: "How long does it take to settle a claim?",
        a: "Health: cashless 4–6 hours, reimbursement 7–15 days. Life: 7–30 days after document submission. We follow up daily." }
    ]
  };

  T['home-services'] = {
    about: [
      "We are a team of trained [profession] serving [City] for [X]+ years. Our work speaks for itself — neat finish, on-time delivery, fair pricing. Available for both small repairs and big projects.",
      "[Service Name] is run by [Owner Name], a master [profession] with [X] years of hands-on experience. We handle residential and commercial work in [City] and nearby areas. WhatsApp-ready for quick quotes.",
      "Trusted by [number]+ households in [City]. No advance, no inflated bills — we charge only for material + labour. Free inspection before quotation. Same-day service for urgent issues.",
      "Quality matters more than speed — but we deliver both. Our team uses only branded materials, follows safety standards, and cleans up after every job. Satisfaction guaranteed or rework at no extra cost.",
      "Local. Reliable. Affordable. We've been the go-to [profession] for [Locality] residents since [Year]. Genuine work, clear quotes, and follow-up service if anything needs attention later."
    ],
    usp: [
      "[X]+ yrs experience · Same-day service · Branded materials · No advance",
      "Trained team · Fair pricing · On-time delivery · Free quote on WhatsApp",
      "Trusted by 500+ homes in [City] · Quality finish · Clean-up included",
      "Emergency service available · Transparent rates · Bilingual support",
      "No middleman · Direct work · 7-day rework guarantee · Polite team"
    ],
    faqs: [
      { q: "How quickly can you reach my place?",
        a: "Within [30–60 minutes] for emergency. Scheduled visit within [same day or next day] depending on availability." },
      { q: "Do you give an estimate before starting work?",
        a: "Yes — free inspection, written/WhatsApp quote, only then we start. No surprise bills at the end." },
      { q: "Do you take an advance payment?",
        a: "[No advance for small jobs / 20–30% for big projects with material]. Final payment after work + your satisfaction." },
      { q: "What if something breaks again within a few days?",
        a: "Free re-visit within [7 / 15 / 30] days if same issue recurs. Service guarantee is part of our work." },
      { q: "Do you bring your own tools and materials?",
        a: "Tools — yes, always. Materials — we bring branded ones, or you can purchase. Both options available." },
      { q: "Do you work on Sundays / holidays?",
        a: "[Yes, by appointment / Sunday off but emergency calls accepted]. WhatsApp anytime for booking." },
      { q: "What payment modes do you accept?",
        a: "Cash, UPI (PhonePe / GPay / Paytm), bank transfer. Bill provided on request." },
      { q: "Do you also do commercial / office work?",
        a: "[Yes — shop, office, factory, society — all locations covered. Bulk quotes available.]" }
    ]
  };

  T['automotive'] = {
    about: [
      "We are [Shop Name], an automotive specialist in [City] since [Year]. From routine servicing to engine overhauls, our team of trained mechanics handles every job with skill and care. Trusted by [number]+ vehicle owners.",
      "Run by [Owner Name], a master mechanic with [X] years of experience, [Shop Name] serves drivers across [City]. We use genuine parts, follow manufacturer specs, and explain repairs clearly — no surprise bills.",
      "Quality service, fair pricing, and honest advice — three pillars of [Shop Name] for over [X] years. Whether it's your [bike / car / commercial vehicle], we treat it like our own. Pickup and drop available within [X] km.",
      "Multi-brand service centre with experienced technicians, advanced tools, and transparent billing. We don't recommend unnecessary repairs — only what your vehicle actually needs. Walk in or book on WhatsApp.",
      "Family-owned auto workshop since [Year]. Our reputation is built on word-of-mouth — and that's how we want it. Honest mechanics, genuine spares, on-time delivery. Test ride after every service, free."
    ],
    usp: [
      "Master mechanic · [X]+ yrs experience · Genuine parts · Transparent billing",
      "Multi-brand service · Free pickup/drop · Test ride after every service",
      "No false repairs · Original spares · 30-day workmanship warranty",
      "Same-day service for routine work · Detailed inspection report on WhatsApp",
      "Trusted by 1000+ vehicle owners in [City] · Fair quotes · Genuine work"
    ],
    faqs: [
      { q: "How long does a routine service take?",
        a: "Standard service: [3–4 hours]. Major service / repair: [1–3 days] depending on parts availability." },
      { q: "Do you provide pickup and drop?",
        a: "Yes — free pickup/drop within [X km] in [City]. Call/WhatsApp 1 hour before pickup needed." },
      { q: "Do you use genuine / OEM spare parts?",
        a: "Yes — we use OEM or company-recommended parts. Aftermarket option only if customer requests, with disclosure." },
      { q: "What's the price for a basic service?",
        a: "Bike service: from ₹[X]. Car service: from ₹[Y]. Final cost depends on model and parts replaced. Free estimate before work." },
      { q: "Is there a warranty on repairs?",
        a: "Yes — [30 days / 1000 km] on workmanship. Parts carry manufacturer warranty as per their policy." },
      { q: "Can I get a written estimate before approval?",
        a: "Absolutely — we send a detailed itemised quote on WhatsApp. Work starts only after your approval." },
      { q: "Do you accept insurance / cashless claim?",
        a: "[Yes — empanelled with X, Y, Z insurance companies. / We provide all bills + claim assistance for reimbursement.]" },
      { q: "Do you also sell accessories and tyres?",
        a: "[Yes — full range available. / We can source within 24 hours.] Quote on WhatsApp with photo." }
    ]
  };

  T['food-beverage'] = {
    about: [
      "Welcome to [Restaurant Name] — bringing authentic [cuisine] flavours to [City] since [Year]. Our chefs use traditional recipes, fresh ingredients, and pure ghee/oil to serve food that tastes like home.",
      "[Restaurant Name] is a family-run [restaurant / dhaba / café] known for [signature dish] and warm hospitality. Comfortable seating, quick service, and AC dining make us a favourite for families and friends.",
      "Famous for our [signature dish] across [City], [Restaurant Name] has been serving smiles since [Year]. Hygiene-first kitchen, freshly cooked food, and reasonable prices keep our customers coming back.",
      "From quick bites to full meals, we serve a wide menu of [veg / non-veg / Indian / Chinese / Continental] dishes. Dine-in, takeaway, and home delivery available. Special party orders accepted with advance notice.",
      "Authentic taste. Hygienic kitchen. Friendly staff. Reasonable prices. That's [Restaurant Name] — your neighbourhood favourite for [meals / snacks / sweets / drinks] since [Year]."
    ],
    usp: [
      "Pure ghee · Fresh ingredients · Family recipes · Hygienic kitchen",
      "Famous for [signature dish] · Dine-in + takeaway + Swiggy/Zomato delivery",
      "AC dining · Family-friendly · Quick service · Reasonable prices",
      "Veg + Non-veg menu · Party orders · Home catering for events",
      "Trusted by 1000+ regulars · Word-of-mouth famous · Open till [late hours]"
    ],
    faqs: [
      { q: "What are your timings?",
        a: "Open from [11 AM to 11 PM] daily. Kitchen closes [30 min before closing]. Closed on [weekly off, if any]." },
      { q: "Do you offer home delivery?",
        a: "Yes — direct delivery within [X km] free above ₹[Y] order. Also available on Swiggy and Zomato." },
      { q: "Do you have AC / family seating?",
        a: "Yes — AC dining, separate family section, and outdoor seating available. Reservation possible for groups." },
      { q: "Do you have a kids menu / Jain food / pure veg options?",
        a: "[Yes — kids menu, Jain food, Jain-without-onion-garlic, pure veg sections all available]." },
      { q: "Can I order for parties / events?",
        a: "Yes — party orders accepted with [4–6 hours] notice. Bulk discounts on orders above ₹[X]." },
      { q: "What's your signature / must-try dish?",
        a: "Our [signature dish] is the most-loved. Also try [item 1] and [item 2] — house specials." },
      { q: "Do you serve breakfast / late-night food?",
        a: "[Yes — breakfast from 8 AM / Late night till midnight on weekends.]" },
      { q: "Do you provide GST bill?",
        a: "Yes — GST invoice provided for all orders above ₹[X]. Please share GSTIN if applicable." }
    ]
  };

  T['retail-shopping'] = {
    about: [
      "[Shop Name] is a trusted retail destination in [Locality], [City] since [Year]. We stock genuine brands at fair prices, offer friendly help in selection, and stand behind every product we sell.",
      "Family-run retail shop with [X] years in business. Wide variety, quality products, and personal attention from owner [Name]. Your satisfaction is our reputation — exchange/return policy is fair and clear.",
      "From everyday needs to special purchases, [Shop Name] has been the go-to choice in [Locality]. Bulk discounts, festival offers, and home delivery within [X] km make shopping with us easy.",
      "We believe local shops should feel like home — that's why we know our regulars by name and remember their preferences. New customers welcome too — drop by, browse, ask anything. No pressure to buy.",
      "Genuine products. Fair pricing. Honest billing. [Shop Name] has earned the trust of [number]+ customers in [City] through consistent quality and friendly service since [Year]."
    ],
    usp: [
      "100% genuine products · Bill + warranty on every purchase · Fair pricing",
      "Wide variety · Latest stock · Festival offers · Bulk discounts available",
      "Trusted local shop since [Year] · Home delivery · Easy exchange/return",
      "Personal selection help · No pressure · Free advice from owner",
      "Branded + local options · Budget-friendly · WhatsApp-ready for queries"
    ],
    faqs: [
      { q: "Do you offer home delivery?",
        a: "Yes — free delivery within [X km] for orders above ₹[Y]. Outside [City], courier charges apply." },
      { q: "Do you have an exchange / return policy?",
        a: "Yes — [7–15 days] exchange with bill, in unused condition. Return policy as per product type and bill terms." },
      { q: "Are your products genuine / branded?",
        a: "Yes — only authentic stock from authorised distributors. Bill + warranty card provided for every branded item." },
      { q: "Do you give bulk / wholesale discount?",
        a: "Yes — discounts on orders above ₹[X] or for B2B purchases. WhatsApp us your list for a custom quote." },
      { q: "What payment methods do you accept?",
        a: "Cash, UPI (PhonePe / GPay / Paytm), debit/credit cards. EMI available on cards above ₹[X]." },
      { q: "Do you stock the latest models / collections?",
        a: "Yes — new arrivals every [week / month]. Follow us on WhatsApp for new-stock alerts and festival offers." },
      { q: "Do you provide GST invoice?",
        a: "Yes — GST bill on request. Please share GSTIN for B2B purchases or claims." },
      { q: "What if my product has a manufacturing defect?",
        a: "Bring it within warranty period — we coordinate with the brand / service centre directly. You don't need to chase anyone." }
    ]
  };

  T['beauty-wellness'] = {
    about: [
      "[Salon Name] is a premium beauty and wellness destination in [Locality], [City]. Trained professionals, hygienic tools, branded products, and a relaxing ambience make every visit a treat for our clients.",
      "Founded by [Owner Name] with [X] years of professional experience, [Salon Name] offers a full range of beauty and grooming services. Walk-in welcome, appointments preferred for guaranteed time.",
      "We believe everyone deserves to feel pampered. [Salon Name] combines skill, hygiene, and warmth — disposable tools, sanitised stations, and trained staff who listen before they style.",
      "[Salon Name] has been the trusted choice for [bridal makeup / hair styling / spa services] in [City] since [Year]. Quality products, latest techniques, and a friendly team — that's our promise.",
      "Look good. Feel better. At [Salon Name] we deliver both. From quick grooming to full bridal package, our skilled team uses branded products and follows global hygiene standards."
    ],
    usp: [
      "Trained professionals · Branded products · Hygienic tools · Modern ambience",
      "Bridal packages · Pre-wedding services · Hair, skin, makeup — all under one roof",
      "Walk-in welcome · AC interiors · Disposable kits · Family-friendly",
      "[X]+ yrs experience · Bilingual staff · Fair pricing · Loyalty offers",
      "Trusted by 500+ clients in [City] · Online booking · WhatsApp-ready"
    ],
    faqs: [
      { q: "Do I need an appointment?",
        a: "Walk-ins welcome. Appointments recommended for [bridal / colour / spa] to avoid waiting. Book via WhatsApp." },
      { q: "What are your timings?",
        a: "Open from [10 AM – 9 PM] all days. [Sunday off / Open Sundays with appointment]." },
      { q: "Do you offer home / bridal services?",
        a: "[Yes — bridal makeup & pre-wedding services at home. Pricing on call.]" },
      { q: "What products do you use?",
        a: "We use [L'Oréal / Schwarzkopf / Lakmé / VLCC / O3+] branded products. Sensitive skin alternatives available." },
      { q: "Are your tools and stations hygienic?",
        a: "Yes — disposable single-use items for every client. Tools sanitised, stations cleaned after each service." },
      { q: "Do you offer package deals?",
        a: "Yes — bridal packages, monthly memberships, pre-paid combos. WhatsApp us for the rate card." },
      { q: "Is there a kids / family section?",
        a: "[Yes — separate family section, kids haircut, ladies-only floor]." },
      { q: "Do you accept cards / UPI?",
        a: "Yes — cash, UPI, debit/credit cards. Online booking option also available." }
    ]
  };

  T['education'] = {
    about: [
      "[Institute Name] is dedicated to quality education and student success. With experienced faculty, structured curriculum, regular tests, and parent updates, we help students achieve their academic goals.",
      "Run by [Founder Name], an educator with [X] years of teaching experience, [Institute Name] focuses on concept clarity, regular practice, and individual attention to every student.",
      "Since [Year], we have helped [number]+ students improve their grades, crack entrance exams, and develop confidence. Small batches, doubt sessions, and weekly tests are part of our standard.",
      "Education is not just about marks — it's about understanding. At [Institute Name], we teach with patience, test for clarity, and guide every student personally. Demo class is always free.",
      "Our mission is to make learning easy, enjoyable, and effective. [Institute Name] offers [courses] with modern teaching methods, study material, and one-on-one mentoring whenever needed."
    ],
    usp: [
      "Experienced faculty · Small batches · Weekly tests · Free demo class",
      "Concept clarity · Individual attention · Doubt sessions · Parent updates",
      "[X]+ yrs experience · [Number]+ students · Proven results · Affordable fees",
      "Modern teaching · Study material included · Online + offline mode",
      "Personalised mentoring · Career guidance · Scholarship test available"
    ],
    faqs: [
      { q: "Can I attend a demo / trial class?",
        a: "Yes — free demo class. WhatsApp us to book a slot in your preferred batch." },
      { q: "What is the batch size and timing?",
        a: "We keep batches of [10–20 students] for personal attention. Timings: [morning / afternoon / evening] batches available." },
      { q: "Do you provide study material and tests?",
        a: "Yes — printed material, weekly tests, monthly assessments, and detailed performance reports for parents." },
      { q: "What are your fees and payment options?",
        a: "Fees: [₹X / month or ₹Y / course]. Monthly / quarterly / one-time options. Discount for siblings / advance payment." },
      { q: "Do you offer online classes?",
        a: "[Yes — recorded + live online classes available. / Currently offline only. / Hybrid model available.]" },
      { q: "What is your success rate?",
        a: "Our students have a [X%] pass rate in [board exams / entrance tests]. Last year [number] students cleared [specific exam]." },
      { q: "Do you have qualified teachers?",
        a: "Yes — all faculty are [M.A. / M.Sc. / Engineers / Subject experts] with [X+] years teaching experience." },
      { q: "What if I miss a class?",
        a: "Missed-class notes shared on WhatsApp. Doubt-clearing session available on Saturdays / Sundays." }
    ]
  };

  T['professional-services'] = {
    about: [
      "[Firm Name] is a professional services firm in [City] established in [Year]. Led by [Founder Name], we serve clients with expertise, integrity, and personalised attention across [practice areas].",
      "We are a team of qualified professionals with [X]+ years of combined experience. Confidentiality, clear communication, and timely delivery are non-negotiable in our practice.",
      "Trusted by [number]+ clients across [City] and beyond, [Firm Name] offers end-to-end professional services with transparent fees and proactive updates. Free initial consultation available.",
      "Our approach is simple — listen carefully, advise honestly, deliver on time. [Firm Name] combines technical expertise with a personal touch, ensuring every client feels heard and supported.",
      "From individual matters to corporate engagements, we provide professional services with the highest ethical standards. Fixed-fee packages and milestone-based billing — no surprise charges."
    ],
    usp: [
      "Qualified professionals · [X]+ yrs experience · Transparent fees · Confidential",
      "Free initial consultation · Fixed-fee packages · Milestone-based billing",
      "End-to-end service · Personal attention · WhatsApp-ready · No middleman",
      "Trusted by [number]+ clients · Proven track record · Multi-domain expertise",
      "Bilingual service · Documentation handheld · Lifetime client support"
    ],
    faqs: [
      { q: "Do you offer a free initial consultation?",
        a: "Yes — first 15–30 minute consultation is free, in person or on call. WhatsApp us to schedule." },
      { q: "What are your fees / pricing model?",
        a: "We offer [fixed-fee packages / hourly billing / milestone-based] depending on the matter. Quote shared after initial discussion." },
      { q: "Is my information kept confidential?",
        a: "Absolutely — strict confidentiality is part of our professional ethics. No client details are shared without your written consent." },
      { q: "How long do you take for [typical engagement]?",
        a: "Standard cases: [X days / weeks]. Complex matters: [Y weeks]. We commit to timelines in writing." },
      { q: "Do you handle work across cities / states / online?",
        a: "Yes — we handle [pan-India / inter-state] matters, with online consultation, e-filing, and courier-based documentation." },
      { q: "What if I'm not satisfied with the service?",
        a: "We address concerns transparently. Refund / re-work as per our engagement letter — clear terms upfront." },
      { q: "Do you provide GST invoice / TDS certificate?",
        a: "Yes — proper GST invoice for every engagement. TDS certificate provided after each payment cycle." },
      { q: "How do I get started?",
        a: "WhatsApp us at [number] with a brief about your matter. We respond within [hours] and schedule a consultation." }
    ]
  };

  // =========================================================
  //  HEALTHCARE SUB-CATEGORIES
  // =========================================================

  T['doctor'] = {
    about: [
      "Dr. [Name], MBBS [+ specialty], has been practicing in [City] since [Year]. With [X] years of experience and [Number]+ patients treated, our clinic offers honest diagnosis, evidence-based treatment, and patient-friendly consultation.",
      "[Clinic Name] is led by Dr. [Name], a qualified [General Physician / Specialist] focused on accurate diagnosis and personalised treatment. Modern equipment, hygienic premises, and clear explanation make every consultation worthwhile.",
      "Trusted family doctor for [number]+ households in [Locality]. Dr. [Name] takes time to listen, explains every prescription, and avoids unnecessary tests. Consultation by appointment as well as walk-in.",
      "Our mission is preventive care, not just treatment. Dr. [Name] specialises in [chronic diseases / lifestyle medicine / general medicine] and educates patients on diet, exercise, and follow-up — not just medicines.",
      "Compassionate care, ethical practice, affordable consultation. Dr. [Name] has been the trusted choice for families in [City] for [X] years. WhatsApp-ready for second opinions and follow-up queries."
    ],
    usp: [
      "MBBS qualified · [X]+ yrs experience · Honest diagnosis · No unnecessary tests",
      "Specialty: [General Physician / Cardiologist / Pediatrician / etc.]",
      "Modern clinic · Affordable fees · Walk-in & appointment · Hygienic premises",
      "Patient-friendly consultation · Bilingual · Follow-up calls included",
      "Trusted by [number]+ families · Empanelled with [insurance companies]"
    ],
    faqs: [
      { q: "What is the doctor's qualification and specialty?",
        a: "Dr. [Name], [MBBS / MD / MS] from [College]. Specialty: [General Medicine / Pediatrics / Cardiology / etc.]. Registration: [State Medical Council No.]" },
      { q: "What is your consultation fee?",
        a: "First consultation: ₹[X]. Follow-up within [15 days]: ₹[Y] / free. Family discounts available." },
      { q: "Do I need an appointment or can I walk in?",
        a: "Both available. Appointments preferred to avoid waiting. Book on WhatsApp [number]." },
      { q: "What are your clinic timings?",
        a: "Morning: [9 AM – 1 PM] · Evening: [5 PM – 9 PM]. Closed on [Sunday] except emergencies." },
      { q: "Do you accept cashless insurance?",
        a: "[Yes — empanelled with Star Health, HDFC Ergo, Niva Bupa, ICICI Lombard, etc. / Cash + UPI + reimbursement bills only]." },
      { q: "Do you offer home visits or video consultation?",
        a: "[Yes — home visit ₹[X] within 5 km. Video consult ₹[Y] anywhere. / Currently in-clinic only.]" },
      { q: "How long does a consultation typically take?",
        a: "First consultation: 15–20 minutes. Follow-up: 5–10 minutes. We don't rush — your concerns are heard fully." },
      { q: "How do I get my prescription / reports later?",
        a: "Digital prescription sent on WhatsApp. Reports collected at clinic or shared digitally with consent." }
    ]
  };

  T['pharmacy'] = {
    about: [
      "[Pharmacy Name] has been serving [City] since [Year] with genuine medicines, fast service, and qualified pharmacist support. Open [extended hours] for emergency and routine needs.",
      "We are a licensed pharmacy stocking medicines from all major brands — generic, branded, and Ayurvedic. Doctor-recommended substitutes available with full transparency on pricing.",
      "Run by qualified pharmacist [Name], [Pharmacy Name] is committed to authentic medicines at fair prices. Home delivery, automatic monthly refills, and elderly-friendly service.",
      "Trusted neighbourhood pharmacy with home delivery, billing transparency, and 24x7 availability for emergencies. We stock chronic care, diabetic, BP, thyroid, and lifestyle medicines.",
      "Genuine medicines from authorised distributors only. Bill, MRP, and expiry checked at every dispense. [Pharmacy Name] has been the trusted choice in [Locality] for [X] years."
    ],
    usp: [
      "Licensed pharmacy · Qualified pharmacist · Genuine medicines · MRP guaranteed",
      "Home delivery within [X km] · Free above ₹[Y] · Same-day for urgent",
      "Generic + branded options · Best price for chronic medication",
      "Open [extended hours] · Emergency 24x7 phone support",
      "Auto-refill reminders · WhatsApp ordering · Senior citizen discount"
    ],
    faqs: [
      { q: "Do you provide home delivery?",
        a: "Yes — free home delivery within [X km] for orders above ₹[Y]. Just WhatsApp prescription photo." },
      { q: "Are all your medicines genuine?",
        a: "100% — sourced only from authorised distributors with full traceability. Bill + batch + expiry visible on every receipt." },
      { q: "Can I get a discount on long-term / chronic medication?",
        a: "Yes — [5–10%] standing discount on chronic prescriptions (BP, diabetes, thyroid). Monthly auto-refill option." },
      { q: "Do you stock branded as well as generic medicines?",
        a: "Yes — we keep both. Pharmacist suggests generic equivalents (if available) so you can choose by cost or doctor's note." },
      { q: "What are your timings?",
        a: "[8 AM – 11 PM] daily. Emergency call available 24x7 — [number]. Closed only on [specific days]." },
      { q: "Do you accept insurance / cashless?",
        a: "[Tax-saving 80D bills provided. Cashless for empanelled hospitals only. UPI / card / cash all accepted.]" },
      { q: "Can I send my prescription on WhatsApp?",
        a: "Yes — photo of prescription on WhatsApp [number]. We confirm availability and total bill before delivery." },
      { q: "Do you also stock Ayurvedic / nutritional supplements?",
        a: "Yes — Patanjali, Himalaya, Dabur, Zandu, plus protein, multivitamin, calcium, B12 supplements." }
    ]
  };

  T['dentist'] = {
    about: [
      "Dr. [Name], BDS / MDS, has been treating patients at [Clinic Name] since [Year]. From routine cleaning to complex implants and orthodontics, we use modern equipment and follow strict sterilisation protocols.",
      "Painless dentistry, advanced equipment, and patient-friendly atmosphere — that's [Clinic Name]. Specialising in cosmetic dentistry, RCT, implants, braces, and pediatric dental care.",
      "[Clinic Name] is a multi-specialty dental clinic with experienced dentists and the latest digital X-ray, RVG, and rotary endo systems. EMI options available for big treatments.",
      "Quality dental care without the fear factor. Our calm environment, gentle approach, and clear pricing make [Clinic Name] the preferred choice for families in [City].",
      "Comprehensive dental services — from teeth cleaning to full mouth rehabilitation. Free consultation, treatment plan with cost upfront, and EMI options for braces, implants, and crowns."
    ],
    usp: [
      "BDS / MDS qualified · Modern equipment · Painless dentistry · Sterilised tools",
      "Implants · Braces · RCT · Cleaning · Cosmetic — all under one roof",
      "Free first consultation · EMI option · Insurance accepted",
      "Pediatric-friendly · Family discount · Bilingual staff",
      "Latest tech: digital X-ray · RVG · Laser · Rotary endo"
    ],
    faqs: [
      { q: "Is the first consultation free?",
        a: "Yes — first consultation including basic examination is free. X-ray, if needed, ₹[X]." },
      { q: "What is the cost of [RCT / cleaning / filling / braces]?",
        a: "Cleaning: ₹[X]. Filling: ₹[Y]. RCT: ₹[Z]. Braces / implants: estimate after exam. EMI available." },
      { q: "Is RCT painful?",
        a: "No — local anesthesia makes the procedure painless. Mild soreness for 1–2 days is normal, manageable with painkiller." },
      { q: "How many sittings are needed for [RCT / braces]?",
        a: "Most RCTs complete in 1–2 sittings. Braces: 12–24 months with monthly visits. Implants: 2–3 visits over 3–6 months." },
      { q: "Do you accept dental insurance / cashless?",
        a: "[Yes — empanelled with X, Y. Reimbursement bills provided for all insurers. / Cash + UPI only currently.]" },
      { q: "Is the clinic hygienic / sterilized?",
        a: "Yes — autoclave sterilisation, disposable gloves, masks, single-use needles. Hygiene is non-negotiable." },
      { q: "Do you treat children?",
        a: "Yes — pediatric dental care with calming approach, kid-friendly chairs, fluoride treatments, and habit counselling." },
      { q: "What are your timings?",
        a: "[10 AM – 1 PM, 5 PM – 9 PM] all days. [Sunday by appointment only / Closed Sunday]." }
    ]
  };

  T['pathology-lab'] = {
    about: [
      "[Lab Name] is a NABL-accredited / certified pathology lab serving [City] since [Year]. Accurate reports, fast turnaround, and patient-friendly home sample collection are our trademarks.",
      "Run under the guidance of qualified pathologist Dr. [Name], we offer the complete range of blood tests, urine, stool, X-ray, ECG, ultrasound, and specialised tests at fair pricing.",
      "Modern lab with auto-analysers, trained technicians, and digital reporting. WhatsApp-delivered reports same day for most tests, with doctor consultation if values are flagged.",
      "Home sample collection within [X km], reports on WhatsApp, and pricing 20–30% lower than chain labs. [Lab Name] is the trusted diagnostic partner for hundreds of families in [City].",
      "Quality you can trust — [Lab Name] follows international quality standards, internal QC daily, and external audit yearly. Empanelled with major insurance companies for cashless tests."
    ],
    usp: [
      "NABL accredited · Accurate reports · Digital + printed copy · Same-day for most tests",
      "Home sample collection · Free above ₹[X] · WhatsApp report delivery",
      "Qualified pathologist · Modern auto-analyser · QC daily",
      "Affordable pricing · Senior citizen discount · Health package combos",
      "Empanelled with insurance · TPA cashless · Doctor referral discount"
    ],
    faqs: [
      { q: "Do you offer home sample collection?",
        a: "Yes — free within [X km] for orders above ₹[Y]. Trained phlebotomist with disposable kit. Book on WhatsApp." },
      { q: "How soon will I get the report?",
        a: "Routine blood tests: same day by evening. Special tests: [24–72 hours]. WhatsApp report + printed copy." },
      { q: "Are your reports accurate / NABL-accredited?",
        a: "Yes — [NABL accredited / ISO certified]. Internal QC twice daily, external audit yearly. Pathologist-verified reports." },
      { q: "What is the cost of [CBC / lipid / thyroid / vitamin D]?",
        a: "Common tests: CBC ₹[X], Lipid ₹[Y], Thyroid ₹[Z], Vitamin D ₹[W]. Discount on full health checkup packages." },
      { q: "Do you accept insurance / cashless?",
        a: "Yes — empanelled with [insurance / TPA list]. Reimbursement bills provided. ID + doctor's prescription required." },
      { q: "Do I need to come fasting?",
        a: "Lipid profile, blood sugar (fasting), and a few others need 10–12 hours fasting. We confirm at booking — no surprises." },
      { q: "Do you have a doctor for explanation of reports?",
        a: "Yes — free phone consultation with our pathologist for abnormal findings. Detailed explanation in plain language." },
      { q: "Do you offer health checkup packages?",
        a: "Yes — Basic (₹[X]), Comprehensive (₹[Y]), Senior citizen (₹[Z]), Women's wellness (₹[W])." }
    ]
  };

  T['physiotherapist'] = {
    about: [
      "[Clinic Name] is led by qualified physiotherapist [Name] (BPT / MPT) with [X] years of experience treating sports injuries, post-surgery rehab, back pain, frozen shoulder, and stroke recovery.",
      "Modern physiotherapy clinic equipped with TENS, ultrasound, IFT, traction, and exercise gym. Customised treatment plans, home visits, and post-surgery rehab specialty.",
      "We believe in evidence-based physiotherapy — assessment first, exercise-focused therapy, and gradual progress tracking. No quick-fix promises, only proven recovery protocols.",
      "Pain relief, mobility restoration, and lifestyle correction — [Clinic Name] is the trusted choice for orthopedic and neurological patients in [City]. Insurance accepted.",
      "From geriatric care to athletic injury, we customise each session. [Number]+ patients recovered fully. Home visits available for bed-ridden and elderly patients."
    ],
    usp: [
      "BPT / MPT qualified · [X]+ yrs experience · Modern equipment · Home visits",
      "Sports injury · Post-op rehab · Back/neck pain · Stroke recovery — all covered",
      "Customised plan · Progress tracking · Diet & posture guidance",
      "TENS · Ultrasound · IFT · Traction · Manual therapy",
      "Insurance accepted · Affordable per-session rates · Family discount"
    ],
    faqs: [
      { q: "What conditions do you treat?",
        a: "Back pain, neck pain, frozen shoulder, knee pain, sports injury, post-op rehab, stroke, paralysis, pediatric and geriatric physio." },
      { q: "How many sessions will I need?",
        a: "Depends on condition. Average 8–15 sessions. We re-assess every 5 sessions and tell you exactly how much more is needed." },
      { q: "What is the per-session fee?",
        a: "Clinic: ₹[X] / session. Home visit: ₹[Y] / session. Package discounts on 10-session pre-booking." },
      { q: "Do you offer home visits?",
        a: "Yes — within [X km] for bed-ridden / post-op / elderly patients. Slot booking on WhatsApp." },
      { q: "Will physiotherapy actually cure my pain?",
        a: "For most musculoskeletal issues — yes, with consistent sessions and home exercises. Surgical cases need realistic expectations." },
      { q: "Do you accept insurance?",
        a: "[Yes — most major insurance covers physio under hospitalisation / post-op. We provide proper bills. Cashless empanelled with X, Y.]" },
      { q: "Do you give a written exercise plan?",
        a: "Yes — printed / WhatsApp exercise plan with video demos. Compliance is half the recovery." },
      { q: "What if I miss a session?",
        a: "Reschedule freely with [24 hour] notice — no charge. No-show: session charged as per package terms." }
    ]
  };

  T['hospital'] = {
    about: [
      "[Hospital Name] is a multi-specialty hospital in [City] established in [Year]. Equipped with modern ICU, OT, diagnostic services, and a team of specialists across [departments].",
      "[X]-bedded hospital with 24x7 emergency, qualified doctors, NABH-compliant protocols, and patient-centric care. Cashless insurance accepted with most major insurers.",
      "Founded by Dr. [Name], our hospital combines clinical excellence with affordable care. Specialty departments include [list specialties]. Ambulance service 24x7 within [X km].",
      "Trusted by [number]+ patients since [Year], [Hospital Name] is known for ethical practice, transparent billing, and personalised attention. Visiting consultants from leading metros once a month.",
      "Patient safety, quality care, and family-friendly environment — three pillars of [Hospital Name]. Modern equipment, trained nursing, and round-the-clock medical officer on duty."
    ],
    usp: [
      "[X]-bedded multi-specialty · 24x7 emergency · ICU · OT · Modern equipment",
      "Cashless insurance · [List of empanelled insurers]",
      "Specialty depts: [Ortho, Gynae, Pediatric, Cardio, etc.]",
      "Ambulance 24x7 · TPA assistance · Pharmacy in-house · Lab in-house",
      "Trusted by [number]+ patients · Senior citizen care · Ethical billing"
    ],
    faqs: [
      { q: "What specialties do you offer?",
        a: "[General Surgery, Gynaecology, Pediatrics, Orthopedics, ENT, Cardiology, Neurology, etc. — list yours]" },
      { q: "Do you provide 24x7 emergency service?",
        a: "Yes — 24x7 emergency with ambulance, on-call doctors, and casualty officer always available." },
      { q: "Is your hospital cashless / insurance empanelled?",
        a: "Yes — empanelled with [list of insurers]. TPA desk for assistance. Reimbursement bills provided for non-empanelled." },
      { q: "What are visiting hours for patients?",
        a: "General ward: [10 AM – 12 noon, 5 PM – 7 PM]. ICU: 1 visitor at a time, [X timings]. Special permission for emergencies." },
      { q: "Do you have an in-house pharmacy and lab?",
        a: "Yes — 24x7 pharmacy and diagnostic lab. No need to step out for medicines or routine tests." },
      { q: "How is your billing — transparent?",
        a: "Yes — itemised bill with rate card, no hidden charges. Senior citizen, BPL, and corporate discounts available." },
      { q: "Do you have ambulance service?",
        a: "Yes — 24x7 ambulance within [X km]. Cardiac ambulance for emergencies. Charges as per distance, ₹[Y]/km approx." },
      { q: "Can I get a second opinion / visiting specialist?",
        a: "Yes — second opinion consultation available. Visiting consultants from [metro hospitals] monthly. Book in advance." }
    ]
  };

  T['ayurveda'] = {
    about: [
      "Vaidya / Dr. [Name], BAMS, has been practicing classical Ayurveda since [Year] at [Clinic Name]. We focus on root-cause treatment of chronic ailments through customised herbal medicines and lifestyle correction.",
      "[Clinic Name] offers authentic Panchakarma therapies, herbal medicines, and personalised diet plans. We treat chronic diseases like arthritis, diabetes, skin issues, and digestive disorders.",
      "Ayurveda is not just medicine — it's a way of life. At [Clinic Name], we combine ancient wisdom with modern diagnosis to offer treatments that heal, not just suppress symptoms.",
      "Genuine herbs, classical formulations, and experienced Vaidyas — that's our promise. Online consultations and medicine delivery available pan-India. WhatsApp-based follow-up support.",
      "From back pain to weight management, lifestyle disorders to fertility — [Clinic Name] has helped hundreds find relief through Ayurveda. Free first consultation for new patients."
    ],
    usp: [
      "BAMS qualified · Classical Ayurveda · [X]+ yrs experience · Panchakarma facility",
      "Root-cause treatment · Customised herbal medicines · Diet & lifestyle guidance",
      "Chronic disease specialty · Diabetes · Arthritis · Skin · Digestive issues",
      "Genuine herbs · GMP-certified medicines · No side effects",
      "Online consultation · Medicine delivery pan-India · Free first consult"
    ],
    faqs: [
      { q: "What conditions do you treat with Ayurveda?",
        a: "Chronic pain (arthritis, back, knee), skin issues (psoriasis, eczema), digestive (IBS, acidity), diabetes, hypertension, fertility, stress, weight management." },
      { q: "How long does Ayurvedic treatment take to show results?",
        a: "Acute issues: 1–2 weeks. Chronic conditions: 1–3 months. Patience and consistency are key — Ayurveda treats the root, not just symptoms." },
      { q: "Are your medicines GMP-certified and safe?",
        a: "Yes — only GMP-certified, government-approved herbal medicines. No heavy metals, no chemicals. Safe for long-term use." },
      { q: "What is Panchakarma and do you offer it?",
        a: "Yes — full Panchakarma facility for detoxification: Vamana, Virechana, Basti, Nasya, Raktamokshana. 7–21 days program with stay option." },
      { q: "Can I continue allopathic medicines along with Ayurveda?",
        a: "Yes — we work alongside your allopathic doctor. We never ask to stop ongoing medicines without medical supervision." },
      { q: "Do you offer online consultation?",
        a: "Yes — video consultation, prescription on WhatsApp, medicine couriered pan-India. Charge: ₹[X]." },
      { q: "What is the consultation fee?",
        a: "First consultation: ₹[X] (30–45 mins). Follow-up: ₹[Y]. Includes detailed Prakriti analysis and personalised plan." },
      { q: "Do you provide diet plans?",
        a: "Yes — every patient gets a detailed diet plan in Hindi / English. Includes Dos, Don'ts, daily routine (Dinacharya), and seasonal adjustments." }
    ]
  };

  T['homeopathy'] = {
    about: [
      "Dr. [Name], BHMS, has been practicing classical Homeopathy since [Year]. We treat chronic illnesses with individualised remedies — every patient gets a personalised case analysis.",
      "[Clinic Name] specialises in chronic disease management through Homeopathy — skin diseases, allergies, hair fall, kidney stones, thyroid, PCOD, migraine, and more.",
      "Gentle, safe, and side-effect-free — Homeopathy works deeply when prescribed correctly. Dr. [Name] takes detailed case history and offers long-term cure, not temporary suppression.",
      "Online consultation across India. Medicine couriered to your doorstep. Follow-up calls and progress tracking through WhatsApp. No artificial chemicals, no steroids.",
      "Trusted by [number]+ patients for chronic ailments. We treat the person, not just the disease — your symptoms, sleep, mood, and lifestyle all matter for the right remedy."
    ],
    usp: [
      "BHMS qualified · [X]+ yrs experience · Classical Homeopathy · Detailed case analysis",
      "Chronic disease specialty · Skin · Hair · Allergy · PCOD · Thyroid · Migraine",
      "No side effects · Safe for kids & elderly · Gentle long-term cure",
      "Online consultation · Medicine couriered pan-India · WhatsApp follow-up",
      "Empanelled with [insurance] · OPD reimbursement · Affordable fees"
    ],
    faqs: [
      { q: "What conditions does Homeopathy treat best?",
        a: "Allergies, asthma, eczema, psoriasis, hair fall, thyroid, PCOD, migraine, IBS, kidney stones, pediatric issues, ADHD, anxiety." },
      { q: "How long does Homeopathy take to work?",
        a: "Acute conditions: hours to days. Chronic conditions: 3–6 months for visible change, 6–18 months for lasting cure." },
      { q: "Are Homeopathic medicines safe for children and pregnant women?",
        a: "Yes — Homeopathy is safe across all ages. Children, infants, pregnant women, and elderly all tolerate it without side effects." },
      { q: "Can I take Homeopathy with allopathic medicines?",
        a: "Yes — no interaction. We never ask you to suddenly stop allopathic medicines. Gradual tapering as your condition improves." },
      { q: "What is your consultation fee?",
        a: "First consultation: ₹[X] (45–60 mins for detailed case taking). Follow-up: ₹[Y] (15–20 mins)." },
      { q: "Do you offer online consultation?",
        a: "Yes — video / phone consultation. Medicines couriered to your address. WhatsApp updates and follow-up." },
      { q: "Why does Homeopathy take so long?",
        a: "It treats the root cause, not just symptoms. Suppression vs cure — slow but lasting. Chronic disease that took years cannot vanish in weeks." },
      { q: "Are your medicines pure and from where?",
        a: "Yes — we use only [SBL / Schwabe / Reckeweg / Boiron] standardised medicines. Globally accepted brands, lab-tested potency." }
    ]
  };

  T['eye-care'] = {
    about: [
      "[Optical Name] is led by qualified optometrist [Name] with [X] years of experience. From basic eye check-up to specialised contact lens fitting, we offer comprehensive vision care.",
      "Modern optical store with computerised eye testing, branded frames (Ray-Ban, Vincent Chase, Oakley, Fastrack), and premium lens options (Essilor, Zeiss, Crizal).",
      "We believe glasses are not just a medical need — they're a lifestyle choice. Wide frame collection for every face shape, budget, and style. Try-on and consult freely.",
      "Trusted eye-care destination in [City] since [Year]. Senior citizen check-up, kids vision screening, contact lens consultation, and post-surgery follow-up — all in one place.",
      "Authorised stockist of [brand names]. Computerised eye testing with the latest auto-refractometer. Free first eye check-up with any spectacles purchase."
    ],
    usp: [
      "Optometrist on-site · Computerised eye test · Free first check-up",
      "Branded frames: Ray-Ban, Vincent Chase, Oakley, Fastrack, Lenskart",
      "Premium lenses: Essilor, Zeiss, Crizal · Blue cut · Photochromic · Progressive",
      "Contact lens fitting · Try-on & buy · Schedule-based fitting",
      "Senior citizen discount · Kids check-up · Post-surgery glasses"
    ],
    faqs: [
      { q: "Is the eye check-up free?",
        a: "Yes — free computerised eye test with any spectacle purchase. Independent check-up: ₹[X]." },
      { q: "What brands of frames do you have?",
        a: "Ray-Ban, Oakley, Vincent Chase, Fastrack, Vogue, Carrera, plus affordable house brands. Range from ₹500 to ₹15,000." },
      { q: "What lens options are best for me?",
        a: "Depends on power, screen time, age. Blue cut for digital users, photochromic for outdoors, progressive for 40+, anti-glare standard." },
      { q: "How long does it take to get glasses ready?",
        a: "Stock power: same day. Special / progressive / high power: 2–5 days. Express service: 24 hours for urgent." },
      { q: "Do you fit contact lenses?",
        a: "Yes — trial pair, fitting, training, after-care. Daily, monthly, coloured, toric — all types." },
      { q: "Do you offer warranty on frames / lenses?",
        a: "Yes — 1-year frame warranty (manufacturing defect). 6-month anti-glare coating warranty. Free adjustment lifetime." },
      { q: "Do you serve children's eye needs?",
        a: "Yes — kids vision screening, flexible frames (Miraflex), correct posture guidance, parental counselling." },
      { q: "Can I claim insurance for eye care?",
        a: "[OPD insurance covers eye check-up. Spectacles covered for kids and senior citizens in some policies. We provide bills for claim.]" }
    ]
  };

  // =========================================================
  //  FINANCIAL SERVICES SUB-CATEGORIES
  // =========================================================

  T['mutual-fund-distributor'] = {
    about: [
      "We are AMFI-registered Mutual Fund Distributors (ARN: [ARN-XXXXXX]) serving [City] since [Year]. With ₹[X] crore AUM and [number]+ families served, we focus on goal-based SIP planning, lumpsum advisory, and lifetime portfolio reviews.",
      "[Firm Name] is led by [Founder Name], AMFI-certified MFD with [X] years of experience. We partner with all major AMCs (HDFC, ICICI, SBI, Axis, Nippon, etc.) and recommend funds based on your goals — not on commission.",
      "Started in [Year], we have helped families build wealth through disciplined SIPs and goal-mapped investments. From your child's education to your retirement, every rupee is allocated with a clear plan.",
      "Honest mutual fund advisory — no churning, no NFO push, no commission games. We believe a 15–20 year SIP discipline is more powerful than chasing the latest hot fund. Free portfolio review for new clients.",
      "Trusted by [number]+ families, our practice combines goal planning, asset allocation, and tax-efficient strategies. We use MFCentral, BSE Star MF, and AMC platforms — full digital, paperless onboarding."
    ],
    usp: [
      "AMFI-registered MFD · ARN [XXXXXX] · ₹[X] cr AUM · 1000+ happy families",
      "Goal-based SIP planning · Lumpsum advisory · Tax-saving ELSS",
      "Partner with all top AMCs · No NFO push · No churning · Long-term focus",
      "Free portfolio review · Risk profiling · Annual rebalancing",
      "Paperless investment · MFCentral · BSE StarMF · 24x7 WhatsApp support"
    ],
    faqs: [
      { q: "Are you AMFI-registered?",
        a: "Yes — ARN [ARN-XXXXXX] issued by AMFI. Our certification number and validity can be verified on amfiindia.com." },
      { q: "Do I have to pay you any fee?",
        a: "No fee from you. Our commission comes directly from the AMC, paid out of expense ratio (already built into the NAV). You pay nothing extra." },
      { q: "What is the minimum SIP / lumpsum amount?",
        a: "SIP: starts from ₹500 per month. Lumpsum: minimum ₹5,000. No upper limit. Goal-based plan tailored to your budget." },
      { q: "Which funds do you recommend?",
        a: "Depends on goal, risk, and time horizon. Diversified Equity for long-term, Hybrid for medium, Debt for short, ELSS for tax saving. No biased recommendations." },
      { q: "Can I do tax-saving investment (80C)?",
        a: "Yes — ELSS mutual funds qualify for 80C deduction (up to ₹1.5 lakh). 3-year lock-in, equity returns, double benefit." },
      { q: "How do I track my SIP / portfolio?",
        a: "MFCentral app, AMC mailers, and our monthly WhatsApp report. We send portfolio statement every quarter with performance vs benchmark." },
      { q: "Can I pause / stop my SIP anytime?",
        a: "Yes — pause for 1–6 months, resume anytime. No exit charge from SIP itself. Exit load on units redeemed within 1 year (typically 1%)." },
      { q: "What if I want to switch funds?",
        a: "Sure — review every quarter. If a fund underperforms benchmark consistently for 2+ quarters, we suggest switch. Your decision, our recommendation." }
    ]
  };

  T['stock-broker'] = {
    about: [
      "We are SEBI-authorised Sub-Broker / Authorised Persons under [Broker Name] serving [City] since [Year]. ₹[X] crore broking turnover. Equity, F&O, IPO, MF, and Bonds — one trusted partner.",
      "[Firm Name] is led by [Founder Name] with [X] years in stock markets. We help retail and HNI clients with informed trading and long-term investing — no tip-based business, only fundamentals and discipline.",
      "Authorised Person of [NSE / BSE-empanelled broker]. Demat + trading account opening free for new clients. Equity, currency, commodity, F&O segments active. Margin funding available for eligible accounts.",
      "Stock market is not a casino — it's a wealth builder when used with discipline. Our research-backed approach, regular client education, and risk-management focus separate us from typical tip-providers.",
      "Trusted by [number]+ traders and investors in [City]. We support clients with research reports, technical setups, fundamental views, and lifetime account servicing. Office walk-in welcome."
    ],
    usp: [
      "SEBI-authorised · Sub-Broker for [Broker Name] · ₹[X] cr turnover · [Y]+ active clients",
      "Free demat + trading A/c · No AMC for first year · Margin available",
      "Equity · F&O · Currency · Commodity · IPO · MF · Bonds — all segments",
      "Research-backed recommendations · No paid tips · Education-first approach",
      "Walk-in office support · Same-day account opening · WhatsApp updates"
    ],
    faqs: [
      { q: "Are you SEBI-registered / authorised?",
        a: "Yes — we are Authorised Person of [Broker Name] (SEBI-registered Trading Member). Authorisation Code: [code]." },
      { q: "How long does it take to open a demat account?",
        a: "With Aadhaar + PAN + cancelled cheque, same-day account opening via paperless e-KYC. Trading ID active in 24–48 hours." },
      { q: "What are the charges — brokerage, AMC, demat?",
        a: "Equity delivery: [0.1–0.25%]. Intraday: [0.01–0.05%]. F&O: ₹[X] per lot. Demat AMC: ₹[Y] / year (often waived for first year)." },
      { q: "Do you offer tips / advisory?",
        a: "We share research reports and technical setups from [broker research team] — but no \"sure-shot\" tips. Disciplined investing beats tip-chasing." },
      { q: "Can I trade in F&O / currency / commodity?",
        a: "Yes — all segments active. F&O requires income proof for margin. Currency and commodity available with separate enable form." },
      { q: "Can you help me apply for IPO?",
        a: "Yes — IPO application via UPI / ASBA, fully assisted. Allotment status tracking and listing-day execution support." },
      { q: "What if I forget my password / face technical issue?",
        a: "Walk into our office or WhatsApp us. We help reset, update KYC, modify nominee, anything — without you having to chase customer care." },
      { q: "Do you also handle mutual funds and bonds?",
        a: "Yes — MF via demat (units in your demat A/c), tax-free bonds, SGB (Sovereign Gold Bonds), corporate FDs, NCDs — all available." }
    ]
  };

  T['tax-consultant'] = {
    about: [
      "[Firm Name] is led by [Founder Name] with [X] years in income tax, GST, TDS, and accounting practice. We serve individuals, freelancers, small businesses, and SMEs — accurate filing, on-time compliance, and audit-ready records.",
      "Established in [Year], our firm handles 500+ ITR filings, 200+ GST registrations, and ongoing accounting for SMEs across [City]. Fixed-fee packages, no surprise bills, full digital onboarding.",
      "Tax planning is more than filing — it's smart legal saving. We help you claim every legitimate deduction, structure your income tax-efficiently, and stay compliant year-round.",
      "From salaried ITR-1 to complex business ITRs, GST returns to ROC filings — we handle all compliance under one roof. Pickup of documents available within [City].",
      "Trusted tax consultant for [number]+ clients in [City]. Free initial consultation, e-mailed estimates, and post-filing support for notices. Lifetime data retention for your records."
    ],
    usp: [
      "[X]+ yrs experience · 500+ ITRs filed · GST registered consultant · Lifetime support",
      "ITR · GST · TDS · ROC · Audit · Bookkeeping — all under one roof",
      "Fixed-fee packages · No hidden charges · Free first consultation",
      "Notice handling · Refund follow-up · Tax-saving planning",
      "Pickup & drop service · Paperless onboarding · WhatsApp updates"
    ],
    faqs: [
      { q: "What ITR form should I file?",
        a: "Salaried: ITR-1 (income < ₹50 lakh). Freelance / business: ITR-3 / ITR-4. Capital gains: ITR-2. We pick the right form after reviewing your income mix." },
      { q: "How much do you charge for ITR filing?",
        a: "ITR-1: ₹[X]. ITR-2/3/4: ₹[Y] depending on complexity. Business: ₹[Z] (with computation, audit prep if applicable)." },
      { q: "Can you help with tax-saving advice before March?",
        a: "Yes — annual tax planning, 80C/80D/80E/24B/HRA optimisation, suggestions on ELSS, NPS, PPF, term plan. Free for retainer clients." },
      { q: "What about GST registration and returns?",
        a: "GST registration: ₹[X] (one-time). Monthly / quarterly returns: ₹[Y] / return. Annual return GSTR-9: ₹[Z]. Composition scheme also handled." },
      { q: "Will you help if I get an Income Tax notice?",
        a: "Yes — notice analysis, reply drafting, faceless assessment representation. Free for clients whose return we filed. Outside clients: ₹[X]." },
      { q: "Do you help small businesses with accounting?",
        a: "Yes — Tally-based / Zoho-based bookkeeping, monthly financials, GST reconciliation, TDS deduction, payroll. Quote depends on volume." },
      { q: "What documents do you need for ITR?",
        a: "PAN, Aadhaar, Form 16 (salaried) / books (business), bank statements, investment proofs, rent receipt, home loan certificate. We share full checklist." },
      { q: "Do you keep my data safe and confidential?",
        a: "Absolutely — encrypted cloud backup, password-protected storage. No data shared without your written consent." }
    ]
  };

  T['financial-advisor'] = {
    about: [
      "[Firm Name] is led by [Founder Name], a qualified financial planner with [X] years of experience helping families achieve their financial goals through customised, goal-mapped investment plans.",
      "We are full-service personal finance advisors — goal planning, asset allocation, tax planning, insurance review, retirement planning. Fee-only or hybrid model, transparent disclosure.",
      "Your money deserves a plan. We help you map your goals (child education, home, retirement, dream vacation), calculate the right SIP, and rebalance annually. No products pushed, only advice driven.",
      "Financial freedom is a journey — and we walk it with you. From your first salary to your last working day, our planning evolves with your life stage. Annual reviews keep you on track.",
      "Trusted by [number]+ families across [City], we combine technical knowledge with empathy. Free initial consultation, written financial plan, and lifetime relationship — that's our model."
    ],
    usp: [
      "CFP / qualified planner · [X]+ yrs experience · Goal-based planning",
      "Asset allocation · Tax efficiency · Insurance review · Retirement",
      "Fee-only / hybrid · Transparent · No product push · Annual review",
      "Written financial plan · Net worth tracking · Goal calculator",
      "Family planning · Estate succession · Will-writing guidance"
    ],
    faqs: [
      { q: "What is the difference between an advisor and a distributor?",
        a: "Distributor sells products and earns commission. Advisor charges a fee for unbiased plan. We can do both transparently — your choice of model." },
      { q: "What is your fee structure?",
        a: "Fee-only plan: ₹[X] one-time + ₹[Y] annual. Commission-only: free for you (we earn from AMC). Hybrid: lower fee + transparent commission disclosure." },
      { q: "Do I need a financial advisor if my income is moderate?",
        a: "Especially yes — small mistakes compound. A ₹5,000 SIP started 5 years late costs you ₹15 lakhs over 25 years. Planning matters more than amount." },
      { q: "What goals do you help plan for?",
        a: "Emergency fund, child education, marriage, home purchase, dream vacation, retirement, parents' healthcare, charitable giving, estate planning." },
      { q: "How often do we review the plan?",
        a: "Annual full review + portfolio rebalancing. Quarterly portfolio statement. Goal-tracking dashboard updated monthly. WhatsApp queries anytime." },
      { q: "Do you help with insurance reviews?",
        a: "Yes — current cover analysis, gap identification, term plan / health plan recommendations. No biased selling; we suggest the best fit." },
      { q: "Do you help with retirement / NPS planning?",
        a: "Yes — corpus calculation, NPS allocation, withdrawal strategy, post-retirement income planning (SWP, annuity, dividend). Long-term partnership." },
      { q: "How do I get started?",
        a: "WhatsApp us at [number] for a free 30-min discovery call. We share questionnaire, you fill at leisure. Plan delivered in 2 weeks." }
    ]
  };

  T['loan-agent'] = {
    about: [
      "[Firm Name] is an authorised DSA / Loan Advisor with [X] years of experience. We help individuals and businesses get the best loan — home, business, personal, vehicle — from top banks and NBFCs.",
      "We are partnered with [HDFC, SBI, ICICI, Axis, Bajaj Finserv, Tata Capital] and 15+ lenders. We compare offers, negotiate terms, and handle paperwork — saving you time and getting better rates.",
      "Loan paperwork is confusing — we make it simple. Eligibility check, document collection, application submission, follow-up with bank, sanction, disbursement — we handle all of it.",
      "Trusted loan advisor in [City] since [Year]. From your first home loan to business expansion, we have helped [number]+ clients secure ₹[X] crore in disbursed loans.",
      "Honest loan advisory — we tell you upfront what you'll get, at what rate, with what conditions. No hidden charges, no false hopes. If you can't get a loan, we'll tell you why."
    ],
    usp: [
      "Authorised DSA · Partner with 15+ banks/NBFCs · ₹[X] cr disbursed",
      "Home · Business · Personal · Vehicle · LAP · Mortgage — all loans",
      "Best rate guarantee · Paperwork handheld · Quick sanction",
      "No upfront fee · Free eligibility check · Honest advisory",
      "Rejected before? We can help · Bank statement analysis · CIBIL improvement"
    ],
    faqs: [
      { q: "Do I have to pay you a fee?",
        a: "No upfront fee. Our processing fee is charged by the bank at disbursement, typically 0.5–2% of loan amount. Transparent before application." },
      { q: "Which banks / NBFCs do you partner with?",
        a: "HDFC, SBI, ICICI, Axis, Kotak, IDFC First, Bajaj Finserv, Tata Capital, HDB Financial, Aditya Birla Finance, and 5+ more." },
      { q: "Can you help if I have a low CIBIL score?",
        a: "Yes — we analyse your report, suggest 3–6 months improvement steps, and find NBFCs that work with 650+ scores. Below 600 is challenging but possible." },
      { q: "What documents do I need?",
        a: "Salaried: 3 months pay slip + 6 month bank statement + Form 16 + ID/address proof. Self-employed: 2 years ITR + balance sheet + bank statement." },
      { q: "How fast can I get the loan?",
        a: "Personal loan: 2–7 days. Home loan: 15–30 days. Business loan: 7–21 days. Vehicle: 1–3 days. Depends on documentation and lender." },
      { q: "What's the current interest rate?",
        a: "Home loan: from [8.5%]. Personal: [10.5%+]. Business: [12%+]. Vehicle: [9%+]. Rates depend on profile, CIBIL, income, and lender." },
      { q: "Can I prepay or foreclose the loan?",
        a: "Yes — most floating-rate home loans allow free prepayment. Fixed-rate has 2–4% foreclosure charge. Personal: usually nil after 12 months." },
      { q: "What if my application is rejected?",
        a: "We try with 2–3 alternate lenders. If all reject, we tell you exact reason (CIBIL, income, age, employment, etc.) and 6-month improvement plan." }
    ]
  };

  T['ca'] = {
    about: [
      "CA [Name], Chartered Accountant since [Year], serves individuals, partnerships, LLPs, and Pvt Ltd companies across [City]. Statutory audit, tax audit, ITR, GST, ROC, and advisory — all under one roof.",
      "Practicing CA firm with [X]+ years of experience handling complex tax, audit, and compliance matters. Our team combines technical depth with practical business insight.",
      "From new business registration to annual compliance, we are your trusted partner. Pvt Ltd / LLP incorporation, IEC, FSSAI, MSME, GST, and trademark — full lifecycle handled.",
      "We are committed to ethical, accurate, and timely service. CA [Name] is empanelled with [banks/professional bodies]. Strict deadline adherence is part of our practice culture.",
      "Specialising in [tax, audit, finance, advisory], our firm handles [number]+ entities including [SMEs / start-ups / partnerships / individuals]. Free initial consultation for new engagements."
    ],
    usp: [
      "ICAI member · CA [Name] · [X]+ yrs practice · Audit + Tax + Advisory",
      "Pvt Ltd · LLP · Partnership · Proprietorship · Trust — all entities",
      "Statutory audit · Tax audit · GST audit · Internal audit",
      "ITR · GST · TDS · ROC · Trademark · IEC · FSSAI · MSME",
      "Free initial consult · Fixed-fee packages · Confidentiality assured"
    ],
    faqs: [
      { q: "Are you a member of ICAI?",
        a: "Yes — CA [Name], ICAI Membership No. [XXXXXX], COP No. [YYYYY]. In practice since [Year]." },
      { q: "What services do you provide?",
        a: "Statutory audit, tax audit, GST audit, ITR, GST returns, TDS, ROC filings, company incorporation, MSME, trademark, advisory, project finance." },
      { q: "How much do you charge for [audit / ITR / GST]?",
        a: "Statutory audit: from ₹[X] (depending on turnover). ITR business: ₹[Y]. GST monthly: ₹[Z]. Quote after understanding scope." },
      { q: "Can you help register a new company / LLP?",
        a: "Yes — full incorporation pack: DIN, DSC, name approval, MOA, AOA, PAN, TAN, GST, MSME. End-to-end in [10–15 days]. Fees: ₹[X]." },
      { q: "Will you handle the GST refund / notice?",
        a: "Yes — GST refund filing, departmental representation, notice reply, appeals at GST Tribunal. Empanelled with GST Commissioner office." },
      { q: "What is your turnaround time for accounting?",
        a: "Monthly books closed by [10th of next month]. GST returns filed [3 days before due date]. Audit completed [within 30 days] of trial balance ready." },
      { q: "Do you provide CFO / virtual accountant service?",
        a: "Yes — outsourced finance team for SMEs: bookkeeping, MIS, GST, TDS, payroll, banking, monthly review with management. Quote on volume." },
      { q: "How do I get started?",
        a: "WhatsApp us at [number] with your entity type and requirement. We schedule a free 30-min call and share engagement letter with scope and fees." }
    ]
  };

  // =========================================================
  //  INSURANCE SUB-CATEGORIES
  // =========================================================

  T['insurance-life'] = {
    about: [
      "Authorised Life Insurance Advisor with [X] years of experience. We represent [Bajaj Allianz Life, SBI Life, HDFC Life, ICICI Pru, Tata AIA, Max Life]. Honest term plan recommendations, no ULIP push.",
      "Life insurance done right — adequate cover, affordable premium, transparent disclosure. We calculate your cover need based on income, family, liabilities, and goals. No mis-selling, ever.",
      "From term plan to retirement annuity, we help families build a financial safety net. Free policy review for existing covers — most clients discover they're under-insured by 5–10x.",
      "[Advisor Name] has helped [number]+ families secure their loved ones' future. Lifetime claim support is part of our service — we stand with families through difficult times.",
      "We believe term plan is the foundation of life insurance — pure protection, low cost. ULIPs and endowments are wealth products, not protection. We explain the difference and let you choose."
    ],
    usp: [
      "IRDAI-licensed advisor · Authorised for 6+ life insurers · [X]+ yrs experience",
      "Term plan specialist · Honest cover calculation · No ULIP push",
      "Free policy review · Goal-based planning · Tax-saving 80C / 10(10D)",
      "Claim support guaranteed · 24x7 family help · Online / paperless",
      "Authorised for: Bajaj, SBI, HDFC, ICICI Pru, Tata AIA, Max"
    ],
    faqs: [
      { q: "Which type of life insurance should I buy — term, endowment, or ULIP?",
        a: "For pure protection: Term plan (cheap, high cover). For wealth + protection: ULIP (high charges initially). For traditional saving: Endowment. Most need 80% term + 20% other." },
      { q: "How much cover do I need?",
        a: "Rule of thumb: 10–20x annual income. Better: liabilities + future expenses (kids' education, retirement spouse income, parental care) minus existing assets." },
      { q: "Why is term plan so cheap?",
        a: "Because it's pure cover — no investment component. Premium goes only for risk protection. If you survive, no return (that's why premium is low)." },
      { q: "Is the premium fixed for the entire term?",
        a: "Yes — most term plans have level premium. You lock in today's rate for the entire policy term (20–40 years). Healthier you are now, cheaper the lifetime cost." },
      { q: "Will my claim really get paid?",
        a: "Yes — if you disclose all facts (medical, occupation, income, smoking) truthfully at proposal. IRDAI claim settlement ratios published yearly — most top insurers settle 95–99%." },
      { q: "Can I buy without medical test?",
        a: "Yes — up to certain cover and age (typically ₹50 lakh under 45 years). Beyond that, medical examination required. We arrange free home pickup." },
      { q: "What is the tax benefit?",
        a: "Section 80C: premium deductible up to ₹1.5 lakh. Section 10(10D): maturity / death benefit tax-free (subject to conditions)." },
      { q: "Can I add critical illness or accident cover?",
        a: "Yes — add-on riders: critical illness, accidental death, disability waiver of premium. Costs 10–25% extra over base term premium." }
    ]
  };

  T['insurance-health'] = {
    about: [
      "Authorised Health Insurance Advisor representing Aditya Birla Health, Niva Bupa, Star Health, HDFC Ergo, ICICI Lombard, Care Health. We help families pick the right cover — not the costliest one.",
      "Health insurance is essential — not optional. A 5-day hospital stay can wipe out years of savings. We help you choose the right cover, network hospitals, and claim process.",
      "We have helped [number]+ families get cashless coverage across India. Free policy comparison, gap analysis, and claim assistance — even if you don't buy through us.",
      "Family floater, individual, senior citizen, critical illness — we offer all types. Honest premium calculation, claim ratio comparison, and exclusion clarity before you buy.",
      "Trusted health insurance partner since [Year]. Our claim assistance is what makes us different — we stand with families during hospitalisation, not just at sale time."
    ],
    usp: [
      "IRDAI-licensed · 6+ health insurers · [X]+ yrs experience",
      "Family floater · Individual · Senior citizen · Critical illness · OPD",
      "Cashless across 8000+ hospitals · TPA assistance · 24x7 claim help",
      "Honest gap analysis · No mis-sell · Free policy review",
      "Tax saving 80D up to ₹75,000 · Multi-year discount"
    ],
    faqs: [
      { q: "How much health cover should I have?",
        a: "Family of 4 in metro: ₹15–25 lakh family floater minimum. Plus super top-up of ₹50 lakh – ₹1 crore at low cost. Rural / small town: ₹10–15 lakh sufficient." },
      { q: "What is family floater vs individual?",
        a: "Floater: one sum insured shared by family (cheaper, but exhausted if one major hospitalisation). Individual: each member has own cover. Mix is best." },
      { q: "Is there a waiting period?",
        a: "Yes — 30 days for new policies (except accidents). Pre-existing diseases: 2–4 years waiting. Specific illnesses (knee, cataract): 2 years. Read carefully." },
      { q: "What is the claim process?",
        a: "Cashless: empanelled hospital + ID + pre-authorisation. Reimbursement: pay first, claim later with bills. We help with both processes." },
      { q: "Are pre-existing diseases covered?",
        a: "After waiting period (2–4 years), yes — fully. Declare honestly at proposal; non-disclosure leads to claim rejection. We never advise hiding facts." },
      { q: "Can I add my parents to the same policy?",
        a: "Yes — multi-individual policy with separate cover per member. Or separate senior citizen policy. Tax benefit u/s 80D extra ₹25k–50k for parents." },
      { q: "What is co-payment and room rent limit?",
        a: "Co-pay: you pay 10–20% of claim. Room rent: capped at 1–2% of sum insured. We help you compare plans without these traps." },
      { q: "Is OPD coverage worth it?",
        a: "OPD plans cost more. Worth it if you have frequent doctor visits / chronic medication. For most healthy families, focus on hospitalisation cover instead." }
    ]
  };

  T['insurance-general'] = {
    about: [
      "Authorised General Insurance Advisor with [X] years of experience. Motor, home, travel, fire, marine, business — full general insurance portfolio under one roof. Authorised for [Bajaj Allianz, ICICI Lombard, HDFC Ergo, Tata AIG].",
      "From your car insurance to your shop fire policy, we offer the complete range of general insurance products with honest comparison across top insurers.",
      "Motor insurance, two-wheeler, home, travel (domestic + international), shop / business — we help you cover every asset. Free quote comparison and renewal reminders.",
      "Most people overpay for motor insurance because they don't know the right deductibles, IDV, and add-ons. We help you optimise — same cover, lower premium.",
      "Trusted by [number]+ vehicle owners and homeowners in [City]. Online instant policy, claim assistance, and 24x7 emergency support are part of our service."
    ],
    usp: [
      "IRDAI-licensed · 5+ general insurers · [X]+ yrs experience",
      "Motor · Home · Travel · Fire · Shop · Business — all covers",
      "Online instant policy · WhatsApp quote · Renewal reminders",
      "Claim assistance · 24x7 emergency · Network garage list",
      "Best premium comparison · Honest IDV calculation · No-claim bonus"
    ],
    faqs: [
      { q: "What does motor insurance cover?",
        a: "Third-party (mandatory): injury / death / property damage to others. Comprehensive: above + your own vehicle damage, theft, fire, natural calamities. Always go comprehensive." },
      { q: "What is IDV and why is it important?",
        a: "IDV = Insured Declared Value, the maximum payout in case of total loss / theft. Higher IDV = higher premium but more cover. Optimise based on vehicle age and market value." },
      { q: "What add-ons should I take in motor insurance?",
        a: "Zero depreciation (recommended for cars under 5 yrs), engine protection (monsoon zones), 24x7 roadside, NCB protector, key & lock cover. Adds 20–30% to premium." },
      { q: "Can I transfer my no-claim bonus?",
        a: "Yes — NCB belongs to you, not the vehicle. Transferable when selling old car and buying new. Up to 50% premium discount after 5 claim-free years." },
      { q: "How do I claim if my vehicle is damaged?",
        a: "Call insurer / us within 24 hours. Cashless at network garage. Take vehicle to garage, surveyor visits, we coordinate. Reimbursement: pay first, claim later." },
      { q: "Do you offer shop / commercial insurance?",
        a: "Yes — fire, burglary, money, business interruption, liability, electronics, plate glass. Coverage tailored to your line of business." },
      { q: "What is travel insurance and do I need it?",
        a: "Covers medical emergency, baggage loss, flight cancellation, passport loss abroad. Mandatory for Schengen, USA. Strongly recommended for any international travel." },
      { q: "Can you help with home / building insurance?",
        a: "Yes — structure (against fire / earthquake / flood), contents (theft / fire), loss of rent. Mandatory if home loan is active." }
    ]
  };

  T['veterinary'] = {
    about: [
      "Dr. [Name], BVSc, has been treating pets and livestock since [Year]. From routine vaccinations to surgeries, [Clinic Name] is a trusted veterinary destination for [City].",
      "Modern veterinary clinic with X-ray, ultrasound, lab, and surgical facilities. We treat dogs, cats, cattle, goats, and exotic pets. Home visits available for cattle and emergency cases.",
      "Comprehensive pet healthcare — vaccinations, deworming, dental, surgery, dermatology, nutrition counselling, and behaviour consultation. Pet-parent friendly environment.",
      "We treat your pets like family. Gentle handling, modern equipment, and clear communication with owners about treatment options and costs.",
      "Trusted by farmers and pet lovers in [City] since [Year]. Cattle artificial insemination, vaccination drives, pet wellness packages, and emergency surgery facilities."
    ],
    usp: [
      "BVSc qualified · [X]+ yrs experience · Pets + Cattle · Surgery facility",
      "Vaccination · Deworming · Dental · X-ray · Ultrasound · Lab",
      "Home visits for cattle · Emergency for pets · 24x7 phone support",
      "Pet wellness packages · Annual checkups · Diet counselling",
      "Cattle AI · Pregnancy diagnosis · Mastitis · Reproductive care"
    ],
    faqs: [
      { q: "What animals do you treat?",
        a: "Dogs, cats, rabbits, birds, cattle, buffalo, goats, sheep, horses. Exotic pets case-by-case basis." },
      { q: "Do you offer vaccinations?",
        a: "Yes — full vaccination schedule for dogs, cats (DHPP, anti-rabies, kennel cough), and cattle (FMD, HS, BQ, theileriosis, brucellosis)." },
      { q: "Do you do home visits?",
        a: "Yes — for cattle (mandatory), elderly/sick pets, and emergencies. Within [X km], charges ₹[Y]." },
      { q: "What surgeries do you perform?",
        a: "Spay/neuter, cesarean, tumour removal, wound management, dental, foreign body removal, fracture management." },
      { q: "What is the consultation fee?",
        a: "Clinic consultation: ₹[X]. Home visit: ₹[Y] + medicine + procedure charges." },
      { q: "Do you stock pet food and accessories?",
        a: "[Yes — premium dog/cat food (Royal Canin, Pedigree, Whiskas), accessories, supplements. / No, we focus on medical only.]" },
      { q: "What if my pet has an emergency at night?",
        a: "Call us on [number] — we provide phone first-aid guidance and emergency consultation. Night fee may apply." },
      { q: "Do you do cattle artificial insemination?",
        a: "Yes — high-quality semen straws, trained technician, pregnancy diagnosis after 60 days. Most preferred breeds available." }
    ]
  };

  // =========================================================
  //  HOME SERVICES SUB-CATEGORIES
  // =========================================================

  T['carpenter'] = {
    about: [
      "Master carpenter [Owner Name] with [X] years of experience in furniture making, modular kitchens, wardrobes, and home repairs. Quality finish, on-time delivery, and fair pricing — that's our promise.",
      "We specialise in modular kitchen, wardrobe, bed, sofa, TV unit, and custom furniture. Premium plywood (Greenply, Century), branded fittings (Hettich, Hafele), and skilled craftsmanship.",
      "From small repairs to full home interiors, our team handles every wood-work need. Free site visit, accurate measurements, and itemised quote before any work starts.",
      "Trusted carpenter for [number]+ households in [Locality]. We use only premium materials, follow safety practices, and clean up after every job. WhatsApp-ready for quick quotes.",
      "Wood work is our passion. From traditional designs to ultra-modern interiors, we deliver craftsmanship that lasts. Free 1-year warranty on workmanship for all major work."
    ],
    usp: [
      "Master carpenter · [X]+ yrs experience · Modular kitchen specialist",
      "Premium plywood · Hettich / Hafele fittings · 1-year warranty",
      "Modular kitchen · Wardrobe · Bed · Sofa · TV unit · Custom",
      "Free site visit · Itemised quote · No advance for small work",
      "On-time delivery · Clean workmanship · Polishing included"
    ],
    faqs: [
      { q: "Do you provide free site visit and quotation?",
        a: "Yes — free site visit within [City]. Measurement and itemised quote on WhatsApp. Work starts only after approval." },
      { q: "What materials do you use?",
        a: "Greenply / Century Plywood, BWP grade for kitchen, Hettich / Hafele fittings, Asian Paint / Sirca polish. Owner can also supply." },
      { q: "How long does a modular kitchen take?",
        a: "Standard: 15–25 days. Includes design, factory cutting, on-site installation, polishing. Express delivery available with surcharge." },
      { q: "What is your pricing model?",
        a: "Per sq ft basis: ₹[X] to ₹[Y] depending on material and finish. Itemised quote provided. No hidden charges." },
      { q: "Do you take advance?",
        a: "30% advance on quote approval, 40% on material delivery, 30% on installation. Final payment after polishing and your satisfaction." },
      { q: "Is there any warranty on the work?",
        a: "1-year warranty on workmanship. Hardware (Hettich / Hafele) carries 10-year manufacturer warranty. Polish 6 months." },
      { q: "Can you match existing furniture / room theme?",
        a: "Yes — we colour-match polish, design to room style, and integrate with existing layout. Photos before quote help us prepare." },
      { q: "Do you also do small repairs / polishing?",
        a: "Yes — door / window repair, lock changes, polish refresh, hinge replacement. Minimum visit charge: ₹[X]." }
    ]
  };

  T['plumber'] = {
    about: [
      "Trained plumber [Owner Name] with [X] years of experience in domestic and commercial plumbing. From leaking taps to full bathroom renovation, we handle every plumbing need.",
      "Quick response, neat work, and fair pricing — three pillars of our service. Available for emergency calls, scheduled visits, and renovation projects. WhatsApp [number] anytime.",
      "We use branded fittings (Jaquar, Cera, Hindware, Astral), follow industry standards, and clean up after every job. No advance for small repairs.",
      "Trusted plumbing partner for [number]+ households in [City]. From RO connection to overhead tank cleaning, all plumbing services under one roof.",
      "Plumbing emergencies don't wait — and neither do we. Same-day service for leaks, blockages, geyser issues. Free assessment before quoting any major work."
    ],
    usp: [
      "Trained plumber · [X]+ yrs experience · Same-day service · No advance",
      "Branded fittings · Jaquar · Cera · Hindware · Astral pipes",
      "Bathroom · Kitchen · RO · Geyser · Tank cleaning",
      "Free assessment · Itemised quote · Fair pricing · Clean work",
      "Emergency response · WhatsApp [number] · 7-day rework guarantee"
    ],
    faqs: [
      { q: "How fast can you reach in an emergency?",
        a: "Within [30–60 minutes] in [City]. Call / WhatsApp [number] — we keep slots open for urgent leaks and blockages." },
      { q: "What is the minimum service charge?",
        a: "Visit charge: ₹[X] for inspection + minor fix. Material extra at MRP. No hidden charges, full quote before work." },
      { q: "Do you handle big work like bathroom renovation?",
        a: "Yes — full bathroom refit: tiling, sanitary fixtures, geyser, exhaust, lights. End-to-end project with timeline." },
      { q: "What brands of fittings do you use?",
        a: "Jaquar, Cera, Hindware, Parryware, Kohler. Pipes: Astral, Supreme, Prince. ISI-mark only. Customer can also supply." },
      { q: "Do you give warranty on the work?",
        a: "Yes — [7 days] for minor work, [30 days] for major. Fittings carry manufacturer warranty as per brand policy." },
      { q: "What payment modes do you accept?",
        a: "Cash, UPI (PhonePe / GPay / Paytm), bank transfer. Bill provided on request. No advance for small work." },
      { q: "Can you clean overhead / underground water tanks?",
        a: "Yes — chemical cleaning, vacuum suction, chlorination. Per tank charge: ₹[X]. Includes report on water quality." },
      { q: "Do you work on Sunday / late night?",
        a: "[Sunday: by appointment / Yes for emergency.] Late night: emergency only, extra ₹[X] surcharge." }
    ]
  };

  T['electrician'] = {
    about: [
      "Licensed electrician [Owner Name] with [X] years of experience in residential, commercial, and industrial electrical work. Wiring, panel work, LED installation, fan / AC fitting — all under one roof.",
      "Safety is non-negotiable in electrical work. We use only ISI-marked components, follow proper earthing and insulation, and provide written certification for major projects.",
      "From a simple bulb fix to full house re-wiring, we handle every job with skill and care. ISI fittings (Anchor, Havells, Polycab) and proper grounding always.",
      "Trusted electrician for [number]+ homes and shops in [City]. Quick response, fair pricing, and warranty on workmanship. Available for emergency calls 24x7.",
      "Electricals are life-and-death matters — we treat them that way. Trained team, certified materials, and proper documentation for insurance / municipal compliance."
    ],
    usp: [
      "Licensed electrician · [X]+ yrs experience · Residential + Commercial",
      "ISI components only · Anchor · Havells · Polycab · Schneider",
      "Wiring · Panel · LED · Fan · AC · Inverter · Solar",
      "Safety-first · Proper earthing · Documented work · Compliance certificate",
      "24x7 emergency · No advance · WhatsApp ready · 30-day workmanship warranty"
    ],
    faqs: [
      { q: "Are you a licensed electrician?",
        a: "Yes — Government licensed electrician [License No.]. Authorised to handle low-tension wiring up to [voltage]." },
      { q: "What is the minimum service charge?",
        a: "Visit + diagnosis: ₹[X]. Minor repair fix: ₹[Y] including material. Quote shared before any work starts." },
      { q: "Do you handle major work like house wiring?",
        a: "Yes — full house / shop re-wiring, panel upgrade, MCB / RCCB installation, earthing improvement. Project-based pricing." },
      { q: "Do you install fans, AC, geyser, LED?",
        a: "Yes — single-point installation, including drilling, wiring, switch fitting. Same-day service for simple installs." },
      { q: "Can you set up inverter / solar?",
        a: "Yes — inverter sizing, battery, wiring, MCB. Solar: 1–10 kW systems, government subsidy assistance, net metering." },
      { q: "Do you give a bill / warranty?",
        a: "Yes — formal bill, [30-day] workmanship warranty. Materials (fans, AC, MCB) carry manufacturer warranty as per brand." },
      { q: "What if I have an electrical emergency at night?",
        a: "Call [number] anytime. Emergency visit fee: ₹[X] (10 PM – 6 AM). We don't leave families in the dark." },
      { q: "Do you work for commercial / industrial setups?",
        a: "Yes — shop wiring, restaurant electricals, factory panels, motor connections, three-phase work. Project quote on visit." }
    ]
  };

  T['painter'] = {
    about: [
      "Professional painters with [X] years of experience in interior, exterior, texture, and POP work. Branded paints (Asian Paint, Berger, Nerolac, Dulux), proper surface prep, and clean finishing.",
      "We treat painting as both a craft and a science — proper putty, primer, two-coat application, masking of fixtures. Our finish lasts longer because the process is right.",
      "From single-room refresh to full building paint, we offer a complete range — emulsion, distemper, weather coat, texture, POP, wallpaper, waterproofing.",
      "Trusted by [number]+ homes and shops in [City]. Free colour consultation, shade card walkthrough, and digital preview so you know how it'll look before paint hits the wall.",
      "Clean work guaranteed — masking tape, drop sheets, careful around switches and fixtures. Post-paint cleanup included. No splatters, no surprises."
    ],
    usp: [
      "Trained team · [X]+ yrs experience · Branded paints · Clean finishing",
      "Asian Paint · Berger · Nerolac · Dulux — authorised use",
      "Interior · Exterior · Texture · POP · Waterproofing · Wallpaper",
      "Free colour consult · Digital preview · Free shade trials",
      "Surface prep included · 2-coat application · 1-year coating warranty"
    ],
    faqs: [
      { q: "What is the price per square foot for painting?",
        a: "Basic emulsion: ₹[X]/sq ft. Premium: ₹[Y]/sq ft. Includes putty, primer, 2 coats, labour. Material extra at MRP if customer supplies." },
      { q: "How long does it take to paint a 2BHK?",
        a: "Standard 2BHK: [5–8 days] depending on putty work, weather, and texture options. Detailed timeline shared in quote." },
      { q: "Do you cover and protect furniture?",
        a: "Yes — drop sheets, masking tape, plastic covers for furniture and fixtures. Owner only moves valuables; rest we handle." },
      { q: "What is included in the price?",
        a: "Putty work, primer, 2 coats of paint, surface preparation, masking, drop sheets, cleanup. Repairs (cracks, dampness) at extra cost." },
      { q: "What brand of paint do you recommend?",
        a: "For interior: Asian Royale, Berger Silk, Dulux Velvet. Exterior: Apex Ultima, Weather Coat. Customer can choose any branded option." },
      { q: "Do you offer texture and stencil designs?",
        a: "Yes — sand texture, marble finish, metallic, stencils, wallpapers. Sample wall created before full execution." },
      { q: "Is there a warranty on paint work?",
        a: "Yes — 1 year on workmanship for premium emulsion. Exterior weather coat: 3–5 years as per paint warranty (Asian / Berger)." },
      { q: "Do you do waterproofing for terrace / walls?",
        a: "Yes — terrace waterproofing (brush / spray), bathroom waterproofing, leakage treatment. 3–10 year warranty depending on material." }
    ]
  };

  T['ac-repair'] = {
    about: [
      "Authorised AC / fridge service technician with [X] years of experience. Window AC, split AC, central AC, fridge, washing machine, microwave — all brands serviced. WhatsApp-ready for quick bookings.",
      "We handle installation, regular servicing, gas refilling, compressor change, PCB repair, and breakdown service. Genuine spares, transparent pricing, written warranty.",
      "Beat the heat without breaking your AC — our seasonal servicing extends life and improves efficiency. AMC packages available for residential and commercial setups.",
      "Trusted AC service partner for [number]+ households and businesses in [City]. Free check-up visit, accurate diagnosis, and itemised repair quote before work.",
      "Quality service + genuine parts + fair pricing. We don't recommend repairs you don't need — and we always tell you when it's cheaper to replace than repair."
    ],
    usp: [
      "Multi-brand · LG · Samsung · Voltas · Daikin · Bluestar · Hitachi",
      "AC · Fridge · Washing machine · Microwave · Geyser — all appliances",
      "Free check-up · Itemised quote · Genuine spares · 90-day warranty",
      "AMC packages · Seasonal servicing · 24x7 emergency",
      "Trained technicians · Branded gas (R32/R410A) · Bill provided"
    ],
    faqs: [
      { q: "Do you service all AC brands?",
        a: "Yes — LG, Samsung, Voltas, Daikin, Bluestar, Hitachi, Carrier, Lloyd, Mitsubishi, Panasonic, Whirlpool. Window + split + central." },
      { q: "What is the basic service / cleaning charge?",
        a: "Split AC service: ₹[X]. Window AC: ₹[Y]. Includes deep cleaning, filter wash, gas check, drainage clearing." },
      { q: "How often should I service my AC?",
        a: "Every 6 months — before summer (March–April) and after monsoon (October). Regular servicing extends compressor life and saves electricity 10–15%." },
      { q: "What if AC needs gas refilling?",
        a: "Gas refill: ₹[X] – ₹[Y] depending on tonnage and gas type (R32 / R410A). Includes leak check, vacuuming, and full charge." },
      { q: "Do you offer AMC?",
        a: "Yes — 2 services per year + unlimited repair calls (parts extra). AMC: ₹[X] / year per AC. Best for office and shops." },
      { q: "Is there a warranty on the repair?",
        a: "Yes — 90-day workmanship warranty. Parts carry [3–12 months] warranty depending on component (compressor, PCB, motor)." },
      { q: "Do you install AC for new purchases?",
        a: "Yes — installation: ₹[X] for split (up to 3 meter copper), ₹[Y] for window. Includes piping, drainage, electrical connection." },
      { q: "What if my AC is not cooling — repair or replace?",
        a: "Free diagnosis — we check compressor, gas, condenser, evaporator. If repair cost exceeds [50% of replacement], we tell you honestly to replace." }
    ]
  };

  T['ro-repair'] = {
    about: [
      "Authorised RO / water purifier service centre with [X] years of experience. Sales, service, AMC, and spare parts for Kent, Aquaguard, Pureit, Livpure, Eureka Forbes, Havells, and more.",
      "Pure water is non-negotiable for health — we make sure your RO performs at its best. Filter changes, membrane replacement, motor service, and water quality testing all available.",
      "Free water TDS test, customised RO recommendation, and installation included. From basic UV to advanced RO+UV+UF+TDS controller — all options explained clearly.",
      "Trusted RO partner for [number]+ households in [City]. Genuine spares, written warranty, and AMC plans that actually save you money over time.",
      "Quality you can drink to — that's our motto. From new RO installation to old RO repair, we offer transparent pricing and never push for unnecessary part changes."
    ],
    usp: [
      "Multi-brand RO · Kent · Aquaguard · Pureit · Livpure · Havells · Eureka",
      "RO sales · Installation · Filter change · Membrane replacement",
      "Free TDS test · Water quality report · Genuine spares · 90-day warranty",
      "AMC plans · 2 filter changes + 1 service per year",
      "Same-day service · No advance · WhatsApp [number] · Bill provided"
    ],
    faqs: [
      { q: "Which RO is best for my home water?",
        a: "Depends on TDS — bore water (>500 TDS): RO needed. Municipal soft water (<150 TDS): UV / UF enough. We test free and recommend honestly." },
      { q: "How often should RO filters be changed?",
        a: "Sediment + carbon filters: every 6–8 months. Membrane: every 2–3 years (depending on water quality and usage)." },
      { q: "What is the cost of filter / membrane change?",
        a: "Sediment + carbon set: ₹[X]. Membrane: ₹[Y] (depends on brand). Service visit included. Genuine spares only." },
      { q: "Do you offer AMC plans?",
        a: "Yes — Annual: 2 filter changes + 1 free service. ₹[X] / year. Comprehensive: includes membrane change. ₹[Y] / year." },
      { q: "What is your installation charge for new RO?",
        a: "Installation: ₹[X] (drilling, fitting, water line connection, electrical, test run). Genuine fittings only." },
      { q: "Is there a warranty?",
        a: "Service warranty: 90 days. Spare parts: as per manufacturer (membrane 1 year, motor 1 year). Bill provided for all warranty claims." },
      { q: "My RO is making noise / leaking — what to do?",
        a: "Could be air-lock, pump issue, or leakage. We do free diagnosis and quote before work. Don't open it yourself — voids warranty." },
      { q: "Do you sell new RO units?",
        a: "Yes — authorised dealer for [Kent / Aquaguard / etc.]. Installation, demo, and 1-year service plan included with new purchase." }
    ]
  };

  T['pest-control'] = {
    about: [
      "Government-licensed pest control service with [X] years of experience. Termite, cockroach, mosquito, bedbug, rat, and lizard control for homes, offices, restaurants, and warehouses.",
      "We use food-safe, government-approved chemicals (Bayer, BASF, Syngenta) with proper application techniques. Safe for kids, pets, and elderly when applied by trained team.",
      "From single treatment to AMC contracts, we offer the complete range — herbal options for sensitive homes, industrial grade for commercial spaces.",
      "Trusted pest control partner for [number]+ properties in [City]. Free survey, detailed quote, before-after photos, and post-treatment support included.",
      "Pests are health hazards — we don't take half measures. Source identification, proper dosage, and follow-up visits are part of our standard process."
    ],
    usp: [
      "Government-licensed · [X]+ yrs experience · Approved chemicals",
      "Termite · Cockroach · Mosquito · Bedbug · Rat · Lizard — all pests",
      "Safe for kids / pets · Food-safe products · Herbal options",
      "Free survey · Before-after photos · Written warranty",
      "AMC plans · Quarterly service · Restaurant / office specialty"
    ],
    faqs: [
      { q: "Are your chemicals safe for kids and pets?",
        a: "Yes — government-approved, food-safe formulations (Bayer / BASF / Syngenta). Recommend keeping kids/pets out for 4 hours post-spray; safe thereafter." },
      { q: "How long does the effect last?",
        a: "Cockroach gel: 3–6 months. Termite: 5–10 years (depending on treatment). Mosquito spray: 3–4 weeks. Bedbug: 2 visits, 21 days apart." },
      { q: "What is the cost for [termite / cockroach / mosquito] treatment?",
        a: "1 BHK: termite ₹[X], cockroach ₹[Y], mosquito ₹[Z]. Larger areas pro-rated. Free survey before quote." },
      { q: "Do you offer AMC?",
        a: "Yes — quarterly visits + unlimited callbacks (general pests). ₹[X] / year for residential. Restaurant / office: custom quote." },
      { q: "Is there a warranty?",
        a: "Yes — written warranty: termite 5 years, bedbug 6 months, general pest 3–6 months. Free re-treatment if reinfestation within warranty." },
      { q: "Do I need to vacate during treatment?",
        a: "General spray: 4 hours after. Termite (drilling): 1 day. Fumigation: 24–48 hours. We give clear instructions before each treatment." },
      { q: "Can you treat restaurants and food shops?",
        a: "Yes — food-grade products, FSSAI-compliant. Treatment outside business hours, with proper masking of food preparation areas." },
      { q: "What if pests return after treatment?",
        a: "Within warranty: free re-treatment. After warranty: discounted re-visit. We always identify the source (entry point, breeding area) for permanent solution." }
    ]
  };

  T['maid-service'] = {
    about: [
      "Verified maid / cook placement agency with [X] years of experience. Background-checked staff, photo ID verified, and trial period offered. Full-time, part-time, live-in, and 24x7 options.",
      "We place trained domestic help for cooking, cleaning, child care, elderly care, and patient care. Hindi / English / regional language preferences accommodated.",
      "Trust is the foundation of our service. Every maid / cook is police-verified, photo ID submitted, and references checked. Replacement guarantee if not satisfied in [X days].",
      "Trusted by [number]+ families in [City], we offer one-time placement, replacement guarantee, and dispute resolution. Our process is transparent and clear.",
      "Quality domestic help should not be a luxury. We bring you trained staff with proper documentation, fair wages, and reasonable agency fees."
    ],
    usp: [
      "Verified staff · Police-verified · Photo ID · Reference checked",
      "Full-time · Part-time · Live-in · 24x7 · Cook / Maid / Care",
      "[X]-day trial · Replacement guarantee · Dispute resolution",
      "Hindi / English / Regional language · Diet preferences honoured",
      "Transparent fees · No hidden charges · Documented placement"
    ],
    faqs: [
      { q: "Are your maids / cooks verified?",
        a: "Yes — police verification, photo ID, address proof, and reference check from previous employer. Documentation shared at placement." },
      { q: "What is your agency / placement fee?",
        a: "One-time placement: ₹[X] (1 month's salary typically). Includes replacement guarantee for [30–90 days]. Salary paid directly to staff." },
      { q: "What is the salary range for full-time / part-time?",
        a: "Part-time (2–3 hours): ₹[X] / month. Full-time (8–10 hours): ₹[Y]. Live-in: ₹[Z] + food + lodging. Varies by city and skill." },
      { q: "What if I don't like the maid / cook?",
        a: "Free replacement within [30–90 days]. After that, replacement at discounted fee. We always aim for the right fit." },
      { q: "Are they trained in cooking specific cuisines?",
        a: "Yes — Indian (regional), Continental, Chinese, baking. We match based on your preference. Trial cooking session before placement." },
      { q: "Do you provide elderly / patient care staff?",
        a: "Yes — trained attendants for elderly, post-surgery patients, bed-ridden care. Higher fee due to specialised skills." },
      { q: "Will the same person come daily?",
        a: "Yes — placed staff is consistent. If they take leave, we arrange backup. Sudden absences within [24 hours] notice." },
      { q: "What if there's theft or other issue?",
        a: "Police verification deters this. In any incident, we cooperate fully with authorities and provide complete staff documentation." }
    ]
  };

  T['cleaning-service'] = {
    about: [
      "Professional deep cleaning service with trained team and commercial-grade equipment. Home, office, post-construction, sofa, mattress, carpet, water tank — all surfaces and spaces covered.",
      "We use eco-friendly chemicals, microfiber tools, and HEPA vacuum for thorough cleaning. Our checklist-based process ensures nothing is missed.",
      "From bachelor pad to luxury villa, we adapt our process to your space. Before-after photos, satisfaction guarantee, and same-day re-clean if you spot any miss.",
      "Trusted by [number]+ homes and offices in [City]. Festive cleaning, move-in / move-out, deep cleaning, post-renovation — packages for every need.",
      "Hygiene is essential — and we deliver it professionally. Trained, uniformed team, on-site supervisor, and detailed cleanup report on completion."
    ],
    usp: [
      "Trained team · Uniformed · Background verified · On-site supervisor",
      "Deep cleaning · Sofa · Mattress · Carpet · Water tank · Post-construction",
      "Eco-friendly chemicals · HEPA vacuum · Microfiber tools",
      "Before-after photos · Same-day re-clean guarantee · Bill provided",
      "Festive packages · Move-in / move-out · Office AMC"
    ],
    faqs: [
      { q: "What is included in deep cleaning?",
        a: "Floor scrubbing, kitchen degreasing, bathroom descaling, fan cleaning, switch / socket wipe, window cleaning, dusting, vacuum, mop. Detailed checklist shared." },
      { q: "How long does deep cleaning take?",
        a: "1 BHK: 4–5 hours, 2 BHK: 6–8 hours, 3 BHK: 8–10 hours. Larger homes: split over 2 days." },
      { q: "What is the cost?",
        a: "1 BHK: ₹[X]. 2 BHK: ₹[Y]. 3 BHK: ₹[Z]. Add-ons: sofa ₹[A] / seat, carpet ₹[B] / sq ft, water tank ₹[C]." },
      { q: "Are your chemicals safe for kids and pets?",
        a: "Yes — eco-friendly, non-toxic, food-safe. Recommended to keep small kids and pets in another room during cleaning." },
      { q: "Do you bring your own tools / chemicals?",
        a: "Yes — full kit: vacuum, mops, brushes, chemicals, microfiber cloth, scrubbers. You only provide water and electricity." },
      { q: "Can you clean sofa, mattress, carpet?",
        a: "Yes — shampoo + steam + dry. Sofa: ₹[X] / seat. Mattress: ₹[Y] / single. Carpet: ₹[Z] / sq ft. Pickup-drop available for big items." },
      { q: "Is there a satisfaction guarantee?",
        a: "Yes — if not satisfied with any area, we re-clean that spot same-day, free. Final approval only after walk-through." },
      { q: "Do you offer monthly AMC for offices?",
        a: "Yes — daily / alternate-day / weekly cleaning for offices. Custom quote based on size, frequency, and scope." }
    ]
  };

  T['packers-movers'] = {
    about: [
      "Reliable packers and movers with [X] years of experience in household, office, and industrial shifting. Local, intercity, and pan-India relocation. Insured transit, professional packing.",
      "We treat your belongings like our own — proper packing materials, careful handling, GPS-tracked vehicles. Insurance available for premium peace of mind.",
      "From a 1 BHK shift to full office relocation, our trained team handles every move with care. Free survey, itemised quote, and transit insurance optional.",
      "Trusted by [number]+ families and businesses in [City]. Our process is transparent — itemised list, packing material breakdown, and tamper-proof seals.",
      "Move smart, move safe — our promise. Professional packers, branded boxes, GPS-tracked trucks, and delivery confirmation. Best price quote on WhatsApp."
    ],
    usp: [
      "[X]+ yrs experience · Local + Intercity + Pan-India",
      "Household · Office · Industrial · Vehicle (car / bike) transport",
      "Insured transit · GPS tracking · Tamper-proof seals · Trained team",
      "Free survey · Itemised quote · No hidden charges",
      "Bubble wrap · Branded boxes · Wooden crates · Strapping"
    ],
    faqs: [
      { q: "How is the cost calculated?",
        a: "Based on quantity of goods, distance, floor / lift access, and packing material. Free pre-move survey gives accurate quote — no hidden charges." },
      { q: "Do you offer transit insurance?",
        a: "Yes — comprehensive transit insurance: 3% of declared value approximately. Covers damage, loss, theft during transit." },
      { q: "How long does a shift take?",
        a: "Local (same city): 1 day. Intercity (500 km): 2–3 days. Pan-India (1500+ km): 5–7 days. Door-to-door delivery." },
      { q: "Do you pack everything or do I have to help?",
        a: "We pack everything — kitchen, wardrobe, electronics, fragile, furniture. You only segregate items you don't want to move." },
      { q: "What packing materials do you use?",
        a: "Bubble wrap (electronics), corrugated boxes (kitchen / clothes), thermocol (fragile), wooden crates (TV / fridge), stretch film, packing tape." },
      { q: "Can I track my goods during transit?",
        a: "Yes — GPS-tracked trucks. We share live location with you. Driver contact also provided for direct communication." },
      { q: "What if something is damaged during shift?",
        a: "Insured items: claim filed and processed. Uninsured: we share liability up to ₹[X]. Photos at packing and unloading for evidence." },
      { q: "Do you transport vehicles (car / bike)?",
        a: "Yes — covered container trucks (no road damage). Single bike: ₹[X]. Car: ₹[Y]. Documentation and insurance included." }
    ]
  };

  // =========================================================
  //  AUTOMOTIVE SUB-CATEGORIES
  // =========================================================

  T['used-car'] = {
    about: [
      "Authorised used car dealer with [X] years of experience. Hand-picked inventory, verified RC + insurance + service records, and finance assistance — buying a used car has never been easier.",
      "We sell only certified pre-owned cars. Every vehicle undergoes 100+ point inspection: engine, suspension, electrical, paint, AC, and document verification.",
      "Trusted by [number]+ buyers in [City]. We deal in all brands and segments — hatchback, sedan, SUV, luxury. Test drive freely, no pressure to buy.",
      "Honest used car business — accident history disclosed, kilometre rolling avoided, fair pricing. We'd rather lose a sale than sell a problem car.",
      "From budget hatchbacks to premium SUVs, our 40+ car inventory has something for every buyer. RC transfer, insurance, loan — all handled in-house."
    ],
    usp: [
      "100+ point inspection · Verified RC + insurance + service record",
      "All brands · All segments · Budget to premium · Test drive freely",
      "RC transfer assistance · Loan up to 90% · Insurance included",
      "Honest disclosure · Accident history shared · No mileage rolling",
      "7-day money-back · 1-year engine warranty option · Exchange welcome"
    ],
    faqs: [
      { q: "How do you verify a used car?",
        a: "100+ point check: engine compression, transmission, suspension, electricals, AC, paint thickness, accident history (VAHAN portal), RC, insurance, service history." },
      { q: "Can you arrange loan for the car?",
        a: "Yes — partnered with HDFC, SBI, Mahindra, Tata Capital. Loan up to 90% of car value. Approval in 24–48 hours with documents." },
      { q: "Do you offer test drive?",
        a: "Yes — free test drive with valid driving license. We accompany you on the drive; no high-pressure sales." },
      { q: "Is the price negotiable?",
        a: "Yes — within reason. Final price depends on demand, condition, and your finance options. Honest pricing from the start." },
      { q: "Will you help with RC transfer?",
        a: "Yes — RC transfer, insurance transfer, NOC (if required), road tax. Complete paperwork handled. Charges as per RTO." },
      { q: "What if I face issue after purchase?",
        a: "7-day money-back (terms apply). Optional 1-year engine warranty: ₹[X]. We stand behind every car we sell." },
      { q: "Do you accept my old car in exchange?",
        a: "Yes — free valuation, instant exchange against new purchase. Save on RTO + paperwork hassles." },
      { q: "How do I know there is no hidden damage?",
        a: "Vehicle history report from VAHAN, accident scan with paint thickness gauge, engine compression test. Independent inspection allowed at your cost." }
    ]
  };

  T['new-car'] = {
    about: [
      "Authorised new car dealer for [Brand Name] with [X] years of dealership experience. Full range of models, attractive financing, exchange offers, and post-sale service.",
      "Step into our showroom for the complete [Brand] experience — test drives, configurator, accessory bundles, and competitive on-road pricing.",
      "From booking to delivery, we make new car buying effortless. Documentation, finance, insurance, RTO — handled end-to-end by our team.",
      "Trusted by [number]+ new car owners in [City]. Authorised service center, genuine parts, and lifetime customer support are part of our offering.",
      "Special corporate plans, exchange bonuses, and festival offers throughout the year. Subscribe to our WhatsApp for the latest deals."
    ],
    usp: [
      "Authorised dealer · Full [Brand] range · Genuine warranty · Service tie-up",
      "Loan partners: HDFC, SBI, Bajaj Finance · Up to 100% finance",
      "Exchange offers · Corporate deals · Festival bonus",
      "Test drive · Booking · Delivery · Free first service",
      "Insurance · RTO · Accessories · Extended warranty — all in-house"
    ],
    faqs: [
      { q: "What models do you sell?",
        a: "Full [Brand Name] range — [list models]. From hatchback to SUV, petrol / diesel / CNG / electric. Latest variants in stock." },
      { q: "Can I take a test drive?",
        a: "Yes — free test drive with valid license. We can also bring the car to your home / office for test drive. Book on WhatsApp." },
      { q: "What is on-road price for [model]?",
        a: "Ex-showroom + RTO + insurance + handling + accessories = on-road. WhatsApp [number] for live quote with all variants and colour options." },
      { q: "Can you arrange loan?",
        a: "Yes — HDFC, SBI, Bajaj Finance, ICICI Bank tie-up. Loan up to 100% with NIL processing fee for select customers. Approval in 24 hours." },
      { q: "Do you accept old car in exchange?",
        a: "Yes — free valuation, exchange bonus up to ₹[X] (offer subject to model and condition). Save on paperwork." },
      { q: "What is the delivery time?",
        a: "In-stock variants: 3–7 days. Special colour / variant: 4–8 weeks. Premium / waitlisted: as per allocation." },
      { q: "Are accessories and extended warranty available?",
        a: "Yes — genuine accessories: floor mats, infotainment, sensors, paint protection. Extended warranty up to 5 years available." },
      { q: "Where do I service the car?",
        a: "Our authorised service centre at [address]. Genuine parts, trained mechanics, doorstep pickup available. First service free." }
    ]
  };

  T['mechanic-2w'] = {
    about: [
      "Two-wheeler specialist mechanic [Owner Name] with [X] years of experience. All brands serviced — Hero, Honda, TVS, Bajaj, Royal Enfield, Yamaha, KTM, Suzuki. Genuine spares, fair pricing.",
      "From routine service to engine overhaul, we handle every two-wheeler issue. Free pick-up and drop within [X km], detailed inspection report on WhatsApp.",
      "We use genuine OEM spare parts only and follow manufacturer service schedules. Bike runs better, lasts longer, retains resale value.",
      "Trusted by [number]+ riders in [City]. Quick service, clear quotes, and 30-day workmanship warranty on every repair.",
      "Honest mechanic — we tell you what your bike actually needs, not what makes us more money. Don't overdo it, don't skip critical work."
    ],
    usp: [
      "Multi-brand · Hero · Honda · TVS · Bajaj · Royal Enfield · Yamaha · KTM",
      "Routine service · Engine overhaul · Tyre · Battery · Electrical · Body",
      "Genuine OEM parts · Branded oils · 30-day workmanship warranty",
      "Free pickup/drop within [X km] · WhatsApp [number] · Detailed quote",
      "Same-day service for routine · Test ride after service · Bill provided"
    ],
    faqs: [
      { q: "How long does a routine service take?",
        a: "General service: 2–3 hours. Major service / engine work: 1–2 days. Pickup-drop adds 30–60 minutes." },
      { q: "Do you use genuine parts?",
        a: "Yes — only OEM (Original Equipment Manufacturer) parts. Aftermarket alternative offered only on customer's explicit request with disclosure." },
      { q: "What is the basic service charge?",
        a: "100cc / 125cc: ₹[X]. 150cc / 200cc: ₹[Y]. Royal Enfield / 350cc+: ₹[Z]. Includes oil change, filter, basic check-up." },
      { q: "Do you offer pickup and drop?",
        a: "Yes — free within [X km] in [City]. WhatsApp 1 hour before pickup. Detailed inspection report shared before any work." },
      { q: "Is there a warranty on the work?",
        a: "Yes — 30-day workmanship warranty. Parts carry manufacturer warranty (typically 6 months – 1 year for components)." },
      { q: "Can you handle electrical / wiring issues?",
        a: "Yes — battery, headlight, indicator, self-start, wiring harness, ECU. Auto-electrician available in-house." },
      { q: "My bike is making strange noise — diagnose?",
        a: "Free diagnosis: 30-minute road test + lift inspection. We share itemised quote on WhatsApp. Work starts only after your approval." },
      { q: "Do you do denting / painting?",
        a: "Yes — full body paint, dents, touch-up. Original colour match, branded paints (Asian / Berger Auto). Quote on visit." }
    ]
  };

  T['mechanic-4w'] = {
    about: [
      "Four-wheeler specialist with [X] years of experience. Multi-brand service — Maruti, Hyundai, Tata, Mahindra, Honda, Toyota, Ford, VW, Skoda. Genuine parts, transparent billing.",
      "From periodic service to engine overhaul, AC repair to suspension, electricals to body shop — full-service workshop for all car needs.",
      "We use OEM-grade parts, follow manufacturer service intervals, and provide detailed invoices with itemised charges. No hidden costs.",
      "Trusted by [number]+ car owners in [City]. Free vehicle pickup-drop, courtesy car for major work, and WhatsApp updates throughout the service.",
      "Honest car mechanic — we recommend only the work your car needs, suggest alternatives where possible, and tell you when a part can wait."
    ],
    usp: [
      "Multi-brand · Maruti · Hyundai · Tata · Mahindra · Honda · Toyota · Ford",
      "Engine · AC · Suspension · Electrical · Body shop · Detailing",
      "Genuine OEM parts · 6-month / 10,000 km workmanship warranty",
      "Free pickup-drop · Detailed quote on WhatsApp · Insurance assistance",
      "[X]+ yrs experience · Trained mechanics · Modern diagnostic tools"
    ],
    faqs: [
      { q: "Do you service my car brand?",
        a: "Yes — Maruti, Hyundai, Tata, Mahindra, Honda, Toyota, Ford, VW, Skoda, Renault, Kia, MG, and luxury (BMW / Audi / Mercedes) on request." },
      { q: "How much does basic service cost?",
        a: "Petrol hatchback: ₹[X]. Sedan: ₹[Y]. SUV: ₹[Z]. Includes oil change, filter, basic inspection, top-ups. Diesel: 10–15% extra." },
      { q: "Do you handle insurance / cashless?",
        a: "Yes — empanelled with [insurance companies]. Cashless claim for accident repair. Documentation handled end-to-end." },
      { q: "How long does service take?",
        a: "Periodic service: same day. Major repair: 2–5 days. Engine / transmission overhaul: 7–15 days depending on parts availability." },
      { q: "Do you use genuine parts?",
        a: "Yes — OEM parts. Aftermarket alternative offered only with customer's explicit approval and full disclosure of difference." },
      { q: "Is there warranty on repairs?",
        a: "Yes — 6 months / 10,000 km on workmanship. Parts carry their own manufacturer warranty (typically 12 months / 20,000 km)." },
      { q: "Can you handle accident repair / dent paint?",
        a: "Yes — full body shop: denting, painting, panel replacement, headlight, bumper. Insurance survey assistance included." },
      { q: "Do you offer pickup-drop?",
        a: "Yes — free pickup-drop within [X km] in [City]. Major work: courtesy car for ₹[Y] / day. Book on WhatsApp [number]." }
    ]
  };

  T['car-service'] = {
    about: [
      "Authorised multi-brand car service centre with [X] years of operation. Genuine parts, manufacturer-trained technicians, modern diagnostic tools, and transparent billing.",
      "Our service centre is equipped with computerised diagnostic, wheel alignment, balancing, body shop, paint booth, and detailing bay — a complete one-stop facility.",
      "We service all major brands — Maruti, Hyundai, Tata, Mahindra, Honda, Toyota, Ford, VW, Skoda. Manufacturer service schedules followed strictly.",
      "Trusted by [number]+ car owners in [City]. Periodic service, repairs, AC, body work, detailing — all under one roof with quality assurance.",
      "From a quick oil change to full engine overhaul, our trained team delivers consistent quality. Genuine parts, fair pricing, and lifetime customer support."
    ],
    usp: [
      "Multi-brand service · Manufacturer-trained team · Modern equipment",
      "Computerised diagnostic · Wheel alignment · Balancing · Body shop",
      "Genuine OEM parts · Branded oils · 1-year workmanship warranty",
      "Free pickup-drop · Courtesy car for major work · Insurance support",
      "AMC packages · Annual maintenance contract · Fleet servicing"
    ],
    faqs: [
      { q: "What services do you offer?",
        a: "Periodic service, engine repair, AC service, suspension, brake, electrical, body shop, paint, detailing, AMC, fleet management." },
      { q: "Do you use genuine parts?",
        a: "Yes — OEM parts only for warranty / new cars. Customer can choose aftermarket for older cars with full disclosure." },
      { q: "How long does service take?",
        a: "Periodic service: 4–6 hours. Major repair: 1–3 days. Paint job: 5–10 days. AC repair: same day for most issues." },
      { q: "What is your AMC?",
        a: "Annual maintenance: 2 periodic services + unlimited repair calls (parts extra). Best value for cars driven 15,000+ km / year." },
      { q: "Is there a warranty?",
        a: "Yes — 1-year workmanship warranty. Parts carry manufacturer warranty. Body shop / paint: 1-year warranty against defect." },
      { q: "Do you accept cashless insurance?",
        a: "Yes — empanelled with major insurers. Cashless claim for accident repair. Surveyor assistance and documentation handled." },
      { q: "Do you offer car detailing / ceramic coating?",
        a: "Yes — interior detailing, exterior polish, ceramic coating (1 / 3 / 5-year warranty). Quote depends on car size and package." },
      { q: "Can I track my car during service?",
        a: "Yes — WhatsApp updates at every stage: arrival, diagnosis, quote, work, quality check, dispatch. Photos shared for major work." }
    ]
  };

  T['tyre-shop'] = {
    about: [
      "Authorised tyre dealer for MRF, Apollo, CEAT, JK, Bridgestone, Michelin, Continental. Sales, fitment, wheel alignment, balancing, and puncture repair — full service.",
      "We stock tyres for every vehicle — bike, car, SUV, truck. Best price guarantee, manufacturer warranty, and free fitment with any tyre purchase.",
      "From budget tyres to premium performance, our team helps you pick the right one for your driving needs. Free pressure check and tread depth measurement.",
      "Trusted by [number]+ vehicle owners in [City]. Modern alignment machine, balancing, nitrogen filling, and emergency puncture service.",
      "Genuine tyres, fair pricing, professional fitment. We follow manufacturer recommendations for size, pattern, and load index — your safety is non-negotiable."
    ],
    usp: [
      "Authorised dealer · MRF · Apollo · CEAT · JK · Bridgestone · Michelin",
      "All vehicles · Bike · Car · SUV · Truck · Commercial",
      "Free fitment · Wheel alignment · Balancing · Nitrogen · Puncture",
      "Manufacturer warranty · Best price guarantee · Bill + invoice",
      "Emergency service · Mobile puncture repair · Tyre rotation"
    ],
    faqs: [
      { q: "Which tyre brand should I choose?",
        a: "Depends on car, usage, and budget. MRF / Apollo: balanced. CEAT: sporty. Bridgestone / Michelin: premium long-life. We recommend based on your vehicle." },
      { q: "Is fitment free with tyre purchase?",
        a: "Yes — free fitment, valve change, nitrogen filling, balancing. Wheel alignment: ₹[X] (recommended after tyre change)." },
      { q: "How long do tyres last?",
        a: "Typical: 40,000–60,000 km for car. Bike: 25,000–35,000 km. Depends on driving, alignment, pressure, road condition." },
      { q: "Should I get wheel alignment?",
        a: "Yes — recommended every 10,000 km or after pothole / tyre change. ₹[X] for 4-wheel computerised alignment." },
      { q: "What is nitrogen filling and is it worth it?",
        a: "Nitrogen reduces pressure loss and heat build-up. Better tyre life by 10–15%. Cost: ₹[X] per tyre. Recommended for highway / hot-climate driving." },
      { q: "Can you do puncture repair?",
        a: "Yes — tubeless puncture: ₹[X] (5 min job). Tube puncture: ₹[Y]. Big damage: tyre replacement advised, no half-measures." },
      { q: "Do you take old tyres back?",
        a: "Yes — small exchange value (₹[X] – ₹[Y] per tyre depending on size) for usable casing. Old tyres recycled responsibly." },
      { q: "Is there a warranty on tyres?",
        a: "Yes — manufacturer warranty against manufacturing defect: 5 years from manufacturing date / 50% tread, whichever earlier." }
    ]
  };

  T['spare-parts'] = {
    about: [
      "Authorised auto spare parts dealer with [X] years of experience. Genuine OEM parts for all major brands — Maruti, Hyundai, Tata, Mahindra, Honda, Toyota, Ford, plus bike spares.",
      "We stock over 5000 SKUs covering engine, transmission, suspension, body, electrical, lighting, and accessories. Same-day availability for common parts.",
      "Genuine parts only — purchased directly from authorised distributors. Every part comes with invoice and manufacturer warranty.",
      "Trusted by mechanics, garages, and direct customers across [City]. Wholesale pricing, fast delivery, and after-sale support.",
      "From a single bulb to engine assembly, we have it or can source it within 24 hours. WhatsApp model + part name for instant quote."
    ],
    usp: [
      "Genuine OEM parts · All brands · 5000+ SKUs in stock",
      "Maruti · Hyundai · Tata · Mahindra · Honda · Toyota · Ford · VW",
      "Bike spares · Hero · Honda · TVS · Bajaj · Royal Enfield",
      "Wholesale + retail · Bill + warranty · Fast sourcing",
      "WhatsApp [number] for instant quote · Delivery within [X km]"
    ],
    faqs: [
      { q: "Do you have parts for my car model?",
        a: "Likely yes — WhatsApp us photo of part / chassis number / part number. We confirm availability and price within minutes." },
      { q: "Are your parts genuine OEM?",
        a: "Yes — only OEM parts from authorised distributors. Holographic seal, batch number, manufacturer warranty card included." },
      { q: "What's the price difference vs aftermarket?",
        a: "OEM is 20–40% costlier than aftermarket. We stock both — recommend OEM for warranty / safety-critical, aftermarket for cost-sensitive." },
      { q: "Do you deliver to mechanics / garages?",
        a: "Yes — wholesale pricing for mechanics. Delivery within [X km] free above ₹[Y]. Daily delivery schedule." },
      { q: "Can you source a rare / discontinued part?",
        a: "Yes — try our network within 24–48 hours. If unavailable, we suggest reliable alternatives or compatible models." },
      { q: "Is there a warranty?",
        a: "Yes — OEM parts carry manufacturer warranty (typically 6 months – 1 year). Bill mandatory for any warranty claim." },
      { q: "Do you accept GST bill / B2B?",
        a: "Yes — GST invoice with GSTIN. Wholesale price slab for B2B. Credit terms for regular mechanic accounts." },
      { q: "What payment methods do you accept?",
        a: "Cash, UPI, debit/credit card, bank transfer, cheque. Credit accounts for verified business customers." }
    ]
  };

  T['battery-shop'] = {
    about: [
      "Authorised dealer for Exide, Amaron, Luminous, Su-Kam, Microtek inverter and automotive batteries. Sales, fitment, AMC, and free battery health check.",
      "We supply batteries for cars, bikes, commercial vehicles, inverter, UPS, solar, and tractors. Free home delivery and fitment within [X km].",
      "Battery health check is free — we test old battery before recommending replacement. If your battery has life left, we say so honestly.",
      "Trusted by [number]+ households and vehicle owners in [City]. Manufacturer warranty, free fitment, and old battery buy-back included.",
      "From a CFL inverter battery to a 200 Ah heavy-duty solar battery, we stock and service all sizes. Quick replacement during emergencies."
    ],
    usp: [
      "Authorised dealer · Exide · Amaron · Luminous · Su-Kam · Microtek",
      "Inverter · Automotive · Solar · UPS · Tractor · CFL",
      "Free home delivery · Fitment · Old battery exchange",
      "Manufacturer warranty 12–60 months · Bill + warranty card",
      "Free battery test · Emergency service · WhatsApp [number]"
    ],
    faqs: [
      { q: "Which battery brand should I choose?",
        a: "Exide / Amaron: trusted automotive. Luminous / Su-Kam / Microtek: inverter specialists. We recommend based on your application and budget." },
      { q: "Is there a warranty?",
        a: "Yes — 12 to 60 months depending on model. Pro-rata refund + full replacement within first [X] months. Warranty card mandatory." },
      { q: "Do you offer free home delivery and fitment?",
        a: "Yes — free delivery + fitment within [X km] for batteries above ₹[Y]. Old battery taken back at exchange value." },
      { q: "How much do you give for my old battery?",
        a: "Exchange value: ₹[X] / kg approximately (depends on battery weight and brand). Better than scrap dealer pricing." },
      { q: "How long does a car / bike battery last?",
        a: "Typical: 3–5 years for car (Exide / Amaron). Bike: 2–3 years. Inverter: 3–5 years for tubular. Depends on maintenance and usage." },
      { q: "Can you test my old battery?",
        a: "Yes — free testing with digital load tester. CCA reading, voltage, electrolyte specific gravity. Report shared on WhatsApp." },
      { q: "Do you stock solar / tractor / commercial vehicle batteries?",
        a: "Yes — solar batteries (deep-cycle, tubular), tractor (TR500 / TR600), commercial vehicle (truck, bus, JCB). Quote on request." },
      { q: "What payment options do you have?",
        a: "Cash, UPI, debit/credit card, EMI on credit card (no-cost EMI for select cards). Bill + warranty card for every sale." }
    ]
  };

  T['car-wash'] = {
    about: [
      "Professional car / bike wash and detailing centre with modern equipment, eco-friendly products, and trained team. From basic wash to full ceramic coating.",
      "We use foam wash, microfiber cloth, soft brushes — no harsh chemicals, no scratches. Interior shampoo, leather conditioning, and engine detailing available.",
      "Quality work, attention to detail, and fair pricing. Our packages cater to every budget — daily wash to monthly deep detail.",
      "Trusted by [number]+ vehicle owners in [City]. Membership plans, doorstep service, and ceramic coating with 3-year warranty.",
      "Your car deserves better than a quick water rinse. We offer professional grooming that protects paint, restores shine, and preserves resale value."
    ],
    usp: [
      "Foam wash · Microfiber · Soft brush · No-scratch process",
      "Basic wash to ceramic coating · Interior detail · Engine clean",
      "Eco-friendly products · Recycled water · Energy-efficient",
      "Doorstep service · Membership plans · Loyalty rewards",
      "Detailing packages · Ceramic coating · 3-year coating warranty"
    ],
    faqs: [
      { q: "What does a basic wash include?",
        a: "Exterior foam wash, microfiber dry, tyre dressing, dashboard wipe, vacuum. Cost: ₹[X] for hatchback, ₹[Y] sedan, ₹[Z] SUV." },
      { q: "How long does a basic / detailed wash take?",
        a: "Basic: 30–45 minutes. Premium detail: 2–3 hours. Full detailing + coating: 6–8 hours." },
      { q: "Do you have monthly membership?",
        a: "Yes — 4 washes / month: ₹[X]. 8 washes: ₹[Y]. Unlimited (mid + occasional premium): ₹[Z]. Best value for daily commuters." },
      { q: "What is ceramic coating?",
        a: "Long-lasting protective layer that repels water, dirt, UV. Glossy finish, scratch resistance. Lasts 1–5 years depending on grade. Cost: ₹[X] – ₹[Y]." },
      { q: "Do you offer interior detailing?",
        a: "Yes — vacuum, dashboard polish, leather conditioning, fabric shampoo, deodoriser. Premium detail: ₹[X] for full interior." },
      { q: "Is water / chemical eco-friendly?",
        a: "Yes — we use biodegradable shampoo, water recycling for non-final rinse, low-flow nozzles. Reduces water use by 60%." },
      { q: "Do you offer doorstep service?",
        a: "Yes — basic wash at your home / office: ₹[X] (above standard rate). Within [X km] in [City]." },
      { q: "Can you remove deep scratches / dents?",
        a: "Light scratches: polishing removes them. Deep scratches / dents: needs body shop work. We can refer to trusted body shops in our network." }
    ]
  };

  // =========================================================
  //  FOOD & BEVERAGE SUB-CATEGORIES
  // =========================================================

  T['restaurant'] = {
    about: [
      "Family-owned restaurant serving [cuisine type] since [Year]. Authentic recipes, fresh ingredients, and warm hospitality. Famous for our [signature dish] across [City].",
      "[Restaurant Name] offers a relaxed dining experience with AC interiors, family seating, and a kid-friendly menu. Pure veg / Veg + Non-Veg / Jain food available.",
      "We use pure ghee, fresh vegetables, and traditional spice blends. Our chefs follow time-tested recipes passed down through generations.",
      "Trusted by [number]+ regulars in [City]. Dine-in, takeaway, party orders, and home delivery via Swiggy / Zomato / direct. Bulk orders welcome.",
      "From quick lunch to special dinner, weekday breakfast to weekend brunch — [Restaurant Name] is your favourite go-to. Reasonable pricing, generous portions."
    ],
    usp: [
      "Authentic [cuisine] · Family recipes · Pure ghee · Fresh ingredients",
      "AC dining · Family seating · Kid menu · Party hall available",
      "Veg / Non-Veg / Jain · Customisable spice level",
      "Famous for [signature dish] · Buffet on [day] · Sunday special",
      "Dine-in · Takeaway · Swiggy / Zomato · Party orders · Catering"
    ],
    faqs: [
      { q: "What are your timings?",
        a: "Lunch: [12 PM – 3:30 PM]. Dinner: [7 PM – 11 PM]. Bar / cafe: [11 AM – 11 PM]. Sunday: open all day." },
      { q: "Do you have AC family seating?",
        a: "Yes — AC dining, separate family section, outdoor garden seating (seasonal). Reservations possible on weekends." },
      { q: "Do you offer pure veg / Jain food?",
        a: "Yes — pure veg section, Jain food without onion-garlic, gluten-free options on request. Notify at order time." },
      { q: "Can I book the place for a party?",
        a: "Yes — full restaurant for 50+ guests. Garden / private hall for 30. Customised menu, decoration, music possible. Quote on visit." },
      { q: "Do you offer home delivery?",
        a: "Yes — direct delivery within [X km] free above ₹[Y]. Swiggy / Zomato city-wide. WhatsApp [number] for direct orders." },
      { q: "Do you have a kids menu?",
        a: "Yes — pasta, sandwich, mini pizza, fries, ice cream. Children high chair, kid-friendly desserts available." },
      { q: "What's your signature dish?",
        a: "[Signature Dish] — must try. Also famous for [Item 2] and [Item 3]. Try the chef's special tasting menu (₹[X] / person, advance notice)." },
      { q: "Do you take advance booking?",
        a: "Yes — recommended for weekends and dinner. Call / WhatsApp [number]. Hold for 15 minutes past booked time." }
    ]
  };

  T['sweets'] = {
    about: [
      "Famous sweet shop in [City] since [Year]. Pure ghee mithai, fresh-made daily, traditional recipes. Famous for [signature sweet] and festival specials.",
      "[Shop Name] is run by [Owner Name], a master halwai with [X] years of experience. We use only pure ingredients — desi ghee, fresh milk, premium dry fruits.",
      "Whether it's daily mithai, festival boxes, or wedding orders, we deliver freshness and taste. Customised packing, bulk discounts, and home delivery.",
      "Trusted by [number]+ families for occasions big and small. Festival specials (Diwali, Holi, Raksha Bandhan, Karwa Chauth), wedding boxes, return gifts.",
      "Pure, fresh, and tasty — that's the [Shop Name] promise. No artificial colours, no preservatives, no compromise. Open early morning for fresh batches."
    ],
    usp: [
      "Pure desi ghee · Fresh milk · Premium dry fruits · No preservatives",
      "Famous for [signature sweet] · Daily fresh · Festival specials",
      "Wedding orders · Bulk discounts · Customised packing",
      "Free home delivery within [X km] · WhatsApp orders",
      "Family halwai since [Year] · Traditional recipes · No shortcuts"
    ],
    faqs: [
      { q: "Do you accept bulk / wedding orders?",
        a: "Yes — wedding box, return gifts, corporate gifting. 24–48 hours advance notice. Bulk discount on orders above ₹[X]." },
      { q: "How long do sweets stay fresh?",
        a: "Khoya / milk-based: 2–3 days refrigerated. Dry sweets (laddu, barfi, kaju katli): 5–7 days. Festival boxes: 7–10 days with care." },
      { q: "Do you use pure desi ghee?",
        a: "Yes — pure desi ghee, fresh milk from local dairies, premium dry fruits. No vanaspati, no palm oil, no artificial colours." },
      { q: "Do you offer customised packing?",
        a: "Yes — branded boxes, gift wrap, ribbon, name printing. Festival specials, wedding theme. Quote on order." },
      { q: "Do you provide home delivery?",
        a: "Yes — free within [X km] above ₹[Y]. WhatsApp [number] for orders. Swiggy / Zomato city-wide for retail items." },
      { q: "Can I order during festivals (Diwali / Holi)?",
        a: "Yes — book 3–7 days advance for popular festivals. Last-minute walk-in welcome but limited stock at peak hours." },
      { q: "Do you have sugar-free / diabetic-friendly sweets?",
        a: "Yes — sugar-free badam halwa, kaju katli, dry fruit laddu. Made with stevia / coconut sugar. Quote on request." },
      { q: "What is your timing?",
        a: "Open from [7 AM – 11 PM] daily. Festival days: extended hours till midnight. Hot snacks (samosa, jalebi): morning + evening only." }
    ]
  };

  T['bakery'] = {
    about: [
      "Artisan bakery serving [City] since [Year]. Fresh cakes, breads, pastries, and customised orders for birthdays, anniversaries, and weddings.",
      "We bake fresh every morning — no day-old products. Premium ingredients, no artificial preservatives, eggless options on request.",
      "From classic chocolate to designer cakes, fondant to photo cakes, we customise every order. WhatsApp design idea + budget for personalised quote.",
      "Trusted by [number]+ customers in [City]. Wedding cakes, corporate orders, school events, return gifts — all handled with care and creativity.",
      "Quality ingredients, skilled bakers, fresh daily — that's our recipe. Open early for breakfast pastries, late for evening cravings."
    ],
    usp: [
      "Fresh daily · Premium ingredients · No preservatives · Eggless option",
      "Customised cakes · Photo · Fondant · Wedding · Designer",
      "Birthday · Anniversary · Wedding · Corporate · Bulk orders",
      "Breads · Pastries · Cookies · Cupcakes · Donuts · Croissants",
      "Same-day delivery · Free above ₹[X] · WhatsApp [number] for design"
    ],
    faqs: [
      { q: "Do you offer eggless cakes?",
        a: "Yes — eggless options for every cake variety (chocolate, vanilla, red velvet, butterscotch, fruit). Mention at order time." },
      { q: "How much advance notice for customised cake?",
        a: "Standard custom cake: 24 hours. Photo cake: 24–36 hours. Fondant / designer / wedding tier cake: 3–5 days. Bulk: 1 week." },
      { q: "Do you have sugar-free / diabetic options?",
        a: "Yes — stevia-based, dry-fruit only, low-sugar versions. Slightly different taste profile but fully diabetic-friendly. Quote on order." },
      { q: "What is the cost of a [chocolate / fondant] cake?",
        a: "Chocolate truffle: ₹[X] / kg. Designer fondant: ₹[Y] / kg. Photo cake: ₹[Z] / kg. Wedding tier (3-tier): ₹[W] onwards." },
      { q: "Do you offer home delivery?",
        a: "Yes — free within [X km] above ₹[Y]. Outside city: chilled box delivery, ₹[Z] extra. Order via WhatsApp [number]." },
      { q: "Can you do wedding / corporate orders?",
        a: "Yes — wedding cakes (multi-tier), corporate gifts, return gift hampers, party platters. Discounts on bulk. Tasting session available." },
      { q: "Are eggs / gelatin / non-veg ingredients used?",
        a: "We use eggs unless eggless specified. Vegetarian gelatin / agar-agar alternatives available on request. 100% veg / vegan options possible." },
      { q: "Do you do classes / tutorials?",
        a: "[Yes — baking workshops on weekends. / Currently only retail bakery.]" }
    ]
  };

  T['tiffin-service'] = {
    about: [
      "Hygienic tiffin / mess service serving home-cooked food since [Year]. Daily fresh meals for students, working professionals, and elderly. Pure veg / Veg + Non-Veg options.",
      "Our kitchen follows strict hygiene standards — bottled water, branded oil (Saffola / Fortune), gas cooking only, no leftovers used. Diet-friendly options available.",
      "Customisable meal plans — daily, weekly, monthly. Diabetic, Jain, vegan, low-oil, gluten-free preferences accommodated.",
      "Trusted by [number]+ subscribers in [City]. Free home delivery, hot food at meal time, and lunch / dinner / both options.",
      "From simple ghar ka khana to special weekend menus, we make food that tastes like home. Mother's recipes, freshness, and care in every tiffin."
    ],
    usp: [
      "Home-cooked taste · Hygienic kitchen · Daily fresh · No preservatives",
      "Pure veg / Veg + Non-Veg / Jain / Vegan options",
      "Daily / Weekly / Monthly plans · Customisable menu",
      "Hot delivery at meal time · Free within [X km] · WhatsApp updates",
      "Diabetic / low-oil / gluten-free options · Diet-friendly"
    ],
    faqs: [
      { q: "What's the monthly subscription cost?",
        a: "Lunch only: ₹[X] / month (30 days). Dinner only: ₹[Y]. Both: ₹[Z]. Pause for travel (advance notice) — refund / extend." },
      { q: "What's in a typical meal?",
        a: "2 chapatis + 1 sabzi + dal + rice + salad + curd + sweet (once a week). Non-Veg: chicken / fish 2x / week (variant plan)." },
      { q: "Do you accommodate dietary restrictions?",
        a: "Yes — Jain, vegan, gluten-free, low-oil, diabetic, post-surgery diet. Discuss at signup; we customise weekly menu." },
      { q: "Is the food packed in steel / aluminium?",
        a: "Steel tiffin (refundable deposit ₹[X]) / hot food container. Microwave-safe options for office delivery." },
      { q: "Do you deliver hot food?",
        a: "Yes — insulated boxes, delivery timed to meal hour. Lunch: 12–1 PM. Dinner: 7–8 PM. Confirmed delivery window." },
      { q: "Can I cancel / pause / change meals?",
        a: "Yes — pause for up to 7 days with 24 hours notice. Meal change (sabzi swap): on weekly menu plan. Cancellation: anytime with 7 days notice." },
      { q: "Is the kitchen FSSAI registered?",
        a: "Yes — FSSAI registered, regular cleaning, branded ingredients (Saffola / Fortune), kitchen visit allowed (advance notice)." },
      { q: "Do you offer trial meal?",
        a: "Yes — 1 trial meal at ₹[X] (full plan cost). If unsatisfied, full refund. We let our food do the talking." }
    ]
  };

  T['cafe'] = {
    about: [
      "Cosy cafe in [City] since [Year]. Specialty coffee, fresh snacks, comfortable seating, and a relaxed vibe — your perfect hangout spot.",
      "We brew our coffee from freshly roasted beans — Arabica blends, single origin, and house specialty. Tea lovers welcome too, with masala chai, green tea, and infusions.",
      "Free WiFi, charging points, AC interiors, and books to borrow. Whether you're working, studying, or catching up with friends — we have a corner for you.",
      "Trusted by students, professionals, and friends groups in [City]. Coffee, snacks, sandwiches, pasta, desserts — full menu through the day.",
      "Quality coffee + relaxed ambiance + reasonable pricing. Open early for morning brew, late for evening conversations."
    ],
    usp: [
      "Specialty coffee · Fresh beans · Single origin · House blend",
      "Free WiFi · Charging points · AC · Books to read",
      "Sandwich · Pasta · Cake · Smoothie · Healthy bowls",
      "Student-friendly · Loyalty card · Group discounts",
      "Open early · Late night options · Catering for events"
    ],
    faqs: [
      { q: "Do you have WiFi and charging points?",
        a: "Yes — free high-speed WiFi, charging points at most tables. Work-from-cafe friendly." },
      { q: "What's special on the menu?",
        a: "Specialty coffee (try our [signature drink]), house cakes, healthy salad bowls, paneer wrap, baked goods. Customisable for diet preferences." },
      { q: "Can I work / study here for long hours?",
        a: "Yes — but please make a minimum order (drink + snack). Peak hours (12–2 PM, 6–8 PM): we appreciate shorter stays." },
      { q: "Do you offer breakfast / late-night?",
        a: "Breakfast: 8–11 AM (eggs, toast, smoothies). Late-night: open till [11 PM]. Hot chocolate, herbal tea evening." },
      { q: "Is there a loyalty / membership program?",
        a: "Yes — buy 9 drinks, 10th free. Premium members: 10% off, priority seating, free upgrades. Sign up free at counter." },
      { q: "Do you cater for events?",
        a: "Yes — corporate offsite, baby shower, small parties (15–40 pax). Customised menu, set-up included. Quote on visit." },
      { q: "Are pets allowed?",
        a: "[Yes — outdoor seating welcomes pets. Indoor: no. / Yes throughout — pet-friendly cafe. / No — sorry.]" },
      { q: "Can I host a small event / book reading / open mic?",
        a: "Yes — Friday evenings free for community events. WhatsApp to book. Just need 10+ attendees commitment." }
    ]
  };

  T['juice-corner'] = {
    about: [
      "Fresh juice / shake / smoothie corner in [City] since [Year]. Daily fresh fruits, hygienic preparation, no concentrate, no added preservatives.",
      "We source fruits daily from the local mandi — seasonal, ripe, washed thoroughly. Our shakes use full-cream milk, our juices use only fruit (no sugar added unless requested).",
      "From simple orange juice to detox green smoothies, gym shakes to fruit bowls — we cater to everyone's taste and health goals.",
      "Trusted by [number]+ regulars in [City]. Pre-workout, post-workout, healthy breakfast bowls, summer coolers — all under one roof.",
      "Pure, fresh, healthy — no compromises. Sugar-free options, lactose-free options, vegan options on request. Tap water filtered (RO + UV)."
    ],
    usp: [
      "Daily fresh fruits · Hygienic prep · No concentrate · No preservatives",
      "Juice · Shake · Smoothie · Lassi · Bowl · Detox · Coolers",
      "Sugar-free · Lactose-free · Vegan · Diet-conscious options",
      "Filtered RO water · Branded milk · Hygienic blender",
      "Pre / post workout shakes · Health bowls · Breakfast options"
    ],
    faqs: [
      { q: "Do you add sugar / preservatives?",
        a: "Sugar: only if you ask. Most juices have natural sweetness. Preservatives: NEVER. Made fresh on order." },
      { q: "Are the fruits washed and clean?",
        a: "Yes — sourced daily, washed with food-safe veg wash, peeled / sliced on order. Hygiene is our priority." },
      { q: "Do you offer sugar-free / diabetic-friendly?",
        a: "Yes — no-sugar juice (just fruit), stevia-sweetened shakes, vegetable juice (cucumber-amla-tulsi-mint), diet bowls." },
      { q: "What about lactose intolerance / vegan?",
        a: "Yes — almond milk, coconut milk, soy milk available for shakes / smoothies. Coconut yogurt option for vegan." },
      { q: "What are your timings?",
        a: "[7 AM – 10 PM] daily. Morning rush: 7–10 AM (breakfast bowls). Post-gym: 5–8 PM (protein shakes)." },
      { q: "Is the water / ice safe?",
        a: "Yes — RO + UV filtered water, ice made from filtered water. No tap water used anywhere." },
      { q: "Do you offer protein shakes for gym?",
        a: "Yes — whey, casein, plant protein (Optimum / Muscleblaze). Customised with banana, peanut butter, oats. Pre / post / mass-gain variants." },
      { q: "Do you do home delivery?",
        a: "[Yes — within [X km], chilled delivery. / Walk-in only.]" }
    ]
  };

  T['ice-cream'] = {
    about: [
      "Premium ice cream parlour with [X]+ flavours, including ice cream, kulfi, sundae, falooda, and seasonal specials. Made with real ingredients, no artificial colours.",
      "We serve branded ice creams (Amul, Kwality Walls, Vadilal, Baskin Robbins) along with house-made traditional kulfi and faloodas.",
      "From a single scoop to family party orders, we cater to all needs. Cake ice cream, ice cream cake, customised hampers for celebrations.",
      "Trusted by families in [City] for treats, parties, and gift hampers. Open till late, kid-friendly, AC interiors.",
      "Pure ingredients, generous portions, fair prices. Sugar-free, diabetic options, dairy-free sorbet on request."
    ],
    usp: [
      "[X]+ flavours · Real fruit · Real cocoa · No artificial colour",
      "Amul · Kwality Walls · Vadilal · Baskin Robbins · House-made kulfi",
      "Sundae · Falooda · Ice cream cake · Party tubs",
      "Sugar-free / diabetic / vegan / sorbet options",
      "Open till late · Kid-friendly · AC seating · Party orders"
    ],
    faqs: [
      { q: "Do you have sugar-free options?",
        a: "Yes — sugar-free vanilla, chocolate, mango, strawberry (made with stevia / sucralose). Diabetic-safe but tasty." },
      { q: "Do you offer party orders / tubs?",
        a: "Yes — 500 ml / 1 L / 5 L family tubs at discount. Party combo: 5 tubs + cones + toppings. Free home delivery above ₹[X]." },
      { q: "What's the price of a regular scoop?",
        a: "Single scoop: ₹[X]. Double: ₹[Y]. Premium / Belgian / Italian: ₹[Z]. Sundae: ₹[W] onwards." },
      { q: "Do you have ice cream cake?",
        a: "Yes — fresh ice cream cake (assorted layers), birthday customisation, photo cake. 4 hours advance notice. From ₹[X] / kg." },
      { q: "Are ingredients fresh / branded?",
        a: "Yes — Amul / Kwality Walls / Vadilal / Baskin (factory-sealed). House-made kulfi: fresh milk, dry fruits, no preservatives." },
      { q: "Do you offer dairy-free / vegan sorbet?",
        a: "Yes — fruit sorbet (mango, raspberry, lime), coconut-milk based ice creams. Lactose-intolerant friendly." },
      { q: "What are your timings?",
        a: "[12 PM – 11:30 PM] daily. Summer extended hours till midnight. Open Sundays and holidays." },
      { q: "Do you do home delivery?",
        a: "Yes — within [X km] in insulated boxes (no melt). Free above ₹[Y]. Swiggy / Zomato also available." }
    ]
  };

  // =========================================================
  //  RETAIL & SHOPPING SUB-CATEGORIES
  // =========================================================

  T['grocery'] = {
    about: [
      "Trusted neighbourhood grocery store serving [City] since [Year]. Fresh stock, branded products, daily essentials, and home delivery.",
      "We stock everything you need — daily groceries, dals, oil, rice, atta, ghee, spices, packaged food, dairy, personal care, household cleaning.",
      "Branded + local products at competitive prices. Bulk discounts for monthly shopping, free home delivery, and credit option for regulars.",
      "[Number]+ households shop with us regularly. Convenient location, friendly staff, and personalised attention — we know our customers by name.",
      "From a single sachet to a month's full grocery, we serve you with the same care. WhatsApp grocery list — we pack and deliver."
    ],
    usp: [
      "Fresh stock · Branded products · Daily essentials · Best prices",
      "Branded: Tata Salt · Saffola · Fortune · Aashirvaad · Patanjali",
      "Free home delivery above ₹[X] · WhatsApp grocery list",
      "Monthly shopping discount · Credit for regulars · Loyalty bonus",
      "Bulk / wedding orders · Festival hampers · Office canteen supply"
    ],
    faqs: [
      { q: "Do you offer home delivery?",
        a: "Yes — free within [X km] above ₹[Y] order. WhatsApp [number] your list / photo of items needed. Same-day / next-day delivery." },
      { q: "Are your products fresh and within expiry?",
        a: "Yes — daily / weekly stock rotation. Expiry checked at receiving. Any product close to expiry is sold at clearance price (disclosed)." },
      { q: "Do you have monthly shopping discount?",
        a: "Yes — bill above ₹[X]: 3% off. Above ₹[Y]: 5% off. Above ₹[Z]: 7% off. WhatsApp full grocery list for combined discount." },
      { q: "Do you accept UPI / cards?",
        a: "Yes — cash, UPI (PhonePe / GPay / Paytm), debit / credit cards (above ₹[X] order)." },
      { q: "Do you do wedding / festival bulk orders?",
        a: "Yes — wedding hampers, festival gift boxes, corporate gifting. Bulk discount + customised packing. 24–48 hours advance notice." },
      { q: "What if a product is missing / damaged?",
        a: "Replacement or refund the same day. Just call within 24 hours of delivery. Photo proof helps speed it up." },
      { q: "Do you have organic / brand-specific items?",
        a: "[Yes — organic atta, pulses, oil, spices. Patanjali / Organic India / 24 Mantra sections.]" },
      { q: "Can I get credit for monthly bill?",
        a: "Yes — for verified regulars after 3 months relationship. Monthly settlement, no interest. Trust-based system." }
    ]
  };

  T['clothes'] = {
    about: [
      "Family clothing shop with men's, women's, and kids' collections. Branded + local manufacturers, latest trends, traditional + western, casual + formal.",
      "We update collections every season — festive, winter, summer, wedding. Trusted brands and reasonable prices. Free alteration with every purchase.",
      "Trial room available, exchange policy fair. Take your time, we'll help you choose. No pressure selling.",
      "Trusted by [number]+ families in [City] for daily wear to wedding outfits. Special discounts during festivals, end-of-season clearance.",
      "Affordable elegance — quality fabric, fair price, friendly service. Bulk orders for weddings, schools, and corporate uniforms welcomed."
    ],
    usp: [
      "Men's · Women's · Kids · Casual · Formal · Traditional · Western",
      "Branded + local · Trial room · Free alteration · Exchange policy",
      "Festival collections · Wedding wear · Seasonal updates · Sale offers",
      "Bulk orders for wedding / school / corporate · Custom stitching",
      "Cash / UPI / Card · No-cost EMI on credit cards · GST bill"
    ],
    faqs: [
      { q: "Do you offer free alteration?",
        a: "Yes — free length, waist, sleeve alteration with purchase. Major alterations (re-styling): ₹[X] charge." },
      { q: "What's your exchange / return policy?",
        a: "Exchange within [7–15 days] with bill, in unused condition with tags. Refund: only on manufacturing defect." },
      { q: "Do you have wedding / festive collection?",
        a: "Yes — sarees, lehengas, suits, sherwanis, kurta-pajamas. Bridal section with appointment booking." },
      { q: "Can I get custom stitching?",
        a: "Yes — in-house tailor for ladies suits, blouses, men's shirts / pants. Quote depends on style and fabric." },
      { q: "Do you do bulk / school uniform orders?",
        a: "Yes — wedding parties, school uniforms, corporate dress code. Bulk discount on orders above ₹[X]. Sample available before bulk." },
      { q: "What payment methods?",
        a: "Cash, UPI, debit / credit cards. No-cost EMI on credit cards above ₹[X]. GST bill on request." },
      { q: "Do you have brand authorised collection?",
        a: "[Yes — authorised dealer for X, Y, Z. / Multi-brand store with selected branded + manufacturer stock.]" },
      { q: "Do you offer home delivery / trial at home?",
        a: "Yes — within [X km], free above ₹[Y]. Trial at home: WhatsApp size, we send 3 options (returnable)." }
    ]
  };

  T['jewellery'] = {
    about: [
      "Trusted jewellery shop with [X] years of experience. Pure 22K / 18K gold, silver, diamond, and platinum. BIS hallmarked, certified, and transparent pricing.",
      "From daily wear to wedding jewellery, we stock authentic, hallmarked pieces. Buyback at fair market rate, exchange against new purchase.",
      "Every gold piece is BIS hallmarked (916 / 750), every diamond IGI / GIA certified. Pricing as per daily market rate, fully transparent.",
      "Trusted by [number]+ families in [City] for over [X] years. Wedding sets, gold investment, gift jewellery — all under one trusted roof.",
      "Honest jewellery business — daily rate displayed, making charges disclosed, buyback at full gold value (only refining loss deducted). Build wealth in gold with confidence."
    ],
    usp: [
      "BIS hallmarked · 22K / 18K gold · IGI / GIA certified diamond",
      "Daily rate transparent · Making charges disclosed · No hidden costs",
      "Wedding sets · Daily wear · Investment coins / bars · Silver",
      "Buyback at market rate · Exchange welcome · Insurance available",
      "Custom designs · Gold testing · Repair / polishing service"
    ],
    faqs: [
      { q: "Is your gold BIS hallmarked?",
        a: "Yes — every piece BIS hallmarked (916 for 22K, 750 for 18K). HUID number tagged. Test in our presence anytime." },
      { q: "How is the price calculated?",
        a: "Gold value (weight × today's rate) + making charges (% of gold) + GST (3% on total). Final price disclosed before purchase." },
      { q: "What's the buyback policy?",
        a: "We buy back gold at current market rate (minus refining loss, ~2–3%). Diamond / stones: at original cost (with bill) less depreciation." },
      { q: "Can I exchange old gold against new?",
        a: "Yes — exchange at full gold value (only refining loss deducted). Difference paid as new purchase. Bills not mandatory but help." },
      { q: "Do you offer custom designs?",
        a: "Yes — in-house karigar. WhatsApp design idea or sketch. 7–15 days to deliver. Wax model approval before final casting." },
      { q: "Is there a return / refund policy?",
        a: "Exchange within [15 days] (no use, original condition). Refund: only on manufacturing defect (within 30 days). Buyback always at market rate." },
      { q: "Do you offer EMI / gold saving schemes?",
        a: "Yes — monthly gold deposit scheme (11 month + 1 free). EMI on credit cards. Some banks offer gold loan within store." },
      { q: "Is the diamond certified?",
        a: "Yes — IGI / GIA / SGL certified diamonds above 0.30 carat. Certificate provided with purchase. Loose diamond also available with cert." }
    ]
  };

  T['mobile-shop'] = {
    about: [
      "Authorised mobile shop with full range of smartphones, accessories, and services. New mobile sales, recharges, repair, and exchange — all under one roof.",
      "We stock all brands — Samsung, Apple, Xiaomi, OnePlus, Vivo, Oppo, Realme, Nothing. Best price guarantee with bill + warranty.",
      "Repair service for screen, battery, charging port, software issues. Original parts, transparent quotes, while-you-wait service for minor fixes.",
      "Trusted by [number]+ customers in [City]. Recharges, DTH, FASTag, Aadhaar update, and online services as one-stop convenience.",
      "Authorised dealer with genuine stock, warranty card, and bill — what you see is what you get. No grey market, no fake products."
    ],
    usp: [
      "Authorised dealer · All brands · Original stock · Bill + warranty",
      "Samsung · Apple · Xiaomi · OnePlus · Vivo · Oppo · Realme",
      "Repair: screen · battery · charging port · software",
      "Recharge · DTH · FASTag · Aadhaar update · UPI services",
      "Exchange offers · EMI on credit / no-cost · Insurance available"
    ],
    faqs: [
      { q: "Are the mobiles genuine with bill / warranty?",
        a: "Yes — authorised stock with manufacturer warranty (1 year typically). Bill + IMEI registered with brand for warranty." },
      { q: "Do you offer exchange / buyback?",
        a: "Yes — exchange your old phone for new (fair valuation based on condition). Buyback: spot cash payment after inspection." },
      { q: "Can you repair my screen / battery?",
        a: "Yes — original screen replacement, battery, charging port. Quote shared before work. Same-day for most repairs." },
      { q: "Do you offer EMI?",
        a: "Yes — no-cost EMI on credit cards (HDFC, SBI, ICICI, etc.). Bajaj Finserv on-spot card. EMI from 3 to 24 months." },
      { q: "Do you do mobile insurance / extended warranty?",
        a: "Yes — accidental damage protection, extended warranty (1–2 years). 7% of phone value typically. Worth it for premium phones." },
      { q: "Do you sell accessories — covers, chargers, earphones?",
        a: "Yes — full range. Brands: Apple, Samsung, OnePlus, Boat, JBL, Mi, Realme. Cheap to premium options." },
      { q: "What other services do you offer?",
        a: "Recharge (all networks), DTH, FASTag, Aadhaar update / print, UPI registration, money transfer, bill payment." },
      { q: "What if my phone has a manufacturing defect?",
        a: "Within warranty: brand handles via authorised service centre. We coordinate and follow up. Defective on receipt: replacement immediately." }
    ]
  };

  T['electronics'] = {
    about: [
      "Authorised electronics retailer with full range of home appliances — TV, AC, fridge, washing machine, microwave, water purifier, kitchen appliances.",
      "We stock all major brands — LG, Samsung, Sony, Whirlpool, Voltas, Daikin, Haier, Bosch, IFB. Authorised dealer with bill, warranty, and installation.",
      "From a small mixer-grinder to a 65-inch QLED TV, our showroom has it all. Demo, comparison, and expert advice before you buy.",
      "Trusted by [number]+ households in [City]. Free delivery within city, professional installation, and authorised after-sales service tie-up.",
      "Best price guarantee, no-cost EMI, exchange offers, and seasonal discounts. We make premium appliances accessible to every family."
    ],
    usp: [
      "Authorised dealer · LG · Samsung · Sony · Whirlpool · Voltas · Daikin",
      "TV · AC · Fridge · Washing Machine · Microwave · Kitchen · Water purifier",
      "Free delivery + installation · Bill + warranty · No-cost EMI",
      "Exchange offers · Seasonal sales · Corporate / bulk discount",
      "After-sales service tie-up · Demo before purchase"
    ],
    faqs: [
      { q: "Do you offer free home delivery and installation?",
        a: "Yes — free delivery within [X km] in [City]. Installation: free for most products. Big appliances (AC / wash machine): standard installation charges from manufacturer." },
      { q: "Is no-cost EMI available?",
        a: "Yes — on most credit cards (HDFC, ICICI, SBI, Axis), Bajaj Finserv, IDFC. 3 to 24 months. Some products: cardless EMI." },
      { q: "Do you have exchange offer?",
        a: "Yes — exchange your old TV / AC / fridge / washing machine. Valuation based on age and condition. Big saving on new purchase." },
      { q: "Will the warranty be honoured?",
        a: "Yes — manufacturer warranty (1–10 years depending on product). Authorised dealer with proper invoice. Service centre coordinates with us." },
      { q: "Can I test / demo before buying?",
        a: "Yes — live demo for TV (sound, picture quality), fridge (cooling, energy), AC (cooling, noise). Comparison between models." },
      { q: "Do you offer extended warranty?",
        a: "Yes — extended warranty (additional 1–3 years). Worth it for premium / heavy-use appliances. Cost: 5–10% of product price." },
      { q: "What if my product has manufacturing defect?",
        a: "DOA (dead on arrival) within 7 days: replacement. Within warranty: authorised service centre repair. We coordinate fully." },
      { q: "Do you accept cards / UPI / corporate orders?",
        a: "Yes — all payment modes. Corporate orders: GST invoice, bulk discount, delivery to office. Government tenders also handled." }
    ]
  };

  T['footwear'] = {
    about: [
      "Trusted footwear shop with men's, women's, and kids' collections. Branded + local, casual + formal, sports + traditional, daily + party wear.",
      "We stock Bata, Liberty, Paragon, Relaxo, Campus, Sparx, Action, Nike (selected), Adidas (selected), Puma (selected). Try-on welcome.",
      "Comfort + style + durability — three factors we never compromise. Wide range of sizes, including hard-to-find big / small sizes.",
      "Trusted by families in [City] for daily walking, office formal, sports, party, and traditional weddings. Festive collections and discounts.",
      "Reasonable prices, exchange policy fair, free polish with leather purchases. Care guide shared so your shoes last longer."
    ],
    usp: [
      "Bata · Liberty · Paragon · Relaxo · Campus · Sparx · Action",
      "Men's · Women's · Kids · Casual · Formal · Sports · Traditional",
      "All sizes (4–13 men, 3–10 women, kids 6–12) · Try-on free",
      "Exchange within 7 days · Bill + warranty · No-cost EMI on cards",
      "Festive collections · School shoes · Wedding sherwani footwear"
    ],
    faqs: [
      { q: "Do you have my size?",
        a: "We stock UK 4–13 for men, 3–10 for women, kids 6–12. Big / small / wide-fit options on request. Tell us size and we confirm." },
      { q: "What's the price range?",
        a: "₹300 (basic chappals) to ₹6000 (premium leather formal). Brand sneakers: ₹1500–4000. Sports: ₹800–3500." },
      { q: "Can I exchange / return?",
        a: "Exchange within 7 days, unused, with bill. Refund: only on manufacturing defect within 30 days." },
      { q: "Do you offer warranty?",
        a: "Manufacturing defect: 30 days to 6 months as per brand. Sole damage / colour fade: 30-day exchange." },
      { q: "Do you stock school shoes / uniforms?",
        a: "Yes — school shoes (black / white / sports type) for major school dress code. Bulk discount on parent groups." },
      { q: "Do you have wedding / festive footwear?",
        a: "Yes — bridal heels, kolhapuri, mojadi, sherwani shoes, ethnic juti. Wedding pack discount." },
      { q: "Do you offer free polish / care?",
        a: "Free polish at purchase. Lifetime free polish for leather customers (visit anytime). Care guide shared at billing." },
      { q: "Do you do bulk / corporate orders?",
        a: "Yes — school uniform, hotel staff, factory worker safety shoes. Bulk discount + custom logo embossing (volume permitting)." }
    ]
  };

  T['stationery'] = {
    about: [
      "Complete stationery and book shop serving students, professionals, and offices. Full range of pens, pencils, notebooks, school supplies, art materials, gifts.",
      "We stock branded items — Camlin, Faber-Castell, Reynolds, Cello, Doms, Classmate, Pidilite, Apsara. Also competitive exam books, novels, kids books.",
      "Printing, photocopying, scanning, lamination, binding — all in-house. Office supply, school project material, art and craft supplies in one place.",
      "Trusted by students of all major schools in [City]. Specialised stationery for IIT / NEET / CA / banking exam preparation. Used books exchange available.",
      "From a single pen to bulk school stationery, we serve every need with care. Personalised attention to school list, project requirements, office orders."
    ],
    usp: [
      "Complete stationery · Camlin · Faber-Castell · Reynolds · Cello · Doms",
      "School supplies · Office supplies · Art & craft · Competitive exam books",
      "Printing · Photocopy · Scan · Lamination · Binding · Spiral",
      "Used books exchange · Project materials · Custom labelling",
      "Bulk school / office orders · Festival cards · Gift items"
    ],
    faqs: [
      { q: "Do you have school books / notebooks?",
        a: "Yes — all major schools' booklists, plus generic notebooks (Classmate / ITC / Navneet). Booklist on WhatsApp for instant quote." },
      { q: "Do you do printing / photocopy?",
        a: "Yes — B&W: ₹[X] / page. Colour: ₹[Y] / page. Lamination: ₹[Z] / A4. Binding: spiral / hard-bind options." },
      { q: "Do you stock competitive exam books?",
        a: "Yes — IIT JEE, NEET, NDA, banking (IBPS / SBI), SSC, UPSC, CA, GATE. Latest editions, sample papers, mock test books." },
      { q: "Can I bulk-order school stationery list?",
        a: "Yes — WhatsApp class + section + school name. We prepare full set, you collect. Discount on full-list purchase." },
      { q: "Do you accept used book exchange?",
        a: "[Yes — used books exchange (50% off new price for usable, less for old editions). / Selective titles only.]" },
      { q: "Do you do greeting cards / gift wrap?",
        a: "Yes — festival cards (Diwali / Raksha Bandhan / New Year), birthday, anniversary. Gift wrap free with purchases." },
      { q: "Can you supply office stationery monthly?",
        a: "Yes — monthly office orders (paper, pen, file, marker, sticky notes). Bulk discount + invoice. Delivery within city." },
      { q: "Do you have art and craft supplies?",
        a: "Yes — paint, brushes, canvas, sketchbooks, craft paper, glue, scissors, beads. School project materials too." }
    ]
  };

  T['gift-shop'] = {
    about: [
      "Curated gift shop with thoughtful items for every occasion — birthday, anniversary, wedding, baby shower, Diwali, Rakhi, Valentine's Day, corporate gifting.",
      "We stock photo frames, personalised mugs, photo cushions, customised t-shirts, chocolates, dry fruit boxes, decorative items, soft toys, candles.",
      "Free gift wrapping with purchase, customisation available (name, photo, message). Same-day delivery within city for last-minute occasions.",
      "Trusted gift destination in [City] for [number]+ customers. Bulk return gift orders, baby shower combos, wedding hampers, corporate gifting.",
      "Beautiful gifts that say what words can't. Whether you have ₹200 or ₹2000, we'll help you find something special."
    ],
    usp: [
      "Birthday · Anniversary · Wedding · Baby shower · Festival · Corporate",
      "Customised: name · photo · message · printing · embroidery",
      "Photo frames · Mugs · Cushions · T-shirts · Chocolates · Dry fruits",
      "Free gift wrap · Same-day delivery · WhatsApp the recipient",
      "Bulk return gifts · Wedding hampers · Corporate orders · GST bill"
    ],
    faqs: [
      { q: "Can you customise gifts with photo / name?",
        a: "Yes — photo on mug / cushion / frame / t-shirt. Name engraving on pen, key chain, gift box. 24–48 hours for customisation." },
      { q: "Do you offer same-day delivery?",
        a: "Yes — within [X km] for in-stock items. Order before [12 PM] for same-day. WhatsApp the gift to be delivered directly with note." },
      { q: "What's the price range?",
        a: "₹200 (small gifts) to ₹5000+ (premium hampers). Customised items: ₹500–2000 typically. Bulk: discount applies." },
      { q: "Do you do return gifts for parties / baby shower?",
        a: "Yes — bulk return gift sets from ₹100 / piece. Themes: baby shower, birthday, wedding. Quantity discounts." },
      { q: "Do you offer corporate gifting?",
        a: "Yes — Diwali, New Year, employee anniversary, client gifting. Custom packaging with company logo. GST invoice." },
      { q: "Can I order online / from another city?",
        a: "Yes — WhatsApp + UPI payment. We deliver across [City] same day, intercity via courier (2–4 days)." },
      { q: "Do you have flowers / cake combo?",
        a: "[Yes — partner with local florist + bakery for flower + cake + gift combos. / Gift only, no flowers / cake.]" },
      { q: "What if the gift is damaged in delivery?",
        a: "Replacement / refund. Photo proof helps. Contact within 24 hours of delivery for fastest resolution." }
    ]
  };

  T['general-store'] = {
    about: [
      "Your neighbourhood general store with everything from cosmetics to crockery, household to stationery, toys to electronics — under one roof.",
      "We stock daily needs, cosmetic items (L'Oreal, Lakme, Maybelline), household cleaning, plastic ware, kitchen items, baby products, festival items.",
      "Convenient location, friendly staff, and personal touch — we know what our regulars need. Free home delivery within [X km] for orders above ₹[Y].",
      "Trusted shop for [number]+ households in [Locality]. From a single soap to monthly bulk shopping, we serve every customer with care.",
      "Branded + local options, fair pricing, fresh stock. We don't run out of basics — daily replenishment ensures you always find what you need."
    ],
    usp: [
      "Daily essentials · Cosmetics · Household · Plastic ware · Toys",
      "Branded: L'Oreal · Lakme · Maybelline · Garnier · Surf · Tide",
      "Free home delivery · Bulk discount · Loyalty card",
      "Festival items · Pooja samagri · Decoration · Gifts",
      "Cash · UPI · Cards · Credit for verified regulars"
    ],
    faqs: [
      { q: "Do you stock branded cosmetics?",
        a: "Yes — L'Oreal, Lakme, Maybelline, Garnier, Nivea, Lotus, Himalaya, Patanjali. Skincare, haircare, makeup full range." },
      { q: "Do you offer free home delivery?",
        a: "Yes — within [X km] above ₹[Y] order. WhatsApp [number] your needs. Same-day for in-stock items." },
      { q: "Do you have pooja samagri / festival items?",
        a: "Yes — daily pooja items (agarbatti, camphor, ghee, kumkum). Festival kits for Diwali, Holi, Karwa Chauth, Rakhi." },
      { q: "Do you stock baby products?",
        a: "Yes — diapers (Pampers, MamyPoko, Himalaya), wipes, baby food (Cerelac), powder, oil, soap, feeding bottle." },
      { q: "Are prices fair / MRP?",
        a: "Yes — MRP-based. Small discount on bulk / loyalty card. No mark-up above MRP on any product." },
      { q: "Do you have plastic ware / kitchen items?",
        a: "Yes — Tupperware-style containers, milton bottles, casserole, pressure cooker, knife set, kitchen utensils." },
      { q: "What payment methods?",
        a: "Cash, UPI (PhonePe / GPay / Paytm), debit / credit card (above ₹[X])." },
      { q: "Do you give credit for regular customers?",
        a: "Yes — verified regulars after 3+ months. Monthly settlement, no interest. Trust-based system." }
    ]
  };

  // =========================================================
  //  BEAUTY & WELLNESS SUB-CATEGORIES
  // =========================================================

  T['salon'] = {
    about: [
      "Premium unisex / ladies / gents salon in [City] since [Year]. Trained stylists, branded products, hygienic tools, and a comfortable atmosphere.",
      "We offer haircut, hair colour, hair spa, skin care, facials, threading, waxing, manicure-pedicure, mehndi, bridal packages — full grooming under one roof.",
      "Branded products: L'Oreal, Schwarzkopf, Wella, Lakme, VLCC. Disposable kits for every client. Trained staff with industry certifications.",
      "Trusted by [number]+ regulars in [City]. Walk-ins welcome, appointments preferred for premium services. Online booking via WhatsApp.",
      "Look good and feel great — that's our promise. Affordable luxury, latest trends, friendly staff. Bridal and pre-wedding packages our specialty."
    ],
    usp: [
      "Trained stylists · Branded products · L'Oreal · Schwarzkopf · Wella · Lakme",
      "Disposable kits · Hygienic stations · Trained team · Bilingual",
      "Hair · Skin · Nails · Mehndi · Bridal · Pre-wedding packages",
      "Walk-in welcome · WhatsApp appointment · Online booking",
      "Membership discount · Loyalty rewards · Home service available"
    ],
    faqs: [
      { q: "What services do you offer?",
        a: "Haircut, hair colour, hair spa, smoothening, keratin, facials, cleanup, threading, waxing, manicure, pedicure, mehndi, bridal makeup." },
      { q: "Are your tools sterilized / disposable?",
        a: "Yes — disposable kits for waxing, manicure, pedicure. Tools sterilised between clients. Hygiene is non-negotiable." },
      { q: "What's the price for a haircut / facial?",
        a: "Haircut: men ₹[X], women ₹[Y] (basic) to ₹[Z] (premium stylist). Facial: ₹[A] (basic) to ₹[B] (luxury). Full price list on WhatsApp." },
      { q: "Do you do bridal makeup?",
        a: "Yes — bridal HD makeup, party makeup, pre-wedding shoot, mehndi. Package: ₹[X] – ₹[Y]. Trial session 15 days before." },
      { q: "Do you offer membership?",
        a: "Yes — monthly: ₹[X] for 4 services / 10% off everything. Annual: ₹[Y] for 24 services. Best value for regular clients." },
      { q: "Do you offer home service?",
        a: "Yes — bridal at home, pre-wedding rituals at home. Daily services at home: 25–30% extra. Within [X km] in [City]." },
      { q: "What products do you use?",
        a: "L'Oreal Professional, Schwarzkopf, Wella, Lakme Salon, VLCC. For sensitive skin: Cheryl's, O3+. Customer can also bring own product." },
      { q: "Do you have kids haircut / mom-friendly section?",
        a: "[Yes — kids haircut, family-friendly stations, ladies-only floor. / Unisex but separate sections.]" }
    ]
  };

  T['gym'] = {
    about: [
      "Modern fitness gym with cardio, weight training, free weights, functional zones, and personal trainers. AC, hygienic, well-ventilated, and motivating environment.",
      "Equipment from [Cybex / Life Fitness / Technogym / Cosco / brand]. Certified trainers, fitness assessment, customised workout plan, and diet guidance.",
      "Whether you want weight loss, muscle gain, or general fitness — our certified trainers design a plan that works for you. Group classes (yoga, Zumba, HIIT) included.",
      "Trusted by [number]+ members across [City]. Affordable monthly plans, family discount, student offer. Free trial session available.",
      "Fitness is a journey — and we walk it with you. Beginner-friendly, no judgment, no pressure. Just real results through consistent effort."
    ],
    usp: [
      "Modern equipment · Cybex · Life Fitness · Technogym · Cosco",
      "Certified trainers · Customised plan · Diet guidance",
      "Cardio · Weights · Functional · Group classes · Yoga · Zumba",
      "AC · Hygienic · CCTV monitored · Music · Towel service",
      "Family discount · Student offer · Free trial · Free first month diet"
    ],
    faqs: [
      { q: "What's the membership fee?",
        a: "Monthly: ₹[X]. Quarterly: ₹[Y] (20% saved). Half-yearly: ₹[Z] (30% saved). Annual: ₹[W] (40% saved). Family discount: 10% extra." },
      { q: "Do I get a personal trainer?",
        a: "Group sessions: free with membership. Dedicated personal trainer: ₹[X] extra / month. Beginner orientation: free 3 sessions." },
      { q: "Is diet plan included?",
        a: "Free basic diet chart with membership. Personalised diet by qualified nutritionist: ₹[X] one-time + monthly review." },
      { q: "What are the timings?",
        a: "[5 AM – 11 PM] all days. Peak: 6–9 AM, 6–9 PM. Less crowded: 10 AM – 5 PM. Sunday: limited hours [7 AM – 1 PM]." },
      { q: "Do you have group classes / yoga / Zumba?",
        a: "Yes — yoga, Zumba, HIIT, aerobics, kick-boxing. Daily schedule shared on WhatsApp / notice board. Free with full membership." },
      { q: "Is there a women's-only section / timing?",
        a: "[Yes — ladies floor / ladies-only 4–6 PM session. / Unisex floor with separate change rooms.]" },
      { q: "Can I freeze my membership when travelling?",
        a: "Yes — freeze for [up to 30 days] without losing months. Just notify in advance. Medical emergencies: longer freeze possible." },
      { q: "Do you offer a free trial?",
        a: "Yes — first session free with valid ID. Trial allows you to use all equipment + 1 group class. No obligation to join." }
    ]
  };

  T['yoga-center'] = {
    about: [
      "Authentic yoga and meditation centre with certified instructors. Hatha, Vinyasa, Ashtanga, Pranayama, Meditation — classical practice in modern setting.",
      "Founded by [Founder Name], certified yoga teacher with [X] years of experience. We teach yoga as a complete way of life — asana, pranayama, dhyana, diet, lifestyle.",
      "Suitable for all levels — beginner, intermediate, advanced. Therapy yoga for back pain, knee pain, diabetes, hypertension, stress, weight loss.",
      "Trusted by [number]+ practitioners. Morning and evening batches, weekend workshops, special therapy sessions, kid's yoga, prenatal yoga.",
      "Yoga is medicine, meditation, and movement combined. Our centre offers a peaceful space for practice, learning, and inner growth."
    ],
    usp: [
      "Certified instructors · Hatha · Vinyasa · Ashtanga · Pranayama",
      "Therapy yoga · Back pain · Knee · Diabetes · BP · Stress · Weight loss",
      "Beginner to advanced · Kids · Senior citizens · Prenatal · Postnatal",
      "Morning + evening batches · Weekend workshops · Personalised sessions",
      "Affordable monthly fee · Drop-in classes · Online classes available"
    ],
    faqs: [
      { q: "I'm a beginner — can I join?",
        a: "Absolutely — our beginner batch starts gentle, teaches alignment, breathing. No prior experience needed. First week is foundational." },
      { q: "What's the monthly fee?",
        a: "Group: ₹[X] / month (unlimited classes). Drop-in: ₹[Y] per class. Personal session: ₹[Z] / hour. Therapy yoga: ₹[W] / month." },
      { q: "Do you have therapy yoga for medical conditions?",
        a: "Yes — back pain, knee pain, diabetes, hypertension, thyroid, PCOD, asthma, depression, anxiety. Adapted practice with focused outcomes." },
      { q: "Are batches by age / level / gender?",
        a: "Yes — beginner, intermediate, advanced. Senior citizens (gentle), kids, prenatal, postnatal. Separate ladies batch available." },
      { q: "Do you do online classes?",
        a: "Yes — live online via Zoom. Recorded library for members. Useful for travel, illness, when away from city." },
      { q: "Will I lose weight with yoga?",
        a: "Yes — combined with diet and consistency. Power yoga / Surya Namaskar variants burn 300–500 cal/hour. Sustainable, mind-body transformation." },
      { q: "What should I bring to class?",
        a: "Loose comfortable clothes, water bottle, yoga mat (or rent / buy at centre). Empty stomach (or light snack 1.5 hours before)." },
      { q: "Do you offer workshops / retreats?",
        a: "Yes — weekend workshops monthly (specific topic: pranayama, advanced asana, meditation). Retreats yearly (3-day intensive)." }
    ]
  };

  T['spa'] = {
    about: [
      "Authentic spa and massage centre offering Ayurvedic, Thai, Swedish, deep tissue, and aromatherapy treatments. Trained therapists, hygienic facility, premium oils.",
      "Our therapists are trained in classical Ayurveda + modern bodywork. Treatments customised to your stress points, posture, and wellness goals.",
      "From a quick neck-shoulder massage to a full 90-minute Abhyanga (Ayurvedic full-body), we offer a complete menu of relaxation and therapy.",
      "Trusted wellness destination in [City] for [number]+ clients. Couple's spa, pre-wedding packages, monthly memberships, gift vouchers.",
      "Hygienic, peaceful, professional — your hour of escape from daily stress. Single-use disposable, branded oils, trained therapists only."
    ],
    usp: [
      "Trained therapists · Ayurvedic + Modern · Hygienic · Branded oils",
      "Abhyanga · Shirodhara · Thai · Swedish · Deep tissue · Aroma",
      "Disposable single-use · Hot towel · AC suites · Couple's room",
      "Pre-wedding packages · Couple's spa · Monthly membership",
      "Gift vouchers · Trial session · Loyalty rewards"
    ],
    faqs: [
      { q: "What treatments do you offer?",
        a: "Abhyanga (Ayurvedic full body), Shirodhara (oil flow on forehead), Swedish (relaxation), Deep tissue (sports), Thai (stretch), Aroma, foot reflexology." },
      { q: "What is the cost of [60-min / 90-min] massage?",
        a: "60-min: ₹[X]. 90-min: ₹[Y]. Couple's: ₹[Z]. Package of 5: 15% off. Membership: best value for regulars." },
      { q: "Are the therapists trained / professional?",
        a: "Yes — certified by [Kerala Ayurveda / Thai Wat Pho / specific training school]. [X]+ years experience. Same-gender therapist preference honoured." },
      { q: "Is the centre hygienic?",
        a: "Yes — disposable bed sheets, single-use kit (cotton, swab, slipper), branded oils, AC suites, clean restrooms. Hygiene rated [Trip Advisor / Google] 4.9+." },
      { q: "Do you offer Ayurvedic Panchakarma?",
        a: "[Yes — full Panchakarma program (5–14 days), under Vaidya guidance. / We focus on relaxation massages, not full medical Panchakarma.]" },
      { q: "Are there couple's / private rooms?",
        a: "Yes — couple's spa room (2 beds), private suite for individual privacy. Pre-wedding package popular for engaged couples." },
      { q: "Do you do home service?",
        a: "[Yes — within [X km] for relaxation massage. Higher charge due to equipment / oils. / Centre-only.]" },
      { q: "What if I have a medical condition?",
        a: "Disclose at booking — we adjust pressure, oils, and technique. Avoid certain massages for pregnancy, heart condition, fresh injury." }
    ]
  };

  T['mehndi-artist'] = {
    about: [
      "Professional mehndi / henna artist with [X] years of experience in bridal, party, traditional, Arabic, Indo-Western, and minimalist designs.",
      "We use 100% pure herbal henna — no chemicals, no artificial darkening. Patch test before bridal application. Stain lasts 7–14 days with proper care.",
      "Bridal mehndi packages include bride + family + relatives. Customised designs based on theme, dress, and time available. Trial session 1 month before wedding.",
      "Trusted by [number]+ brides and party hosts. Designs from simple to ultra-detailed, traditional to modern, suitable for every occasion.",
      "Beautiful designs, lasting stain, comfortable application. We come to your venue or you visit our studio — your choice."
    ],
    usp: [
      "Bridal · Party · Traditional · Arabic · Indo-Western · Minimalist",
      "100% herbal henna · No chemicals · Patch test · Long-lasting stain",
      "Studio + home / venue service · Family rate · Bulk discount",
      "Customised designs · Theme-based · Trial session before wedding",
      "Bridal + family packages · Wedding car decoration · Sangeet henna"
    ],
    faqs: [
      { q: "How long does bridal mehndi take?",
        a: "Bride full hands + feet: 4–6 hours (extensive design). Family / guests: 30–60 minutes each. Plan accordingly with full timeline." },
      { q: "What's the cost?",
        a: "Bridal full: ₹[X] – ₹[Y] depending on detail. Family / guests: ₹[Z] – ₹[W] per pair. Bulk for sangeet: discount." },
      { q: "Is the henna safe / chemical-free?",
        a: "Yes — 100% herbal henna (pure). No PPD, no chemical darkener. Patch test 24 hours before bridal application to confirm no allergy." },
      { q: "How dark will the colour come?",
        a: "Initially orange, deepens to dark brown in 24–48 hours. Final colour: rich maroon-brown on palms, lighter on outer side. Care guide shared." },
      { q: "How long does the stain last?",
        a: "Palms: 7–14 days with care. Outer side / arms: 5–7 days. Care: keep dry for first 24 hours, avoid soap on hands too much." },
      { q: "Do you come to my home / venue?",
        a: "Yes — for bridal + family. Within [X km], no extra charge. Outside city: travel + stay extra. Equipment, cones, paste — all included." },
      { q: "Can I get a trial design before booking?",
        a: "Yes — trial design 1 month before wedding (small pattern). Helps decide style and confirms no skin reaction." },
      { q: "Do you do wedding car / venue decoration with mehndi?",
        a: "[Yes — car door panels, sangeet stage edge, wedding photo frames. / Mehndi on people only.]" }
    ]
  };

  // =========================================================
  //  EDUCATION SUB-CATEGORIES
  // =========================================================

  T['tuition-coaching'] = {
    about: [
      "Established coaching institute with [X] years of teaching [board / exam] preparation. Experienced faculty, structured curriculum, regular tests, and parent updates.",
      "We specialise in [boards (CBSE / ICSE / State) + competitive exams: IIT JEE / NEET / banking / NDA / SSC / CA]. Small batches for individual attention.",
      "Concept-based teaching, weekly tests, doubt sessions, study material, mock tests, and one-on-one mentoring for weak students.",
      "Trusted by [number]+ students and parents in [City]. Our results: [X%] above board average, [Y] students cleared [exam] last year.",
      "Education is more than marks — we develop concept clarity, exam temperament, and time management. Free demo class, scholarship test for new admissions."
    ],
    usp: [
      "Experienced faculty · MA / M.Sc / B.Tech / Subject experts",
      "Boards: CBSE · ICSE · State · IIT / NEET / Banking / NDA / SSC",
      "Small batches · Weekly tests · Mock papers · Doubt sessions",
      "Free demo class · Scholarship test · Sibling discount",
      "Result-oriented · [X%] above board average · WhatsApp updates"
    ],
    faqs: [
      { q: "What classes / subjects do you cover?",
        a: "[Specify: Class 9–12 CBSE / ICSE / State board for Physics, Chemistry, Maths, Biology. JEE / NEET / Foundation. Tally / banking exam.]" },
      { q: "What's the batch size?",
        a: "10–20 students for individual attention. Online: max 25. Demo class before joining shows actual batch experience." },
      { q: "What are your fees?",
        a: "Monthly: ₹[X]. Quarterly: ₹[Y] (10% off). Full course: ₹[Z] (15% off). Includes material + tests. Sibling discount: 15%." },
      { q: "Do you offer online classes?",
        a: "[Yes — live online + recorded library. Hybrid model: attend either online or offline. / Currently offline only.]" },
      { q: "Will my child improve grades?",
        a: "With consistent attendance, completed homework, and our discipline: yes — most students improve 15–25%. Genuine effort required." },
      { q: "What if my child misses a class?",
        a: "Recording shared on WhatsApp (online batches). Notes from peers + Saturday doubt session for offline. Extra session: ₹[X] if needed." },
      { q: "How do you assess progress?",
        a: "Weekly chapter test, monthly cumulative test, half-yearly mock. Detailed report to parents on WhatsApp + monthly meet." },
      { q: "What if I want to discontinue?",
        a: "30-day notice. Refund: pro-rata for unused months minus admission fee. Transferable to sibling / friend (case-by-case)." }
    ]
  };

  T['music-dance'] = {
    about: [
      "Music and dance academy teaching classical and contemporary styles. Trained gurus, structured curriculum, performance opportunities, exam preparation.",
      "We teach [vocal, instrument, classical dance, Western dance, Bollywood]. Beginner to advanced levels. Stage performance and concert opportunities.",
      "Founded by [Founder Name], a trained artist with [X] years of teaching experience. Our students perform at school events, cultural shows, and competitions.",
      "Trusted by [number]+ families in [City]. Online + offline batches, individual lessons available. Annual recital and certificate programs.",
      "Music and dance are gifts — we help every student discover and express theirs. Affordable, patient, structured teaching for all ages."
    ],
    usp: [
      "Classical + Contemporary · Vocal · Instrument · Dance",
      "Trained gurus · Pranjali · Trinity exam prep · Structured curriculum",
      "Beginner to advanced · All age groups · Individual + group",
      "Performance opportunities · Annual recital · Stage shows",
      "Free trial class · Sibling discount · Online + offline"
    ],
    faqs: [
      { q: "What do you teach?",
        a: "[Vocal Hindustani / Carnatic. Instrument: harmonium / tabla / guitar / keyboard / flute. Dance: Bharatanatyam / Kathak / Bollywood / Hip-hop / Salsa.]" },
      { q: "Can adults / beginners join?",
        a: "Absolutely — separate adult beginner batches. Age 4 to 70 — we've taught all. No experience needed." },
      { q: "What's the fee?",
        a: "Group class (4–8 students): ₹[X] / month. Personal: ₹[Y] / month. Quarterly / annual: 10–15% off." },
      { q: "How long until I learn enough to perform?",
        a: "Basic stage-ready: 6–12 months with regular practice. Solo performance: 2–3 years. Like any art, depends on dedication." },
      { q: "Do you prepare for exams (Prarambhik / Trinity / Pandit)?",
        a: "Yes — Pranjali (Pracheen Kala Kendra), Prarambhik (Akhil Bharatiya), Trinity College London (Western), Akadami Sangeet Natak exams. We coach through all levels." },
      { q: "Do students perform on stage?",
        a: "Yes — annual recital, school events, cultural society programs, competitions. Stage exposure builds confidence." },
      { q: "Do you offer online classes?",
        a: "Yes — individual online via Zoom. Group: hybrid model. Equipment requirements explained at signup." },
      { q: "Should I buy my own instrument?",
        a: "Initial months: rent from us or borrow. After 3 months: own instrument recommended. We guide on what to buy (budget to premium)." }
    ]
  };

  T['computer-classes'] = {
    about: [
      "IT and computer training institute with industry-relevant courses. Basic computer, Tally, MS Office, programming, web development, digital marketing.",
      "Hands-on training with real projects, certified instructors, and placement assistance. Affordable fees, flexible batches (morning, evening, weekend).",
      "Government-recognised institute with [DGT / NIELIT / state board] affiliation. Certificates accepted for jobs, government, and further study.",
      "Trusted by [number]+ students in [City]. Career counselling, internship opportunities, and placement assistance with local + remote companies.",
      "Bridge to your IT career — from basic to advanced. We make complex topics simple, hands-on, and job-ready."
    ],
    usp: [
      "DGT / NIELIT certified · Industry-recognised certificates",
      "Basic · Tally · MS Office · Java · Python · Web · Digital marketing",
      "Hands-on real projects · Personalised guidance · Job-ready",
      "Flexible batches · Morning / evening / weekend / online",
      "Placement assistance · Internship · Resume building · Interview prep"
    ],
    faqs: [
      { q: "What courses do you offer?",
        a: "Basic computer / MS Office, Tally Prime with GST, advanced Excel, Python / Java programming, Web development (HTML / CSS / JS / React), Digital Marketing, Data Entry, DCA / ADCA." },
      { q: "Is the certificate recognised?",
        a: "Yes — [DGT / NIELIT / specific board] certified. Accepted by employers, government recruitment, further education." },
      { q: "What's the fee and duration?",
        a: "Basic computer (1 month): ₹[X]. Tally (2 months): ₹[Y]. Web development (4 months): ₹[Z]. EMI option available." },
      { q: "Do you offer placement assistance?",
        a: "Yes — resume building, interview prep, internship referrals, partnered with local IT companies. Not a guaranteed placement, but strong support." },
      { q: "Are batches available for working professionals?",
        a: "Yes — early morning [6 AM], evening [6 PM], weekend (Sat-Sun) batches. Customised for working schedules." },
      { q: "Do you offer online classes?",
        a: "Yes — live online + recorded library. Hybrid possible. Useful for students in remote areas or with mobility issues." },
      { q: "Do I need to bring my own laptop?",
        a: "Beginner courses: computers provided. Advanced (web / programming): own laptop preferred (we guide on budget options)." },
      { q: "What's the success rate?",
        a: "[80%+] complete course. [60%+] get IT-related job within 6 months. Independent freelance students: also significant." }
    ]
  };

  T['english-speaking'] = {
    about: [
      "Spoken English and personality development classes for students, working professionals, and homemakers. Build confidence in English communication and interviews.",
      "We focus on real-life conversation, not just grammar. Daily speaking practice, group discussion, presentation, and accent neutralisation.",
      "Trained English language instructors with TEFL / CELTA certification. Small batches for individual attention. Beginner to advanced levels.",
      "Trusted by [number]+ students for IELTS / TOEFL / interview / career growth. Government job aspirants and international students prepare with us.",
      "Confidence in English transforms careers — we help you achieve fluency, clarity, and confidence step by step."
    ],
    usp: [
      "TEFL / CELTA certified instructors · Spoken English focus",
      "Beginner to advanced · IELTS · TOEFL · Interview prep · Group discussion",
      "Real-life conversation · Accent neutralisation · Pronunciation",
      "Small batches · Personalised feedback · Doubt sessions",
      "Free demo class · Confidence guaranteed in 3 months"
    ],
    faqs: [
      { q: "I can barely speak English — can I improve?",
        a: "Absolutely — even from zero. Our beginner batch builds vocabulary, sentence structure, and confidence in 2–3 months. Daily practice key." },
      { q: "What's the fee and duration?",
        a: "Basic (3 months): ₹[X]. Advanced (3 months): ₹[Y]. IELTS / TOEFL prep (2–3 months): ₹[Z]. Daily 1-hour class typical." },
      { q: "Do you prepare for IELTS / TOEFL?",
        a: "Yes — full IELTS prep (Reading / Writing / Speaking / Listening). Target: Band 6.5–8 depending on starting level. Mock tests included." },
      { q: "How is the speaking practice done?",
        a: "Daily 1-on-1 with instructor, peer practice, group discussion, presentation, role-play, debate, news reading, story telling." },
      { q: "Do you offer online classes?",
        a: "Yes — live online via Zoom / Google Meet. Group + 1-on-1 options. Works as well as offline for committed students." },
      { q: "Will I be confident in interviews after this course?",
        a: "With our interview prep module: yes. Mock interviews, common HR questions, presentation skills, body language — all covered." },
      { q: "Are classes in pure English or with translation?",
        a: "Beginner: Hindi-English mix for first 2 weeks, then mostly English. Advanced: 100% English. Gradual immersion approach." },
      { q: "Do you offer a guarantee?",
        a: "Confidence guarantee: if you attend 80%+ classes and complete homework, you WILL improve. Money back if not satisfied in first 7 days." }
    ]
  };

  T['driving-school'] = {
    about: [
      "Authorised driving school with RTO-approved curriculum. Car and bike training, learner's licence to permanent licence support, RTO test prep.",
      "Trained instructors with [X] years of experience. Dual-control cars for safety, modern vehicles, and confidence-building methodology.",
      "We teach defensive driving, traffic rules, parking (parallel / reverse), highway driving, and emergency handling. Theory + practical balanced.",
      "Trusted by [number]+ learners in [City]. Affordable packages, flexible timings, lady instructor available for women students.",
      "Driving is a life skill — we make sure you don't just pass the test, you become a safe, confident driver for life."
    ],
    usp: [
      "RTO-authorised school · Dual-control cars · Modern vehicles",
      "Car · Bike · Heavy vehicle · Auto · Light Motor Vehicle",
      "Learner's licence + RTO test assistance · Form 4, 5, 6 handled",
      "Lady instructor available · Flexible timings · Home pickup",
      "Theory + practical · Defensive driving · Parking practice"
    ],
    faqs: [
      { q: "How long does it take to learn driving?",
        a: "Car: 10–15 sessions (1 hour each). Bike: 5–8 sessions. Confident driver: depends on practice frequency. RTO test pass: 90%+." },
      { q: "What's the fee?",
        a: "Car: ₹[X] for 15 sessions. Bike: ₹[Y] for 8 sessions. RTO assistance: ₹[Z] (learner's + permanent licence). EMI option." },
      { q: "Will you help with RTO process?",
        a: "Yes — Form 4 (learner's), Form 5 (driving certificate), Form 6 (permanent licence). RTO booking, test slot, document submission." },
      { q: "Do you have lady instructor for women learners?",
        a: "Yes — trained lady instructor for women students. Comfortable, judgment-free environment." },
      { q: "Do you teach defensive driving?",
        a: "Yes — emergency braking, sudden lane change, skid recovery, night driving, highway etiquette. Beyond just passing the test." },
      { q: "What if I'm scared / nervous?",
        a: "Most beginners are. We start in empty grounds, gradually move to traffic. Patient, no judgment. Build confidence step by step." },
      { q: "Do you offer pickup / drop?",
        a: "Yes — home pickup within [X km], drop after session. Extra ₹[Y] / session. Useful for busy professionals." },
      { q: "Can I learn for commercial (truck / heavy / taxi)?",
        a: "Yes — LMV / HMV (light / heavy motor vehicle), commercial driving licence. Longer course, RTO test for transport licence." }
    ]
  };

  // =========================================================
  //  PROFESSIONAL SERVICES SUB-CATEGORIES
  // =========================================================

  T['lawyer'] = {
    about: [
      "Advocate [Name], practicing in [City] courts since [Year]. Specialty: civil, criminal, family, property, corporate, consumer, taxation, divorce, will.",
      "We offer transparent legal advice and effective representation. Initial consultation free. Fees disclosed upfront, no surprise bills.",
      "Bar Council registered, member of [State] Bar Association. Network of senior advocates for High Court / Supreme Court matters.",
      "Trusted by [number]+ clients for matters big and small. Family-friendly approach for personal matters, professional approach for corporate.",
      "Justice is a process — we walk it with you, ethically and effectively. From notice to judgment, we handle every step with care."
    ],
    usp: [
      "Bar Council registered · [X]+ yrs practice · [Specialty areas]",
      "Civil · Criminal · Family · Property · Corporate · Consumer · Tax",
      "District + High Court · Supreme Court network · Documentation",
      "Free initial consultation · Transparent fee · Fixed-fee packages",
      "Mediation first · Court if necessary · Out-of-court settlement"
    ],
    faqs: [
      { q: "What types of cases do you handle?",
        a: "[Civil disputes, criminal defence, family / matrimonial, property, divorce, will / inheritance, consumer, motor accident, taxation. Specialty: X.]" },
      { q: "Is the first consultation free?",
        a: "Yes — first 30-minute consultation free, in person or on call. Documents review extra (₹[X] for [pages]). Quote shared after." },
      { q: "How are your fees structured?",
        a: "Consultation: ₹[X]. Documentation: ₹[Y]. Court case: fixed-fee per stage (filing, evidence, arguments). High Court / Supreme: matter-specific." },
      { q: "How long does a typical case take?",
        a: "Notice / out-of-court: 1–3 months. District court civil: 1–3 years. Criminal: 2–5 years. High Court appeal: 3–7 years. Realistic timelines shared upfront." },
      { q: "Is everything confidential?",
        a: "Absolutely — attorney-client privilege protects all communication. No details shared without your written consent." },
      { q: "What if I lose the case?",
        a: "Court outcomes are uncertain. We don't promise wins — we promise honest, best-effort representation. Fees are for effort + time, not guaranteed result." },
      { q: "Do you handle work in other cities / courts?",
        a: "Yes — direct in [City] district court + High Court. Network of advocates in other cities / Supreme Court Delhi. Documentation virtual." },
      { q: "Can you help with notarisation / will / agreement?",
        a: "Yes — sale deed, lease, partnership, will, power of attorney, affidavit. Notarised + stamped + executed. Quote per document." }
    ]
  };

  T['architect'] = {
    about: [
      "Licensed architect [Name] (B.Arch / M.Arch) with [X] years of design and construction experience. Residential, commercial, interior, and renovation projects.",
      "We deliver designs that balance aesthetics, functionality, and budget. 3D walkthroughs, material samples, and itemised cost estimates before construction.",
      "Council of Architecture registered (Reg. No. [X]). Network of structural engineers, MEP consultants, and contractors for complete project delivery.",
      "Trusted by [number]+ clients for residential and commercial projects. From house plan to ready-to-move keys, end-to-end service.",
      "Architecture is about people — how they live, work, and feel in spaces. We design with your lifestyle, vastu preferences, and aspirations in mind."
    ],
    usp: [
      "COA registered · B.Arch / M.Arch · [X]+ yrs experience",
      "Residential · Commercial · Interior · Renovation · Landscape",
      "3D walkthrough · Material samples · Itemised cost estimate",
      "Network of engineers / contractors · End-to-end project management",
      "Vastu-compliant · Energy-efficient · Modern + traditional fusion"
    ],
    faqs: [
      { q: "What services do you offer?",
        a: "Floor plan, 3D elevation, working drawings, structural design (via empanelled engineer), interior design, project supervision, contractor coordination." },
      { q: "How are fees calculated?",
        a: "Design only: ₹[X] / sq ft. Design + supervision: ₹[Y] / sq ft. End-to-end project: ₹[Z] / sq ft. Quote depends on complexity." },
      { q: "Can I see 3D walkthrough before construction?",
        a: "Yes — 3D rendered walkthrough provided. Multiple iterations until you're satisfied with layout, look, and feel." },
      { q: "How long does design phase take?",
        a: "Floor plan: 2–3 weeks. Final design + drawings: 4–6 weeks. Approvals from municipality: 4–8 weeks (depends on local authority)." },
      { q: "Do you help with municipal approval?",
        a: "Yes — plan submission, sanctions, completion certificate. We coordinate with municipal authorities — you sign forms only." },
      { q: "Can you do Vastu-compliant design?",
        a: "Yes — Vastu-aware design (entry direction, kitchen, master bedroom, pooja room). We balance Vastu with practical needs." },
      { q: "Do you manage contractor / supervise construction?",
        a: "Yes — project supervision (weekly visits): ₹[X]. End-to-end management (we handle contractor): ₹[Y]. Quality control throughout." },
      { q: "What about budget overrun?",
        a: "We give itemised estimate upfront. Changes during construction get costed before approval. 5–10% buffer recommended for unforeseen." }
    ]
  };

  T['interior-designer'] = {
    about: [
      "Interior design studio specialising in residential and commercial interiors. Modular kitchen, wardrobe, false ceiling, lighting, furniture, decor.",
      "We deliver complete turnkey interiors — design, material, fabrication, installation. Premium plywood, branded fittings, and quality finish guaranteed.",
      "From a single room makeover to full-house interior, we customise based on your style, lifestyle, and budget. 3D visualisation before execution.",
      "Trusted by [number]+ homeowners and businesses in [City]. Modular kitchens, wardrobes, restaurant interiors, office fitouts — all delivered on time.",
      "Beautiful interiors transform daily life — and we deliver that transformation. Trendy + timeless designs, quality materials, on-time delivery."
    ],
    usp: [
      "Turnkey interiors · Design + Execute · 3D visualisation",
      "Modular kitchen · Wardrobe · False ceiling · Lighting · Furniture",
      "Premium plywood · Hettich / Hafele · Asian Paint · Saint-Gobain",
      "Residential · Commercial · Office · Restaurant · Showroom",
      "1-year workmanship warranty · On-time delivery · Itemised quote"
    ],
    faqs: [
      { q: "What's the cost of a modular kitchen / full-home interior?",
        a: "Modular kitchen: ₹[X] – ₹[Y] / running ft (basic to premium). 2BHK full interior: ₹[Z] – ₹[W] depending on finish level." },
      { q: "How long does a full interior take?",
        a: "1 room: 2–3 weeks. 2 BHK: 4–6 weeks. 3 BHK: 6–8 weeks. Detailed timeline shared after final design approval." },
      { q: "Can I see 3D before I commit?",
        a: "Yes — 3D rendering of every room, multiple revisions until you're 100% satisfied. Material samples and shade card sessions." },
      { q: "What materials do you use?",
        a: "Plywood: Greenply / Century. Fittings: Hettich / Hafele. Paint: Asian / Berger / Dulux. Wallpaper: branded. Tiles: Kajaria / Somany." },
      { q: "Do you supply furniture and decor?",
        a: "Yes — sofa, bed, dining, lighting, curtains, blinds, art, decor accessories. Customised + branded options. Full styling possible." },
      { q: "Is there a warranty?",
        a: "1-year workmanship warranty. Hardware (Hettich / Hafele): 10-year manufacturer warranty. Polish: 6 months. Detailed warranty card." },
      { q: "Do you do commercial interiors (office / restaurant)?",
        a: "Yes — office fitout, restaurant theme design, retail showroom, clinic, salon interiors. Project-based pricing." },
      { q: "What's the payment schedule?",
        a: "10% on design finalisation, 40% on material order, 40% on installation, 10% on completion. Bank transfer / cheque / UPI." }
    ]
  };

  T['property-dealer'] = {
    about: [
      "Property consultant with [X] years of experience in residential, commercial, and agricultural deals across [City] and nearby areas. Sale, purchase, rental, lease.",
      "We have an extensive inventory of plots, flats, houses, shops, offices, and farmland. Verified properties, fair pricing, and end-to-end paperwork support.",
      "From a small rental to a large investment purchase, we provide honest guidance, market insight, and negotiation support. Bank loan tie-up available.",
      "Trusted by [number]+ buyers, sellers, and tenants in [City]. Free property valuation, market trend reports, and legal verification support.",
      "Real estate is a long-term decision — we help you make it right. Transparent dealings, no off-the-record commitments, full disclosure of property status."
    ],
    usp: [
      "[X]+ yrs experience · Residential + Commercial + Agricultural",
      "Sale · Purchase · Rental · Lease · Land investment",
      "Verified properties · Title check assistance · Documentation",
      "Bank loan tie-up · HDFC · SBI · ICICI · LIC Housing",
      "Free valuation · Market trends · Investment guidance"
    ],
    faqs: [
      { q: "Do you charge a commission?",
        a: "Yes — 1% from buyer + 1% from seller (standard). Rental: half month's rent from landlord + half from tenant. Negotiable on big deals." },
      { q: "Are your properties verified / legally clear?",
        a: "We do basic due diligence (title, encumbrance, occupancy certificate). For purchases, we strongly recommend client's own lawyer for final verification." },
      { q: "Can you help with home loan?",
        a: "Yes — partnered with HDFC, SBI, ICICI, LIC Housing, Bajaj. Loan up to 80% of property value. Approval in 7–15 days." },
      { q: "Do you have rental properties?",
        a: "Yes — 1 BHK to 4 BHK, fully furnished to bare shell, residential and commercial. Updated inventory on WhatsApp." },
      { q: "What if I want to sell my property?",
        a: "Free valuation visit. We list across our network + online portals + buyer database. Photo / video shoot, virtual tour, paperwork all handled." },
      { q: "How long does a typical purchase take?",
        a: "Identification: 1–4 weeks (depends on requirement). Documentation + registration: 2–4 weeks. Bank loan: 2–3 weeks parallel. Total: 4–8 weeks." },
      { q: "Do you handle agricultural / farm land?",
        a: "Yes — agricultural land, farmhouse plots, organic farm. Vasai / Mira-Mansoor / NCR areas. Land use clarification, conversion, NA status check." },
      { q: "What about NRI / out-of-city buyers?",
        a: "Yes — video tours, virtual meetings, power-of-attorney based documentation. NRI tax + RBI compliance handled with CA support." }
    ]
  };

  T['photographer'] = {
    about: [
      "Professional photographer / videographer with [X] years of experience. Wedding, pre-wedding, baby shoot, birthday, anniversary, corporate, product photography.",
      "Latest equipment: full-frame DSLR / mirrorless, drone, gimbal, professional lighting. Beautiful candid + traditional shots, cinematic videos.",
      "We craft your story with eye for detail. From quiet moments to grand celebrations, every frame tells a part of your day.",
      "Trusted by [number]+ couples and families in [City]. Premium albums, online sharing platform, edited delivery in 30 days, raw photos with package.",
      "Photography is memory-keeping — and we take it seriously. On-time, professional behaviour, creative output. Sample portfolio on Instagram + WhatsApp."
    ],
    usp: [
      "Wedding · Pre-wedding · Baby · Birthday · Anniversary · Corporate · Product",
      "Latest gear · DSLR · Drone · Gimbal · Professional lighting",
      "Candid + Traditional · Cinematic video · Photo + video combo",
      "Premium albums · Online gallery · 30-day delivery · Raw photos included",
      "Sample portfolio · Trial shoot · Customised packages"
    ],
    faqs: [
      { q: "What's the wedding photography package cost?",
        a: "Basic (1 day, photographer + 1 video): ₹[X]. Premium (2 days, multi-camera, drone, album): ₹[Y]. Custom packages available." },
      { q: "How many days for delivery?",
        a: "Photos: 15–30 days (edited). Video: 30–45 days. Highlight video: 7–10 days. Raw photos: with final delivery." },
      { q: "Do you provide album / printed photos?",
        a: "Yes — premium albums (10×12 / 12×18 / coffee table), framed photos, parents' album, signature book. Quoted as per package." },
      { q: "Will you travel for outstation shoot?",
        a: "Yes — travel + stay extra. Notice 2 weeks. Destination weddings: customised package. International: passport / visa requirements discussed." },
      { q: "Do you have drone permission?",
        a: "Yes — drone licence + flight permission obtained where required. Outdoor weddings: drone shots stunning. Indoor: not feasible." },
      { q: "Can I see your past work?",
        a: "Yes — Instagram, YouTube, Facebook, WhatsApp portfolio. Sample film of recent wedding available on request." },
      { q: "What if I'm not satisfied?",
        a: "Re-edit allowed (within reason). 2 rounds of revisions included. Replacement photographer not possible mid-event for obvious reasons." },
      { q: "Do you do product / catalogue photography?",
        a: "Yes — e-commerce, fashion, food, jewellery, real estate. Studio + on-location. Per-product or full catalogue packages." }
    ]
  };

  T['wedding-planner'] = {
    about: [
      "Full-service wedding planner with [X] years of experience handling intimate to grand weddings. Decor, catering, photography, music, mehndi, choreography — all coordinated.",
      "We turn your dream wedding into reality. From concept to execution, vendor management to guest experience — handle every detail so you can enjoy your day.",
      "Network of trusted vendors (florists, decorators, caterers, sound, lights, photographers, makeup artists). Negotiated rates, quality guaranteed.",
      "Trusted by [number]+ families for weddings, anniversaries, sangeet, mehndi, reception. Customised packages from intimate to lavish.",
      "Your wedding is once-in-a-lifetime — we plan it with the care it deserves. Transparent budgeting, weekly progress meetings, on-day execution."
    ],
    usp: [
      "End-to-end planning · Decor · Catering · Music · Photography · Mehndi",
      "Network of trusted vendors · Negotiated rates · Quality assured",
      "Intimate to grand · Customised themes · Destination weddings",
      "Weekly progress meets · Vendor coordination · On-day execution",
      "Transparent budgeting · Final tally with savings · Money-back on failures"
    ],
    faqs: [
      { q: "What does your planning include?",
        a: "Venue booking, theme + decor, catering, photography, music + DJ, mehndi artist, makeup, choreographer, hospitality, transport, guest management." },
      { q: "What's your fee?",
        a: "10–15% of total wedding budget (typically). Fixed-fee for smaller events: ₹[X] – ₹[Y]. Quote shared after understanding scope." },
      { q: "Can you work within my budget?",
        a: "Yes — we customise based on your budget. Honest about what's possible. We never recommend things you can't afford." },
      { q: "How early should I book you?",
        a: "Big wedding: 6–9 months ahead. Smaller event: 2–4 months. Last-minute (1–4 weeks): possible but limited venue / vendor choice." },
      { q: "Do you do destination weddings?",
        a: "Yes — within India and international (Thailand / Bali / Sri Lanka / Maldives). Logistics, visa, hotel, transport, local vendors — all handled." },
      { q: "What if a vendor fails on the day?",
        a: "Pre-vetted vendor network minimises risk. Backup vendor on standby for critical roles (food, photography). On-day team handles any escalation." },
      { q: "Are payments to vendors handled by you?",
        a: "Yes — we collect from you and pay vendors. Itemised account given. Transparent — no hidden margins on top of vendor rates." },
      { q: "Can I be involved in decisions?",
        a: "Absolutely — every decision is yours. We give options, recommendations, samples; you choose. We just execute." }
    ]
  };

  T['event-management'] = {
    about: [
      "Event management company handling birthdays, anniversaries, corporate events, conferences, product launches, exhibitions, fashion shows.",
      "Trained team for venue management, decor, sound + light, catering, photography, MC, entertainment. Scalable from 10 to 1000+ guests.",
      "Network of partner vendors, in-house designers, audio-visual equipment, and trained staff. Quality you can rely on.",
      "Trusted by [number]+ corporates and individuals in [City]. From a small birthday to a 500-pax corporate offsite, we deliver consistently.",
      "Events should be unforgettable — and stress-free for the host. We handle the execution; you enjoy the celebration."
    ],
    usp: [
      "Birthday · Anniversary · Corporate · Conference · Product launch",
      "Decor · Sound · Light · Catering · Photo · Entertainment · MC",
      "10 to 1000+ guests · Scalable · Trained staff · Branded equipment",
      "Theme-based events · Customised packages · Concept to execution",
      "Vendor management · Budget control · Reporting after event"
    ],
    faqs: [
      { q: "What types of events do you handle?",
        a: "Birthdays, anniversaries, baby showers, weddings (full / partial), corporate offsite, conferences, AGMs, product launches, exhibitions, fashion shows." },
      { q: "What's your minimum order?",
        a: "Smaller events: from ₹[X] (basic decor + sound + photography for 30 pax). Bigger: scaled accordingly." },
      { q: "Do you provide venue?",
        a: "We have a list of partner venues (hotels, banquet halls, gardens, farmhouses). You book directly — we coordinate execution there." },
      { q: "Can you handle outstation events?",
        a: "Yes — within India. Logistics, equipment transport, local vendor partnerships, accommodation for our team. Quote depends on distance." },
      { q: "How early should I book?",
        a: "Big event (500+ pax): 3–6 months. Medium (100–300 pax): 1–3 months. Small (50 pax): 2–4 weeks." },
      { q: "What is your payment schedule?",
        a: "25% on booking, 50% one week before, 25% on completion. GST invoice provided. Bank transfer / cheque." },
      { q: "What if weather is bad / outdoor event?",
        a: "We always have backup plan (indoor venue / tent + canopy). Force majeure: postponed at no extra cost (within reason)." },
      { q: "Can you provide concept / theme ideas?",
        a: "Yes — Instagram-worthy themes, traditional, retro, Bollywood, international, corporate-branded. Mood boards and 3D mockups." }
    ]
  };

  // =========================================================
  //  HELPER: getTemplates(subSlug, parentSlug?)
  //  Fallback chain: sub-cat → parent → default
  // =========================================================
  window.getProfileTemplates = function(subSlug, parentSlug){
    const empty = { about: [], usp: [], faqs: [] };
    if (subSlug && T[subSlug]) return T[subSlug];
    if (parentSlug && T[parentSlug]) return T[parentSlug];
    return T['default'] || empty;
  };

  T['printing-press'] = {
    about: [
      "Modern printing press with offset, digital, and large-format printing facilities. Visiting cards, wedding cards, banners, flex, brochures, certificates, books.",
      "We handle small (10 pieces) to bulk (100,000+) orders. Same-day delivery for digital, 3–7 days for offset. Free design consultation.",
      "Quality printing — vibrant colours, sharp text, durable paper. Multiple paper options (matte / glossy / textured / handmade) and finishes (UV / lamination / spot UV).",
      "Trusted by [number]+ businesses, weddings, and individuals across [City]. Bulk discount, design support, and quick turnaround.",
      "From a single business card to a 500-page book — we print it all. Honest pricing, no compromise on quality, on-time delivery guaranteed."
    ],
    usp: [
      "Offset · Digital · Large-format printing",
      "Visiting cards · Wedding cards · Banners · Flex · Brochures · Books",
      "Same-day digital · 3–7 days offset · Bulk discount",
      "Free design support · Sample before bulk · Quality colour profile",
      "Lamination · UV · Spot UV · Embossing · Hot-foil · Die-cut"
    ],
    faqs: [
      { q: "Can you design or do I need ready design?",
        a: "Both — bring your design (Photoshop / CDR / PDF) or we design for you. Design charge: ₹[X] – ₹[Y] depending on complexity." },
      { q: "What's the minimum order quantity?",
        a: "Digital: 1 piece (single photo, certificate). Offset: 250+ pieces minimum (cost-effective from 500+)." },
      { q: "How long does printing take?",
        a: "Digital small order: same day / next day. Digital large: 1–3 days. Offset: 3–7 days depending on quantity and finishes." },
      { q: "What paper / finish options?",
        a: "Paper: matte, glossy, textured, handmade, art paper. GSM: 100–350. Finish: lamination, UV, spot UV, embossing, foil, die-cut." },
      { q: "Do you do wedding cards / invitations?",
        a: "Yes — full wedding card design + print. From simple to royal designs. Bulk discount on 100+ pieces. Sample before bulk approval." },
      { q: "Can you print large-format banners / flex?",
        a: "Yes — flex (per sq ft), vinyl, fabric banners, hoardings, standees, pop-ups. Sample available, on-site installation possible." },
      { q: "What's the cost for visiting cards?",
        a: "Basic 250 cards: ₹[X]. Premium 500 cards (good paper + finish): ₹[Y]. Spot UV / foil add-on: ₹[Z]." },
      { q: "Do you provide GST invoice?",
        a: "Yes — GST invoice with GSTIN. B2B orders welcome. Credit terms for verified business accounts." }
    ]
  };

})();
