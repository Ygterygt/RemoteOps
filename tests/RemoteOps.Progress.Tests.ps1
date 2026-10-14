$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$OperationName='Fixture';$Values=[pscustomobject]@{}
function Test-RemoteOpsOperationAccess {param($ComputerName,$Operation,$InputValues)[pscustomobject]@{Status='Success';Detail='isolated fixture'}}
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
$Tokens=$null;$Errors=$null
$Ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.Runner.ps1'),[ref]$Tokens,[ref]$Errors)
if($Errors.Count){throw ($Errors|Out-String)}
foreach($Name in @('Write-TargetProgress','Invoke-TargetBatch','Get-TargetOutcome')){
    $Definition=$Ast.Find({param($Node)$Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq $Name},$true)
    Set-Item ('Function:\'+$Name) -Value $Definition.Body.GetScriptBlock()
}
$AppAst=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'),[ref]$Tokens,[ref]$Errors)
if($Errors.Count){throw ($Errors|Out-String)}
$Definition=$AppAst.Find({param($Node)$Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq 'Read-TargetProgress'},$true)
Set-Item Function:\Read-TargetProgress -Value $Definition.Body.GetScriptBlock()
$Temporary=Join-Path $env:TEMP ('RemoteOpsProgress-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Temporary|Out-Null
try{
    $RunReportRoot=$Temporary;$Common=@{};$script:ReportCandidates=@();$script:OperationMessages=@();$script:PromptAnswers=New-Object 'System.Collections.Generic.Queue[string]'
    $ProgressPath=Join-Path $Temporary 'progress.json'
    $OtherPath=Join-Path $Temporary 'other-progress.json'
    $Warnings=@(& {
        Write-TargetProgress -Path $ProgressPath -Total 100 -Completed 0 -CurrentTarget '' -Stage 'Running'
        Write-TargetProgress -Path $OtherPath -Total 28 -Completed 3 -CurrentTarget 'OTHER-PC' -Stage 'Running'
    } 3>&1)
    if($Warnings.Count){throw 'Initial progress creation emitted warnings.'}
    $StaleTemporary=$ProgressPath+'.tmp'
    Set-Content -LiteralPath $StaleTemporary -Value 'Do not overwrite another temporary file'
    $Sharing=[System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
    $HeldReader=[System.IO.File]::Open($ProgressPath,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,$Sharing)
    try{
        foreach($Completed in 1..100){
            $Warnings=@(& {Write-TargetProgress -Path $ProgressPath -Total 100 -Completed $Completed -CurrentTarget ('PC-'+$Completed) -Stage 'Running'} 3>&1)
            if($Warnings.Count){throw "Replacement emitted a warning at ${Completed}: $($Warnings -join '; ')"}
            $State=Read-TargetProgress -Path $ProgressPath
            if($State.Completed -ne $Completed -or $State.Pending -ne (100-$Completed)){throw 'Reader saw stale or incomplete JSON.'}
        }
    }
    finally{$HeldReader.Dispose()}
    if((Read-TargetProgress -Path $OtherPath).Completed -ne 3){throw 'Independent run progress was overwritten.'}
    if((Get-Content -LiteralPath $StaleTemporary -Raw).Trim() -ne 'Do not overwrite another temporary file'){throw 'A stale temporary file was overwritten.'}
    Remove-Item -LiteralPath $StaleTemporary -Force
    $LockedReader=[System.IO.File]::Open($ProgressPath,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::Read)
    try{
        $Warnings=@(& {Write-TargetProgress -Path $ProgressPath -Total 100 -Completed 99 -CurrentTarget 'LOCKED' -Stage 'Running'} 3>&1)
        if($Warnings.Count -ne 1 -or (Read-TargetProgress -Path $ProgressPath).Completed -ne 100){throw 'A denied replacement lost the last valid progress snapshot.'}
    }
    finally{$LockedReader.Dispose()}
    $Warnings=@(& {Write-TargetProgress -Path $ProgressPath -Total 100 -Completed 100 -CurrentTarget '' -Stage 'Completed'} 3>&1)
    if($Warnings.Count -or (Read-TargetProgress -Path $ProgressPath).Stage -ne 'Completed'){throw 'Progress did not recover after a lock was released.'}
    if(@(Get-ChildItem -LiteralPath $Temporary -Filter '*.tmp' -File).Count){throw 'Progress temporary files leaked.'}
    $Batch=Invoke-TargetBatch -InputTargets @('PC-OK','PC-FAIL','PC-EMPTY','PC-SKIP') -RunOperationID 'BATCH' -ProgressPath $ProgressPath -InvokeTarget {
        $State=Get-Content $ProgressPath -Raw|ConvertFrom-Json
        if($State.CurrentTarget -ne $Systems[0] -or $State.Total -ne 4){throw 'Current target or total is incorrect.'}
        if($null -eq $State.PSObject.Properties['Targets'] -or @($State.Targets|Where-Object{$_.ComputerName -eq $Systems[0] -and $_.Stage -eq 'Running'}).Count -ne 1){throw 'Running operation target is absent from live target rows.'}
        if($Common.Systems.Count -ne 1 -or $Common.OperationID -ne $OperationID){throw 'Module context was not scoped to a single target.'}
        if($Systems[0] -eq 'PC-FAIL'){throw 'Simulated failure'}
        if($Systems[0] -eq 'PC-EMPTY'){return $null}
        $Status=if($Systems[0] -eq 'PC-SKIP'){'Skipped'}else{'Success'}
        return [PSCustomObject]@{ResultCsv=(Join-Path $Temporary ($Systems[0]+'.csv'));Rows=@([PSCustomObject]@{ComputerName=$Systems[0];OperationID=$OperationID;Status=$Status})}
    }
    if($Batch.Rows.Count -ne 4){throw 'Batch omitted failed, empty or skipped targets.'}
    if($Batch.Rows[0].OperationID -ne 'BATCH' -or $Batch.Rows[1].Status -ne 'Failed' -or $Batch.Rows[2].Status -ne 'NoData' -or $Batch.Rows[3].Status -ne 'Skipped'){throw 'Aggregated results lost outcomes or run identity.'}
    $State=Get-Content $ProgressPath -Raw|ConvertFrom-Json
    if($State.Completed -ne 4 -or $State.Pending -ne 0 -or $State.Stage -ne 'Reporting'){throw 'Final progress counters are incorrect.'}
    if(@($State.Targets).Count -ne 4 -or @($State.Targets|Where-Object{$_.ComputerName -eq 'PC-FAIL' -and $_.Outcome -eq 'Error'}).Count -ne 1){throw 'Per-target live results lost failures or targets.'}
    $Common=@{}
    $Batch=Invoke-TargetBatch -InputTargets @('PC-A','PC-B') -RunOperationID 'CSV-BATCH' -ProgressPath $ProgressPath -InvokeTarget {
        $Csv=Join-Path $Temporary 'shared.csv'
        @([PSCustomObject]@{ComputerName='OLD-PC';OperationID='OLD';Status='Success'},[PSCustomObject]@{ComputerName=$Systems[0];OperationID=$OperationID;Status='Success'})|Export-Csv $Csv -Delimiter ';' -NoTypeInformation
        $script:ReportCandidates=@($Csv)
        return $null
    }
    if($Batch.Rows.Count -ne 2 -or ($Batch.Rows.ComputerName -join ',') -ne 'PC-A,PC-B'){throw 'CSV snapshots leaked history or lost a target when the source was overwritten.'}
    Write-Output 'PASS: 100 atomic progress replacements with an open reader, independent runs, stale temp isolation, lock recovery/cleanup, counters and aggregate snapshots.'
}
finally{Remove-Item -LiteralPath $Temporary -Recurse -Force -ErrorAction SilentlyContinue}
