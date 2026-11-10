@echo off
setlocal
cd /d "%~dp0"
title Instalador de Impressoras - TI Prefeitura

rem O script principal solicita elevacao via UAC quando necessario.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0InstaladorImpressoras.ps1"
set "PS_EXIT=%ERRORLEVEL%"
if not "%PS_EXIT%"=="0" (
    echo.
    echo O instalador encerrou com erro (codigo %PS_EXIT%).
    pause
)
exit /b %PS_EXIT%
