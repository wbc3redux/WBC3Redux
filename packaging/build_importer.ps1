<#
PACKAGING.md step 2: freezes tools/import_assets.py (and the importer modules it imports, with Pillow) into a one-folder
importer.exe with PyInstaller, so players need no Python. Output: .local/packaging/importer/importer.exe (+ _internal/).

  .\packaging\build_importer.ps1            # creates .local/pyi-venv from packaging/requirements-build.txt if missing
  .\packaging\build_importer.ps1 -Rebuild   # recreates the venv first

The importer is called by the installer as
  importer.exe --source "<WBC3 folder>" --dest "<install>\assets" --progress-file "<temp>\import-progress.txt"
Exit codes: 0 done, 1 failed, 3 a different version of the game (nothing is written then).
#>
param([switch]$Rebuild)
# No $ErrorActionPreference = 'Stop': Windows PowerShell 5.1 would turn PyInstaller's log lines on stderr into errors.
# Every native step checks $LASTEXITCODE instead.
$project = Split-Path $PSScriptRoot -Parent
$venv = Join-Path $project '.local/pyi-venv'
$python = Join-Path $venv 'Scripts/python.exe'
$out = Join-Path $project '.local/packaging'

if ($Rebuild -and (Test-Path $venv)) { Remove-Item -Recurse -Force $venv }
if (-not (Test-Path $python)) {
    python -m venv $venv
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the build venv (needs Python 3.12 on PATH).' }
    & $python -m pip install --disable-pip-version-check -q -r (Join-Path $PSScriptRoot 'requirements-build.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Could not install the build requirements.' }
}

& $python -m PyInstaller --noconfirm --clean --onedir --console --name importer `
    --paths (Join-Path $project 'tools') `
    --distpath $out --workpath (Join-Path $out 'pyi-build') --specpath (Join-Path $out 'pyi-build') `
    --exclude-module tkinter --exclude-module unittest --exclude-module pydoc `
    (Join-Path $project 'tools/import_assets.py')
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller failed.' }
$exe = Join-Path $out 'importer/importer.exe'
$size = (Get-ChildItem -Recurse (Join-Path $out 'importer') | Measure-Object Length -Sum).Sum / 1MB
Write-Host ("Built {0} ({1:N1} MB with _internal)" -f $exe, $size)
