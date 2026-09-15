# Per-user Apps & Features registration. Test keys are isolated from the real app.
function Assert-SidebarRegistrationPath([string]$KeyPath) {
    if($KeyPath -ne 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\NativeSidebar' -and
       $KeyPath -notmatch ('^'+[regex]::Escape('HKCU:\Software\NativeSidebar.Tests\')+'[a-f0-9]{32}$')) {
        throw 'Unexpected Native Sidebar registration path.'
    }
}
function Get-SidebarRegistration([string]$KeyPath) {
    Assert-SidebarRegistrationPath $KeyPath
    if(!(Test-Path -LiteralPath $KeyPath)){return $null}
    $key=Get-Item -LiteralPath $KeyPath
    $values=@{}
    foreach($name in $key.GetValueNames()){
        $values[$name]=@{Value=$key.GetValue($name);Kind=$key.GetValueKind($name).ToString()}
    }
    return $values
}
function Restore-SidebarRegistration([string]$KeyPath,$Values) {
    Assert-SidebarRegistrationPath $KeyPath
    if(Test-Path -LiteralPath $KeyPath){Remove-Item -LiteralPath $KeyPath -Force}
    if($null -ne $Values){
        New-Item -Path $KeyPath -Force | Out-Null
        foreach($name in $Values.Keys){New-ItemProperty -LiteralPath $KeyPath -Name $name -Value $Values[$name].Value -PropertyType $Values[$name].Kind -Force | Out-Null}
    }
}
function Register-SidebarApp([string]$KeyPath,[string]$Directory) {
    Assert-SidebarRegistrationPath $KeyPath
    $existing=Get-SidebarRegistration $KeyPath
    if($existing -and (!$existing.ContainsKey('InstallLocation') -or $existing.InstallLocation.Value -ne $Directory)){
        throw 'Native Sidebar is already registered at a different location.'
    }
    New-Item -Path $KeyPath -Force | Out-Null
    $values=@{
        DisplayName='Native Sidebar';DisplayVersion='0.1.0';Publisher='Native Sidebar contributors'
        InstallLocation=$Directory;DisplayIcon=(Join-Path $Directory 'native-sidebar.exe')+',0'
        UninstallString='"'+(Join-Path $env:SystemRoot 'System32\cmd.exe')+'" /d /c ""'+(Join-Path $Directory 'Uninstall.cmd')+'""'
        InstallDate=(Get-Date -Format yyyyMMdd)
    }
    foreach($name in $values.Keys){New-ItemProperty -LiteralPath $KeyPath -Name $name -Value $values[$name] -PropertyType String -Force | Out-Null}
    foreach($name in @('NoModify','NoRepair')){New-ItemProperty -LiteralPath $KeyPath -Name $name -Value 1 -PropertyType DWord -Force | Out-Null}
    $size=[int][math]::Ceiling((Get-ChildItem -LiteralPath $Directory -Recurse -File | Measure-Object Length -Sum).Sum/1KB)
    New-ItemProperty -LiteralPath $KeyPath -Name EstimatedSize -Value $size -PropertyType DWord -Force | Out-Null
}
