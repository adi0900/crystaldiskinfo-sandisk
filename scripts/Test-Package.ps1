#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidatePattern('\A[0-9]+\.[0-9]+\.[0-9]+\z')]
    [string] $Version = '0.1.0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Get-Item -LiteralPath (Join-Path $PSScriptRoot '..')).FullName
$release = Join-Path (Join-Path $root 'dist') $Version
$setupName = "CrystalDiskInfo-SanDisk-$Version-Setup-x64.exe"
$zipName = "CrystalDiskInfo-SanDisk-$Version-windows-x64.zip"
$setup = Join-Path $release $setupName
$zip = Join-Path $release $zipName
$manifest = Get-Content -LiteralPath (Join-Path $release 'SHA256SUMS.txt')
foreach ($name in $setupName, $zipName) {
    $asset = Join-Path $release $name
    $hash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash.ToLowerInvariant()
    if ("$hash  $name" -notin $manifest) {
        throw "Checksum verification failed for $name."
    }
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($zip)
try {
    foreach ($name in 'DiskInfo64.exe', 'CdiResource/dialog/Graph.html', 'CdiResource/language/English.lang',
        'LICENSE.txt', 'License/COPYRIGHT.txt', 'NOTICE.md', 'VERSION.txt') {
        if (-not $archive.GetEntry($name)) {
            throw "The portable ZIP is missing $name."
        }
    }
    $privateEntries = $archive.Entries | Where-Object { $_.FullName -match '(^|[/\\])(DiskInfo\.ini|DiskInfo\.txt|Smart)([/\\]|$)' }
    if ($privateEntries) {
        throw 'The portable ZIP contains settings or saved device data.'
    }
    $entryStream = $archive.GetEntry('DiskInfo64.exe').Open()
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $portableExeHash = [BitConverter]::ToString($sha.ComputeHash($entryStream)).Replace('-', '')
    } finally {
        $sha.Dispose()
        $entryStream.Dispose()
    }
} finally {
    $archive.Dispose()
}

$fixture = Join-Path (Join-Path $root '.build') ('smoke-' + [Guid]::NewGuid().ToString('N'))
$installedRoot = Join-Path $fixture 'Programs'
$shortcut = Join-Path $fixture 'Start Menu\CrystalDiskInfo for SanDisk.lnk'
[void] [Reflection.Assembly]::LoadFile($setup)
$installed = [CrystalDiskInfoSanDisk.PackageInstaller]::Install($installedRoot, $shortcut)
if ((Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash -ne $portableExeHash) {
    throw 'The installer and portable ZIP contain different app executables.'
}

$settings = Join-Path (Split-Path -Parent $installed) 'DiskInfo.ini'
Set-Content -LiteralPath $settings -Value '[SmokeTest]' -Encoding Ascii
$reinstalled = [CrystalDiskInfoSanDisk.PackageInstaller]::Install($installedRoot, $shortcut)
if ($reinstalled -ne $installed -or (Get-Content -LiteralPath $settings) -ne '[SmokeTest]') {
    throw 'Running setup again changed the installed version or its settings.'
}

$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($shortcut)
try {
    if ($link.TargetPath -ne $installed -or $link.WorkingDirectory -ne (Split-Path -Parent $installed)) {
        throw 'The shortcut points to the wrong executable or working directory.'
    }
} finally {
    [void] [Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)
    [void] [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
}

Write-Output "Verified setup, portable ZIP, checksums, shortcut, and reinstall. Test app: $installed"
