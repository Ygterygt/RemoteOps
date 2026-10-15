$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
$Module=Join-Path $Root 'RemoteOps.App\RemoteOps.History.ps1'
if(Test-Path $Module){. $Module}
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
$Sandbox=Join-Path $env:TEMP ('RemoteOpsHistory-'+[guid]::NewGuid().ToString('N'))
try{
 $RunRoot=Join-Path $Sandbox 'Logs\Operations\PackageDeployment\GUI-20261015-110000-A'
 New-Item -ItemType Directory -Path $RunRoot -Force|Out-Null
 $Rows=@(
 [pscustomobject]@{ComputerName='PC-I';Step='Install';Status='Failed';ErrorDetail='old step';OperationID='GUI-20261015-110000-A'},
 [pscustomobject]@{ComputerName='PC-I';Step='Result';Status='Success';ErrorDetail='';OperationID='GUI-20261015-110000-A'})
 $Rows|Export-Csv (Join-Path $RunRoot 'Results.csv') -Delimiter ';' -NoTypeInformation
 [void](Write-RemoteOpsLedger -BasePath $Sandbox -OperationID 'GUI-20261015-110000-A' -Operation PackageDeployment -Outcomes @([pscustomobject]@{ComputerName='PC-I';Outcome='Success';CompletedAt=[datetime]'2026-10-15T11:00:00'}))
 $Old=Join-Path $Sandbox 'Logs\Operations\FilePull\GUI-20261014-100000-B'
 New-Item -ItemType Directory -Path $Old -Force|Out-Null
 @([pscustomobject]@{IstemciAdi='PC-I';Durum='Failed';HataDetayi='Access denied'})|Export-Csv (Join-Path $Old 'Results.csv') -Delimiter ';' -NoTypeInformation
 $Broken=Join-Path $Sandbox 'Logs\Operations\FilePull\BROKEN'
 New-Item -ItemType Directory -Path $Broken -Force|Out-Null
 'wrong;headers'|Set-Content (Join-Path $Broken 'Results.csv')
 $Index=Get-RemoteOpsHistoryIndex $Sandbox
 Assert ($Index.Runs.Count -eq 3) 'History omitted or duplicated runs'
 Assert ($Index.Issues.Count -gt 0) 'Malformed CSV must be visible'
 $Run=@($Index.Runs|Where-Object OperationID -eq 'GUI-20261015-110000-A')[0]
 $Detail=Get-RemoteOpsHistoryDetails $Sandbox $Run
 Assert ($Detail.Targets.Count -eq 1 -and $Detail.Rows.Count -eq 2) 'Steps counted as computers'
 Assert ($Detail.Targets[0].Outcome -eq 'Success') 'Terminal success lost'
 $Found=Find-RemoteOpsHistoryRuns -Runs $Index.Runs -Computer 'pc-i' -Outcome Error -From ([datetime]'2026-10-14') -To ([datetime]'2026-10-14')
 Assert ($Found.Total -eq 1 -and $Found.Items[0].OperationID -eq 'GUI-20261014-100000-B') 'Filter/date/legacy normalization failed'
 Assert ((Find-RemoteOpsHistoryRuns -Runs $Index.Runs -Computer 'PC-*').Total -eq 0) 'Filter must be literal'
 $Page=Find-RemoteOpsHistoryRuns -Runs $Index.Runs -PageSize 1 -Page 1
 Assert ($Page.Items.Count -eq 1 -and $Page.Total -eq 3) 'Paging failed'
 Remove-Item (Join-Path $RunRoot 'Results.csv')
 $Missing=Get-RemoteOpsHistoryDetails $Sandbox $Run
 Assert ($Missing.Targets.Count -eq 1 -and $Missing.Issues.Count -gt 0) 'Ledger target must survive missing results'
 foreach($Outside in @((Join-Path $Sandbox 'domains.json'),(Join-Path $Sandbox 'Logs\Operations2\secret.txt'),(Join-Path $Sandbox 'Logs\Operations\..\secret.txt'))){
  $Rejected=$false;try{Resolve-RemoteOpsHistoryPath $Sandbox $Outside|Out-Null}catch{$Rejected=$true};Assert $Rejected 'Outside path accepted'
 }
 $Named=Join-Path $Sandbox 'Logs\Operations\FilePull\NAMED'
 New-Item -ItemType Directory -Path $Named -Force|Out-Null
 @([pscustomobject]@{IstemciAdi='PC-NAMED';Durum='Success'})|Export-Csv (Join-Path $Named 'NAMED_FilePull.csv') -Delimiter ';' -NoTypeInformation
 '<html>report</html>'|Set-Content (Join-Path $Named 'NAMED_FilePull.html')
 $Index=Get-RemoteOpsHistoryIndex $Sandbox
 $NamedRun=@($Index.Runs|Where-Object OperationID -eq 'NAMED')[0]
 Assert ($NamedRun.Targets.Count -eq 1) 'Actual module-named report CSV was not indexed'
 $NamedDetails=Get-RemoteOpsHistoryDetails $Sandbox $NamedRun
 Assert ($NamedDetails.Rows.Count -eq 1 -and @($NamedDetails.Artifacts|Where-Object Kind -eq 'NAMED_FilePull.html').Count -eq 1) 'Module report detail missing'
 $Fatal=Join-Path $Sandbox 'Logs\Operations\FilePull\FATAL'
 New-Item -ItemType Directory -Path $Fatal -Force|Out-Null
 @([pscustomobject]@{Operation='FilePull';Status='Failed';ErrorDetail='Fatal runner exception'})|Export-Csv (Join-Path $Fatal 'Error.csv') -Delimiter ';' -NoTypeInformation
 $Index=Get-RemoteOpsHistoryIndex $Sandbox
 $FatalRun=@($Index.Runs|Where-Object OperationID -eq FATAL)[0]
 Assert ($FatalRun.Targets.Count -eq 1 -and $FatalRun.Targets[0].Outcome -eq 'Error') 'Run-level error without computer omitted'
 $Empty=Join-Path $Sandbox 'Logs\Operations\FilePull\EMPTY'
 New-Item -ItemType Directory -Path $Empty -Force|Out-Null
 '"ComputerName";"Status"'|Set-Content (Join-Path $Empty 'EMPTY_FilePull.csv')
 '<html>empty report</html>'|Set-Content (Join-Path $Empty 'EMPTY_FilePull.html')
 $Mixed=Join-Path $Sandbox 'Logs\Operations\FilePull\MIXED'
 New-Item -ItemType Directory -Path $Mixed -Force|Out-Null
 @([pscustomobject]@{ComputerName='PC-A';Status='Success';OperationID='MIXED'},[pscustomobject]@{ComputerName='PC-A';Status='Failed';OperationID='MIXED-UNRELATED'})|Export-Csv (Join-Path $Mixed 'Results.csv') -Delimiter ';' -NoTypeInformation
 $Index=Get-RemoteOpsHistoryIndex $Sandbox
 $EmptyRun=@($Index.Runs|Where-Object OperationID -eq EMPTY)[0]
 $EmptyDetails=Get-RemoteOpsHistoryDetails $Sandbox $EmptyRun
 Assert ($EmptyDetails.Rows.Count -eq 0 -and @($EmptyDetails.Artifacts|Where-Object{ $_.Kind -eq 'EMPTY_FilePull.html' -and $_.Exists}).Count -eq 1) 'Empty report HTML inaccessible'
 $MixedRun=@($Index.Runs|Where-Object OperationID -eq MIXED)[0]
 Assert ($MixedRun.Targets[0].Outcome -eq 'Success') 'Index mixed results from unrelated operation identity'
 $MixedDetails=Get-RemoteOpsHistoryDetails $Sandbox $MixedRun
 Assert ($MixedDetails.Rows.Count -eq 1) 'Details accepted unrelated prefix run'
 Write-Output 'PASS: history deduplication, terminal outcomes, legacy/named rows, filters, paging, corrupt/missing data, path boundary.'
}finally{if(Test-Path $Sandbox){Remove-Item -LiteralPath $Sandbox -Recurse -Force}}
