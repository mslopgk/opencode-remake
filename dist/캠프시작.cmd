@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\lib-log.ps1; . .\scripts\lib-appstate.ps1; . .\scripts\lib-team.ps1; . .\scripts\launcher.ps1; exit (Start-CampLauncher -TemplateDir '%~dp0template')"
set RC=%ERRORLEVEL%
if %RC% NEQ 0 pause
exit /b %RC%
