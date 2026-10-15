$ErrorActionPreference='Stop';$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'RemoteOps.App\RemoteOps.RecipeResults.ps1')
function Assert($C,$M){if(-not $C){throw $M}}
$Cases=@(
 @('ServiceList',@{Status='NotFound'},'Continue'),@('ServiceControl',@{Status='NotFound'},'Stop'),
 @('RegistryRead',@{Status='NotFound';ReturnValue=2},'Continue'),@('RegistryEdit',@{Status='Success'},'Stop'),@('RegistryEdit',@{Status='Success';ReturnValue=0},'Continue'),
 @('FileCompare',@{Durum='Esit';HashEsit='True';SizeEsit='True';ModifiedEsit='True'},'Continue'),@('FileCompare',@{Durum='Farkli';HashEsit='True'},'Stop'),
 @('FilePush',@{Durum='Success';AtlananAdet=1},'Stop'),@('FilePush',@{Durum='Success';AtlananAdet=0},'Continue'),
 @('FileDelete',@{Durum='Success'},'Stop'),@('FileDelete',@{Durum='Success';BackupDurumu='Verified';BackupDogrulandi='Evet';KaynakStabil='Evet';SilmeSonKontrol='Verified'},'Continue')
)
foreach($Case in $Cases){$D=Get-RemoteOpsRecipeStepDecision $Case[0] @{} @([pscustomobject]$Case[1]) @();Assert ($D.Decision -eq $Case[2]) ('Wrong '+$Case[0])}
$D=Get-RemoteOpsRecipeStepDecision ServiceControl @{} @([pscustomobject]@{Status='Success'},[pscustomobject]@{Status='Failed'}) @();Assert ($D.Decision -eq 'Stop') 'Failed row hidden'
$D=Get-RemoteOpsRecipeStepDecision PackageDeployment @{} @([pscustomobject]@{Status='Skipped'}) @([pscustomobject]@{Outcome='Skipped';DecisionCode='AlreadyAbsent'});Assert ($D.Decision -eq 'Continue') 'Verified skip'
$D=Get-RemoteOpsRecipeStepDecision PackageDeployment @{} @([pscustomobject]@{Status='Skipped'}) @([pscustomobject]@{Outcome='Skipped';Detail='Application already absent.'});Assert ($D.Decision -eq 'Stop') 'Text inferred success'
$D=Get-RemoteOpsRecipeStepDecision PackageDeployment @{} @([pscustomobject]@{Status='Success';ExitCode=3010}) @([pscustomobject]@{Outcome='Success'});Assert ($D.Outcome -eq 'RebootRequired') 'Reboot lost'
Write-Host 'PASS explicit recipe continuation and failure/reboot precedence'
