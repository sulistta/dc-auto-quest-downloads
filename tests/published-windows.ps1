# Exercise the published command against an isolated Discord installation.
$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('autoquest-published-'+[guid]::NewGuid().ToString('N'))
$oldAppData = $env:APPDATA
$oldLocal = $env:LOCALAPPDATA
try {
    $env:APPDATA = Join-Path $fixture 'profile'
    $env:LOCALAPPDATA = Join-Path $fixture 'local'
    $core = Join-Path $env:APPDATA 'discord/app-1.0.1/modules/discord_desktop_core-1/discord_desktop_core'
    New-Item -ItemType Directory -Path $core -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $core 'core.asar'), 'fixture')
    $index = Join-Path $core 'index.js'
    $original = "module.exports = require('./core.asar');`n// independent modification`n"
    [IO.File]::WriteAllText($index, $original)
    Invoke-RestMethod 'https://raw.githubusercontent.com/sulistta/dc-auto-quest-downloads/main/install.ps1' | Invoke-Expression
    $installed = [IO.File]::ReadAllText($index)
    if (-not $installed.Contains('BEGIN DC AUTO QUEST INTEGRATION') -or -not $installed.Contains('independent modification')) { throw 'The integration or the independent code was lost.' }
    Invoke-RestMethod 'https://raw.githubusercontent.com/sulistta/dc-auto-quest-downloads/main/install.ps1' | Invoke-Expression
    if ([IO.File]::ReadAllText($index) -cne $installed) { throw 'Repeat installation rewrote an intact integration.' }
    $cli = Join-Path $env:LOCALAPPDATA 'dc-auto-quest/bin/dc-auto-quest.exe'
    & $cli --status
    if ($LASTEXITCODE -ne 0) { throw 'Status failed.' }
    & $cli --remove
    if ($LASTEXITCODE -ne 0) { throw 'Removal failed.' }
    if ([IO.File]::ReadAllText($index) -cne $original) { throw 'Removal did not preserve the independent code.' }
    if (Test-Path -LiteralPath (Join-Path $env:APPDATA 'dev.dcautoquest.desktop/integration.json')) { throw 'Ownership record was not removed.' }
    Write-Host 'Published Windows installation, repeat and removal passed.'
} finally {
    $env:APPDATA = $oldAppData
    $env:LOCALAPPDATA = $oldLocal
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
