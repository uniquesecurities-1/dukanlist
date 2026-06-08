# 📱 DukanList → Google Play Store Publishing Guide

**Goal:** Publish DukanList PWA as an Android app on Play Store using **TWA (Trusted Web Activity)** — Google's official method for wrapping PWAs into Android apps.

**Total time:** 2-4 hours (one-time setup) + Play Store review (1-3 days)

---

## 📋 Pre-flight Check — What You Already Have ✅

| Requirement | Status |
|------------|--------|
| HTTPS site (`dukanlist.com`) | ✅ Done (Vercel) |
| `manifest.webmanifest` valid | ✅ Done |
| Service Worker (`sw.js`) | ✅ Done (v1.8.5) |
| App icon 192×192 | ✅ `/assets/icons/icon-192.png` |
| App icon 512×512 | ✅ `/assets/icons/icon-512.png` |
| Maskable icon | ✅ `/assets/icons/icon-maskable-512.png` |
| Privacy Policy URL | ✅ `dukanlist.com/privacy.html` |
| Terms of Service URL | ✅ `dukanlist.com/terms.html` |
| Google Play Developer Account | ✅ You have one |

**What's needed:** TWA wrapper APK/AAB + Play Store listing assets + SHA-256 fingerprint in `.well-known/assetlinks.json`.

---

## 🎯 Easiest Path — PWABuilder.com (Recommended)

This is Microsoft's free official tool. No coding, no Android Studio needed.

### Step 1: Generate the Android App Bundle (AAB)

1. Open **https://www.pwabuilder.com/**
2. Enter your URL: `https://dukanlist.com`
3. Click **Start**
4. Wait for the scorecard. You should see:
   - ✅ Manifest: 100/100 (or close)
   - ✅ Service Worker: detected
   - ✅ Security: HTTPS valid
5. Click **Package for Stores** → **Android**
6. **Fill these fields exactly:**

| Field | Value |
|-------|-------|
| Package ID | `com.dukanlist.app` |
| App name | `DukanList — Bharat's Local Directory` |
| Launcher name | `DukanList` |
| App version | `1.0.0` |
| App version code | `1` |
| Display mode | `standalone` |
| Status bar color | `#FF6B1A` |
| Splash screen color | `#FFFBF5` |
| Icon URL | `https://dukanlist.com/assets/icons/icon-512.png` |
| Maskable icon URL | `https://dukanlist.com/assets/icons/icon-maskable-512.png` |
| Start URL | `/` |
| Host | `dukanlist.com` |
| Enable notifications | ✅ Yes |
| Include source code | ✅ Yes (saves it for future updates) |

7. Click **Generate**
8. Download the **ZIP file** containing:
   - `app-release-bundle.aab` ← This goes to Play Store
   - `signing-key-info.txt` ← **CRITICAL — keep safe forever**
   - `assetlinks.json` ← Replaces the placeholder in your site

### Step 2: Update `.well-known/assetlinks.json`

PWABuilder generates a file with your real SHA-256 fingerprint. Replace the placeholder:

1. Open the downloaded `assetlinks.json`
2. Copy the entire contents
3. Replace `E:\dukanlist-web\.well-known\assetlinks.json` with that content
4. Push to production:
   ```bash
   quick-push.bat
   ```
5. Wait 2 minutes for Vercel to deploy
6. Verify accessible at: `https://dukanlist.com/.well-known/assetlinks.json`

⚠️ **WITHOUT this file, the app will show the Chrome address bar at top — looks unprofessional.**

### Step 3: Backup the Keystore (CRITICAL)

The `signing-key-info.txt` contains your keystore password. **Without it, you can NEVER update your app on Play Store again** (you'd have to publish a new app from scratch).

**Backup in 3 places:**
1. 📧 Email to yourself (`singla223377@gmail.com`)
2. ☁️ Google Drive / OneDrive
3. 📱 Note in a password manager

---

## 🏪 Step 4: Google Play Console Submission

### 4.1 Create the App Entry

1. Open **https://play.google.com/console**
2. Click **Create app**
3. Fill in:
   - **App name:** DukanList — Bharat's Local Directory
   - **Default language:** English (India) — `en-IN`
   - **App or game:** App
   - **Free or paid:** Free
   - Accept declarations → **Create app**

### 4.2 Upload the AAB

1. Left sidebar → **Production** (or **Internal testing** first — recommended)
2. Click **Create new release**
3. Upload the `.aab` file from PWABuilder ZIP
4. Release name: `1.0.0`
5. Release notes (English):
   ```
   First public release of DukanList!
   
   Discover local shops, restaurants, and services across Sirsa, 
   Bathinda, Mansa, and Muktsar districts. Find verified businesses 
   with photos, ratings, and one-tap WhatsApp/Call.
   ```

### 4.3 Fill the Store Listing

**Main store listing → Edit:**

| Field | Value |
|-------|-------|
| App name | `DukanList — Bharat's Local Directory` |
| Short description (80 chars) | `Find local shops, restaurants & services near you. Verified businesses.` |
| Full description (4000 chars) | *See section below* |
| App category | `Shopping` |
| Tags | `shopping`, `business`, `local`, `directory` |
| Email | `singla223377@gmail.com` |
| Phone (optional) | `+91 9541223377` |
| Website | `https://dukanlist.com` |
| Privacy policy | `https://dukanlist.com/privacy.html` |

#### Full description (paste exactly):

```
DukanList — Bharat ka apna local business directory.

Find verified shops, restaurants, doctors, services, and skilled 
professionals in your neighborhood — all in one app.

✨ KEY FEATURES

📍 LOCAL FIRST
Browse 80+ categories of local businesses across Mandi Dabwali, 
Sirsa, Bathinda, Mansa, and Muktsar. Real shopkeepers, real 
locations, real reviews.

🌟 VERIFIED LISTINGS
Every shop is verified — mobile number, address, and photos checked. 
No fake listings. Trust signals like Bronze/Silver/Gold badges 
show shop reliability.

⚡ TIKTOK-STYLE DISCOVER
Swipe vertically through nearby shops. Save your favourites, 
react with emojis, double-tap to love. Find new local gems in 
seconds.

🎯 ONE-TAP ACTIONS
Call, WhatsApp, or get directions — all in one tap. No friction. 
Customers find you fast, you grow faster.

🏪 FOR SHOPKEEPERS
Free listing forever. Add photos, services, deals, hours. Get more 
customer leads, manage reviews, share your shop with one link. 
Build your local digital identity.

💬 PUCHO BHAI — COMMUNITY Q&A
Ask your neighbours: "Best plumber in Sirsa?" "Where to buy 
flex printing in Mandi Dabwali?" Get genuine local recommendations.

🎁 DEALS & OFFERS
Check today's deals from local shops. Save more on your daily 
purchases.

📊 ZERO COST
Free for customers. Free basic listing for shopkeepers. No hidden 
charges, no spam ads.

🇮🇳 BUILT FOR BHARAT
English + Hindi support. Optimised for slow 3G. Works on every 
smartphone. Made with love for small towns of India.

— DigiMutual Goals Pvt. Ltd. | dukanlist.com
```

### 4.4 Graphics Assets

You need to upload these images. **I'll provide the spec — design them in Canva (free) or just take screenshots:**

| Asset | Size | Source |
|-------|------|--------|
| **App icon** | 512×512 PNG | `/assets/icons/icon-512.png` (already have) |
| **Feature graphic** | 1024×500 JPG/PNG | Design in Canva (banner with logo + tagline) |
| **Phone screenshots** | 1080×1920 (min 2, max 8) | Take from your phone's DukanList app |
| **7-inch tablet screenshots** (optional) | 1200×1920 | Optional but helpful |

**Screenshot tips:**
- Home page (categories + featured)
- Discover page (TikTok feed)
- Business detail page
- Shop owner dashboard
- Pucho Bhai community
- Save these as `screenshot-1.png`, `screenshot-2.png`, etc.

### 4.5 Content Rating

Complete the questionnaire. Most DukanList answers:
- Violence: No
- Sexual content: No
- Gambling: No
- Strong language: No
- User-generated content: **Yes** (shopkeepers add their own listings)

Result: **Everyone** (E) — works for all ages.

### 4.6 Target Audience

- Target age: **18 and over**
- Designed for families: **No** (it's a business directory)

### 4.7 Data Safety

Click **Data safety** → Fill in:

**Data collected:**
| Data type | Collected? | Required? | Shared? | Purpose |
|-----------|-----------|-----------|---------|---------|
| Email address | Yes | Yes | No | Account management, verification |
| Phone number | Yes (shopkeepers) | Yes | No (only visible on shop page) | Customer contact |
| Name | Yes | Optional | No | Account |
| Photos | Yes (shopkeepers) | Optional | No | Shop listing |
| Approximate location | Yes (optional) | Optional | No | Show nearby shops |
| Crash logs | Yes | No | No | App stability |

**Security practices:**
- ✅ Data encrypted in transit (HTTPS)
- ✅ Users can request deletion (via contact form)
- ✅ Reviewed against Play's families policy

### 4.8 App Access

If you have any features behind login, note:
> "Shopkeeper dashboard requires email registration. Use test account: testshop@dukanlist.com / Test@1234 to review owner features."

(Create this test account first in your DB.)

### 4.9 Submit for Review

1. Verify all sections show **green checkmarks** in left sidebar:
   - ✅ App access
   - ✅ Ads (declare "No, my app does not contain ads")
   - ✅ Content rating
   - ✅ Target audience
   - ✅ Data safety
   - ✅ Main store listing
2. Click **Send for review**
3. Wait **1-3 days** for Google review

---

## 🧪 Recommended: Internal Testing First (BEFORE Production)

Before going public, do a private test:

1. Play Console → **Internal testing** → **Create new release**
2. Upload same AAB
3. Add up to 100 testers by email
4. Get an opt-in URL → testers install via that link
5. **Test for 2-3 days** to catch bugs
6. Then promote to **Production**

This avoids public bad reviews if something breaks.

---

## ⚠️ Common Pitfalls

| Issue | Cause | Fix |
|-------|-------|-----|
| App shows Chrome URL bar | `assetlinks.json` missing or wrong SHA-256 | Re-deploy correct assetlinks.json |
| App rejected: "broken UX" | Service Worker not working offline | Test with airplane mode first |
| App rejected: "broken links" | Some buttons return 404 | Test every nav item |
| Slow first load | No splash screen | Already configured in manifest |
| App icon looks cropped | Not maskable | We have `icon-maskable-512.png` ✅ |
| "Data safety not declared" | Missing form | Fill section 4.7 |
| Wrong app size in store | PWABuilder bundle too big | Should be ~5-10 MB (it's just a wrapper) |

---

## 🔄 Updating Your App Later

Good news: **PWA updates are LIVE — no Play Store update needed!**

When you push code via `quick-push.bat`, the website updates and the Android app automatically picks it up (it's just a webview wrapper).

**Only update the Play Store AAB when:**
- You change the `manifest.webmanifest` (app icon, name, etc.)
- You bump up Android-specific features
- Major UX overhauls that need new screenshots

Otherwise, the app shown on Play Store is always running your latest code.

---

## 🎯 Bonus: Alternative — Bubblewrap CLI (For Developers)

If you want full control + automation, use Google's official **Bubblewrap CLI** instead of PWABuilder:

```bash
npm install -g @bubblewrap/cli
bubblewrap init --manifest=https://dukanlist.com/manifest.webmanifest
bubblewrap build
```

But for your case, **PWABuilder is faster and easier** — gives you everything in one ZIP.

---

## 📝 Post-Launch Checklist

After Play Store approval:

- [ ] Add Play Store badge on dukanlist.com homepage: `<a href="https://play.google.com/store/apps/details?id=com.dukanlist.app">`
- [ ] Update WhatsApp poster prompts to mention "Available on Play Store"
- [ ] Add Play Store link in shopkeeper invite WhatsApp message
- [ ] Update social media bios with Play Store link
- [ ] Print new posters with Play Store QR code
- [ ] Announce in Pucho Bhai community
- [ ] Send broadcast to shopkeepers: "Aapki shop ab Play Store par bhi visible!"

---

## 🆘 Need Help?

If stuck on any step, share screenshot with me and I'll guide. Most common issue is the `assetlinks.json` SHA-256 mismatch — easy fix with one redeploy.

**🚀 Total estimated cost: ₹0** (besides your existing ₹2000-ish Play Console one-time fee that you already paid.)

---

**Generated for:** DigiMutual Goals Pvt. Ltd. (Unique Securities)  
**Brand:** DukanList  
**Domain:** dukanlist.com  
**Package ID:** com.dukanlist.app  
**Initial version:** 1.0.0
