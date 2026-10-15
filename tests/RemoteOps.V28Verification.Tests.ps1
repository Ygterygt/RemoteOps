$ErrorActionPreference='Stop'
$Root=Split-Path $PSScriptRoot -Parent
$File=Join-Path $Root 'RemoteOps.App\RemoteOps.Verification.ps1'
if(-not(Test-Path $File)){throw 'FAIL: automatic postcondition verification is missing'}
. $File
. (Join-Path $Root 'RemoteOps.App\RemoteOps.RecipeResults.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
function Assert($Value,$Message){if(-not $Value){throw $Message}}
function Row { [pscustomobject]@{ComputerName='SIM-PC1';Status='Success';ReturnValue=0;ValueType='REG_DWORD';AtlananAdet=0} }
function ProbeValue($State='Running',$Startup='Automatic',$Exists=$true,$Type='',$Value='') { [pscustomobject]@{Exists=$Exists;State=$State;Startup=$Startup;ValueType=$Type;Value=$Value;Detail=''} }
$script:Reads=0
foreach($Action in @('Start','Restart','Stop')){
 $R=Row;$script:ExpectedState=if($Action -eq 'Stop'){'Stopped'}else{'Running'}
 Set-RemoteOpsPostVerification ServiceControl @{ServiceName='OfflineDemo';Action=$Action} @($R) SIM-PC1 -Probe {param($c,$t) $script:Reads++;ProbeValue $script:ExpectedState} -TimeoutSeconds 0
 Assert ($R.StepName -and $R.Operation -ceq 'ServiceControl') 'Standalone result has no readable operation name'
 Assert ($R.VerificationStatus -ceq 'Verified' -and $R.CommandStatus -ceq 'Success' -and $R.VerifiedAt) ('Expected verification '+$Action)
}
$R=Row;Set-RemoteOpsPostVerification ServiceStartup @{ServiceName='OfflineDemo';StartupType='Manual'} @($R) SIM-PC1 -Probe {ProbeValue Running Manual} -TimeoutSeconds 0
Assert ($R.VerificationStatus -ceq 'Verified') 'Startup readback missing'
$R=Row;Set-RemoteOpsPostVerification ServiceControl @{ServiceName='OfflineDemo';Action='Start'} @($R) SIM-PC1 -Probe {ProbeValue Stopped} -TimeoutSeconds 0
Assert ($R.Status -ceq 'Success' -and $R.CommandStatus -ceq 'Success' -and $R.VerificationStatus -ceq 'Failed') 'No-op success was not distinguished'
$D=Get-RemoteOpsRecipeStepDecision ServiceControl @{} @($R)
Assert ($D.Decision -ceq 'Stop' -and $D.Outcome -ceq 'Error') 'No-op did not stop chain'
Assert ((Get-RemoteOpsRowCategory $R) -ceq 'issue') 'Report painted verification failure green'
$R=Row;Set-RemoteOpsPostVerification ServiceControl @{ServiceName='OfflineDemo';Action='Start'} @($R) SIM-PC1 -Probe {ProbeValue '' '' $false} -TimeoutSeconds 0
Assert ($R.VerificationStatus -ceq 'Failed') 'Missing service was considered reached'
$R=Row;Set-RemoteOpsPostVerification ServiceControl @{ServiceName='OfflineDemo';Action='Start'} @($R) SIM-PC1 -Probe {throw 'read denied'} -TimeoutSeconds 0
Assert ($R.VerificationStatus -ceq 'Unknown' -and $R.VerificationDetail -like '*read denied*') 'Read error was called mismatch or success'
Assert ((Get-RemoteOpsRecipeStepDecision ServiceControl @{} @($R)).Outcome -ceq 'Indeterminate') 'Unknown verification did not stop as uncertain'
$R=Row;$R.Status='Failed';$script:Reads=0
Set-RemoteOpsPostVerification ServiceControl @{ServiceName='OfflineDemo';Action='Start'} @($R) SIM-PC1 -Probe {$script:Reads++;throw 'must not read'} -TimeoutSeconds 0
Assert ($script:Reads -eq 0 -and $R.VerificationStatus -ceq 'NotPerformed') 'Failed command was verified'
$R=Row;Set-RemoteOpsPostVerification ServiceControl @{ServiceName='OfflineDemo';Action='Start'} @($R) SIM-PC1 -Probe {[pscustomobject]@{Exists=$true;State='banana'}} -TimeoutSeconds 0
Assert ($R.VerificationStatus -ceq 'Unknown') 'Malformed provider evidence accepted'
foreach($Case in @(@('REG_DWORD','0x10','16'),@('REG_QWORD','18446744073709551615','18446744073709551615'),@('REG_SZ','16.0.444','16.0.444'),@('REG_MULTI_SZ','["a","b"]','["a","b"]'),@('REG_EXPAND_SZ','%TEMP%','%TEMP%'))){
 $R=Row;$R.ValueType=$Case[0];$script:ActualType=$Case[0];$script:ActualValue=$Case[2]
 Set-RemoteOpsPostVerification RegistryEdit @{RegistryPath='HKLM\SOFTWARE\Fixture';ValueName='Version';ValueType='Auto';Value=$Case[1]} @($R) SIM-PC1 -Probe {ProbeValue '' '' $true $script:ActualType $script:ActualValue} -TimeoutSeconds 0
 Assert ($R.VerificationStatus -ceq 'Verified') ('Typed readback '+$Case[0])
}
$R=Row;Set-RemoteOpsPostVerification RegistryEdit @{RegistryPath='HKLM\SOFTWARE\Fixture';ValueName='Version';Value='1'} @($R) SIM-PC1 -Probe {ProbeValue '' '' $true REG_SZ '1'} -TimeoutSeconds 0
Assert ($R.VerificationStatus -ceq 'Failed') 'Registry type change was accepted'
$R=Row;Set-RemoteOpsPostVerification RegistryDelete @{RegistryPath='HKLM\SOFTWARE\Fixture';ValueName='Version'} @($R) SIM-PC1 -Probe {ProbeValue '' '' $false} -TimeoutSeconds 0
Assert ($R.VerificationStatus -ceq 'Verified') 'Delete absence not verified'
$R=Row;Set-RemoteOpsPostVerification RegistryDelete @{RegistryPath='HKLM\SOFTWARE\Fixture';ValueName='Version'} @($R) SIM-PC1 -Probe {ProbeValue '' '' $true REG_DWORD '1'} -TimeoutSeconds 0
Assert ($R.VerificationStatus -ceq 'Failed') 'Delete no-op accepted'
Write-Output 'PASS service and registry postconditions; failure/unknown precedence; no probe after command failure'

$script:Attempts=0;$R=Row
Set-RemoteOpsPostVerification ServiceControl @{ServiceName='OfflineDemo';Action='Start'} @($R) SIM-PC1 -Probe {$script:Attempts++;if($script:Attempts -lt 3){ProbeValue 'Start Pending'}else{ProbeValue Running}} -TimeoutSeconds 3
Assert ($R.VerificationStatus -ceq 'Verified' -and $script:Attempts -eq 3) 'Service transition was not polled until expected state'
$R=Row;$R.ReturnValue=5;$script:Reads=0
Set-RemoteOpsPostVerification RegistryEdit @{RegistryPath='HKLM\SOFTWARE\Fixture';ValueName='Version';Value='1'} @($R) SIM-PC1 -Probe {$script:Reads++;throw 'must not probe'}
Assert ($R.VerificationStatus -ceq 'NotPerformed' -and $script:Reads -eq 0) 'Failed registry return code was verified'
