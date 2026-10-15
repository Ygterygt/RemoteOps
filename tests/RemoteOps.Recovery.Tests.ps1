$ErrorActionPreference='Stop'
$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Recovery.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action){$Failed=$false;try{& $Action}catch{$Failed=$true};Assert $Failed 'Expected rejection'}
$Base=Join-Path $env:TEMP ('RecoveryTests_'+[guid]::NewGuid().ToString('N'))
try{
 foreach($Folder in @('DeleteBackups\run_Delete\PC-IST-001','FileRollbacks\run\PC-IST-001','RegistryRollback','ServiceTaskRollbacks\run')){New-Item -ItemType Directory (Join-Path $Base $Folder) -Force|Out-Null}
 $Backup=Join-Path $Base 'DeleteBackups\run_Delete\PC-IST-001\a.txt';Set-Content $Backup 'old'
 @([pscustomobject]@{ComputerName='PC-IST-001';OriginalPath='C:\data\a.txt';BackupPath=$Backup;ItemType='File';BackupStatus='Success'},[pscustomobject]@{ComputerName='PC2';OriginalPath='C:\data\a.txt';BackupPath=$Backup;ItemType='File';BackupStatus='Success'})|Export-Csv (Join-Path $Base 'DeleteBackups\run_Delete\manifest.csv') -Delimiter ';' -NoTypeInformation
 $Fb=Join-Path $Base 'FileRollbacks\run\PC-IST-001\a.txt';Set-Content $Fb 'old'
 [pscustomobject]@{ComputerName='PC-IST-001';Action='Replace';OriginalPath='\\PC-IST-001\C$\data\a.txt';ChangedPath='';BackupPath=$Fb}|Export-Csv (Join-Path $Base 'FileRollbacks\run\manifest.csv') -Delimiter ';' -NoTypeInformation
 @([pscustomobject]@{ComputerName='PC-IST-001';RegistryKey='Software\Example';ValueName='a';OldExists='True';OldValue='18446744073709551615';OldType='REG_QWORD'},[pscustomobject]@{ComputerName='PC2';RegistryKey='Software\Example';ValueName='b';OldExists='False';OldValue='';OldType=''})|Export-Csv (Join-Path $Base 'RegistryRollback\run.csv') -Delimiter ';' -NoTypeInformation
 $Xml=Join-Path $Base 'ServiceTaskRollbacks\run\task.xml';Set-Content $Xml '<Task xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"><Actions/></Task>'
 @([pscustomobject]@{ComputerName='PC-IST-001';ObjectType='Service';ObjectName='Spooler';Action='StartStop';OldState='Running';TaskName='';TaskPath='';BackupXml='';OldEnabled=''},[pscustomobject]@{ComputerName='PC-IST-001';ObjectType='ScheduledTask';ObjectName='Example';Action='Delete';OldState='';TaskName='Example';TaskPath='\';BackupXml=$Xml;OldEnabled='True'})|Export-Csv (Join-Path $Base 'ServiceTaskRollbacks\run.csv') -Delimiter ';' -NoTypeInformation
 $Index=Get-RemoteOpsRecoveryIndex $Base
 Assert ($Index.Records.Count -eq 7) 'All scopes indexed'
 Assert (@($Index.Records|Where-Object Available).Count -eq 7) 'All fixtures available'
 $Record=@($Index.Records|Where-Object{ $_.Kind -eq 'Registry' -and $_.ComputerName -eq 'PC-IST-001'})[0]
 $Request=New-RemoteOpsRecoveryRequest $Base $Record
 $Checked=Assert-RemoteOpsRecoverySelection $Base $Request.Selection @('PC-IST-001')
 Assert ($Checked.Entries.Count -eq 1 -and $Checked.Entries[0].OldValue -eq '18446744073709551615') 'Exact typed scope'
 Reject {Assert-RemoteOpsRecoverySelection $Base $Request.Selection @('PC2')}
 Assert ((Find-RemoteOpsRecoveryRecords $Index.Records -Computer 'PC' -PageSize 2).Items.Count -eq 2) 'Paging'
 Assert ((Find-RemoteOpsRecoveryRecords $Index.Records -Computer '*').Total -eq 0) 'Literal filter'
 $Again=Get-RemoteOpsRecoveryIndex $Base;Assert (@($Again.Records|Where-Object Id -eq $Record.Id).Count -eq 1) 'Stable identity'
 Add-Content $Record.ManifestPath 'changed'
 Reject {Assert-RemoteOpsRecoverySelection $Base $Request.Selection @('PC-IST-001')}
 Remove-Item $Backup
 $Index=Get-RemoteOpsRecoveryIndex $Base
 Assert (@($Index.Records|Where-Object{ $_.Kind -eq 'FileRestore' -and -not $_.Available}).Count -eq 2) 'Missing backup visible'
 Set-Content $Xml '<!DOCTYPE Task [<!ENTITY x SYSTEM "file:///C:/secret">]><Task>&x;</Task>'
 Assert (@((Get-RemoteOpsRecoveryIndex $Base).Records|Where-Object{ $_.Kind -eq 'ScheduledTask' -and -not $_.Available}).Count -eq 1) 'DTD rejected'
 $Bad=Join-Path $Base 'RegistryRollback\missing-value.csv'
 [pscustomobject]@{ComputerName='PC2';RegistryKey='Software\Example';ValueName='bad';OldExists='True'}|Export-Csv $Bad -Delimiter ';' -NoTypeInformation
 Assert (@((Get-RemoteOpsRecoveryIndex $Base).Records|Where-Object{$_.ManifestPath -eq $Bad -and -not $_.Available}).Count -eq 1) 'Missing OldValue must not become empty string'

 Assert-RemoteOpsRecoveryRemotePath 'I:\data\file' 'PC-IST-001' -DrivePath
 Assert-RemoteOpsRecoveryRemotePath '\\PC-IST-001\I$\data\file' 'PC-IST-001'
 Reject {Assert-RemoteOpsRecoveryRemotePath '\\PC2\C$\a' 'PC-IST-001'}
 Reject {Assert-RemoteOpsRecoveryRemotePath 'C:\data\..\secret' 'PC-IST-001' -DrivePath}
 Reject {Assert-RemoteOpsRecoveryLocalPath $Fb (Join-Path $Base 'DeleteBackups')}
 $Typed=Join-Path $Base 'RegistryRollback\typed.csv'
 @([pscustomobject]@{ComputerName='PC-IST-001';RegistryPath='HKU\S-1-5-21-1\Software\Example';RegistryKey='Software\Example';ValueName='empty';OldExists='True';OldType='REG_SZ';OldValue=''},[pscustomobject]@{ComputerName='PC-IST-001';RegistryPath='HKU\S-1-5-21-1\Software\Example';RegistryKey='Software\Example';ValueName='multi';OldExists='True';OldType='REG_MULTI_SZ';OldValue='["one","two"]'})|Export-Csv $Typed -Delimiter ';' -NoTypeInformation
 $R=@((Get-RemoteOpsRecoveryIndex $Base).Records|Where-Object ManifestPath -eq $Typed)[0]
 Assert ($R.Available -and $R.EntryKeys.Count -eq 2) 'Empty strings/MULTI_SZ/SID valid'
 $Rows=@(Import-Csv $Typed -Delimiter ';');$Keys=@($R.EntryKeys)
 @($Rows[1],$Rows[0])|Export-Csv $Typed -Delimiter ';' -NoTypeInformation
 $R2=@((Get-RemoteOpsRecoveryIndex $Base).Records|Where-Object ManifestPath -eq $Typed)[0]
 Assert ($R.Id -eq $R2.Id -and ($Keys -join '|') -eq ($R2.EntryKeys -join '|')) 'Identity changed on row reorder'
 @($Rows[0],$Rows[0])|Export-Csv $Typed -Delimiter ';' -NoTypeInformation
 Assert (-not @((Get-RemoteOpsRecoveryIndex $Base).Records|Where-Object ManifestPath -eq $Typed)[0].Available) 'Duplicate rows accepted'
 $Index=Get-RemoteOpsRecoveryIndex $Base
 Assert ((Find-RemoteOpsRecoveryRecords $Index.Records -From ([datetime]::Today.AddDays(1))).Total -eq 0) 'Date range ignored'
 $Junction=Join-Path $Base 'FileRollbacks\run\link'
 New-Item -ItemType Junction -Path $Junction -Target (Join-Path $Base 'DeleteBackups\run_Delete')|Out-Null
 try{Reject {Assert-RemoteOpsRecoveryLocalPath (Join-Path $Junction 'PC-IST-001') (Join-Path $Base 'FileRollbacks') -Directory}}finally{[IO.Directory]::Delete($Junction)}
 Write-Host 'PASS Recovery index, scope, typed values, stale selection, missing backups, XML'
}finally{if(Test-Path $Base){Remove-Item $Base -Recurse -Force}}
