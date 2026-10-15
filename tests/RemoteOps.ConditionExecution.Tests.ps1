$ErrorActionPreference='Stop'
$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'RemoteOps.App\RemoteOps.RecipeExecution.ps1')
function Assert($C,$M){if(-not $C){throw $M}}
function Reject([scriptblock]$Work){$Rejected=$false;try{& $Work}catch{$Rejected=$true};Assert $Rejected 'Expected rejection'}
$Base=Join-Path $env:TEMP ('ConditionsExec-'+[guid]::NewGuid().ToString('N'))
$D=New-RemoteOpsRecipeDefinition 'Conditional recipe';$D.Schema='RemoteOps.Recipe/2';$D.Revision=1
$Condition=[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Stopped service';Operation='RecipeCondition';Values=[pscustomobject]@{Match='All';OnFalse='Skip';Checks=@([pscustomobject]@{Kind='Service';Path='';Name='Spooler';Operator='State';ExpectedType='';Expected='Stopped'})}}
$D.Steps=@($Condition,[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Start';Operation='ServiceControl';ConditionId=$Condition.Id;Values=@{ServiceName='Spooler';Action='Start'}},[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Always list';Operation='ServiceList';Values=@{Filter=''}})
Assert-RemoteOpsRecipeDefinition $D
$Forged=Get-RemoteOpsRecipeStepDecision 'RecipeCondition' $Condition.Values @([pscustomobject]@{Status='Success';CheckIndex=1;Matched=$true}) @()
Assert ($Forged.Decision -eq 'Stop') 'Condition accepted missing check evidence'
$Evidence=Invoke-RemoteOpsConditionChecks $Condition.Values 'PC1' 'STEP1' -Probe {param($Check,$ComputerName)[pscustomobject]@{Exists=$true;ValueType='';Value='';State='Running';Startup='Automatic';Detail='fixture'}}
$Evidence.Rows[0].Matched=$true
Assert ((Get-RemoteOpsRecipeStepDecision 'RecipeCondition' $Condition.Values @($Evidence.Rows) @()).Decision -eq 'Stop') 'Forged match overrode observed state'
$Evidence.Rows[0].Matched=$false;$Evidence.Rows[0].Name='OtherService'
Assert ((Get-RemoteOpsRecipeStepDecision 'RecipeCondition' $Condition.Values @($Evidence.Rows) @()).Decision -eq 'Stop') 'Evidence from different service accepted'
$Copy=Copy-RemoteOpsRecipeDefinition $D -NewIdentity;Assert ($Copy.Steps[1].ConditionId -eq $Copy.Steps[0].Id -and $Copy.Steps[0].Id -ne $Condition.Id) 'Copy lost condition scope'
$Bad=Copy-RemoteOpsRecipeDefinition $D;$Bad.Steps[1].ConditionId=[guid]::NewGuid().ToString();Reject {Assert-RemoteOpsRecipeDefinition $Bad}
$Bad=Copy-RemoteOpsRecipeDefinition $D;$Bad.Steps=@($Bad.Steps[0],$Bad.Steps[2],$Bad.Steps[1]);Reject {Assert-RemoteOpsRecipeDefinition $Bad}
$S=New-RemoteOpsRecipeRunSnapshot $D @('PC1','PC2') ([pscustomobject]@{Domain='TEST';UserName='operator';IsMain=$true}) $false
$script:Calls=@()
$Invoke={param($Request)
 $script:Calls+=($Request.Targets[0]+'|'+$Request.Operation)
 $Rows=if($Request.Operation -eq 'RecipeCondition'){
  $Checked=Invoke-RemoteOpsConditionChecks $Request.Worker.Snapshot.Definition.Steps[$Request.Worker.StepIndex-1].Values $Request.Targets[0] $Request.Worker.StepOperationID -Probe {param($Check,$ComputerName)[pscustomobject]@{Exists=$true;ValueType='';Value='';State=$(if($ComputerName -eq 'PC2'){'Stopped'}else{'Running'});Startup='Automatic';Detail='fixture'}}
  @($Checked.Rows)
 }else{@([pscustomobject]@{ComputerName=$Request.Targets[0];OperationID=$Request.Worker.StepOperationID;Status='Success'})}
 New-RemoteOpsRecipeStepResult $Request $Rows @()
}
$Run=Invoke-RemoteOpsRecipeRun $S 'GUI-20261015-120000-ABCDEF' $Base '' (Join-Path $Base 'state') $Invoke
Assert (($script:Calls -join ',') -eq 'PC1|RecipeCondition,PC1|ServiceList,PC2|RecipeCondition,PC2|ServiceControl,PC2|ServiceList') 'Wrong per-target conditional dispatch'
Assert (@($Run.Rows|Where-Object {$_.Status -eq 'Skipped'}).Count -eq 1) 'False condition did not record skipped action'
$D.Steps[0].Values.OnFalse='Stop';$S=New-RemoteOpsRecipeRunSnapshot $D @('PC1') ([pscustomobject]@{Domain='TEST';UserName='operator';IsMain=$true}) $false;$script:Calls=@()
$Run=Invoke-RemoteOpsRecipeRun $S 'GUI-20261015-120001-ABCDEF' $Base '' (Join-Path $Base 'state-stop') $Invoke
Assert ($script:Calls.Count -eq 1 -and $Run.Outcomes[0].Outcome -eq 'Skipped') 'False stop continued target'
$Req=New-RemoteOpsRecipeStepRequest $S 'GUI-20261015-120001-ABCDEF' 1 1 $Base
$Req.Values.Checks[0].Expected='Running';Reject {Assert-RemoteOpsRecipeWorkerRequest $Req $Base}
Write-Output 'PASS v24 condition schema, copy links, contiguous scope, per-target gating, skip/stop and snapshot tampering'
