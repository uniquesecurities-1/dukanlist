@echo off
setlocal
title DukanList - Quick Push (zero input)
color 0B

REM ============================================================
REM  DukanList - QUICK PUSH
REM  Zero questions asked. Just double-click and walk away.
REM  - auto-stages everything
REM  - auto-commits with timestamp
REM  - pushes to GitHub
REM  - Vercel auto-deploys in 1-2 min
REM ============================================================

cd /d "E:\dukanlist-web"

REM Build timestamp message: "Quick push 2026-06-02 14:35"
for /f "tokens=2 delims==" %%a in ('wmic OS Get localdatetime /value') do set DT=%%a
set "STAMP=%DT:~0,4%-%DT:~4,2%-%DT:~6,2% %DT:~8,2%:%DT:~10,2%"
set "MSG=Quick push %STAMP%"

echo.
echo ================================================
echo    DukanList - QUICK PUSH
echo    %MSG%
echo ================================================
echo Project: %CD%
echo.

git --version >nul 2>&1
if errorlevel 1 (
  color 0C
  echo [ERROR] Git not found. Install Git for Windows first.
  echo.
  pause
  exit /b 1
)

echo Changes to be pushed:
echo ------------------------------------------------
git status --short
echo ------------------------------------------------
echo.

REM ============================================================
REM  PRE-FLIGHT GUARDRAIL — syntax-check critical files
REM  Catches Windows-mount truncation bugs BEFORE they reach prod.
REM  - All api/*.js are parsed by Node — refuses push on any syntax error
REM  - All assets/js/*.js similarly checked
REM  - Top-level HTML files checked for missing </html> closer
REM ============================================================
echo Running pre-flight syntax checks...
echo ------------------------------------------------

REM Verify node is available
node --version >nul 2>&1
if errorlevel 1 (
  color 0E
  echo [WARN] Node.js not found in PATH ^- skipping syntax checks.
  echo        Install Node to enable pre-flight guards.
  echo.
  goto :SKIP_GUARD
)

set "SYNTAX_FAIL=0"

REM ---- Check every .js file under api/ ----
for %%f in (api\*.js) do (
  node --check "%%f" >nul 2>&1
  if errorlevel 1 (
    color 0C
    echo [SYNTAX ERROR] %%f
    node --check "%%f"
    set "SYNTAX_FAIL=1"
  )
)

REM ---- Check every .js file under assets\js\ ----
for %%f in (assets\js\*.js) do (
  node --check "%%f" >nul 2>&1
  if errorlevel 1 (
    color 0C
    echo [SYNTAX ERROR] %%f
    node --check "%%f"
    set "SYNTAX_FAIL=1"
  )
)

REM ---- Check sw.js ----
if exist sw.js (
  node --check sw.js >nul 2>&1
  if errorlevel 1 (
    color 0C
    echo [SYNTAX ERROR] sw.js
    node --check sw.js
    set "SYNTAX_FAIL=1"
  )
)

REM ---- Check critical HTML files have closing </html> ----
REM  (Windows mount truncation often eats the tail of large files)
for %%h in (index.html business.html search.html shortlist.html browse.html register.html) do (
  if exist %%h (
    findstr /C:"</html>" %%h >nul 2>&1
    if errorlevel 1 (
      color 0C
      echo [TRUNCATED HTML] %%h ^- missing closing ^</html^> tag
      set "SYNTAX_FAIL=1"
    )
  )
)

REM ---- Check panel/*.html closing tags ----
for %%h in (panel\dashboard.html panel\profile.html panel\photos.html panel\digital-card.html) do (
  if exist %%h (
    findstr /C:"</html>" %%h >nul 2>&1
    if errorlevel 1 (
      color 0C
      echo [TRUNCATED HTML] %%h ^- missing closing ^</html^> tag
      set "SYNTAX_FAIL=1"
    )
  )
)

REM ---- Check admin/*.html closing tags ----
for %%h in (admin\dashboard.html admin\monitoring.html admin\shop.html admin\moderation.html admin\suspicious.html) do (
  if exist %%h (
    findstr /C:"</html>" %%h >nul 2>&1
    if errorlevel 1 (
      color 0C
      echo [TRUNCATED HTML] %%h ^- missing closing ^</html^> tag
      set "SYNTAX_FAIL=1"
    )
  )
)

REM ---- Check categories.json is valid JSON ----
if exist assets\data\categories.json (
  node -e "JSON.parse(require('fs').readFileSync('assets/data/categories.json','utf8'))" >nul 2>&1
  if errorlevel 1 (
    color 0C
    echo [INVALID JSON] assets\data\categories.json
    set "SYNTAX_FAIL=1"
  )
)

if "%SYNTAX_FAIL%"=="1" (
  echo.
  echo ================================================
  echo    PUSH ABORTED ^- syntax errors detected
  echo ================================================
  echo.
  echo One or more files would crash in production.
  echo Fix the errors above and try again.
  echo.
  echo Tip: most truncations come from the Windows mount
  echo cutting large file writes. Re-save the broken file
  echo or restore from git: git restore ^<file^>
  echo.
  pause
  exit /b 1
)

color 0A
echo [OK] All syntax checks passed.
color 0B
echo.

:SKIP_GUARD

echo Adding all changes...
git add -A

echo.
echo Committing...
git commit -m "%MSG%"
if errorlevel 1 (
  echo.
  echo [INFO] Nothing new to commit ^(working tree clean^).
  echo        Going to push anyway in case earlier commits not pushed...
  echo.
)

echo.
echo Pushing to GitHub...
git push
if errorlevel 1 (
  color 0C
  echo.
  echo ================================================
  echo    PUSH FAILED
  echo ================================================
  echo Possible reasons:
  echo  - No internet connection
  echo  - GitHub credentials expired
  echo  - Local branch behind remote ^(run 'git pull' first^)
  echo.
  pause
  exit /b 1
)

color 0A
echo.
echo ================================================
echo    SUCCESS
echo ================================================
echo    Public site : https://dukanlist.com
echo    Admin panel : https://dukanlist.com/admin/login.html
echo.
echo    Vercel will auto-deploy in 1-2 minutes.
echo.
echo    REMINDER:
echo    If you added new .sql files in db/, run them in
echo    Supabase SQL Editor manually.
echo ================================================
echo.
timeout /t 8 /nobreak >nul
exit /b 0
