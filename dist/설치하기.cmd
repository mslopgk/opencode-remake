@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\lib-log.ps1; . .\scripts\lib-appstate.ps1; . .\scripts\lib-team.ps1; . .\scripts\selfcheck.ps1; . .\scripts\orchestrator.ps1; exit (Start-CampInstall -DistDir '%~dp0')"
set RC=%ERRORLEVEL%
pause
exit /b %RC%
