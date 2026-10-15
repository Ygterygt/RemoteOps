. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Modules\RegistryPaths.ps1')
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Modules\RegistryValues.ps1')
function Assert-RemoteOpsConditionFields {
 param($Object,[string[]]$Fields)
 if($null -eq $Object){throw 'Condition object is required.'}
 $Names=if($Object -is [System.Collections.IDictionary]){@($Object.Keys)}else{@($Object.PSObject.Properties.Name)}
 if($Names.Count -ne $Fields.Count){throw 'Unexpected condition fields.'}
 foreach($Field in $Fields){if($Names -cnotcontains $Field){throw "Missing condition field: $Field"}}
}
function Assert-RemoteOpsConditionValues {
 param($Values)
 Assert-RemoteOpsConditionFields $Values @('Match','OnFalse','Checks')
 if($Values.Match -isnot [string] -or @('All','Any') -cnotcontains $Values.Match){throw 'Match must be All or Any.'}
 if($Values.OnFalse -isnot [string] -or @('Skip','Stop') -cnotcontains $Values.OnFalse){throw 'OnFalse must be Skip or Stop.'}
 if($Values.Checks -isnot [System.Collections.IList] -or $Values.Checks.Count -lt 1 -or $Values.Checks.Count -gt 10){throw 'Checks must contain 1 through 10 checks.'}
 foreach($Check in $Values.Checks){
  Assert-RemoteOpsConditionFields $Check @('Kind','Path','Name','Operator','ExpectedType','Expected')
  foreach($Field in @('Kind','Path','Name','Operator','ExpectedType','Expected')){if($Check.$Field -isnot [string]){throw "Check $Field must be a string."}}
  if(@('RegistryKey','RegistryValue','Service') -cnotcontains $Check.Kind){throw 'Unknown condition kind.'}
  if($Check.Name -match '[\x00-\x1f*?\[\]]' -or $Check.Path -match '[\x00-\x1f*?\[\]]'){throw 'Condition names and paths must be exact literals.'}
  if($Check.Kind -eq 'Service'){
   if($Check.Path -ne '' -or $Check.ExpectedType -ne '' -or $Check.Name -notmatch '^[A-Za-z0-9_. $@{}()+,:=-]{1,256}$'){throw 'Exact service Name is required; Path and ExpectedType must be empty.'}
   if(@('Exists','NotExists','State','Startup') -cnotcontains $Check.Operator){throw 'Invalid service operator.'}
   if($Check.Operator -eq 'State' -and @('Running','Stopped','Paused','Start Pending','Stop Pending','Continue Pending','Pause Pending','Unknown') -cnotcontains $Check.Expected){throw 'Invalid service state.'}
   if($Check.Operator -eq 'Startup' -and @('Automatic','Manual','Disabled') -cnotcontains $Check.Expected){throw 'Invalid service startup mode.'}
  }else{
   $null=ConvertTo-RemoteOpsRegistryPath $Check.Path
   $Ops=@('Exists','NotExists');if($Check.Kind -eq 'RegistryValue'){$Ops+=@('Equals','NotEquals')}
   if($Ops -cnotcontains $Check.Operator){throw 'Invalid registry operator.'}
   if($Check.Kind -eq 'RegistryKey' -and $Check.Name -ne ''){throw 'RegistryKey Name must be empty.'}
   if($Check.Operator -in @('Equals','NotEquals')){
    if(@('Auto','REG_SZ','REG_EXPAND_SZ','REG_DWORD','REG_MULTI_SZ','REG_QWORD') -cnotcontains $Check.ExpectedType){throw 'Canonical registry type required.'}
    if($Check.ExpectedType -cne 'Auto'){$null=ConvertTo-RemoteOpsRegistryData -Type $Check.ExpectedType -Text $Check.Expected}
   }elseif($Check.ExpectedType -ne ''){throw 'Existence checks require empty ExpectedType.'}
  }
  if($Check.Operator -in @('Exists','NotExists') -and $Check.Expected -ne ''){throw 'Existence checks require empty Expected.'}
 }
}
function Get-RemoteOpsConditionReturnCode {
 param($Result)
 if($null -eq $Result -or -not $Result.PSObject.Properties['ReturnValue'] -or $null -eq $Result.ReturnValue){throw 'Registry provider omitted return code.'}
 $Value=$Result.ReturnValue;$Code=[uint32]0
 if($Value -is [bool] -or $Value -is [double] -or $Value -is [single] -or $Value -is [decimal] -or ([string]$Value) -notmatch '^[0-9]+$' -or -not [uint32]::TryParse([string]$Value,[ref]$Code)){throw 'Registry provider returned an invalid return code.'}
 if($Code -notin @(0,2)){throw "Registry read failed (return code $Code)."}
 return $Code
}
function Read-RemoteOpsConditionRegistryValue {
 param($Session,$Path,[string]$Name)
 $Args=@{hDefKey=$Path.Hive;sSubKeyName=$Path.SubKey}
 $Enum=Invoke-CimMethod -CimSession $Session -Namespace 'root\default' -ClassName StdRegProv -MethodName EnumValues -Arguments $Args -OperationTimeoutSec 10 -ErrorAction Stop
 $Code=Get-RemoteOpsConditionReturnCode $Enum
 if($Code -eq 2){return [pscustomobject]@{ReturnValue=2;Exists=$false;Type='';Value=''}}
 foreach($Field in @('sNames','Types')){if(-not $Enum.PSObject.Properties[$Field]){throw "Registry enumeration omitted $Field."}}
 # StdRegProv uses two null arrays for an existing key with no values.
 if(($null -eq $Enum.sNames) -ne ($null -eq $Enum.Types)){throw 'Registry enumeration arrays are inconsistent.'}
 $Names=@();$Types=@()
 if($null -ne $Enum.sNames){$Names=@($Enum.sNames);$Types=@($Enum.Types)}
 if($Names.Count -ne $Types.Count){throw 'Registry enumeration arrays are inconsistent.'}
 $Index=-1
 for($i=0;$i -lt $Names.Count;$i++){
  if($Names[$i] -isnot [string] -or $null -eq $Types[$i]){throw 'Registry enumeration entry is invalid.'}
  if([string]::Equals($Names[$i],$Name,[StringComparison]::OrdinalIgnoreCase)){if($Index -ge 0){throw 'Registry enumeration contains duplicate names.'};$Index=$i}
 }
 if($Index -lt 0){return [pscustomobject]@{ReturnValue=2;Exists=$false;Type='';Value=''}}
 $Type=switch([string]$Types[$Index]){'1'{'REG_SZ'}'2'{'REG_EXPAND_SZ'}'4'{'REG_DWORD'}'7'{'REG_MULTI_SZ'}'11'{'REG_QWORD'}default{throw 'Unsupported or malformed registry value type.'}}
 if($Type -eq 'REG_EXPAND_SZ'){
  $Raw=Get-RemoteOpsRawExpandString -Session $Session -Hive $Path.Hive -RegistryKey $Path.SubKey -ValueName $Name
  if($null -eq $Raw){throw 'Registry provider omitted string value.'}
  $Value=ConvertTo-RemoteOpsRegistryData $Type ([string]$Raw)
 }else{
  $Info=Get-RemoteOpsRegistryTypeInfo $Type;$Args.sValueName=$Name
  $Read=Invoke-CimMethod -CimSession $Session -Namespace 'root\default' -ClassName StdRegProv -MethodName $Info.Getter -Arguments $Args -OperationTimeoutSec 10 -ErrorAction Stop
  $Code=Get-RemoteOpsConditionReturnCode $Read
  if($Code -eq 2){return [pscustomobject]@{ReturnValue=2;Exists=$false;Type='';Value=''}}
  $Field=$Info.Argument
  if(-not $Read.PSObject.Properties[$Field] -or $null -eq $Read.$Field){throw "Registry provider omitted $Field."}
  if($Type -eq 'REG_MULTI_SZ'){
   foreach($Item in @($Read.$Field)){if($Item -isnot [string]){throw 'Registry provider returned malformed string array.'}}
   $Text=ConvertTo-Json -InputObject ([string[]]@($Read.$Field)) -Compress
  }else{
   if($Type -eq 'REG_SZ' -and $Read.$Field -isnot [string]){throw 'Registry provider returned malformed string.'}
   $Text=[string]$Read.$Field
  }
  $Value=ConvertTo-RemoteOpsRegistryData $Type $Text
 }
 [pscustomobject]@{ReturnValue=0;Exists=$true;Type=$Type;Value=$Value}
}
function Read-RemoteOpsConditionProbe {
 param($Check,[string]$ComputerName)
 Assert-RemoteOpsConditionValues ([pscustomobject]@{Match='All';OnFalse='Skip';Checks=@($Check)})
 $Session=$null
 try{
  $Option=New-CimSessionOption -Protocol Dcom
  $Session=New-CimSession -ComputerName $ComputerName -SessionOption $Option -OperationTimeoutSec 10 -ErrorAction Stop
  $Probe=[pscustomobject]@{Exists=$false;ValueType='';Value='';State='';Startup='';Detail=''}
  if($Check.Kind -eq 'Service'){
   $Services=@(Get-CimInstance -CimSession $Session -ClassName Win32_Service -Filter ("Name='"+$Check.Name+"'") -OperationTimeoutSec 10 -ErrorAction Stop)
   if($Services.Count -gt 1){throw 'Exact service query returned multiple services.'}
   if($Services.Count -eq 1){if(-not [string]::Equals([string]$Services[0].Name,$Check.Name,[StringComparison]::OrdinalIgnoreCase)){throw 'Service query returned a different name.'};$Probe.Exists=$true;$Probe.State=[string]$Services[0].State;$Probe.Startup=if([string]$Services[0].StartMode -ceq 'Auto'){'Automatic'}else{[string]$Services[0].StartMode}}
   if($Probe.Exists -and $Check.Operator -eq 'State' -and @('Running','Stopped','Paused','Start Pending','Stop Pending','Continue Pending','Pause Pending','Unknown') -cnotcontains $Probe.State){throw 'Service provider returned a missing or invalid State.'}
   if($Probe.Exists -and $Check.Operator -eq 'Startup' -and @('Automatic','Manual','Disabled','Boot','System') -cnotcontains $Probe.Startup){throw 'Service provider returned a missing or invalid StartMode.'}
  }else{
   # HKCU resolution uses the existing single interactive-user SID convention.
   $Path=Resolve-RemoteOpsRegistryPath -Session $Session -RegistryKey $Check.Path
   if($Check.Kind -eq 'RegistryKey'){
    $Result=Invoke-CimMethod -CimSession $Session -Namespace 'root\default' -ClassName StdRegProv -MethodName EnumKey -Arguments @{hDefKey=$Path.Hive;sSubKeyName=$Path.SubKey} -OperationTimeoutSec 10 -ErrorAction Stop
    $Code=Get-RemoteOpsConditionReturnCode $Result;$Probe.Exists=($Code -eq 0)
   }else{
    $Result=Read-RemoteOpsConditionRegistryValue -Session $Session -Path $Path -Name $Check.Name
    $Code=[uint32]$Result.ReturnValue;$Probe.Exists=[bool]$Result.Exists;$Probe.ValueType=[string]$Result.Type;$Probe.Value=[string]$Result.Value
   }
   if($Code -notin @(0,2)){throw "Registry read failed (return code $Code)."}
  }
  $Probe.Detail=if($Probe.Exists){'Present'}else{'Missing'}
  return $Probe
 }finally{if($null -ne $Session){Remove-CimSession -CimSession $Session -ErrorAction SilentlyContinue}}
}
function Invoke-RemoteOpsConditionChecks {
 param($Values,[string]$ComputerName,[string]$OperationID,[scriptblock]$Probe={param($Check,$ComputerName) Read-RemoteOpsConditionProbe -Check $Check -ComputerName $ComputerName})
 Assert-RemoteOpsConditionValues $Values
 $Rows=@();$HasError=$false;$Index=0
 foreach($Check in $Values.Checks){
  $Index++;$Row=[pscustomobject]@{ComputerName=$ComputerName;OperationID=$OperationID;Status='Success';CheckIndex=$Index;Kind=$Check.Kind;Path=$Check.Path;Name=$Check.Name;Operator=$Check.Operator;Expected=$Check.Expected;ExpectedType=$Check.ExpectedType;Observed='';Exists=$null;ValueType='';Value='';State='';Startup='';Matched=$null;ErrorDetail=''}
  try{
   $P=& $Probe $Check $ComputerName
   foreach($Field in @('Exists','ValueType','Value','State','Startup','Detail')){if($null -eq $P -or -not $P.PSObject.Properties[$Field]){throw "Probe omitted $Field."}}
   if($P.Exists -isnot [bool]){throw 'Probe Exists must be Boolean.'}
   if($P.Exists -and $Check.Kind -eq 'RegistryValue'){
    if($P.Value -isnot [string] -or @('REG_SZ','REG_EXPAND_SZ','REG_DWORD','REG_MULTI_SZ','REG_QWORD') -cnotcontains $P.ValueType){throw 'Probe registry evidence is malformed.'}
    $null=ConvertTo-RemoteOpsRegistryData $P.ValueType $P.Value
   }
   if($P.Exists -and $Check.Kind -eq 'Service'){
    if($Check.Operator -ceq 'State' -and @('Running','Stopped','Paused','Start Pending','Stop Pending','Continue Pending','Pause Pending','Unknown') -cnotcontains $P.State){throw 'Probe service State is malformed.'}
    if($Check.Operator -ceq 'Startup' -and @('Automatic','Manual','Disabled','Boot','System') -cnotcontains $P.Startup){throw 'Probe service Startup is malformed.'}
   }
   $Row.Exists=$P.Exists;$Row.ValueType=$P.ValueType;$Row.Value=$P.Value;$Row.State=$P.State;$Row.Startup=$P.Startup
   $Row.Observed=if(-not $P.Exists){'Missing'}elseif($Check.Kind -eq 'Service'){"State=$($P.State); Startup=$($P.Startup)"}elseif($Check.Kind -eq 'RegistryValue'){"$($P.ValueType): $($P.Value)"}else{'Present'}
   $Match=$false
   switch -CaseSensitive ($Check.Operator){
    'Exists' {$Match=$P.Exists}
    'NotExists' {$Match=-not $P.Exists}
    'State' {$Match=$P.Exists -and [string]::Equals($Check.Expected,[string]$P.State,[StringComparison]::Ordinal)}
    'Startup' {$Match=$P.Exists -and [string]::Equals($Check.Expected,[string]$P.Startup,[StringComparison]::Ordinal)}
    default {
     # Values are canonical text, preserving uint64 precision and ordered MULTI_SZ arrays.
     # String and array element comparison is ordinal and case-sensitive.
     $Equal=$false
     if($P.Exists -and $Check.ExpectedType -ceq 'Auto'){
      # Actual evidence was strictly validated above. Only invalid expected input
      # becomes a known nonmatch; provider/actual errors still reach the outer catch.
      $Actual=ConvertTo-RemoteOpsRegistryData $P.ValueType ([string]$P.Value)
      try{
       if($P.ValueType -ceq 'REG_MULTI_SZ'){
        # CRLF and LF delimit ordered literal items. Preserve spaces, blank items,
        # and trailing blank lines; empty input means one empty item, not [].
        # A lone CR is literal data. JSON syntax is never interpreted here.
        $Items=[string[]][regex]::Split($Check.Expected,"\r\n|\n")
        $Text=ConvertTo-Json -InputObject $Items -Compress
        $Expected=ConvertTo-RemoteOpsRegistryData $P.ValueType $Text
       }else{$Expected=ConvertTo-RemoteOpsRegistryData $P.ValueType $Check.Expected}
       $Equal=[string]::Equals($Expected,$Actual,[StringComparison]::Ordinal)
      }catch{$Equal=$false}
     }elseif($P.Exists -and $P.ValueType -ceq $Check.ExpectedType){
      $Expected=ConvertTo-RemoteOpsRegistryData $Check.ExpectedType $Check.Expected
      $Actual=ConvertTo-RemoteOpsRegistryData $P.ValueType ([string]$P.Value)
      $Equal=[string]::Equals($Expected,$Actual,[StringComparison]::Ordinal)
     }
     $Match=$P.Exists -and (($Check.Operator -ceq 'Equals' -and $Equal) -or ($Check.Operator -ceq 'NotEquals' -and -not $Equal))
    }
   }
   $Row.Matched=[bool]$Match
  }catch{$HasError=$true;$Row.Status='Error';$Row.ErrorDetail=$_.Exception.Message}
  $Rows+=$Row
 }
 $Matched=if($Values.Match -ceq 'All'){@($Rows|Where-Object{$_.Matched -ne $true}).Count -eq 0}else{@($Rows|Where-Object{$_.Matched -eq $true}).Count -gt 0}
 [pscustomobject]@{Rows=@($Rows);Matched=([bool]$Matched -and -not $HasError);Error=$HasError}
}

function New-RemoteOpsConditionValues {
 [pscustomobject]@{Match='All';OnFalse='Skip';Checks=@([pscustomobject]@{Kind='Service';Path='';Name='Spooler';Operator='State';ExpectedType='';Expected='Stopped'})}
}