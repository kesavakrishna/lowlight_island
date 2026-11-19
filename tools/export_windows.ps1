# Build the standalone Windows game and a zip to share with friends.
# Needs the Godot 4.7.2 export templates installed (Editor > Manage Export Templates, or extract
# the Windows x86_64 files from the .tpz into %APPDATA%\Godot\export_templates\4.7.2.stable\).
# Usage:  powershell -ExecutionPolicy Bypass -File tools\export_windows.ps1 [-Godot path\to\godot_console.exe]
param(
    [string]$Godot = $(if ($env:GODOT) { $env:GODOT } else { "godot" })
)
$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $project "build\windows"
New-Item -ItemType Directory -Force $out | Out-Null

& $Godot --headless --path "$project" --import | Out-Null
& $Godot --headless --path "$project" --export-release "Windows Desktop" (Join-Path $out "LowlightIsland.exe")
if (-not (Test-Path (Join-Path $out "LowlightIsland.exe"))) { throw "Export failed: no LowlightIsland.exe" }

Copy-Item (Join-Path $project "docs\REMOTE_PLAY.md") $out -Force
@"
LOWLIGHT ISLAND - co-op survival horror for 2-4 friends

1. One person clicks 'Host a run'. Windows may ask about the firewall: allow it.
2. Everyone else types the host's address and clicks 'Join by address'.
   - Same Wi-Fi / LAN: the host's local address shown in the lobby.
   - Different homes: use Tailscale (free) - see REMOTE_PLAY.md.
3. The host clicks 'Start run'. 'How to play' in the menu explains the rest.

Windows SmartScreen may warn that the app is unrecognised (it isn't signed):
choose 'More info' -> 'Run anyway'.

Playtest notes: F8 saves a quick note in-game. Run reports and notes are in
%APPDATA%\Godot\app_userdata\Lowlight Island\ (runs\ and feedback.log).
"@ | Set-Content -Encoding utf8 (Join-Path $out "PLAYING.txt")

$zip = Join-Path $project "build\LowlightIsland-windows.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip
Write-Output "Built $zip"
