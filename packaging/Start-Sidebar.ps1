$ErrorActionPreference='Stop'
$state=Get-Content (Join-Path $PSScriptRoot 'installation.json') -Raw | ConvertFrom-Json
if (!(Get-Process glazewm -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath $state.GlazeExe -ArgumentList @('start','--config',('"'+$state.ConfigPath+'"')) -WindowStyle Hidden
}
Start-Process -FilePath (Join-Path $PSScriptRoot 'native-sidebar.exe') -WindowStyle Hidden
