@echo off
setlocal
title DukanList - Push to GitHub
color 0A

REM Always operate in the folder this .bat lives in
cd /d "%~dp0"

echo.
echo ================================================
echo    DukanList - Push to GitHub
echo    Vercel will auto-deploy in 1-2 minutes
echo ================================================
echo.
echo Project folder: %CD%
echo.

REM Check git is installed
git --version >nul 2>&1
if errorlevel 1 goto :NoGit

REM Show what changed
echo Changes since last push:
echo ------------------------------------------------
git status --short
echo ------------------------------------------------
echo.

REM Ask for commit message
set "MSG="
set /p MSG="Commit message (press Enter for 'Quick update'): "
if "%MSG%"=="" set "MSG=Quick update"

echo.
echo Adding files...
git add .

echo Committing...
git commit -m "%MSG%"
if errorlevel 1 goto :Nothing

echo Pushing to GitHub...
git push
if errorlevel 1 goto :PushFail

echo.
echo ================================================
echo    SUCCESS
echo ================================================
echo.
echo    Live in 1-2 minutes:
echo    https://dukanlist.com
echo.
echo ================================================
echo.
pause
exit /b 0


:NoGit
echo.
echo [ERROR] Git not found in PATH.
echo Install Git for Windows: https://git-scm.com/download/win
echo.
pause
exit /b 1

:Nothing
echo.
echo [INFO] Nothing new to commit. Working tree is clean.
echo (Files may already be deployed.)
echo.
pause
exit /b 0

:PushFail
echo.
echo [ERROR] git push failed.
echo Possible reasons:
echo   - Network/internet issue
echo   - GitHub credentials expired
echo   - Conflict with remote (someone else pushed)
echo.
echo Try running 'git push' manually to see the exact error.
echo.
pause
exit /b 1
