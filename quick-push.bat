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
