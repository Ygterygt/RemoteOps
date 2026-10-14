$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Packages.ps1');. (Join-Path $Root 'RemoteOps.App\RemoteOps.Deployment.ps1');. (Join-Path $Root 'RemoteOps.App\RemoteOps.RunState.ps1')
$t=$null;$e=$null;$Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.Runner.ps1'),[ref]$t,[ref]$e)
foreach($Name in @('Invoke-SavedPackageDeploymentRequest','Convert-ApplicationSearchMode','Invoke-RegistryCheckWorker')){. ([scriptblock]::Create($Ast.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq $Name},$true).Extent.Text))}
function Import-HostFunction {param($FunctionName)}
function Compare-ApplicationVersion {param($CurrentVersion,$TargetVersion)return [PSCustomObject]@{Comparable=$true;Result=0}}
$script:PackageCalls=0
function Get-HostScriptBlock {param($VariableName)
    if($VariableName -eq 'RegistryCheckScript'){return {param($ComputerName,$SearchMode,$SearchValue,$TimeoutSeconds) return [PSCustomObject]@{Status='Var';DisplayVersion='2.0';ErrorDetail='';Applications=@([PSCustomObject]@{RegistryKey='OTHER-KEY';DisplayVersion='2.0';DisplayName='App'})}}}
    return {$script:PackageCalls++;return [PSCustomObject]@{ExecutionStatus='Success';ExitCode=0;ErrorDetail=''}}
}
function Invoke-RemoteOpsPackageProbe {param($Definition,$ComputerName,$PsExecPath)return $true}
function Test-RemoteOpsTargetAccess {param($ComputerName)return [PSCustomObject]@{Status='Success';Detail='fixture'}}
function Write-RemoteOpsLog {param($Level,$Message)}
function Write-ApplicationRows {param($Name,$Rows)return (Join-Path $BasePath 'results.csv')}
$Temp=Join-Path $env:TEMP ('ROIdentity-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path $Temp -Force|Out-Null;Set-Content (Join-Path $Temp 'PsExec.exe') 'placeholder'
    $WorkspaceRoot=$Temp;$ModulesRoot=Join-Path $Root 'Modules';$BasePath=$Temp;$RunReportRoot=Join-Path $Temp 'IDENTITY';$Systems=@('PC1');$OperationID='IDENTITY';$CancelPath='';$CheckpointRoot=Join-Path $Temp 'state';$Request=[PSCustomObject]@{CleanupPackageLogs=$false}
    $P=New-RemoteOpsPackageDefinition 'App';$P.Uninstall.Enabled=$true;$P.Uninstall.PackagePath='\\server\share';$P.Uninstall.PackageFile='remove.cmd';$P.Uninstall.Application='App';$P.Uninstall.RegistryKey='REQUIRED-KEY'
    $Result=Invoke-SavedPackageDeploymentRequest ([PSCustomObject]@{PackageDefinition=$P;Action='Uninstall'})
    if($script:PackageCalls -ne 0 -or $Result.Outcomes[0].Outcome -ne 'Error'){throw 'Exact registry key mismatch allowed package removal.'}
    Write-Output 'PASS: a nonmatching exact registry key prevents package execution even with one display-name match.'
}finally{if(Test-Path $Temp){Remove-Item $Temp -Recurse -Force}}
