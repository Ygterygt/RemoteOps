$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
$Temp=Join-Path $env:TEMP ('RemoteOpsReportSummary-'+[guid]::NewGuid().ToString('N'))
try{
    $Rows=@(
        [PSCustomObject]@{ComputerName='PC1';OperationID='RUN';PackageId='PKG';PackageName='Example';Action='Install';Step='Install';Status='Failed';ExitCode=50010;RebootRequired=$false;LogDestination='C:\Logs\PC1';LogCollectionStatus='Success';ErrorDetail='Source wrapper failed'},
        [PSCustomObject]@{ComputerName='PC1';OperationID='RUN';PackageId='PKG';PackageName='Example';Action='Install';Step='Result';Status='Error';ExitCode=$null;RebootRequired=$false;LogDestination='';LogCollectionStatus='';ErrorDetail='Package failed'}
    )
    $Path=Write-RemoteOpsResultHtml -Path (Join-Path $Temp 'Results.html') -Title PackageDeployment -OperationID RUN -Rows $Rows
    $Text=Get-Content $Path -Raw -Encoding UTF8
    $Main=[regex]::Match($Text,'(?s)<table id="results".*?<tbody>(.*?)</tbody>').Groups[1].Value
    if([regex]::Matches($Main,'<tr\s+data-client=').Count -ne 1){throw 'Main package report duplicates execution and terminal rows for one target.'}
    if($Main -notmatch '50010' -or $Main -notmatch 'C:\\Logs\\PC1' -or $Main -notmatch 'data-outcome="Error"'){throw 'Single terminal target summary lost the real exit code/log destination/outcome.'}
    if($Text -notmatch '<details' -or $Text -notmatch 'Source wrapper failed'){throw 'Execution diagnostics were discarded instead of retained as step details.'}
    if($Rows[1].ExitCode -ne $null -or $Rows[1].LogDestination -ne ''){throw 'Report rendering mutated durable source rows.'}
    $Fallback=[PSCustomObject]@{ComputerName='PC-FAIL';Status='Failed';ErrorDetail='Worker failed before terminal metadata'}
    $MixedPath=Write-RemoteOpsResultHtml -Path (Join-Path $Temp 'Mixed.html') -Title PackageDeployment -OperationID RUN -Rows @($Rows+$Fallback)
    $MixedText=Get-Content $MixedPath -Raw -Encoding UTF8
    $MixedMain=[regex]::Match($MixedText,'(?s)<table id="results".*?<tbody>(.*?)</tbody>').Groups[1].Value
    if([regex]::Matches($MixedMain,'<tr\s+data-client=').Count -ne 2 -or $MixedMain -notmatch 'data-client="PC-FAIL"' -or $MixedMain -notmatch 'Worker failed before terminal metadata'){throw 'A target without a terminal Result disappeared from the mixed report summary.'}
    Write-Output 'PASS: single package target summary with exit/log metadata and separate preserved step details.'
}finally{if(Test-Path -LiteralPath $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force}}
