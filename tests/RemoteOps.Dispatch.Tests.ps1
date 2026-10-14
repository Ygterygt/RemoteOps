$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$OperationName='Fixture';$Values=[pscustomobject]@{}
function Test-RemoteOpsOperationAccess {param($ComputerName,$Operation,$InputValues)[pscustomobject]@{Status='Success';Detail='isolated fixture'}}
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
$Tokens=$null;$Errors=$null
$Ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.Runner.ps1'),[ref]$Tokens,[ref]$Errors)
if($Errors.Count){throw ($Errors|Out-String)}
foreach($Name in @('Register-AOModule','Register-AOModuleOperation','Test-ConsoleMenuText','Write-Host','Read-Host','Add-Answers','Write-TargetProgress','Invoke-TargetBatch','Get-TargetOutcome')){
    $Definition=$Ast.Find({param($Node)$Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq $Name},$true)
    Set-Item ('Function:\'+$Name) -Value $Definition.Body.GetScriptBlock()
}
$script:AOModules=@();$script:AOModuleOperations=@();$script:OperationMessages=@();$script:ReportCandidates=@();$script:PromptAnswers=New-Object 'System.Collections.Generic.Queue[string]'
. (Join-Path $Root 'Modules\ServiceTaskOperations.ps1')
function Get-ServiceTaskSession { param($ComputerName) return $ComputerName }
function Remove-CimSession { param($CimSession,$ErrorAction) }
function Get-CimInstance {
    param($CimSession,$Namespace,$ClassName,$ErrorAction)
    if($CimSession -eq 'PC-FAIL'){throw 'Mock access denied'}
    return [PSCustomObject]@{TaskName='Nightly';TaskPath='\Ops\';State='Ready';Settings=[PSCustomObject]@{Enabled=$true}}
}
function Start-Process { param($FilePath) $script:ReportCandidates+=[string]$FilePath }
function Write-RemoteOpsLog { param($Level,$Message) }
function Write-RemoteOpsHistory { param($OperationID,$OperationDate,$OperationTime,$IstemciAdi,$Modul,$Operasyon,$Sonuc,$Aciklama) }
$Temporary=Join-Path $env:TEMP ('RemoteOpsDispatch-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Temporary|Out-Null
try{
    $BasePath=$Temporary;$RunReportRoot=$Temporary;$OperationName='ScheduledTaskList';$OperationDate='2026-10-05';$OperationTime='10:00:00'
    $Values=[PSCustomObject]@{TaskFilter=''}
    $Request=[PSCustomObject]@{Operation=$OperationName;Targets=@('PC-A','PC-FAIL','PC-B');Values=$Values}
    $Common=@{BasePath=$BasePath;Systems=$Request.Targets;ReachableSystems=$Request.Targets;UnreachableSystems=@();OperationID='DISPATCH';OperationDate=$OperationDate;OperationTime=$OperationTime;TechnicalLogWriter=${function:Write-RemoteOpsLog};OperationHistoryWriter=${function:Write-RemoteOpsHistory}}
    $Assignment=$Ast.Find({param($Node)$Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $Node.Left.Extent.Text -eq '$InvokeTarget'},$true)
    Invoke-Expression $Assignment.Extent.Text
    $Captured=@(& {
        Invoke-TargetBatch -InputTargets $Request.Targets -RunOperationID 'DISPATCH' -ProgressPath (Join-Path $Temporary 'progress.json') -InvokeTarget $InvokeTarget
    } 6>&1)
    $Text=$Captured|Out-String
    if($Text -match 'SERVICE AND TASK OPERATIONS|GUI input:|Seciminiz|4 - Scheduled task'){throw 'Actual task dispatch leaked a console menu or prompt.'}
    $HostLines=@($Captured|Where-Object{$_ -is [System.Management.Automation.InformationRecord]}|ForEach-Object{$_.MessageData.ToString()})
    if(($HostLines -join '|') -ne 'PC-A - Success|PC-FAIL - Error|PC-B - Success'){throw "Expected exactly one outcome line per target: $($HostLines -join '|')"}
    $Batch=@($Captured|Where-Object{$null -ne $_.PSObject.Properties['Rows']})
    if($Batch.Count -ne 1 -or $Batch[0].Rows.Count -ne 3){throw "Task dispatch lost results: $Text"}
    if(($Batch[0].Rows.ComputerName -join ',') -ne 'PC-A,PC-FAIL,PC-B'){throw 'Task dispatch processed the wrong target scope.'}
    if($Batch[0].Rows[1].Status -ne 'Failed' -or $Batch[0].Rows[0].TaskName -ne 'Nightly'){throw 'Task dispatch lost task inventory or errors.'}
    if($script:PromptAnswers.Count -ne 0){throw 'Task dispatch left automatic answers queued.'}
    $Captured=@(& {
        Invoke-TargetBatch -InputTargets @('PC-OK','PC-SKIP','PC-OFF','PC-POST','PC-ERROR') -RunOperationID 'PACKAGE-OUTPUT' -ProgressPath (Join-Path $Temporary 'package-progress.json') -InvokeTarget {
            $Row=switch($Systems[0]){
                'PC-OK' {[PSCustomObject]@{ComputerName=$Systems[0];ExecutionStatus='Success';Outcome='Completed'}}
                'PC-SKIP' {[PSCustomObject]@{ComputerName=$Systems[0];ExecutionStatus='Skipped';Outcome='Skipped'}}
                'PC-OFF' {[PSCustomObject]@{ComputerName=$Systems[0];ExecutionStatus='NotRun';Decision='Unreachable';Outcome='Error'}}
                'PC-POST' {[PSCustomObject]@{ComputerName=$Systems[0];ExecutionStatus='Success';PostCheckStatus='Hata';PostCheckErrorDetail='Verification failed';Outcome='Error'}}
                'PC-ERROR' {[PSCustomObject]@{ComputerName=$Systems[0];ExecutionStatus='Failed';Outcome='Error'}}
            }
            Write-Host "$($Systems[0]) - package execution details"
            Write-Host 'Installed : 1';Write-Host 'Skipped : 0';Write-Host 'Error/Unreachable : 0'
            return [PSCustomObject]@{ResultCsv=(Join-Path $Temporary ($Systems[0]+'.csv'));Rows=@($Row)}
        }
    } 6>&1)
    $HostLines=@($Captured|Where-Object{$_ -is [System.Management.Automation.InformationRecord]}|ForEach-Object{$_.MessageData.ToString()})
    if(($HostLines -join '|') -ne 'PC-OK - Success|PC-SKIP - Skipped|PC-OFF - Unreachable|PC-POST - Error|PC-ERROR - Error'){throw "Package summaries or outcomes are incorrect: $($HostLines -join '|')"}
    $Outcome=Get-TargetOutcome -Rows @([PSCustomObject]@{Status='NoData'}) -Messages @([PSCustomObject]@{Message='PC-SERVICE : SERVIS OK | Example'}) -Target 'PC-SERVICE'
    if($Outcome -ne 'Success'){throw 'Service action without structured rows lost its explicit success result.'}
    if(@($script:OperationMessages|Where-Object{$_.Message -eq 'Installed : 1'}).Count -ne 5){throw 'Suppressed details were lost from Activity reporting.'}
    Write-Output 'PASS: actual scheduled-task dispatch, menu suppression, three-target scope, failure preservation and report snapshots.'
}
finally{Remove-Item -LiteralPath $Temporary -Recurse -Force -ErrorAction SilentlyContinue}