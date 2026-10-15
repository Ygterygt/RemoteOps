$ErrorActionPreference='Stop'
$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Recovery.ps1')
function Assert($C,$M){if(-not $C){throw $M}}
function Reject([scriptblock]$A){$F=$false;try{& $A}catch{$F=$true};Assert $F 'Expected refusal'}
$t=$null;$e=$null;$Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.Runner.ps1'),[ref]$t,[ref]$e)
foreach($Name in 'New-TargetScopedManifest','Invoke-RegistryRollbackRequest','Invoke-ServiceTaskRollbackRequest','Invoke-RemoteOpsRecoveryRequest'){$F=$Ast.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq $Name},$true);if(-not $F){throw "Missing adapter $Name"};. ([scriptblock]::Create($F.Extent.Text))}
. (Join-Path $Root 'Modules\RegistryPaths.ps1');. (Join-Path $Root 'Modules\RegistryValues.ps1')
function New-CimSession {param($ComputerName,$SessionOption,$OperationTimeoutSec)$script:Connections++;[pscustomobject]@{ComputerName=$ComputerName}}
function New-CimSessionOption {param($Protocol)}
function Remove-CimSession {param($CimSession)}
function Invoke-CimMethod {param($CimSession,$Namespace,$ClassName,$MethodName,$Arguments)$script:Writes+=,[pscustomobject]@{Host=$CimSession.ComputerName;Method=$MethodName;Args=$Arguments};[pscustomobject]@{ReturnValue=0}}
function Write-ApplicationRows {param($Name,$Rows)$script:Rows=$Rows;'mock.csv'}
$BasePath=Join-Path $env:TEMP ('RecoveryRunner_'+[guid]::NewGuid().ToString('N'));$Systems=@('PC1');$OperationID='TEST';$OperationName='RegistryRollback';$script:Writes=@();$script:Connections=0
try{
 New-Item -ItemType Directory (Join-Path $BasePath 'RegistryRollback') -Force|Out-Null
 $Manifest=Join-Path $BasePath 'RegistryRollback\test.csv'
 @([pscustomobject]@{ComputerName='PC1';RegistryPath='HKU\S-1-5-21-1\Software\Example';RegistryKey='Software\Example';ValueName='Mode';OldExists='True';OldType='REG_QWORD';OldValue='18446744073709551615'},[pscustomobject]@{ComputerName='PC2';RegistryPath='HKLM\Software\Example';RegistryKey='Software\Example';ValueName='Mode';OldExists='True';OldType='REG_SZ';OldValue='other'})|Export-Csv $Manifest -Delimiter ';' -NoTypeInformation
 $Record=@((Get-RemoteOpsRecoveryIndex $BasePath).Records|Where-Object ComputerName -eq PC1)[0];$Request=New-RemoteOpsRecoveryRequest $BasePath $Record;$Values=$Request.Values;$Values.Confirm='ROLLBACK'
 Invoke-RemoteOpsRecoveryRequest $Values|Out-Null
 Assert ($script:Writes.Count -eq 1 -and $script:Writes[0].Host -eq 'PC1' -and $script:Writes[0].Method -eq 'SetQWORDValue' -and $script:Writes[0].Args.hDefKey -eq 2147483651 -and $script:Writes[0].Args.uValue -eq [uint64]::MaxValue) 'Exact host, SID and type'
 Assert ((Import-Csv $Manifest -Delimiter ';').Count -eq 2) 'Original manifest modified'
 $Before=$script:Connections;$Systems=@('PC2');Reject {Invoke-RemoteOpsRecoveryRequest $Values};Assert ($script:Connections -eq $Before) 'Mismatch opened remote connection'
 $Systems=@('PC1');$OperationName='FileRollback';Reject {Invoke-RemoteOpsRecoveryRequest $Values};Assert ($script:Writes.Count -eq 1) 'Operation mismatch mutated'
 $OperationName='RegistryRollback';$Values.Confirm='';Reject {Invoke-RemoteOpsRecoveryRequest $Values}
 $Values.Confirm='ROLLBACK';Add-Content $Manifest 'changed';Reject {Invoke-RemoteOpsRecoveryRequest $Values};Assert ($script:Writes.Count -eq 1) 'Stale data mutated'

 $script:FileCopies=@()
 function Copy-Item {param($LiteralPath,$Destination,[switch]$Force,[switch]$Recurse)$script:FileCopies+=,$Destination}
 $Tokens=$null;$Errors=$null;$FileAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'Modules\FileOperations.ps1'),[ref]$Tokens,[ref]$Errors)
 $F=$FileAst.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq 'Invoke-AORemoteFileRollback'},$true);. ([scriptblock]::Create($F.Extent.Text))
 $Dir=Join-Path $BasePath 'FileRollbacks\run';New-Item -ItemType Directory $Dir -Force|Out-Null;$Backup=Join-Path $Dir 'backup';Set-Content $Backup 'old'
 @([pscustomobject]@{ComputerName='PC1';Action='Replace';OriginalPath='\\PC1\C$\a';ChangedPath='';BackupPath=$Backup},[pscustomobject]@{ComputerName='PC1';Action='Replace';OriginalPath='\\PC1\C$\b';ChangedPath='';BackupPath=$Backup},[pscustomobject]@{ComputerName='PC2';Action='Replace';OriginalPath='\\PC2\C$\c';ChangedPath='';BackupPath=$Backup})|Export-Csv (Join-Path $Dir 'manifest.csv') -Delimiter ';' -NoTypeInformation
 $Record=@((Get-RemoteOpsRecoveryIndex $BasePath).Records|Where-Object{$_.ComputerName -eq 'PC1' -and $_.Kind -eq 'FileRollback'})[0]
 $Request=New-RemoteOpsRecoveryRequest $BasePath $Record;$Values=$Request.Values;$Values.Confirm='ROLLBACK';$OperationName='FileRollback'
 $Result=Invoke-RemoteOpsRecoveryRequest $Values
 Assert ($Result.ResultCsv -eq 'mock.csv' -and $script:Rows.Count -eq 2 -and $script:Rows[0] -isnot [array] -and $script:Rows[0].Status -eq 'Success') 'File rollback results lost in nested array'
 Assert ($script:FileCopies.Count -eq 2 -and @($script:FileCopies|Where-Object{$_ -like '\\PC2\*'}).Count -eq 0) 'File rollback escaped scope'

 $script:TaskWrites=0;$script:ValidationCalls=0
 function Get-ServiceTaskSession {param($ComputerName)[pscustomobject]@{ComputerName=$ComputerName}}
 function Enable-ScheduledTask {param($CimSession,$TaskName,$TaskPath)$script:TaskWrites++}
 function Disable-ScheduledTask {param($CimSession,$TaskName,$TaskPath)$script:TaskWrites++}
 $TaskEntry=[pscustomobject]@{ComputerName='PC1';ObjectType='ScheduledTask';ObjectName='Example';TaskName='Example';TaskPath='\';Action='EnableDisable';OldEnabled='True'}
 $Result=Invoke-ServiceTaskRollbackRequest @{ManifestPath=$Manifest} -RecoveryEntries @($TaskEntry) -RecoveryValidate {$script:ValidationCalls++;throw 'Stale manifest'}
 Assert ($script:TaskWrites -eq 0 -and $script:ValidationCalls -gt 0) 'Service/task stale callback skipped'

 # Actual CSV writer receives flat success/failure rows, preserving history inputs.
 $F=$Ast.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq 'Write-ApplicationRows'},$true);. ([scriptblock]::Create($F.Extent.Text))
 function Copy-Item {param($LiteralPath,$Destination,[switch]$Force,[switch]$Recurse)if($Destination.EndsWith('\b')){throw 'Fixture denied'};$script:FileCopies+=,$Destination}
 $OperationName='FileRollback';$Result=Invoke-RemoteOpsRecoveryRequest $Values
 $Saved=@(Import-Csv $Result.ResultCsv -Delimiter ';')
 Assert ($Saved.Count -eq 2 -and $Saved[0].ComputerName -eq 'PC1' -and $Saved[0].Status -eq 'Success' -and $Saved[1].Status -eq 'Failed' -and $Saved[1].ErrorDetail -eq 'Fixture denied') 'Actual rollback CSV lost outcomes'
 # Real task/service adapter, mocked remote calls, mixed manifest narrowed by kind.
 $Dir=Join-Path $BasePath 'ServiceTaskRollbacks';New-Item -ItemType Directory $Dir -Force|Out-Null
 $Xml=Join-Path $Dir 'task.xml';Set-Content $Xml '<Task xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"><Actions/></Task>'
 $TaskEntry=[pscustomobject]@{ComputerName='PC1';ObjectType='ScheduledTask';ObjectName='Example';TaskName='Example';TaskPath='\';Action='Delete';OldEnabled='True';BackupXml=$Xml;OldState=''}
 $ServiceEntry=[pscustomobject]@{ComputerName='PC1';ObjectType='Service';ObjectName='Spooler';TaskName='';TaskPath='';Action='StartStop';OldEnabled='';BackupXml='';OldState='Running'}
 @($TaskEntry,$ServiceEntry)|Export-Csv (Join-Path $Dir 'mixed.csv') -Delimiter ';' -NoTypeInformation
 $script:ExistingTask=$false;$script:Registrations=0;$script:LastMethod=''
 function Get-CimInstance {param($CimSession,$Namespace,$ClassName,$Filter)if($ClassName -eq 'Win32_Service'){[pscustomobject]@{Name='Spooler'}}elseif($script:ExistingTask){[pscustomobject]@{TaskName='Example';TaskPath='\'}}}
 function Register-ScheduledTask {param($CimSession,$TaskName,$TaskPath,$Xml)$script:Registrations++}
 function Invoke-CimMethod {param($CimSession,$InputObject,$MethodName,$Arguments)$script:LastMethod=$MethodName;[pscustomobject]@{ReturnValue=0}}
 $Record=@((Get-RemoteOpsRecoveryIndex $BasePath).Records|Where-Object Kind -eq Service)[0];$R=New-RemoteOpsRecoveryRequest $BasePath $Record;$OperationName='ServiceTaskRollback';$R.Values.Confirm='ROLLBACK'
 $Result=Invoke-RemoteOpsRecoveryRequest $R.Values;Assert ($script:LastMethod -eq 'StartService' -and $script:Registrations -eq 0) 'Mixed scope service mismatch'
 $Record=@((Get-RemoteOpsRecoveryIndex $BasePath).Records|Where-Object Kind -eq ScheduledTask)[0];$R=New-RemoteOpsRecoveryRequest $BasePath $Record;$R.Values.Confirm='ROLLBACK'
 $Result=Invoke-RemoteOpsRecoveryRequest $R.Values;Assert ($script:Registrations -eq 1) 'Task restore missing'
 $script:ExistingTask=$true;$Result=Invoke-RemoteOpsRecoveryRequest $R.Values;Assert ($script:Registrations -eq 1 -and (Import-Csv $Result.ResultCsv -Delimiter ';').Status -eq 'Failed') 'Existing task overwritten'
 # Selected delete-backup goes through the real restore copy loop.
 foreach($Name in 'Restore-AODeleteBackup','ConvertTo-AORemoteAdminPath'){$F=$FileAst.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq $Name},$true);. ([scriptblock]::Create($F.Extent.Text))}
 function Add-AOFileOperationRows {param($BasePath,$OperationName,$OperationID,$OperationDate,$OperationTime,$Rows,$TechnicalLogWriter,$OperationHistoryWriter)$script:RestoreRows=@($Rows);$P=Join-Path $BasePath 'restore.csv';$Rows|Export-Csv $P -Delimiter ';' -NoTypeInformation;return $P}
 function Test-Path {param($LiteralPath,$Path,$PathType)if($LiteralPath -and $LiteralPath.StartsWith('\\')){return $true};$A=@{};if($LiteralPath){$A.LiteralPath=$LiteralPath}else{$A.Path=$Path};if($PathType){$A.PathType=$PathType};Microsoft.PowerShell.Management\Test-Path @A}
 $Dir=Join-Path $BasePath 'DeleteBackups\run_Delete';New-Item -ItemType Directory $Dir -Force|Out-Null;$Backup=Join-Path $Dir 'a';Set-Content $Backup 'old'
 @([pscustomobject]@{ComputerName='PC1';OriginalPath='C:\a';BackupPath=$Backup;ItemType='File';BackupStatus='Success'},[pscustomobject]@{ComputerName='PC2';OriginalPath='C:\a';BackupPath=$Backup;ItemType='File';BackupStatus='Success'})|Export-Csv (Join-Path $Dir 'manifest.csv') -Delimiter ';' -NoTypeInformation
 $Record=@((Get-RemoteOpsRecoveryIndex $BasePath).Records|Where-Object{$_.Kind -eq 'FileRestore' -and $_.ComputerName -eq 'PC1'})[0];$R=New-RemoteOpsRecoveryRequest $BasePath $Record;$R.Values.Confirm='RESTORE';$OperationName='FileRestore';$OperationDate='2026-10-15';$OperationTime='12:00:00'
 $Result=Invoke-RemoteOpsRecoveryRequest $R.Values;Assert ($Result.ResultCsv -and $script:RestoreRows.Count -eq 1 -and $script:RestoreRows[0].IstemciAdi -eq 'PC1' -and $script:RestoreRows[0].Durum -eq 'Success') 'Delete backup scope/results incorrect'
 Write-Host 'PASS Recovery adapter exact scope and zero-write refusal'
}finally{if(Test-Path $BasePath){Remove-Item $BasePath -Recurse -Force}}
