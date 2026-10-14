[CmdletBinding()]
param([Parameter(Mandatory=$true)][switch]$RunLive,[string]$OutputDirectory='')
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
if(-not $RunLive){throw 'Explicit -RunLive is required.'}
$Admin=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $Admin){throw 'Administrator token is required to verify local administrative transports.'}
$Root=Split-Path -Parent $PSScriptRoot
if(-not $OutputDirectory){$OutputDirectory=Join-Path $Root 'docs\live-test-v11'}
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Packages.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Deployment.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
$Cases=@(foreach($Operation in @($script:RemoteOpsOperationMeta.Keys|Sort-Object)){
 $Watch=[Diagnostics.Stopwatch]::StartNew()
 try{
  $R=Test-RemoteOpsOperationAccess -ComputerName $env:COMPUTERNAME -Operation $Operation
  [pscustomobject]@{Operation=$Operation;Status=$R.Status;Passed=($R.Status -eq 'Success');Seconds=[math]::Round($Watch.Elapsed.TotalSeconds,2);Detail=$R.Detail}
 }catch{[pscustomobject]@{Operation=$Operation;Status='Exception';Passed=$false;Seconds=[math]::Round($Watch.Elapsed.TotalSeconds,2);Detail=$_.Exception.ToString()}}
})
$Report=[pscustomobject]@{ExecutedAt=(Get-Date).ToString('o');Version=11;ComputerName=$env:COMPUTERNAME;Admin=$Admin;ReadOnly=$true;TargetOperationsInvoked=$false;TemporaryTargetResourcesCreated=$false;Cases=$Cases;Passed=@($Cases|Where-Object Passed -eq $true).Count;Failed=@($Cases|Where-Object Passed -eq $false).Count}
$Report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $OutputDirectory 'ACCESS_LIVE_TEST.json') -Encoding UTF8
$Cases|Export-Csv -LiteralPath (Join-Path $OutputDirectory 'ACCESS_LIVE_TEST.csv') -Encoding UTF8 -NoTypeInformation
if($Report.Failed){exit 1}
