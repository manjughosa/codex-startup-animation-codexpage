[CmdletBinding()]
param(
    [string]$UpstreamDirectory = (Join-Path $env:TEMP 'CodexDragon-R16'),
    [switch]$FetchNode
)

$ErrorActionPreference = 'Stop'
$stage = Join-Path (Split-Path -Parent $PSScriptRoot) '.local'
$r16 = Join-Path (Split-Path -Parent $PSScriptRoot) 'third_party/R16'
$media = Join-Path $stage 'R16-media'
$upstream = [IO.Path]::GetFullPath($UpstreamDirectory).TrimEnd('\')
if (Test-Path -LiteralPath (Join-Path $stage 'inputs.json') -PathType Leaf) {
    $existing = Get-Content -LiteralPath (Join-Path $stage 'inputs.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($existing.schema -eq 1 -and $existing.ready) {
        Write-Output 'Verified local inputs already exist; reusing them.'
        return
    }
}
$item = Get-Item -LiteralPath $upstream -Force -ErrorAction Stop
if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'The upstream directory must be a regular local directory.'
}
$manifestPath = Join-Path $upstream 'release-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Expected the fully extracted official R16 package at $upstream."
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.version -cne '34.4-reliability-r16-test' -or $manifest.product -cne 'CodexDragonPublic') {
    throw 'The supplied package is not the expected R16 release.'
}

if (Test-Path -LiteralPath $stage) {
    throw 'Existing input directory has no completion marker. Move it aside or use a fresh clone before rebuilding.'
}
[IO.Directory]::CreateDirectory($stage) | Out-Null
function Assert-LocalDirectory([string]$path) {
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Expected a regular directory: $path" }
}

foreach ($name in @('assets', 'output')) {
    $source = Join-Path $upstream $name
    Assert-LocalDirectory $source
    Copy-Item -LiteralPath $source -Destination (Join-Path $media $name) -Recurse
}
$videos = Join-Path $stage 'DragonVideos'
[IO.Directory]::CreateDirectory($videos) | Out-Null
$ambient = Join-Path $media 'output/versions/ai-refined-v4/dragon-wallpaper-ambient-2k-144fps.mp4'
$particles = Join-Path $media 'output/versions/particle-v33/dragon-wallpaper-particles-1440p48.mp4'
& ffmpeg.exe -nostdin -hide_banner -loglevel error -n -i $ambient -an -vf 'fps=60,scale=1920:1080:flags=lanczos' -c:v libx264 -preset veryfast -crf 16 -pix_fmt yuv420p -movflags +faststart (Join-Path $videos 'Dragon Ambient.mp4')
if ($LASTEXITCODE -ne 0) { throw 'Ambient video conversion failed.' }
& ffmpeg.exe -nostdin -hide_banner -loglevel error -n -i $particles -an -vf 'scale=1920:1080:flags=lanczos' -c:v libx264 -preset veryfast -crf 16 -pix_fmt yuv420p -movflags +faststart (Join-Path $videos 'Dragon Particles.mp4')
if ($LASTEXITCODE -ne 0) { throw 'Particle video conversion failed.' }
$sha = [Security.Cryptography.SHA256]::Create()
function Get-Hash([string]$path) {
    $stream = [IO.File]::OpenRead($path)
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
    finally { $stream.Dispose() }
}
foreach ($record in $manifest.files) {
    $relative = [string]$record.path
    if ($relative -notmatch '^(assets|output)/') { continue }
    $expected = Join-Path $media $relative
    if (-not (Test-Path -LiteralPath $expected -PathType Leaf) -or
        (Get-Item -LiteralPath $expected).Length -ne [long]$record.bytes -or
        (Get-Hash $expected) -cne ([string]$record.sha256).ToLowerInvariant()) {
        throw "Media verification failed: $relative"
    }
}

$upstreamSource = Join-Path $upstream 'source'
Assert-LocalDirectory $upstreamSource
$baselineManifest = Get-Content -LiteralPath (Join-Path $upstreamSource 'media-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($baselineManifest.schemaVersion -ne 1) { throw 'Unexpected R16 media manifest.' }
foreach ($record in $baselineManifest.files) {
    $path = Join-Path $media ([string]$record.path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Hash $path) -cne ([string]$record.sha256).ToLowerInvariant()) {
        throw "R16 media does not match the upstream source manifest: $($record.path)"
    }
}
$baseline = Get-Content -LiteralPath (Join-Path $upstreamSource 'media-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$currentManifest = Get-Content -LiteralPath (Join-Path $r16 'media-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (($baseline | ConvertTo-Json -Depth 8 -Compress) -cne ($currentManifest | ConvertTo-Json -Depth 8 -Compress)) {
    throw 'The integration input manifest differs from the supplied R16 package.'
}

if ($FetchNode) {
    $runtime = Join-Path $stage 'CodexPage/engine/runtime/node'
    $pin = Get-Content -LiteralPath (Join-Path $stage 'CodexPage/scripts/node-runtime.json') -Raw | ConvertFrom-Json
    $archive = Join-Path $stage $pin.archive
    $nodeRoot = Join-Path $stage 'node-download'
    [IO.Directory]::CreateDirectory($runtime) | Out-Null
    try {
        Invoke-WebRequest -Uri $pin.url -OutFile $archive -UseBasicParsing
        if ((Get-Hash $archive) -cne ([string]$pin.sha256).ToLowerInvariant()) { throw 'Node archive SHA-256 mismatch.' }
        Expand-Archive -LiteralPath $archive -DestinationPath $nodeRoot
        Copy-Item -LiteralPath (Join-Path $nodeRoot $pin.nodeEntry) -Destination (Join-Path $runtime 'node.exe')
        Copy-Item -LiteralPath (Join-Path $nodeRoot $pin.licenseEntry) -Destination (Join-Path $runtime 'LICENSE')
        if ((Get-Hash (Join-Path $runtime 'node.exe')) -cne ([string]$pin.nodeSha256).ToLowerInvariant()) { throw 'Node executable SHA-256 mismatch.' }
        $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $runtime 'node.exe')
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=OpenJS Foundation(?:,|$)') {
            throw 'Node executable signature validation failed.'
        }
    } finally {
        Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $nodeRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
$sha.Dispose()
$completed = [ordered]@{ schema = 1; ready = $true; upstreamVersion = $manifest.version; preparedAt = [datetime]::UtcNow.ToString('o') }
[IO.File]::WriteAllText((Join-Path $stage 'inputs.json'), ($completed | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Output "Verified R16 inputs in $stage. Node installed: $FetchNode"
