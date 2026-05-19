-- ============================================================
-- shop.mfdtools.com — INITIAL SCHEMA
-- Run on a NEW Supabase project (isolated from MFDTools)
-- Order: 01-schema → 02-rls → 03-categories → 04-geo → 05-rpcs
-- ============================================================

-- Required extensions
CREATE EXTENSION IF NOT EXISTS pg_trgm;          -- fast text search
CREATE EXTENSION IF NOT EXISTS unaccent;         -- normalize Hindi+English search
-- CREATE EXTENSION IF NOT EXISTS postgis;       -- uncomment if you enable PostGIS for radius search

-- ============================================================
-- GEO HIERARCHY
-- ============================================================
CREATE TABLE IF NOT EXISTS geo_states (
  id          SMALLSERIAL PRIMARY KEY,
  code        TEXT NOT NULL UNIQUE,           -- e.g. 'HR', 'PB'
  name        TEXT NOT NULL,                  -- 'Haryana'
  name_hi     TEXT,                           -- 'हरियाणा'
  active      BOOLEAN DEFAULT TRUE,
  sort_order  SMALLINT DEFAULT 100
);

CREATE TABLE IF NOT EXISTS geo_districts (
  id          SERIAL PRIMARY KEY,
  state_id    SMALLINT NOT NULL REFERENCES geo_states(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,                  -- 'Sirsa'
  name_hi     TEXT,
  active      BOOLEAN DEFAULT TRUE,
  UNIQUE(state_id, name)
);

CREATE TABLE IF NOT EXISTS geo_cities (
  id            SERIAL PRIMARY KEY,
  district_id   INT NOT NULL REFERENCES geo_districts(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,                -- 'Mandi Dabwali'
  name_hi       TEXT,                          -- 'मंडी डबवाली'
  pincodes      TEXT[] DEFAULT '{}',          -- ['125104','125103']
  lat           NUMERIC(9,6),                  -- optional centroid
  lng           NUMERIC(9,6),
  active        BOOLEAN DEFAULT TRUE,
  UNIQUE(district_id, name)
);

CREATE TABLE IF NOT EXISTS geo_localities (
  id          SERIAL PRIMARY KEY,
  city_id     INT NOT NULL REFERENCES geo_cities(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,                  -- 'Mandi Bazar', 'Chotala Road'
  name_hi     TEXT,
  pincode     TEXT,                            -- override if locality has its own
  UNIQUE(city_id, name)
);

CREATE INDEX IF NOT EXISTS idx_districts_state    ON geo_districts(state_id);
CREATE INDEX IF NOT EXISTS idx_cities_district    ON geo_cities(district_id);
CREATE INDEX IF NOT EXISTS idx_localities_city    ON geo_localities(city_id);
CREATE INDEX IF NOT EXISTS idx_cities_pincode_gin ON geo_cities USING GIN(pincodes);

-- ============================================================
-- CATEGORIES (3-level tree)
-- ============================================================
CREATE TABLE IF NOT EXISTS categories (
  id          SERIAL PRIMARY KEY,
  parent_id   INT REFERENCES categories(id) ON DELETE CASCADE,
  slug        TEXT NOT NULL UNIQUE,            -- 'doctor', 'carpenter'
  name        TEXT NOT NULL,                   -- 'Doctors & Clinics'
  name_hi     TEXT,                            -- 'डॉक्टर एवं क्लिनिक'
  icon        TEXT,                            -- emoji or icon name
  color       TEXT DEFAULT '#1E3A8A',
  description TEXT,
  sort_order  SMALLINT DEFAULT 100,
  active      BOOLEAN DEFAULT TRUE,
  business_count INT DEFAULT 0                 -- denormalised for fast listing
);

CREATE INDEX IF NOT EXISTS idx_categories_parent ON categories(parent_id);
CREATE INDEX IF NOT EXISTS idx_categories_slug   ON categories(slug);

-- ============================================================
-- BUSINESSES (main table)
-- ============================================================
CREATE TABLE IF NOT EXISTS businesses (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  slug            TEXT NOT NULL UNIQUE,         -- 'rajesh-carpenter-dabwali-001'
  category_id     INT NOT NULL REFERENCES categories(id),
  sub_category_id INT REFERENCES categories(id),

  -- Business identity
  name            TEXT NOT NULL,                -- 'Sharma Carpentry Works'
  name_hi         TEXT,
  owner_name      TEXT NOT NULL,                -- 'Rajesh Sharma'
  established_year SMALLINT,

  -- Contact (phone is unique to enable login)
  mobile          TEXT NOT NULL,
  whatsapp        TEXT,                          -- defaults to mobile if blank
  email           TEXT,
  alt_mobile      TEXT,

  -- Address
  address_line1   TEXT NOT NULL,
  address_line2   TEXT,
  locality_id     INT REFERENCES geo_localities(id),
  city_id         INT NOT NULL REFERENCES geo_cities(id),
  district_id     INT NOT NULL REFERENCES geo_districts(id),
  state_id        SMALLINT NOT NULL REFERENCES geo_states(id),
  pincode         TEXT NOT NULL,
  lat             NUMERIC(9,6),
  lng             NUMERIC(9,6),

  -- Business hours: { mon:{open:'09:00',close:'21:00'}, sun:{closed:true}, ... }
  hours_json      JSONB DEFAULT '{}'::JSONB,

  -- Content
  usp_text        TEXT,                         -- 30-word USP English
  usp_hi          TEXT,                         -- Hindi
  about_text      TEXT,                         -- longer description
  photos          TEXT[] DEFAULT '{}',          -- Supabase storage URLs
  video_url       TEXT,                         -- 30-sec intro

  -- Services + price (JSONB array)
  services_json   JSONB DEFAULT '[]'::JSONB,    -- [{name, price_min, price_max, desc}]

  -- Status
  status          TEXT NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending','active','flagged','banned','self_hidden')),

  -- Verification (4 levels)
  verified_mobile     BOOLEAN DEFAULT FALSE,
  verified_address    BOOLEAN DEFAULT FALSE,    -- pincode-city match auto
  verified_photo      BOOLEAN DEFAULT FALSE,    -- has at least 1 photo
  verified_visit      BOOLEAN DEFAULT FALSE,    -- community moderator visited
  verified_score      SMALLINT GENERATED ALWAYS AS (
    (verified_mobile::int + verified_address::int + verified_photo::int + (verified_visit::int * 2))
  ) STORED,

  -- Stats (denormalised, updated via triggers/RPCs)
  rating_avg      NUMERIC(3,2) DEFAULT 0,
  rating_count    INT DEFAULT 0,
  view_count      INT DEFAULT 0,
  lead_count      INT DEFAULT 0,                -- WhatsApp/call clicks

  -- Internal
  flagged_count   SMALLINT DEFAULT 0,
  notes_internal  TEXT,                          -- admin only
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW(),
  last_active_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_biz_category    ON businesses(category_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_biz_city        ON businesses(city_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_biz_district    ON businesses(district_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_biz_pincode     ON businesses(pincode);
CREATE INDEX IF NOT EXISTS idx_biz_status      ON businesses(status);
CREATE INDEX IF NOT EXISTS idx_biz_mobile      ON businesses(mobile);
CREATE INDEX IF NOT EXISTS idx_biz_slug        ON businesses(slug);
CREATE INDEX IF NOT EXISTS idx_biz_rating      ON businesses(rating_avg DESC) WHERE status = 'active';

-- Text search index (trigram for typo-tolerant search)
CREATE INDEX IF NOT EXISTS idx_biz_name_trgm   ON businesses USING GIN (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_biz_usp_trgm    ON businesses USING GIN (usp_text gin_trgm_ops);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;
DROP TRIGGER IF EXISTS trg_biz_updated ON businesses;
CREATE TRIGGER trg_biz_updated BEFORE UPDATE ON businesses FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================
-- REVIEWS
-- ============================================================
CREATE TABLE IF NOT EXISTS reviews (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  business_id     UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  customer_name   TEXT,                         -- optional, can be anonymous
  customer_phone_hash TEXT NOT NULL,            -- SHA256(phone) for dedup
  rating          SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  text            TEXT,
  photos          TEXT[] DEFAULT '{}',
  owner_reply     TEXT,
  owner_reply_at  TIMESTAMPTZ,
  status          TEXT NOT NULL DEFAULT 'active'
                   CHECK (status IN ('active','flagged','removed')),
  helpful_count   INT DEFAULT 0,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(business_id, customer_phone_hash)       -- one review per phone per business
);

CREATE INDEX IF NOT EXISTS idx_reviews_business ON reviews(business_id) WHERE status='active';
CREATE INDEX IF NOT EXISTS idx_reviews_rating   ON reviews(rating);

-- Recompute business rating after review insert/update/delete
CREATE OR REPLACE FUNCTION recompute_business_rating(p_business_id UUID)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  UPDATE businesses
  SET rating_avg = COALESCE((SELECT ROUND(AVG(rating)::numeric, 2)
                              FROM reviews
                              WHERE business_id = p_business_id
                                AND status = 'active'), 0),
      rating_count = COALESCE((SELECT COUNT(*)
                                FROM reviews
                                WHERE business_id = p_business_id
                                  AND status = 'active'), 0)
  WHERE id = p_business_id;
END;
$$;

CREATE OR REPLACE FUNCTION trg_recompute_rating() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  PERFORM recompute_business_rating(COALESCE(NEW.business_id, OLD.business_id));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_review_rating ON reviews;
CREATE TRIGGER trg_review_rating
  AFTER INSERT OR UPDATE OR DELETE ON reviews
  FOR EACH ROW EXECUTE FUNCTION trg_recompute_rating();

-- ============================================================
-- LEADS LOG (track call/whatsapp clicks)
-- ============================================================
CREATE TABLE IF NOT EXISTS leads_log (
  id              BIGSERIAL PRIMARY KEY,
  business_id     UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  action          TEXT NOT NULL CHECK (action IN ('view','call','whatsapp','direction','share')),
  ip_hash         TEXT,                          -- SHA256(ip+date) — dedup same-day same-ip
  ua_summary      TEXT,                          -- 'Mobile-Chrome' kind of short
  city_from       TEXT,                          -- guessed via IP, optional
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_leads_business    ON leads_log(business_id);
CREATE INDEX IF NOT EXISTS idx_leads_created     ON leads_log(created_at DESC);

-- ============================================================
-- FLAGS (community reports)
-- ============================================================
CREATE TABLE IF NOT EXISTS flags (
  id                  UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  business_id         UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  reporter_phone_hash TEXT NOT NULL,
  reason              TEXT NOT NULL CHECK (reason IN ('fake','closed','wrong-info','spam','duplicate','other')),
  text                TEXT,
  status              TEXT NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending','resolved','dismissed')),
  resolved_by         TEXT,                       -- admin email
  resolved_at         TIMESTAMPTZ,
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_flags_business ON flags(business_id);
CREATE INDEX IF NOT EXISTS idx_flags_status   ON flags(status);

-- Auto-flag business when flag count crosses threshold
CREATE OR REPLACE FUNCTION check_auto_flag_business() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM flags
  WHERE business_id = NEW.business_id AND status = 'pending';
  UPDATE businesses SET flagged_count = v_count WHERE id = NEW.business_id;
  IF v_count >= 3 THEN
    UPDATE businesses SET status = 'flagged' WHERE id = NEW.business_id AND status = 'active';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_check_auto_flag ON flags;
CREATE TRIGGER trg_check_auto_flag AFTER INSERT ON flags
  FOR EACH ROW EXECUTE FUNCTION check_auto_flag_business();

-- ============================================================
-- BUSINESS OWNERS (auth.users link for shopkeeper login)
-- ============================================================
CREATE TABLE IF NOT EXISTS business_owners (
  business_id     UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  auth_user_id    UUID NOT NULL,                  -- Supabase auth.users.id
  role            TEXT NOT NULL DEFAULT 'owner'
                   CHECK (role IN ('owner','manager','editor')),
  added_at        TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (business_id, auth_user_id)
);

CREATE INDEX IF NOT EXISTS idx_owners_user ON business_owners(auth_user_id);

NOTIFY pgrst, 'reload schema';
