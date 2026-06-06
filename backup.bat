@echo off
setlocal EnableDelayedExpansion
title DukanList Backup System
color 0E

REM ============================================================
REM DukanList - Full Backup System
REM Backs up: project files + git state + Supabase database
REM ============================================================

set PROJECT=E:\dukanlist-web
set BACKUP_ROOT=E:\backups\dukanlist

REM ----- Supabase credentials (anon key — read-only, public-safe) -----
set SB_URL=https://qazuyygrpqopwygxmvwq.supabase.co
set SB_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFhenV5eWdycHFvcHd5Z3htdndxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxNTUwOTEsImV4cCI6MjA5NDczMTA5MX0.FR8x2kldC2yelpPnK2QKd5WGwHUAQheCVmxfs6hR00I

REM ----- Generate timestamp YYYY-MM-DD_HHMMSS -----
for /f "tokens=2 delims==" %%a in ('wmic OS Get localdatetime /value') do set DT=%%a
set TS=%DT:~0,4%-%DT:~4,2%-%DT:~6,2%_%DT:~8,2%%DT:~10,2%%DT:~12,2%
set BACKUP_DIR=%BACKUP_ROOT%\%TS%

echo.
echo ================================================
echo    DukanList - Full Backup System
echo ================================================
echo  Source : %PROJECT%
echo  Target : %BACKUP_DIR%
echo  Time   : %TS%
echo ================================================
echo.

REM ----- Sanity check -----
if not exist "%PROJECT%" goto :NoProject

REM ----- Create backup folder structure -----
echo [Step 1/5] Creating backup folder...
mkdir "%BACKUP_DIR%" 2>nul
mkdir "%BACKUP_DIR%\project" 2>nul
mkdir "%BACKUP_DIR%\database" 2>nul
mkdir "%BACKUP_DIR%\git" 2>nul
echo   [OK] %BACKUP_DIR%
echo.

REM ----- Step 2: Copy project files (full snapshot) -----
echo [Step 2/5] Copying project files...
xcopy "%PROJECT%\*.html"        "%BACKUP_DIR%\project\"        /Y /Q >nul 2>&1
xcopy "%PROJECT%\*.bat"         "%BACKUP_DIR%\project\"        /Y /Q >nul 2>&1
xcopy "%PROJECT%\*.json"        "%BACKUP_DIR%\project\"        /Y /Q >nul 2>&1
xcopy "%PROJECT%\*.txt"         "%BACKUP_DIR%\project\"        /Y /Q >nul 2>&1
xcopy "%PROJECT%\*.xml"         "%BACKUP_DIR%\project\"        /Y /Q >nul 2>&1
xcopy "%PROJECT%\*.md"          "%BACKUP_DIR%\project\"        /Y /Q >nul 2>&1
xcopy "%PROJECT%\.gitignore"    "%BACKUP_DIR%\project\"        /Y /Q >nul 2>&1
xcopy "%PROJECT%\db"            "%BACKUP_DIR%\project\db\"     /E /Y /Q /I >nul 2>&1
xcopy "%PROJECT%\admin"         "%BACKUP_DIR%\project\admin\"  /E /Y /Q /I >nul 2>&1
xcopy "%PROJECT%\panel"         "%BACKUP_DIR%\project\panel\"  /E /Y /Q /I >nul 2>&1
xcopy "%PROJECT%\assets"        "%BACKUP_DIR%\project\assets\" /E /Y /Q /I >nul 2>&1
xcopy "%PROJECT%\api"           "%BACKUP_DIR%\project\api\"    /E /Y /Q /I >nul 2>&1
xcopy "%PROJECT%\components"    "%BACKUP_DIR%\project\components\" /E /Y /Q /I >nul 2>&1
echo   [OK] All project files copied
echo.

REM ----- Step 3: Save git state -----
echo [Step 3/5] Saving git state...
cd /d "%PROJECT%"
git log --oneline -50    > "%BACKUP_DIR%\git\commit-log.txt"  2>nul
git status               > "%BACKUP_DIR%\git\status.txt"      2>nul
git remote -v            > "%BACKUP_DIR%\git\remote.txt"      2>nul
git branch -a            > "%BACKUP_DIR%\git\branches.txt"    2>nul
git rev-parse HEAD       > "%BACKUP_DIR%\git\head-commit.txt" 2>nul
git config --get remote.origin.url > "%BACKUP_DIR%\git\github-url.txt" 2>nul
echo   [OK] Git state captured
echo.

REM ----- Step 4: Export Supabase tables (JSON via REST API) -----
echo [Step 4/5] Exporting Supabase database...

call :ExportTable categories
call :ExportTable geo_states
call :ExportTable geo_districts
call :ExportTable geo_cities
call :ExportTable geo_localities
call :ExportTable businesses
call :ExportTable business_categories
call :ExportTable reviews

echo   [OK] Public tables exported as JSON
echo   [NOTE] business_owners, admin_users, flags, leads_log
echo          need SERVICE_ROLE key (manual backup required)
echo.

REM ----- Step 5: Create README + restore guide -----
echo [Step 5/5] Creating restore guide...
(
echo DukanList Backup - %TS%
echo ============================================================
echo.
echo BACKUP CONTENTS:
echo --------------------------------------------------------
echo /project/         Full project source code snapshot
echo /database/        Supabase public tables as JSON
echo /git/             Git log, commit hash, remote URL
echo.
echo WHAT'S BACKED UP:
echo --------------------------------------------------------
echo  Project files - all HTML/CSS/JS/SQL/configs
echo  Public DB tables - categories, geo_*, active businesses
echo  Git state - last 50 commits, HEAD hash, remote URL
echo.
echo WHAT'S NOT BACKED UP ^(manual^):
echo --------------------------------------------------------
echo  X auth.users ^(Supabase Auth - private, needs service key^)
echo  X admin_users, business_owners, flags, leads_log
echo  X Supabase Storage photos ^(see manual steps below^)
echo  X Vercel env variables ^(MSG91 keys, etc.^)
echo.
echo HOW TO RESTORE:
echo --------------------------------------------------------
echo 1. PROJECT FILES:
echo    Copy /project/* to E:\dukanlist-web\
echo    Then run push.bat to redeploy to Vercel.
echo.
echo 2. GIT REPO:
echo    Already on GitHub - https://github.com/uniquesecurities-1/dukanlist
echo    Read /git/head-commit.txt for last known good commit.
echo.
echo 3. SUPABASE DATA:
echo    Login to Supabase dashboard - SQL Editor
echo    Use the JSON files in /database/ to re-insert data:
echo    a. Disable RLS temporarily
echo    b. INSERT INTO table_name SELECT * FROM jsonb_to_recordset^(...^);
echo    c. Re-enable RLS
echo    OR contact developer for restore.sql script
echo.
echo 4. STORAGE PHOTOS ^(manual^):
echo    Supabase Dashboard - Storage - shop-photos bucket
echo    Download files manually OR use Supabase CLI:
echo    supabase storage download bucket://shop-photos
echo.
echo 5. FULL DB DUMP ^(recommended monthly^):
echo    Supabase Dashboard - Settings - Database
echo    Use connection string + pg_dump:
echo    pg_dump "postgres://..." ^> backup.sql
echo.
echo NEXT STEPS RECOMMENDED:
echo --------------------------------------------------------
echo - Move this backup folder to cloud ^(Google Drive, OneDrive^)
echo - Run backup.bat WEEKLY ^(set Windows Task Scheduler^)
echo - Once a month, do full pg_dump backup via Supabase
echo - Keep last 4 weekly + last 6 monthly backups
echo.
echo CONTACT:
echo --------------------------------------------------------
echo Issue with restore? WhatsApp +91 95412 23377
echo.
) > "%BACKUP_DIR%\README.txt"

echo   [OK] Restore guide created
echo.

REM ----- Show summary -----
echo ================================================
echo    BACKUP COMPLETE
echo ================================================
echo  Location: %BACKUP_DIR%
echo  Size:
for /f "tokens=3" %%a in ('dir /s "%BACKUP_DIR%" ^| find "File(s)"') do (
  set "RAW=%%a"
)
echo  Total: !RAW! bytes
echo.
echo  RECOMMENDATIONS:
echo  - Copy backup to Google Drive / OneDrive
echo  - Schedule weekly via Task Scheduler
echo  - Monthly full pg_dump via Supabase dashboard
echo ================================================
echo.
echo Opening backup folder...
start "" "%BACKUP_DIR%"
pause
exit /b 0


REM ============================================================
REM Helper subroutine: export one Supabase table
REM ============================================================
:ExportTable
echo   - Exporting %~1 ...
curl -s -X GET "%SB_URL%/rest/v1/%~1?select=*" ^
  -H "apikey: %SB_KEY%" ^
  -H "Authorization: Bearer %SB_KEY%" ^
  -H "Accept: application/json" > "%BACKUP_DIR%\database\%~1.json" 2>nul
exit /b 0


:NoProject
echo.
echo [ERROR] Project folder not found: %PROJECT%
echo.
pause
exit /b 1
