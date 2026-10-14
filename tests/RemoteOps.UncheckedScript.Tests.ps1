$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Packages.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Deployment.ps1')
$P=New-RemoteOpsPackageDefinition 'Personal script'
$P.Category='Personal scripts';$P.Install.Enabled=$true;$P.Install.CheckMode='Trigger without checks'
$P.Install.PackagePath='\\server\scripts';$P.Install.PackageFile='maintenance.ps1'
Assert-RemoteOpsPackageDefinition $P Install
$script:Calls=0
$R=Invoke-RemoteOpsPackageDeployment -Definition $P -Action Install -ComputerName PC1 -OperationID TEST -Detect {throw 'Unchecked script must not query installed applications'} -VersionComparer {throw 'Unchecked script must not compare versions'} -ValidateSource {param($Part,$Target)if($Part.PackageFile -ne 'maintenance.ps1'){throw 'Wrong source'}} -Execute {
 param($Part,$Action,$Policy,$StepId)
 $script:Calls++
 [pscustomobject]@{ExecutionStatus='Success';ExitCode=0;ErrorDetail=''}
}
if($R.Outcome.Outcome -ne 'Success' -or $script:Calls -ne 1 -or $R.Outcome.TargetVersion -ne ''){throw 'Versionless saved script failed'}
function Test-RemoteOpsTargetAccess {param($ComputerName,$Transport,$Namespace)
 if($Transport -ne 'SMB'){throw 'Unchecked script must not depend on WMI'}
 [pscustomobject]@{Status='Success';Detail='SMB fixture'}
}
$R=Test-RemoteOpsOperationAccess PC1 PackageDeployment ([pscustomobject]@{Action='Install';PackageDefinition=$P})
if($R.Status -ne 'Success'){throw 'Unchecked script rejected at access check'}
$R=Test-RemoteOpsOperationAccess PC1 PackageTrigger ([pscustomobject]@{CheckMode='Presence only';Application=''})
if($R.Status -ne 'Success'){throw 'Legacy versionless trigger must retain SMB-only access'}
Write-Output 'PASS: versionless saved PowerShell script executes once without identity/version checks or WMI dependency.'
