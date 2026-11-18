@echo off
setlocal
if not defined GODOT_EXE set "GODOT_EXE=%~dp0..\..\work\godot\Godot_v4.5.1-stable_win64.exe"
if not exist "%GODOT_EXE%" (
    echo Godot 4 was not found. Open project.godot with Godot, or set GODOT_EXE to its executable path.
    pause
    exit /b 1
)
start "Lowlight Island" "%GODOT_EXE%" --path "%~dp0."
