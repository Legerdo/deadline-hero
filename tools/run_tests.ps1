# Runs data/formula checks and the S4 gameplay regressions headless.
# Exit code 0 = all passed. Never touches the player's save.
$godot = $env:GODOT_PATH
if (-not $godot) {
    $cmd = Get-Command godot_console, godot -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $godot = $cmd.Source }
}
if (-not $godot -and $env:LOCALAPPDATA) {
    $localGodot = Join-Path $env:LOCALAPPDATA "Programs\Godot\bin\godot_console.exe"
    if (Test-Path $localGodot) { $godot = $localGodot }
}
if (-not $godot -or -not (Test-Path $godot)) {
    throw "Godot executable not found. Set GODOT_PATH or add godot/godot_console to PATH."
}
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
foreach ($scenario in @("tests", "stage4-tests")) {
    & $godot --headless --path $root -- "--scenario=$scenario" 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match "\[test\]|SCRIPT ERROR|Parse Error|ERROR:|WARNING:" }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
exit 0
