$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'Modules\RegistryPaths.ps1')
foreach($InputPath in 'HKLM\Software\T','hklm:\Software\T','HKEY_LOCAL_MACHINE\Software\T','Registry::HKEY_LOCAL_MACHINE\Software\T','Software\T'){
 $P=ConvertTo-RemoteOpsRegistryPath $InputPath
 if($P.Hive -ne [uint32]2147483650 -or $P.SubKey -ne 'Software\T'){throw "HKLM parse: $InputPath"}
}
foreach($InputPath in 'HKCU\Software\T','HKEY_CURRENT_USER:\Software\T'){
 if((ConvertTo-RemoteOpsRegistryPath $InputPath).HiveName -ne 'HKEY_CURRENT_USER'){throw 'HKCU parse failed'}
}
foreach($InputPath in 'HKU\S-1-5-21-100\Software\T','HKEY_USERS:\S-1-5-21-100\Software\T'){
 if((ConvertTo-RemoteOpsRegistryPath $InputPath).Hive -ne [uint32]2147483651){throw 'HKU parse failed'}
}
foreach($InputPath in 'HKLM','HKCU:\','HKEY_INVALID\Software','C:\Software','HKLM:\..\Software'){
 $Failed=$false;try{ConvertTo-RemoteOpsRegistryPath $InputPath|Out-Null}catch{$Failed=$true}
 if(-not $Failed){throw "Invalid path accepted: $InputPath"}
}
$script:Sids=@('S-1-5-21-100')
function Get-CimInstance {param($CimSession,$ClassName,$Filter) [pscustomobject]@{LogonId='123'}}
function Get-CimAssociatedInstance {param($CimSession,$InputObject,$Association,$ResultClassName) foreach($Sid in $script:Sids){[pscustomobject]@{SID=$Sid}}}
function Invoke-CimMethod {param($CimSession,$Namespace,$ClassName,$MethodName,$Arguments) [pscustomobject]@{ReturnValue=0}}
$P=Resolve-RemoteOpsRegistryPath -Session fixture -RegistryKey 'HKCU\Software\T'
if($P.Hive -ne [uint32]2147483651 -or $P.SubKey -ne 'S-1-5-21-100\Software\T'){throw 'HKCU must resolve to interactive user HKU SID'}
foreach($Sids in @(@(),@('S-1-5-21-100','S-1-5-21-200'))){
 $script:Sids=$Sids;$Failed=$false
 try{Resolve-RemoteOpsRegistryPath -Session fixture -RegistryKey 'HKCU\Software\T'|Out-Null}catch{$Failed=$true}
 if(-not $Failed){throw 'Absent/ambiguous interactive users must be rejected'}
}
$P=Get-RemoteOpsRegistryManifestPath ([pscustomobject]@{RegistryKey='Software\T'})
if($P.HiveName -ne 'HKEY_LOCAL_MACHINE'){throw 'Legacy manifest must default HKLM'}
$P=Get-RemoteOpsRegistryManifestPath ([pscustomobject]@{RegistryKey='S-1-5-21-100\Software\T';RegistryHive='HKEY_USERS'})
if($P.SubKey -notlike 'S-1-5-21-100*' -or $P.HiveName -ne 'HKEY_USERS'){throw 'Rollback must retain recorded SID'}
Write-Output 'PASS: registry aliases, invalid paths, HKCU user resolution, ambiguity rejection and legacy manifest compatibility.'
