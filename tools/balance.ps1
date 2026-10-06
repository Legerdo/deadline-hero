param(
    [string]$Stages = "s1,s2,s3,s4,s5,s6,s7",
    [int]$Frames = 16000
)
# Autoplay every stage from a fresh save (bot follows the objective arrow),
# up to ~3 loops, and print the outcome lines per stage.
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
foreach ($s in $Stages.Split(",")) {
    "===== $s"
    $out = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\run_check.ps1") -Fast -Frames $Frames -UserArgs "--stage=$s --bot --fresh --quit-on-clear"
    $out | Where-Object { $_ -match "\[dbg\] (CLEAR|TIMEUP|DOWN)|bought|SCRIPT ERROR|at: " -and $_ -notmatch "backtrace" } | Select-Object -Unique | Select-Object -First 30
}
