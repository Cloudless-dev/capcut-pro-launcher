param()
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$python = Join-Path $root 'runtime\python\python.exe'
$script = Join-Path $root 'scripts\runtime\verify_capcut_session.py'
& $python -B $script
if ($LASTEXITCODE -eq 2) { throw 'Session expired or rejected. Sign in again.' }
if ($LASTEXITCODE -ne 0) { throw 'Не удалось подтвердить вход. Проверьте соединение или войдите заново.' }
