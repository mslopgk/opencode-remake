@echo off
chcp 65001 >nul
title 창의디자인캠프 시작
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\lib-log.ps1; . .\scripts\lib-appstate.ps1; . .\scripts\lib-team.ps1; . .\scripts\launcher.ps1; exit (Start-CampLauncher -TemplateDir '%~dp0template')"
if errorlevel 1 (
  echo.
  echo 문제가 생겼어요. 선생님을 불러 주세요.
  pause
)
