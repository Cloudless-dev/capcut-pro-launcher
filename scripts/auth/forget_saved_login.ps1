param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$state = [IO.Path]::GetFullPath((Join-Path $root 'local'))
$appState = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'CapCutLauncher'))
$workspaceState = $state
$profileRoot = [IO.Path]::GetFullPath((Join-Path $appState 'Profiles'))
$profileId = [Guid]::Empty
$isProfile = $false
if ($env:CAPCUT_STATE_ROOT) { $state = [IO.Path]::GetFullPath($env:CAPCUT_STATE_ROOT) }
$isProfile = ([IO.Path]::GetDirectoryName($state).Equals($profileRoot,[StringComparison]::OrdinalIgnoreCase) -and [Guid]::TryParseExact([IO.Path]::GetFileName($state),'D',[ref]$profileId))
if (-not ($isProfile -or $state.Equals($appState,[StringComparison]::OrdinalIgnoreCase) -or $state.Equals($workspaceState,[StringComparison]::OrdinalIgnoreCase) -or $state.StartsWith($workspaceState+'\',[StringComparison]::OrdinalIgnoreCase))) { throw 'Unexpected account state directory.' }
$sessionPath = Join-Path $state 'auth-browser-sdk\desktop-session.bin'
$browserPath = [IO.Path]::GetFullPath((Join-Path $state 'auth-browser-profile'))
if (-not $browserPath.StartsWith($state+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected browser profile path.' }
$ancestor = $state
while ($ancestor) {
    if ((Test-Path -LiteralPath $ancestor) -and ((Get-Item -Force -LiteralPath $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Linked state paths are not supported.' }
    $ancestor = Split-Path -Parent $ancestor
}
$pending = New-Object 'System.Collections.Generic.Stack[string]'
if (Test-Path -LiteralPath $browserPath) { $pending.Push($browserPath) }
while ($pending.Count -gt 0) {
    $directory = $pending.Pop()
    if ((Get-Item -Force -LiteralPath $directory).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked browser profiles are not supported.' }
    foreach ($entry in Get-ChildItem -Force -LiteralPath $directory) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Links inside browser profiles are not supported.' }
        if ($entry.PSIsContainer) { $pending.Push($entry.FullName) }
    }
}
if ($CheckOnly) { Write-Host 'Forget Saved Login: path checks OK; nothing changed.'; return }
if (@(Get-Process -Name CapCut -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'Close CapCut fully before forgetting the saved login.'
}
if (@(Get-Process -Name CapCutBrowserLogin -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Close the browser sign-in window first.' }
# Remove the browser first. If locked, retain the saved desktop session.
if (Test-Path -LiteralPath $browserPath) { Remove-Item -LiteralPath $browserPath -Recurse -Force }
if (Test-Path -LiteralPath $sessionPath) { Remove-Item -LiteralPath $sessionPath }
$credentialsPath = Join-Path $state 'credentials.json'
if (Test-Path -LiteralPath $credentialsPath) { Remove-Item -LiteralPath $credentialsPath }
# Clear only the native account profile. Projects are retained.
$accountKey = 'HKCU:\Software\Bytedance\CapCut\Account'
if (-not $isProfile -and (Test-Path -LiteralPath $accountKey)) {
    $loggedOut = '{"uid":"0","xToken":"","csrfToken":"","nick_name":"","screen_name":""}'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($loggedOut))
    Set-ItemProperty -LiteralPath $accountKey -Name user_info -Value $encoded
}
Write-Host 'Saved desktop login removed. Use Email Login.cmd to sign in again.'
Write-Host 'The launcher browser profile was removed; the next login starts fresh.'
