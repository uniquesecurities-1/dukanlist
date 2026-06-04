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
REM  - Auto-detects OneDrive path (handles spaces in path)
REM  - Keeps last 10 backups, deletes older (saves space)
REM  - Uses Windows PowerShell built-in (no extra software)
REM
REM  Recommended: Weekly run karein (Sunday raat ko).
REM ============================================================

REM ----- 1. Find OneDrive path (env vars set by OneDrive client) -----
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
  echo Make sure OneDrive is installed and signed in.
  echo.
  pause
  exit /b 1
)

REM ----- 2. Prepare destination folder -----
set "BACKUP_ROOT=%OD_PATH%\DukanList-Backups"
if not exist "%BACKUP_ROOT%" mkdir "%BACKUP_ROOT%"

REM ----- 3. Build timestamp filename -----
for /f "tokens=2 delims==" %%a in ('wmic OS Get localdatetime /value 2^>nul') do set DT=%%a
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
echo Working... this may take 10-60 seconds.
echo.

REM ----- 4. Write a temp PowerShell script (avoids escape hell) -----
set "PS_SCRIPT=%TEMP%\dl_backup.ps1"
> "%PS_SCRIPT%" echo $ErrorActionPreference = 'Stop'
>>"%PS_SCRIPT%" echo $src = 'E:\dukanlist-web'
>>"%PS_SCRIPT%" echo $dst = '%ZIP_PATH%'
>>"%PS_SCRIPT%" echo $tmp = Join-Path $env:TEMP ('dl_bk_' + [System.Guid]::NewGuid().ToString())
>>"%PS_SCRIPT%" echo $null = New-Item -ItemType Directory -Path $tmp -Force
>>"%PS_SCRIPT%" echo $exclude = @('.git', 'node_modules', 'backups', 'New folder', '.vscode', '.idea')
>>"%PS_SCRIPT%" echo Get-ChildItem -Path $src -Force ^| Where-Object { $exclude -notcontains $_.Name } ^| ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $tmp -Recurse -Force }
>>"%PS_SCRIPT%" echo if (Test-Path $dst) { Remove-Item -LiteralPath $dst -Force }
>>"%PS_SCRIPT%" echo Compress-Archive -Path (Join-Path $tmp '*') -DestinationPath $dst -CompressionLevel Optimal -Force
>>"%PS_SCRIPT%" echo Remove-Item -LiteralPath $tmp -Recurse -Force
>>"%PS_SCRIPT%" echo $size = (Get-Item -LiteralPath $dst).Length / 1MB
>>"%PS_SCRIPT%" echo Write-Host ('   [OK] Created backup, size: {0:N2} MB' -f $size) -ForegroundColor Green

REM ----- 5. Run the PowerShell script -----
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
set "PS_RESULT=%errorlevel%"

REM ----- 6. Clean up the temp script file -----
del /q "%PS_SCRIPT%" 2>nul

if not "%PS_RESULT%"=="0" (
  color 0C
  echo.
  echo [ERROR] Backup failed. Check messages above.
  echo Common causes:
  echo  - OneDrive folder is read-only or full
  echo  - Antivirus blocked PowerShell
  echo  - Source folder E:\dukanlist-web not accessible
  echo.
  pause
  exit /b 1
)

REM ----- 7. Cleanup: keep only 10 latest backups -----
echo.
echo Cleaning old backups (keeping last 10)...
set "PS_CLEAN=%TEMP%\dl_cleanup.ps1"
> "%PS_CLEAN%" echo $folder = '%BACKUP_ROOT%'
>>"%PS_CLEAN%" echo $files = Get-ChildItem -LiteralPath $folder -Filter 'dukanlist_*.zip' ^| Sort-Object LastWriteTime -Descending
>>"%PS_CLEAN%" echo $old = $files ^| Select-Object -Skip 10
>>"%PS_CLEAN%" echo if ($old) { $old ^| ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force; Write-Host ('   [DEL] ' + $_.Name) } } else { Write-Host '   No old backups to delete.' }
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_CLEAN%"
del /q "%PS_CLEAN%" 2>nul

REM ----- 8. Show current backups in folder -----
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
echo  3. Unzip the latest dukanlist_*.zip
echo  4. (or) git clone from GitHub for live history
echo.
echo Recommended: run this backup every Sunday.
echo ================================================
echo.
timeout /t 10 /nobreak >nul
exit /b 0
