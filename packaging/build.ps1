<#
PACKAGING.md step 4: builds the player's installer in one step.
  1. packaging/build_game.ps1      Godot export + .pck check     -> .local/packaging/game/WBC3Redux.exe
  2. packaging/build_importer.ps1  importer.exe (PyInstaller)    -> .local/packaging/importer/
  3. Inno Setup 7 (ISCC.exe)       packaging/installer.iss       -> .local/packaging/installer/<name>-Setup-<version>.exe

  .\packaging\build.ps1 -Version 0.1.0
  .\packaging\build.ps1 -Version 0.1.0 -SkipImporter     # reuse the last importer.exe
  .\packaging\build.ps1 -Version 0.1.0 -Test             # "WBC3 Redux test": own AppId and Start menu name, for
                                                        # automated installs that must not touch a real install

ISCC.exe: -Iscc, INNO_ISCC, or the portable Inno Setup 7 in .local/tools/innosetup7 (PACKAGING.md says how it was
installed).
#>
param(
    [string]$Version = '0.1.0',
    [string]$Iscc = $env:INNO_ISCC,
    [switch]$SkipImporter,
    [switch]$Test
)
$project = Split-Path $PSScriptRoot -Parent
if (-not $Iscc) { $Iscc = Join-Path $project '.local/tools/innosetup7/ISCC.exe' }
if (-not (Test-Path $Iscc)) { throw "Inno Setup compiler not found: $Iscc" }

& (Join-Path $PSScriptRoot 'build_game.ps1')
if (-not $?) { throw 'Game export failed.' }
if (-not $SkipImporter) {
    & (Join-Path $PSScriptRoot 'build_importer.ps1')
    if (-not $?) { throw 'Importer build failed.' }
}
if (-not (Test-Path (Join-Path $project '.local/packaging/importer/importer.exe'))) { throw 'importer.exe missing; run without -SkipImporter.' }

$log = Join-Path $project '.local/packaging/iscc.log'
$defines = @("/DAppVersion=$Version") + $(if ($Test) { @('/DTestBuild') } else { @() })
& $Iscc @defines (Join-Path $PSScriptRoot 'installer.iss') *> $log
if ($LASTEXITCODE -ne 0) { Get-Content $log -Tail 15; throw "Inno Setup failed; see $log" }
$setup = Get-ChildItem (Join-Path $project '.local/packaging/installer') -Filter "*-Setup-$Version.exe" | Sort-Object LastWriteTime | Select-Object -Last 1
Write-Host ("Installer: {0} ({1:N1} MB)" -f $setup.FullName, ($setup.Length / 1MB))
