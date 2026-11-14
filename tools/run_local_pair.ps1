# Launch a host and a client side by side on this PC (milestone 1 test).
# Usage:  powershell -ExecutionPolicy Bypass -File tools\run_local_pair.ps1 [-Godot path\to\godot.exe] [-Night]
param(
    [string]$Godot = $(if ($env:GODOT) { $env:GODOT } else { "godot" }),
    [switch]$Night
)
$project = Split-Path -Parent $PSScriptRoot
$extra = @()
if ($Night) { $extra += "--start-phase=night" }
Start-Process $Godot -ArgumentList (@("--path", "`"$project`"", "--resolution", "960x540", "--position", "0,40", "--", "--host", "--autostart=2", "--name=Host") + $extra)
Start-Sleep -Seconds 2
Start-Process $Godot -ArgumentList @("--path", "`"$project`"", "--resolution", "960x540", "--position", "960,40", "--", "--join=127.0.0.1", "--name=Guest")
