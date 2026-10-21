param([switch]$CheckOnly, [switch]$Diagnostics, [switch]$WaitForExit)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sdk = Join-Path $root 'local\auth-browser-sdk'
$source = Join-Path $PSScriptRoot 'CapCutBrowserLogin.cs'
$uiSource = Join-Path $root 'launcher\UiText.cs'
$exe = Join-Path $sdk 'CapCutBrowserLogin.exe'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
foreach ($path in @($compiler, (Join-Path $sdk 'Microsoft.Web.WebView2.Core.dll'), (Join-Path $sdk 'Microsoft.Web.WebView2.WinForms.dll'), (Join-Path $sdk 'WebView2Loader.dll'))) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing browser dependency: $path" }
}
if (-not (Test-Path -LiteralPath $exe) -or (Get-Item -LiteralPath $source).LastWriteTimeUtc -gt (Get-Item -LiteralPath $exe).LastWriteTimeUtc) {
    & $compiler /nologo /target:winexe /platform:x64 "/out:$exe" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll /reference:System.Net.Http.dll /reference:System.Security.dll "/reference:$sdk\Microsoft.Web.WebView2.Core.dll" "/reference:$sdk\Microsoft.Web.WebView2.WinForms.dll" $source $uiSource
    if ($LASTEXITCODE -ne 0) { throw 'Browser helper compilation failed.' }
}
if ($CheckOnly) {
    $process = Start-Process -FilePath $exe -ArgumentList @(('"' + $root + '"'), '--check-only') -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "WebView2 check failed: $($process.ExitCode)" }
    Write-Host 'Browser helper compiled; WebView2 Runtime is available. CapCut was not started.'
    return
}
if (@(Get-Process -Name CapCut -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Close CapCut fully before signing in.' }
if ($Diagnostics) { $env:CAPCUT_AUTH_DIAGNOSTIC = '1' }
else { Remove-Item Env:\CAPCUT_AUTH_DIAGNOSTIC -ErrorAction SilentlyContinue }
# This is the interactive sign-in window requested by the user.
$browserProcess = Start-Process -FilePath $exe -ArgumentList ('"' + $root + '"') -WorkingDirectory $root -PassThru
if ($WaitForExit) {
    $browserProcess.WaitForExit()
    if ($browserProcess.ExitCode -ne 0) { throw "Browser helper exited: $($browserProcess.ExitCode)" }
}
