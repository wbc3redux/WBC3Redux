<#
"Re-import game data" (PACKAGING.md step 4): installed beside the game by packaging/installer.iss and started from the
Start menu. Asks for the Warlords Battlecry III folder (the one chosen at install is the default), converts it again into
a loose assets folder with importer.exe, then runs the game's image preparation, which packs everything into the one
wbc3-data.pck beside the game and removes the loose folder. The Warlords Battlecry III folder is only read.
#>
param([string]$Source = '')
$app = $PSScriptRoot
$importer = Join-Path $app 'importer\importer.exe'
$game = Join-Path $app 'WBC3Redux.exe'
$assets = Join-Path $app 'assets'
$config = Join-Path $app 'source.cfg'
$log = Join-Path $app 'import-log.txt'
$Host.UI.RawUI.WindowTitle = 'Re-import game data'

function Fail([string]$text) {
    Write-Host ''
    Write-Host $text -ForegroundColor Red
    Write-Host "Log: $log"
    Read-Host 'Press Enter to close'
    exit 1
}

if (-not $PSBoundParameters.ContainsKey('Source')) {       # -Source <folder> skips the folder dialog (tests, scripts)
    if (Test-Path $config) {
        $line = Get-Content $config | Where-Object { $_ -like 'path=*' } | Select-Object -First 1
        if ($line) { $Source = $line.Substring(5) }
    }
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Choose the Warlords Battlecry III folder (the one that contains Battlecry III.exe). It is only read.'
    if ($Source -and (Test-Path $Source)) { $dialog.SelectedPath = $Source }
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit 0 }
    $Source = $dialog.SelectedPath
}
if (-not (Test-Path (Join-Path $Source 'Battlecry III.exe'))) { Fail "No Battlecry III.exe in $Source." }
Set-Content -Path $config -Value @('[source]', "path=$Source") -Encoding UTF8

Write-Host "Importing from $Source (about 5 minutes)..."
$lines = New-Object System.Collections.Generic.List[string]
& $importer --source $Source --dest $assets 2>&1 | ForEach-Object {
    $text = "$_"
    $lines.Add($text)
    if ($text -match '^PROGRESS (\d+) (.*)$') {
        Write-Progress -Activity 'Importing game data' -Status $Matches[2] -PercentComplete ([int]$Matches[1])
    }
}
$code = $LASTEXITCODE
Write-Progress -Activity 'Importing game data' -Completed
$lines | Set-Content -Path $log -Encoding UTF8
if ($code -eq 3) { Fail 'This copy of Warlords Battlecry III is a version the importer does not support yet (see the log for the files that differ; please report them).' }
if ($code -ne 0) { Fail "The import failed (code $code)." }

Write-Host 'Preparing the images and packing the game data (about 2 minutes)...'
$p = Start-Process -FilePath $game -ArgumentList '--headless', '--', '--prepare-assets', '--pack' -WorkingDirectory $app -Wait -PassThru -WindowStyle Hidden
if ($p.ExitCode -ne 0 -or -not (Test-Path (Join-Path $app 'wbc3-data.pck')) -or (Test-Path $assets)) {
    Fail "Preparing and packing the game data failed (code $($p.ExitCode))."
}
Write-Host 'Done. The game data is up to date.' -ForegroundColor Green
Start-Sleep -Seconds 3
