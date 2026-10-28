@echo off
setlocal
chcp 65001 >nul
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0XCross-CLI.ps1" menu
if errorlevel 1 (
    echo.
    echo XCross CLI termino con un error. Revisa los mensajes anteriores.
    pause
)
endlocal
