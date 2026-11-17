# Runs one headless Godot check with a memory and time guard. Watches only the processes this run started (the console
# executable and the engine it starts as a child) and kills them past -MaxMB or -MaxSeconds.
param(
    [Parameter(Mandatory)][string]$Script,
    [string]$Log = 'guarded.log',
    [int]$MaxMB = 1536,
    [int]$MaxSeconds = 180,
    [string[]]$UserArgs = @(),
    [switch]$Windowed,                 # a real window (rendering benchmarks); the default is headless
    [int]$QuitAfter = 120              # Godot --quit-after (frames); 0 = no limit
)
$root = Split-Path $PSScriptRoot -Parent
$env:APPDATA = Join-Path $root '.local'
$env:LOCALAPPDATA = $env:APPDATA
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
$godot = if ($env:GODOT_EXE) { $env:GODOT_EXE } else { 'C:\Tools\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' }
$logPath = Join-Path $root $Log
$arguments = @('--path', ('"' + $root + '"'), '--script', $Script, '--log-file', ('"' + $logPath + '"'))
if (-not $Windowed) { $arguments = @('--headless') + $arguments }
if ($QuitAfter -gt 0) { $arguments += @('--quit-after', "$QuitAfter") }
if ($UserArgs) { $arguments += @('--') + $UserArgs }
$process = Start-Process -FilePath $godot -ArgumentList $arguments -NoNewWindow -PassThru -RedirectStandardError "$logPath.stderr" -RedirectStandardOutput "$logPath.stdout"
$null = $process.Handle
$watch = [Diagnostics.Stopwatch]::StartNew()
$peak = 0
$killed = ''
while (-not $process.HasExited) {
    # Only this run's own processes: the console executable and the engine it started (other sessions may run Godot too).
    $ids = @($process.Id) + @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($process.Id)" | ForEach-Object { $_.ProcessId })
    $mine = @($ids | ForEach-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
    $total = ($mine | Measure-Object -Property WorkingSet64 -Sum).Sum
    if ($total -gt $peak) { $peak = $total }
    if ($total -gt $MaxMB * 1MB) { $killed = 'memory' }
    elseif ($watch.Elapsed.TotalSeconds -gt $MaxSeconds) { $killed = 'time' }
    if ($killed) { $mine | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }; break }
    Start-Sleep -Milliseconds 200
}
$process.WaitForExit()
"exit=$($process.ExitCode) killed=$killed peakMB=$([int]($peak / 1MB)) seconds=$([int]$watch.Elapsed.TotalSeconds)"
