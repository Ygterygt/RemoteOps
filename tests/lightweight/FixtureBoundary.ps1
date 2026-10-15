# Test-only remote boundary. Never dot-source into production.
function Invoke-OfflineBlocked {
 param([string]$Operation)
 $entry=[pscustomobject]@{PID=$PID;Operation=$Operation;Time=[datetime]::UtcNow.ToString('o')}
 [IO.File]::AppendAllText(($env:REMOTEOPS_OFFLINE_STATE+'.blocked.jsonl'),(($entry|ConvertTo-Json -Compress)+[Environment]::NewLine))
 throw ('OFFLINE_BOUNDARY_BLOCKED: '+$Operation)
}
function Invoke-OfflineState {
 param([string]$Target,[string]$Operation,[scriptblock]$Action)
 $path=$env:REMOTEOPS_OFFLINE_STATE
 if(-not [IO.Path]::IsPathRooted($path) -or -not [IO.File]::Exists($path)){throw 'Offline state path must be an existing absolute JSON file.'}
 $lock=$null
 for($i=0;$i -lt 500 -and $null -eq $lock;$i++){try{$lock=[IO.File]::Open(($path+'.lock'),'OpenOrCreate','ReadWrite','None')}catch{Start-Sleep -Milliseconds 10}}
 if($null -eq $lock){throw 'Offline state lock timeout.'}
 try{
  $state=ConvertFrom-Json ([IO.File]::ReadAllText($path))
  $property=$state.Targets.PSObject.Properties[$Target]
  if($Target -cnotmatch '^SIM-[A-Z0-9_-]+$' -or $null -eq $property){Invoke-OfflineBlocked ('Target:'+ $Target)}
  $model=$property.Value
  $before=ConvertFrom-Json ($model|ConvertTo-Json -Depth 30 -Compress)
  $failure=$null;$result=$null
  try{$result=& $Action $model}catch{$failure=$_}
  $after=ConvertFrom-Json ($model|ConvertTo-Json -Depth 30 -Compress)
  $state.Events=@($state.Events)+@([pscustomobject]@{PID=$PID;Target=$Target;Operation=$Operation;Before=$before;After=$after;Error=$(if($failure){$failure.Exception.Message}else{''});Time=[datetime]::UtcNow.ToString('o')})
  $temp=$path+'.'+$PID+'.tmp'
  [IO.File]::WriteAllText($temp,($state|ConvertTo-Json -Depth 50),[Text.UTF8Encoding]::new($true))
  [IO.File]::Replace($temp,$path,[System.Management.Automation.Language.NullString]::Value)
  if($Operation -in @('StartService','StopService','ChangeStartMode') -and $state.PSObject.Properties['PauseAfterMutationMs']){$ms=[int]$state.PauseAfterMutationMs;if($ms -lt 0 -or $ms -gt 1000){throw 'Invalid PauseAfterMutationMs'};Start-Sleep -Milliseconds $ms}
  if($failure){throw $failure}
  return $result
 }finally{$lock.Dispose()}
}
function Assert-OfflineRequest {
 param($Request)
 if([string]$Request.Operation -cnotin @('RecipeRun','RecipeCondition','ServiceList','ServiceControl','ServiceStartup')){Invoke-OfflineBlocked ('Request:'+ $Request.Operation)}
 foreach($target in @($Request.Targets)){Invoke-OfflineState $target 'ValidateTarget' {param($m)} }
}
function New-CimSessionOption { param($Protocol) [pscustomobject]@{Offline=$true} }
function New-CimSession { [CmdletBinding()]param([string]$ComputerName,$SessionOption,$OperationTimeoutSec) Invoke-OfflineState $ComputerName 'Session' {param($m)};[pscustomobject]@{ComputerName=$ComputerName;Offline=$true} }
function Remove-CimSession { [CmdletBinding()]param($CimSession) }
function Get-CimInstance {
 [CmdletBinding()]param($CimSession,[string]$ClassName,[string]$Filter,$OperationTimeoutSec,$Namespace)
 if($ClassName -cne 'Win32_Service'){Invoke-OfflineBlocked ('GetCim:'+ $ClassName)}
 Invoke-OfflineState $CimSession.ComputerName 'GetService' {param($m)
  if($m.PSObject.Properties['ProbeError'] -and $m.ProbeError){throw [string]$m.ProbeError}
  $s=$m.Service
  if($s.Exists -and (-not $Filter -or $Filter -ceq ("Name='"+$s.Name+"'"))){[pscustomobject]@{Name=$s.Name;DisplayName=$s.Name;State=$s.State;StartMode=$(if($s.Startup -eq 'Automatic'){'Auto'}else{$s.Startup})}}
 }
}
function Invoke-CimMethod {
 [CmdletBinding()]param($CimSession,$InputObject,[string]$MethodName,$Arguments,$ClassName,$Namespace,$OperationTimeoutSec)
 if($MethodName -cnotin @('StartService','StopService','ChangeStartMode')){Invoke-OfflineBlocked ('CimMethod:'+ $MethodName)}
 Invoke-OfflineState $CimSession.ComputerName $MethodName {param($m)
  if($m.PSObject.Properties['MutationError'] -and $m.MutationError){throw [string]$m.MutationError}
  if(-not $m.Service.Exists -or $null -eq $InputObject -or $InputObject.Name -cne $m.Service.Name){throw 'Modeled service not found.'}
  if($m.PSObject.Properties['SuppressMutation'] -and [bool]$m.SuppressMutation){return [pscustomobject]@{ReturnValue=0}}
  switch($MethodName){'StartService'{$m.Service.State='Running'}'StopService'{$m.Service.State='Stopped'}'ChangeStartMode'{if($Arguments.StartMode -cnotin @('Automatic','Manual','Disabled')){Invoke-OfflineBlocked 'StartMode'};$m.Service.Startup=$Arguments.StartMode}}
  [pscustomobject]@{ReturnValue=0}
 }
}
function Read-RemoteOpsConditionProbe {
 param($Check,[string]$ComputerName,[switch]$Verification)
 Invoke-OfflineState $ComputerName $(if($Verification){'Verify'}else{'Probe'}) {param($m)
  if($Verification -and $m.PSObject.Properties['VerificationError'] -and $m.VerificationError){throw [string]$m.VerificationError}
  if($m.PSObject.Properties['ProbeErrors'] -and $m.ProbeErrors.PSObject.Properties[[string]$Check.Kind]){throw [string]$m.ProbeErrors.($Check.Kind)}
  if($m.PSObject.Properties['ProbeError'] -and $m.ProbeError){throw [string]$m.ProbeError}
  $p=[pscustomobject]@{Exists=$false;ValueType='';Value='';State='';Startup='';Detail='Missing'}
  if($Check.Kind -ceq 'Service'){if($m.Service.Name -ceq $Check.Name){$p.Exists=[bool]$m.Service.Exists;$p.State=$m.Service.State;$p.Startup=$m.Service.Startup}}
  elseif($Check.Kind -ceq 'RegistryValue'){$r=$m.Registry.PSObject.Properties[([string]$Check.Path+'|'+[string]$Check.Name)];if($null -ne $r){$p.Exists=[bool]$r.Value.Exists;$p.ValueType=$r.Value.ValueType;$p.Value=$r.Value.Value}}
  elseif($Check.Kind -ceq 'RegistryKey'){foreach($r in $m.Registry.PSObject.Properties){if($r.Name.StartsWith(([string]$Check.Path+'|'),[StringComparison]::OrdinalIgnoreCase) -and $r.Value.Exists){$p.Exists=$true}}}
  else{Invoke-OfflineBlocked ('ProbeKind:'+ $Check.Kind)}
  if($p.Exists){$p.Detail='Present'}
  $p
 }
}
function Test-RemoteOpsTargetAccess {param([string]$ComputerName,$Transport,$Namespace) Invoke-OfflineState $ComputerName 'Access' {param($m) [pscustomobject]@{Status='Success';Detail='Offline model access'}} }
function Invoke-OfflineStartProcess {
 [CmdletBinding()]param([string]$FilePath,[string[]]$ArgumentList,[string]$WorkingDirectory,[switch]$Wait,[switch]$PassThru,[string]$RedirectStandardOutput,[string]$RedirectStandardError,[string]$WindowStyle)
 $expected=[IO.Path]::GetFullPath($env:REMOTEOPS_OFFLINE_RUNNER)
 $argsText=$ArgumentList -join ' '
 if([IO.Path]::GetFullPath($FilePath) -ine (Join-Path $PSHOME 'powershell.exe') -or $argsText -cnotmatch ('^-NoLogo -NoProfile (?:-NonInteractive )?-ExecutionPolicy Bypass -File "'+[regex]::Escape($expected)+'" -RequestBase64 [A-Za-z0-9+/=]+$')){Invoke-OfflineBlocked ('Process:'+ $FilePath)}
 Microsoft.PowerShell.Management\Start-Process @PSBoundParameters
}
foreach($name in @('Get-WmiObject','Invoke-WmiMethod','Invoke-Command','Enter-PSSession','New-PSSession','Test-Connection','Test-NetConnection','Invoke-WebRequest','Invoke-RestMethod','Get-Service','Set-Service','Start-Service','Stop-Service','Restart-Service','Get-ItemProperty','Set-ItemProperty','Remove-ItemProperty','New-ItemProperty','Get-CimAssociatedInstance','Get-CimClass','Set-CimInstance','New-CimInstance','Remove-CimInstance')){
 Set-Item -Path ('Function:script:'+ $name) -Value ([scriptblock]::Create("Invoke-OfflineBlocked '$name'"))
}





function Read-RemoteOpsVerificationProbe {param($Check,[string]$ComputerName) Read-RemoteOpsConditionProbe $Check $ComputerName -Verification}
