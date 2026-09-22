#!/usr/bin/env node
// =====================================================
// tools/apply-config.js — push config/site.json into the code
// =====================================================
// The site has no build step, so values like the support WhatsApp
// number are written literally in 40+ files. This tool makes
// config/site.json the ONE place to change them:
//
//   1. edit config/site.json
//   2. node tools/apply-config.js
//   3. commit everything it touched
//
// How it works: config/site.lock.json remembers the value each key
// had the last time the tool ran. For every key whose value changed,
// every occurrence of the OLD value is replaced with the NEW one in
// html / js / json / md files (db/ is history and is left alone —
// DB-side copies need a migration). Then it regenerates
// assets/js/dl-config.js (window.DL_CONFIG, for new runtime code)
// and rebuilds the core bundle.
//
//   node tools/apply-config.js --check   → exit 1 if site.json and the
//                                          lock disagree (unapplied edit)
// =====================================================
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT  = path.join(__dirname, '..');
const CFG   = path.join(ROOT, 'config', 'site.json');
const LOCK  = path.join(ROOT, 'config', 'site.lock.json');
const OUTJS = path.join(ROOT, 'assets', 'js', 'dl-config.js');
const check = process.argv.includes('--check');

const SKIP_DIRS  = new Set(['node_modules', '.git', 'db', 'config', 'tools', 'marketing']);  // supabase/email-templates IS included — re-paste those in the Supabase dashboard after a change
const SKIP_FILES = new Set(['dl-core.js', 'dl-core-defer.js', 'dl-config.js']);
const EXT = /\.(html|js|json|md|txt|webmanifest)$/;

// ---- flatten config to dot paths, dropping _notes ----
function flatten(obj, prefix, out){
  for (const [k, v] of Object.entries(obj)){
    if (k.startsWith('_')) continue;
    const key = prefix ? prefix + '.' + k : k;
    if (v && typeof v === 'object' && !Array.isArray(v)) flatten(v, key, out);
    else out[key] = v;
  }
  return out;
}
function stripNotes(obj){
  if (Array.isArray(obj)) return obj;
  if (obj && typeof obj === 'object'){
    const o = {};
    for (const [k, v] of Object.entries(obj)) if (!k.startsWith('_')) o[k] = stripNotes(v);
    return o;
  }
  return obj;
}

// Text forms each key can appear in. Order: longest first so a spaced
// phone form is swapped before the raw digits inside it.
function variants(key, val){
  if (key === 'support.whatsapp'){
    const s = String(val);
    return [s.slice(0, 5) + ' ' + s.slice(5), s];            // "95412 23377", "9541223377"
  }
  if (key === 'cities_fallback.list'){
    const q = (c) => val.map(x => c + x + c).join(',');
    return ['[' + q("'") + ']', '[' + q('"') + ']'];          // JS array literal, both quote styles
  }
  if (key === 'limits.max_photos') return ['const MAX_PHOTOS = ' + val + ';'];
  return [String(val)];
}

function walk(dir, out){
  for (const e of fs.readdirSync(dir, { withFileTypes: true })){
    if (e.isDirectory()){ if (!SKIP_DIRS.has(e.name)) walk(path.join(dir, e.name), out); }
    else if (EXT.test(e.name) && !SKIP_FILES.has(e.name)) out.push(path.join(dir, e.name));
  }
  return out;
}

const cfg  = JSON.parse(fs.readFileSync(CFG, 'utf8'));
const flat = flatten(cfg, '', {});
const lock = fs.existsSync(LOCK) ? JSON.parse(fs.readFileSync(LOCK, 'utf8')) : null;

if (check){
  const bad = lock ? Object.keys(flat).filter(k => JSON.stringify(flat[k]) !== JSON.stringify(lock[k])) : Object.keys(flat);
  if (bad.length){ console.error('site.json changed but not applied:', bad.join(', '), '\nrun: node tools/apply-config.js'); process.exit(1); }
  console.log('config applied — ok');
  process.exit(0);
}

// ---- 1. replace changed values across the codebase ----
if (lock){
  const changed = Object.keys(flat).filter(k => k in lock && JSON.stringify(flat[k]) !== JSON.stringify(lock[k]));
  if (changed.length){
    const files = walk(ROOT, []);
    for (const key of changed){
      const olds = variants(key, lock[key]), news = variants(key, flat[key]);
      let hits = 0, touched = 0;
      for (const f of files){
        let s = fs.readFileSync(f, 'utf8'), o = s;
        olds.forEach((ov, i) => { if (ov && s.includes(ov)){ hits += s.split(ov).length - 1; s = s.split(ov).join(news[i]); } });
        if (s !== o){ fs.writeFileSync(f, s); touched++; }
      }
      console.log(`${key}: ${JSON.stringify(lock[key])} → ${JSON.stringify(flat[key])}  (${hits} occurrences in ${touched} files)`);
    }
  } else console.log('no value changes');
} else console.log('first run — recording current values, no replacements');

// ---- 2. lock + runtime config ----
fs.writeFileSync(LOCK, JSON.stringify(flat, null, 2) + '\n');
const runtime = stripNotes(cfg);
fs.writeFileSync(OUTJS,
  '/* GENERATED from config/site.json by tools/apply-config.js — do not edit. */\n' +
  'window.DL_CONFIG = Object.freeze(' + JSON.stringify(runtime, null, 2) + ');\n');
console.log('wrote assets/js/dl-config.js');

// ---- 3. bundle picks it up ----
execFileSync(process.execPath, [path.join(__dirname, 'build-core.js')], { stdio: 'inherit' });
