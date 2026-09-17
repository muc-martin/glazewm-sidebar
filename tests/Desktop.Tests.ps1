# Explicit opt-in test: changes workspace focus temporarily, never moves windows.
param([Parameter(Mandatory)][string]$Binary)
$ErrorActionPreference='Stop'
Add-Type @'
using System;using System.Runtime.InteropServices;using System.Text;using System.Collections.Generic;
public class ClickTest {
 public delegate bool Callback(IntPtr h,IntPtr p);
 [DllImport("user32.dll")] static extern bool EnumWindows(Callback c,IntPtr p);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr h,uint f);
 [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
 public static IntPtr[] Bars(){var a=new List<IntPtr>();EnumWindows((h,p)=>{var s=new StringBuilder(128);GetClassName(h,s,128);if(s.ToString()=="NativeSidebar")a.Add(h);return true;},IntPtr.Zero);return a.ToArray();}
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c,string t);
 [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,IntPtr l,uint flags,uint timeout,out IntPtr result);
}
'@
function Send($Message,$Wparam,$Lparam){$result=[IntPtr]::Zero;$ok=[ClickTest]::SendMessageTimeout($script:bar,$Message,[IntPtr]$Wparam,[IntPtr]$Lparam,2,2000,[ref]$result);if($ok -eq [IntPtr]::Zero){throw 'Sidebar did not respond'};Start-Sleep -Milliseconds 400}
function Workspaces { (glazewm query workspaces | ConvertFrom-Json).data.workspaces }
function AssertFocus($Name){for($attempt=0;$attempt -lt 20;$attempt++){if((Workspaces | Where-Object hasFocus).name -eq $Name){Write-Output "PASS: focused $Name";return};Start-Sleep -Milliseconds 100};throw "Expected focused workspace $Name"}
$original=(Workspaces | Where-Object hasFocus).name
$originalDisplayed=@(Workspaces | Where-Object isDisplayed | ForEach-Object name)
$start=Get-Process native-sidebar -ErrorAction SilentlyContinue
if($start){throw 'Exit the current sidebar before running this explicit desktop test.'}
$process=Start-Process $Binary -ArgumentList '--diagnostics' -WindowStyle Hidden -PassThru
try {
 Start-Sleep -Seconds 2
 $state=Get-Content (Join-Path (Split-Path $Binary) 'state.json') -Raw | ConvertFrom-Json
 $expected=@(Workspaces | Where-Object {$_.hasFocus -or $_.isDisplayed -or $_.children.Count -gt 0} | ForEach-Object name | Sort-Object)
 if(($expected -join ',') -ne (($state.workspaces.name|Sort-Object) -join ',')){throw 'Inactive workspaces were displayed'}
 $monitors=(glazewm query monitors | ConvertFrom-Json).data.monitors
 $windows=[ClickTest]::Bars()
 if($windows.Count -ne $monitors.Count){throw 'Sidebar count does not match monitors'}
 foreach($script:bar in $windows){
   $monitorHandle=[ClickTest]::MonitorFromWindow($script:bar,2).ToInt64()
   $monitor=$monitors | Where-Object {$_.handle -eq $monitorHandle}
   $shown=$state.bars | Where-Object {$_.monitor -eq $monitorHandle}
   $expected=@($monitor.children | Where-Object {$_.type -eq 'workspace' -and ($_.hasFocus -or $_.isDisplayed -or $_.children.Count -gt 0)} | ForEach-Object name | Sort-Object)
   if(($expected -join ',') -ne (($shown.workspaces | Sort-Object) -join ',')){throw 'Sidebar contains workspaces from the wrong monitor'}
   if(!$shown.workspaces.Count){continue}
   $first=$shown.workspaces[0]
   $dpi=[ClickTest]::GetDpiForWindow($script:bar)
   $x=[int][Math]::Round(16*$dpi/96);$y=[int][Math]::Round(20*$dpi/96)
   $firstPoint=$x -bor ($y -shl 16)
   Send 0x202 0 $firstPoint;AssertFocus $first
   if((Workspaces | Where-Object hasFocus).parentId -ne $monitor.id){throw 'Click changed monitor ownership'}
   if($shown.workspaces.Count -gt 1){
     $y=[int][Math]::Round(48*$dpi/96)
     Send 0x202 0 ($x -bor ($y -shl 16));AssertFocus $shown.workspaces[1]
   }
   $before=(glazewm query windows | ConvertFrom-Json).data.windows
   Send 0x202 4 $firstPoint;AssertFocus $first
   $after=(glazewm query windows | ConvertFrom-Json).data.windows
   foreach($window in $before){$same=$after|Where-Object id -eq $window.id;if($same -and $same.parentId -ne $window.parentId){throw 'Shift-click moved a window'}}
   Send 0x20A (120 -shl 16) 0;AssertFocus $first
   Send 0x7B 0 0;AssertFocus $first
 }
 $controller=[ClickTest]::FindWindow('NativeSidebarController','Native Sidebar Controller')
 $shortcut=Join-Path ([Environment]::GetFolderPath('Startup')) 'Native Sidebar.lnk'
 $saved=if(Test-Path $shortcut){[IO.File]::ReadAllBytes($shortcut)}else{$null}
 try{
   $existed=Test-Path $shortcut;$result=[IntPtr]::Zero
   [ClickTest]::SendMessageTimeout($controller,0x111,[IntPtr]4102,[IntPtr]::Zero,2,2000,[ref]$result)|Out-Null
   if((Test-Path $shortcut) -eq $existed){throw 'Tray autostart toggle failed'}
   [ClickTest]::SendMessageTimeout($controller,0x111,[IntPtr]4102,[IntPtr]::Zero,2,2000,[ref]$result)|Out-Null
   if((Test-Path $shortcut) -ne $existed){throw 'Tray autostart reverse toggle failed'}
 }finally{if($saved){[IO.File]::WriteAllBytes($shortcut,$saved)}elseif(Test-Path $shortcut){Remove-Item -LiteralPath $shortcut}}
 'PASS: only occupied/current workspaces; tray autostart toggle and restore.'
 'PASS: click switches; Shift-click only switches; scroll and right-click do nothing.'
 Get-Process -Id $process.Id | Select-Object @{n='WorkingSetMB';e={[math]::Round($_.WorkingSet64/1MB,2)}},@{n='PrivateCommitMB';e={[math]::Round($_.PrivateMemorySize64/1MB,2)}}
}finally {
 Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
 foreach($name in $originalDisplayed){glazewm command focus --workspace $name | Out-Null}
 glazewm command focus --workspace $original | Out-Null
}
