@echo off
setlocal
if not defined GODOT_EXE set "GODOT_EXE=%~dp0..\..\work\godot\Godot_v4.5.1-stable_win64.exe"
start "Forest Study" "%GODOT_EXE%" --path "%~dp0."
