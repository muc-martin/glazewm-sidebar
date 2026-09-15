param([string]$BuildDirectory=(Join-Path (Split-Path $PSScriptRoot -Parent) 'build'))
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$dist=Join-Path $repo 'dist'
$stage=Join-Path $dist ('stage-'+[guid]::NewGuid().ToString('N'))
& cmake --install $BuildDirectory --config Release --prefix $stage
if($LASTEXITCODE){throw 'CMake install failed'}
$zip=Join-Path $dist 'native-sidebar-0.1.0-windows-x64.zip'
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force
$hash=(Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(($zip+'.sha256'),$hash+'  '+[IO.Path]::GetFileName($zip)+"`n")
Write-Output $zip
