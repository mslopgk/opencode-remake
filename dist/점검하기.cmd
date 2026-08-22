@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\lib-log.ps1; . .\scripts\selfcheck.ps1; exit (Start-CampCheck)"
set RC=%ERRORLEVEL%
pause
exit /b %RC%
