#!/usr/bin/env python3
"""
DukanList — Play Store assets processor
==========================================
Takes raw uploads (icon + feature graphic + screenshots) and produces
Play Console-ready files:
  • app-icon-512.png         (512 × 512)
  • feature-graphic-1024x500.png  (1024 × 500)
  • screenshot-1.png through screenshot-8.png  (1080 × 1920)

Run from project root:
  python3 marketing/play-store/process-assets.py

Expects these files in marketing/play-store/raw/:
  app-icon.png                — square, any size ≥ 512
  feature-graphic.png         — wide, any size
  screen-1-hero.png           — homepage
  screen-2-categories.png     — browse categories
  screen-3-shop-detail.png    — Goyal Saree etc.
  screen-4-reviews.png        — What People Say
  screen-5-map.png            — Map / address section
  screen-6-pucho-bhai.png     — community Q&A
  screen-7-register.png       — Register Your Business
  screen-8-hindi.png          — Hindi UI

Naming flexibility — script also accepts files with just the number
(e.g. screen-1.png). The script logs which file it matched.

Fonts: tries to use Manrope + Noto Sans Devanagari from Google Fonts.
Downloads them on first run into ./marketing/play-store/.fonts/.
"""

import os
import sys
import urllib.request
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

# ----------------------------------------------------------------------
# Config
# ----------------------------------------------------------------------
ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw"
OUT = ROOT / "assets"
FONTS = ROOT / ".fonts"

STRIP_HEIGHT = 200
CANVAS_W = 1080
CANVAS_H = 1920

SAFFRON = (255, 107, 26)        # #FF6B1A
DEEP_SAFFRON = (217, 119, 6)    # #D97706
CREAM = (255, 251, 245)         # #FFFBF5

# Captions — same as visuals-kit Section 4
CAPTIONS = {
    "1": ("Every shop in your town",          "हर दुकान आपके फ़ोन पर"),
    "2": ("Browse 370+ categories",           "370+ श्रेणियाँ खोजें"),
    "3": ("Call, WhatsApp, Maps — one tap",   "एक टैप पर कॉल, WhatsApp, नक्शा"),
    "4": ("Real reviews from real customers", "असली ग्राहकों की सच्ची राय"),
    "5": ("Find them on Google Maps",         "Google Maps पर सीधा रास्ता"),
    "6": ("Ask your neighbourhood anything",  "अपने मोहल्ले से पूछिए"),
    "7": ("List your shop FREE, forever",     "अपनी दुकान मुफ़्त में रजिस्टर करें"),
    "8": ("Works in English and Hindi",       "अंग्रेज़ी और हिंदी, दोनों में"),
}

FONT_URLS = {
    "Manrope-ExtraBold.ttf":
        "https://github.com/google/fonts/raw/main/ofl/manrope/Manrope%5Bwght%5D.ttf",
    "NotoSansDevanagari-Medium.ttf":
        "https://github.com/notofonts/devanagari/raw/main/fonts/NotoSansDevanagari/full/ttf/NotoSansDevanagari-Medium.ttf",
}


# ----------------------------------------------------------------------
# Font loader
# ----------------------------------------------------------------------
def ensure_fonts():
    FONTS.mkdir(parents=True, exist_ok=True)
    for name, url in FONT_URLS.items():
        path = FONTS / name
        if path.exists():
            continue
        print(f"[fonts] downloading {name} …")
        try:
            urllib.request.urlretrieve(url, path)
        except Exception as e:
            print(f"[fonts] ⚠ failed to download {name}: {e}")
            # fallback to system DejaVu — Hindi won't render but English will
            return None
    return FONTS


def load_font(name, size):
    path = FONTS / name
    if path.exists():
        return ImageFont.truetype(str(path), size)
    # fallback
    return ImageFont.load_default()


# ----------------------------------------------------------------------
# Find a raw file by partial match (number + optional keyword)
# ----------------------------------------------------------------------
def find_raw(*keywords):
    """Return first file in raw/ whose name contains ALL keywords (case-insensitive)."""
    if not RAW.exists():
        return None
    for p in sorted(RAW.iterdir()):
        if not p.is_file():
            continue
        n = p.name.lower()
        if all(k.lower() in n for k in keywords):
            return p
    return None


# ----------------------------------------------------------------------
# App icon — resize square to 512
# ----------------------------------------------------------------------
def make_app_icon():
    src = find_raw("icon") or find_raw("app-icon")
    if not src:
        print("[icon] ✗ no app-icon.png in raw/ — SKIPPING")
        return
    print(f"[icon] matched: {src.name}")
    img = Image.open(src).convert("RGBA")
    # Ensure square — centre crop if not
    w, h = img.size
    side = min(w, h)
    img = img.crop(((w - side) // 2, (h - side) // 2,
                    (w - side) // 2 + side, (h - side) // 2 + side))
    img = img.resize((512, 512), Image.LANCZOS)
    # Flatten alpha onto saffron so Play Store transparency edge cases are safe
    out = Image.new("RGB", (512, 512), SAFFRON)
    out.paste(img, (0, 0), img if img.mode == "RGBA" else None)
    dst = OUT / "app-icon-512.png"
    out.save(dst, "PNG", optimize=True)
    print(f"[icon] ✓ saved {dst} (512 × 512)")


# ----------------------------------------------------------------------
# Feature graphic — resize/crop to 1024 × 500
# ----------------------------------------------------------------------
def make_feature_graphic():
    src = find_raw("feature")
    if not src:
        print("[feature] ✗ no feature-graphic in raw/ — SKIPPING")
        return
    print(f"[feature] matched: {src.name}")
    img = Image.open(src).convert("RGB")
    w, h = img.size
    target_ratio = 1024 / 500
    cur_ratio = w / h
    if abs(cur_ratio - target_ratio) > 0.01:
        # need to crop
        if cur_ratio > target_ratio:
            # too wide — crop sides
            new_w = int(h * target_ratio)
            left = (w - new_w) // 2
            img = img.crop((left, 0, left + new_w, h))
        else:
            # too tall — crop top/bottom
            new_h = int(w / target_ratio)
            top = (h - new_h) // 2
            img = img.crop((0, top, w, top + new_h))
    img = img.resize((1024, 500), Image.LANCZOS)
    dst = OUT / "feature-graphic-1024x500.png"
    img.save(dst, "PNG", optimize=True)
    print(f"[feature] ✓ saved {dst} (1024 × 500)")


# ----------------------------------------------------------------------
# Screenshot processor — crop chrome, resize, add bilingual strip
# ----------------------------------------------------------------------
def detect_chrome(img, side):
    """
    Detect status bar (top) and nav bar (bottom) by finding rows that are
    mostly the same colour. Returns (top_skip, bottom_skip).
    """
    px = img.load()
    w, h = img.size

    def row_var(y):
        # sample every 20px
        samples = [px[x, y] for x in range(0, w, 20)]
        avg = tuple(sum(c[i] for c in samples) // len(samples) for i in range(3))
        var = sum(abs(c[i] - avg[i]) for c in samples for i in range(3))
        return var, avg

    # top
    top_skip = 0
    for y in range(0, min(200, h)):
        var, avg = row_var(y)
        if var < 800:  # mostly uniform → likely status bar / app header
            top_skip = y + 1
        else:
            break
    # bottom
    bot_skip = 0
    for y in range(h - 1, max(h - 250, 0), -1):
        var, avg = row_var(y)
        if var < 800:
            bot_skip = (h - 1) - y + 1
        else:
            break
    return top_skip, bot_skip


def make_screenshot(num):
    en, hi = CAPTIONS[str(num)]
    # find a file with the number
    candidates = []
    if RAW.exists():
        for p in sorted(RAW.iterdir()):
            if not p.is_file():
                continue
            n = p.name.lower()
            if n.startswith(f"screen-{num}") or n.startswith(f"screenshot-{num}") or n.startswith(f"{num}-") or n.startswith(f"{num}."):
                candidates.append(p)
    if not candidates:
        print(f"[screen-{num}] ✗ no raw screenshot found — SKIPPING")
        return
    src = candidates[0]
    print(f"[screen-{num}] matched: {src.name}")

    img = Image.open(src).convert("RGB")
    w, h = img.size

    # Try to detect and crop chrome (only at top — keep bottom intact, the
    # app's own nav bar is intentional)
    top_skip, _ = detect_chrome(img, "top")
    # Limit aggressive cropping
    top_skip = min(top_skip, h // 8)
    if top_skip > 30:
        img = img.crop((0, top_skip, w, h))
        w, h = img.size
        print(f"[screen-{num}]   cropped top {top_skip}px")

    # Resize to 1080 wide
    if w != CANVAS_W:
        new_h = int(h * CANVAS_W / w)
        img = img.resize((CANVAS_W, new_h), Image.LANCZOS)
        w, h = img.size

    # Build 1080x1920 canvas, cream background
    canvas = Image.new("RGB", (CANVAS_W, CANVAS_H), CREAM)

    # Paste screenshot below the 200px caption strip
    avail_h = CANVAS_H - STRIP_HEIGHT
    if h > avail_h:
        # Take top portion
        img = img.crop((0, 0, w, avail_h))
        h = avail_h
    canvas.paste(img, (0, STRIP_HEIGHT))

    # Draw saffron strip
    draw = ImageDraw.Draw(canvas)
    draw.rectangle([(0, 0), (CANVAS_W, STRIP_HEIGHT)], fill=SAFFRON)
    # 6px divider at bottom of strip
    draw.rectangle([(0, STRIP_HEIGHT - 6), (CANVAS_W, STRIP_HEIGHT)],
                   fill=DEEP_SAFFRON)

    # Fonts
    font_en = load_font("Manrope-ExtraBold.ttf", 64)
    font_hi = load_font("NotoSansDevanagari-Medium.ttf", 44)

    # Helpers
    def draw_centered(text, y, font, fill):
        # bbox returns (l, t, r, b) — use textbbox for accurate metrics
        bbox = draw.textbbox((0, 0), text, font=font)
        text_w = bbox[2] - bbox[0]
        x = (CANVAS_W - text_w) // 2
        draw.text((x, y), text, font=font, fill=fill)

    # English at y=42 (centred vertically in upper half of strip)
    draw_centered(en, 42, font_en, CREAM)
    # Hindi at y=124 (lower half of strip)
    draw_centered(hi, 124, font_hi, CREAM)

    dst = OUT / f"screenshot-{num}.png"
    canvas.save(dst, "PNG", optimize=True)
    print(f"[screen-{num}] ✓ saved {dst}")


# ----------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------
def main():
    print("=" * 60)
    print("DukanList Play Store assets processor")
    print("=" * 60)
    print(f"raw    : {RAW}")
    print(f"assets : {OUT}")
    print()

    OUT.mkdir(parents=True, exist_ok=True)

    # Fonts
    ensure_fonts()

    # Process
    make_app_icon()
    print()
    make_feature_graphic()
    print()
    for i in range(1, 9):
        make_screenshot(i)

    print()
    print("=" * 60)
    print("Done. Check 'assets/' folder for final files.")
    print("Upload these to Play Console.")
    print("=" * 60)


if __name__ == "__main__":
    main()
