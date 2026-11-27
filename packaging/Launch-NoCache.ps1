param(
    [string]$GamePath = $env:GTA6_TEST_GAME_PATH,
    [string]$RuntimeSha256 = '238aa4cc95f2242a974b74a3f7f05d39b90c2b5b5b31ff5baaf4896bf9eadb0a',
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
try {
    $runtime = Join-Path $PSScriptRoot 'patched\kyty_emulator.exe'
    if (!(Test-Path -LiteralPath $runtime -PathType Leaf)) {
        throw 'Extract this update beside START-GTA6.cmd in the existing Test 01 folder.'
    }
    if ((Get-FileHash -LiteralPath $runtime -Algorithm SHA256).Hash -ne $RuntimeSha256) {
        throw 'The runtime differs from the verified Test 01 executable. Check the package location.'
    }
    $savedPath = Join-Path $PSScriptRoot 'game-path.txt'
    if (!$GamePath -and (Test-Path -LiteralPath $savedPath)) {
        $GamePath = [IO.File]::ReadAllText($savedPath).Trim()
    }
    if (!$GamePath -and !$NonInteractive) {
        $GamePath = Read-Host 'Existing GTA6 folder or exact eboot.bin path'
    }
    if (!$GamePath) { throw 'No game path was provided.' }
    $GamePath = $GamePath.Trim().Trim('"')
    $inputItem = Get-Item -LiteralPath $GamePath
    if ($inputItem.PSIsContainer) {
        $direct = Join-Path $inputItem.FullName 'eboot.bin'
        if (Test-Path -LiteralPath $direct -PathType Leaf) {
            $GamePath = $direct
        } else {
            Write-Host 'Looking for a nested eboot.bin in the selected folder...'
            $gameFiles = @(Get-ChildItem -LiteralPath $inputItem.FullName -Filter 'eboot.bin' -Recurse -File -ErrorAction SilentlyContinue)
            if ($gameFiles.Count -ne 1) {
                foreach ($item in $gameFiles) { Write-Host $item.FullName }
                throw "Found $($gameFiles.Count) eboot.bin files. Drag the exact GTA6 executable onto START-GTA6-NOCACHE.cmd."
            }
            $GamePath = $gameFiles[0].FullName
        }
    } else {
        $GamePath = $inputItem.FullName
    }
    $read = [IO.File]::Open($GamePath, [IO.FileMode]::Open, [IO.FileAccess]::Read,
                          ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        if ($read.ReadByte() -lt 0) { throw 'The selected game file is empty.' }
    } finally { $read.Dispose() }
    $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
    $logDir = Join-Path $PSScriptRoot 'logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $report = Join-Path $logDir ("nocache-baseline-$stamp.txt")
    $stdout = Join-Path $logDir ("nocache-baseline-$stamp-stdout.tmp")
    $stderr = Join-Path $logDir ("nocache-baseline-$stamp-stderr.tmp")
    $work = Join-Path $PSScriptRoot ("diagnostic-runs\$stamp")
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'patched\assets') -Destination (Join-Path $work 'assets') -Recurse
    $arguments = '--game "' + $GamePath + '" --printf-direction Console'
    $header = @(
        'GTA6 Test 01 - fresh baseline diagnostic launcher v2'
        'Shader-store preloading: disabled (no --shader-cache)'
        'Vulkan pipeline cache: fresh working directory; existing test caches retained'
        'Compatibility flags: none'
        "Runtime SHA256: $RuntimeSha256"
        "Game input: $GamePath"
        "Working directory: $work"
        "Arguments: $arguments"
        ''
    ) -join "`r`n"
    [IO.File]::WriteAllText($report, $header, $utf8)
    Write-Host "Starting a fresh baseline. Report: $report"
    Write-Host 'Close the game window if it hangs. The report opens after the process exits.'

    $process = Start-Process -FilePath $runtime -ArgumentList $arguments -WorkingDirectory $work `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -NoNewWindow
    $null = $process.Handle
    $modules = @{}
    do {
        try {
            $process.Refresh()
            foreach ($module in $process.Modules) {
                $base = [uint64]$module.BaseAddress.ToInt64()
                $key = '{0}:{1:X16}' -f $module.ModuleName, $base
                if (!$modules.ContainsKey($key)) {
                    $modules[$key] = [pscustomobject]@{
                        Name = $module.ModuleName; Base = $base
                        Size = [uint64]$module.ModuleMemorySize; Path = $module.FileName
                    }
                }
            }
        } catch {
            # A process may exit between reading HasExited and querying Modules.
        }
        if ($process.HasExited) { break }
        Start-Sleep -Milliseconds 500
    } while ($true)
    $process.WaitForExit()
    $exitCode = $process.ExitCode

    $output = [IO.File]::Open($report, [IO.FileMode]::Append, [IO.FileAccess]::Write)
    try {
        foreach ($file in @($stdout, $stderr)) {
            if ((Test-Path -LiteralPath $file) -and (Get-Item -LiteralPath $file).Length -gt 0) {
                $stream = [IO.File]::OpenRead($file)
                try { $stream.CopyTo($output) } finally { $stream.Dispose() }
            }
        }
    } finally { $output.Dispose() }

    $footer = New-Object System.Text.StringBuilder
    $null = $footer.AppendLine("`r`n--- Diagnostic launcher result ---")
    $null = $footer.AppendLine("Process exit code: $exitCode")
    $null = $footer.AppendLine('Loaded module snapshots (base, size, name, path):')
    foreach ($module in ($modules.Values | Sort-Object Base)) {
        $null = $footer.AppendLine(('0x{0:X16} 0x{1:X8} {2} {3}' -f $module.Base, $module.Size, $module.Name, $module.Path))
    }
    $faultPc = $null
    foreach ($line in [IO.File]::ReadLines($report)) {
        if ($line -match 'Unhandled host exception:.*pc=0x([0-9a-fA-F]+)') {
            $faultPc = [Convert]::ToUInt64($Matches[1], 16)
        }
    }
    if ($null -ne $faultPc) {
        $mapped = @($modules.Values | Where-Object { $faultPc -ge $_.Base -and ($faultPc - $_.Base) -lt $_.Size })
        if ($mapped.Count -eq 0) {
            $null = $footer.AppendLine('Fault PC was not in a captured module range; it may be guest/JIT code or an uncaptured module.')
        } else {
            foreach ($module in $mapped) {
                $null = $footer.AppendLine(('Fault PC module candidate: {0}+0x{1:X} ({2})' -f $module.Name, ($faultPc - $module.Base), $module.Path))
            }
        }
    }
    [IO.File]::AppendAllText($report, $footer.ToString(), $utf8)
    Remove-Item -LiteralPath $stdout, $stderr
    Write-Host "Process exit code: $exitCode"
    Write-Host "Send this report: $report"
    if (!$NonInteractive) { Start-Process notepad.exe -ArgumentList ('"' + $report + '"') }
    exit $exitCode
} catch {
    Write-Host ('LAUNCH ERROR: ' + $_.Exception.Message)
    Write-Host 'Any partial stdout/stderr logs remain in the logs folder.'
    exit 1
}
