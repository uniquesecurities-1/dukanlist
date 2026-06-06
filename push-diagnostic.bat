@echo off
REM ============================================================
REM  push-diagnostic.bat — DukanList git push troubleshooter
REM ============================================================
REM  Tests every layer between you and GitHub. Run this when
REM  push fails so you know exactly WHERE it's broken.
REM ============================================================

setlocal enabledelayedexpansion
title DukanList - Push Diagnostic

color 0E
echo ============================================================
echo   DukanList - Git Push Diagnostic Tool
echo   Run Time: %DATE% %TIME%
echo ============================================================
echo.

REM ---- Test 1: Basic internet via ping ----
echo [1/7] Testing basic internet (ping google.com)...
ping -n 2 -w 3000 8.8.8.8 > nul
if errorlevel 1 (
  color 0C
  echo   FAILED - No internet at all. Check WiFi/cable.
  goto :verdict
) else (
  echo   OK - Basic internet works.
)
echo.

REM ---- Test 2: DNS resolution for github.com ----
echo [2/7] Resolving github.com via DNS...
nslookup github.com > "%TEMP%\_dns_test.txt" 2>&1
findstr /C:"Address:" "%TEMP%\_dns_test.txt" | findstr /V "#53" | findstr /V "127.0.0.1" >nul
if errorlevel 1 (
  color 0C
  echo   FAILED - DNS cannot resolve github.com.
  echo   FIX: Run as Admin in PowerShell:  ipconfig /flushdns
  echo   OR change DNS to 8.8.8.8 / 1.1.1.1
  goto :verdict
) else (
  echo   OK - DNS resolution working.
)
del "%TEMP%\_dns_test.txt" 2>nul
echo.

REM ---- Test 3: HTTPS to github.com ----
echo [3/7] Testing HTTPS connection to github.com:443...
curl --connect-timeout 10 --max-time 15 -s -o nul -w "Status %%{http_code}" https://github.com/
if errorlevel 1 (
  color 0C
  echo.
  echo   FAILED - HTTPS to GitHub blocked or unreachable.
  echo   Possible reasons:
  echo     - ISP blocking github.com (try different ISP/mobile hotspot)
  echo     - Antivirus/firewall blocking
  echo     - VPN interference
  goto :verdict
) else (
  echo  -- OK - HTTPS to github.com works.
)
echo.

REM ---- Test 4: GitHub API ----
echo [4/7] Testing GitHub API...
curl --connect-timeout 10 --max-time 15 -s -o nul -w "Status %%{http_code}" https://api.github.com/zen
if errorlevel 1 (
  color 0E
  echo.
  echo   WARN - API blocked but main site OK. Unusual but proceed.
) else (
  echo  -- OK - GitHub API reachable.
)
echo.

REM ---- Test 5: Repo accessible ----
echo [5/7] Testing your repo URL...
curl --connect-timeout 10 --max-time 15 -s -o nul -w "Status %%{http_code}" https://github.com/uniquesecurities-1/dukanlist.git
if errorlevel 1 (
  color 0C
  echo.
  echo   FAILED - Repo URL unreachable.
  goto :verdict
) else (
  echo  -- OK - Repo URL responds.
)
echo.

REM ---- Test 6: Git remote configured ----
echo [6/7] Checking git remote config...
cd /d "E:\dukanlist-web" 2>nul
if errorlevel 1 (
  color 0C
  echo   FAILED - E:\dukanlist-web folder not found.
  goto :verdict
)
git remote -v > "%TEMP%\_remote.txt" 2>&1
findstr /C:"origin" "%TEMP%\_remote.txt" >nul
if errorlevel 1 (
  color 0C
  echo   FAILED - No git remote 'origin' configured.
  goto :verdict
) else (
  echo   OK - Remote 'origin' configured:
  type "%TEMP%\_remote.txt"
)
del "%TEMP%\_remote.txt" 2>nul
echo.

REM ---- Test 7: Actual git ls-remote ----
echo [7/7] Test git protocol with ls-remote (the real push test)...
git ls-remote --heads origin 2>&1 | findstr /C:"refs/heads/main" >nul
if errorlevel 1 (
  color 0C
  echo   FAILED - git protocol fails.
  echo.
  git ls-remote --heads origin 2>&1 | findstr /R "fatal error unable"
  echo.
  echo   FIX OPTIONS:
  echo     1. Check GitHub credentials (PAT may have expired)
  echo     2. Try mobile hotspot ^(IPS may be blocking^)
  echo     3. Run:  git pull --rebase  ^(if local is behind^)
  goto :verdict
) else (
  color 0A
  echo   OK - Git protocol works! Push should succeed.
  echo.
  echo ============================================================
  echo   ALL CHECKS PASSED
  echo ============================================================
  echo.
  echo   You can now run quick-push.bat and it should work.
  echo   If it still fails, retry — sometimes it's transient.
)

:verdict
echo.
echo ============================================================
pause
endlocal
