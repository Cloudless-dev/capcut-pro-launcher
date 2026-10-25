param([switch]$SkipUI)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'Windows x64 .NET Framework compiler is required.' }
$output = Join-Path $root 'local\windows-check'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$base = @('/nologo', '/codepage:65001', '/langversion:5', '/platform:x64', '/reference:System.Web.Extensions.dll', '/reference:System.Security.dll')
$core = @('launcher\ProjectLibrary.cs', 'launcher\ProjectAssets.cs', 'launcher\UiText.cs')
& $compiler @base "/out:$output\ProjectLibraryTests.exe" @core 'tests\windows\ProjectLibraryTests.cs'
if ($LASTEXITCODE -ne 0) { throw 'Project tests did not compile.' }
& "$output\ProjectLibraryTests.exe"
if ($LASTEXITCODE -ne 0) { throw 'Project tests failed.' }
& $compiler @base "/out:$output\ProjectLocationTests.exe" @core 'launcher\ProjectLocations.cs' 'tests\windows\ProjectLocationTests.cs'
if ($LASTEXITCODE -ne 0) { throw 'Project-location tests did not compile.' }
& "$output\ProjectLocationTests.exe"
if ($LASTEXITCODE -ne 0) { throw 'Project-location tests failed.' }
& $compiler @base "/out:$output\LauncherStateTests.exe" @core 'launcher\LauncherProfiles.cs' 'launcher\LauncherUpdate.cs' 'launcher\Version.cs' 'tests\windows\LauncherStateTests.cs'
if ($LASTEXITCODE -ne 0) { throw 'Profile tests did not compile.' }
& "$output\LauncherStateTests.exe"
if ($LASTEXITCODE -ne 0) { throw 'Profile tests failed.' }
$sources = @(Get-ChildItem -LiteralPath (Join-Path $root 'launcher') -Filter '*.cs' | ForEach-Object { $_.FullName })
$sdk = Join-Path $root 'local\auth-browser-sdk'
$ui = @('/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll', "/reference:$sdk\Microsoft.Web.WebView2.Core.dll", "/reference:$sdk\Microsoft.Web.WebView2.WinForms.dll")
Copy-Item -Path "$sdk\*.dll" -Destination $output -Force
if(Test-Path -LiteralPath (Join-Path $root 'launcher-web\dist')) { New-Item -ItemType Directory -Force (Join-Path $output 'ui') | Out-Null; Copy-Item -Path (Join-Path $root 'launcher-web\dist\*') -Destination (Join-Path $output 'ui') -Recurse -Force }
& $compiler @base @ui '/target:winexe' "/out:$output\CapCut Launcher.exe" @sources
if ($LASTEXITCODE -ne 0) { throw 'Launcher did not compile.' }
if (-not $SkipUI) {
    Copy-Item -LiteralPath (Join-Path $root 'assets') -Destination $output -Recurse -Force
    New-Item -ItemType Directory -Force -Path "$output\launcher" | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'launcher\English.json') -Destination "$output\launcher\English.json" -Force
    & $compiler @base @ui '/main:WebShellTests' "/out:$output\WebShellTests.exe" @sources 'tests\windows\WebShellTests.cs'
    if ($LASTEXITCODE -ne 0) { throw 'WebView2 integration tests did not compile.' }
    & "$output\WebShellTests.exe"
    if ($LASTEXITCODE -ne 0) { throw 'WebView2 integration tests failed.' }
    & $compiler @base @ui '/reference:System.Net.Http.dll' '/main:BrowserModeTests' "/out:$output\BrowserModeTests.exe" 'scripts\auth\CapCutBrowserLogin.cs' 'launcher\UiText.cs' 'tests\windows\BrowserModeTests.cs'
    if ($LASTEXITCODE -ne 0) { throw 'Browser mode tests did not compile.' }
    & "$output\BrowserModeTests.exe"
    if ($LASTEXITCODE -ne 0) { throw 'Browser mode tests failed.' }
}
python -m unittest discover -s tests/windows -p 'test_*.py' -v
if ($LASTEXITCODE -ne 0) { throw 'Session tests failed.' }
Write-Host 'Windows checks passed. Live CapCut, WebView2 sign-in and Recycle Bin still need integration testing.'
