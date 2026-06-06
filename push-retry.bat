@echo off
REM ============================================================
REM  push-retry.bat — Auto-retry push with backoff
REM ============================================================
REM  Tries to push up to 5 times with 15 second delays.
REM  Use this when network is flaky.
REM ============================================================

setlocal enabledelayedexpansion
title DukanList - Push with Retry

color 0E
echo ============================================================
echo   DukanList - Push With Auto-Retry
echo ============================================================
echo.

cd /d "E:\dukanlist-web"
if errorlevel 1 (
  color 0C
  echo ERROR: E:\dukanlist-web not found
  pause
  exit /b 1
)

REM ---- Stage and commit any pending changes first ----
echo Checking for pending changes...
git status --short
echo.

git diff --cached --quiet >nul 2>&1
set "has_staged=%errorlevel%"
git diff --quiet >nul 2>&1
set "has_unstaged=%errorlevel%"

if not "%has_staged%"=="0" goto :do_commit
if not "%has_unstaged%"=="0" goto :do_commit

REM Check for untracked files
git ls-files --others --exclude-standard | findstr "." >nul
if "%errorlevel%"=="0" goto :do_commit

echo No pending changes. Will push existing local commits.
goto :push_loop

:do_commit
echo Committing pending changes...
git add -A
git commit -m "Quick push %DATE% %TIME%"
if errorlevel 1 (
  echo WARN: Commit step had issues but continuing to push.
)
echo.

:push_loop
echo ============================================================
echo Starting push retry loop ^(max 5 attempts, 15s between^)
echo ============================================================
echo.

set attempt=0
:retry
set /a attempt+=1
echo [Attempt %attempt%/5] Pushing to GitHub...
echo.

git push origin main
if "%errorlevel%"=="0" goto :success

echo.
if %attempt% GEQ 5 goto :all_failed

color 0E
echo Attempt %attempt% failed. Waiting 15 seconds before retry...
echo Press Ctrl+C to cancel.
timeout /t 15 /nobreak >nul
echo.
goto :retry

:success
color 0A
echo.
echo ============================================================
echo   PUSH SUCCESSFUL on attempt %attempt%
echo ============================================================
echo.
echo   Vercel will auto-deploy in ~30 seconds.
echo   Check: https://dukanlist.com
echo.
pause
exit /b 0

:all_failed
color 0C
echo.
echo ============================================================
echo   ALL 5 ATTEMPTS FAILED
echo ============================================================
echo.
echo   Your commit is saved locally but didn't reach GitHub.
echo.
echo   NEXT STEPS:
echo     1. Run push-diagnostic.bat to find the exact issue
echo     2. Try mobile hotspot
echo     3. Wait a few minutes and try again
echo     4. Local commits are safe ^(check: git log --oneline -3^)
echo.
pause
exit /b 1

endlocal
