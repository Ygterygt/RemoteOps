$ErrorActionPreference='Stop'
$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Recovery.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.History.ps1')
function Assert($C,$M){if(-not $C){throw $M}}
$Base=Join-Path $env:TEMP ('RemoteOpsV20-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $Base|Out-Null
$Text='<?xml version="1.0" encoding="UTF-16"?><Task xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"><RegistrationInfo><Description>Turkish character: &#305;</Description></RegistrationInfo><Actions/></Task>'
$Text=$Text.Replace('&#305;',[string][char]305)
$Path=Join-Path $Base 'legacy.xml'
[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($true)))
$TaskRoot=Join-Path $Base 'ServiceTaskRollbacks'
New-Item -ItemType Directory $TaskRoot|Out-Null
$Stored=Join-Path $TaskRoot 'legacy.xml';[IO.File]::WriteAllText($Stored,$Text,(New-Object Text.UTF8Encoding($true)))
[pscustomobject]@{ComputerName='PC1';ObjectType='ScheduledTask';ObjectName='Example';TaskName='Example';TaskPath='\';Action='Delete';OldEnabled='True';BackupXml=$Stored}|Export-Csv (Join-Path $TaskRoot 'run.csv') -Delimiter ';' -NoTypeInformation
$Index=Get-RemoteOpsRecoveryIndex $Base
Assert (@($Index.Records|Where-Object {$_.Kind -eq 'ScheduledTask' -and $_.Available}).Count -eq 1) 'Legacy task not available in recovery center'
$Hash=(Get-FileHash $Path).Hash
$Xml=Read-RemoteOpsRecoveryTaskXml $Path
Assert (([xml]$Xml).Task.RegistrationInfo.Description.Contains([string][char]305)) 'Legacy mismatch lost text'
Assert ((Get-FileHash $Path).Hash -eq $Hash) 'Reading changed backup'
[IO.File]::WriteAllText($Path,$Text,[Text.Encoding]::Unicode)
Assert ((Read-RemoteOpsRecoveryTaskXml $Path).Contains('Task')) 'Real UTF16 rejected'
[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))
Assert ((Read-RemoteOpsRecoveryTaskXml $Path).Contains('Task')) 'BOMless UTF8 rejected'
Write-RemoteOpsRecoveryTaskXml -Path $Path -Text $Text
$Doc=New-Object Xml.XmlDocument;$Doc.Load($Path)
Assert ($Doc.DocumentElement.LocalName -eq 'Task') 'New backup invalid'
[IO.File]::WriteAllText($Path,'<!DOCTYPE Task [<!ENTITY x SYSTEM "file:///C:/secret">]><Task>&x;</Task>',(New-Object Text.UTF8Encoding($true)))
$Rejected=$false;try{Read-RemoteOpsRecoveryTaskXml $Path}catch{$Rejected=$true};Assert $Rejected 'DTD accepted'
$Rejected=$false;try{Write-RemoteOpsRecoveryTaskXml $Path '<Other/>'}catch{$Rejected=$true};Assert $Rejected 'Wrong root accepted'
$Run=[pscustomobject]@{OperationID='GUI-123';Operation='PackageDeployment';CompletedAt='2026-10-15 13:58:32';PackageName='Example package'}
$Label=Get-RemoteOpsDiagnosisRunLabel $Run
Assert ($Label.Contains('15.10.2026 13:58:32') -and $Label.Contains('Example package') -and -not $Label.Contains('GUI-123')) 'Diagnosis label unreadable'
$Ui=Get-Content (Join-Path $Root 'RemoteOps.App\RemoteOps.HistoryUi.ps1') -Raw -Encoding UTF8
Assert ($Ui.Contains('DisplayMemberPath="DiagnosisLabel"')) 'Picker binding incorrect'
Write-Host 'PASS v20 legacy/new XML, Unicode, no mutation, DTD and diagnosis labels'
