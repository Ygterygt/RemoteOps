$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Packages.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Deployment.ps1')
$script:Transports=@()
function Test-RemoteOpsTargetAccess {param($ComputerName,$Transport='Management',$Namespace='root\default')
 $script:Transports+=($Transport+'|'+$Namespace)
 return [pscustomobject]@{Status='Success';Detail='fixture'}
}
foreach($Operation in @('FilePull','FilePush','FileDelete','FileCompare','FileBrowser','FileRestore','FileRollback')){
 $script:Transports=@();$R=Test-RemoteOpsOperationAccess PC1 $Operation
 if($R.Status -ne 'Success' -or ($script:Transports -join ',') -ne 'SMB|root\default'){throw "$Operation must check SMB without requiring WMI"}
}
foreach($Operation in @('RegistryRead','RegistryEdit','RegistryDelete','RegistryRollback','ServiceList','ServiceControl','ServiceStartup','ServiceTaskRollback','ScheduledTaskList','ScheduledTaskAction','ScheduledTaskDelete','ProcessQuery','ProcessKill','EndpointInventory','HealthCheck','ApplicationCheck','ApplicationInventory','PackageTrigger','PackageDeployment')){
 $script:Transports=@();$R=Test-RemoteOpsOperationAccess PC1 $Operation
 if($R.Status -ne 'Success' -or $script:Transports.Count -eq 0){throw "$Operation omitted preflight"}
}
Write-Output 'PASS: operation-specific access selection covers every built-in operation.'
