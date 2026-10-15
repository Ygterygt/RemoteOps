$ErrorActionPreference='Stop';$Root=Split-Path $PSScriptRoot -Parent
$File=Join-Path $Root 'RemoteOps.App\RemoteOps.StepResults.ps1'
if(-not(Test-Path $File)){throw 'FAIL: readable step result view is missing'}
. $File
function Assert($Value,$Message){if(-not $Value){throw $Message}}
$Rows=@(
 [pscustomobject]@{StepIndex=1;StepName='Servisi başlat';Operation='ServiceControl';Status='Success';CommandStatus='Success';VerificationStatus='Failed';VerificationExpected='Running';VerificationObserved='Stopped';VerificationDetail='Beklenen sonuç yok';VerifiedAt='2026-10-16T10:00:00Z'},
 [pscustomobject]@{StepIndex=2;StepName='Dosyayı gönder';Operation='FilePush';Status='NotRun';ErrorDetail='Önceki adım durdu'},
 [pscustomobject]@{StepIndex=3;StepName='Diğer adım';Operation='ServiceList';Status='Skipped';ErrorDetail='Koşul sağlanmadı'}
)
$V=@(ConvertTo-RemoteOpsStepViews $Rows)
Assert ($V.Count -eq 3 -and $V[0].Name -ceq 'Servisi başlat') 'Name/order lost'
Assert ($V[0].Verification -ceq 'Beklenen sonuç oluşmadı' -and $V[0].Command -ceq 'Kabul edildi') 'Command and verification conflated'
Assert ($V[1].Result -ceq 'Çalıştırılmadı' -and $V[2].Result -ceq 'Atlandı') 'Skipped/notrun indistinguishable'
$Text=Get-RemoteOpsStepViewDetail $V[0]
Assert ($Text -like '*Running*' -and $Text -like '*Stopped*' -and $Text -like '*2026-10-16*') 'Expected/observed/time hidden'
$Old=@(ConvertTo-RemoteOpsStepViews @([pscustomobject]@{StepIndex=1;Operation='ServiceControl';Status='Success'}))
Assert ($Old[0].Verification -ceq 'Bu kayıtta otomatik doğrulama yok') 'Legacy success retroactively verified'
$Checks=@([pscustomobject]@{StepIndex=1;StepName='Ortak koşul';Operation='RecipeCondition';Status='Success';Matched=$true;Observed='A';StepResultReason='Koşul sağlandı.'},[pscustomobject]@{StepIndex=1;StepName='Ortak koşul';Operation='RecipeCondition';Status='Success';Matched=$false;Observed='B';StepResultReason='Koşul sağlandı.'})
$V=@(ConvertTo-RemoteOpsStepViews $Checks)
Assert ($V.Count -eq 1 -and $V[0].Reason -ceq 'Koşul sağlandı.' -and $V[0].SourceRows.Count -eq 2) 'Any condition summary recomputed incorrectly or original evidence lost'
Write-Output 'PASS readable step projection, command/verification split, legacy evidence, multi-check aggregation, detail'

$Rows[0]|Add-Member NoteProperty StepResultReason 'Komut kabul edildi; zincir durdu.'
$Rows[0].VerificationDetail='Readback denied'
$V=@(ConvertTo-RemoteOpsStepViews $Rows)
Assert ($V[0].Reason -like '*Readback denied*') 'Specific readback error hidden by generic recipe decision'
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.History.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Diagnostics.ps1')
$Diagnosis=Get-RemoteOpsDiagnosis ([pscustomobject]@{OperationID='SIM-RUN';Operation='RecipeRun'}) SIM-PC1 ([pscustomobject]@{Rows=@([pscustomobject]@{ComputerName='SIM-PC1';Status='Success';VerificationStatus='Failed';VerificationDetail='Readback denied'});Targets=@([pscustomobject]@{ComputerName='SIM-PC1';Outcome='Error';Detail=''})})
Assert ($Diagnosis.Category -ceq 'Verification' -and $Diagnosis.NextAction -notlike '*uygulama kimliğini*') 'Service verification failure got package-only advice'

$V=@(ConvertTo-RemoteOpsStepViews @([pscustomobject]@{StepIndex=1;Operation='ServiceControl';Status='Failed';StepResultReason='Adım durdu.';ErrorDetail='Access denied'}))
Assert ($V[0].Reason -like '*Access denied*') 'Original command error hidden'
