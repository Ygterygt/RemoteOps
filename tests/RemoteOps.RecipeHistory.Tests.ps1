$ErrorActionPreference='Stop';$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'RemoteOps.App\RemoteOps.RecipeExecution.ps1');. (Join-Path $Root 'RemoteOps.App\RemoteOps.History.ps1');. (Join-Path $Root 'RemoteOps.App\RemoteOps.Diagnostics.ps1')
function Assert($C,$M){if(-not $C){throw $M}}
$Base=Join-Path $env:TEMP ('RecipeHistory_'+[guid]::NewGuid().ToString('N'));$RunId='GUI-20261015-120000-ABCDEF'
try{
 $D=New-RemoteOpsRecipeDefinition '<script>Pilot</script>';$D.Revision=1;$D.Steps=@(1..2|ForEach-Object{[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Read';Operation='RegistryRead';Values=@{RegistryPath='HKLM\Software\Example';ValueName='a'}}})
 $S=New-RemoteOpsRecipeRunSnapshot $D @('PC1','PC2') ([pscustomobject]@{Domain='TEST';UserName='operator';IsMain=$true}) $false
 $RootPath=Get-RemoteOpsRecipeRunRoot $Base $RunId;$StateRoot=Join-Path $RootPath 'state'
 $Result=Invoke-RemoteOpsRecipeRun $S $RunId $Base '' $StateRoot {param($R) New-RemoteOpsRecipeStepResult $R @([pscustomobject]@{ComputerName=$R.Targets[0];OperationID=$R.Worker.StepOperationID;Status='Failed';ReturnValue=50010;ErrorDetail='Original failure'}) @()} {param($State)}
 [void](Write-RemoteOpsLedger $Base $RunId RecipeRun Recipes 'TEST\operator' $Result.Outcomes);Complete-RemoteOpsReports -Result $Result -Title $D.Name -OperationID $RunId -ReportRoot $RootPath
 $Index=Get-RemoteOpsHistoryIndex $Base;Assert ($Index.Runs.Count -eq 1 -and $Index.Runs[0].Targets.Count -eq 2) 'Upper history duplicated'
 Assert ($Index.Runs[0].PackageName -eq $D.Name) 'Recipe name missing in history list'
 $Details=Get-RemoteOpsHistoryDetails $Base $Index.Runs[0];Assert ($Details.Rows.Count -eq 4 -and @($Details.Rows|Where-Object StepId).Count -eq 4) 'Step history missing'
 $Diag=Get-RemoteOpsDiagnosis $Index.Runs[0] PC1 $Details;Assert (($Diag|ConvertTo-Json -Depth 12) -match '50010') 'Original diagnostic code lost'
 Assert ((Get-Content (Join-Path $RootPath 'Results.html') -Raw) -notmatch '<script>Pilot</script>') 'HTML not escaped'
 $Active=[pscustomobject]@{ComputerName='PC1';OperationID=$RunId;SnapshotHash=$S.Hash;Terminal=$false;SideEffectActive=$true;StepIndex=1;Rows=@();Outcome=$null;UpdatedAt=(Get-Date).ToString('o')}
 $Partial=Get-RemoteOpsPartialRecipeResult $S $RunId @($Active) Error
 Assert ($Partial.Outcomes[0].Outcome -eq 'Indeterminate') 'Active interrupted target claimed error/success'
 Assert (@($Partial.Rows|Where-Object{ $_.ComputerName -eq 'PC1' -and $_.Status -eq 'Indeterminate' -and $_.StepId -eq $D.Steps[0].Id -and $_.StepIndex -eq 1 -and $_.StepOperationID -eq ($RunId+'-0001-S01')}).Count -eq 1) 'Interrupted active step identity missing'
 Assert (@($Partial.Rows|Where-Object{ $_.ComputerName -eq 'PC1' -and $_.Status -eq 'NotRun'}).Count -eq 1) 'Interrupted remaining steps absent'
 [void](Complete-RemoteOpsInterruptedRecipe $Base $StateRoot Error);[void](Complete-RemoteOpsInterruptedRecipe $Base $StateRoot Error)
 Assert ((Get-RemoteOpsHistoryIndex $Base).Runs.Count -eq 1) 'Partial completion duplicate'

 $MetaPath=Join-Path $StateRoot 'run.json';$Meta=ConvertFrom-Json ([IO.File]::ReadAllText($MetaPath));$Meta.CoordinatorPid=99999999;Write-RemoteOpsAtomicJson $MetaPath $Meta 20
 Remove-Item (Join-Path $StateRoot 'reported.json') -ErrorAction SilentlyContinue
 $Recovery=Repair-RemoteOpsRecipeReports $Base;Assert ($Recovery.Repaired -eq 1) 'Startup did not repair interrupted recipe'
 $Recovery=Repair-RemoteOpsRecipeReports $Base;Assert ($Recovery.Repaired -eq 0) 'Startup repeated completed repair'
 Write-Host 'PASS recipe parent history, step evidence, original code, escaped HTML and interruption idempotence'
}finally{if(Test-Path $Base){Remove-Item $Base -Recurse -Force}}
