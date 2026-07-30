# 📸 Cloudinary Photos Integration Roadmap

**Goal:** Bring back shop photos with **Cloudinary CDN** instead of Supabase Storage — so we can serve unlimited photos to Mandi Dabwali traffic without breaking Supabase's 5 GB/month free egress.

**Impact:**
- 25 GB storage + 25 GB bandwidth/month (Cloudinary free) vs 1 GB + 5 GB (Supabase free)
- Auto image optimization saves 60-80% file size
- Global CDN = faster load even on 3G rural networks
- Zero cost until we exceed 25 GB/month (which is 100,000+ photo views)

**Approach:** Signed upload from browser directly to Cloudinary. Supabase DB only stores the URL string. No proxying through our server.

---

## 📋 PHASE 1 — Cloudinary Account Setup (10 min)

### Step 1: Create free Cloudinary account
1. Visit [cloudinary.com](https://cloudinary.com) → **Sign up free**
2. Use same email: `singla223377@gmail.com`
3. Verify email
4. Cloud name suggestion: `dukanlist` (or auto-generated)

### Step 2: Get credentials
1. Cloudinary Dashboard → **Settings → API Keys**
2. Note down:
   - **Cloud Name:** `dukanlist` (or whatever)
   - **API Key:** shown on dashboard
   - **API Secret:** shown on dashboard (⚠️ keep private)

### Step 3: Create upload preset (for unsigned browser uploads)
1. Settings → **Upload → Upload presets → Add upload preset**
2. Configure:
   - **Preset name:** `dukanlist_shops`
   - **Signing mode:** `Unsigned` (browsers can upload directly)
   - **Folder:** `businesses` (organizes uploads)
   - **Allowed formats:** `jpg, png, webp`
   - **Max file size:** 5 MB (5000 KB)
   - **Image transformations:**
     - Width: 1200, Height: 1200 (max)
     - Crop: `limit` (preserves aspect ratio)
     - Quality: `auto:good` (Cloudinary picks best)
     - Format: `auto` (serves WebP/AVIF to modern browsers)
3. Save preset

### Step 4: Enable moderation (recommended)
1. Same preset → **Add-ons → Enable Amazon Rekognition Moderation**
2. Or manual moderation via admin panel
3. Rejects nude/violent images automatically (free tier includes 500 moderations/month)

---

## 📋 PHASE 2 — Database Setup (5 min)

### Migration file: `db/200-restore-photos-cloudinary.sql`

```sql
-- Restore business_photos table + add cloudinary_url column
-- Safe to run — table wasn't dropped, we just add missing column

BEGIN;

-- Ensure column exists (add if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name='business_photos' AND column_name='cloudinary_url'
  ) THEN
    ALTER TABLE business_photos ADD COLUMN cloudinary_url TEXT;
  END IF;
  
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name='business_photos' AND column_name='cloudinary_public_id'
  ) THEN
    ALTER TABLE business_photos ADD COLUMN cloudinary_public_id TEXT;
  END IF;
END $$;

-- Add photo count check function (max 5 per shop)
CREATE OR REPLACE FUNCTION check_photo_limit()
RETURNS TRIGGER AS $$
DECLARE
  photo_count INT;
BEGIN
  SELECT COUNT(*) INTO photo_count 
  FROM business_photos WHERE business_id = NEW.business_id;
  
  IF photo_count >= 5 THEN
    RAISE EXCEPTION 'Photo limit exceeded — max 5 photos per shop';
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS enforce_photo_limit ON business_photos;
CREATE TRIGGER enforce_photo_limit
BEFORE INSERT ON business_photos
FOR EACH ROW EXECUTE FUNCTION check_photo_limit();

COMMIT;
```

**Photo limit = 5 per shop** (hardware-enforced via DB trigger — can't bypass from frontend)

---

## 📋 PHASE 3 — Restore Photos Nav Link (2 min)

Currently the photos link is hidden. Remove CSS block similar to digital card.

Find in `assets/css/dl-simple-mode.css`:
```css
nav a[href="/panel/photos.html"]  /* find this */
```
Remove that line from the display:none block.

---

## 📋 PHASE 4 — Update Upload Page (30 min)

### File: `panel/photos.html` — replace Supabase upload with Cloudinary widget

Key change — instead of uploading to Supabase Storage:

```html
<!-- Add Cloudinary widget script -->
<script src="https://upload-widget.cloudinary.com/global/all.js"></script>

<script>
const cloudinaryWidget = cloudinary.createUploadWidget({
  cloudName: 'dukanlist',         // your cloud name
  uploadPreset: 'dukanlist_shops', // your preset name
  folder: `businesses/${businessId}`,
  sources: ['local', 'camera'],
  maxFiles: 5,                    // max 5 uploads at once
  maxFileSize: 5000000,           // 5 MB
  cropping: true,
  croppingAspectRatio: 1.0,       // square crops for consistency
  clientAllowedFormats: ['jpg', 'png', 'webp'],
  showAdvancedOptions: false
}, async (error, result) => {
  if (result && result.event === "success") {
    // Save URL to Supabase DB
    const photoUrl = result.info.secure_url;
    const publicId = result.info.public_id;
    
    await ShopDB.client.from('business_photos').insert({
      business_id: businessId,
      cloudinary_url: photoUrl,
      cloudinary_public_id: publicId,
      uploaded_at: new Date().toISOString()
    });
    
    reloadPhotoGrid();
  }
});

document.getElementById('uploadBtn').addEventListener('click', () => {
  cloudinaryWidget.open();
});
</script>
```

### Delete photo:
```javascript
async function deletePhoto(photoId, publicId) {
  // Delete from Supabase DB
  await ShopDB.client.from('business_photos').delete().eq('id', photoId);
  
  // Note: Cloudinary deletion needs server-side (admin API + secret)
  // For now, orphaned images stay in Cloudinary — 25 GB is huge, not a concern
  // Can add /api/cloudinary-cleanup endpoint later for periodic cleanup
}
```

---

## 📋 PHASE 5 — Display Photos on Business Page (20 min)

### File: `business.html` — update photo strip rendering

```javascript
// Fetch photos
const { data: photos } = await ShopDB.client
  .from('business_photos')
  .select('id, cloudinary_url')
  .eq('business_id', businessId)
  .order('uploaded_at');

// Render with Cloudinary auto-optimization params
photos.forEach(p => {
  const url = p.cloudinary_url;
  // Cloudinary URL transformation for thumbnails:
  // Original: https://res.cloudinary.com/dukanlist/image/upload/v1/businesses/abc.jpg
  // Thumb:    https://res.cloudinary.com/dukanlist/image/upload/w_400,h_400,c_fill,q_auto,f_auto/v1/businesses/abc.jpg
  
  const thumbUrl = url.replace('/upload/', '/upload/w_400,h_400,c_fill,q_auto,f_auto/');
  const fullUrl = url.replace('/upload/', '/upload/w_1200,q_auto,f_auto/');
  
  photoStrip.innerHTML += `
    <a href="${fullUrl}" target="_blank">
      <img src="${thumbUrl}" alt="Shop photo" loading="lazy" />
    </a>
  `;
});
```

**Key trick:** Cloudinary URL transformations happen **on-the-fly** — no need to re-upload thumbnails. Just add params in URL.

---

## 📋 PHASE 6 — Homepage & Search Cards (15 min)

Show **first photo as thumbnail** on shop cards (homepage + search results).

Update:
- `assets/js/dl-golden-render.js` — homepage cards
- `assets/js/dl-search-address.js` — search page enrichment
- `api/locality.js` — /local/* server-rendered pages

Add photo lookup:
```javascript
// In enrich function
const { data: firstPhoto } = await ShopDB.client
  .from('business_photos')
  .select('cloudinary_url')
  .eq('business_id', b.id)
  .limit(1)
  .single();

if (firstPhoto) {
  const thumb = firstPhoto.cloudinary_url
    .replace('/upload/', '/upload/w_120,h_120,c_fill,q_auto,f_auto/');
  card.querySelector('.biz-photo').innerHTML = `<img src="${thumb}" alt="" />`;
}
```

---

## 📋 PHASE 7 — CSS Un-hide Photo Elements (5 min)

Find these in `assets/css/dl-simple-mode.css`:
```css
.biz-photo,
.photos-strip,
.photo-item {
  display: none !important;
}
```
Remove those hide blocks. Photos will re-appear on all pages.

---

## 📋 PHASE 8 — Admin Panel Update (10 min)

`admin/shop.html` currently hides photos card via JS. Update `dl-admin-shop-clean.js`:

```javascript
// REMOVE this block from nukeOnce():
// var strips = document.querySelectorAll('.photos-strip');
// for (var j = 0; j < strips.length; j++) {
//   var card = strips[j].closest('.card');
//   if (card) hideEl(card);
// }
```

And remove photo-card hide from `dl-admin-simple.css`.

---

## 📋 PHASE 9 — Testing Checklist

Before pushing live:
- [ ] Cloudinary account created + preset configured
- [ ] Migration 200 run in Supabase SQL Editor
- [ ] Upload 1 photo from panel/photos.html — appears in Cloudinary Dashboard
- [ ] Verify photo shows on business.html
- [ ] Verify photo shows on homepage card
- [ ] Verify 5-photo limit enforced (try uploading 6th → gets error)
- [ ] Test on mobile — upload from camera works
- [ ] Delete photo — removed from DB
- [ ] Check Cloudinary bandwidth usage after 1 week

---

## 💰 COST MONITORING

### Cloudinary Dashboard weekly check:
1. Login → Dashboard
2. Look for:
   - **Storage used:** goal < 20 GB (out of 25 GB free)
   - **Bandwidth this month:** goal < 20 GB (out of 25 GB free)
   - **Transformations:** should be well within free 25,000/month

### When to worry:
- Bandwidth > 20 GB: Enable Cloudinary auto-quality more aggressively, or drop max resolution to 800px
- Storage > 20 GB: Time to purge old/deleted shop photos manually
- Approaching limits: Cloudinary paid plan is $89/month for 225 GB — plenty of room to grow if business justifies

### Estimated capacity on free tier:
- 1000 shops × 5 photos avg = 5000 photos
- Each optimized ~250 KB = 1.25 GB storage (5% of quota)
- Even with 30,000 photo views/month = ~7 GB bandwidth (28% of quota)
- **Free tier will comfortably last until 2000-3000 active shops**

---

## 🚨 ROLLBACK PLAN

If something breaks after deploying photos:
1. Re-add CSS hide blocks to `dl-simple-mode.css`
2. Photos disappear from UI instantly
3. Cloudinary + DB data preserved (not deleted)
4. Fix issue → remove CSS hide → back live

Also keep DB migration reversible — new columns can be dropped, trigger can be removed.

---

## 📅 SUGGESTED TIMELINE

**Day 1 (2-3 hours):**
- Phase 1: Cloudinary setup (10 min)
- Phase 2: DB migration (5 min)
- Phase 3: Nav link restore (2 min)
- Phase 4: Upload page (30 min)
- Test end-to-end upload

**Day 2 (1-2 hours):**
- Phase 5: Business page display (20 min)
- Phase 6: Card thumbnails (15 min)
- Phase 7: CSS unhide (5 min)
- Phase 8: Admin update (10 min)
- Phase 9: Testing (30 min)

**Day 3:**
- Announce feature to owners
- Monitor Cloudinary usage
- Encourage owners to add photos (build content)

---

## ✅ FINAL DECISION POINTS FOR YOU

Before I code Phase 4 onwards, please confirm:

1. **Photo count per shop:** 5 (my recommendation) or different?
2. **Square crop enforced?** Consistency across cards vs. shopkeeper freedom
3. **Camera upload allowed on mobile?** (Recommended — most shopkeepers only have phone)
4. **Moderation:** Cloudinary auto (500 free/month) or manual admin review?
5. **First photo becomes card thumbnail** or owner picks featured?

Aap ke answers ke baad main Phase 1 se Phase 9 tak sab implement kar dunga.

---

**Created:** 2026-07-30  
**For:** Deepak Singla · DigiMutual Goals Pvt. Ltd.  
**Category:** Feature restoration / Cloudinary migration
