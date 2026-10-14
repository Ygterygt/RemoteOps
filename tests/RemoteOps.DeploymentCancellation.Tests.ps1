$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Packages.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
$File=Join-Path $Root 'RemoteOps.App\RemoteOps.RunState.ps1'
if(-not(Test-Path $File)){throw 'Deployment checkpoints are missing.'};. $File
$Temp=Join-Path $env:TEMP ('RemoteOpsCancel-'+[guid]::NewGuid().ToString('N'))
try{
    $Cancel=Join-Path $Temp 'cancel.json'
    if(Test-RemoteOpsRunCancellation $Cancel){throw 'Missing cancellation was treated as requested.'}
    Request-RemoteOpsRunCancellation $Cancel
    if(-not(Test-RemoteOpsRunCancellation $Cancel)){throw 'Cancellation was lost.'}
    $Done=[PSCustomObject]@{ComputerName='PC1';OperationID='RUN';Step='Result';Terminal=$true;Rows=@([PSCustomObject]@{ComputerName='PC1';Step='Result';Status='Success'});Outcome=[PSCustomObject]@{ComputerName='PC1';Outcome='Success';CompletedAt=(Get-Date)};UpdatedAt=(Get-Date).ToString('o')}
    $Active=[PSCustomObject]@{ComputerName='PC2';OperationID='RUN';Step='Uninstall';Terminal=$false;SideEffectActive=$true;Removed=$false;Rows=@();Outcome=$null;UpdatedAt=(Get-Date).ToString('o')}
    Write-RemoteOpsRunCheckpoint $Temp $Done;Write-RemoteOpsRunCheckpoint $Temp $Active
    $Result=Get-RemoteOpsPartialDeploymentResult @('PC1','PC2','PC3') (Get-RemoteOpsRunCheckpoints $Temp)
    if(($Result.Outcomes.Outcome -join ',') -ne 'Success,Indeterminate,Cancelled'){throw 'Partial results lost successful, unknown or unstarted targets.'}
    if($Result.Rows.Count -ne 3){throw 'Partial report did not retain one result per target.'}
    $Bad=Join-Path $Temp 'broken.target.json';Set-Content $Bad '{invalid' -Encoding UTF8
    if(@(Get-RemoteOpsRunCheckpoints $Temp).Count -ne 2){throw 'Corrupt checkpoint damaged other targets.'}
    $P=New-RemoteOpsPackageDefinition 'Recovery';$P.Install.Enabled=$true;$P.Install.PackagePath='\\server\share';$P.Install.PackageFile='install.cmd';$P.Install.Application='App';$P.TargetVersion='2.0'
    $ReportRoot=Join-Path $Temp 'Logs\Operations\PackageDeployment\RUN'
    Write-RemoteOpsAtomicJson (Join-Path $Temp 'run.json') ([PSCustomObject]@{OperationID='RUN';ReportRoot=$ReportRoot;Targets=@('PC1','PC2','PC3');Definition=$P;Action='Downgrade';Identity='TEST\user'})
    function Open-RemoteOpsHtmlFile {param($Path)}
    $Recovered=Complete-RemoteOpsInterruptedDeployment -BasePath $Temp -CheckpointRoot $Temp
    $Saved=@(Import-Csv (Join-Path $ReportRoot 'Results.csv') -Delimiter ';')
    if($Recovered.Outcomes.Count -ne 3 -or $Saved.Count -ne 3){throw 'Forced interruption did not produce a partial report.'}
    $Ledger=@(Get-ChildItem (Join-Path $Temp 'Logs\Reports\Ledger') -Filter '*.csv'|ForEach-Object{Import-Csv $_.FullName -Delimiter ';'})
    if(($Ledger.Outcome -join ',') -ne 'Success,Indeterminate,Cancelled'){throw 'Recovered ledger mislabeled interrupted targets.'}
    Write-Output 'PASS: cancellation request, atomic checkpoints, successful/unknown/unstarted partial outcomes.'
}finally{if(Test-Path $Temp){Remove-Item $Temp -Recurse -Force}}
