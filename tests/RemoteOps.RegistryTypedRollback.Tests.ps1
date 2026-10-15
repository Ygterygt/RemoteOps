$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$Root=Split-Path -Parent $PSScriptRoot
function Register-AOModule {param($Name,$Version,$MinimumHostApiVersion,$SourcePath)}
function Register-AOModuleOperation {param($ModuleName,$Name,$DisplayName,$EntryPointName,$Handler)}
. (Join-Path $Root 'Modules\RegistryOperations.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Backups.ps1')
$script:Memory=$null;$script:Writes=@();$script:Answers=New-Object 'System.Collections.Generic.Queue[string]'
function Read-Host {param($Prompt)if(-not $script:Answers.Count){throw 'Unexpected prompt'};$script:Answers.Dequeue()}
function Write-Host {param([Parameter(Position=0)]$Object,$ForegroundColor)}
function New-CimSession {param($ComputerName,$SessionOption,$OperationTimeoutSec)[pscustomobject]@{ComputerName=$ComputerName}}
function New-CimSessionOption {param($Protocol)}
function Remove-CimSession {param($CimSession)}
function Get-RemoteOpsRawExpandString {param($Session,$Hive,$RegistryKey,$ValueName) $script:Memory.Text}
function Invoke-CimMethod {
 param($CimSession,$Namespace,$ClassName,$MethodName,$Arguments)
 if($MethodName -eq 'EnumValues'){
  return [pscustomobject]@{ReturnValue=0;sNames=$(if($null -ne $script:Memory){@('Mode')}else{@()});Types=$(if($null -ne $script:Memory){@((Get-RemoteOpsRegistryTypeInfo $script:Memory.Type).Code)}else{@()})}
 }
 if($MethodName -like 'Get*'){
  $Data=if($script:Memory.Type -eq 'REG_MULTI_SZ'){ConvertFrom-Json $script:Memory.Text}else{$script:Memory.Text}
  return [pscustomobject]@{ReturnValue=0;sValue=$Data;uValue=$Data}
 }
 if(-not(Test-Path -LiteralPath $script:ExpectedManifest)){throw 'Write attempted without durable manifest'}
 $script:Writes+=,$MethodName
 if($MethodName -eq 'DeleteValue'){$script:Memory=$null}else{
  $Type=switch($MethodName){SetStringValue{'REG_SZ'}SetDWORDValue{'REG_DWORD'}SetQWORDValue{'REG_QWORD'}SetMultiStringValue{'REG_MULTI_SZ'}SetExpandedStringValue{'REG_EXPAND_SZ'}default{throw "Wrong setter $MethodName"}}
  $Text=if($Type -eq 'REG_MULTI_SZ'){ConvertTo-Json -InputObject ([string[]]$Arguments.sValue) -Compress}elseif($Type -in @('REG_DWORD','REG_QWORD')){[string]$Arguments.uValue}else{[string]$Arguments.sValue}
  $script:Memory=[pscustomobject]@{Type=$Type;Text=$Text}
 }
 [pscustomobject]@{ReturnValue=0}
}
function Write-ApplicationRows {param($Name,$Rows)$script:ReportRows=$Rows;'mock.csv'}
$t=$null;$e=$null;$Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.Runner.ps1'),[ref]$t,[ref]$e)
foreach($Name in 'New-TargetScopedManifest','Invoke-RegistryRollbackRequest'){$F=$Ast.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq $Name},$true);. ([scriptblock]::Create($F.Extent.Text))}
$BasePath=Join-Path $env:TEMP ('ROTypedRegistry-'+[guid]::NewGuid().ToString('N'));$Systems=@('PC1');$OperationID='RB'
try{
 $Cases=@(@('REG_SZ','old','new'),@('REG_DWORD','4294967295','0x1234'),@('REG_QWORD','18446744073709551615','0x20000000000001'),@('REG_MULTI_SZ','["ilk","ikinci"]','["new","line\\path"]'),@('REG_MULTI_SZ','[]','["only"]'),@('REG_MULTI_SZ','["only"]','[]'),@('REG_EXPAND_SZ','%SystemRoot%\Old','%TEMP%\New'))
 $Cases+=,@('REG_SZ','','')
 $Cases+=,@('REG_SZ','  old  ',"line1`nline2")
 $Cases+=,@('REG_EXPAND_SZ','','%SystemRoot%\New')
 $Index=0
 foreach($Case in $Cases){foreach($Action in '2','3'){
  $Index++;$script:Memory=[pscustomobject]@{Type=$Case[0];Text=$Case[1]};$script:Writes=@()
  $script:ExpectedManifest=Join-Path $BasePath ('RegistryRollback\T'+$Index+'_'+$(if($Action -eq '2'){'Edit'}else{'Delete'})+'.csv')
  foreach($Answer in @($Action,'HKLM\Software\T','Mode')){$script:Answers.Enqueue($Answer)}
  if($Action -eq '2'){$script:Answers.Enqueue($Case[2]);$script:Answers.Enqueue('EDIT')}else{$script:Answers.Enqueue('DELETE')};$script:Answers.Enqueue('0')
  $R=Invoke-RegistryOperationsMenu -BasePath $BasePath -Systems $Systems -ReachableSystems $Systems -OperationID "T$Index" -OperationDate test -OperationTime test
  if($R.Rows[0].Status -ne 'Success'){throw "Typed mutation failed: $($R.Rows[0].ErrorDetail)"}
  $Manifest=@(Import-Csv $script:ExpectedManifest -Delimiter ';')[0]
  if($Manifest.OldType -ne $Case[0] -or $Manifest.OldValue -cne $Case[1]){throw "Manifest mismatch case $Index $($Case[0]): saved '$($Manifest.OldValue)', expected '$($Case[1])'"}
  $Choice=@(Get-RemoteOpsRollbackChoices -BasePath $BasePath -OperationName RegistryRollback|Where-Object Id -eq $script:ExpectedManifest)[0]
  if(-not $Choice.Display.Contains($Case[0])){throw 'Rollback list omitted registry type'}
  Invoke-RegistryRollbackRequest ([pscustomobject]@{ManifestPath=$script:ExpectedManifest})|Out-Null
  if($script:ReportRows[0].Status -ne 'Success' -or $script:Memory.Type -ne $Case[0] -or $script:Memory.Text -cne $Case[1]){throw "Runner rollback lost data/type: $($Case[0])"}
  # Same manifest must also round-trip through the console rollback implementation.
  $script:Memory=$null;foreach($Answer in @('4',$script:ExpectedManifest,'ROLLBACK','0')){$script:Answers.Enqueue($Answer)}
  Invoke-RegistryOperationsMenu -BasePath $BasePath -Systems $Systems -ReachableSystems $Systems -OperationID console -OperationDate test -OperationTime test|Out-Null
  if($script:Memory.Type -ne $Case[0] -or $script:Memory.Text -cne $Case[1]){throw 'Console rollback lost data/type'}
 }}
 # Explicitly creating a missing numeric value must keep its selected type; rollback removes it.
 $script:Memory=$null;$script:ExpectedManifest=Join-Path $BasePath 'RegistryRollback\CREATE_Edit.csv'
 foreach($Answer in @('2','HKLM\Software\T','Mode','0xffffffffffffffff','EDIT','0')){$script:Answers.Enqueue($Answer)}
 $R=Invoke-RegistryOperationsMenu -BasePath $BasePath -Systems $Systems -ReachableSystems $Systems -OperationID CREATE -ValueType REG_QWORD
 if($R.Rows[0].Status -ne 'Success' -or $script:Memory.Type -ne 'REG_QWORD'){throw 'New numeric type was not preserved'}
 Invoke-RegistryRollbackRequest ([pscustomobject]@{ManifestPath=$script:ExpectedManifest})|Out-Null
 if($null -ne $script:Memory){throw 'Rollback of newly created value must remove it'}
 # Execute the actual runner dispatch block with a serialized GUI ValueType.
 $Assignment=$Ast.Find({param($N)$N -is [Management.Automation.Language.AssignmentStatementAst] -and $N.Left.Extent.Text -eq '$InvokeTarget'},$true)
 Invoke-Expression $Assignment.Extent.Text
 function Add-Answers {param([string[]]$Answers)foreach($Answer in $Answers){$script:Answers.Enqueue($Answer)}}
 $OperationName='RegistryEdit';$Values=[pscustomobject]@{RegistryPath='HKLM\Software\T';ValueName='Mode';Value='0xffffffff';ValueType='REG_DWORD';Confirm='EDIT'}
 $Common=@{BasePath=$BasePath;Systems=$Systems;ReachableSystems=$Systems;OperationID='DISPATCH';OperationDate='test';OperationTime='test'}
 $script:ExpectedManifest=Join-Path $BasePath 'RegistryRollback\DISPATCH_Edit.csv'
 $Result=& $InvokeTarget
 if($Result.Rows[0].Status -ne 'Success' -or $script:Memory.Type -ne 'REG_DWORD' -or $script:Memory.Text -ne '4294967295'){throw 'Runner dispatch dropped the GUI type selector'}
 # Changing an existing type is forbidden, and invalid integers must cause no writes.
 foreach($Type in 'REG_SZ','Auto'){
  $script:Memory=[pscustomobject]@{Type='REG_DWORD';Text='5'};$Before=$script:Writes.Count
  foreach($Answer in @('2','HKLM\Software\T','Mode','-1','EDIT','0')){$script:Answers.Enqueue($Answer)}
  $R=Invoke-RegistryOperationsMenu -BasePath $BasePath -Systems $Systems -ReachableSystems $Systems -OperationID INVALID -ValueType $Type
  if($R.Rows[0].Status -ne 'Failed' -or $script:Writes.Count -ne $Before){throw 'Invalid data or mismatched type mutated registry'}
 }
 function Get-RemoteOpsRawExpandString {param($Session,$Hive,$RegistryKey,$ValueName)throw 'Simulated raw Remote Registry access failure'}
 $script:Memory=[pscustomobject]@{Type='REG_EXPAND_SZ';Text='%TEMP%'};$Before=$script:Writes.Count
 foreach($Answer in @('2','HKLM\Software\T','Mode','%SystemRoot%','EDIT','0')){$script:Answers.Enqueue($Answer)}
 $R=Invoke-RegistryOperationsMenu -BasePath $BasePath -Systems $Systems -ReachableSystems $Systems -OperationID RAWFAIL
 if($R.Rows[0].Status -ne 'Failed' -or $script:Writes.Count -ne $Before -or (Test-Path (Join-Path $BasePath 'RegistryRollback\RAWFAIL_Edit.csv'))){throw 'Failed raw backup must block all writes'}
 Write-Output 'PASS: typed edit/delete durable backups, CSV and list summaries, console/runner rollback, QWORD creation/removal, invalid input and raw-read failure guards.'
}finally{if((Split-Path $BasePath -Parent) -ne $env:TEMP){throw 'Unsafe cleanup'};if(Test-Path -LiteralPath $BasePath){Remove-Item -LiteralPath $BasePath -Recurse -Force}}
