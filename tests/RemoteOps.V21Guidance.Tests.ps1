$ErrorActionPreference='Stop'
$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Packages.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.History.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Diagnostics.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Recovery.ps1')
function Assert($C,$M){if(-not $C){throw $M}}
$Run=[pscustomobject]@{OperationID='RUN';Operation='PackageDeployment'}
foreach($Case in @(@('Skipped','Target or newer version already installed.'),@('Skipped','other skip'),@('Indeterminate','timeout'),@('Error','access denied'),@('Success','done'),@('Error','unrecognized error'))){
 $D=Get-RemoteOpsDiagnosis $Run 'PC1' ([pscustomobject]@{Rows=@([pscustomobject]@{ComputerName='PC1';Status=$Case[0];ErrorDetail=$Case[1]});Targets=@([pscustomobject]@{ComputerName='PC1';Outcome=$Case[0];Detail=''})})
 Assert ([bool]$D.Reason -and [bool]$D.NextAction) 'Missing plain-language guidance'
 if($Case[1] -eq 'other skip'){Assert (-not $D.Reason.Contains('sürüm')) 'Generic skip guessed a version cause'}
 if($Case[1] -like 'Target or*'){Assert ($D.Reason.Contains('sürüm')) 'Known skip not explained'}
}
$D=Get-RemoteOpsDiagnosis $Run 'PC1' ([pscustomobject]@{Rows=@([pscustomobject]@{ComputerName='PC1';Status='Success';ExitCode='3010';ErrorDetail=''});Targets=@([pscustomobject]@{ComputerName='PC1';Outcome='Success';Detail=''})})
Assert ($D.NextAction.Contains('yeniden başlatma')) 'Successful reboot code lost next action'
$Base=Join-Path $env:TEMP ('RemoteOpsV21-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $Base|Out-Null
$Record=[pscustomobject]@{Id='REC';ManifestHash='HASH';BackupStamp='STAMP';ComputerName='PC1';Kind='ScheduledTask';EntryKeys=@('ONE');Available=$true;UnavailableReason=''}
$S=Get-RemoteOpsRecoveryPresentation $Base $Record
Assert ($S.LocalLabel -eq 'Yerel yedek hazır' -and $S.HistoryLabel.Contains('yok') -and $S.LiveLabel.Contains('sorgulanmadı')) 'No evidence confused with live state'
$Folder=Join-Path $Base 'Logs\Operations\ServiceTaskRollback\RUN';New-Item -ItemType Directory $Folder -Force|Out-Null
$Selection=[pscustomobject]@{RecordId='REC';ManifestHash='HASH';BackupStamp='STAMP';ComputerName='PC1';Kind='ScheduledTask';EntryKeys=@('ONE')}
$Result=[pscustomobject]@{Rows=@([pscustomobject]@{ComputerName='PC1';Status='Success'})}
Write-RemoteOpsRecoveryReceipt $Folder $Selection $Result 'RUN'
$S=Get-RemoteOpsRecoveryPresentation $Base $Record
Assert ($S.HistoryLabel.Contains('başarılı') -and $S.LiveLabel.Contains('sorgulanmadı')) 'Receipt not shown as local history'
$Result.Rows[0].Status='Failed';Write-RemoteOpsRecoveryReceipt $Folder $Selection $Result 'RUN'
$S=Get-RemoteOpsRecoveryPresentation $Base $Record
Assert ($S.HistoryLabel.Contains('tam başarı doğrulanamadı')) 'Failed attempt still shown successful'
$Selection.ComputerName='PC2';Write-RemoteOpsRecoveryReceipt $Folder $Selection $Result 'RUN'
$S=Get-RemoteOpsRecoveryPresentation $Base $Record
Assert ($S.HistoryLabel.Contains('yok')) 'Another computer leaked into history'
$Selection.ComputerName='PC1';$Result.Rows=@();Write-RemoteOpsRecoveryReceipt $Folder $Selection $Result 'RUN'
$S=Get-RemoteOpsRecoveryPresentation $Base $Record
Assert ($S.HistoryLabel.Contains('tam başarı doğrulanamadı')) 'Empty results became successful'
$Selection.ComputerName='PC1';$Result.Rows=@([pscustomobject]@{IstemciAdi='PC1';Durum='Success'})
Write-RemoteOpsRecoveryReceipt $Folder $Selection $Result 'RUN'
$S=Get-RemoteOpsRecoveryPresentation $Base $Record
Assert ($S.HistoryLabel.Contains('başarılı')) 'FileRestore Turkish result schema not recognized'
$Record.ManifestHash='CHANGED';$S=Get-RemoteOpsRecoveryPresentation $Base $Record
Assert ($S.HistoryLabel.Contains('yok')) 'Changed manifest inherited earlier receipt'
$Record.Available=$false;$Record.UnavailableReason='Required backup or manifest is missing.'
$S=Get-RemoteOpsRecoveryPresentation $Base $Record
Assert ($S.LocalLabel.Contains('eksik')) 'Missing backup not explained'
Write-Host 'PASS v21 diagnosis guidance, scoped recovery receipt, local/live distinction'
