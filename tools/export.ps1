# Builds a standalone Stream Rooms for Windows into a fresh folder, ready to copy to another PC.
#
# - Uses the "Windows Desktop" export preset, but runs the export without the editor window.
#   That has two upsides: the editor can't put back settings it remembers (it re-enabled the
#   shader baker once, and shaders baked on this PC froze another PC), and the build never has
#   shaders prepared for this PC's graphics card: each PC prepares its own on the first start.
# - Release build (the plugins' release DLLs). Add -DebugBuild for a debug build.
# - Copies tools\ (yt-dlp, ffmpeg) along, which File or URL and watching together need.
# - Checks the game data (.pck) is complete.
#
# Run from PowerShell in the project folder (the editor can stay open):
#   powershell -ExecutionPolicy Bypass -File tools\export.ps1
# The build lands in exported\StreamRooms_<date-time>\. Copy that whole folder.
param(
	[string]$Out = "",
	[string]$Redot = "G:\streamin dings\Redot_v26.2-stable_windows_win64\redot.windows.editor.x86_64.console.exe",
	[switch]$DebugBuild
)
$ErrorActionPreference = "Stop"
$project = Split-Path $PSScriptRoot -Parent
if ($Out -eq "") { $Out = Join-Path $project ("exported\StreamRooms_" + (Get-Date -Format "yyyy-MM-dd_HHmm")) }
if ((Test-Path $Out) -and (Get-ChildItem $Out | Measure-Object).Count -gt 0) {
	throw "$Out isn't empty. Pick another folder with -Out, so nothing old gets mixed in."
}
New-Item -ItemType Directory -Force $Out | Out-Null
$exe = Join-Path $Out "StreamRooms.exe"
$mode = if ($DebugBuild) { "--export-debug" } else { "--export-release" }

Write-Host "Exporting to $Out ..."
$log = Join-Path $Out "export_log.txt"
$p = Start-Process -FilePath $Redot -ArgumentList @("--headless", "--path", "`"$project`"", $mode, "`"Windows Desktop`"", "`"$exe`"") `
	-NoNewWindow -PassThru -Wait -RedirectStandardOutput $log -RedirectStandardError "$log.err"

# the export leaves temp copies of the plugin DLLs behind while the editor holds them open
Get-ChildItem (Join-Path $project "addons") -Recurse -Filter "*.TMP" -ErrorAction SilentlyContinue | Remove-Item -Force

$pck = Join-Path $Out "StreamRooms.pck"
if (-not (Test-Path $exe) -or -not (Test-Path $pck)) {
	throw "The export didn't produce StreamRooms.exe and StreamRooms.pck. See $log"
}
$mb = [math]::Round((Get-Item $pck).Length / 1MB)
if ($mb -lt 100) {
	throw "StreamRooms.pck is only $mb MB (a complete one is about 140 MB). Check Project > Export > Resources > Export Mode is 'Export all resources in the project'."
}
New-Item -ItemType Directory -Force (Join-Path $Out "tools") | Out-Null
Copy-Item (Join-Path $project "tools\*.exe") (Join-Path $Out "tools")
Remove-Item $log, "$log.err" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Done: $Out ($mb MB of game data)."
Get-ChildItem $Out -Recurse -File | ForEach-Object { Write-Host ("  " + $_.FullName.Substring($Out.Length + 1)) }
Write-Host "Copy the whole folder to the other PC. The first start there takes a little longer while it prepares its shaders."
