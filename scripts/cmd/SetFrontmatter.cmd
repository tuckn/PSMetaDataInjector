@echo off
setlocal EnableExtensions
set "_ROOT=%~dp0.."
set "_SCRIPT=%_ROOT%\SetFrontmatter.ps1"

where pwsh.exe >nul 2>&1
if not errorlevel 1 (
  pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%_SCRIPT%" %*
) else (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%_SCRIPT%" %*
)
endlocal
