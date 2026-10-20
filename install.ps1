# DC Auto Quest: PowerShell 5.1+, normal desktop account.
function Assert-AutoQuestPlatform {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $PSVersionTable.PSVersion.Major -lt 5) { throw 'Use o PowerShell 5.1 ou superior no Windows.' }
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if (-not $architecture) { $architecture = $env:PROCESSOR_ARCHITECTURE }
    if ($architecture -ne 'AMD64' -or -not [Environment]::Is64BitProcess) { throw 'Use o PowerShell de 64 bits em um Windows x64.' }
    $session = (Get-Process -Id $PID).SessionId
    if (@(Get-Process -Name Discord,DiscordPTB,DiscordCanary -ErrorAction SilentlyContinue | Where-Object SessionId -eq $session).Count) { throw 'Feche completamente o Discord, incluindo a bandeja, e execute o comando novamente.' }
}
function Save-AutoQuestDownload([string]$Url, [string]$Destination) {
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -TimeoutSec 180 -Headers @{'User-Agent'='DCAutoQuest-Installer'} | Out-Null
}
function Assert-AutoQuestHash([string]$Archive, [string]$Checksum) {
    if ((Get-Item -LiteralPath $Archive).Length -gt 67108864 -or (Get-Item -LiteralPath $Checksum).Length -gt 256) { throw 'Pacote ou verificacao muito grande.' }
    $value = Get-Content -LiteralPath $Checksum -Raw
    if ($value -notmatch '\A([a-fA-F0-9]{64})[ \t]+\*?dc-auto-quest-windows-x64\.zip\r?\n?\z') { throw 'Verificacao do pacote invalida.' }
    if ((Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash -ne $Matches[1]) { throw 'O SHA-256 nao confere; nenhum arquivo baixado foi executado.' }
}
function Expand-AutoQuestPackage([string]$Archive, [string]$Directory) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $expected = @('dc-auto-quest.exe','README.md','LICENSE')
        if ($zip.Entries.Count -ne $expected.Count) { throw 'Pacote incompleto ou com arquivos inesperados.' }
        foreach ($name in $expected) {
            $entries = @($zip.Entries | Where-Object FullName -ceq $name)
            if ($entries.Count -ne 1 -or $entries[0].Length -lt 1 -or $entries[0].Length -gt 33554432 -or (($entries[0].ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw ('Arquivo ausente, repetido ou invalido: '+$name+'.') }
        }
        foreach ($entry in $zip.Entries) {
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $Directory $entry.FullName), $false)
        }
    } finally { $zip.Dispose() }
}
function Invoke-AutoQuestIntegration([string]$Executable) {
    & $Executable
    if ($LASTEXITCODE -ne 0) { throw 'A integracao nao foi concluida. O comando anterior foi preservado; verifique a mensagem acima e tente novamente.' }
}
function Install-AutoQuest {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    Set-StrictMode -Version 2
    Assert-AutoQuestPlatform
    if (-not $env:LOCALAPPDATA) { throw 'O perfil do Windows nao esta disponivel.' }
    $directory = Join-Path ([IO.Path]::GetTempPath()) ('dc-auto-quest-install-'+[guid]::NewGuid().ToString('N'))
    $base = Join-Path $env:LOCALAPPDATA 'dc-auto-quest'
    $staged = Join-Path $base ('.bin-'+[guid]::NewGuid().ToString('N'))
    $backup = Join-Path $base ('.previous-'+[guid]::NewGuid().ToString('N'))
    $bin = Join-Path $base 'bin'
    $download = 'https://github.com/sulistta/dc-auto-quest-downloads/releases/latest/download/dc-auto-quest-windows-x64.zip'
    $tls = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $tls -bor [Net.SecurityProtocolType]::Tls12
        New-Item -ItemType Directory -Path $directory | Out-Null
        $archive = Join-Path $directory 'package.zip'
        $checksum = Join-Path $directory 'package.sha256'
        Save-AutoQuestDownload $download $archive
        Save-AutoQuestDownload ($download+'.sha256') $checksum
        Assert-AutoQuestHash $archive $checksum
        Expand-AutoQuestPackage $archive $directory
        New-Item -ItemType Directory -Force -Path $staged | Out-Null
        Copy-Item -LiteralPath (Join-Path $directory 'dc-auto-quest.exe') -Destination $staged
        Invoke-AutoQuestIntegration (Join-Path $staged 'dc-auto-quest.exe')
        if (Test-Path -LiteralPath $bin) { [IO.Directory]::Move($bin, $backup) }
        try { [IO.Directory]::Move($staged, $bin) }
        catch { if (Test-Path -LiteralPath $backup) { [IO.Directory]::Move($backup, $bin) }; throw }
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
        Write-Host 'Instalacao concluida. Reabra o Discord.'
        Write-Host ('Status: & "'+(Join-Path $bin 'dc-auto-quest.exe')+'" --status')
        Write-Host ('Remover: & "'+(Join-Path $bin 'dc-auto-quest.exe')+'" --remove')
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $tls
        foreach ($path in @($directory,$staged)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force } }
    }
}
if ($MyInvocation.InvocationName -ne '.') { Install-AutoQuest }
