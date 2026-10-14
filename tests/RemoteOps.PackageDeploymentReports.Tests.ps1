$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot;. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
$Temp=Join-Path $env:TEMP ('RemoteOpsDeploymentReports-'+[guid]::NewGuid().ToString('N'))
try{
    $Rows=@([PSCustomObject]@{ComputerName='PC1';Step='Uninstall';Status='Success'},[PSCustomObject]@{ComputerName='PC1';Step='Result';Status='Cancelled'})
    if((Get-RemoteOpsComputerOutcome $Rows) -ne 'Cancelled'){throw 'Successful intermediate step overrode terminal cancellation.'}
    foreach($Status in @('Indeterminate','RebootRequired','Error','Skipped','Success')){
        $Rows[1].Status=$Status;if((Get-RemoteOpsComputerOutcome $Rows) -ne $Status){throw "Terminal outcome $Status was not preserved."}
    }
    New-Item -ItemType Directory -Path $Temp|Out-Null
    $Name='Example <>&';$Outcomes=@([PSCustomObject]@{ComputerName='PC1';Outcome='Indeterminate';CompletedAt=(Get-Date);PackageName=$Name;PackageId='ID';PackageRevision=2;Action='Downgrade'},[PSCustomObject]@{ComputerName='PC2';Outcome='Cancelled';CompletedAt=(Get-Date);PackageName=$Name;PackageId='ID';PackageRevision=2;Action='Downgrade'})
    $Path=Write-RemoteOpsLedger -BasePath $Temp -OperationID RUN1 -Operation PackageDeployment -Category Applications -Outcomes $Outcomes
    $Saved=@(Import-Csv $Path -Delimiter ';')
    if($Saved.Count -ne 2 -or $Saved[0].PackageName -ne $Name){throw 'Ledger lost package identity or duplicated step counts.'}
    [void](Write-RemoteOpsLedger -BasePath $Temp -OperationID RUN1 -Operation PackageDeployment -Outcomes $Outcomes)
    $Daily=Get-RemoteOpsDailyReport $Temp (Get-Date)
    if($Daily.Total -ne 2 -or $Daily.Success -ne 0 -or $Daily.Indeterminate -ne 1 -or $Daily.Cancelled -ne 1){throw 'Unknown/cancelled deployment counted as success or step attempts.'}
    if($null -eq $Daily.PSObject.Properties['Packages']){throw 'Daily report has no saved package/action breakdown.'}
    if(@($Daily.Packages).Count -ne 1 -or $Daily.Packages[0].Name -ne $Name -or $Daily.Packages[0].Action -ne 'Downgrade' -or $Daily.Packages[0].Count -ne 2 -or $Daily.Packages[0].Problems -ne 1 -or $Daily.Packages[0].Cancelled -ne 1){throw 'Package/action totals lost identity, terminal counting or attention states.'}
    $Dashboard=Write-RemoteOpsDailyDashboardHtml -Path (Join-Path $Temp 'Daily.html') -Report $Daily
    $DailyText=Get-Content $Dashboard -Raw -Encoding UTF8
    if($DailyText -notmatch 'data-outcome="Indeterminate"[^>]*>1<' -or $DailyText -notmatch 'data-outcome="Cancelled"[^>]*>1<'){throw 'Exported daily dashboard omitted new outcome counts.'}
    if($DailyText -notmatch 'data-package="ID"' -or $DailyText -notmatch 'Example &lt;&gt;&amp;' -or $DailyText -notmatch 'Downgrade'){throw 'Daily dashboard omitted or failed to escape package/action breakdown.'}
    $More=@([PSCustomObject]@{ComputerName='PC3';Outcome='Success';CompletedAt=(Get-Date);PackageName=$Name;PackageId='ID';Action='Install'},[PSCustomObject]@{ComputerName='PC4';Outcome='RebootRequired';CompletedAt=(Get-Date);PackageName=$Name;PackageId='OTHER';Action='Downgrade'})
    [void](Write-RemoteOpsLedger -BasePath $Temp -OperationID RUN2 -Operation PackageDeployment -Outcomes $More)
    [void](Write-RemoteOpsLedger -BasePath $Temp -OperationID RUN3 -Operation ServiceList -Outcomes @([PSCustomObject]@{ComputerName='PC5';Outcome='Success';CompletedAt=(Get-Date)}))
    $Mixed=Get-RemoteOpsDailyReport $Temp (Get-Date)
    if($Mixed.Total -ne 5 -or @($Mixed.Packages).Count -ne 3 -or ($Mixed.Packages|Measure-Object Count -Sum).Sum -ne 4){throw 'Distinct IDs/actions merged or a legacy non-package operation polluted package totals.'}
    $Other=@($Mixed.Packages|Where-Object Id -eq OTHER)
    if($Other.Count -ne 1 -or $Other[0].Problems -ne 1){throw 'Reboot-required package missing from attention count.'}
    $Html=Write-RemoteOpsResultHtml -Path (Join-Path $Temp 'Results.html') -Title $Name -OperationID RUN1 -Rows @([PSCustomObject]@{ComputerName='PC1';Step='Uninstall';Status='Success'},[PSCustomObject]@{ComputerName='PC1';Step='Result';Status='Indeterminate';PackageName=$Name})
    $Text=Get-Content $Html -Raw -Encoding UTF8
    if($Text -notmatch 'Example &lt;&gt;&amp;' -or $Text -notmatch 'data-outcome="Indeterminate"'){throw 'Package HTML escaping or explicit outcome filter missing.'}
    Write-Output 'PASS: terminal outcomes, package ledger identity, partial totals, idempotent run ledger and encoded HTML outcome filters.'
}finally{if(Test-Path $Temp){Remove-Item $Temp -Recurse -Force}}
