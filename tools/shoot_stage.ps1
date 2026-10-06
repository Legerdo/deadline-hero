param(
    [Parameter(Mandatory = $true)][string]$Stage,
    [string]$Times = "3,12,24,36",
    [string]$Extra = ""
)
# Bot-plays a stage in a window and saves a 2x2 contact sheet to tools/_preview/sheet_<stage>.png
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$shots = Join-Path $root "tools\_shots"
Get-ChildItem $shots -Filter "shot_*.png" -ErrorAction SilentlyContinue | Remove-Item
$last = [double](($Times.Split(",") | Select-Object -Last 1)) + 0.5
$out = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\run_check.ps1") -Window -Fast -Frames 20000 -UserArgs "--stage=$Stage --bot --fresh --shots=$Times --quit-at=$last $Extra"
$out | Where-Object { $_ -match "dbg\] (CLEAR|TIMEUP|DOWN)|SCRIPT ERROR|at: " } | Select-Object -Unique
$files = Get-ChildItem $shots -Filter "shot_*.png" | Sort-Object Name | ForEach-Object { $_.FullName }
python (Join-Path $root "tools\contact_sheet.py") (Join-Path $root "tools\_preview\sheet_$Stage.png") @files
