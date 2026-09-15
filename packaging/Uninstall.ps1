[CmdletBinding()]
param([switch]$NoLaunch)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Registration.ps1')
$record=Get-Content (Join-Path $PSScriptRoot 'installation.json') -Raw | ConvertFrom-Json
if(!$record.Active){Write-Output 'Sidebar is already uninstalled.';return}
if($record.PSObject.Properties.Name -contains 'RegistrationPath'){
    Assert-SidebarRegistrationPath $record.RegistrationPath
    $registered=Get-SidebarRegistration $record.RegistrationPath
    if($registered -and (!$registered.ContainsKey('InstallLocation') -or $registered.InstallLocation.Value -ne $PSScriptRoot)){throw 'App registration belongs to another installation.'}
}
$installed=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'installed-config.yaml'))
if([IO.File]::ReadAllText($record.ConfigPath) -ne $installed){throw 'GlazeWM configuration has changed. Merge original-config.yaml manually before uninstalling; nothing was changed.'}
$original=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'original-config.yaml'))
[IO.File]::WriteAllText($record.ConfigPath,$original,[Text.UTF8Encoding]::new($false))
try {
    if(!$NoLaunch -and (Get-Process glazewm -ErrorAction SilentlyContinue)){
        $result=(& $record.GlazeExe command wm-reload-config | ConvertFrom-Json)
        if(!$result.success){throw 'GlazeWM rejected the restored configuration.'}
    }
}catch{[IO.File]::WriteAllText($record.ConfigPath,$installed,[Text.UTF8Encoding]::new($false));throw}
if(Test-Path -LiteralPath $record.Shortcut){Remove-Item -LiteralPath $record.Shortcut}
if($record.PSObject.Properties.Name -contains 'StartMenuShortcut'){
    if(Test-Path -LiteralPath $record.StartMenuShortcut){Remove-Item -LiteralPath $record.StartMenuShortcut}
}
$record.Active=$false
if($record.PSObject.Properties.Name -contains 'RegistrationPath'){Restore-SidebarRegistration $record.RegistrationPath $null}
$record | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot 'installation.json') -Encoding UTF8
Get-Process native-sidebar -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq (Join-Path $PSScriptRoot 'native-sidebar.exe')} | Stop-Process
if(!$NoLaunch -and $original -match '(?i)zebar'){
    $zebar=Get-Command zebar.exe -ErrorAction SilentlyContinue
    if($zebar){Start-Process $zebar.Source -WindowStyle Hidden}else{Write-Warning 'Previous configuration restored. Start Zebar manually if it is not on PATH.'}
}
# Retain the small directory and original backup deliberately; no recursive deletion.
Write-Output 'Sidebar disabled, Windows startup removed, GlazeWM configuration restored. Installation files and backup retained.'
