/* ============================================================
   product-suggestions.js — tap, don't type
   ============================================================
   v299. businesses.services_json has held up to 15 products per shop
   since it shipped, the shop page renders them, and as of db/238 search
   looks inside them. On 2026-09-29, 7 shops out of 268 had filled it.

   Typing twenty item names on a phone is why. So the shop's own trade
   decides what it is offered, and each one is a single tap.

   The words are the ones used on a Mandi Dabwali counter, not catalogue
   English: "Atta", "Sariya", "Chuni", "RC transfer". A shopkeeper
   recognises his own stock or he ignores the chip.

   DukanProductIdeas.forCategory('kirana-grocery') -> ['Atta', 'Chawal', …]
   Falls back to the parent category, then to a short generic set, so a
   trade with no list of its own still gets something usable.

   Adding a trade: one entry below. Nothing else to touch.
   ============================================================ */
(function (global) {
  'use strict';

  var BY_SLUG = {
    // ---------- food & grocery ----------
    'kirana-grocery': ['Atta', 'Chawal', 'Dal', 'Cheeni', 'Tel / Refined', 'Masale', 'Chai patti', 'Namak', 'Besan', 'Sooji / Maida', 'Ghee', 'Sabun / Detergent', 'Biscuit', 'Namkeen', 'Cold drink', 'Dry fruits', 'Poha', 'Pooja samagri'],
    'general-store': ['Sabun / Shampoo', 'Detergent', 'Toothpaste', 'Biscuit', 'Namkeen', 'Cold drink', 'Stationery', 'Plastic saman', 'Agarbatti', 'Cosmetic', 'Diapers', 'Phenyl'],
    'bakery-cake': ['Birthday cake', 'Pastry', 'Bread', 'Rusk', 'Cookies', 'Patties', 'Cream roll', 'Cup cake', 'Photo cake', 'Party order'],
    'sweets': ['Barfi', 'Laddoo', 'Rasgulla', 'Gulab jamun', 'Kaju katli', 'Soan papdi', 'Namkeen', 'Mithai box', 'Shadi order'],
    'halwai-mithai': ['Mithai', 'Namkeen', 'Shadi ka order', 'Bhandara order', 'Halwai service', 'Sweet box'],
    'dairy-milk': ['Doodh', 'Dahi', 'Paneer', 'Ghee', 'Makhan', 'Lassi', 'Chaach', 'Khoya', 'Cream'],
    'dairy-farm': ['Gaay ka doodh', 'Bhains ka doodh', 'Paneer', 'Ghee', 'Dahi', 'Khoya', 'Daily supply'],
    'cafe': ['Chai', 'Coffee', 'Cold coffee', 'Shake', 'Burger', 'Sandwich', 'Pizza', 'Maggi', 'French fries', 'Momos', 'Pasta', 'Mojito'],
    'restaurant': ['Veg thali', 'Dal makhani', 'Paneer dish', 'Chinese', 'Roti / Naan', 'Rice / Biryani', 'Chaap', 'Party order', 'Home delivery'],
    'dhaba': ['Dal fry', 'Sabzi', 'Tandoori roti', 'Paratha', 'Lassi', 'Chai', 'Rice', 'Family seating'],
    'ice-cream': ['Cone', 'Cup', 'Family pack', 'Kulfi', 'Shake', 'Sundae', 'Falooda'],
    'fruit-vegetable': ['Sabzi', 'Fal', 'Pyaz / Aloo', 'Hari sabzi', 'Seasonal fruit', 'Home delivery'],
    'meat-chicken': ['Chicken', 'Mutton', 'Fish', 'Eggs', 'Keema', 'Boneless'],
    'flour-mill': ['Gehu pisai', 'Besan', 'Makki atta', 'Bajra atta', 'Masala pisai', 'Chokar'],
    'namkeen-snacks': ['Bhujia', 'Mixture', 'Mathi', 'Papdi', 'Sev', 'Dry samosa', 'Chips'],
    'tea-stall': ['Chai', 'Special chai', 'Coffee', 'Rusk', 'Samosa', 'Bread pakora'],

    // ---------- clothing & personal ----------
    'readymade-garments': ['Shirt', 'T-shirt', 'Pant', 'Jeans', 'Kurta', 'Suit', 'Saree', 'Kids wear', 'Nightwear', 'Winter jacket', 'Sweater', 'Track suit', 'Innerwear', 'Dupatta / Chuni'],
    'clothes': ['Suit piece', 'Saree', 'Shirting', 'Suiting', 'Dupatta / Chuni', 'Lehenga', 'Kurta pajama', 'Dress material', 'Silai'],
    'garments-ladies': ['Suit', 'Saree', 'Kurti', 'Lehenga', 'Nightwear', 'Dupatta / Chuni', 'Leggings', 'Winter wear'],
    'garments-girls': ['Frock', 'Suit', 'Skirt top', 'Party dress', 'School uniform', 'Winter wear'],
    'garments-boys': ['Shirt', 'T-shirt', 'Jeans', 'Kurta pajama', 'School uniform', 'Winter jacket'],
    'mens-wear': ['Shirt', 'T-shirt', 'Pant', 'Jeans', 'Kurta pajama', 'Blazer', 'Sherwani', 'Innerwear'],
    'kids-wear': ['Frock', 'Baby set', 'School uniform', 'Party dress', 'Winter wear', 'Nightwear'],
    'saree-shop': ['Cotton saree', 'Silk saree', 'Party saree', 'Banarasi', 'Georgette', 'Blouse piece', 'Shadi collection'],
    'handloom-shop': ['Bedsheet', 'Razai / Comforter', 'Towel', 'Curtain', 'Blanket', 'Chadar', 'Pillow cover', 'Mattress cover'],
    'footwear-shop': ['Chappal', 'Sandal', 'Formal shoe', 'Sports shoe', 'School shoe', 'Ladies heel', 'Kids shoe', 'Safety shoe'],
    'undergarment': ['Baniyan', 'Underwear', 'Bra', 'Panty', 'Socks', 'Thermal', 'Nightwear'],
    'cosmetic-shop': ['Cream', 'Lipstick', 'Kajal', 'Shampoo', 'Hair colour', 'Nail polish', 'Perfume', 'Face wash', 'Bridal kit'],
    'jewellery': ['Sona', 'Chandi', 'Mangalsutra', 'Chain', 'Ring', 'Payal', 'Kangan', 'Bridal set', 'Purani jewellery exchange'],
    'bag-luggage': ['School bag', 'Trolley bag', 'Laptop bag', 'Purse', 'Suitcase', 'Travel bag', 'Wallet'],

    // ---------- services ----------
    'salon': ['Hair cut', 'Shaving', 'Facial', 'Hair colour', 'Threading', 'Head massage', 'Bridal makeup', 'Waxing', 'Pedicure'],
    'beauty-parlour': ['Facial', 'Threading', 'Waxing', 'Bleach', 'Hair spa', 'Bridal makeup', 'Mehndi', 'Party makeup'],
    'tailor-darzi': ['Suit silai', 'Shirt silai', 'Pant silai', 'Blouse silai', 'Alteration', 'Fall pico', 'Urgent silai'],
    'tailor-ladies': ['Suit silai', 'Blouse silai', 'Lehenga silai', 'Fall pico', 'Alteration', 'Designer silai'],
    'tailor-gents': ['Shirt silai', 'Pant silai', 'Coat / Blazer', 'Kurta pajama', 'Alteration'],
    'dry-cleaner': ['Dry clean', 'Laundry', 'Suit press', 'Razai / Blanket', 'Saree press', 'Stain removal', 'Pickup & delivery'],
    'photographer': ['Wedding shoot', 'Pre-wedding', 'Birthday shoot', 'Passport photo', 'Video shooting', 'Album', 'Drone shoot'],
    'photo-studio': ['Passport photo', 'Lamination', 'Photo print', 'Frame', 'Album', 'ID card photo'],
    'electrician': ['Wiring', 'Fan repair', 'Switch board', 'MCB / Fuse', 'Inverter', 'Light fitting', 'Motor repair'],
    'plumber': ['Tap repair', 'Pipe fitting', 'Bathroom fitting', 'Tank cleaning', 'Motor fitting', 'Leakage repair'],
    'carpenter': ['Almirah', 'Bed', 'Kitchen work', 'Door / Window', 'Sofa repair', 'Furniture repair'],
    'painter': ['Ghar painting', 'Putty', 'Distemper', 'Plastic paint', 'Texture', 'Wood polish'],
    'ac-repair': ['AC service', 'Gas filling', 'AC installation', 'Fridge repair', 'Cooler repair', 'AMC'],
    'mobile-repair': ['Screen change', 'Battery change', 'Charging port', 'Software update', 'Water damage', 'Speaker repair'],
    'computer-laptop-repair': ['Laptop repair', 'Windows install', 'Virus removal', 'RAM / SSD upgrade', 'Printer repair', 'Data recovery'],
    'cctv-camera': ['CCTV installation', 'DVR / NVR', 'Camera repair', 'Wiring', 'Mobile viewing setup', 'AMC'],
    'cable-internet': ['Cable TV connection', 'Broadband', 'Set top box', 'WiFi router', 'Monthly plan'],

    // ---------- vehicle ----------
    'mechanic-2w': ['Bike service', 'Engine work', 'Clutch plate', 'Chain sprocket', 'Brake shoe', 'Oil change', 'Puncture'],
    'mechanic-4w': ['Car service', 'Engine work', 'Clutch', 'Brake work', 'Suspension', 'AC repair', 'Denting painting'],
    'tyre-shop': ['Bike tyre', 'Car tyre', 'Tractor tyre', 'Tube', 'Wheel balancing', 'Alignment', 'Puncture'],
    'spare-parts': ['Bike parts', 'Car parts', 'Filter', 'Battery', 'Clutch plate', 'Brake shoe', 'Engine oil'],
    'car-wash': ['Bike wash', 'Car wash', 'Interior cleaning', 'Rubbing polish', 'Teflon coating'],
    'battery-shop': ['Bike battery', 'Car battery', 'Inverter battery', 'Battery repair', 'Old battery exchange'],
    'rto-agent': ['RC transfer', 'Driving licence', 'Learning licence', 'Fitness', 'Permit', 'Insurance', 'NOC'],

    // ---------- electronics & mobile ----------
    'mobile-shop': ['Smartphone', 'Keypad phone', 'Charger', 'Earphone', 'Cover / Glass', 'Power bank', 'Memory card', 'Recharge', 'EMI par mobile'],
    'mobile-accessories': ['Cover', 'Tempered glass', 'Charger', 'Earphone', 'Power bank', 'Bluetooth speaker', 'Smart watch', 'Data cable'],
    'electronics': ['TV', 'Fridge', 'Washing machine', 'Cooler', 'Fan', 'Mixer grinder', 'Geyser', 'Inverter', 'EMI available'],
    'laptop-computer-sale': ['Laptop', 'Desktop', 'Printer', 'Monitor', 'Keyboard / Mouse', 'Hard disk', 'Antivirus'],

    // ---------- home & construction ----------
    'hardware-shop': ['Cement', 'Sariya', 'Paint', 'Pipe / Fitting', 'Tools', 'Nails / Screws', 'Lock', 'Wire'],
    'paint-shop': ['Emulsion', 'Distemper', 'Primer', 'Putty', 'Wood polish', 'Brush / Roller', 'Colour matching'],
    'plywood-laminate': ['Plywood', 'Laminate / Sunmica', 'Board', 'Adhesive / Fevicol', 'Door', 'Veneer', 'Hardware fitting'],
    'tiles-marble': ['Floor tile', 'Wall tile', 'Marble', 'Granite', 'Kota stone', 'Adhesive', 'Fitting service'],
    'sanitary-bathroom': ['Wash basin', 'Commode', 'Tap / Fitting', 'Shower', 'Tank', 'Pipe', 'Bathroom accessories'],
    'building-material': ['Cement', 'Sariya', 'Bajri', 'Rait', 'Bricks', 'Chuna', 'Delivery'],
    'builder-contractor': ['House construction', 'Labour rate', 'Material + labour', 'Renovation', 'Boundary wall', 'Slab work'],
    'furniture-wood': ['Bed', 'Almirah', 'Sofa', 'Dining table', 'Study table', 'Kitchen trolley', 'Custom order'],
    'utensils-shop': ['Steel bartan', 'Non-stick', 'Pressure cooker', 'Thali set', 'Gift set', 'Water bottle', 'Casserole'],
    'crockery-glassware': ['Dinner set', 'Tea set', 'Glass set', 'Casserole', 'Gift item', 'Melamine'],

    // ---------- professional & financial ----------
    'mutual-fund-distributor': ['SIP', 'Lumpsum', 'ELSS (tax saving)', 'Liquid fund', 'Debt fund', 'Hybrid fund', 'NPS', 'SGB', 'Child plan', 'Retirement plan', 'Portfolio review', 'Goal planning'],
    'stock-broker': ['Demat account', 'Trading account', 'IPO apply', 'Equity delivery', 'Intraday', 'F&O', 'Bonds', 'Portfolio review'],
    'insurance-life': ['Term plan', 'Endowment', 'ULIP', 'Child plan', 'Pension plan', 'Claim help'],
    'insurance-health': ['Health policy', 'Family floater', 'Senior citizen plan', 'Top-up plan', 'Cashless claim help'],
    'insurance-general': ['Vehicle insurance', 'Fire insurance', 'Shop insurance', 'Travel insurance', 'Claim help'],
    'insurance-vehicle': ['Bike insurance', 'Car insurance', 'Commercial vehicle', 'Third party', 'Claim help'],
    'tax-consultant': ['ITR filing', 'GST return', 'GST registration', 'TDS return', 'Audit', 'Book keeping', 'PAN / TAN'],
    'ca': ['ITR filing', 'GST', 'Audit', 'Company registration', 'Book keeping', 'Project report', 'TDS'],
    'financial-advisor': ['Goal planning', 'Retirement planning', 'Tax planning', 'Insurance review', 'Portfolio review', 'Child education plan'],
    'loan-agent': ['Home loan', 'Personal loan', 'Vehicle loan', 'Business loan', 'Loan against property', 'Balance transfer'],
    'gold-loan': ['Gold loan', 'Loan renewal', 'Gold valuation', 'Instant cash'],
    'property-dealer': ['Plot', 'House sale', 'Kirayedari', 'Shop / Showroom', 'Agricultural land', 'Registry help'],
    'lawyer': ['Property case', 'Family case', 'Criminal case', 'Agreement drafting', 'Notary', 'Court representation'],
    'advocate': ['Property case', 'Family case', 'Criminal case', 'Agreement drafting', 'Notary'],
    'architect': ['Ghar ka naksha', 'Elevation design', 'Interior design', '3D view', 'Naksha pass', 'Site visit'],
    'interior-designer': ['Modular kitchen', 'Wardrobe', 'False ceiling', 'Wall panelling', 'Full home interior', '3D design'],
    'csc-aadhaar': ['Aadhaar update', 'PAN card', 'Passport form', 'Bijli bill', 'Ayushman card', 'Birth certificate', 'Railway ticket'],
    'travel-agent': ['Air ticket', 'Train ticket', 'Bus booking', 'Hotel booking', 'Tour package', 'Passport / Visa'],
    'printing-press': ['Visiting card', 'Shadi card', 'Bill book', 'Letter head', 'Pamphlet', 'Sticker', 'Banner'],
    'flex-printing': ['Flex banner', 'Hoarding', 'Sticker', 'Vinyl print', 'Standee', 'Glow sign'],
    'property-dealer2': [],

    // ---------- education & health ----------
    'coaching-institute': ['Class 9-10', 'Class 11-12', 'NEET / JEE', 'Competition exam', 'Spoken English', 'Computer course', 'Demo class'],
    'tuition-coaching': ['Class 1-5', 'Class 6-8', 'Class 9-10', 'Maths', 'Science', 'English', 'Home tuition'],
    'computer-classes': ['Basic computer', 'Tally', 'MS Office', 'DTP', 'Typing', 'Programming', 'Certificate course'],
    'computer-class': ['Basic computer', 'Tally', 'MS Office', 'DTP', 'Typing', 'Certificate course'],
    'pharmacy': ['Dawai', 'Generic medicine', 'Ayurvedic', 'Baby products', 'Health supplement', 'BP / Sugar machine', 'Home delivery'],
    'doctor': ['Consultation', 'Checkup', 'Dressing', 'Injection', 'BP / Sugar test', 'Follow-up'],
    'dentist': ['Dant safai', 'Filling', 'RCT', 'Dant nikalna', 'Cap / Crown', 'Braces', 'Denture'],
    'pathology-lab': ['Blood test', 'Sugar test', 'Thyroid test', 'Lipid profile', 'Full body checkup', 'Home collection'],
    'gym': ['Monthly membership', 'Quarterly', 'Yearly', 'Personal training', 'Cardio', 'Weight loss program', 'Diet plan'],
    'gym-supplements': ['Whey protein', 'Mass gainer', 'BCAA', 'Creatine', 'Multivitamin', 'Fat burner', 'Shaker'],

    // ---------- agri ----------
    'seeds-shop': ['Narma / Cotton beej', 'Gehu beej', 'Sarson beej', 'Sabzi beej', 'Dhan beej', 'Guar beej'],
    'pesticide-shop': ['Keetnashak', 'Kharpatwar nashak', 'Fungicide', 'Growth promoter', 'Spray pump', 'Salah'],
    'fertilizer-shop': ['DAP', 'Urea', 'Potash', 'Zinc', 'Micronutrient', 'Organic khaad'],
    'agri-equipment-shop': ['Spray pump', 'Thresher parts', 'Rotavator', 'Cultivator', 'Pipe', 'Repair'],
    'cattle-feed-shop': ['Pashu aahar', 'Khal', 'Chokar', 'Mineral mixture', 'Murgi dana'],

    // ---------- wholesale ----------
    'wholesale-kirana': ['Atta bori', 'Chawal bori', 'Dal', 'Cheeni', 'Tel tin', 'Masala', 'Chai patti', 'Monthly supply'],
    'distributor-food': ['Biscuit', 'Namkeen', 'Atta / Maida', 'Tel', 'Masala', 'Cold drink', 'Retail supply'],
    'distributor-beverages': ['Cold drink', 'Soda', 'Juice', 'Water bottle', 'Energy drink', 'Crate supply'],

    // ---------- hospitality ----------
    'hotel': ['AC room', 'Non-AC room', 'Deluxe room', 'Family room', 'Hall booking', 'Food service'],
    'marriage-palace': ['Shadi booking', 'Ring ceremony', 'Birthday party', 'Catering', 'Decoration', 'Rooms'],
    'banquet-hall': ['Hall booking', 'Catering', 'Decoration', 'Sound system', 'Parking']
  };

  // If a trade has no list, its parent's list is better than nothing.
  var BY_PARENT = {
    'food-beverage':        ['Home delivery', 'Party order', 'Bulk order', 'Fresh daily'],
    'retail-shopping':      ['Retail', 'Wholesale rate', 'Home delivery', 'New arrival', 'Exchange / Return'],
    'home-services':        ['Home visit', 'Repair', 'Installation', 'AMC / Yearly contract', 'Emergency service'],
    'automotive':           ['Service', 'Repair', 'Spare parts', 'Pickup & drop'],
    'healthcare':           ['Consultation', 'Checkup', 'Follow-up', 'Home visit'],
    'education':            ['Demo class', 'Monthly fees', 'Weekend batch', 'Home tuition'],
    'professional-services':['Consultation', 'Documentation', 'Government filing', 'Home visit'],
    'financial-services':   ['Consultation', 'Documentation', 'Yearly review'],
    'wholesale-distribution':['Wholesale rate', 'Bulk supply', 'Retailer supply', 'Home delivery', 'Credit facility'],
    'construction-material':['Retail', 'Bulk supply', 'Site delivery', 'Fitting service'],
    'beauty-wellness':      ['Appointment', 'Home service', 'Bridal package', 'Monthly package'],
    'agri-business':        ['Retail', 'Bulk supply', 'Home delivery', 'Salah / Advice']
  };

  var GENERIC = ['Home delivery', 'Repair / Service', 'Wholesale rate', 'Custom order', 'Consultation'];

  function forCategory(slug, parentSlug){
    if (slug && BY_SLUG[slug] && BY_SLUG[slug].length) return BY_SLUG[slug].slice();
    if (parentSlug && BY_PARENT[parentSlug]) return BY_PARENT[parentSlug].slice();
    if (slug && BY_PARENT[slug]) return BY_PARENT[slug].slice();
    return GENERIC.slice();
  }

  global.DukanProductIdeas = {
    forCategory: forCategory,
    has: function (slug){ return !!(slug && BY_SLUG[slug]); },
    tradesCovered: function (){ return Object.keys(BY_SLUG).length; }
  };
})(window);
