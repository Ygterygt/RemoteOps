$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
$t=$null;$e=$null;$Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.Runner.ps1'),[ref]$t,[ref]$e)
foreach($Name in @('Invoke-TargetBatch','Get-TargetOutcome')){
 $F=$Ast.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq $Name},$true)
 Set-Item ('Function:\'+$Name) $F.Body.GetScriptBlock()
}
function Write-TargetProgress {param($Path,$Total,$Completed,$CurrentTarget,$Stage,$Targets)}
function Write-RemoteOpsLog {param($Level,$Message)}
function Test-RemoteOpsOperationAccess {param($ComputerName,$Operation,$InputValues)
 $script:Events+=('check:'+ $ComputerName)
 [pscustomobject]@{Status=$(if($ComputerName -eq 'OFF'){'Unreachable'}elseif($ComputerName -eq 'DENIED'){'AccessDenied'}else{'Success'});Detail='fixture diagnostic'}
}
$OperationName='FilePull';$Values=[pscustomobject]@{};$Common=@{};$RunReportRoot=$env:TEMP
$script:Events=@();$script:OperationMessages=@();$script:PromptAnswers=New-Object 'Collections.Generic.Queue[string]'
$R=Invoke-TargetBatch -InputTargets @('OFF','DENIED','OK') -RunOperationID TEST -ProgressPath '' -InvokeTarget {
 $script:Events+=('execute:'+ $Systems[0])
 [pscustomobject]@{ResultCsv=(Join-Path $env:TEMP 'test-result.csv');Rows=@([pscustomobject]@{ComputerName=$Systems[0];Status='Success'})}
}
if(($script:Events -join ',') -ne 'check:OFF,check:DENIED,check:OK,execute:OK'){throw 'Every target must be checked and inaccessible targets must never execute'}
if(($R.Outcomes.Outcome -join ',') -ne 'Unreachable,Error,Success' -or $R.Rows.Count -ne 3){throw 'Access results lost or duplicated'}
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Packages.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.RunState.ps1')
$P=New-RemoteOpsPackageDefinition 'Personal script';$Values=[pscustomobject]@{Action='Install';PackageDefinition=$P}
$OperationName='PackageDeployment';$CheckpointRoot=''
$R=Invoke-TargetBatch -InputTargets @('OFF') -RunOperationID TEST -ProgressPath '' -InvokeTarget {throw 'Must never execute'}
if($R.Outcomes[0].PackageName -ne $P.Name -or $R.Outcomes[0].PackageId -ne $P.Id -or $R.Outcomes[0].Detail -notmatch 'fixture diagnostic' -or $R.Rows[0].PackageName -ne $P.Name){throw 'Skipped deployment lost package identity or diagnostics'}
Write-Output 'PASS: common batch gate prevents remote execution and preserves one terminal outcome per target.'
