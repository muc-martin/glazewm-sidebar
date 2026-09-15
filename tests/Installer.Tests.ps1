param([Parameter(Mandatory)][string]$Binary)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$root=Join-Path $repo ('.test-output\'+[guid]::NewGuid().ToString('N'))
$package=Join-Path $root 'package'
$target=Join-Path $root 'installed app'
$startup=Join-Path $root 'startup'
$config=Join-Path $root 'config.yaml'
New-Item -ItemType Directory -Path $package,$startup -Force | Out-Null
Copy-Item $Binary (Join-Path $package 'native-sidebar.exe')
Copy-Item (Join-Path $repo 'packaging\*') $package
foreach($file in @('README.md','LICENSE','THIRD_PARTY_NOTICES.md')){Copy-Item (Join-Path $repo $file) $package}
. (Join-Path $package 'Configuration.ps1')
function Assert($Condition,$Message){if(!$Condition){throw $Message}}
$original=@'
general:
  startup_commands: ['shell-exec zebar', 'shell-exec other-app']
  shutdown_commands: ['shell-exec taskkill /IM zebar.exe /F']
  config_reload_commands: []
gaps:
  inner_gap: '8px'
  outer_gap:
    top: '44px'
    right: '8px'
    bottom: '8px'
    left: '8px'
workspaces:
  - name: '1'
  - name: '2'
window_rules:
  - commands: ['ignore']
    match:
      - window_process: { equals: 'zebar' }
keybindings:
  - commands: ['focus --workspace 1']
    bindings: ['alt+1']
'@
$changed=ConvertTo-SidebarConfiguration $original
Assert ($changed.Contains('shell-exec other-app')) 'Other startup command lost'
Assert (!$changed.Contains('shell-exec zebar')) 'Zebar startup retained'
Assert ($changed.Contains("left: '44px'")) 'Left gap not applied'
Assert ($changed.Contains("bindings: ['alt+1']")) 'Keybindings changed'
Assert ((ConvertTo-SidebarConfiguration $changed) -eq $changed) 'Transformation not idempotent'
$block=$original.Replace("  startup_commands: ['shell-exec zebar', 'shell-exec other-app']","  startup_commands:`n    - 'shell-exec zebar'`n    - 'shell-exec other-app'")
Assert ((ConvertTo-SidebarConfiguration $block).Contains('shell-exec other-app')) 'Block command list failed'
$unrelated=$original.Replace('shell-exec other-app','shell-exec echo zebar')
Assert ((ConvertTo-SidebarConfiguration $unrelated).Contains('shell-exec echo zebar')) 'Unrelated command mentioning Zebar was removed'
$invalid=$original.Replace("top: '44px'","top: '3%' ")
$rejected=$false;try{ConvertTo-SidebarConfiguration $invalid | Out-Null}catch{$rejected=$true}
Assert $rejected 'Unsupported gap did not fail safely'
$unknown=$original.Replace("  - name: '2'","  - name: 'has spaces'")
$rejected=$false;try{Get-WorkspaceNames $unknown | Out-Null}catch{$rejected=$true}
Assert $rejected 'Ambiguous workspace name accepted'
[IO.File]::WriteAllText($config,$original)
$args=@{InstallDirectory=$target;ConfigPath=$config;GlazeExe=$Binary;StartupDirectory=$startup;NoLaunch=$true}
& (Join-Path $package 'Install.ps1') @args
Assert (([IO.File]::ReadAllText($config)) -eq $changed) 'Installed configuration incorrect'
Assert (Test-Path (Join-Path $startup 'Native Sidebar.lnk')) 'Startup shortcut missing'
$shell=New-Object -ComObject WScript.Shell
$link=$shell.CreateShortcut((Join-Path $startup 'Native Sidebar.lnk'))
Assert ($link.Arguments.Contains('installed app\Start-Sidebar.ps1"')) 'Shortcut path with spaces broken'
Assert ((Get-Content (Join-Path $target 'sidebar.ini') -Raw).Contains('workspaces=1,2')) 'Workspace import failed'
& (Join-Path $package 'Install.ps1') @args
Assert (([IO.File]::ReadAllText((Join-Path $target 'original-config.yaml'))) -eq $original) 'Update overwrote original backup'
[IO.File]::AppendAllText($config,"`n# user edit")
$rejected=$false;try{& (Join-Path $target 'Uninstall.ps1') -NoLaunch}catch{$rejected=$true}
Assert $rejected 'Uninstall overwrote later edits'
Assert (Test-Path (Join-Path $startup 'Native Sidebar.lnk')) 'Rejected uninstall removed startup'
[IO.File]::WriteAllText($config,$changed)
& (Join-Path $target 'Uninstall.ps1') -NoLaunch
Assert (([IO.File]::ReadAllText($config)) -eq $original) 'Uninstall did not restore exact original'
Assert (!(Test-Path (Join-Path $startup 'Native Sidebar.lnk'))) 'Startup shortcut retained after uninstall'
Assert (Test-Path (Join-Path $target 'original-config.yaml')) 'Recovery backup deleted'
& (Join-Path $target 'Uninstall.ps1') -NoLaunch
& (Join-Path $package 'Install.ps1') @args
Assert (Test-Path (Join-Path $startup 'Native Sidebar.lnk')) 'Reinstall failed'
& (Join-Path $target 'Uninstall.ps1') -NoLaunch
$failedTarget=Join-Path $root 'failed-install'
$notDirectory=Join-Path $root 'startup-is-a-file'
[IO.File]::WriteAllText($notDirectory,'fixture')
[IO.File]::WriteAllText($config,$original)
$rejected=$false
try{& (Join-Path $package 'Install.ps1') -InstallDirectory $failedTarget -ConfigPath $config -GlazeExe $Binary -StartupDirectory $notDirectory -NoLaunch}catch{$rejected=$true}
Assert $rejected 'Simulated startup failure did not abort'
Assert (([IO.File]::ReadAllText($config)) -eq $original) 'Failed installation did not roll back configuration'
Assert (!(Test-Path $failedTarget)) 'Failed installation remained active'
'PASS: configuration transform, inline/block lists, idempotence, fail-closed validation, install, paths with spaces, startup, update, edit conflict and uninstall.'
