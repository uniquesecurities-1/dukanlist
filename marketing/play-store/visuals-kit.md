# DukanList — Play Store Visuals Kit

**Bilingual (English + Hindi) creative brief for all Play Store visual assets.**

Last updated: 26 Jun 2026

---

## 0. What you need (and what's in this kit)

| Asset | Size | Format | This kit gives you |
|-------|------|--------|---------------------|
| App icon | 512 × 512 | PNG (alpha OK) | **3 ChatGPT image prompts** (pick the one you like) |
| Feature graphic | 1024 × 500 | PNG / JPEG (no alpha) | **1 ChatGPT image prompt** |
| Phone screenshots × 8 | 1080 × 1920 (9:16) | PNG | **8 bilingual caption strips** + **`screenshot-composer.html`** tool |

Total time to produce all assets: **about 60–90 minutes** if ChatGPT image gen is on the standard tier.

---

## 1. Brand bible — refer to these in every prompt

| Element | Value |
|---------|-------|
| Primary saffron | `#FF6B1A` |
| Deep saffron | `#D97706` |
| Dark saffron (text) | `#92400E` |
| Cream background | `#FFFBF5` |
| Warm cream alt | `#FFE4B5` |
| Ink (body text) | `#0F172A` |
| Muted text | `#64748B` |
| English font | `Manrope` (headings, bold 800/900), `Inter` (body) |
| Hindi font | `Noto Sans Devanagari` (medium 500 / bold 700) |
| Voice | Clean, calm, no exclamation marks, no "Bharat ka #1" tone |

---

## 2. App icon — 3 ChatGPT prompts (pick one)

### Direction A — Storefront on saffron (recommended for thumbnail visibility)

```
Create a modern flat app icon, exactly 1024×1024 pixels, square format,
PNG with transparent background NOT required — use solid saffron orange
(#FF6B1A) as the background.

Foreground: a clean, geometric silhouette of a small Indian
neighbourhood shop, centred in the canvas. The shop has a triangular
sloping awning on top, an open rectangular doorway in the middle, and
one square shopfront window to the left of the door. Render the entire
shop silhouette in soft cream white (#FFFBF5).

Style: minimal flat illustration, no gradients, no drop shadows, no
3D effects. Crisp geometric edges with slightly rounded corners on
the shapes. The shop should occupy roughly 55% of the icon's height,
centred horizontally, with at least 18% padding on every side (this is
the Android adaptive icon safe zone).

NO text anywhere. NO outline border around the icon. NO decorative
elements. The shop silhouette should be instantly recognisable even
when scaled down to 48 pixels in a Play Store listing thumbnail.

Aesthetic: warm, friendly, India-appropriate, professional, modern.
```

### Direction B — Map pin + shop hybrid

```
Create an app icon, exactly 1024×1024 pixels, square format.

Background: warm cream colour (#FFFBF5), full coverage.

Centred subject: a stylised teardrop-shaped map pin in saffron orange
(#FF6B1A), pointing downward. Inside the round top portion of the pin,
place a small white silhouette of a tiny shop — triangular awning,
small doorway, small window — all in clean cream white (#FFFBF5).

Style: flat illustration, bold and geometric. The pin has a subtle
soft drop shadow underneath in deep saffron (#D97706 at 20% opacity)
to suggest gentle depth, but the pin itself stays flat (no gradient
on the pin body).

The pin occupies about 65% of the icon's height, centred vertically
and horizontally, with at least 17% padding on every side.

NO text. NO outline border. NO decorations.

Aesthetic: communicates "local discovery" instantly. Modern, friendly,
clean.
```

### Direction C — Bold DL monogram

```
Create an app icon, exactly 1024×1024 pixels, square format.

Background: a smooth saffron gradient — top-left corner (#FF6B1A)
flowing diagonally to bottom-right corner (#D97706). Smooth blending,
no banding.

Foreground: the letters "DL" in custom bold typography, centred. The
letters are in cream white (#FFFBF5). Use a geometric, slightly
rounded sans-serif (similar to Manrope ExtraBold or Inter Black). The
two letters should sit close together as a tight monogram. Make the
L's bottom horizontal stroke slightly extended like a small ledge or
shop-counter top, suggesting commerce.

Letter height roughly 55% of icon height, centred with at least 20%
padding on every side.

NO additional text. NO outline. NO icons or decorations beyond the
two letters.

Aesthetic: bold, modern brand mark, instantly readable as "DL" at
thumbnail size. Should feel like a confident utility-app brand.
```

> **My recommendation:** **Direction A** for highest thumbnail recognisability in Play Store search. Direction B is the most "descriptive" of what the app does. Direction C is the most modern but least descriptive.

### After generation

1. Save the PNG.
2. Open it in any image viewer to verify it's 1024×1024.
3. If ChatGPT outputs at a different size, resize to **1024 × 1024**, then export a second copy at **512 × 512** for Play Console.
4. Save both copies to `marketing/play-store/assets/app-icon-1024.png` and `marketing/play-store/assets/app-icon-512.png`.

---

## 3. Feature graphic — 1024 × 500 banner

This is the wide image shown at the top of your Play Store listing. It should communicate the value prop in one second.

### ChatGPT prompt

```
Create a horizontal promotional banner image, exactly 1792×1024 pixels
(I'll resize down to 1024×500 myself). Wide banner composition.

LEFT 60% of the canvas:
Background: soft warm cream gradient — top (#FFFBF5) flowing to bottom
(#FFE4B5).

Large bold English headline, top-aligned:
"Every shop in your town, one tap away"
- Use Manrope ExtraBold (or similar geometric sans-serif).
- Headline colour: deep ink (#0F172A) except for the words "one tap"
  which should be in vibrant saffron orange (#FF6B1A).
- Headline takes about 4 lines wrapped naturally, font size ~110px.

Below the English headline, smaller Hindi sub-headline:
"हर दुकान आपके फ़ोन पर"
- Use Noto Sans Devanagari, medium-bold weight.
- Hindi text colour: dark saffron (#92400E).
- Hindi font size ~58px.

RIGHT 40% of the canvas:
Background: continues the same cream gradient.

A clean, modern flat illustration of a smartphone (iPhone-style frame
in dark navy #0F172A) tilted at a 12-degree angle to the right.
Inside the phone screen, show a stylised DukanList app interface:
- Top: saffron orange (#FF6B1A) header bar with the word "DukanList"
  in cream white
- Middle: 3-4 stacked search result cards, each with a tiny storefront
  silhouette icon on the left and a fictional shop name on the right,
  using realistic small-town Indian shop names like:
    "Sharma Kirana Store"
    "Goyal Medical"
    "Singh Electrician"
    "Verma Sweets"
- Each card has a small "Call" and "WhatsApp" button at the bottom right
- Bottom of phone screen: rounded corners, no home indicator drawn

Style throughout: flat illustration, no photorealistic textures, no
3D, no drop shadows except a soft subtle shadow under the phone. India-
appropriate aesthetic, premium and calm. No clutter. No extra
decorative elements like sparkles or stars or emojis.
```

### After generation

1. Save the output PNG.
2. Resize to **1024 × 500** pixels (crop if needed — keep the headline + phone visible).
3. Save to `marketing/play-store/assets/feature-graphic-1024x500.png`.
4. Verify file is under 1 MB (Play Console limit is 1 MB for feature graphic).

---

## 4. Phone screenshots — 8 frames with bilingual caption strips

### Why this approach (instead of ChatGPT-generating fake screenshots)

ChatGPT can fake UI screenshots, but Play Store reviewers often reject mocked UIs that don't match the actual app behaviour. The safer, faster path is:

1. **Capture real screenshots** from `dukanlist.com` on your phone, OR ask me to capture them via the live site.
2. **Overlay a caption strip** at the top of each screenshot — English headline + Hindi subhead — using the included `screenshot-composer.html` tool.
3. **Export at 1080 × 1920**.

### The 8 frames — page to capture + caption strip text

| # | Capture from | English caption | Hindi caption |
|---|--------------|------------------|---------------|
| 1 | `dukanlist.com/` (homepage) | Every shop in your town | हर दुकान आपके फ़ोन पर |
| 2 | `dukanlist.com/browse.html` | Browse 370+ categories | 370+ श्रेणियाँ खोजें |
| 3 | Any shop detail page (e.g. `business.html?...`) | Call, WhatsApp, Maps — one tap | एक टैप पर कॉल, WhatsApp, नक्शा |
| 4 | Same shop, scrolled to Reviews section | Real reviews from real customers | असली ग्राहकों की सच्ची राय |
| 5 | Same shop, scrolled to Map embed | Find them on Google Maps | Google Maps पर सीधा रास्ता |
| 6 | `dukanlist.com/pucho-bhai.html` (or community page) | Ask your neighbourhood anything | अपने मोहल्ले से पूछिए |
| 7 | `dukanlist.com/register.html` | List your shop FREE, forever | अपनी दुकान मुफ़्त में रजिस्टर करें |
| 8 | Homepage with Hindi toggle active | Works in English and Hindi | अंग्रेज़ी और हिंदी, दोनों में |

### Caption strip design spec

Each strip is **the top 200 px of the 1080 × 1920 image** (so the app screenshot fills the remaining 1720 px below).

| Element | Value |
|---------|-------|
| Strip background | Solid saffron orange `#FF6B1A` |
| English text | Manrope ExtraBold, ~46 px, colour `#FFFBF5` |
| Hindi text | Noto Sans Devanagari Medium, ~32 px, colour `#FFFBF5` at 88% opacity |
| Alignment | Both lines centred horizontally |
| Padding | 28 px from strip top to English text; 14 px gap between English and Hindi; 24 px from Hindi to strip bottom |
| Strip bottom edge | A 6 px deep saffron `#D97706` divider line separates the strip from the screenshot |

### Using `screenshot-composer.html` (included tool)

I've built a simple HTML tool at `marketing/play-store/screenshot-composer.html`. Open it in any browser, do this for each of the 8 frames:

1. Click "Choose file" → select your raw screenshot from `dukanlist.com`
2. Pick the caption number (1–8) from the dropdown — the English + Hindi text auto-fills
3. The preview renders at 1080 × 1920 with the saffron caption strip on top
4. Click "Download PNG" → save as `screenshot-1.png` … `screenshot-8.png`
5. Repeat for all 8 frames

The composer runs entirely in your browser (no upload to any server). All 8 captions are pre-encoded in the dropdown so you don't have to retype Hindi.

### Capturing the raw screenshots — 3 options

**Option A (fastest, recommended):** Open dukanlist.com on your phone, navigate to each of the 8 pages, take a screenshot using your phone's screenshot shortcut. Your phone already outputs near-1080-wide screenshots — perfect. Send them to your laptop and feed to the composer.

**Option B (cleaner output):** Use Chrome desktop with the URL bar trick:
1. Open `dukanlist.com` in Chrome desktop
2. Press `F12` → Toggle device toolbar (`Ctrl+Shift+M`)
3. Select "iPhone 12 Pro" (390 × 844)
4. Set device pixel ratio to 3x (in settings)
5. Use `Ctrl+Shift+P` → "Capture full size screenshot" or "Capture screenshot"
6. Output will be 1170 × 2532 (3x scaled) — close enough; the composer auto-fits

**Option C (let me capture them for you):** Tell me to do it, I'll use Chrome MCP to capture all 8 raw screenshots at the right viewport, then composite with captions and place them in `marketing/play-store/assets/`. You'll get 8 ready-to-upload PNGs without lifting a finger.

---

## 5. Caption strip — alternative if you want to skip the composer

If you'd rather just edit screenshots in Canva or similar:

1. Open your raw screenshot in Canva (1080 × 1920 canvas)
2. Add a rectangle at the top, 1080 × 200 pixels, saffron `#FF6B1A`
3. Add a horizontal line at the bottom of that rectangle, 1080 × 6 pixels, deep saffron `#D97706`
4. Add two text layers inside the rectangle:
   - English (centred, Manrope ExtraBold 46 px, cream `#FFFBF5`)
   - Hindi (centred below English, Noto Sans Devanagari Medium 32 px, cream `#FFFBF5` at 88% opacity)
5. Export as PNG

---

## 6. Final upload checklist (Play Console)

| File | Path | Size required |
|------|------|---------------|
| App icon | `assets/app-icon-512.png` | 512 × 512 |
| Feature graphic | `assets/feature-graphic-1024x500.png` | 1024 × 500 |
| Screenshot 1 | `assets/screenshot-1.png` | 1080 × 1920 |
| Screenshot 2 | `assets/screenshot-2.png` | 1080 × 1920 |
| Screenshot 3 | `assets/screenshot-3.png` | 1080 × 1920 |
| Screenshot 4 | `assets/screenshot-4.png` | 1080 × 1920 |
| Screenshot 5 | `assets/screenshot-5.png` | 1080 × 1920 |
| Screenshot 6 | `assets/screenshot-6.png` | 1080 × 1920 |
| Screenshot 7 | `assets/screenshot-7.png` | 1080 × 1920 |
| Screenshot 8 | `assets/screenshot-8.png` | 1080 × 1920 |

Play Console → your DukanList app → **Main store listing** → upload each in the corresponding slot. Save. Done.

---

## 7. What I recommend you do next

1. **Run icon Prompt A in ChatGPT** → get 1024 × 1024 PNG → resize to 512 × 512.
2. **Run feature graphic prompt in ChatGPT** → resize to 1024 × 500.
3. **Tell me "capture screenshots for me"** — I'll grab all 8 raw screenshots from the live site via Chrome MCP and composite them into the final 8 PNGs with bilingual caption strips. You upload them to Play Console without touching a design tool.

Or, if you'd rather do screenshots yourself: open `screenshot-composer.html` in your browser and follow Section 4.

Tell me when you're ready or if you want me to capture the screenshots now.
