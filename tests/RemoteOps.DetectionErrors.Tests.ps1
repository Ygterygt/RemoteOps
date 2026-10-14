$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Packages.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Deployment.ps1')
$P=New-RemoteOpsPackageDefinition 'Test';$P.TargetVersion='2.0';$P.DowngradeEnabled=$true
foreach($A in 'Install','Uninstall'){$P.$A.Enabled=$true;$P.$A.PackagePath='\\server\share';$P.$A.PackageFile='test.cmd';$P.$A.Application='ID';$P.$A.SearchType='ProductID'}
$P.Downgrade=($P.Install|Select-Object *);$P.Downgrade.Enabled=$true;$P.Downgrade.CheckMode='Version controlled';$P.DowngradeVersion='2.0'
foreach($Action in 'Install','Uninstall','Downgrade'){
 foreach($Case in @(@('Hata','The RPC server is unavailable. (0x800706BA)'),@('Hata','Access is denied. (0x80070005)'),@('CokluEslesme','Two matching applications'))){
  $script:DetectionStatus=$Case[0];$script:DetectionDetail=$Case[1]
  $Result=Invoke-RemoteOpsPackageDeployment -Definition $P -Action $Action -ComputerName PC1 -OperationID TEST -Detect {param($Part,$Computer)[pscustomobject]@{Status=$script:DetectionStatus;DisplayVersion='';ErrorDetail=$script:DetectionDetail}} -Execute {throw 'Execution must not run'} -ValidateSource {throw 'Source check must not run'} -VersionComparer {throw 'Version comparison must not run'}
  if($Result.Outcome.Outcome -ne 'Error' -or $Result.Outcome.Detail -notlike ('*'+$Case[1]+'*')){throw "$Action lost detection error: $($Result.Outcome.Detail)"}
  if($Case[0] -eq 'Hata' -and $Result.Outcome.Detail -match 'identity could not'){throw 'Connection/query failure mislabeled identity failure.'}
 }
}
Write-Output 'PASS: install/uninstall/downgrade preserve RPC, access and ambiguous-match errors without executing.'
