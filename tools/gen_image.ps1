param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Model = 'gpt-6-luna'
)
# Runs Codex CLI's built-in image_gen tool for tools/prompts/<Name>.txt
# and stores the PNG as tools/art_src/<Name>.png
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$promptFile = Join-Path $root "prompts\$Name.txt"
$style = (Get-Content -Raw -Encoding UTF8 (Join-Path $root "prompts\_style.txt")).Trim()
$body = (Get-Content -Raw -Encoding UTF8 $promptFile).Trim()
$text = ($body + ' ' + $style) -replace '\s+', ' '
$full = "Use your built-in image_gen tool to create the following image. $text Save the resulting PNG into the current working directory with the exact file name $Name.png and do not create or modify any other files. Reply only with the saved path."
Set-Location (Join-Path $root "art_src")
$codex = Get-Command codex -ErrorAction SilentlyContinue
if ($codex) {
    $codex = $codex.Source
} elseif ($env:APPDATA) {
    $npmCodex = Join-Path $env:APPDATA "npm\codex.ps1"
    if (Test-Path $npmCodex) { $codex = $npmCodex }
}
if (-not $codex) {
    throw "Codex CLI not found. Install it or add codex to PATH."
}
& $codex exec --skip-git-repo-check -s workspace-write -m $Model -c model_reasoning_effort=low $full
# Codex may not copy the file into the sandboxed workspace; pull it from ~/.codex/generated_images.
python (Join-Path $root "collect_images.py")
