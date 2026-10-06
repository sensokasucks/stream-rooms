# Downloads yt-dlp.exe and ffmpeg.exe into this tools folder so the game can
# fetch YouTube videos and convert any video to .ogv (Ogg Theora), and
# cloudflared.exe for the Together tab's Cloudflare tunnel.
# Run: right-click this file > "Run with PowerShell"
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$here = $PSScriptRoot

Write-Host "Downloading yt-dlp..."
Invoke-WebRequest "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" -OutFile (Join-Path $here "yt-dlp.exe")

Write-Host "Downloading cloudflared (for the Together tab's Cloudflare tunnel)..."
Invoke-WebRequest "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe" -OutFile (Join-Path $here "cloudflared.exe")

Write-Host "Downloading ffmpeg (GPL build with Theora/Vorbis)..."
$zip = Join-Path $env:TEMP "ffmpeg-win64-gpl.zip"
$tmp = Join-Path $env:TEMP "ffmpeg-win64-gpl"
Invoke-WebRequest "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip" -OutFile $zip
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
Expand-Archive $zip -DestinationPath $tmp -Force
$ff = Get-ChildItem $tmp -Recurse -Filter ffmpeg.exe | Select-Object -First 1
Copy-Item $ff.FullName (Join-Path $here "ffmpeg.exe") -Force
Remove-Item $zip, $tmp -Recurse -Force

Write-Host "Done. Tools are in $here"
& (Join-Path $here "ffmpeg.exe") -hide_banner -encoders 2>$null | Select-String "libtheora"
Read-Host "Press Enter to close"
