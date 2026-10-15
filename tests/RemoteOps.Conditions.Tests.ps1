$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Conditions.ps1')
function Check($Op='Equals',$Type='REG_DWORD',$Expected='0x10') { [pscustomobject]@{Kind='RegistryValue';Path='HKLM\Software\Fixture';Name='Mode';Operator=$Op;ExpectedType=$Type;Expected=$Expected} }
$V=[pscustomobject]@{Match='All';OnFalse='Skip';Checks=@((Check))}
$R=Invoke-RemoteOpsConditionChecks $V fixture op {param($Check,$ComputerName) [pscustomobject]@{Exists=$true;ValueType='REG_DWORD';Value='16';State='';Startup='';Detail='fixture'}}
if(-not $R.Matched -or $R.Error -or $R.Rows.Count -ne 1){throw 'Typed match failed'}
$V.Checks=@((Check 'NotEquals'))
$R=Invoke-RemoteOpsConditionChecks $V fixture op { [pscustomobject]@{Exists=$false;ValueType='';Value='';State='';Startup='';Detail='missing'}}
if($R.Matched){throw 'Missing must not match NotEquals'}
$V.Match='Any';$V.Checks=@((Check),(Check))
$script:Calls=0
$R=Invoke-RemoteOpsConditionChecks $V fixture op { $script:Calls++;if($script:Calls -eq 2){throw 'denied'};[pscustomobject]@{Exists=$true;ValueType='REG_DWORD';Value='16';State='';Startup='';Detail='fixture'}}
if(-not $R.Error -or $R.Matched -or $R.Rows.Count -ne 2){throw 'Error dominance failed'}
foreach($Bad in @('Spool*',"Spool' OR Name='x",'Spool?')){
 $V.Checks=@([pscustomobject]@{Kind='Service';Path='';Name=$Bad;Operator='Exists';ExpectedType='';Expected=''})
 $Failed=$false;try{Assert-RemoteOpsConditionValues $V}catch{$Failed=$true};if(-not $Failed){throw 'Unsafe service name accepted'}
}
Write-Output 'PASS: typed equality, missing NotEquals, all checks and error dominance, exact service validation.'
# Read-only provider fixtures. No network access occurs in this file.
$script:Disposed=0;$script:Code=0;$script:Methods=@()
function New-CimSessionOption {param($Protocol) if($Protocol -ne 'Dcom'){throw 'Expected DCOM'}; 'fixture-option'}
function New-CimSession {param($ComputerName,$SessionOption,$OperationTimeoutSec) if($OperationTimeoutSec -ne 10){throw 'Expected timeout'};[pscustomobject]@{ComputerName=$ComputerName}}
function Remove-CimSession {param($CimSession) $script:Disposed++}
function Invoke-CimMethod {
 param($CimSession,$Namespace,$ClassName,$MethodName,$Arguments,$OperationTimeoutSec)
 $script:Methods+=$MethodName
 if($MethodName -eq 'EnumKey'){return [pscustomobject]@{ReturnValue=$script:Code}}
 if($MethodName -eq 'EnumValues'){return [pscustomobject]@{ReturnValue=$script:Code;sNames=@('Mode');Types=@(4)}}
 if($MethodName -eq 'GetDWORDValue'){return [pscustomobject]@{ReturnValue=$script:Code;uValue=[uint32]16}}
 throw "Unexpected provider method $MethodName"
}
$K=[pscustomobject]@{Kind='RegistryKey';Path='HKLM\Software\Fixture';Name='';Operator='Exists';ExpectedType='';Expected=''}
$script:Code=2
if((Read-RemoteOpsConditionProbe $K fixture).Exists){throw 'Missing key returned present'}
$script:Code=5;$Failed=$false
try{Read-RemoteOpsConditionProbe $K fixture|Out-Null}catch{$Failed=$true}
if(-not $Failed){throw 'Access denied returned missing'}
$script:Code=0
$P=Read-RemoteOpsConditionProbe (Check) fixture
if(-not $P.Exists -or $P.ValueType -ne 'REG_DWORD' -or $P.Value -cne '16'){throw 'Typed provider read failed'}
if($script:Disposed -ne 3){throw 'CIM session cleanup failed'}
function Get-CimInstance {param($CimSession,$ClassName,$Filter,$OperationTimeoutSec) if($Filter -cne "Name='Spooler'" -or $OperationTimeoutSec -ne 10){throw 'Unsafe service query'};[pscustomobject]@{Name='Spooler';State='Running';StartMode='Auto'}}
$S=[pscustomobject]@{Kind='Service';Path='';Name='Spooler';Operator='State';ExpectedType='';Expected='Running'}
if((Read-RemoteOpsConditionProbe $S fixture).State -cne 'Running'){throw 'Service probe failed'}
foreach($Pair in @(@('REG_SZ','A','a',$false),@('REG_QWORD','0xffffffffffffffff','18446744073709551615',$true),@('REG_MULTI_SZ','["a","b"]','[ "a", "b" ]',$true),@('REG_MULTI_SZ','["a","b"]','["b","a"]',$false))){
 $V.Match='All';$V.Checks=@((Check 'Equals' $Pair[0] $Pair[1]));$script:Observed=$Pair[2];$script:ObservedType=$Pair[0]
 $R=Invoke-RemoteOpsConditionChecks $V fixture op {[pscustomobject]@{Exists=$true;ValueType=$script:ObservedType;Value=$script:Observed;State='';Startup='';Detail='fixture'}}
 if($R.Matched -ne $Pair[3] -or $R.Error){throw 'Typed comparison semantics failed'}
}
$V.Checks=@((Check 'NotEquals' 'REG_DWORD' '16'))
$R=Invoke-RemoteOpsConditionChecks $V fixture op {[pscustomobject]@{Exists=$true;ValueType='REG_SZ';Value='16';State='';Startup='';Detail='fixture'}}
if(-not $R.Matched){throw 'Type mismatch NotEquals failed'}
Write-Output 'PASS: read-only CIM fixtures, missing versus access denied, session cleanup, exact WQL, uint64 precision, ordinal text, ordered arrays and type mismatch.'
$Defaults=New-RemoteOpsConditionValues
Assert-RemoteOpsConditionValues $Defaults
if($Defaults.Checks[0].Expected -cne 'Stopped'){throw 'Default condition mismatch'}
$S.Operator='Startup';$S.Expected='Automatic'
Assert-RemoteOpsConditionValues ([pscustomobject]@{Match='All';OnFalse='Skip';Checks=@($S)})
if((Read-RemoteOpsConditionProbe $S fixture).Startup -cne 'Automatic'){throw 'Startup normalization failed'}
foreach($Mode in @('All','Any')){
 $V.Match=$Mode;$V.Checks=@((Check),(Check));$script:Calls=0
 $R=Invoke-RemoteOpsConditionChecks $V fixture op {$script:Calls++;[pscustomobject]@{Exists=$true;ValueType='REG_DWORD';Value=if($script:Calls -eq 1){'16'}else{'17'};State='';Startup='';Detail='fixture'}}
 if($R.Matched -ne ($Mode -eq 'Any') -or $R.Rows.Count -ne 2 -or $R.Error){throw 'All/Any aggregation failed'}
}
$Invalid=@(
 [pscustomobject]@{Match='all';OnFalse='Skip';Checks=@((Check))},
 [pscustomobject]@{Match='All';OnFalse='Skip';Checks=@()},
 [pscustomobject]@{Match='All';OnFalse='Skip';Checks=@((Check))*11},
 [pscustomobject]@{Match='All';OnFalse='Skip';Checks=@((Check));Extra='bad'}
)
foreach($Bad in $Invalid){$Failed=$false;try{Assert-RemoteOpsConditionValues $Bad}catch{$Failed=$true};if(-not $Failed){throw 'Invalid schema accepted'}}
Write-Output 'PASS: defaults, startup normalization, All/Any truth tables and strict schema rejection.'
$script:Malformed='NullReturn'
function Invoke-CimMethod {
 param($CimSession,$Namespace,$ClassName,$MethodName,$Arguments,$OperationTimeoutSec)
 if($MethodName -eq 'EnumValues'){
  if($script:Malformed -eq 'NullReturn'){return [pscustomobject]@{ReturnValue=$null;sNames=@('Mode');Types=@(4)}}
  return [pscustomobject]@{ReturnValue=0;sNames=@('Mode');Types=@(4)}
 }
 [pscustomobject]@{ReturnValue=0;uValue=$null}
}
foreach($Malformed in @('NullReturn','NullGetter')){
 $script:Malformed=$Malformed;$Failed=$false
 try{Read-RemoteOpsConditionProbe (Check 'Equals' 'REG_DWORD' '0') fixture|Out-Null}catch{$Failed=$true}
 if(-not $Failed){throw "Malformed provider accepted: $Malformed"}
}
function Get-CimInstance {param($CimSession,$ClassName,$Filter,$OperationTimeoutSec) [pscustomobject]@{Name='Spooler';State=$null;StartMode=$null}}
$S.Operator='State';$S.Expected='Stopped';$Failed=$false
try{Read-RemoteOpsConditionProbe $S fixture|Out-Null}catch{$Failed=$true}
if(-not $Failed){throw 'Null service state accepted'}
Write-Output 'PASS: malformed provider return code, getter value and service state fail closed.'
foreach($BadReturn in @($null,-1,'n/a',4294967296,[double]0,$true)){
 $Failed=$false;try{Get-RemoteOpsConditionReturnCode ([pscustomobject]@{ReturnValue=$BadReturn})|Out-Null}catch{$Failed=$true}
 if(-not $Failed){throw 'Malformed return code accepted'}
}
function Invoke-CimMethod {
 param($CimSession,$Namespace,$ClassName,$MethodName,$Arguments,$OperationTimeoutSec)
 if($MethodName -eq 'EnumValues'){return [pscustomobject]@{ReturnValue=0;sNames=@('Mode');Types=@(4)}}
 [pscustomobject]@{ReturnValue=$null;uValue=0}
}
$Failed=$false;try{Read-RemoteOpsConditionProbe (Check 'Equals' 'REG_DWORD' '0') fixture|Out-Null}catch{$Failed=$true}
if(-not $Failed){throw 'Null getter return code accepted'}
$V.Match='Any';$V.Checks=@((Check),(Check));$script:Calls=0
$R=Invoke-RemoteOpsConditionChecks $V fixture op {$script:Calls++;[pscustomobject]@{Exists=$true;ValueType='REG_DWORD';Value=if($script:Calls -eq 1){'16'}else{$null};State='';Startup='';Detail='fixture'}}
if(-not $R.Error -or $R.Matched){throw 'Malformed evidence did not dominate Any match'}
Write-Output 'PASS: malformed numeric codes, null getter return code and malformed injected evidence fail closed.'
$script:FixtureType=1;$script:FixtureValue=''
function Invoke-CimMethod {
 param($CimSession,$Namespace,$ClassName,$MethodName,$Arguments,$OperationTimeoutSec)
 if($MethodName -eq 'EnumValues'){return [pscustomobject]@{ReturnValue=0;sNames=@('Mode');Types=@($script:FixtureType)}}
 [pscustomobject]@{ReturnValue=0;sValue=$script:FixtureValue}
}
$P=Read-RemoteOpsConditionProbe (Check 'Equals' 'REG_SZ' '') fixture
if(-not $P.Exists -or $P.Value -cne ''){throw 'Empty string rejected'}
$script:FixtureType=7;$script:FixtureValue=[string[]]@()
$P=Read-RemoteOpsConditionProbe (Check 'Equals' 'REG_MULTI_SZ' '[]') fixture
if(-not $P.Exists -or $P.Value -cne '[]'){throw 'Empty array rejected'}
function Invoke-CimMethod {param($CimSession,$Namespace,$ClassName,$MethodName,$Arguments,$OperationTimeoutSec) [pscustomobject]@{ReturnValue=0;sNames=$null;Types=$null}}
$P=Read-RemoteOpsConditionProbe (Check) fixture
if($P.Exists){throw 'Empty key treated as existing value'}
Write-Output 'PASS: legitimate empty string, empty MULTI_SZ and provider empty-key arrays remain supported.'
