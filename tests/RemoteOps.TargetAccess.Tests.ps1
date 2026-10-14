$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Packages.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Deployment.ps1')
$P=New-RemoteOpsPackageDefinition 'Access';$P.TargetVersion='2.0';$P.DowngradeEnabled=$true
foreach($A in 'Install','Uninstall'){$P.$A.Enabled=$true;$P.$A.PackagePath='\\server\share';$P.$A.PackageFile='test.cmd';$P.$A.Application='ID';$P.$A.SearchType='ProductID'}
$P.Downgrade=($P.Install|Select-Object *);$P.Downgrade.Enabled=$true;$P.Downgrade.CheckMode='Version controlled';$P.DowngradeVersion='2.0'
foreach($Action in 'Install','Uninstall','Downgrade'){
 foreach($Status in 'Unreachable','AccessDenied','Failed'){
  $script:AccessStatus=$Status
  $R=Invoke-RemoteOpsPackageDeployment -Definition $P -Action $Action -ComputerName PC1 -OperationID TEST -CheckAccess {param($Computer)[pscustomobject]@{Status=$script:AccessStatus;Detail='original diagnostic'}} -Detect {throw 'Detection must not run'} -Execute {throw 'Execution must not run'} -ValidateSource {throw 'Source check must not run'} -VersionComparer {throw 'Compare must not run'}
  $Expected=if($Status -eq 'Unreachable'){'Unreachable'}else{'Error'}
  if($R.Outcome.Outcome -ne $Expected -or $R.Outcome.Detail -notmatch 'original diagnostic' -or @($R.Rows|Where-Object Step -ne Result).Count -ne 1){throw "$Action / $Status did not stop at access gate"}
 }
}
foreach($Case in @(@('800706BA','Unreachable'),@('80070035','Unreachable'),@('80070005','AccessDenied'),@('80041003','AccessDenied'),@('80004005','Failed'))){
 $script:Code=[BitConverter]::ToInt32([BitConverter]::GetBytes([Convert]::ToUInt32($Case[0],16)),0)
 $R=Test-RemoteOpsTargetAccess PC1 -Connect {param($Computer,$Seconds)throw (New-Object Runtime.InteropServices.COMException 'fixture' ,$script:Code)}
 if($R.Status -ne $Case[1] -or $R.Detail -notmatch $Case[0]){throw "Incorrect classification for $($Case[0]): $($R.Status) $($R.Detail)"}
}
$R=Test-RemoteOpsTargetAccess PC1 -Connect {param($Computer,$Seconds)if($Computer -ne 'PC1'){throw 'Wrong target'}}
if($R.Status -ne 'Success'){throw 'Successful connection failed preflight'}
Write-Output 'PASS: real-management access gate blocks unreachable/denied/unknown before all package actions; structured error codes kept distinct.'
