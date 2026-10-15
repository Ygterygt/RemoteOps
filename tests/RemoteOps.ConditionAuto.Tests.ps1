$ErrorActionPreference='Stop';Set-StrictMode -Version 2
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'RemoteOps.App\RemoteOps.Conditions.ps1')
function AutoCheck($Expected='1',$Operator='Equals',$Type='Auto'){[pscustomobject]@{Kind='RegistryValue';Path='HKLM\Software\Fixture';Name='Mode';Operator=$Operator;ExpectedType=$Type;Expected=$Expected}}
function RunAuto($Check,$ActualType,$Actual,$Exists=$true){
 $script:ActualType=$ActualType;$script:Actual=$Actual;$script:Exists=$Exists;$script:Calls=0
 $Values=[pscustomobject]@{Match='All';OnFalse='Skip';Checks=@($Check)}
 $R=Invoke-RemoteOpsConditionChecks $Values fixture auto {param($Check,$ComputerName) $script:Calls++;[pscustomobject]@{Exists=$script:Exists;ValueType=$script:ActualType;Value=$script:Actual;State='';Startup='';Detail='fixture'}}
 if($script:Calls -ne 1){throw 'Auto must observe each check exactly once'}
 return $R
}
foreach($Case in @(
 @('1','REG_DWORD','1',$true),@('0x10','REG_DWORD','16',$true),@('18446744073709551615','REG_QWORD','18446744073709551615',$true),
 @('18446744073709551614','REG_QWORD','18446744073709551615',$false),@('1','REG_SZ','1',$true),@('01','REG_SZ','1',$false),
 @('16.0.444','REG_SZ','16.0.444',$true),@('16.0.444','REG_DWORD','16',$false),@('bad','REG_DWORD','1',$false),
 @('0xffffffffffffffff','REG_QWORD','18446744073709551615',$true),@('4294967296','REG_DWORD','1',$false),@('$(Get-Date)','REG_SZ','$(Get-Date)',$true),
 @('%PATH%','REG_EXPAND_SZ','%PATH%',$true),@('a','REG_SZ','A',$false),
 @("a`r`nb",'REG_MULTI_SZ','["a","b"]',$true),@("a`nb",'REG_MULTI_SZ','["a","b"]',$true),
 @("b`na",'REG_MULTI_SZ','["a","b"]',$false),@("a`n",'REG_MULTI_SZ','["a",""]',$true),
 @('','REG_MULTI_SZ','[""]',$true),@('','REG_MULTI_SZ','[]',$false),@("a`rb",'REG_MULTI_SZ','["a\rb"]',$true),@(" a`nb ",'REG_MULTI_SZ','[" a","b "]',$true),@('["a","b"]','REG_MULTI_SZ','["a","b"]',$false)
)){
 $R=RunAuto (AutoCheck $Case[0]) $Case[1] $Case[2]
 if($R.Error -or $R.Matched -ne $Case[3] -or $R.Rows[0].ValueType -cne $Case[1]){throw "Auto comparison failed: $($Case|ConvertTo-Json -Compress)"}
}
$R=RunAuto (AutoCheck 'bad' 'NotEquals') REG_DWORD '1';if($R.Error -or -not $R.Matched){throw 'Invalid expected numeric must be known nonmatch'}
$R=RunAuto (AutoCheck '1' 'NotEquals') '' '' $false;if($R.Error -or $R.Matched){throw 'Missing NotEquals must be false'}
$R=RunAuto (AutoCheck) REG_DWORD 'broken';if(-not $R.Error -or $R.Matched){throw 'Malformed actual must be Error'}
foreach($Type in @('REG_SZ','REG_EXPAND_SZ','REG_DWORD','REG_QWORD','REG_MULTI_SZ')){
 $Text=if($Type -eq 'REG_MULTI_SZ'){'["a","b"]'}else{'1'}
 $R=RunAuto (AutoCheck $Text Equals $Type) $Type $Text;if($R.Error -or -not $R.Matched){throw "Legacy $Type comparison changed"}
}
$R=RunAuto (AutoCheck '1' Equals REG_DWORD) REG_SZ '1';if($R.Matched -or $R.Error){throw 'Pinned legacy type must stay pinned'}
foreach($Mode in @('All','Any')){
 $V=[pscustomobject]@{Match=$Mode;OnFalse='Skip';Checks=@((AutoCheck),(AutoCheck '2'))}
 $R=Invoke-RemoteOpsConditionChecks $V fixture auto {[pscustomobject]@{Exists=$true;ValueType='REG_DWORD';Value='1';State='';Startup='';Detail='fixture'}}
 if($R.Error -or $R.Matched -ne ($Mode -eq 'Any')){throw 'Auto All/Any failed'}
 $script:Calls=0
 $R=Invoke-RemoteOpsConditionChecks $V fixture auto {$script:Calls++;if($script:Calls -eq 2){throw 'denied'};[pscustomobject]@{Exists=$true;ValueType='REG_DWORD';Value='1';State='';Startup='';Detail='fixture'}}
 if(-not $R.Error -or $R.Matched -or $R.Rows.Count -ne 2){throw 'Error must dominate Any'}
}
foreach($Kind in @('RegistryKey','Service')){
 $C=AutoCheck;$C.Kind=$Kind;$C.Operator='Exists';$C.Expected='';$C.Name=if($Kind -eq 'Service'){'Spooler'}else{''};if($Kind -eq 'Service'){$C.Path=''}
 $Failed=$false;try{Assert-RemoteOpsConditionValues ([pscustomobject]@{Match='All';OnFalse='Skip';Checks=@($C)})}catch{$Failed=$true};if(-not $Failed){throw 'Auto escaped registry equality scope'}
}
Write-Output 'PASS: Auto observed type, literal text, numeric precision, newline arrays, legacy types, missing, malformed actual and aggregation. Fake probes only; no endpoints.'
