@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\lib-log.ps1; . .\scripts\github-connect.ps1; exit (Connect-CampGithub)"
set RC=%ERRORLEVEL%
if %RC% NEQ 0 pause
exit /b %RC%
