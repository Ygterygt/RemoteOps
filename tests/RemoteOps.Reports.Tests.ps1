param([string]$PreviewPath='')
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$WorkspaceRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $WorkspaceRoot 'RemoteOps.App\RemoteOps.Reports.ps1')
$Tokens=$null;$ParseErrors=$null
$RunnerAst=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $WorkspaceRoot 'RemoteOps.App\RemoteOps.Runner.ps1'),[ref]$Tokens,[ref]$ParseErrors)
if($ParseErrors.Count){throw ($ParseErrors|Out-String)}
$script:HostAst=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $WorkspaceRoot 'Modules\ApplicationWorkers.ps1'),[ref]$Tokens,[ref]$ParseErrors)
foreach($Name in @('Import-HostFunction','Invoke-ApplicationInventoryRequest','Write-ApplicationRows')){
    $Definition=$RunnerAst.Find({param($Node)$Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq $Name},$true)
    Set-Item -Path ('Function:'+ $Name) -Value $Definition.Body.GetScriptBlock()
}
$script:Opened=@()
function Start-Process { param($FilePath) $script:Opened+=[string]$FilePath }
function Open-RemoteOpsHtmlFile { param($Path) $script:Opened+=[string]$Path }
function Write-RemoteOpsLog { param($Level,$Message) }
function Get-HostScriptBlock {
    param($VariableName)
    return {
        param($ComputerName,$TimeoutSeconds)
        if($ComputerName -eq 'PC-FAIL'){return [PSCustomObject]@{Status='Failed';Applications=@();ErrorDetail='Access denied'}}
        if($ComputerName -eq 'PC-EMPTY'){return [PSCustomObject]@{Status='Success';Applications=@();ErrorDetail=''}}
        return [PSCustomObject]@{Status='Success';Applications=@([PSCustomObject]@{IstemciAdi=$ComputerName;DisplayName='Webex <test>';DisplayVersion='46.7';Publisher='Test';ProductID='{TEST-ID}';ProductIDKaynak='MSI';RegistryPath='SOFTWARE';RegistryKey='SOFTWARE\Test';Durum='Basarili';HataDetayi=''});ErrorDetail=''}
    }
}
$TestRoot=Join-Path $env:TEMP ('RemoteOpsReportsTest-'+[guid]::NewGuid().ToString('N'))
try{
    $script:BasePath=$TestRoot;$script:OperationID='REPORT-TEST'
    $script:Systems=@('PC-OK','PC-EMPTY','PC-FAIL','PC-OFFLINE')
    $script:ReachableSystems=@('PC-OK','PC-EMPTY','PC-FAIL')
    Import-HostFunction 'ConvertTo-AOInstalledApplicationHtml'
    Import-HostFunction 'Write-AOInstalledApplicationHtmlReport'
    if((ConvertTo-AOInstalledApplicationHtml '<test>') -ne '&lt;test&gt;'){throw 'Imported encoder did not survive importer scope.'}
    $Inventory=Invoke-ApplicationInventoryRequest
    if(-not(Test-Path -LiteralPath $Inventory.ResultCsv)){throw 'Actual inventory writer did not produce HTML.'}
    if($Inventory.Rows.Count -ne 4){throw 'Inventory omitted offline, empty or failed client.'}
    $InventoryCsv=[System.IO.Path]::ChangeExtension($Inventory.ResultCsv,'.csv')
    $InventoryRows=@(Import-Csv -LiteralPath $InventoryCsv -Delimiter ';')
    if(@($InventoryRows|Where-Object{$_.IstemciAdi -eq 'PC-OFFLINE' -and $_.Durum -eq 'Unreachable'}).Count -ne 1){throw 'Offline inventory row was not preserved.'}

    $script:Opened=@()
    $ReportRoot=Join-Path $TestRoot 'Operations\ApplicationInventory\REPORT-TEST'
    Complete-RemoteOpsReports -Result $Inventory -Title 'ApplicationInventory' -OperationID $OperationID -ReportRoot $ReportRoot -Candidates @($Inventory.ResultCsv)
    if($script:Opened.Count -ne 1){throw 'Completion must open one HTML for the inventory, not duplicates.'}
    $Html=Get-Content -LiteralPath $script:Opened[0] -Raw
    if($Html -notmatch 'Webex &lt;test&gt;' -or $Html -notmatch 'PC-OFFLINE' -or $Html -notmatch 'aria-label="Sonu&ccedil; &ouml;zeti"'){throw 'Report data, encoding or summary is missing.'}
    if(-not(Test-Path -LiteralPath (Join-Path $ReportRoot 'Activity.html'))){throw 'Activity HTML must be retained alongside the result report.'}
    if($PreviewPath){Copy-Item -LiteralPath $script:Opened[0] -Destination $PreviewPath -Force}

    $HistoryPath=Join-Path $TestRoot 'History.csv'
    @([PSCustomObject]@{OperationID='OLD';ComputerName='OLD-PC';Status='Success'},[PSCustomObject]@{OperationID='REPORT-TEST';ComputerName='PC-NEW';Status='Failed';ErrorDetail='<script>alert(1)</script>'})|Select-Object OperationID,ComputerName,Status,ErrorDetail|Export-Csv -LiteralPath $HistoryPath -NoTypeInformation -Delimiter ';'
    $script:Opened=@()
    Complete-RemoteOpsReports -Result ([PSCustomObject]@{ResultCsv=$HistoryPath}) -Title 'FilePull' -OperationID $OperationID -ReportRoot (Join-Path $TestRoot 'Operations\FilePull\REPORT-TEST')
    $Html=Get-Content -LiteralPath $script:Opened[0] -Raw
    if($Html -match 'OLD-PC' -or $Html -notmatch 'PC-NEW' -or $Html -match '<script>alert'){throw 'History report exposed old records or unencoded data.'}

    $PackageRows=@(
        [PSCustomObject]@{ComputerName='PC-SKIP';Decision='AlreadyAtTarget';ExecutionStatus='Skipped'},
        [PSCustomObject]@{ComputerName='PC-INSTALL';Decision='InstallMissing';ExecutionStatus='Success';PostCheckStatus='Var';PostCheckErrorDetail='';DisplayVersion='2.1'},
        [PSCustomObject]@{ComputerName='PC-OFF';Decision='Unreachable';ExecutionStatus='NotRun';ErrorDetail='RPC unavailable'},
        [PSCustomObject]@{ComputerName='PC-POST';Decision='InstallMissing';ExecutionStatus='Success';PostCheckStatus='Hata';PostCheckErrorDetail='Verification failed'}
    )
    $Text=(Write-RemoteOpsPackageSummary -Rows $PackageRows -Action INSTALL -CheckMode 'VarlikKontrollu' 6>&1|Out-String)
    if($Text -notmatch 'Installed : 1' -or $Text -notmatch 'Skipped : 2' -or $Text -notmatch 'Error : 1' -or $Text -notmatch 'PC-SKIP - already installed'){throw "Package summary mismatch: $Text"}
    if((Get-RemoteOpsRowCategory $PackageRows[3]) -ne 'issue'){throw 'Failed post-check displayed as success.'}
    Import-HostFunction 'Compare-ApplicationVersion'
    $VersionRows=@([PSCustomObject]@{ComputerName='OLD-VERSION';ExecutionStatus='Success';PostCheckStatus='Var';PostCheckDisplayVersion='1.0';PostCheckErrorDetail=''},[PSCustomObject]@{ComputerName='NEW-VERSION';ExecutionStatus='Success';PostCheckStatus='Var';PostCheckDisplayVersion='2.1';PostCheckErrorDetail=''})
    Set-RemoteOpsPackageOutcome -Rows $VersionRows -Action INSTALL -CheckMode VersiyonKontrollu -TargetVersion '2.0' -VersionComparer ${function:Compare-ApplicationVersion}
    if($VersionRows[0].Outcome -ne 'Error' -or $VersionRows[1].Outcome -ne 'Completed'){throw 'Version-controlled result ignored the actual post-install version.'}
    $FailedUninstall=@([PSCustomObject]@{ExecutionStatus='Success';PostCheckStatus='Var';PostCheckErrorDetail=''})
    Set-RemoteOpsPackageOutcome -Rows $FailedUninstall -Action UNINSTALL -CheckMode VarlikKontrollu
    if($FailedUninstall[0].Outcome -ne 'Error' -or (Get-RemoteOpsRowCategory $FailedUninstall[0]) -ne 'issue'){throw 'Uninstall that leaves the application present must be an error in host and HTML.'}
    $MissingInstall=@([PSCustomObject]@{ExecutionStatus='Success';PostCheckStatus='Yok';PostCheckErrorDetail=''})
    Set-RemoteOpsPackageOutcome -Rows $MissingInstall -Action INSTALL -CheckMode VarlikKontrollu
    if($MissingInstall[0].Outcome -ne 'Error'){throw 'Install with missing application must not count as completed.'}
    if((Get-RemoteOpsRowCategory $PackageRows[2]) -ne 'neutral'){throw 'Unreachable NotRun endpoint must appear under HTML skipped/unreachable.'}
    $MixedPath=Write-ApplicationRows -Name 'Package' -Rows $PackageRows
    $Mixed=@(Import-Csv -LiteralPath $MixedPath -Delimiter ';')
    if($Mixed[1].DisplayVersion -ne '2.1'){throw 'CSV lost success columns after a skipped first row.'}

    $EmptyPath=Write-RemoteOpsResultHtml -Path (Join-Path $TestRoot 'empty.html') -Title 'Empty' -OperationID 'TEST' -Rows @()
    if((Get-Content $EmptyPath -Raw) -notmatch 'Sonu.{0,10}kayd'){throw 'Empty report state missing.'}
    $script:Opened=@()
    $FailureRoot=Join-Path $TestRoot 'failure-report'
    Complete-RemoteOpsReports -Result ([PSCustomObject]@{ResultCsv=(Join-Path $FailureRoot 'Error.csv');Rows=@([PSCustomObject]@{Status='Failed';ErrorDetail='Worker failure'})}) -Title ApplicationCheck -OperationID TEST -ReportRoot $FailureRoot
    if($script:Opened.Count -ne 1 -or -not(Test-Path -LiteralPath (Join-Path $FailureRoot 'Error.csv'))){throw 'Failure must produce a CSV and open its HTML even without an existing source file.'}
    $script:Opened=@()
    Complete-RemoteOpsReports -Result $null -Title RegistryRead -OperationID TEST -ReportRoot (Join-Path $TestRoot 'message-only') -Messages @([PSCustomObject]@{Message='PC1: Registry value read'})
    if($script:Opened.Count -ne 1 -or $script:Opened[0] -notlike '*Activity.html'){throw 'Message-only operation must open its Activity HTML.'}
    function Open-RemoteOpsHtmlFile {param($Path) throw 'Browser unavailable'}
    Complete-RemoteOpsReports -Result ([PSCustomObject]@{ResultCsv=$HistoryPath}) -Title 'FilePull' -OperationID $OperationID -ReportRoot (Join-Path $TestRoot 'browser-failure') -WarningVariable ReportWarnings
    if(@($ReportWarnings).Count -eq 0){throw 'Browser failure was not diagnosed nonfatally.'}
    $LedgerRoot=Join-Path $TestRoot 'LedgerTest'
    $Today=Get-Date
    [void](Write-RemoteOpsLedger -BasePath $LedgerRoot -OperationID 'GUI-L1' -Operation 'RegistryRead' -Category 'Registry' -Identity 'D\u' -Outcomes @([PSCustomObject]@{ComputerName='PC1';Outcome='Success'},[PSCustomObject]@{ComputerName='PC2';Outcome='Error'},[PSCustomObject]@{ComputerName='PC3';Outcome='Skipped'}))
    [void](Write-RemoteOpsLedger -BasePath $LedgerRoot -OperationID 'GUI-L2' -Operation 'ServiceList' -Category 'Services' -Identity 'D\u' -Outcomes @([PSCustomObject]@{ComputerName='pc1';Outcome='Success'}))
    $Legacy=Join-Path $LedgerRoot ('Logs\Operations\FilePull\GUI-{0}-101500-ABCDEF' -f $Today.ToString('yyyyMMdd'));New-Item -ItemType Directory -Path $Legacy -Force|Out-Null
    @([PSCustomObject]@{ComputerName='PC9';Status='Success'},[PSCustomObject]@{ComputerName='PC9';Status='Success'})|Export-Csv (Join-Path $Legacy 'Results.csv') -Delimiter ';' -NoTypeInformation
    $Daily=Get-RemoteOpsDailyReport -BasePath $LedgerRoot -Date $Today
    if($Daily.Total -ne 5 -or $Daily.UniqueComputers -ne 4 -or $Daily.Runs -ne 3 -or $Daily.Success -ne 3 -or $Daily.Error -ne 1 -or $Daily.Skipped -ne 1){throw "Daily totals wrong: $($Daily|Out-String)"}
    $Registry=@($Daily.Categories|Where-Object Name -eq 'Registry')[0]
    if($Registry.Count -ne 3 -or $Registry.Percent -ne 60 -or $Registry.Operations[0].Percent -ne 100 -or @($Daily.Categories|Where-Object Name -eq 'Files').Count -ne 1){throw 'Category counts/percentages (incl. history rebuild) are wrong.'}
    if((Get-RemoteOpsDailyReport -BasePath $LedgerRoot -Date $Today.AddDays(-1)).Total -ne 0){throw 'Other day must be empty.'}
    $DashboardPath=Write-RemoteOpsDailyDashboardHtml -Path (Join-Path $LedgerRoot 'daily.html') -Report $Daily
    if(-not(Test-Path -LiteralPath $DashboardPath)){throw 'Dashboard HTML missing.'}
    if($PreviewPath){Copy-Item -LiteralPath $DashboardPath -Destination ($PreviewPath+'.daily.html') -Force}
    # rows where only some carry an OperationID (e.g. a failing target among successful ones) must still produce the run report
    $MixedRoot=Join-Path $TestRoot 'mixed-rows'
    $script:Opened=@()
    Complete-RemoteOpsReports -Result ([PSCustomObject]@{ResultCsv=(Join-Path $MixedRoot 'Results.csv');Rows=@([PSCustomObject]@{OperationID='MIX';ComputerName='A';Status='Success'},[PSCustomObject]@{ComputerName='B';Status='Failed';ErrorDetail='boom'})}) -Title 'EndpointInventory' -OperationID 'MIX' -ReportRoot $MixedRoot
    $MixedCsv=@(Import-Csv -LiteralPath (Join-Path $MixedRoot 'Results.csv') -Delimiter ';')
    if($MixedCsv.Count -ne 2 -or -not(Test-Path -LiteralPath (Join-Path $MixedRoot 'Results.html'))){throw 'Mixed OperationID rows must still produce Results.csv/html.'}
    Write-Output 'PASS: inventory scope/data, encoded HTML, current-run isolation, automatic report opening, package summary, CSV schema union, empty report and nonfatal browser failure.'
}
finally{if(Test-Path -LiteralPath $TestRoot){Remove-Item -LiteralPath $TestRoot -Recurse -Force -ErrorAction SilentlyContinue}}