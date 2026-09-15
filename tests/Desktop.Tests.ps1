# Explicit opt-in test: changes workspace focus temporarily, never moves windows.
param([Parameter(Mandatory)][string]$Binary)
$ErrorActionPreference='Stop'
Add-Type @'
using System;using System.Runtime.InteropServices;
public class ClickTest {
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c,string t);
 [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,IntPtr l,uint flags,uint timeout,out IntPtr result);
}
'@
function Send($Message,$Wparam,$Lparam){$result=[IntPtr]::Zero;$ok=[ClickTest]::SendMessageTimeout($script:bar,$Message,[IntPtr]$Wparam,[IntPtr]$Lparam,2,2000,[ref]$result);if($ok -eq [IntPtr]::Zero){throw 'Sidebar did not respond'};Start-Sleep -Milliseconds 400}
function Workspaces { (glazewm query workspaces | ConvertFrom-Json).data.workspaces }
function AssertFocus($Name){for($attempt=0;$attempt -lt 20;$attempt++){if((Workspaces | Where-Object hasFocus).name -eq $Name){Write-Output "PASS: focused $Name";return};Start-Sleep -Milliseconds 100};throw "Expected focused workspace $Name"}
$original=(Workspaces | Where-Object hasFocus).name
$start=Get-Process native-sidebar -ErrorAction SilentlyContinue
if($start){throw 'Exit the current sidebar before running this explicit desktop test.'}
$process=Start-Process $Binary -ArgumentList '--diagnostics' -WindowStyle Hidden -PassThru
try {
 Start-Sleep -Seconds 2
 $script:bar=[ClickTest]::FindWindow('NativeSidebar','Native Sidebar')
 $state=Get-Content (Join-Path (Split-Path $Binary) 'state.json') -Raw | ConvertFrom-Json
 if($state.workspaces.Count -lt 2){throw 'Test requires at least two configured workspaces'}
 $first=$state.workspaces[0].name;$second=$state.workspaces[1].name
 # These coordinates are logical pixels at the tested 96 DPI baseline.
 Send 0x202 0 (16 -bor (20 -shl 16));AssertFocus $first
 Send 0x202 0 (16 -bor (52 -shl 16));AssertFocus $second
 $before=(glazewm query windows | ConvertFrom-Json).data.windows
 Send 0x202 4 (16 -bor (20 -shl 16));AssertFocus $first
 $after=(glazewm query windows | ConvertFrom-Json).data.windows
 foreach($window in $before){$same=$after|Where-Object id -eq $window.id;if($same -and $same.parentId -ne $window.parentId){throw 'Shift-click moved a window'}}
 Send 0x20A (120 -shl 16) 0;AssertFocus $first
 Send 0x7B 0 0;AssertFocus $first
 'PASS: click switches; Shift-click only switches; scroll and right-click do nothing.'
 Get-Process -Id $process.Id | Select-Object @{n='WorkingSetMB';e={[math]::Round($_.WorkingSet64/1MB,2)}},@{n='PrivateCommitMB';e={[math]::Round($_.PrivateMemorySize64/1MB,2)}}
}finally {
 Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
 glazewm command focus --workspace $original | Out-Null
}
