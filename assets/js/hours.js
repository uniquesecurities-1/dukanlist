/* ============================================================
   hours.js — Open/Closed status helper
   Shared by business.html, search.html, browse.html
   ============================================================
   getOpenStatus(hoursJson) → { isOpen, label, closesIn, open }
     - isOpen   : bool  — currently open?
     - open     : bool  — alias of isOpen (back-compat with business.html)
     - label    : str   — human-readable e.g. "Open now · Closes 21:00"
     - closesIn : str|null — "1h 32m" if open, otherwise null

   hoursJson shape:
     { "mon":{"open":"09:00","close":"21:00","closed":false}, ... }
   Day keys: sun, mon, tue, wed, thu, fri, sat
   ============================================================ */
(function (global) {
  'use strict';

  function pad2(n) { return (n < 10 ? '0' : '') + n; }

  function fmtDuration(mins) {
    if (mins <= 0) return null;
    var h = Math.floor(mins / 60);
    var m = mins % 60;
    if (h === 0) return m + 'm';
    if (m === 0) return h + 'h';
    return h + 'h ' + m + 'm';
  }

  function getOpenStatus(hoursJson) {
    if (!hoursJson || typeof hoursJson !== 'object' || !Object.keys(hoursJson).length) {
      return null;
    }
    var now = new Date();
    var dayKeys = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
    var todayKey = dayKeys[now.getDay()];
    var entry = hoursJson[todayKey];

    if (!entry) {
      return { isOpen: false, open: false, label: 'Hours not set', closesIn: null };
    }
    if (entry.closed) {
      return { isOpen: false, open: false, label: 'Closed today', closesIn: null };
    }
    if (!entry.open || !entry.close) {
      return { isOpen: false, open: false, label: 'Closed', closesIn: null };
    }
    var op = entry.open.split(':').map(Number);
    var cl = entry.close.split(':').map(Number);
    if (op.length < 2 || cl.length < 2 || isNaN(op[0]) || isNaN(cl[0])) {
      return { isOpen: false, open: false, label: 'Closed', closesIn: null };
    }
    var cur = now.getHours() * 60 + now.getMinutes();
    var opens = op[0] * 60 + op[1];
    var closes = cl[0] * 60 + cl[1];

    if (cur >= opens && cur < closes) {
      var remain = closes - cur;
      var closesInStr = fmtDuration(remain);
      return {
        isOpen: true,
        open: true,
        label: 'Open now · Closes ' + entry.close,
        closesIn: closesInStr
      };
    }
    if (cur < opens) {
      return {
        isOpen: false,
        open: false,
        label: 'Closed · Opens ' + entry.open,
        closesIn: null
      };
    }
    return { isOpen: false, open: false, label: 'Closed for today', closesIn: null };
  }

  // Expose globally (no module system in this project)
  global.getOpenStatus = getOpenStatus;
  global.DukanHours = { getOpenStatus: getOpenStatus };
})(typeof window !== 'undefined' ? window : this);
