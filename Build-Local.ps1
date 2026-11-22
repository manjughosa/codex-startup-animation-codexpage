[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Destination,
    [string]$UpstreamDirectory = (Join-Path $env:TEMP 'CodexDragon-R16'),
    [switch]$FetchNode
)

$ErrorActionPreference = 'Stop'
$local = Join-Path $PSScriptRoot '.local'
$inputs = Join-Path $local 'inputs.json'
$codexPage = Join-Path $PSScriptRoot 'third_party/CodexPage'
if (-not (Test-Path -LiteralPath $inputs -PathType Leaf)) {
    & (Join-Path $PSScriptRoot 'tools/Prepare-Inputs.ps1') -UpstreamDirectory $UpstreamDirectory -FetchNode:$FetchNode
}
$current = Get-Content -LiteralPath $inputs -Raw -Encoding UTF8 | ConvertFrom-Json
if ($current.schema -ne 1 -or -not $current.ready) { throw 'The input preparation did not complete.' }
$r16 = Join-Path $PSScriptRoot 'third_party/R16'
$media = Join-Path $local 'R16-media'
$videos = Join-Path $local 'DragonVideos'
$root = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
& {
    . (Join-Path $r16 'packaging/PackageTools.ps1')
    Assert-SupportedPlatform
}
if (Test-Path -LiteralPath $root) { throw 'Choose a new destination. Existing installations are preserved.' }

$stage = Join-Path ([IO.Path]::GetTempPath()) ('CodexPlugin3-' + [guid]::NewGuid().ToString('N'))
try {
    & (Join-Path $r16 'Build.ps1') -MediaRoot $media -OutputDirectory $stage -SkipZip
    $packageVersion = (Get-Content -LiteralPath (Join-Path $stage 'release-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version
    if ($packageVersion -cne '34.4-reliability-r16-test') { throw 'The integration input no longer matches R16.' }
    $pageVersion = (Get-Content -LiteralPath (Join-Path $codexPage 'VERSION') -Raw -Encoding UTF8).Trim()
    if ($pageVersion -cnotmatch '^\d+\.\d+\.\d+$') { throw 'The bundled CodexPage version is invalid.' }
    $integrationVersion = 'R16' + [char]0x2014 + $pageVersion
    [IO.File]::WriteAllText((Join-Path $stage 'VERSION'), $integrationVersion + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $stage 'package-version.json'), ([ordered]@{
        integration = $integrationVersion
        startupAnimation = 'R16'
        startupAnimationUpstream = '34.4-reliability-r16-test'
        codexPage = $pageVersion
    } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    $skin = Join-Path $root 'CodexPage'
    & (Join-Path $codexPage 'scripts/install.ps1') -InstallRoot $skin -SkipShortcuts -SkipBackgroundTask
    . (Join-Path $skin 'scripts/media.ps1')
    . (Join-Path $skin 'scripts/wallpaper-library.ps1')
    Initialize-DynamicMedia $skin
    $ambient = Import-DynamicWallpaper (Join-Path $videos 'Dragon Ambient.mp4') Video $skin
    $null = Import-DynamicWallpaper (Join-Path $videos 'Dragon Particles.mp4') Video $skin
    $null = Use-DynamicWallpaper $skin $ambient.Item.Id {}
    foreach ($item in Get-ChildItem -LiteralPath $stage) {
        Move-Item -LiteralPath $item.FullName -Destination $root
    }
    & {
        . (Join-Path $r16 'packaging/PackageTools.ps1')
        Test-PackageFiles $root (Read-PackageManifest $root)
    }
    $check = Start-Process -FilePath (Join-Path $root 'Launch.exe') -ArgumentList '--check' -Wait -PassThru
    if ($check.ExitCode -ne 0) { throw "Launcher check exited with code $($check.ExitCode)." }
    Write-Output "Verified local build: $root"
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
