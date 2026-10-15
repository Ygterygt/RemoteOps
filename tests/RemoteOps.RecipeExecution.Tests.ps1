$ErrorActionPreference='Stop';$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'RemoteOps.App\RemoteOps.RecipeExecution.ps1')
function Assert($C,$M){if(-not $C){throw $M}}
$Base=Join-Path $env:TEMP ('RecipeExec_'+[guid]::NewGuid().ToString('N'))
try{
 $D=New-RemoteOpsRecipeDefinition 'Pilot';$D.Revision=1;$D.Steps=@(1..2|ForEach-Object{[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name=('Step'+$_);Operation='ServiceControl';Values=@{ServiceName='Spooler';Action='Start'}}})
 $S=New-RemoteOpsRecipeRunSnapshot $D @('PC1','PC2') ([pscustomobject]@{Domain='TEST';UserName='operator';IsMain=$true}) $false
 $script:Calls=@();$script:Fail=$true
 $Run=Invoke-RemoteOpsRecipeRun $S 'GUI-20261015-120000-ABCDEF' $Base '' (Join-Path $Base 'state') {param($Request)
  $script:Calls+=($Request.Targets[0]+'-'+$Request.Worker.StepIndex)
  $Rows=@([pscustomobject]@{ComputerName=$Request.Targets[0];OperationID=$Request.Worker.StepOperationID;Status=$(if($script:Fail -and $Request.Targets[0] -eq 'PC1'){'Failed'}else{'Success'})})
  New-RemoteOpsRecipeStepResult $Request $Rows @()
 } {param($State)}
 Assert (($script:Calls -join ',') -eq 'PC1-1,PC2-1,PC2-2') 'Wrong order/failure continuation'
 Assert ($Run.Outcomes.Count -eq 2 -and $Run.Outcomes[0].Outcome -eq 'Error' -and $Run.Outcomes[1].Outcome -eq 'Completed') 'Terminal targets'
 Assert (@($Run.Rows|Where-Object Status -eq NotRun).Count -eq 1) 'NotRun missing'
 $Request=New-RemoteOpsRecipeStepRequest $S 'GUI-20261015-120000-ABCDEF' 1 1 $Base
 $V=Assert-RemoteOpsRecipeWorkerRequest $Request $Base;Assert ($V.StepOperationID -eq 'GUI-20261015-120000-ABCDEF-0001-S01') 'Exact ID'
 $Request.Values.ServiceName='Other';$Failed=$false;try{Assert-RemoteOpsRecipeWorkerRequest $Request $Base}catch{$Failed=$true};Assert $Failed 'Tampered step accepted'
 $Cancel=Join-Path $Base 'cancel';Set-Content $Cancel 'cancel';$script:Calls=@()
 $Run=Invoke-RemoteOpsRecipeRun $S 'GUI-20261015-120001-ABCDEF' $Base $Cancel (Join-Path $Base 'state2') {throw 'Should not dispatch'} {param($State)}
 Assert ($Run.Outcomes.Count -eq 2 -and @($Run.Outcomes|Where-Object Outcome -ne Cancelled).Count -eq 0) 'Cancel before start'

 Assert ((Get-Command Invoke-RemoteOpsRecipeStepWorker).Parameters.ContainsKey('StartWorker')) 'Timeout tracking test seam absent'
 $Req=New-RemoteOpsRecipeStepRequest $S 'GUI-20261015-120003-ABCDEF' 1 1 $Base
 New-Item -ItemType Directory $Req.Worker.ReportRoot -Force|Out-Null
 $Payload=New-RemoteOpsRecipeStepResult $Req @([pscustomobject]@{ComputerName='PC1';OperationID=$Req.Worker.StepOperationID;Status='Success'}) @()
 Write-RemoteOpsAtomicJson $Req.Worker.ResultPath $Payload 20
 $script:FakeTicks=0;$script:FakeProcess=[pscustomobject]@{HasExited=$false};$script:FakeProcess|Add-Member -MemberType ScriptMethod -Name Refresh -Value {}; $script:FakeProcess|Add-Member -MemberType ScriptMethod -Name Dispose -Value {}
 $Late=Invoke-RemoteOpsRecipeStepWorker $Req 'fixture.ps1' '' 0 -StartWorker {param($Engine,$Args,$Folder)$script:FakeProcess} -WaitTick {$script:FakeTicks++;if($script:FakeTicks -ge 3){$script:FakeProcess.HasExited=$true}}
 Assert ($script:FakeTicks -eq 3 -and $Late.StopRun) 'Timed-out child detached before exit'
 $script:LateCalls=0
 $Stopped=Invoke-RemoteOpsRecipeRun $S 'GUI-20261015-120004-ABCDEF' $Base '' (Join-Path $Base 'late-state') {param($Request)$script:LateCalls++;$R=New-RemoteOpsRecipeStepResult $Request @([pscustomobject]@{ComputerName=$Request.Targets[0];OperationID=$Request.Worker.StepOperationID;Status='Success'}) @();Add-Member -InputObject $R -NotePropertyName StopRun -NotePropertyValue $true;$R} {param($State)}
 Assert ($script:LateCalls -eq 1 -and $Stopped.Outcomes.Count -eq 2) 'Timeout allowed more dispatch'
 # Real parent Runner and child processes; all remote boundaries replaced in the isolated copy.
 $Fixture=Join-Path $Base 'fixture';New-Item -ItemType Directory $Fixture -Force|Out-Null
 Copy-Item (Join-Path $Root 'RemoteOps.App') $Fixture -Recurse;Copy-Item (Join-Path $Root 'Modules') $Fixture -Recurse
 $Data=Join-Path $Base 'data';$MutationLog=Join-Path $Base 'mutations.txt'
 $Runner=Join-Path $Fixture 'RemoteOps.App\RemoteOps.Runner.ps1';$Source=[IO.File]::ReadAllText($Runner)
 $Source=$Source.Replace('$BasePath = ''C:\Temp\YD_RemoteOps.App''',('$BasePath = '''+$Data+''''))
 $Mocks=@'
    function Test-RemoteOpsOperationAccess {param($ComputerName,$Operation,$InputValues) [pscustomobject]@{Status='Success';Detail='Fixture'}}
    function New-CimSessionOption {param($Protocol)}
    function New-CimSession {param($ComputerName,$SessionOption,$OperationTimeoutSec) [pscustomobject]@{ComputerName=$ComputerName}}
    function Remove-CimSession {param($CimSession)}
    function Get-CimInstance {param($CimSession,$ClassName,$Filter,$Namespace) [pscustomobject]@{Name='Spooler';DisplayName='Spooler';State='Running';StartMode='Auto'}}
    function Invoke-CimMethod {param($CimSession,$InputObject,$MethodName,$Arguments) Add-Content -LiteralPath '__MUTATION_LOG__' ($CimSession.ComputerName+'|'+$MethodName);[pscustomobject]@{ReturnValue=0}}
'@
 $Source=$Source.Replace('    # Mod 4 (normal):',$Mocks.Replace('__MUTATION_LOG__',$MutationLog)+"`r`n"+'    # Mod 4 (normal):')
 [IO.File]::WriteAllText($Runner,$Source,(New-Object Text.UTF8Encoding $true))
 $Id='GUI-20261015-120002-ABCDEF';$RunRoot=Get-RemoteOpsRecipeRunRoot $Data $Id
 $R=[pscustomobject]@{Operation='RecipeRun';Category='Recipes';RecipeRunId=$Id;Targets=$S.Targets;Domain='TEST';UserName='operator';IsMain=$true;Parallelism=1;ProgressPath='';CancelPath=(Join-Path $RunRoot 'cancel.json');CheckpointRoot=(Join-Path $RunRoot 'state');Values=@{Snapshot=$S;Confirm='RECETE'}}
 $Encoded=ConvertTo-RemoteOpsRecipeRequestBase64 $R
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Runner -RequestBase64 $Encoded *> (Join-Path $Base 'runner.log')
 if($LASTEXITCODE -ne 0){Get-Content (Join-Path $Base 'runner.log') -Tail 18;throw 'Real recipe Runner failed'}
 $Actual=@(Get-Content $MutationLog);Assert (($Actual -join ',') -eq 'PC1|StartService,PC1|StartService,PC2|StartService,PC2|StartService') 'Real worker mutations escaped order/scope'
 Assert ((Get-ChildItem (Join-Path $Data 'Logs\Reports\Ledger') -Filter '*.csv').Count -eq 1) 'Child worker duplicated ledger'
 $Terminal=@(Import-Csv (Get-ChildItem (Join-Path $Data 'Logs\Reports\Ledger') -Filter '*.csv')[0].FullName -Delimiter ';')
 Assert ($Terminal.Count -eq 2 -and @($Terminal|Where-Object Outcome -ne Completed).Count -eq 0) 'Real recipe terminal outputs failed'
 Write-Host 'PASS recipe order, scope, stop, independent targets, worker identity, cancellation and real isolated Runner processes'
}finally{if(Test-Path $Base){Remove-Item $Base -Recurse -Force}}
