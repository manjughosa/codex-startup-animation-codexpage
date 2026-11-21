param([string]$Root = (Join-Path $env:LOCALAPPDATA ('Programs\3' + [char]0x53f7 + [char]0x63d2 + [char]0x4ef6)))
$ErrorActionPreference = 'Stop'
$skin = Join-Path $Root 'CodexPage'
$programs = Split-Path -Parent $Root
. (Join-Path $skin 'engine/scripts/common-windows.ps1')
function Read-State {
    [IO.File]::ReadAllText((Join-Path $skin 'state.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
}
$codex = Get-DreamSkinCodexInstall
$before = Read-State
if (@(Get-DreamSkinCodexProcesses -Codex $codex).Count) {
$identity = Get-DreamSkinVerifiedCdpIdentity -Port $before.port -Codex $codex
if (-not $identity -or $identity.BrowserId -cne $before.browserId) { throw 'Session ownership changed' }
$owner = @(Get-NetTCPConnection -State Listen -LocalPort $before.port | Where-Object LocalAddress -eq '127.0.0.1')
if ($owner.Count -ne 1) { throw 'Expected a unique client' }
$client = Get-Process -Id $owner[0].OwningProcess
if ($client.SessionId -ne (Get-Process -Id $PID).SessionId -or $client.Path -ine $codex.Executable) { throw 'Unexpected client identity' }
if ($client.MainWindowHandle -eq 0) {
    $null = Start-DreamSkinCodex -Codex $codex -Arguments @('--remote-debugging-address=127.0.0.1', "--remote-debugging-port=$($before.port)", "--user-data-dir=$($before.profilePath)")
}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Plugin3TestWindow {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
}
'@
function Test-OwnedForeground {
    $foregroundId = [uint32]0
    $null = [Plugin3TestWindow]::GetWindowThreadProcessId([Plugin3TestWindow]::GetForegroundWindow(), [ref]$foregroundId)
    return $foregroundId -eq $client.Id
}
$ui = New-Object -ComObject WScript.Shell
$deadline = (Get-Date).AddSeconds(14)
do {
    $client.Refresh()
    if ($client.MainWindowHandle -ne 0) {
        if (Test-OwnedForeground) { break }
        $null = $ui.AppActivate($client.Id)
    }
    Start-Sleep -Milliseconds 250
} while ((Get-Date) -lt $deadline)
if ($client.MainWindowHandle -eq 0 -or -not (Test-OwnedForeground)) { throw 'Owned Codex window is not in the foreground' }
$ui.SendKeys('^q')
$deadline = (Get-Date).AddSeconds(14)
while (@(Get-DreamSkinCodexProcesses -Codex $codex).Count -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
if (@(Get-DreamSkinCodexProcesses -Codex $codex).Count) { throw 'Codex did not exit normally before isolation' }
}
$entries = [Collections.Generic.List[object]]::new()
$tasks = [Collections.Generic.List[object]]::new()
$restoreErrors = [Collections.Generic.List[string]]::new()
$tag = [guid]::NewGuid().ToString('N')
try {
    $oldExe = Join-Path $programs 'CodexPage-Dragon\engine\launcher\CodexDynamicSkinLauncher.exe'
    foreach ($task in @(Get-ScheduledTask -TaskName 'CodexPage-Monitor-*' -ErrorAction SilentlyContinue | Where-Object { $_.Settings.Enabled -and $_.Actions.Execute -eq $oldExe })) {
        Disable-ScheduledTask -InputObject $task | Out-Null
        $tasks.Add($task)
        if ($task.State -eq 'Running') { Stop-ScheduledTask -InputObject $task }
    }
    $paths = @('CodexDragonPublic\Launch.exe', 'CodexDragonPublic\Start-Codex-Dragon.exe', 'CodexDragonPublic\WallpaperHost.exe',
               'CodexDragon-Animation\Launch.exe', 'CodexDragon-Animation\Start-Codex-Dragon.exe',
               'CodexPage-Dragon\CodexSkinManager.exe', 'CodexPage-Dragon\engine\launcher\CodexDynamicSkinLauncher.exe',
               'CodexPage-Dragon\engine\scripts\launch-dream-skin.ps1', 'CodexPage-Dragon\engine\scripts\start-dream-skin.ps1',
               'CodexPage-Dragon\engine\scripts\injector.mjs', 'CodexPage-Dragon\engine\scripts\video-server.mjs')
    foreach ($relative in $paths) {
        $oldPath = Join-Path $programs $relative
        $name = Split-Path -Leaf $oldPath
        $heldName = "$name.isolated-$tag"
        Rename-Item -LiteralPath $oldPath -NewName $heldName
        $entries.Add([pscustomobject]@{ Name = $name; Old = $oldPath; Held = (Join-Path (Split-Path -Parent $oldPath) $heldName) })
        if (Test-Path -LiteralPath $oldPath) { throw "Original path still present: $relative" }
    }
    $oldRoot = Join-Path $programs 'CodexPage-Dragon'
    $oldScriptRoot = Join-Path $oldRoot 'engine\scripts'
    $oldRuntime = Join-Path $oldRoot 'engine\runtime\node\node.exe'
    $oldWorkers = @(Get-CimInstance Win32_Process | Where-Object {
        ($_.ExecutablePath -ieq $oldRuntime -and $_.CommandLine -match '(?i)(injector|video-server)\.mjs') -or
        ($_.Name -eq 'powershell.exe' -and $_.CommandLine -like "*$oldScriptRoot*multi-instance.ps1*")
    })
    foreach ($worker in $oldWorkers) {
        $current = Get-CimInstance Win32_Process -Filter "ProcessId = $($worker.ProcessId)"
        if ($current -and $current.CreationDate -eq $worker.CreationDate -and $current.CommandLine -ceq $worker.CommandLine) {
            Stop-Process -Id $worker.ProcessId
        }
    }
    Write-Output "Isolated: $($entries.Name -join ', ')"
    $started = [datetime]::UtcNow
    $launch = Start-Process -FilePath (Join-Path $Root 'Launch.exe') -WorkingDirectory $Root -PassThru
    if (-not $launch.WaitForExit(105000)) { throw 'Animation exceeded validation deadline' }
    if ($launch.ExitCode -ne 0) { throw "Launcher exit $($launch.ExitCode)" }
    $log = Join-Path $Root 'output/handoff-latest.log'
    $handoff = @(Select-String -LiteralPath $log -SimpleMatch 'Handoff complete; success=True' | Where-Object { $_.Line.Contains('replayExisting=False') -and [datetime]::Parse($_.Line.Split(' ')[0]).ToUniversalTime() -ge $started })
    if ($handoff.Count -ne 1) {
        $skipped = @(Select-String -LiteralPath $log -SimpleMatch 'animation-skip source=' | Where-Object { [datetime]::Parse($_.Line.Split(' ')[0]).ToUniversalTime() -ge $started })
        if ($skipped.Count -ne 1) { throw 'No successful cold handoff or explicit animation skip for this run' }
        Write-Output $skipped[0].Line
    } else { Write-Output $handoff[0].Line }
    $verifyPath = Join-Path $skin 'verify.log'
    $deadline = (Get-Date).AddSeconds(40)
    do {
        $after = Read-State
        $verification = Get-Item -LiteralPath $verifyPath -ErrorAction SilentlyContinue
        if ($verification -and $verification.LastWriteTimeUtc -ge $started -and $after.browserId -cne $before.browserId) {
            $text = [IO.File]::ReadAllText($verifyPath, [Text.Encoding]::UTF8)
            if ($text -match '"playing"\s*:\s*true' -and $text -match '"pass"\s*:\s*true') { break }
        }
        if ((Get-Date) -ge $deadline) { throw 'No fresh wallpaper playing/pass result' }
        Start-Sleep -Milliseconds 300
    } while ($true)
    $newIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $after.port -Codex $codex
    if (-not $newIdentity -or $newIdentity.BrowserId -cne $after.browserId) { throw 'New renderer identity mismatch' }
    $media = [IO.File]::ReadAllText((Join-Path $skin 'video-theme.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($path in @($after.profilePath, $after.nodePath, $after.injectorPath, $after.videoScript, $media.filePath)) {
        if (-not $path.StartsWith($skin + '\', [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $path)) { throw "Dependency outside package or missing: $path" }
    }
    foreach ($entry in $entries) { if (Test-Path -LiteralPath $entry.Old) { throw 'Original path reappeared during test' } }
    Write-Output "Fresh packaged wallpaper verified playing on Codex $($after.codexVersion)."
    if ($handoff.Count -ne 1) { throw 'Independent startup and wallpaper passed, but the animation was skipped before the handoff' }
} finally {
    foreach ($entry in $entries) {
        try { Rename-Item -LiteralPath $entry.Held -NewName $entry.Name; Write-Output "Restored: $($entry.Name)" }
        catch { $restoreErrors.Add($_.Exception.Message) }
    }
    foreach ($task in $tasks) {
        try {
            Enable-ScheduledTask -InputObject $task | Out-Null
            if ($task.State -eq 'Running') { Start-ScheduledTask -InputObject $task }
            Write-Output 'Restored old monitor schedule'
        }
        catch { $restoreErrors.Add($_.Exception.Message) }
    }
    if ($restoreErrors.Count) { throw ($restoreErrors -join [Environment]::NewLine) }
}
