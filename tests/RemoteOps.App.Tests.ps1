$ErrorActionPreference = 'Stop'

$WorkspaceRoot = Split-Path -Parent $PSScriptRoot
$RunnerPath = Join-Path $WorkspaceRoot 'RemoteOps.App\RemoteOps.Runner.ps1'
$Tokens = $null
$ParseErrors = $null
$RunnerAst = [System.Management.Automation.Language.Parser]::ParseFile($RunnerPath,[ref]$Tokens,[ref]$ParseErrors)
if ($ParseErrors.Count -gt 0) { throw ($ParseErrors | Out-String) }

function Get-RunnerFunctionBody {
    param([Parameter(Mandatory=$true)][string]$Name)
    $Definition = $RunnerAst.Find({param($Node)$Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq $Name},$true)
    if ($null -eq $Definition) { throw "Runner function not found: $Name" }
    return $Definition.Body.GetScriptBlock()
}

Set-Item Function:\New-TargetScopedManifest -Value (Get-RunnerFunctionBody 'New-TargetScopedManifest')
Set-Item Function:\Invoke-ScheduledTaskActionRequest -Value (Get-RunnerFunctionBody 'Invoke-ScheduledTaskActionRequest')
Set-Item Function:\Invoke-ServiceTaskRollbackRequest -Value (Get-RunnerFunctionBody 'Invoke-ServiceTaskRollbackRequest')
Set-Item Function:\Test-RemoteOpsAccess -Value (Get-RunnerFunctionBody 'Test-RemoteOpsAccess')
Set-Item Function:\New-FileBrowserPromptAnswers -Value (Get-RunnerFunctionBody 'New-FileBrowserPromptAnswers')
Set-Item Function:\Test-ConsoleMenuText -Value (Get-RunnerFunctionBody 'Test-ConsoleMenuText')
foreach($Text in @('','====',' SERVICE AND TASK OPERATIONS','4 - Scheduled task listele','10 - Process kill',' REGISTRY OPERATIONS',' DOSYA OPERASYONLARI')){
    if(-not(Test-ConsoleMenuText $Text)){throw "Console menu text leaked: $Text"}
}
foreach($Text in @('TEST-PC : TASK OK','TEST-PC : HATA | Access denied','CSV rapor : C:\Reports\tasks.csv')){
    if(Test-ConsoleMenuText $Text){throw "Useful output was suppressed: $Text"}
}

$script:TestTasks = @{}
$script:EnableCalls = 0
$script:DisableCalls = 0
$script:RunCalls = 0
$script:DeleteCalls = 0
$script:RegisterCalls = 0
$script:FailManifestWrite=$false
$script:TaskXml = '<Task xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"><Principals><Principal><LogonType>ServiceAccount</LogonType></Principal></Principals><Settings><Enabled>true</Enabled></Settings></Task>'
function Export-ScheduledTask { param($CimSession,$TaskName,$TaskPath,$ErrorAction) return $script:TaskXml }
function Unregister-ScheduledTask {
    param($CimSession,$TaskName,$TaskPath,$Confirm,$ErrorAction)
    $Saved=@(Import-Csv -LiteralPath (Join-Path $script:BasePath "ServiceTaskRollbacks\${OperationID}_ScheduledTasks.csv") -Delimiter ';')
    if($Saved.Count -eq 0 -or -not(Test-Path -LiteralPath $Saved[-1].BackupXml)){throw 'Delete called before durable backup and manifest.'}
    $script:DeleteCalls++;$script:TestTasks[[string]$CimSession]=@()
}
function Register-ScheduledTask {
    param($CimSession,$TaskName,$TaskPath,$Xml,$ErrorAction)
    if($TaskName -ne 'Nightly' -or $TaskPath -ne '\Ops\' -or $Xml.Trim() -ne $script:TaskXml){throw 'Rollback task definition or identity differs from backup.'}
    $script:RegisterCalls++
}

function Get-ServiceTaskSession { param([string]$ComputerName) return $ComputerName }
function Get-CimInstance {
    param($CimSession,$Namespace,$ClassName,$ErrorAction)
    $Task = $script:TestTasks[[string]$CimSession]
    if ($null -eq $Task) { throw "Mock task missing for $CimSession" }
    return $Task
}
function Enable-ScheduledTask { param($CimSession,$TaskName,$TaskPath,$ErrorAction) $script:EnableCalls++ }
function Disable-ScheduledTask { param($CimSession,$TaskName,$TaskPath,$ErrorAction) $script:DisableCalls++ }
function Start-ScheduledTask { param($CimSession,$TaskName,$TaskPath,$ErrorAction) $script:RunCalls++ }
function Remove-CimSession { param($CimSession,$ErrorAction) }
function Write-RemoteOpsLog { param($Level,$Message) }
function Write-ServiceTaskManifest {
    param([string]$Path,[object[]]$Rows)
    if($script:FailManifestWrite){throw 'Simulated manifest write failure'}
    $Parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $Parent)) { New-Item -ItemType Directory -Path $Parent -Force | Out-Null }
    @($Rows) | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8 -Delimiter ';'
}

$TestRoot = Join-Path $env:TEMP ('RemoteOps-App-Test-' + [guid]::NewGuid().ToString('N'))
try {
    $LogRoot = Join-Path $TestRoot 'logs'
    $DataRoot = Join-Path $TestRoot 'data'
    New-Item -ItemType Directory -Path $LogRoot,$DataRoot -Force | Out-Null

    $script:Systems = @('TEST-PC')
    $script:ReachableSystems = @('TEST-PC')
    $script:OperationID = 'TASK-DISABLE-TEST'
    $script:BasePath = $DataRoot
    $script:TestTasks['TEST-PC'] = [PSCustomObject]@{TaskName='Nightly';TaskPath='\Ops\';Settings=[PSCustomObject]@{Enabled=$true}}

    [void](Invoke-ScheduledTaskActionRequest -InputValues @{TaskName='Nightly';Action='Disable'})
    $DisableManifest = Join-Path $DataRoot 'ServiceTaskRollbacks\TASK-DISABLE-TEST_ScheduledTasks.csv'
    $DisableRows = @(Import-Csv -LiteralPath $DisableManifest -Delimiter ';')
    if ($DisableRows.Count -ne 1 -or $DisableRows[0].OldEnabled -ne 'True' -or $DisableRows[0].Action -ne 'EnableDisable') { throw 'Disable did not create a rollback row with the previous task state.' }
    if ($script:DisableCalls -ne 1) { throw 'Disable action was not invoked exactly once.' }

    $script:OperationID = 'TASK-RUN-TEST'
    [void](Invoke-ScheduledTaskActionRequest -InputValues @{TaskName='Nightly';Action='Run'})
    $RunManifest = Join-Path $DataRoot 'ServiceTaskRollbacks\TASK-RUN-TEST_ScheduledTasks.csv'
    if (Test-Path -LiteralPath $RunManifest) { throw 'Run action must not create an enable/disable rollback manifest.' }
    if ($script:RunCalls -ne 1) { throw 'Run action was not invoked exactly once.' }

    $script:OperationID = 'TASK-ROLLBACK-TEST'
    $RollbackResult = Invoke-ServiceTaskRollbackRequest -InputValues @{ManifestPath=$DisableManifest}
    if ($script:EnableCalls -ne 1) { throw 'Rollback did not restore the previously enabled task.' }
    if (-not (Test-Path -LiteralPath $RollbackResult -PathType Leaf)) { throw 'Task rollback report was not written.' }

    $script:OperationID='TASK-DELETE-TEST'
    $Deleted=Invoke-ScheduledTaskActionRequest -InputValues @{TaskName='Nightly';TaskPath='\Ops\';Action='Delete'}
    if($script:DeleteCalls -ne 1 -or $Deleted.Rows[0].Status -ne 'Success'){throw 'Delete did not complete with a durable backup.'}
    $DeleteManifest=Join-Path $DataRoot 'ServiceTaskRollbacks\TASK-DELETE-TEST_ScheduledTasks.csv'
    $script:OperationID='TASK-DELETE-ROLLBACK'
    [void](Invoke-ServiceTaskRollbackRequest -InputValues @{ManifestPath=$DeleteManifest})
    if($script:RegisterCalls -ne 1){throw 'Deleted task was not restored from XML.'}
    $script:TestTasks['TEST-PC']=[PSCustomObject]@{TaskName='Nightly';TaskPath='\Ops\';Settings=[PSCustomObject]@{Enabled=$true}}
    $ConflictReport=Invoke-ServiceTaskRollbackRequest -InputValues @{ManifestPath=$DeleteManifest}
    if($script:RegisterCalls -ne 1 -or (Import-Csv $ConflictReport -Delimiter ';').Status -ne 'Failed'){throw 'Rollback overwrote an existing task.'}
    $script:OperationID='TASK-PASSWORD-REFUSED'
    $script:TaskXml=$script:TaskXml.Replace('ServiceAccount','Password')
    $Refused=Invoke-ScheduledTaskActionRequest -InputValues @{TaskName='Nightly';Action='Delete'}
    if($script:DeleteCalls -ne 1 -or $Refused.Rows[0].Status -ne 'Failed'){throw 'Password task was deleted without restorable credentials.'}
    $script:TaskXml='<invalid'
    $Refused=Invoke-ScheduledTaskActionRequest -InputValues @{TaskName='Nightly';Action='Delete'}
    if($script:DeleteCalls -ne 1 -or $Refused.Rows[0].Status -ne 'Failed'){throw 'Invalid export did not prevent deletion.'}
    $script:TaskXml='<Task xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"><Principals><Principal><LogonType>ServiceAccount</LogonType></Principal></Principals></Task>'
    $script:FailManifestWrite=$true
    $script:OperationID='TASK-MANIFEST-FAIL'
    $Refused=Invoke-ScheduledTaskActionRequest -InputValues @{TaskName='Nightly';Action='Delete'}
    $script:FailManifestWrite=$false
    if($script:DeleteCalls -ne 1 -or $Refused.Rows[0].Status -ne 'Failed'){throw 'Manifest write failure did not prevent deletion.'}

    $ServiceTaskRoot=Join-Path $DataRoot 'ServiceTaskRollbacks'
    $ProcessManifest=Join-Path $ServiceTaskRoot '999_ProcessKill.csv'
    [PSCustomObject]@{ComputerName='TEST-PC';ObjectType='Process';ObjectName='app.exe';Action='Kill'}|Export-Csv -LiteralPath $ProcessManifest -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    $script:OperationID='LATEST-ROLLBACK-TEST'
    $script:Systems=@('TEST-PC')
    $LatestScoped=New-TargetScopedManifest -ManifestPath '' -ManifestRoot $ServiceTaskRoot -Label 'Service/task' -AllowedObjectTypes @('Service','ScheduledTask')
    $LatestRows=@(Import-Csv -LiteralPath $LatestScoped.Path -Delimiter ';')
    if($LatestRows.Count -ne 1 -or $LatestRows[0].ObjectType -ne 'ScheduledTask'){throw 'Latest service/task rollback selected a process manifest or skipped the task manifest.'}
    Remove-Item -LiteralPath $LatestScoped.Path -Force

    function ConvertTo-AORemoteAdminPath { param($ComputerName,$LocalPath) return ('{0}|{1}' -f $ComputerName,$LocalPath) }
    function Get-ChildItem {
        param($LiteralPath,[switch]$File,[switch]$Recurse,[switch]$Force,$ErrorAction)
        if($LiteralPath -like 'PC-A|*'){return @([PSCustomObject]@{FullName='PC-A|C:\Browse\a.txt'},[PSCustomObject]@{FullName='PC-A|C:\Browse\b.txt'})}
        if($LiteralPath -like 'PC-B|*'){return @([PSCustomObject]@{FullName='PC-B|C:\Browse\b.txt'})}
        return Microsoft.PowerShell.Management\Get-ChildItem @PSBoundParameters
    }
    $BrowserAnswers=New-FileBrowserPromptAnswers -BrowsePath 'C:\Browse' -SelectedPath 'C:\Browse\b.txt' -Action 'Move' -ComputerNames @('PC-A','PC-B') -MoveTarget 'C:\Archive' -ReplaceSource '' -Confirm 'MOVE'
    $ExpectedAnswers=@('C:\Browse','2','2','C:\Archive','MOVE','1','2','C:\Archive','MOVE','0')
    if(($BrowserAnswers -join '|') -cne ($ExpectedAnswers -join '|')){throw "FileBrowser answer queue mismatch: $($BrowserAnswers -join ', ')"}

    $AccessCheck = [PSCustomObject]@{
        RunnerPath=$RunnerPath
        WorkersPath=(Join-Path $WorkspaceRoot 'Modules\ApplicationWorkers.ps1')
        ModulesRoot=(Join-Path $WorkspaceRoot 'Modules')
        BasePath=$DataRoot
        LogRoot=$LogRoot
        Operation='ApplicationCheck'
        Values=@{}
        PsExecPath=''
        PluginScript=''
    }
    if (-not (Test-RemoteOpsAccess -Preflight $AccessCheck)) { throw 'Filesystem preflight did not return success.' }

    Write-Output 'PASS: task enable/disable and delete rollback, durable backup before delete, password/invalid XML/manifest failure guards, collision protection, menu filter, FileBrowser queue and filesystem preflight.'
}
finally {
    if (Test-Path -LiteralPath $TestRoot) { Remove-Item -LiteralPath $TestRoot -Recurse -Force -ErrorAction SilentlyContinue }
}