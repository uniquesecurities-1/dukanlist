@echo off
setlocal
title DukanList - Push to GitHub
color 0A

REM Hardcoded project path - works regardless of where bat is launched from
cd /d "E:\dukanlist-web"

echo.
echo ================================================
echo    DukanList - Push to GitHub
echo    Vercel auto-deploys in 1-2 minutes
echo ================================================
echo Project: %CD%
echo.

git --version >nul 2>&1
if errorlevel 1 goto :NoGit

echo Changes since last push:
echo ------------------------------------------------
git status --short
echo ------------------------------------------------
echo.

set "MSG="
set /p MSG="Commit message (Enter for 'Quick update'): "
if "%MSG%"=="" set "MSG=Quick update"

echo.
echo Adding...
git add .

echo Committing...
git commit -m "%MSG%"
if errorlevel 1 goto :Nothing

echo Pushing...
git push
if errorlevel 1 goto :PushFail

echo.
echo ================================================
echo    SUCCESS
echo ================================================
echo    Public site : https://dukanlist.com
echo    Admin panel : https://dukanlist.com/admin/login.html
echo.
echo    If new .sql files were added to db/, run them
echo    in Supabase SQL Editor.
echo ================================================
echo.
pause
exit /b 0

:NoGit
echo [ERROR] Git not found in PATH.
pause
exit /b 1

:Nothing
echo.
echo [INFO] Nothing new to commit. Working tree is clean.
echo.
pause
exit /b 0

:PushFail
echo.
echo [ERROR] git push failed. Check network/credentials.
echo Run 'git push' manually in E:\dukanlist-web to see error.
echo.
pause
exit /b 1
