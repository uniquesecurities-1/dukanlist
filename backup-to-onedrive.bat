@echo off
setlocal EnableDelayedExpansion
title DukanList - Backup to OneDrive
color 0E

REM ============================================================
REM  DukanList - SAFE Backup to OneDrive
REM  Double-click se ek ZIP archive OneDrive me save ho jata hai.
REM
REM  - Excludes .git folder (conflicts cause)
REM  - Excludes node_modules (rebuilds automatically)
REM  - Excludes backups/ (avoid recursive nesting)
REM  - Auto-detects OneDrive path
REM  - Keeps last 10 backups, deletes older (saves space)
REM  - Uses Windows PowerShell built-in (no extra software)
REM
REM  Recommended: Weekly run karein (Sunday raat ko).
REM  Optional: Windows Task Scheduler me schedule kar sakte hain.
REM ============================================================

REM ----- 1. Find OneDrive path -----
set "OD_PATH="

if defined OneDrive (
  set "OD_PATH=%OneDrive%"
) else if defined OneDriveCommercial (
  set "OD_PATH=%OneDriveCommercial%"
) else if defined OneDriveConsumer (
  set "OD_PATH=%OneDriveConsumer%"
) else if exist "%UserProfile%\OneDrive" (
  set "OD_PATH=%UserProfile%\OneDrive"
)

if not defined OD_PATH (
  color 0C
  echo.
  echo [ERROR] OneDrive folder not found on this PC.
  echo.
  echo Make sure OneDrive is installed and signed in.
  echo Usually located at: C:\Users\^<your-name^>\OneDrive
  echo.
  echo Tip: Open File Explorer ^- if OneDrive shows on the
  echo      left sidebar, restart this script.
  echo.
  pause
  exit /b 1
)

REM ----- 2. Prepare backup folder -----
set "BACKUP_ROOT=%OD_PATH%\DukanList-Backups"
if not exist "%BACKUP_ROOT%" mkdir "%BACKUP_ROOT%"

REM ----- 3. Build timestamp filename -----
for /f "tokens=2 delims==" %%a in ('wmic OS Get localdatetime /value') do set DT=%%a
set "TS=%DT:~0,4%-%DT:~4,2%-%DT:~6,2%_%DT:~8,2%%DT:~10,2%"
set "ZIP_NAME=dukanlist_%TS%.zip"
set "ZIP_PATH=%BACKUP_ROOT%\%ZIP_NAME%"

echo.
echo ================================================
echo    DukanList - BACKUP TO ONEDRIVE
echo ================================================
echo Source       : E:\dukanlist-web
echo Destination  : %BACKUP_ROOT%
echo File         : %ZIP_NAME%
echo.
echo This may take 10-30 seconds...
echo.

REM ----- 4. Use PowerShell to ZIP everything (smart-excluded) -----
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "$src = 'E:\dukanlist-web';" ^
  "$dst = '%ZIP_PATH%';" ^
  "$tmp = Join-Path $env:TEMP ('dl_backup_' + [guid]::NewGuid().ToString());" ^
  "New-Item -ItemType Directory -Path $tmp ^| Out-Null;" ^
  "$exclude = @('.git', 'node_modules', 'backups', 'New folder');" ^
  "Get-ChildItem -Path $src -Force ^| Where-Object { $exclude -notcontains $_.Name } ^| ForEach-Object { Copy-Item $_.FullName -Destination $tmp -Recurse -Force };" ^
  "Compress-Archive -Path (Join-Path $tmp '*') -DestinationPath $dst -CompressionLevel Optimal -Force;" ^
  "Remove-Item -Path $tmp -Recurse -Force;" ^
  "$size = (Get-Item $dst).Length / 1MB;" ^
  "Write-Host ('   [OK] Created backup, size: {0:N2} MB' -f $size)"

if errorlevel 1 (
  color 0C
  echo.
  echo [ERROR] Backup failed. Check messages above.
  pause
  exit /b 1
)

REM ----- 5. Cleanup: keep only 10 latest backups -----
echo.
echo Cleaning old backups (keeping last 10)...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$folder = '%BACKUP_ROOT%';" ^
  "$files = Get-ChildItem -Path $folder -Filter 'dukanlist_*.zip' ^| Sort-Object LastWriteTime -Descending;" ^
  "$old = $files ^| Select-Object -Skip 10;" ^
  "if ($old) { $old ^| ForEach-Object { Remove-Item $_.FullName -Force; Write-Host ('   [DEL] ' + $_.Name) } } else { Write-Host '   No old backups to delete.' }"

REM ----- 6. Show what's in the backup folder -----
echo.
echo Current backups in OneDrive:
echo ------------------------------------------------
dir /b /o-d "%BACKUP_ROOT%\dukanlist_*.zip"
echo ------------------------------------------------

color 0A
echo.
echo ================================================
echo    BACKUP SUCCESSFUL
echo ================================================
echo.
echo OneDrive will sync the new ZIP to the cloud in
echo the next 1-2 minutes. Once synced, your project
echo is safe even if this laptop crashes.
echo.
echo Recovery steps (in case of laptop loss):
echo  1. Install OneDrive on new PC, sign in
echo  2. Open folder: %BACKUP_ROOT%
echo  3. Unzip the latest dukanlist_*.zip to E:\dukanlist-web
echo  4. Open Command Prompt, run:
echo        cd /d E:\dukanlist-web
echo        git init
echo        git remote add origin ^<your-github-url^>
echo        git pull origin main
echo.
echo Recommended: run this backup every Sunday.
echo ================================================
echo.
timeout /t 10 /nobreak >nul
exit /b 0
