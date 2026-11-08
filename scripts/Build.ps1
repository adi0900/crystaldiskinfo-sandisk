#requires -Version 5.1
[CmdletBinding()]
param(
    [string] $StandardZip,
    [ValidatePattern('\A[0-9]+\.[0-9]+\.[0-9]+\z')]
    [string] $Version = '0.1.0',
    [string] $CompilerDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Checked {
    param([string] $Program, [string[]] $Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Program exited with code $LASTEXITCODE."
    }
}

$root = (Get-Item -LiteralPath (Join-Path $PSScriptRoot '..')).FullName
$upstream = 'https://github.com/hiyohiyo/CrystalDiskInfo.git'
$revision = '99f885efb57bd98ccce8c2c24188f93c81383cec'
$download = 'https://downloads.sourceforge.net/project/crystaldiskinfo/9.9.4/CrystalDiskInfo9_9_4.zip'
$archiveHash = '0215B873F77C0219147B07C420D92A50E23E8795D507D238D4A6B622E3BF56F4'
$destination = Join-Path (Join-Path $root 'dist') $Version
if (Test-Path -LiteralPath $destination) {
    throw "Release folder already exists at $destination. Choose a new version for another package."
}

$git = (Get-Command git.exe -ErrorAction Stop).Source
$programFiles32 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
$vswhere = Join-Path $programFiles32 'Microsoft Visual Studio\Installer\vswhere.exe'
$components = @('Microsoft.Component.MSBuild', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64')
if (-not $CompilerDirectory) {
    $components += 'Microsoft.VisualStudio.Component.VC.ATLMFC'
}
$vs = & $vswhere -latest -products '*' -version '[17.0,18.0)' -requires @components -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $vs) {
    throw 'Visual Studio 2022 with MSBuild, v143 C++, and x64 MFC is required.'
}
$msbuild = Join-Path $vs 'MSBuild\Current\Bin\amd64\MSBuild.exe'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'

$kitInclude = Join-Path $programFiles32 'Windows Kits\10\Include'
$sdk = Get-ChildItem -LiteralPath $kitInclude -Directory |
    Where-Object { $_.Name -match '^10\.0\.\d+\.\d+$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'um\Windows.h')) } |
    Sort-Object { [version] $_.Name } -Descending |
    Select-Object -First 1
if (-not $sdk) {
    throw 'A Windows 10 or 11 SDK is required.'
}

$working = Join-Path (Join-Path $root '.build') ([Guid]::NewGuid().ToString('N'))
$source = Join-Path $working 'upstream'
$app = Join-Path $working 'app'
$assets = Join-Path $working 'assets'
$release = Join-Path $working 'release'
New-Item -ItemType Directory -Path $source, $app, $assets, $release | Out-Null

if (-not $StandardZip) {
    $StandardZip = Join-Path $working 'CrystalDiskInfo9_9_4.zip'
    Invoke-WebRequest -UseBasicParsing -Uri $download -OutFile $StandardZip
}
$StandardZip = (Get-Item -LiteralPath $StandardZip).FullName
if ((Get-FileHash -LiteralPath $StandardZip -Algorithm SHA256).Hash -ne $archiveHash) {
    throw 'The ZIP checksum does not match the official CrystalDiskInfo 9.9.4 Standard Edition archive.'
}

$patch = Join-Path $root 'patches\crystaldiskinfo-9.9.4.patch'
Invoke-Checked $git @('-C', $source, 'init', '-q')
Invoke-Checked $git @('-C', $source, 'config', 'core.autocrlf', 'false')
Invoke-Checked $git @('-C', $source, 'fetch', '--depth=1', $upstream, $revision)
Invoke-Checked $git @('-C', $source, 'checkout', '--detach', 'FETCH_HEAD')
Invoke-Checked $git @('-C', $source, 'apply', '--check', $patch)
Invoke-Checked $git @('-C', $source, 'apply', $patch)
Copy-Item -LiteralPath (Join-Path $root 'src\SanDisk55DD.h') -Destination $source

$buildArgs = @(
    (Join-Path $source 'DiskInfo.vcxproj')
    '/p:Configuration=Release'
    '/p:Platform=x64'
    '/p:PlatformToolset=v143'
    "/p:WindowsTargetPlatformVersion=$($sdk.Name)"
    "/p:OutDir=$app\"
    "/p:IntDir=$working\obj\"
    '/nologo'
    '/verbosity:minimal'
    '/m'
)
if ($CompilerDirectory) {
    $compiler = (Get-Item -LiteralPath $CompilerDirectory).FullName
    $mfc = Join-Path $compiler 'atlmfc\lib\x64\mfcs140u.lib'
    if (-not (Test-Path -LiteralPath $mfc -PathType Leaf)) {
        throw 'The supplied compiler directory is missing the x64 Unicode MFC library.'
    }
    $buildArgs += "/p:VCToolsInstallDir=$compiler\", "/p:MFC_KeyFile=$mfc"
}
Invoke-Checked $msbuild $buildArgs
if (-not (Test-Path -LiteralPath (Join-Path $app 'DiskInfo64.exe') -PathType Leaf)) {
    throw 'MSBuild did not produce DiskInfo64.exe.'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
[IO.Compression.ZipFile]::ExtractToDirectory($StandardZip, $assets)
foreach ($directory in 'CdiResource', 'License') {
    Copy-Item -LiteralPath (Join-Path $assets $directory) -Destination $app -Recurse
}
foreach ($document in 'LICENSE.txt', 'NOTICE.md', 'README.md') {
    Copy-Item -LiteralPath (Join-Path $root $document) -Destination $app
}
Set-Content -LiteralPath (Join-Path $app 'VERSION.txt') -Value $Version -Encoding Ascii

$portable = Join-Path $release "CrystalDiskInfo-SanDisk-$Version-windows-x64.zip"
$setup = Join-Path $release "CrystalDiskInfo-SanDisk-$Version-Setup-x64.exe"
$package = [IO.Compression.ZipFile]::Open($portable, [IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem -LiteralPath $app -Recurse -File | Sort-Object FullName | ForEach-Object {
        $name = $_.FullName.Substring($app.Length + 1).Replace('\', '/')
        [void] [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($package, $_.FullName, $name)
    }
} finally {
    $package.Dispose()
}
Invoke-Checked $csc @(
    '/nologo'
    '/target:winexe'
    '/platform:x64'
    '/optimize+'
    '/reference:System.Windows.Forms.dll'
    '/reference:System.IO.Compression.dll'
    '/reference:Microsoft.CSharp.dll'
    "/resource:$portable,CrystalDiskInfo.Payload.zip"
    "/out:$setup"
    (Join-Path $root 'installer\Setup.cs')
)
$hashes = Get-Item -LiteralPath $portable, $setup | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $($_.Name)"
}
Set-Content -LiteralPath (Join-Path $release 'SHA256SUMS.txt') -Value $hashes -Encoding Ascii

New-Item -ItemType Directory -Path $destination | Out-Null
Get-ChildItem -LiteralPath $release -File | Copy-Item -Destination $destination
Get-ChildItem -LiteralPath $destination -File
