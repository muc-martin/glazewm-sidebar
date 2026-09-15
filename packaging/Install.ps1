[CmdletBinding()]
param(
    [string]$InstallDirectory=(Join-Path $env:LOCALAPPDATA 'Programs\NativeSidebar'),
    [string]$ConfigPath=$(if($env:GLAZEWM_CONFIG_PATH){$env:GLAZEWM_CONFIG_PATH}else{Join-Path $env:USERPROFILE '.glzr\glazewm\config.yaml'}),
    [string]$GlazeExe,
    [string]$StartupDirectory=[Environment]::GetFolderPath('Startup'),
    [switch]$NoLaunch
)
$ErrorActionPreference='Stop'
if(![Environment]::Is64BitOperatingSystem){throw 'Native Sidebar requires 64-bit Windows.'}
. (Join-Path $PSScriptRoot 'Configuration.ps1')
if(!$GlazeExe){$command=Get-Command glazewm.exe -ErrorAction SilentlyContinue;if($command){$GlazeExe=$command.Source}}
if(!$GlazeExe -or !(Test-Path -LiteralPath $GlazeExe)){throw 'Install GlazeWM first, or supply -GlazeExe.'}
if(!(Test-Path -LiteralPath $ConfigPath)){throw 'GlazeWM configuration was not found.'}
$ConfigPath=[IO.Path]::GetFullPath($ConfigPath)
$InstallDirectory=[IO.Path]::GetFullPath($InstallDirectory)
$payload=Join-Path $PSScriptRoot 'native-sidebar.exe'
if(!(Test-Path -LiteralPath $payload)){throw 'Run Install.cmd from the extracted release package, not the source tree.'}
if($InstallDirectory.TrimEnd('\') -eq $PSScriptRoot.TrimEnd('\')){throw 'Extract the installer outside the installation directory.'}
$marker=Join-Path $InstallDirectory 'installation.json'
$shortcut=Join-Path $StartupDirectory 'Native Sidebar.lnk'
$before=[IO.File]::ReadAllText($ConfigPath)
$previous=$null
if(Test-Path -LiteralPath $InstallDirectory){
    if(!(Test-Path -LiteralPath $marker)){throw 'Destination already exists without an installation record. Choose an empty destination.'}
    $previous=Get-Content $marker -Raw | ConvertFrom-Json
    if($previous.ConfigPath -ne $ConfigPath -or $previous.Shortcut -ne $shortcut){throw 'Update must use the original configuration and startup directory.'}
    $expectedName=if($previous.Active){'installed-config.yaml'}else{'original-config.yaml'}
    if($before -ne [IO.File]::ReadAllText((Join-Path $InstallDirectory $expectedName))){throw 'Configuration changed since installation. Preserve/merge your changes before upgrading.'}
}
if((Test-Path -LiteralPath $shortcut) -and !$previous){throw 'A Native Sidebar startup entry already exists without a matching installation.'}
$after=ConvertTo-SidebarConfiguration $before
$names=@(Get-WorkspaceNames $before)
$stage=Join-Path ([IO.Path]::GetDirectoryName($InstallDirectory)) ('NativeSidebar-stage-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$files=@('native-sidebar.exe','Start-Sidebar.ps1','Uninstall.ps1','Configuration.ps1','README.md','LICENSE','THIRD_PARTY_NOTICES.md')
foreach($name in $files){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $stage}
[IO.File]::WriteAllText((Join-Path $stage 'sidebar.ini'),"[sidebar]`r`nworkspaces="+($names -join ','),[Text.UTF8Encoding]::new($false))
$original=if($previous){[IO.File]::ReadAllText((Join-Path $InstallDirectory 'original-config.yaml'))}else{$before}
[IO.File]::WriteAllText((Join-Path $stage 'original-config.yaml'),$original,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $stage 'installed-config.yaml'),$after,[Text.UTF8Encoding]::new($false))
$record=[ordered]@{Version='0.1.0';Active=$true;ConfigPath=$ConfigPath;GlazeExe=[IO.Path]::GetFullPath($GlazeExe);Shortcut=$shortcut;InstalledAt=[DateTime]::UtcNow.ToString('o')}
$record | ConvertTo-Json | Set-Content (Join-Path $stage 'installation.json') -Encoding UTF8
$archive=$null
try {
    if($previous){
        Get-Process native-sidebar -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq (Join-Path $InstallDirectory 'native-sidebar.exe')} | Stop-Process
        $archive=$InstallDirectory+'.previous-'+[guid]::NewGuid().ToString('N')
        # Both absolute paths are explicit siblings under the installation parent.
        Move-Item -LiteralPath $InstallDirectory -Destination $archive
    }
    Move-Item -LiteralPath $stage -Destination $InstallDirectory
    [IO.File]::WriteAllText($ConfigPath,$after,[Text.UTF8Encoding]::new($false))
    New-Item -ItemType Directory -Path $StartupDirectory -Force | Out-Null
    $shell=New-Object -ComObject WScript.Shell
    $link=$shell.CreateShortcut($shortcut)
    $link.TargetPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $link.Arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $InstallDirectory 'Start-Sidebar.ps1')+'"'
    $link.WorkingDirectory=$InstallDirectory;$link.WindowStyle=7;$link.Description='Native Sidebar for GlazeWM';$link.Save()
    if(!$NoLaunch){
        if(Get-Process glazewm -ErrorAction SilentlyContinue){
            $response=(& $GlazeExe command wm-reload-config | ConvertFrom-Json)
            if(!$response.success){throw "GlazeWM rejected configuration: $($response.error)"}
        }
        # Replace the bar, not the window manager. No application windows are closed.
        Get-Process zebar,native-sidebar -ErrorAction SilentlyContinue | Stop-Process
        & (Join-Path $InstallDirectory 'Start-Sidebar.ps1')
    }
} catch {
    [IO.File]::WriteAllText($ConfigPath,$before,[Text.UTF8Encoding]::new($false))
    if(!$previous -and (Test-Path -LiteralPath $shortcut)){Remove-Item -LiteralPath $shortcut}
    if(Test-Path -LiteralPath $InstallDirectory){Move-Item -LiteralPath $InstallDirectory -Destination ($InstallDirectory+'.failed-'+[guid]::NewGuid().ToString('N'))}
    if($archive){Move-Item -LiteralPath $archive -Destination $InstallDirectory}
    if(!$NoLaunch -and (Get-Process glazewm -ErrorAction SilentlyContinue)){& $GlazeExe command wm-reload-config | Out-Null}
    throw
}
Write-Output "Installed Native Sidebar in $InstallDirectory"
Write-Output 'Windows sign-in startup enabled. Original GlazeWM configuration preserved.'
