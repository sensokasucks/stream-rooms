# Runs the scene tests in _tests/ one at a time and prints a summary.
#
# - Rebuilds the editor's class cache first (a stale cache makes scripts fail with
#   "Identifier ... not declared").
# - Runs every test with --mp-profile=test, starting from a fresh settings_test.cfg each time,
#   so tests start from the default settings and never touch your real settings.cfg.
# - Stops a test that runs longer than the time limit (a script error can leave a test hanging).
#
# Run from PowerShell in the project folder:
#   powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1
#   powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1 -Tests test_crowd,test_reactions
# Screenshots and logs go to -Out (default C:\temp\sr_tests), outside the project folder.
param(
	[string[]]$Tests = @("test_performance", "test_accessibility", "test_crowd", "test_platform_split", "test_reactions", "test_mp_profile", "test_together", "test_panel_clicks", "test_spout", "test_watch_together"),
	[string]$Out = "C:\temp\sr_tests",
	[string]$Redot = "G:\streamin dings\Redot_v26.2-stable_windows_win64\redot.windows.editor.x86_64.console.exe",
	[int]$TimeLimit = 400,
	[switch]$SkipImport
)
$ErrorActionPreference = "Stop"
# "powershell -File" hands "-Tests a,b" over as one string, so split it here
$Tests = @($Tests | ForEach-Object { $_ -split "," } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$project = Split-Path $PSScriptRoot -Parent
$profileCfg = Join-Path $env:APPDATA "Redot\app_userdata\Stream Rooms\settings_test.cfg"
New-Item -ItemType Directory -Force $Out | Out-Null

function Invoke-Redot([string[]]$ArgList, [string]$Log, [int]$Seconds) {
	$p = Start-Process -FilePath $Redot -ArgumentList $ArgList -WorkingDirectory $project -NoNewWindow -PassThru `
		-RedirectStandardOutput $Log -RedirectStandardError "$Log.err"
	$null = $p.Handle    # keeps the handle open so ExitCode can be read afterwards
	if (-not $p.WaitForExit($Seconds * 1000)) {
		Stop-Process -Id $p.Id -Force
		return "TIMED OUT"
	}
	# exit code 0 = quit cleanly; anything else (e.g. -1073741819) = crashed
	return "exit $($p.ExitCode)"
}

if (-not $SkipImport) {
	Write-Host "Rebuilding the class cache..."
	Invoke-Redot @("--headless", "--path", "`"$project`"", "--import") (Join-Path $Out "import.log") 300 | Out-Null
}

$rows = @()
foreach ($t in $Tests) {
	Write-Host "Running $t..."
	$dir = Join-Path $Out $t
	New-Item -ItemType Directory -Force $dir | Out-Null
	if (Test-Path $profileCfg) { Remove-Item $profileCfg -Force }
	$log = Join-Path $Out "$t.log"
	$ended = Invoke-Redot @("--path", "`"$project`"", "_tests/$t.tscn", "--", "`"$dir`"", "--mp-profile=test") $log $TimeLimit
	$text = @(Get-Content $log -ErrorAction SilentlyContinue) + @(Get-Content "$log.err" -ErrorAction SilentlyContinue)
	$rows += [pscustomobject]@{
		Test           = $t
		Ended          = $ended
		Pass           = @($text | Where-Object { $_ -like "PASS *" }).Count
		Fail           = @($text | Where-Object { $_ -like "FAIL *" }).Count
		"Script errors" = @($text | Where-Object { $_ -like "*SCRIPT ERROR*" }).Count
	}
}
if (Test-Path $profileCfg) { Remove-Item $profileCfg -Force }

$rows | Format-Table -AutoSize
Write-Host "Logs and screenshots: $Out"
