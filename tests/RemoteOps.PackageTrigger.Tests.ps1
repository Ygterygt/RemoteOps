$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$WorkspaceRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $WorkspaceRoot 'RemoteOps.App\RemoteOps.Reports.ps1')
$Tokens=$null;$Errors=$null
$Ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $WorkspaceRoot 'RemoteOps.App\RemoteOps.Runner.ps1'),[ref]$Tokens,[ref]$Errors)
if($Errors.Count){throw ($Errors|Out-String)}
$script:HostAst=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $WorkspaceRoot 'Modules\ApplicationWorkers.ps1'),[ref]$Tokens,[ref]$Errors)
foreach($Name in @('Invoke-PackageRequest','Convert-ApplicationSearchMode','Write-ApplicationRows')){
    $Definition=$Ast.Find({param($Node)$Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq $Name},$true)
    Set-Item ('Function:\'+$Name) -Value $Definition.Body.GetScriptBlock()
}
$script:WorkerCalls=0;$script:RegistryCalls=0;$script:CleanupSeen=@()
. (Join-Path $WorkspaceRoot 'Modules\FileOperations.ps1')
$Request=[PSCustomObject]@{Operation='PackageTrigger'}
function Get-HostScriptBlock {
    param($VariableName)
    if($VariableName -eq 'RegistryCheckScript'){return {throw 'Unexpected registry worker invocation'}}
    if($VariableName -ne 'PackageScript'){throw "Unexpected worker $VariableName"}
    return {
        param($ComputerName,$PackagePath,$BatFile,$PsExecPath,$PsExecConnectTimeoutSeconds,$PackageTimeoutSeconds,$CollectPackageLogs,$FileOperationsModulePath,$BasePath,$PackageOperation,$OperationID,$LogLookbackMinutes,$RegistryCheckScriptText,$SearchMode,$SearchValue,$WMITimeoutSeconds,$TargetInstallVersion,$PostCheckInitialDelaySec,$PostCheckRetryCount,$PostCheckRetryIntervalSec,$SkipPostCheck,$InstallRequiresVersionMatch,$SelectedApplication,$CleanupLogsUserName='')
        if(-not $SkipPostCheck -or $InstallRequiresVersionMatch -or -not [string]::IsNullOrWhiteSpace($SearchValue)){throw 'Blank identity did not disable presence/version/post-checks.'}
        $script:WorkerCalls++
        $script:CleanupSeen+=,$CleanupLogsUserName
        return [PSCustomObject]@{ComputerName=$ComputerName;ExecutionStatus='Success';ErrorDetail=''}
    }
}
function Invoke-RegistryCheckWorker { param($Worker,$ComputerName,$SearchMode,$SearchValue,$TimeoutSeconds) $script:RegistryCalls++;throw 'Unexpected application check' }
function Write-RemoteOpsLog { param($Level,$Message) }
$Temporary=Join-Path $env:TEMP ('RemoteOpsPackage-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Temporary|Out-Null
try{
    $ModulesRoot=Join-Path $WorkspaceRoot 'Modules'
    # Package execution is mocked; resolving PsExec must not require a real third-party binary.
    $WorkspaceRoot=Join-Path $Temporary 'project'
    New-Item -ItemType Directory -Path $WorkspaceRoot|Out-Null
    Set-Content -LiteralPath (Join-Path $WorkspaceRoot 'PsExec.exe') -Value 'fixture placeholder; never executed'
    $BasePath=$Temporary;$RunReportRoot=Join-Path $Temporary 'BLANK-PACKAGE';$Systems=@('PC-A','PC-B');$ReachableSystems=$Systems;$OperationID='BLANK-PACKAGE'
    foreach($Mode in @('Version controlled','Presence only','Trigger without checks')){
        $Values=[PSCustomObject]@{PackagePath='\\server\packages';PackageFile='install.bat';Action='Install';CheckMode=$Mode;SearchType='DisplayName exact';Application='';Version='';RegistryKey='';CollectLogs=$false}
        $Result=Invoke-PackageRequest -InputValues $Values
        if($Result.Rows.Count -ne 2 -or @($Result.Rows|Where-Object{$_.Decision -ne 'UnconditionalTrigger' -or $_.Outcome -ne 'Completed'}).Count){throw "Blank identity did not trigger both targets for $Mode"}
    }
    if($script:WorkerCalls -ne 6 -or $script:RegistryCalls -ne 0){throw 'Unexpected package/check invocation counts.'}
    # ---- opt-in log cleanup: user name is validated and only handed to the worker when logs are collected
    $script:CleanupSeen=@()
    $Values=[PSCustomObject]@{PackagePath='\\server\packages';PackageFile='install.bat';Action='Install';CheckMode='Trigger without checks';SearchType='DisplayName exact';Application='';Version='';RegistryKey='';CollectLogs=$true}
    $Request=[PSCustomObject]@{Operation='PackageTrigger';CleanupPackageLogs=$true;CleanupUserName='yigitery0'}
    [void](Invoke-PackageRequest -InputValues $Values)
    if(($script:CleanupSeen -join ',') -ne 'yigitery0,yigitery0'){throw "Cleanup user name was not passed to every worker call: $($script:CleanupSeen -join ',')"}
    $script:CleanupSeen=@();$Values.CollectLogs=$false
    [void](Invoke-PackageRequest -InputValues $Values)
    if(@($script:CleanupSeen|Where-Object{$_}).Count -ne 0){throw 'Cleanup must not be requested when log collection is not ticked.'}
    $script:CleanupSeen=@();$Values.CollectLogs=$true;$Request.CleanupUserName='admin'
    [void](Invoke-PackageRequest -InputValues $Values)
    if(@($script:CleanupSeen|Where-Object{$_}).Count -ne 0){throw 'A generic user name must never reach the worker.'}
    $script:CleanupSeen=@();$Request.CleanupPackageLogs=$false;$Request.CleanupUserName='yigitery0'
    [void](Invoke-PackageRequest -InputValues $Values)
    if(@($script:CleanupSeen|Where-Object{$_}).Count -ne 0){throw 'Cleanup must stay off unless enabled in Settings.'}
    Write-Output 'PASS: blank package identity skips registry, version and post-checks in all three check modes; log-cleanup user name gating; mock workers only.'
}
finally{Remove-Item -LiteralPath $Temporary -Recurse -Force -ErrorAction SilentlyContinue}
