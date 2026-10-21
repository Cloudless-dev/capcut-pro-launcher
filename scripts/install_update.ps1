param([Parameter(Mandatory=$true)][string]$Target,
      [Parameter(Mandatory=$true)][string]$Archive,
      [Parameter(Mandatory=$true)][string]$ExpectedHash,
      [int]$LauncherPid)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$targetPath=[IO.Path]::GetFullPath($Target).TrimEnd('\')
$parentPath=Split-Path -Parent $targetPath
$newPath=Join-Path $parentPath ('.capcut-update-'+[Guid]::NewGuid().ToString('N'))
$backupPath=$targetPath+'.backup-'+[Guid]::NewGuid().ToString('N')
$swapped=$false
try {
    if (-not $parentPath -or -not (Test-Path -LiteralPath (Join-Path $targetPath 'CapCut Launcher.exe'))) { throw 'Invalid launcher folder.' }
    if ((Get-Item -LiteralPath $targetPath).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked launcher folders cannot be updated.' }
    if ((Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash -ne $ExpectedHash) { throw 'Update checksum mismatch.' }
    [IO.Directory]::CreateDirectory($newPath) | Out-Null
    $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $total=0L
        foreach($entry in $zip.Entries){
            $total+=$entry.Length
            if($total -gt 1GB){throw 'Update is too large.'}
            $destination=[IO.Path]::GetFullPath((Join-Path $newPath $entry.FullName))
            if(-not $destination.StartsWith($newPath+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe archive path.'}
            if($entry.FullName.EndsWith('/')){[IO.Directory]::CreateDirectory($destination)|Out-Null;continue}
            [IO.Directory]::CreateDirectory((Split-Path -Parent $destination))|Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$destination,$false)
        }
    }finally{$zip.Dispose()}
    $folders=@(Get-ChildItem -LiteralPath $newPath -Directory)
    if($folders.Count -ne 1){throw 'Invalid archive layout.'}
    $payload=$folders[0].FullName
    if(-not(Test-Path -LiteralPath (Join-Path $payload 'CapCut Launcher.exe'))){throw 'Launcher is missing.'}
    $manifest=Get-Content -LiteralPath (Join-Path $payload 'manifest-sha256.json') -Encoding UTF8 -Raw | ConvertFrom-Json
    foreach($item in $manifest.PSObject.Properties){
        $file=[IO.Path]::GetFullPath((Join-Path $payload $item.Name))
        if(-not $file.StartsWith($payload+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe manifest path.'}
        if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $item.Value){throw 'File checksum mismatch.'}
    }
    if($LauncherPid -gt 0){Wait-Process -Id $LauncherPid -Timeout 60 -ErrorAction SilentlyContinue}
    if(@(Get-Process -Name CapCut,CapCutBrowserLogin -ErrorAction SilentlyContinue).Count){throw 'Close CapCut and the sign-in window before updating.'}
    for($attempt=0;$attempt -lt 20;$attempt++){
        try{Move-Item -LiteralPath $targetPath -Destination $backupPath;break}catch{if($attempt -eq 19){throw};Start-Sleep -Milliseconds 500}
    }
    $swapped=$true
    Move-Item -LiteralPath $payload -Destination $targetPath
    Start-Process -FilePath (Join-Path $targetPath 'CapCut Launcher.exe') -WorkingDirectory $targetPath
}catch{
    if($swapped -and -not(Test-Path -LiteralPath $targetPath)){Move-Item -LiteralPath $backupPath -Destination $targetPath}
    $_ | Out-String | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'update-error.txt')
    Add-Type -AssemblyName System.Windows.Forms
    [Windows.Forms.MessageBox]::Show('Update failed. Your previous files and account data have been retained. Details: '+(Join-Path $PSScriptRoot 'update-error.txt'),'CapCut Launcher') | Out-Null
    exit 1
}
