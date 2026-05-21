/* ============================================================
   dukanlist.com — Voice search (Web Speech API)
   ============================================================
   USAGE:
     <input id="q" type="search">
     <button type="button" onclick="DukanVoice.start('q')">🎙</button>

   Or pass any element id + optional onResult callback:
     DukanVoice.start('q', (text) => { ... })

   Falls back gracefully if browser does not support speech.
   Supports Hindi + English (auto-detect based on browser UI lang).
============================================================ */
(function(global){
  'use strict';

  const Speech = global.SpeechRecognition || global.webkitSpeechRecognition;

  function supported(){ return !!Speech; }

  function start(inputId, onResult){
    const input = document.getElementById(inputId);
    if (!input) return;

    if (!supported()){
      toast('Voice search not supported on this browser. Try Chrome on mobile.');
      input.focus();
      return;
    }

    const btn = document.querySelector('[data-voice-btn="' + inputId + '"]');
    const rec = new Speech();
    // Pick locale based on document lang attribute or browser
    const docLang = (document.documentElement.getAttribute('lang') || '').toLowerCase();
    const userLang = (navigator.language || '').toLowerCase();
    if (/hi/.test(docLang) || /hi/.test(userLang)){
      rec.lang = 'hi-IN';
    } else {
      rec.lang = 'en-IN';
    }
    rec.continuous = false;
    rec.interimResults = true;
    rec.maxAlternatives = 1;

    let finalText = '';
    let listening = true;

    if (btn){
      btn.classList.add('listening');
      btn.setAttribute('aria-pressed', 'true');
      btn.dataset.origTitle = btn.title || '';
      btn.title = 'Listening — tap to stop';
    }
    toast('🎙 Listening… speak now', 1500);

    rec.onresult = function(ev){
      let text = '';
      for (let i = ev.resultIndex; i < ev.results.length; i++){
        text += ev.results[i][0].transcript;
        if (ev.results[i].isFinal) finalText = text;
      }
      input.value = (finalText || text).trim();
      // Fire input event so any "live search" listeners update
      input.dispatchEvent(new Event('input', { bubbles: true }));
    };

    rec.onerror = function(e){
      cleanup();
      if (e.error === 'not-allowed' || e.error === 'service-not-allowed'){
        toast('Microphone access blocked. Enable mic in browser settings.', 3500);
      } else if (e.error === 'no-speech'){
        toast('Didn\'t catch that. Try again.', 2000);
      } else {
        toast('Voice error: ' + (e.error || 'unknown'), 2500);
      }
    };

    rec.onend = function(){
      cleanup();
      if (finalText && typeof onResult === 'function'){
        try { onResult(finalText.trim()); } catch(_) {}
      }
      // If wrapped in a form, submit it.
      else if (finalText){
        const form = input.closest('form');
        if (form){
          setTimeout(() => {
            if (typeof form.requestSubmit === 'function') form.requestSubmit();
            else form.submit();
          }, 250);
        }
      }
    };

    function cleanup(){
      listening = false;
      if (btn){
        btn.classList.remove('listening');
        btn.setAttribute('aria-pressed', 'false');
        btn.title = btn.dataset.origTitle || 'Voice search';
      }
    }

    // Click again to stop
    if (btn){
      btn.onclick = function(){
        if (listening){ try { rec.stop(); } catch(_) {} }
        else start(inputId, onResult);
      };
    }

    try { rec.start(); }
    catch(err){ cleanup(); toast('Could not start mic: ' + err.message); }
  }

  function toast(msg, ms){
    ms = ms || 2200;
    let t = document.getElementById('__voicetoast');
    if (!t){
      t = document.createElement('div');
      t.id = '__voicetoast';
      t.style.cssText = 'position:fixed;bottom:24px;left:50%;transform:translateX(-50%);'
        + 'background:#0F172A;color:#fff;padding:12px 20px;border-radius:10px;font-size:14px;'
        + 'font-weight:600;z-index:99999;box-shadow:0 8px 24px rgba(15,23,42,.25);'
        + 'opacity:0;transition:opacity .18s;font-family:-apple-system,Segoe UI,Roboto,sans-serif';
      document.body.appendChild(t);
    }
    t.textContent = msg;
    t.style.opacity = '1';
    clearTimeout(t._tm);
    t._tm = setTimeout(() => { t.style.opacity = '0'; }, ms);
  }

  // Returns inline mic button HTML (for templated injection)
  function btn(inputId, opts){
    opts = opts || {};
    const size = opts.size || 'md';
    if (!supported()) return '';
    const styles = size === 'lg'
      ? 'width:44px;height:44px;font-size:20px'
      : 'width:38px;height:38px;font-size:17px';
    return '<button type="button"'
      + ' data-voice-btn="' + inputId + '"'
      + ' onclick="DukanVoice.start(\'' + inputId + '\')"'
      + ' title="Voice search" aria-label="Voice search"'
      + ' style="' + styles + ';display:inline-flex;align-items:center;justify-content:center;'
      + 'background:#fff;border:1.5px solid #cbd5e1;color:#0F172A;border-radius:50%;'
      + 'cursor:pointer;transition:all .18s;line-height:1">'
      + '<span class="vmic-idle">🎙</span>'
      + '</button>'
      + '<style>'
      + '[data-voice-btn].listening{background:#EF4444 !important;border-color:#EF4444 !important;color:#fff !important;animation:vpulse 1s ease-in-out infinite}'
      + '@keyframes vpulse{0%,100%{box-shadow:0 0 0 0 rgba(239,68,68,.6)}50%{box-shadow:0 0 0 12px rgba(239,68,68,0)}}'
      + '</style>';
  }

  global.DukanVoice = { start, btn, supported };
})(window);
