. (Join-Path $PSScriptRoot 'RemoteOps.Recipes.ps1')
. (Join-Path $PSScriptRoot 'RemoteOps.RecipeResults.ps1')
. (Join-Path $PSScriptRoot 'RemoteOps.RunState.ps1')
. (Join-Path $PSScriptRoot 'RemoteOps.Reports.ps1')
. (Join-Path $PSScriptRoot 'RemoteOps.History.ps1')
function Get-RemoteOpsRecipeRunRoot {
 param([string]$BasePath,[string]$RunId)
 if($RunId -cnotmatch '^GUI-[0-9]{8}-[0-9]{6}-[A-F0-9]{6}$'){throw 'Invalid recipe run ID.'}
 $Root=Join-Path $BasePath ('Logs\Operations\RecipeRun\'+$RunId)
 $Current=[IO.Path]::GetFullPath($Root)
 while($Current){if(Test-Path -LiteralPath $Current){if((Get-Item -LiteralPath $Current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse run directory rejected.'}};$P=Split-Path $Current -Parent;if($P -eq $Current){break};$Current=$P}
 return $Root
}
function New-RemoteOpsRecipeStepRequest {
 param($Snapshot,[string]$ParentRunId,[int]$TargetIndex,[int]$StepIndex,[string]$BasePath,[string]$CancelPath='')
 Assert-RemoteOpsRecipeRunSnapshot $Snapshot
 if($TargetIndex -lt 1 -or $TargetIndex -gt $Snapshot.Targets.Count -or $StepIndex -lt 1 -or $StepIndex -gt $Snapshot.Definition.Steps.Count){throw 'Invalid recipe step index.'}
 $Root=Get-RemoteOpsRecipeRunRoot $BasePath $ParentRunId;$Step=$Snapshot.Definition.Steps[$StepIndex-1];$Computer=$Snapshot.Targets[$TargetIndex-1]
 $StepOperationID=('{0}-{1:D4}-S{2:D2}' -f $ParentRunId,$TargetIndex,$StepIndex)
 $Folder=Join-Path $Root ('Steps\{0:D4}-S{1:D2}' -f $TargetIndex,$StepIndex)
 $Values=@{};foreach($Key in Get-RemoteOpsRecipeKeys $Step.Values){$Values[$Key]=Get-RemoteOpsPreviewValue $Step.Values $Key};$Values.Targets=$Computer
 $Values.Confirm=switch($Step.Operation){ServiceControl{([string]$Values.Action).ToUpperInvariant()}ServiceStartup{'EDIT'}RegistryEdit{'EDIT'}{$_ -in @('RegistryDelete','FileDelete')}{'DELETE'}PackageDeployment{if($Values.Action -eq 'Downgrade'){'DOWNGRADE'}else{'TRIGGER'}}default{''}}
 $Worker=[pscustomobject]@{Kind='RemoteOps.RecipeStep/1';RunID=$ParentRunId;ParentRunId=$ParentRunId;ComputerName=$Computer;TargetIndex=$TargetIndex;StepIndex=$StepIndex;StepId=$Step.Id;StepOperationID=$StepOperationID;RecipeId=$Snapshot.Definition.Id;RecipeRevision=$Snapshot.Definition.Revision;SnapshotHash=$Snapshot.Hash;Snapshot=$Snapshot;ResultPath=(Join-Path $Folder 'result.json');ReportRoot=$Folder;IndexOffset=($TargetIndex-1)}
 $R=[pscustomobject]@{Operation=$Step.Operation;Category='Recipes';Domain=$Snapshot.Identity.Domain;UserName=$Snapshot.Identity.UserName;IsMain=$Snapshot.Identity.IsMain;Targets=@($Computer);Values=$Values;Worker=$Worker;Parallelism=1;CleanupPackageLogs=$Snapshot.CleanupLogs;CleanupUserName=$Snapshot.Identity.UserName;CancelPath=$CancelPath;CheckpointRoot=(Join-Path $Folder 'state');ProgressPath=''}
 [void](ConvertTo-RemoteOpsRecipeRequestBase64 $R);return $R
}
function Assert-RemoteOpsRecipeWorkerRequest {
 param($Request,[string]$BasePath)
 $W=$Request.Worker
 if($W.Kind -cne 'RemoteOps.RecipeStep/1'){throw 'Invalid recipe worker kind.'}
 $Expected=New-RemoteOpsRecipeStepRequest $W.Snapshot $W.ParentRunId $W.TargetIndex $W.StepIndex $BasePath ([string]$Request.CancelPath)
 if((Get-RemoteOpsPreviewHash $Expected) -cne (Get-RemoteOpsPreviewHash $Request)){throw 'Recipe worker scope/identity changed.'}
 if($Request.CancelPath -and [IO.Path]::GetFullPath($Request.CancelPath) -ine [IO.Path]::GetFullPath((Join-Path (Get-RemoteOpsRecipeRunRoot $BasePath $W.ParentRunId) 'cancel.json'))){throw 'Invalid recipe cancel path.'}
 # Also check existing step subdirectories, never just the parent root.
 $Current=$Expected.Worker.ReportRoot;while($Current -and $Current.Length -ge $BasePath.Length){if(Test-Path -LiteralPath $Current){if((Get-Item -LiteralPath $Current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse worker path.'}};$Current=Split-Path $Current -Parent}
 return $Expected.Worker
}
function New-RemoteOpsRecipeStepResult {
 param($Request,[object[]]$Rows,[object[]]$Outcomes=@(),[object[]]$Messages=@())
 $W=$Request.Worker
 [pscustomobject]@{Schema='RemoteOps.RecipeStepResult/1';ParentRunId=$W.ParentRunId;ComputerName=$W.ComputerName;StepId=$W.StepId;StepIndex=$W.StepIndex;StepOperationID=$W.StepOperationID;RecipeId=$W.RecipeId;RecipeRevision=$W.RecipeRevision;SnapshotHash=$W.SnapshotHash;Rows=@($Rows);Outcomes=@($Outcomes);Messages=@($Messages);ArtifactPaths=@()}
}
function Assert-RemoteOpsRecipeStepResult {
 param($Result,$Request)
 $W=$Request.Worker
 if($Result.Schema -cne 'RemoteOps.RecipeStepResult/1'){throw 'Invalid recipe result schema.'}
 foreach($Key in @('ParentRunId','ComputerName','StepId','StepIndex','StepOperationID','RecipeId','RecipeRevision','SnapshotHash')){if([string]$Result.$Key -cne [string]$W.$Key){throw ('Recipe result identity mismatch: '+$Key)}}
 if($Result.Rows -isnot [array] -or $Result.Rows.Count -eq 0){throw 'Missing recipe result rows.'}
 foreach($Row in $Result.Rows){$Computer=Get-RemoteOpsRowValue $Row @('ComputerName','IstemciAdi');$Id=Get-RemoteOpsPreviewValue $Row OperationID '';if($Computer -ine $W.ComputerName -or ($Id -and $Id -cne $W.StepOperationID) -or ($Request.Operation -ceq 'RecipeCondition' -and $Id -cne $W.StepOperationID)){throw 'Recipe result row escaped scope.'}}
 foreach($O in $Result.Outcomes){if($O.ComputerName -ine $W.ComputerName){throw 'Recipe outcome escaped scope.'}}
 foreach($Path in $Result.ArtifactPaths){$Full=[IO.Path]::GetFullPath($Path);if(-not $Full.StartsWith([IO.Path]::GetFullPath($W.ReportRoot).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Recipe artifact escaped scope.'};$Current=$Full;while($Current.Length -ge $W.ReportRoot.Length){if(Test-Path -LiteralPath $Current){if((Get-Item -LiteralPath $Current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse artifact rejected.'}};$Current=Split-Path $Current -Parent}}
}
function Invoke-RemoteOpsRecipeStepWorker {
 param($Request,[string]$RunnerPath,[string]$CancelPath='',[int]$MaxWaitSeconds=7200,[scriptblock]$StartWorker=$null,[scriptblock]$WaitTick={Start-Sleep -Milliseconds 200})
 $Root=$Request.Worker.ReportRoot;New-Item -ItemType Directory -Path $Root -Force|Out-Null
 $Encoded=ConvertTo-RemoteOpsRecipeRequestBase64 $Request
 $Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -RequestBase64 {1}' -f $RunnerPath,$Encoded
 $Process=$null;$TimedOut=$false
 try{
  try{
   if($null -ne $StartWorker){$Process=& $StartWorker (Join-Path $PSHOME 'powershell.exe') $Arguments $Root}
   else{$Process=Microsoft.PowerShell.Management\Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $Arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $Root 'stdout.log') -RedirectStandardError (Join-Path $Root 'stderr.log') -ErrorAction Stop}
  }catch{$_.Exception.Data['RecipeNotStarted']=$true;throw}
  $Clock=[Diagnostics.Stopwatch]::StartNew()
  while(-not $Process.HasExited){
   if(-not $TimedOut -and $Clock.Elapsed.TotalSeconds -ge $MaxWaitSeconds){
    $TimedOut=$true
    Write-Warning 'Adım bekleme süresini aştı. Yeni adım/hedef başlatılmayacak; aktif süreç takip ediliyor. Zorla durdurma uzak işlemin durduğunu garanti etmez.'
   }
   & $WaitTick|Out-Null;$Process.Refresh()
  }
  $Path=$Request.Worker.ResultPath
  if(-not(Test-Path -LiteralPath $Path) -or (Get-Item -LiteralPath $Path).Length -gt 16MB){throw 'Worker result missing or too large; target state is unknown.'}
  $WorkerBase=$Root;1..6|ForEach-Object{$WorkerBase=Split-Path $WorkerBase -Parent};[void](Assert-RemoteOpsRecipeWorkerRequest $Request $WorkerBase);[void](Resolve-RemoteOpsHistoryPath $WorkerBase $Path)
  $Result=ConvertFrom-Json ([IO.File]::ReadAllText($Path));Assert-RemoteOpsRecipeStepResult $Result $Request
  if($TimedOut){Add-Member -InputObject $Result -NotePropertyName StopRun -NotePropertyValue $true -Force};return $Result
 }catch{if($TimedOut){$_.Exception.Data['RecipeStopRun']=$true};throw}
 finally{
  # Never detach a local child which can still issue remote writes. Explicit force-stop kills the tracked tree.
  if($null -ne $Process){while(-not $Process.HasExited){& $WaitTick|Out-Null;$Process.Refresh()};$Process.Dispose()}
 }
}
function Invoke-RemoteOpsRecipeRun {
 param($Snapshot,[string]$RunId,[string]$BasePath,[string]$CancelPath,[string]$CheckpointRoot,[scriptblock]$InvokeStep,[scriptblock]$WriteProgress={param($State)})
 Assert-RemoteOpsRecipeRunSnapshot $Snapshot;$Root=Get-RemoteOpsRecipeRunRoot $BasePath $RunId
 # Preflight every envelope before any worker can start.
 for($T=1;$T -le $Snapshot.Targets.Count;$T++){for($I=1;$I -le $Snapshot.Definition.Steps.Count;$I++){[void](New-RemoteOpsRecipeStepRequest $Snapshot $RunId $T $I $BasePath $CancelPath)}}
 New-Item -ItemType Directory -Path $Root -Force|Out-Null
 Write-RemoteOpsAtomicJson (Join-Path $CheckpointRoot 'run.json') ([pscustomobject]@{Schema='RemoteOps.RecipeCheckpoint/1';RunId=$RunId;Snapshot=$Snapshot;ReportRoot=$Root;Identity=($Snapshot.Identity.Domain+'\'+$Snapshot.Identity.UserName);CoordinatorPid=$PID;CoordinatorStartUtc=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks}) 20
 $Rows=New-Object Collections.ArrayList;$Outcomes=New-Object Collections.ArrayList;$Halted=$false
 for($T=1;$T -le $Snapshot.Targets.Count;$T++){
  $Computer=$Snapshot.Targets[$T-1];$ConditionResults=@{};$SkippedCount=0;$TargetRows=New-Object Collections.ArrayList;$Stop=$Halted;$Outcome=if($Halted){'Cancelled'}else{'Completed'};$Detail=if($Halted){'Önceki adımın bekleme sınırı aşıldı; yeni işler durduruldu.'}else{'Bütün adımlar tamamlandı.'}
  $State=[pscustomobject]@{ComputerName=$Computer;OperationID=$RunId;SnapshotHash=$Snapshot.Hash;Terminal=$false;SideEffectActive=$false;StepIndex=0;Rows=@();Outcome=$null;UpdatedAt=''}
  for($I=1;$I -le $Snapshot.Definition.Steps.Count;$I++){
   $Step=$Snapshot.Definition.Steps[$I-1];$StepOperationID=('{0}-{1:D4}-S{2:D2}' -f $RunId,$T,$I)
   if(-not $Stop -and (Test-RemoteOpsRunCancellation $CancelPath)){$Stop=$true;$Outcome='Cancelled';$Detail='Yeni adımlar kullanıcı isteğiyle durduruldu.'}
   if($Stop){[void]$TargetRows.Add([pscustomobject]@{ComputerName=$Computer;OperationID=$RunId;ParentRunId=$RunId;StepOperationID=$StepOperationID;StepId=$Step.Id;StepIndex=$I;Operation=$Step.Operation;Status='NotRun';ErrorDetail=$Detail});continue}
   $ConditionId=[string](Get-RemoteOpsPreviewValue $Step ConditionId '')
   if($ConditionId -and (-not $ConditionResults.ContainsKey($ConditionId) -or -not $ConditionResults[$ConditionId])){
    if(-not $ConditionResults.ContainsKey($ConditionId)){throw 'Condition decision missing; dispatch rejected.'}
    [void]$TargetRows.Add([pscustomobject]@{ComputerName=$Computer;OperationID=$RunId;ParentRunId=$RunId;StepOperationID=$StepOperationID;StepId=$Step.Id;StepIndex=$I;Operation=$Step.Operation;ConditionId=$ConditionId;Status='Skipped';ErrorDetail='Koşul sağlanmadığı için bu adım çalıştırılmadı.'})
    $SkippedCount++;$State.StepIndex=$I;$State.SideEffectActive=$false;$State.Rows=@($TargetRows);$State.UpdatedAt=(Get-Date).ToString('o');Write-RemoteOpsRunCheckpoint $CheckpointRoot $State;continue
   }
   $State.StepIndex=$I;$State.SideEffectActive=$true;$State.Rows=@($TargetRows);$State.UpdatedAt=(Get-Date).ToString('o');Write-RemoteOpsRunCheckpoint $CheckpointRoot $State
   & $WriteProgress ([pscustomobject]@{ComputerName=$Computer;TargetIndex=$T;StepIndex=$I;StepCount=$Snapshot.Definition.Steps.Count;Stage='Running'})|Out-Null
   try{
    $Request=New-RemoteOpsRecipeStepRequest $Snapshot $RunId $T $I $BasePath $CancelPath
    $Payload=& $InvokeStep $Request;Assert-RemoteOpsRecipeStepResult $Payload $Request
    $Decision=Get-RemoteOpsRecipeStepDecision $Step.Operation $Step.Values @($Payload.Rows) @($Payload.Outcomes)
    if($Step.Operation -ceq 'RecipeCondition'){$ConditionResults[$Step.Id]=[bool]$Decision.ConditionMatched}
    foreach($SourceRow in $Payload.Rows){$Row=ConvertFrom-Json (ConvertTo-Json -InputObject $SourceRow -Depth 20);$Original=Get-RemoteOpsPreviewValue $Row OperationID ''
     if($ConditionId){Add-Member -InputObject $Row -NotePropertyName ConditionId -NotePropertyValue $ConditionId -Force}
     foreach($Pair in @{ComputerName=$Computer;OperationID=$RunId;ParentRunId=$RunId;OriginalOperationID=$Original;StepOperationID=$StepOperationID;StepId=$Step.Id;StepIndex=$I;Operation=$Step.Operation;RecipeName=$Snapshot.Definition.Name;RecipeId=$Snapshot.Definition.Id;RecipeRevision=$Snapshot.Definition.Revision}.GetEnumerator()){Add-Member -InputObject $Row -NotePropertyName $Pair.Key -NotePropertyValue $Pair.Value -Force};[void]$TargetRows.Add($Row)
    }
    if($Decision.Decision -eq 'Stop'){$Stop=$true;$Outcome=$Decision.Outcome;$Detail=$Decision.Reason}
    if((Get-RemoteOpsPreviewValue $Payload StopRun $false) -eq $true){$Halted=$true;$Stop=$true;if($Outcome -eq 'Completed'){$Outcome='Error'};$Detail='Adım bekleme süresini aştı; son sonuç ayrıntıda korundu. Yeni adım/hedef başlatılmadı.'}
   }catch{
    $Stop=$true;if($_.Exception.Data['RecipeStopRun']){$Halted=$true};$Outcome=if($_.Exception.Data['RecipeNotStarted']){'Error'}else{'Indeterminate'};$Detail=$_.Exception.Message
    [void]$TargetRows.Add([pscustomobject]@{ComputerName=$Computer;OperationID=$RunId;ParentRunId=$RunId;StepOperationID=$StepOperationID;StepId=$Step.Id;StepIndex=$I;Operation=$Step.Operation;Status=$Outcome;ErrorDetail=$Detail})
   }
   $State.SideEffectActive=$false;$State.Rows=@($TargetRows);$State.UpdatedAt=(Get-Date).ToString('o');Write-RemoteOpsRunCheckpoint $CheckpointRoot $State
  }
  if($Outcome -eq 'Completed' -and $SkippedCount -gt 0){$Detail=('Reçete tamamlandı; koşul nedeniyle {0} adım atlandı.' -f $SkippedCount)}
  $Terminal=[pscustomobject]@{ComputerName=$Computer;Outcome=$Outcome;CompletedAt=(Get-Date).ToString('o');Detail=$Detail;RecipeName=$Snapshot.Definition.Name;RecipeId=$Snapshot.Definition.Id;RecipeRevision=$Snapshot.Definition.Revision}
  $State.Terminal=$true;$State.SideEffectActive=$false;$State.Outcome=$Terminal;$State.Rows=@($TargetRows);$State.UpdatedAt=(Get-Date).ToString('o');Write-RemoteOpsRunCheckpoint $CheckpointRoot $State
  foreach($Row in $TargetRows){[void]$Rows.Add($Row)};[void]$Outcomes.Add($Terminal)
 }
 [pscustomobject]@{Completed=$true;ResultCsv=(Join-Path $Root 'Results.csv');Rows=@($Rows);Outcomes=@($Outcomes)}
}
function Get-RemoteOpsPartialRecipeResult {
 param($Snapshot,[string]$RunId,[object[]]$Checkpoints,[ValidateSet('Cancelled','Error')][string]$MissingOutcome='Cancelled')
 $Rows=New-Object Collections.ArrayList;$Outcomes=New-Object Collections.ArrayList
 foreach($Computer in $Snapshot.Targets){
  $Matches=@($Checkpoints|Where-Object{(Get-RemoteOpsPreviewValue $_ OperationID '') -ceq $RunId -and (Get-RemoteOpsPreviewValue $_ SnapshotHash '') -ceq $Snapshot.Hash -and [string]::Equals([string]$_.ComputerName,$Computer,[StringComparison]::OrdinalIgnoreCase)}|Sort-Object UpdatedAt -Descending|Select-Object -First 1)
  if($Matches.Count){$State=$Matches[0];foreach($Row in $State.Rows){[void]$Rows.Add($Row)};if($State.Terminal -and $null -ne $State.Outcome){[void]$Outcomes.Add($State.Outcome);continue}}
  $Outcome=if($Matches.Count){'Indeterminate'}else{$MissingOutcome};$Reason=if($Matches.Count){'Çalışma kesildi; son adımın hedef durumu doğrulanmalı.'}else{'Bu hedef başlatılmadan çalışma durdu.'}
  if($Matches.Count -and $Matches[0].SideEffectActive -and [int]$Matches[0].StepIndex -ge 1 -and [int]$Matches[0].StepIndex -le $Snapshot.Definition.Steps.Count){
   $I=[int]$Matches[0].StepIndex;$Step=$Snapshot.Definition.Steps[$I-1];$T=[array]::IndexOf([object[]]$Snapshot.Targets,$Computer)+1
   [void]$Rows.Add([pscustomobject]@{ComputerName=$Computer;OperationID=$RunId;ParentRunId=$RunId;StepId=$Step.Id;StepIndex=$I;StepOperationID=('{0}-{1:D4}-S{2:D2}' -f $RunId,$T,$I);Operation=$Step.Operation;Status='Indeterminate';ErrorDetail=$Reason})
  }
  $FirstPending=if($Matches.Count){[int]$Matches[0].StepIndex+1}else{1}
  for($I=$FirstPending;$I -le $Snapshot.Definition.Steps.Count;$I++){$Step=$Snapshot.Definition.Steps[$I-1];[void]$Rows.Add([pscustomobject]@{ComputerName=$Computer;OperationID=$RunId;ParentRunId=$RunId;StepId=$Step.Id;StepIndex=$I;Operation=$Step.Operation;Status='NotRun';ErrorDetail=$Reason})}
  [void]$Rows.Add([pscustomobject]@{ComputerName=$Computer;OperationID=$RunId;Step='Result';Status=$Outcome;ErrorDetail=$Reason})
  [void]$Outcomes.Add([pscustomobject]@{ComputerName=$Computer;Outcome=$Outcome;CompletedAt=(Get-Date).ToString('o');Detail=$Reason;RecipeName=$Snapshot.Definition.Name;RecipeId=$Snapshot.Definition.Id;RecipeRevision=$Snapshot.Definition.Revision})
 }
 [pscustomobject]@{Rows=@($Rows);Outcomes=@($Outcomes)}
}
function Complete-RemoteOpsInterruptedRecipe {
 param([string]$BasePath,[string]$CheckpointRoot,[ValidateSet('Cancelled','Error')][string]$MissingOutcome='Cancelled')
 $MetaPath=Resolve-RemoteOpsHistoryPath $BasePath (Join-Path $CheckpointRoot 'run.json');if((Get-Item -LiteralPath $MetaPath).Length -gt 1MB){throw 'Checkpoint metadata too large.'};$Meta=ConvertFrom-Json ([IO.File]::ReadAllText($MetaPath));Assert-RemoteOpsRecipeRunSnapshot $Meta.Snapshot
 $Root=Get-RemoteOpsRecipeRunRoot $BasePath $Meta.RunId
 if([IO.Path]::GetFullPath($CheckpointRoot) -ine [IO.Path]::GetFullPath((Join-Path $Root 'state')) -or $Meta.ReportRoot -ine $Root){throw 'Recipe checkpoint path mismatch.'}
 $Partial=Get-RemoteOpsPartialRecipeResult $Meta.Snapshot $Meta.RunId @(Get-RemoteOpsRunCheckpoints $CheckpointRoot) $MissingOutcome
 $Result=[pscustomobject]@{Completed=$true;Rows=$Partial.Rows;Outcomes=$Partial.Outcomes;ResultCsv=(Join-Path $Root 'Results.csv')}
 [void](Write-RemoteOpsLedger $BasePath $Meta.RunId RecipeRun Recipes $Meta.Identity $Partial.Outcomes)
 Complete-RemoteOpsReports -Result $Result -Title ($Meta.Snapshot.Definition.Name+' / partial') -OperationID $Meta.RunId -ReportRoot $Root -Messages @()
 Write-RemoteOpsAtomicJson (Join-Path $CheckpointRoot 'reported.json') ([pscustomobject]@{RunId=$Meta.RunId;ReportedAt=(Get-Date).ToString('o')})
 return $Result
}

function Repair-RemoteOpsRecipeReports {
 param([string]$BasePath)
 $Repaired=0;$Issues=New-Object Collections.ArrayList;$Catalog=Join-Path $BasePath 'Logs\Operations\RecipeRun'
 if(Test-Path -LiteralPath $Catalog){foreach($Dir in Get-ChildItem -LiteralPath $Catalog -Directory){try{
  $Root=Get-RemoteOpsRecipeRunRoot $BasePath $Dir.Name;$State=Join-Path $Root 'state';$Path=Join-Path $State 'run.json'
  if(-not(Test-Path -LiteralPath $Path) -or (Test-Path -LiteralPath (Join-Path $State 'reported.json'))){continue}
  [void](Resolve-RemoteOpsHistoryPath $BasePath $Path);$Meta=ConvertFrom-Json ([IO.File]::ReadAllText($Path));$OwnerId=[int](Get-RemoteOpsPreviewValue $Meta CoordinatorPid 0)
  if($OwnerId -gt 0){$Owner=Get-Process -Id $OwnerId -ErrorAction SilentlyContinue;if($null -ne $Owner -and $Owner.StartTime.ToUniversalTime().Ticks -eq [long]$Meta.CoordinatorStartUtc){continue}}
  [void](Complete-RemoteOpsInterruptedRecipe $BasePath $State Error);$Repaired++
 }catch{[void]$Issues.Add([pscustomobject]@{Path=$Dir.FullName;Message=$_.Exception.Message})}}}
 return [pscustomobject]@{Repaired=$Repaired;Issues=@($Issues)}
}
