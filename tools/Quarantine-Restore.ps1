[CmdletBinding()]
param(
    [ValidateSet('Isolate','Restore')]
    [string]$Action = 'Restore',
    [string]$QuarantineDirectory = (Join-Path ([Environment]::GetFolderPath('Desktop')) '待隔离区')
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$manifestPath = Join-Path $root 'manifest.json'
$desktop = [Environment]::GetFolderPath('Desktop')
$programs = Join-Path $env:LOCALAPPDATA 'Programs'
$shell = New-Object -ComObject WScript.Shell

function Assert-RegularItem([string]$path) {
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Reparse item refused: $path"
    }
    return $item
}

function Resolve-VaultPath([string]$relative, [string]$expectedName) {
    if ([IO.Path]::IsPathRooted($relative) -or $relative.Split([IO.Path]::DirectorySeparatorChar) -contains '..') {
        throw 'Invalid vault-relative path.'
    }
    $path = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Vault path escapes the quarantine root.'
    }
    if ($expectedName -and (Split-Path -Leaf $path) -cne $expectedName) {
        throw 'Manifest basename changed unexpectedly.'
    }
    return $path
}

function Find-OriginalLink([string]$name, [string]$target) {
    $folders = @(
        $desktop,
        [Environment]::GetFolderPath('Programs'),
        (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'),
        [Environment]::GetFolderPath('CommonPrograms'),
        [Environment]::GetFolderPath('CommonDesktopDirectory')
    ) | Select-Object -Unique
    $links = [Collections.Generic.List[object]]::new()
    foreach ($folder in $folders) {
        if (-not (Test-Path -LiteralPath $folder)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -Recurse -File)) {
            if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked shortcut refused: $($file.FullName)" }
            $link = $shell.CreateShortcut($file.FullName)
            if ($link.TargetPath -ieq $target) { $links.Add($file) }
        }
    }
    if ($links.Count -ne 1 -or $links[0].Name -cne $name) {
        throw "Expected exactly one original shortcut named $name, found $($links.Count)."
    }
    return $links[0]
}

if ($Action -eq 'Isolate') {
    if (Test-Path -LiteralPath $manifestPath) {
        $previous = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($previous.schema -eq 1 -and $previous.enabled) {
            Write-Output 'Already isolated. Use Restore to return the archived entries.'
            return
        }
        $previousArchived = @($previous.entries | Where-Object { $_.kind -eq 'directory' -and -not (Test-Path -LiteralPath $_.original) })
        $previousOriginals = @($previous.entries | Where-Object { $_.kind -eq 'directory' -and (Test-Path -LiteralPath $_.original) })
        if ($previousArchived.Count -eq 3 -and $previousOriginals.Count -eq 0) {
            $previous.enabled = $true
            foreach ($entry in $previous.entries) { $entry.enabled = $true }
            [IO.File]::WriteAllText($manifestPath, ($previous | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
            Write-Output 'Archived installations confirmed isolated. Restore manifest reactivated.'
            return
        }
    }
    $oldPage = Join-Path $programs 'CodexPage-Dragon'
    $directories = @(
        [pscustomobject]@{ Name = 'CodexDragonPublic'; Path = (Join-Path $programs 'CodexDragonPublic') },
        [pscustomobject]@{ Name = 'CodexDragon-Animation'; Path = (Join-Path $programs 'CodexDragon-Animation') },
        [pscustomobject]@{ Name = 'CodexPage-Dragon'; Path = $oldPage }
    )
    $entries = [Collections.Generic.List[object]]::new()
    $links = [Collections.Generic.List[object]]::new()
    $taskDefinitions = @()
    $oldProcesses = @()
    $oldNamePattern = 'CodexDragonPublic|CodexDragon-Animation|CodexPage-Dragon'
    foreach ($directory in $directories) {
        $item = Assert-RegularItem $directory.Path
        if (-not $item.PSIsContainer) { throw "Expected installation directory: $($directory.Path)" }
    }
    foreach ($item in @(
        [pscustomobject]@{ Name = 'Codex Dragon.lnk'; Target = (Join-Path $programs 'CodexDragonPublic\Launch.exe') },
        [pscustomobject]@{ Name = 'Codex Dragon + CodexPage.lnk'; Target = (Join-Path $programs 'CodexDragon-Animation\Launch.exe') },
        [pscustomobject]@{ Name = 'CodexPage.lnk'; Target = (Join-Path $oldPage 'CodexSkinManager.exe') }
    )) {
        $link = Find-OriginalLink $item.Name $item.Target
        $links.Add([pscustomobject]@{ Name = $item.Name; Target = $item.Target; Original = $link.FullName; Entry = $link.FullName })
    }
    $oldRoot = $oldPage + '\'
    $oldProcesses = @(Get-CimInstance Win32_Process | Where-Object {
        ($_.Name -in @('CodexDynamicSkinLauncher.exe', 'CodexSkinManager.exe', 'node.exe') -and
            $_.ExecutablePath -and $_.ExecutablePath.StartsWith($oldRoot, [StringComparison]::OrdinalIgnoreCase)) -or
        ($_.Name -eq 'powershell.exe' -and $_.ProcessId -ne $PID -and $_.CommandLine -like "*$oldRoot*multi-instance.ps1*")
    })
    $taskModule = Join-Path $oldPage 'engine/scripts/background-task.ps1'
    . $taskModule
    $spec = Get-DreamSkinBackgroundTaskSpec $oldPage
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $task = $null
    try { $task = $service.GetFolder('\').GetTask($spec.Name) } catch { if ($_.Exception.HResult -ne -2147024894) { throw } }
    if ($task) {
        if (-not (Test-DreamSkinOwnedBackgroundTask $task $spec)) { throw 'The old monitor task is not owned by the expected installation.' }
        $taskDefinitions = @(@{ Task = $task; Spec = $spec })
    }
    if ($taskDefinitions.Count) {
        $savedTaskPath = Join-Path $root 'tasks'
        [IO.Directory]::CreateDirectory($savedTaskPath) | Out-Null
        [IO.File]::WriteAllText((Join-Path $savedTaskPath ($spec.Name + '.xml')), $taskDefinitions[0].Task.Definition.XmlText, [Text.UTF8Encoding]::new($false))
    }
    foreach ($directory in $directories) {
        $entries.Add([pscustomobject]@{
            kind = 'directory'; name = $directory.Name; original = $directory.Path;
            stored = 'packages/' + $directory.Name; enabled = $true
        })
    }
    foreach ($link in $links) {
        $entries.Add([pscustomobject]@{
            kind = 'shortcut'; name = $link.Name; original = $link.Original;
            stored = 'shortcuts/' + $link.Name; enabled = $true; target = $link.Target
        })
    }
    foreach ($definition in $taskDefinitions) {
        $entries.Add([pscustomobject]@{
            kind = 'task'; name = $definition.Spec.Name; original = $definition.Spec.Name;
            stored = 'tasks/' + $definition.Spec.Name + '.xml'; enabled = $true
        })
    }
    foreach ($process in $oldProcesses) {
        $entries.Add([pscustomobject]@{
            kind = 'process'; name = $process.Name; original = [string]$process.ProcessId;
            stored = 'processes/' + $process.ProcessId + '.json'; enabled = $true;
            commandLine = $process.CommandLine; creationTime = $process.CreationDate.ToUniversalTime().ToString('o')
        })
    }
    [IO.Directory]::CreateDirectory((Join-Path $root 'packages')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $root 'shortcuts')) | Out-Null
    if ($taskDefinitions.Count) { [IO.Directory]::CreateDirectory((Join-Path $root 'tasks')) | Out-Null }
    if ($oldProcesses.Count) { [IO.Directory]::CreateDirectory((Join-Path $root 'processes')) | Out-Null }
    foreach ($definition in $taskDefinitions) {
        [IO.File]::WriteAllText((Resolve-VaultPath ('tasks/' + $definition.Spec.Name + '.xml') ''), $definition.Task.Definition.XmlText, [Text.UTF8Encoding]::new($false))
        Disable-DreamSkinBackgroundTask $definition.Spec.Root
    }
    foreach ($process in $oldProcesses) {
        $current = Get-CimInstance Win32_Process -Filter "ProcessId = $($process.ProcessId)"
        if ($current -and $current.CommandLine -ceq $process.CommandLine -and $current.CreationDate -eq $process.CreationDate) {
            Stop-Process -Id $process.ProcessId -Force
        }
        $record = [pscustomobject]@{ pid = $process.ProcessId; commandLine = $process.CommandLine; creationTime = $process.CreationDate.ToUniversalTime().ToString('o') }
        [IO.File]::WriteAllText((Resolve-VaultPath ('processes/' + $process.ProcessId + '.json') ''), ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    }
    foreach ($entry in $entries) {
        $held = Resolve-VaultPath $entry.stored $(if ($entry.kind -in @('directory','shortcut')) { $entry.name } else { '' })
        if ($entry.kind -eq 'shortcut') {
            $existing = Get-Item -LiteralPath $entry.original -Force -ErrorAction Stop
            $heldParent = Split-Path -Parent $held
            [IO.Directory]::CreateDirectory($heldParent) | Out-Null
            $archiveName = [guid]::NewGuid().ToString('N') + '.lnk'
            $archivePath = Join-Path $heldParent $archiveName
            Move-Item -LiteralPath $existing.FullName -Destination $archivePath
            if (Test-Path -LiteralPath $held) { Move-Item -LiteralPath $held -Destination $entry.original }
            Move-Item -LiteralPath $archivePath -Destination $held
            continue
        }
        if ($entry.kind -eq 'task') { continue }
        if ($entry.kind -ne 'process' -and (Test-Path -LiteralPath $held)) { throw "Vault destination already exists: $held" }
        if ($entry.kind -eq 'process') {
            [IO.File]::WriteAllText($held, $entry.original, [Text.UTF8Encoding]::new($false))
            continue
        }
        Move-Item -LiteralPath $entry.original -Destination $held
    }
    [IO.File]::WriteAllText($manifestPath, (@{ schema = 1; isolatedAt = [datetime]::UtcNow.ToString('o'); entries = $entries } | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    foreach ($entry in $entries) {
        if ($entry.kind -in @('directory','shortcut')) {
            if (Test-Path -LiteralPath $entry.original) { throw "Old entry still present: $($entry.original)" }
            Assert-RegularItem (Resolve-VaultPath $entry.stored '') | Out-Null
        }
    }
    Write-Output "Isolated the modified 1/2 plugins, their shortcuts and old monitor."
    Write-Output "Restore: powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$root\restore.ps1`" -Action Restore"
} else {
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'Isolation manifest is missing.' }
    $manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($manifest.schema -ne 1) { throw 'Unknown isolation manifest schema.' }
    $records = [Collections.Generic.List[object]]::new()
    $taskModule = $null
    foreach ($entry in $manifest.entries) {
        if (-not $entry.enabled) { continue }
        $held = Resolve-VaultPath $entry.stored $(if ($entry.kind -in @('directory','shortcut')) { $entry.name } else { '' })
        if ($entry.kind -in @('directory','shortcut')) {
            Assert-RegularItem $held | Out-Null
            if ($entry.kind -eq 'shortcut') {
                $expected = Find-OriginalLink (Split-Path -Leaf $entry.original) $entry.target
                if ($expected.FullName -cne $held) { throw 'Shortcut target or path mismatch.' }
            }
            if (Test-Path -LiteralPath $entry.original) { throw "Restore destination already exists: $($entry.original)" }
        }
        if ($entry.kind -eq 'task') {
            if (-not (Test-Path -LiteralPath $held)) { throw "Saved task definition missing: $held" }
            $taskName = $entry.name
            $currentTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            if ($currentTask) {
                if ($currentTask.Actions.Execute -cne (Join-Path $programs 'CodexPage-Dragon\engine\launcher\CodexDynamicSkinLauncher.exe')) {
                    throw "An unrelated task already exists: $taskName"
                }
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            }
        }
        $records.Add($entry)
    }
    $restored = [Collections.Generic.List[string]]::new()
    try {
        foreach ($entry in $records) {
            $held = Resolve-VaultPath $entry.stored ''
            if ($entry.kind -in @('directory','shortcut')) {
                Move-Item -LiteralPath $held -Destination $entry.original
                $restored.Add($entry.name)
            } elseif ($entry.kind -eq 'task') {
                $taskXml = [IO.File]::ReadAllText($held, [Text.Encoding]::UTF8)
                $saved = New-Object Xml.XmlDocument
                $saved.PreserveWhitespace = $true
                $saved.LoadXml($taskXml)
                $ns = New-Object Xml.XmlNamespaceManager $saved.NameTable
                $ns.AddNamespace('t', 'http://schemas.microsoft.com/windows/2004/02/mit/task')
                $expectedSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
                $expectedExe = Join-Path $programs 'CodexPage-Dragon\engine\launcher\CodexDynamicSkinLauncher.exe'
                $source = $saved.SelectSingleNode('/t:Task/t:RegistrationInfo/t:Source', $ns).InnerText
                $principal = $saved.SelectSingleNode('/t:Task/t:Principals/t:Principal/t:UserId', $ns).InnerText
                $command = $saved.SelectSingleNode('/t:Task/t:Actions/t:Exec/t:Command', $ns).InnerText
                if ($source -cne 'CodexPage/background-monitor/1' -or $principal -cne $expectedSid -or $command -cne $expectedExe) {
                    throw 'Saved task identity does not match the old 2 plugin.'
                }
                $service = New-Object -ComObject 'Schedule.Service'; $service.Connect()
                $service.GetFolder('\').RegisterTask($entry.name, $taskXml, 2, $null, $null, 3) | Out-Null
                $registered = Get-ScheduledTask -TaskName $entry.name -ErrorAction Stop
                if (-not $registered.Settings.Enabled -or $registered.Actions.Execute -cne $expectedExe) {
                    throw 'The restored monitor task is missing, disabled or has a different executable.'
                }
                $restored.Add($entry.name)
            } else {
                Remove-Item -LiteralPath $held -Force
            }
        }
        $manifest.enabled = $false
        foreach ($entry in $manifest.entries) { $entry.enabled = $false }
        $manifest | Add-Member -NotePropertyName restoredAt -NotePropertyValue ([datetime]::UtcNow.ToString('o')) -Force
        [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
        Write-Output "Restored: $($restored -join ', ')"
    } catch {
        $failed = $_
        foreach ($entry in $records) {
            if ($entry.kind -in @('directory','shortcut') -and (Test-Path -LiteralPath $entry.original)) {
                $held = Resolve-VaultPath $entry.stored ''
                if (-not (Test-Path -LiteralPath $held)) { Move-Item -LiteralPath $entry.original -Destination $held }
            }
        }
        throw $failed
    }
}
