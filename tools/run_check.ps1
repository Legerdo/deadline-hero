param(
    [string]$UserArgs = "",
    [int]$Frames = 90,
    [switch]$Window,
    [switch]$Fast
)
# Runs the project and prints only errors/warnings/debug lines from our scripts.
# -Fast uses a fixed 60 fps timestep so simulations run faster than real time.
# -UserArgs: game arguments separated by spaces; wrap a value containing spaces in
#  double quotes, e.g. -UserArgs '--stage=s1 --shotdir="C:\My Folder\shots"'
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
$a = @("--path", $root)
if (-not $Window) { $a += "--headless" }
if ($Fast) { $a += @("--fixed-fps", "60", "--disable-vsync") }
$a += @("--quit-after", "$Frames")
if ($UserArgs -ne "") {
    $a += "--"
    # split on spaces that are outside double quotes, then drop the quotes
    $parts = [regex]::Matches($UserArgs, '(?:[^\s"]+|"[^"]*")+') | ForEach-Object { $_.Value.Replace('"', '') }
    $a += $parts
}
# Start-Process-free invocation keeps each element as one argv entry (spaces preserved)
& $godot @a 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match "ERROR|SCRIPT|Parse|Invalid|at: |\[shot\]|\[dbg\]|\[bot\]|\[test\]|Cannot|null instance|Nonexistent" -and $_ -notmatch "ObjectDB instances|resources still in use|object.cpp|resource.cpp" } | Select-Object -First 200
