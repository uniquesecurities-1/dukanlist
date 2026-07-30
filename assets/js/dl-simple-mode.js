/* ============================================================
   DL RELAUNCH JS — v46 (2026-07)
   ------------------------------------------------------------
   Previous "simple mode" behavior REMOVED:
   - Dashboard redirect (dashboard.html now works normally)
   - prof-strict body class injection (reviews now allowed for pros)
   - Late-render widget hiding
   - Site-wide feature suppression

   File kept for backwards-compatibility with <script> tags in
   HTML files that reference this path. Now essentially a no-op.

   Backup of original (with all hides): dl-simple-mode.js.PRE-RELAUNCH-BAK
============================================================ */
(function(){
  'use strict';
  // No-op — all features are now enabled at HTML/CSS level.
  // Keeping the file avoids 404 errors from stale <script> tags.
  console.log('[dl] Full-feature mode active (v46)');
})();
