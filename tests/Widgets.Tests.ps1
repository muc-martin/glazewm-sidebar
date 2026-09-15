# Explicit live test: temporarily changes Windows theme, restoring exact original values.
param([Parameter(Mandatory)][string]$Binary)
$ErrorActionPreference='Stop'
Add-Type @'
using System;using System.Runtime.InteropServices;
public class WidgetTest {
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; }
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c,string t);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h,out Rect r);
 [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,IntPtr l,uint f,uint t,out IntPtr result);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern bool SendNotifyMessage(IntPtr h,uint m,IntPtr w,string l);
}
'@
function Send($Handle,$Message,$Wparam,$Lparam){$result=[IntPtr]::Zero;if([WidgetTest]::SendMessageTimeout($Handle,$Message,[IntPtr]$Wparam,[IntPtr]$Lparam,2,2000,[ref]$result) -eq [IntPtr]::Zero){throw 'Sidebar did not respond'}}
function Assert($Value,$Message){if(!$Value){throw $Message}}
$directory=Split-Path $Binary
$ini=Join-Path $directory 'sidebar.ini'
$savedIni=if(Test-Path $ini){[IO.File]::ReadAllBytes($ini)}else{$null}
$key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$original=Get-ItemProperty $key
$names=@('AppsUseLightTheme','SystemUsesLightTheme')
$saved=@{};foreach($name in $names){$saved[$name]=$original.$name}
if(Get-Process native-sidebar -ErrorAction SilentlyContinue){throw 'Exit sidebar before this opt-in test.'}
$process=$null
try {
 [IO.File]::WriteAllText($ini,"[widgets]`r`ntheme=1`r`ncpu=1`r`nram=1`r`nbattery=1`r`n")
 $process=Start-Process $Binary -ArgumentList '--diagnostics' -WindowStyle Hidden -PassThru
 Start-Sleep -Seconds 7
 $controller=[WidgetTest]::FindWindow('NativeSidebarController','Native Sidebar Controller')
 $bar=[WidgetTest]::FindWindow('NativeSidebar','Native Sidebar')
 $statePath=Join-Path $directory 'widgets.json'
 $state=Get-Content $statePath -Raw | ConvertFrom-Json
 Assert ($state.cpu -ge 0 -and $state.cpu -le 100) 'CPU sample outside 0..100'
 Assert ($state.ram -gt 0 -and $state.ram -le 100) 'RAM sample outside 1..100'
 Assert ($state.battery -ge -1 -and $state.battery -le 100) 'Invalid battery state'
 "Samples: CPU=$($state.cpu)% RAM=$($state.ram)% battery=$($state.battery)%"
 $rect=New-Object WidgetTest+Rect
 [WidgetTest]::GetClientRect($bar,[ref]$rect)|Out-Null
 $scale=[WidgetTest]::GetDpiForWindow($bar)/96.0
 $x=[int](20*$scale);$y=$rect.Bottom-[int](232*$scale)
 Send $bar 0x202 0 ($x -bor ($y -shl 16))
 $expected=if($saved['AppsUseLightTheme'] -eq 0){1}else{0}
 $changed=Get-ItemProperty $key
 Assert ($changed.AppsUseLightTheme -eq $expected -and $changed.SystemUsesLightTheme -eq $expected) 'Theme click failed'
 Send $bar 0x202 0 ($x -bor ($y -shl 16))
 $changed=Get-ItemProperty $key
 Assert ($changed.AppsUseLightTheme -ne $expected -and $changed.SystemUsesLightTheme -ne $expected) 'Reverse theme click failed'
 foreach($id in 4110..4113){Send $controller 0x111 $id 0}
 $state=Get-Content $statePath -Raw | ConvertFrom-Json
 Assert ($state.timerMs -eq 0 -and !($state.enabled -contains $true)) 'Disabled widgets still have a sampling timer'
 $stamp=(Get-Item $statePath).LastWriteTimeUtc
 $process.Refresh();$cpuStart=$process.TotalProcessorTime.TotalSeconds
 Start-Sleep -Seconds 15
 $process.Refresh();$idleCpu=$process.TotalProcessorTime.TotalSeconds-$cpuStart
 Assert ((Get-Item $statePath).LastWriteTimeUtc -eq $stamp) 'Widgets sampled while disabled'
 $offMemory=$process.WorkingSet64;$offPrivate=$process.PrivateMemorySize64
 foreach($id in 4110..4113){Send $controller 0x111 $id 0}
 Start-Sleep -Seconds 6
 $process.Refresh();$cpuStart=$process.TotalProcessorTime.TotalSeconds
 Start-Sleep -Seconds 15
 $process.Refresh();$widgetCpu=$process.TotalProcessorTime.TotalSeconds-$cpuStart
 [pscustomobject]@{OffWorkingMB=[math]::Round($offMemory/1MB,2);OnWorkingMB=[math]::Round($process.WorkingSet64/1MB,2);OffPrivateMB=[math]::Round($offPrivate/1MB,2);OnPrivateMB=[math]::Round($process.PrivateMemorySize64/1MB,2);OffCpuSecondsIn15s=$idleCpu;OnCpuSecondsIn15s=$widgetCpu}
 # Confirm the persisted preference is read after a full restart.
 Send $controller 0x111 4111 0
 Send $controller 0x10 0 0
 Assert ($process.WaitForExit(5000)) 'Test process did not exit'
 $process=Start-Process $Binary -ArgumentList '--diagnostics' -WindowStyle Hidden -PassThru
 Start-Sleep -Seconds 6
 $state=Get-Content $statePath -Raw | ConvertFrom-Json
 Assert (!$state.enabled[1] -and $state.enabled[2]) 'Widget preference was not restored after restart'
 'PASS: samples, theme click both ways, disabled sampling, settings persistence.'
} finally {
 if($process -and !$process.HasExited){Stop-Process -Id $process.Id;$process.WaitForExit()}
 if($savedIni){[IO.File]::WriteAllBytes($ini,$savedIni)}elseif(Test-Path $ini){Remove-Item -LiteralPath $ini}
 foreach($name in $names){if($null -eq $saved[$name]){Remove-ItemProperty $key $name -ErrorAction SilentlyContinue}else{Set-ItemProperty $key $name $saved[$name]}}
 [WidgetTest]::SendNotifyMessage([IntPtr]0xffff,0x1a,[IntPtr]::Zero,'ImmersiveColorSet')|Out-Null
}
