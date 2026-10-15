$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'Modules\RegistryValues.ps1')
foreach($Case in @(@('REG_DWORD','0xffffffff','4294967295'),@('REG_QWORD','18446744073709551615','18446744073709551615'),@('REG_QWORD','0xffffffffffffffff','18446744073709551615'),@('REG_MULTI_SZ','["one","two"]','["one","two"]'),@('REG_MULTI_SZ','[]','[]'),@('REG_MULTI_SZ','["only"]','["only"]'),@('REG_EXPAND_SZ','%SystemRoot%\Temp','%SystemRoot%\Temp'))){
 if((ConvertTo-RemoteOpsRegistryData -Type $Case[0] -Text $Case[1]) -cne $Case[2]){throw "Data conversion failed $($Case[0])"}
}
foreach($Case in @(@('REG_DWORD','4294967296'),@('REG_QWORD','18446744073709551616'),@('REG_QWORD','-1'),@('REG_QWORD','1.1'),@('REG_DWORD','1e3'),@('REG_MULTI_SZ','[1]'),@('REG_MULTI_SZ','null'),@('REG_MULTI_SZ','[null]'),@('REG_MULTI_SZ','"one"'))){
 $Failed=$false;try{ConvertTo-RemoteOpsRegistryData -Type $Case[0] -Text $Case[1]|Out-Null}catch{$Failed=$true};if(-not $Failed){throw 'Invalid typed value accepted'}
}
$script:Type=1;$script:Value='old';$script:Writes=@();$script:EnumCode=0
function Invoke-CimMethod {
 param($CimSession,$Namespace,$ClassName,$MethodName,$Arguments)
 if($MethodName -eq 'EnumValues'){return [pscustomobject]@{ReturnValue=$script:EnumCode;sNames=@('Mode');Types=@($script:Type)}}
 if($MethodName -like 'Get*'){return [pscustomobject]@{ReturnValue=0;sValue=$script:Value;uValue=$script:Value}}
 $script:Writes+=[pscustomobject]@{Method=$MethodName;Arguments=$Arguments};[pscustomobject]@{ReturnValue=0}
}
function Get-RemoteOpsRawExpandString {param($Session,$Hive,$RegistryKey,$ValueName) '%SystemRoot%\Temp'}
foreach($Case in @(@(1,'REG_SZ','old','SetStringValue'),@(2,'REG_EXPAND_SZ','%SystemRoot%\Temp','SetExpandedStringValue'),@(4,'REG_DWORD','4294967295','SetDWORDValue'),@(11,'REG_QWORD','18446744073709551615','SetQWORDValue'),@(7,'REG_MULTI_SZ','["one","two"]','SetMultiStringValue'))){
 $script:Type=$Case[0];$script:Value=if($Case[0] -eq 7){[string[]]@('one','two')}else{$Case[2]}
 $Old=Get-RemoteOpsRegistryValue -Session fixture -Hive 2147483650 -RegistryKey 'Software\T' -ValueName Mode
 if(-not $Old.Exists -or $Old.Type -ne $Case[1] -or $Old.Value -cne $Case[2]){throw "Typed read failed $($Case[1])"}
 Set-RemoteOpsRegistryValue -Session fixture -Hive 2147483650 -RegistryKey 'Software\T' -ValueName Mode -Type $Old.Type -Text $Old.Value|Out-Null
 if($script:Writes[-1].Method -ne $Case[3]){throw 'Wrong typed setter'}
}
if($script:Writes[2].Arguments.uValue -isnot [uint32] -or $script:Writes[3].Arguments.uValue -isnot [uint64] -or $script:Writes[4].Arguments.sValue -isnot [string[]]){throw 'CIM arguments lost native numeric/array types'}
$script:EnumCode=5
if((Get-RemoteOpsRegistryValue -Session fixture -Hive 2147483650 -RegistryKey 'Software\T' -ValueName Mode).ReturnValue -ne 5){throw 'Enum failure must not fall back to string reads'}
Write-Output 'PASS: five registry types, unsigned limits, input rejection, exact QWORD precision, arrays, raw expand strings and typed CIM writes.'
