<#
Shared limit for heavy Godot runs across parallel sessions (soaks, world suites, -Check -Quick, profiling): at most two
at once on this PC. Every worktree uses the same lock folder in the main checkout's .local (ignored by git).

  .\tools\heavy_slot.ps1 -Acquire -Owner 'p3-perf'     # waits until a slot is free, prints the slot name
  .\tools\heavy_slot.ps1 -Release -Owner 'p3-perf'     # frees the slot this owner holds
  .\tools\heavy_slot.ps1 -Status

A slot is a folder (mkdir is atomic). A slot older than -StaleMinutes (default 120) is treated as abandoned.
#>
param(
    [switch]$Acquire,
    [switch]$Release,
    [switch]$Status,
    [string]$Owner = 'unnamed',
    [int]$Slots = 2,
    [int]$StaleMinutes = 120,
    [int]$WaitSeconds = 14400
)
# The main checkout is the folder holding git's common directory, the same for every worktree.
$common = git -C $PSScriptRoot rev-parse --path-format=absolute --git-common-dir 2>$null
$main = if ($LASTEXITCODE -eq 0 -and $common) { Split-Path $common -Parent } else { Split-Path $PSScriptRoot -Parent }
$root = Join-Path $main '.local\heavy-slots'
New-Item -ItemType Directory -Force $root | Out-Null

function Get-Slots {
    Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $file = Join-Path $_.FullName 'owner.txt'
        [pscustomobject]@{ Name = $_.Name; Path = $_.FullName; Age = ((Get-Date) - $_.CreationTime).TotalMinutes
            Owner = if (Test-Path $file) { (Get-Content $file -Raw).Trim() } else { '?' } }
    }
}

if ($Status) { Get-Slots | Format-Table Name, Owner, @{n='Minutes'; e={[int]$_.Age}}; exit 0 }

if ($Release) {
    foreach ($s in Get-Slots) { if ($s.Owner -eq $Owner) { Remove-Item -Recurse -Force $s.Path; "released $($s.Name)" } }
    exit 0
}

if ($Acquire) {
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ((Get-Date) -lt $deadline) {
        foreach ($s in Get-Slots) { if ($s.Age -gt $StaleMinutes) { Remove-Item -Recurse -Force $s.Path -ErrorAction SilentlyContinue } }
        for ($i = 1; $i -le $Slots; $i++) {
            $path = Join-Path $root "slot$i"
            try {
                New-Item -ItemType Directory $path -ErrorAction Stop | Out-Null
                Set-Content -Path (Join-Path $path 'owner.txt') -Value $Owner -Encoding utf8
                "acquired slot$i"
                exit 0
            } catch { }
        }
        Start-Sleep -Seconds 20
    }
    Write-Error 'No heavy slot became free in time.'
    exit 1
}
'Pass -Acquire, -Release or -Status.'
