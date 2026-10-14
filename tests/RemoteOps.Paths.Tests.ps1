$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
$ExpectedBase='C:\Temp\YD_RemoteOps.App'
$Tokens=$null;$Errors=$null
foreach($Relative in @('RemoteOps.App\RemoteOps.Runner.ps1')){
    $Ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root $Relative),[ref]$Tokens,[ref]$Errors)
    if($Errors.Count){throw ($Errors|Out-String)}
    $Assignment=$Ast.Find({param($Node)$Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $Node.Left.Extent.Text -eq '$BasePath'},$true)
    if((Invoke-Expression $Assignment.Right.Extent.Text) -ne $ExpectedBase){throw "Incorrect base path: $Relative"}
}
$RunnerAst=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.Runner.ps1'),[ref]$Tokens,[ref]$Errors)
$LogFunction=$RunnerAst.Find({param($Node)$Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq 'Write-RemoteOpsLog'},$true)
Set-Item Function:\Write-RemoteOpsLog -Value $LogFunction.Body.GetScriptBlock()
$AppAst=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'),[ref]$Tokens,[ref]$Errors)
if($Errors.Count){throw ($Errors|Out-String)}
$Operation=[PSCustomObject]@{Name='ScheduledTaskList'}
foreach($Name in @('$ProgressRoot','$LogRoot')){
    $Assignment=$AppAst.Find({param($Node)$Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $Node.Left.Extent.Text -eq $Name},$true)
    if((Invoke-Expression $Assignment.Right.Extent.Text) -ne "$ExpectedBase\Logs\Operations\ScheduledTaskList"){throw "UI path outside Logs: $Name"}
}
$BasePath=$ExpectedBase;$OperationName='ScheduledTaskList';$OperationID='PATH-TEST'
$Assignment=$RunnerAst.Find({param($Node)$Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $Node.Left.Extent.Text -eq '$RunReportRoot'},$true)
if((Invoke-Expression $Assignment.Right.Extent.Text) -ne "$ExpectedBase\Logs\Operations\ScheduledTaskList\PATH-TEST"){throw 'Runner report path is outside Logs.'}
$Batch=Get-Content (Join-Path $Root 'RemoteOps.App\RemoteOps.App.bat') -Raw
if($Batch -match 'SYSTEMROOT%\\TEMP' -or $Batch -notmatch 'CALL :MAIN >> "C:\\Temp\\YD_RemoteOps.App\\Logs\\'){throw 'Launcher log path is incorrect.'}
function Register-AOModule { param($Name,$Version,$MinimumHostApiVersion,$SourcePath,$Initializer) }
function Register-AOModuleOperation { param($ModuleName,$Name,$DisplayName,$EntryPointName,$Handler) }
. (Join-Path $Root 'Modules\FileOperations.ps1')
$Temporary=Join-Path $env:TEMP ('RemoteOpsPaths-'+[guid]::NewGuid().ToString('N'))
try{
    $BasePath=Join-Path $Temporary 'data'
    $RemoteTemp=Join-Path $Temporary 'remote'
    New-Item -ItemType Directory -Path $RemoteTemp -Force|Out-Null
    Set-Content -LiteralPath (Join-Path $RemoteTemp 'sample.log') -Value 'Mock remote log'
    $script:MockRemoteTemp=$RemoteTemp
    function ConvertTo-AORemoteAdminPath { param($ComputerName,$LocalPath) return $script:MockRemoteTemp }
    Write-RemoteOpsLog -Level INFO -Message 'Path check'
    if(-not(Test-Path -LiteralPath (Join-Path $BasePath 'Logs\Operations\ScheduledTaskList\PATH-TEST\RemoteOps.log'))){throw 'Technical log was not written under Logs.'}
    $Collected=Get-AORecentLogs -ComputerName 'PC-TEST' -BasePath $BasePath -OperationName 'Install' -OperationID 'PATH-TEST'
    $ExpectedPull=Join-Path $BasePath 'PulledLogs\PC-TEST\PATH-TEST_Install'
    if(-not $Collected.Success -or $Collected.Destination -ne $ExpectedPull -or -not(Test-Path (Join-Path $ExpectedPull 'sample.log'))){throw "Pulled log check failed: Destination=$($Collected.Destination); Expected=$ExpectedPull; Count=$($Collected.FileCount); Error=$($Collected.ErrorDetail)"}
    Write-Output 'PASS: current UI/runner/launcher paths, technical log output and separate PulledLogs collection.'
}
finally{if(Test-Path -LiteralPath $Temporary){Remove-Item -LiteralPath $Temporary -Recurse -Force -ErrorAction SilentlyContinue}}
