<#
PACKAGING.md step 3: exports the Windows release build (export_presets.cfg, "Windows Desktop": .pck embedded in the
exe, plus a console wrapper) to .local/packaging/game/, then checks the embedded .pck (packaging/check_pck.py): nothing
from assets/, tests/, tools/ or .local/ may ship.

  .\packaging\build_game.ps1

Needs Godot 4.7.2 (GODOT_EXE or the default under C:\Tools) and the 4.7.2 export templates in .local/Godot/
export_templates/4.7.2.stable (the launcher's Godot data folder; PACKAGING.md says how they were installed).
#>
param([string]$Godot = $env:GODOT_EXE)
$project = Split-Path $PSScriptRoot -Parent
if (-not $Godot) { $Godot = 'C:\Tools\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' }
$out = Join-Path $project '.local/packaging/game'
New-Item -ItemType Directory -Force $out | Out-Null
$exe = Join-Path $out 'WBC3Redux.exe'
# Godot runs with the launcher's data folder (templates, editor settings); the caller's environment is restored after,
# so nothing started later from the same window (an installer test, say) sees the redirected folders.
$saved = @{ APPDATA = $env:APPDATA; LOCALAPPDATA = $env:LOCALAPPDATA }
try {
    $env:APPDATA = Join-Path $project '.local'
    $env:LOCALAPPDATA = $env:APPDATA
    $templates = Join-Path $env:APPDATA 'Godot/export_templates/4.7.2.stable/windows_release_x86_64.exe'
    if (-not (Test-Path $templates)) { throw "Export templates missing: $templates" }
    & $Godot --headless --path $project --export-release 'Windows Desktop' $exe *> (Join-Path $out 'export.log')
    $code = $LASTEXITCODE
} finally {
    $env:APPDATA = $saved.APPDATA
    $env:LOCALAPPDATA = $saved.LOCALAPPDATA
}
if ($code -ne 0) { throw "Export failed; see $out\export.log" }
if (Select-String -Path (Join-Path $out 'export.log') -Pattern 'ERROR' -SimpleMatch -Quiet) { throw "Export logged errors; see $out\export.log" }
python (Join-Path $PSScriptRoot 'check_pck.py') $exe
if ($LASTEXITCODE -ne 0) { throw 'The exported .pck failed its check.' }
Write-Host ("Built {0} ({1:N1} MB)" -f $exe, ((Get-Item $exe).Length / 1MB))
