$ErrorActionPreference='Stop'
$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'RemoteOps.App\RemoteOps.RecipeExecution.ps1')
function Assert($C,$M){if(-not $C){throw $M}}
function Reject([scriptblock]$Work){$Rejected=$false;try{& $Work}catch{$Rejected=$true};Assert $Rejected 'Expected rejection'}
$Base=Join-Path $env:TEMP ('AutoExec-'+[guid]::NewGuid().ToString('N'))
$D=New-RemoteOpsRecipeDefinition 'Automatic value';$D.Schema='RemoteOps.Recipe/3';$D.Revision=1
$C=[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Version';Operation='RecipeCondition';Values=[pscustomobject]@{Match='All';OnFalse='Skip';Checks=@([pscustomobject]@{Kind='RegistryValue';Path='HKLM\SOFTWARE\Fixture';Name='Version';Operator='Equals';ExpectedType='Auto';Expected='16.0.444'})}}
$D.Steps=@($C,[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Start';Operation='ServiceControl';ConditionId=$C.Id;Values=@{ServiceName='Spooler';Action='Start'}})
Assert-RemoteOpsRecipeDefinition $D
$Legacy=Copy-RemoteOpsRecipeDefinition $D;$Legacy.Schema='RemoteOps.Recipe/2';Reject {Assert-RemoteOpsRecipeDefinition $Legacy}
$Legacy.Steps[0].Values.Checks[0].ExpectedType='REG_SZ';Assert-RemoteOpsRecipeDefinition $Legacy
$Profile=[pscustomobject]@{Domain='TEST';UserName='operator';IsMain=$true}
$S=New-RemoteOpsRecipeRunSnapshot $D @('PC1','PC2','PC3','PC4') $Profile $false
$script:Mutations=@()
$Invoke={param($Request)
 if($Request.Operation -eq 'RecipeCondition'){
  $Values=$Request.Worker.Snapshot.Definition.Steps[$Request.Worker.StepIndex-1].Values
  $Checked=Invoke-RemoteOpsConditionChecks $Values $Request.Targets[0] $Request.Worker.StepOperationID -Probe {param($Check,$ComputerName)
   if($ComputerName -eq 'PC4'){throw 'fixture access denied'}
   [pscustomobject]@{Exists=$true;ValueType=$(if($ComputerName -eq 'PC3'){'REG_DWORD'}else{'REG_SZ'});Value=$(switch($ComputerName){PC1{'16.0.444'}PC2{'16.0.333'}PC3{'1'}});State='';Startup='';Detail='fixture'}
  }
  $Rows=@($Checked.Rows)
 }else{$script:Mutations+=$Request.Targets[0];$Rows=@([pscustomobject]@{ComputerName=$Request.Targets[0];OperationID=$Request.Worker.StepOperationID;Status='Success'})}
 New-RemoteOpsRecipeStepResult $Request $Rows @()
}
$R=Invoke-RemoteOpsRecipeRun $S 'GUI-20261015-120020-ABCDEF' $Base '' (Join-Path $Base 'state') $Invoke
Assert (($script:Mutations -join ',') -eq 'PC1') 'Auto version gated wrong target'
Assert (@($R.Rows|Where-Object Status -eq Skipped).Count -eq 2) 'Known nonmatches not recorded as skips'
Assert ($R.Outcomes[3].Outcome -eq 'Error') 'Read error treated as a nonmatch'
$D.Steps[0].Values.Checks[0].Expected='1';$S=New-RemoteOpsRecipeRunSnapshot $D @('PC1','PC3') $Profile $false;$script:Mutations=@()
$R=Invoke-RemoteOpsRecipeRun $S 'GUI-20261015-120021-ABCDEF' $Base '' (Join-Path $Base 'state2') $Invoke
Assert (($script:Mutations -join ',') -eq 'PC3') 'Auto numeric condition failed'
$Saved=Save-RemoteOpsRecipeDefinition (Join-Path $Base 'catalog') $D 0
Assert ($Saved.Schema -eq 'RemoteOps.Recipe/3' -and $Saved.Steps[0].Values.Checks[0].ExpectedType -eq 'Auto') 'Auto roundtrip lost interpretation'
Write-Output 'PASS v25 schema3, legacy schema2, auto version/numeric per-target gate, strict evidence and read error stop'
