$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../install.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Assert-True($Value, [string]$Message) {
    if (-not $Value) { throw $Message }
}
function Assert-AutoQuestPlatform { }
function Invoke-AutoQuestIntegration([string]$Executable) {
    Assert-True (Test-Path -LiteralPath $Executable) 'Executable was not staged.'
    $script:Invocations++
    if ($script:HelperFails) { throw 'Fixture integration failed.' }
}
function Save-AutoQuestDownload([string]$Url, [string]$Destination) {
    Assert-True ($Url.StartsWith('https://github.com/sulistta/dc-auto-quest-downloads/releases/latest/download/')) 'Unexpected download origin.'
    if ($Url.EndsWith('.sha256')) { Copy-Item -LiteralPath $script:Checksum -Destination $Destination }
    else { Copy-Item -LiteralPath $script:Archive -Destination $Destination }
}
function New-Fixture([string]$Kind = 'valid', [string]$Payload = 'fixture executable') {
    if (Test-Path -LiteralPath $script:Archive) { Remove-Item -LiteralPath $script:Archive }
    $zip = [IO.Compression.ZipFile]::Open($script:Archive, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $names = @('dc-auto-quest.exe', 'README.md', 'LICENSE')
        if ($Kind -eq 'missing') { $names = @('README.md', 'LICENSE') }
        if ($Kind -eq 'duplicate') { $names += 'dc-auto-quest.exe' }
        if ($Kind -eq 'traversal') { $names += '../escaped' }
        foreach ($name in $names) {
            $entry = $zip.CreateEntry($name)
            if ($Kind -eq 'symlink' -and $name -eq 'dc-auto-quest.exe') { $entry.ExternalAttributes = -1577123840 }
            $stream = $entry.Open()
            try {
                $bytes = [Text.Encoding]::UTF8.GetBytes($Payload)
                $stream.Write($bytes, 0, $bytes.Length)
            } finally { $stream.Dispose() }
        }
    } finally { $zip.Dispose() }
    $hash = (Get-FileHash -LiteralPath $script:Archive -Algorithm SHA256).Hash
    [IO.File]::WriteAllText($script:Checksum, "$hash  dc-auto-quest-windows-x64.zip`n", [Text.Encoding]::ASCII)
}
function Invoke-Fixture([bool]$Success) {
    $failed = $false
    $failureMessage = ''
    try { Install-AutoQuest } catch { $failed = $true; $failureMessage = $_.Exception.Message }
    Assert-True ($failed -ne $Success) ('Unexpected installer result; expected success='+$Success+'; '+$failureMessage)
    Assert-True (@(Get-ChildItem -LiteralPath $script:Temp -Directory -Filter 'dc-auto-quest-install-*').Count -eq 0) 'Temporary downloads leaked.'
    if (Test-Path -LiteralPath $script:Base) {
        Assert-True (@(Get-ChildItem -LiteralPath $script:Base -Directory -Filter '.bin-*').Count -eq 0) 'Staged executable leaked.'
    }
}

$directory = Join-Path ([IO.Path]::GetTempPath()) ('autoquest-installer-tests-'+[guid]::NewGuid().ToString('N'))
$oldLocal = $env:LOCALAPPDATA
$oldTemp = $env:TEMP
$oldTmp = $env:TMP
$oldTmpDir = $env:TMPDIR
try {
    New-Item -ItemType Directory -Path $directory | Out-Null
    $script:Temp = Join-Path $directory 'temporary'
    New-Item -ItemType Directory -Path $script:Temp | Out-Null
    $env:TEMP = $script:Temp
    $env:TMP = $script:Temp
    $env:TMPDIR = $script:Temp
    $env:LOCALAPPDATA = Join-Path $directory 'profile with spaces'
    $script:Base = Join-Path $env:LOCALAPPDATA 'dc-auto-quest'
    $script:Archive = Join-Path $directory 'fixture.zip'
    $script:Checksum = Join-Path $directory 'fixture.sha256'
    $script:Invocations = 0
    $script:HelperFails = $false
    $cli = Join-Path $script:Base 'bin/dc-auto-quest.exe'

    New-Fixture
    Invoke-Fixture $true
    Assert-True ((Get-Content -LiteralPath $cli -Raw) -eq 'fixture executable') 'Initial command missing.'
    New-Fixture 'valid' 'updated executable'
    Invoke-Fixture $true
    Assert-True ((Get-Content -LiteralPath $cli -Raw) -eq 'updated executable') 'Command was not updated.'
    Assert-True ($script:Invocations -eq 2) 'Integration did not run exactly once per install.'

    $previous = Get-Content -LiteralPath $cli -Raw
    foreach ($kind in @('missing','duplicate','traversal','symlink')) {
        New-Fixture $kind
        $count = $script:Invocations
        Invoke-Fixture $false
        Assert-True ($script:Invocations -eq $count) ('Invalid package executed: '+$kind)
        Assert-True ((Get-Content -LiteralPath $cli -Raw) -eq $previous) 'Invalid package replaced the existing command.'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $script:Temp 'escaped'))) 'Traversal escaped extraction.'
    }
    New-Fixture
    [IO.File]::WriteAllText($script:Checksum, (('0'*64)+'  dc-auto-quest-windows-x64.zip'), [Text.Encoding]::ASCII)
    $count = $script:Invocations
    Invoke-Fixture $false
    Assert-True ($script:Invocations -eq $count) 'Invalid checksum executed a package.'
    Assert-True ((Get-Content -LiteralPath $cli -Raw) -eq $previous) 'Invalid checksum replaced the command.'

    foreach ($value in @('invalid', ('0'*64)+'  wrong-name.zip', ('0'*64)+"  dc-auto-quest-windows-x64.zip`nextra")) {
        New-Fixture
        [IO.File]::WriteAllText($script:Checksum, $value, [Text.Encoding]::ASCII)
        $count = $script:Invocations
        Invoke-Fixture $false
        Assert-True ($script:Invocations -eq $count) 'Malformed checksum executed a package.'
        Assert-True ((Get-Content -LiteralPath $cli -Raw) -eq $previous) 'Malformed checksum replaced the command.'
    }
    New-Fixture
    $script:HelperFails = $true
    Invoke-Fixture $false
    Assert-True ((Get-Content -LiteralPath $cli -Raw) -eq $previous) 'Failed integration replaced the command.'
    Write-Host 'Passed: install, update, checksum, missing, duplicate, traversal, symlink, integration failure, cleanup.'
} finally {
    $env:LOCALAPPDATA = $oldLocal
    $env:TEMP = $oldTemp
    $env:TMP = $oldTmp
    $env:TMPDIR = $oldTmpDir
    if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
}
