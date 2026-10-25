param(
    [ValidatePattern('^[A-Za-z]{2}$')][string]$Region = 'US',
    [string]$AppPath,
    [switch]$ShowProUI,
    [switch]$NoDiagnostics,
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$env:PYTHONIOENCODING = 'utf-8'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$portablePython = Join-Path $workspaceRoot 'runtime\python\python.exe'
$pythonPath = $portablePython
$scriptPath = if ($NoDiagnostics) {
    Join-Path $PSScriptRoot 'runtime\launch_capcut_minimal.py'
} else {
    Join-Path $PSScriptRoot 'runtime\observe_capcut.py'
}
$selectedAppPath = if ($AppPath) { [IO.Path]::GetFullPath($AppPath) }
elseif ($env:CAPCUT_APP_PATH) { $env:CAPCUT_APP_PATH }
else { Join-Path $env:LOCALAPPDATA 'CapCut\Apps\9.6.0.4097\CapCut.exe' }
$appPath = $selectedAppPath
$env:CAPCUT_APP_PATH = $appPath
$env:CAPCUT_REGION = $Region.ToUpperInvariant()
if (-not $NoDiagnostics -and $Region.ToUpperInvariant() -notin @('US','NL')) {
    throw 'Other regions are supported by the portable/minimal launcher only.'
}
$dependenciesPath = Join-Path $workspaceRoot 'local\runtime-dependencies\frida'
$diagnosticsPath = Join-Path $workspaceRoot 'local\diagnostics'

$requiredPaths = @($pythonPath, $scriptPath, $appPath, $dependenciesPath,
    (Join-Path $PSScriptRoot 'runtime\guard_capcut_region.js'))
$requiredPaths += if ($NoDiagnostics) {
    (Join-Path $PSScriptRoot 'runtime\show_capcut_pro_ui.js')
    (Join-Path $PSScriptRoot 'runtime\capcut_region_settings.py')
} else { (Join-Path $PSScriptRoot 'runtime\observe_capcut.js') }
foreach ($path in $requiredPaths) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Не найден необходимый файл или каталог: $path"
    }
}

$interfaceName = if ($ShowProUI) {'с показом Pro-интерфейса'} else {'с обычным интерфейсом'}
if ($NoDiagnostics -and -not $ShowProUI) {
    throw 'Режим без диагностики предназначен для запусков US Pro и NL Pro: нужен -ShowProUI.'
}
if ($CheckOnly) {
    if ($NoDiagnostics) {
        & $pythonPath -B $scriptPath --region $Region.ToLowerInvariant() --check-only
        if ($LASTEXITCODE -ne 0) { throw 'Проверка помощника не пройдена.' }
    }
    Write-Host "Проверка пройдена: CapCut 9.6.0.4097, регион $Region, $interfaceName."
    Write-Host 'Приложение не запускалось.'
    if ($NoDiagnostics) { Write-Host 'Диагностика и новые копии отключены.' }
    else { Write-Host "Журналы: $diagnosticsPath" }
    return
}
if (@(Get-Process -Name CapCut -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'CapCut уже запущен. Полностью закройте его и повторите запуск.'
}
if ($NoDiagnostics) {
    # Startup status is read through memory-only pipes; no output files are opened.
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $pythonPath
    $startInfo.Arguments = '-B "' + $scriptPath + '" --region ' + $Region.ToLowerInvariant()
    $startInfo.WorkingDirectory = $workspaceRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $helper = New-Object System.Diagnostics.Process
    $helper.StartInfo = $startInfo
    if (-not $helper.Start()) { throw 'Не удалось запустить помощник.' }
    $errorsTask = $helper.StandardError.ReadToEndAsync()
    $statusTask = $helper.StandardOutput.ReadLineAsync()
    if ($statusTask.Wait(20000)) {
        if ($statusTask.Result -like 'SPAWNED *') {
            Write-Output 'CAPCUT_LAUNCH_READY'
            Write-Host "CapCut запущен: $Region Pro. Без диагностики и новых копий."
            return
        }
        $helper.WaitForExit(1000) | Out-Null
        $details = if ($errorsTask.IsCompleted) { $errorsTask.Result } else { '' }
        throw "Не удалось подтвердить запуск CapCut. $details"
    }
    Write-Host 'Помощник работает, запуск ещё не подтверждён. Проверьте окно CapCut.'
    return
}
New-Item -ItemType Directory -Path $diagnosticsPath -Force | Out-Null
$profileName = $Region.ToLowerInvariant() + $(if ($ShowProUI) {'-pro-ui'} else {'-standard'})
$stdoutPath = Join-Path $diagnosticsPath ($profileName + '-output.log')
$stderrPath = Join-Path $diagnosticsPath ($profileName + '-errors.log')
$helperArguments = @('"' + $scriptPath + '"', '--spawn', '--region-guard',
    '--region', $Region.ToLowerInvariant(), '--while-running')
if ($ShowProUI) { $helperArguments += '--show-pro-ui' }

$helper = Start-Process -FilePath $pythonPath -ArgumentList $helperArguments `
    -WorkingDirectory $workspaceRoot -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
for ($attempt = 0; $attempt -lt 40; $attempt++) {
    Start-Sleep -Milliseconds 500
    $helper.Refresh()
    if ($helper.HasExited) {
        $details = Get-Content -LiteralPath $stderrPath -Tail 12 -ErrorAction SilentlyContinue
        throw "Помощник завершился до подтверждения запуска. Код: $($helper.ExitCode).`n$($details -join [Environment]::NewLine)`nЖурнал: $stderrPath"
    }
    if (Select-String -LiteralPath $stdoutPath -Pattern '^SPAWNED ' -Quiet) {
        Write-Host "CapCut запущен: регион $Region, $interfaceName."
        Write-Host 'Показ Pro не означает активацию подписки; права проверяет приложение.'
        Write-Host "Журналы: $diagnosticsPath"
        return
    }
}
Write-Host "Помощник работает, запуск ещё не подтверждён. Проверьте окно CapCut и журнал: $stderrPath"
