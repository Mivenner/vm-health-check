@echo off
rem Esempio: Avvia-CLI.cmd -Pdf -Cliente "Nome cliente"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0VMHealth.CLI.ps1" %*
