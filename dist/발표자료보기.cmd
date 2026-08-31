@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\lib-appstate.ps1; . .\scripts\slides-viewer.ps1; exit (Show-CampSlides)"
set RC=%ERRORLEVEL%
if %RC% NEQ 0 pause
exit /b %RC%
