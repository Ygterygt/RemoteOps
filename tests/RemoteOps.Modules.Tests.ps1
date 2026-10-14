$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
function Register-AOModule {param($Name,$Version,$MinimumHostApiVersion,$SourcePath,$Initializer)}
function Register-AOModuleOperation {param($ModuleName,$Name,$DisplayName,$EntryPointName,$Handler)}
foreach($Module in 'RegistryOperations','ServiceTaskOperations','InventoryOperations'){. (Join-Path $Root "Modules\$Module.ps1")}
$script:Answers=New-Object 'System.Collections.Generic.Queue[string]'
function Read-Host {param([string]$Prompt)if($script:Answers.Count -eq 0){throw "No answer for: $Prompt"};return $script:Answers.Dequeue()}
function Write-Host {param([Parameter(Position=0)][object[]]$Object,[object]$ForegroundColor)}
function Start-Process {param($FilePath)}
function New-CimSession {param($ComputerName,$SessionOption,$OperationTimeoutSec)if($ComputerName -eq 'PC-DOWN'){throw 'RPC server is unavailable.'};return "SESSION:$ComputerName"}
function New-CimSessionOption {param($Protocol)return $null}
function Remove-CimSession {param($CimSession)}
$script:Return=@{};$script:RegValue='';$script:Services=@{};$script:Terminated=@()
function Invoke-CimMethod {
    param($CimSession,$Namespace,$ClassName,$InputObject,$MethodName,$Arguments)
    if($MethodName -eq 'GetStringValue'){if($script:RegValue -eq '<missing>'){return [PSCustomObject]@{ReturnValue=[uint32]2;sValue=$null}};return [PSCustomObject]@{ReturnValue=[uint32]0;sValue=$script:RegValue}}
    if($MethodName -eq 'Terminate'){$script:Terminated+=$InputObject.Name}
    $Code=if($script:Return.ContainsKey($MethodName)){$script:Return[$MethodName]}else{0}
    return [PSCustomObject]@{ReturnValue=[uint32]$Code}
}
function Get-CimInstance {
    param($CimSession,$ClassName,$Filter,$Namespace)
    switch($ClassName){
        'Win32_Service'{
            if($Filter -match "Name='([^']+)'"){$Name=$Matches[1];if($script:Services.ContainsKey($Name)){return [PSCustomObject]@{Name=$Name;State=$script:Services[$Name];StartMode='Auto';DisplayName=$Name}};return $null}
            return @($script:Services.Keys|ForEach-Object{[PSCustomObject]@{Name=$_;State=$script:Services[$_];StartMode='Auto';DisplayName=$_}})
        }
        'Win32_Process'{return @([PSCustomObject]@{Name='notepad.exe';ProcessId=11;CreationDate=(Get-Date);ExecutablePath='C:\x\notepad.exe'},[PSCustomObject]@{Name='svchost.exe';ProcessId=12;CreationDate=(Get-Date);ExecutablePath='C:\Windows\svchost.exe'},[PSCustomObject]@{Name='mysvc.exe';ProcessId=13;CreationDate=(Get-Date);ExecutablePath='C:\x\mysvc.exe'})}
        'Win32_OperatingSystem'{return [PSCustomObject]@{CSName='PC';Caption='Windows';Version='10';BuildNumber='1';OSArchitecture='64';LastBootUpTime=(Get-Date);InstallDate=(Get-Date)}}
        default{return @()}
    }
}
$Temp=Join-Path $env:TEMP ('RemoteOpsModules-'+[guid]::NewGuid().ToString('N'))
function Common {param([string[]]$Systems)@{BasePath=$Temp;Systems=$Systems;ReachableSystems=$Systems;UnreachableSystems=[string[]]@();OperationID='OP-1';OperationDate='d';OperationTime='t';TechnicalLogWriter={param($Level,$Message)};OperationHistoryWriter={param($OperationID,$OperationDate,$OperationTime,$IstemciAdi,$Modul,$Operasyon,$Sonuc,$Aciklama)}}}
function Add-Answers {param([string[]]$Values)foreach($V in $Values){$script:Answers.Enqueue($V)}}
try{
    # ---------------- registry: structured rows for read / edit / failures
    $script:RegValue='abc'
    Add-Answers '1','SOFTWARE\Test','Val','0'
    $C=Common @('PC1');$R=Invoke-RegistryOperationsMenu @C
    $Rows=@(Import-Csv -LiteralPath $R.ResultCsv -Delimiter ';')
    if($Rows.Count -ne 1 -or $Rows[0].Status -ne 'Success' -or $Rows[0].Value -ne 'abc' -or $Rows[0].OperationID -ne 'OP-1'){throw 'Registry read must return a Success row with the value.'}
    $script:RegValue='<missing>'
    Add-Answers '1','SOFTWARE\Test','Val','0'
    $R=Invoke-RegistryOperationsMenu @C
    $Rows=@(Import-Csv -LiteralPath $R.ResultCsv -Delimiter ';')
    if($Rows[0].Status -ne 'NotFound' -or (Get-RemoteOpsRowCategory $Rows[0]) -ne 'neutral'){throw 'Missing registry value must be NotFound (neutral).'}
    $script:RegValue='old';$script:Return=@{SetStringValue=5}
    Add-Answers '2','SOFTWARE\Test','Val','new','EDIT','0'
    $R=Invoke-RegistryOperationsMenu @C
    $Rows=@(Import-Csv -LiteralPath $R.ResultCsv -Delimiter ';')
    if($Rows[0].Status -ne 'Failed' -or (Get-RemoteOpsRowCategory $Rows[0]) -ne 'issue'){throw 'Registry write with non-zero ReturnValue must be Failed.'}
    $script:Return=@{}
    Add-Answers '2','SOFTWARE\Test','Val','new','EDIT','0'
    $R=Invoke-RegistryOperationsMenu @C
    $Rows=@(Import-Csv -LiteralPath $R.ResultCsv -Delimiter ';')
    if($Rows[0].Status -ne 'Success' -or $Rows[0].NewValue -ne 'new'){throw 'Registry edit success row missing.'}
    $C=Common @('PC-DOWN');Add-Answers '1','SOFTWARE\Test','Val','0'
    $R=Invoke-RegistryOperationsMenu @C
    $Rows=@(Import-Csv -LiteralPath $R.ResultCsv -Delimiter ';')
    if($Rows[0].Status -ne 'Failed' -or $Rows[0].ErrorDetail -notmatch 'unavailable'){throw 'Registry connection failure must be a Failed row.'}

    # ---------------- services
    $script:Services=@{EventLog='Running';Svc2='Stopped'}
    $C=Common @('PC1')
    Add-Answers '2','EventLog','start','START','0'
    $script:Return=@{StartService=10}
    $R=Invoke-ServiceTaskOperationsMenu @C
    $Rows=@(Import-Csv -LiteralPath (Get-ChildItem (Join-Path $Temp 'Logs\ServiceTask') -Filter 'OP-1_ServiceControl.csv').FullName -Delimiter ';')
    if($Rows[0].Status -ne 'Success'){throw 'Start on a running service (code 10) must count as success.'}
    $script:Return=@{StartService=7}
    Add-Answers '2','EventLog','start','START','0'
    [void](Invoke-ServiceTaskOperationsMenu @C)
    $Rows=@(Import-Csv -LiteralPath (Join-Path $Temp 'Logs\ServiceTask\OP-1_ServiceControl.csv') -Delimiter ';')
    if($Rows[0].Status -ne 'Failed' -or $Rows[0].ErrorDetail -notmatch 'returned 7'){throw 'A failing service method code must be reported as Failed.'}
    $script:Return=@{}
    Add-Answers '2','Svc2','restart','RESTART','0'
    [void](Invoke-ServiceTaskOperationsMenu @C)
    $Rows=@(Import-Csv -LiteralPath (Join-Path $Temp 'Logs\ServiceTask\OP-1_ServiceControl.csv') -Delimiter ';')
    if($Rows[0].Status -ne 'Success' -or $Rows[0].Action -ne 'restart'){throw 'Restart must succeed after waiting for the stopped state.'}
    Add-Answers '2','NoSuchSvc','start','START','0'
    [void](Invoke-ServiceTaskOperationsMenu @C)
    $Rows=@(Import-Csv -LiteralPath (Join-Path $Temp 'Logs\ServiceTask\OP-1_ServiceControl.csv') -Delimiter ';')
    if($Rows[0].Status -ne 'Failed'){throw 'Unknown service must be Failed.'}
    Add-Answers '3','EventLog','auto','EDIT','0'
    [void](Invoke-ServiceTaskOperationsMenu @C)
    if(-not(Test-Path (Join-Path $Temp 'Logs\ServiceTask\OP-1_ServiceStartup.csv'))){throw 'Startup change report missing.'}
    Add-Answers '1','zzz-none','0'
    [void](Invoke-ServiceTaskOperationsMenu @C)
    $Rows=@(Import-Csv -LiteralPath (Join-Path $Temp 'Logs\ServiceTask\OP-1_ServiceList.csv') -Delimiter ';')
    if($Rows.Count -ne 1 -or $Rows[0].Status -ne 'NotFound'){throw 'Empty service match must be reported as NotFound.'}

    # ---------------- processes
    Add-Answers '10','svc','KILL','0'
    [void](Invoke-ServiceTaskOperationsMenu @C)
    $Rows=@(Import-Csv -LiteralPath (Join-Path $Temp 'Logs\ServiceTask\OP-1_ProcessKill.csv') -Delimiter ';')
    if($Rows.Count -ne 0 -and $script:Terminated.Count -ne 0){throw 'Substring "svc" must not terminate svchost/mysvc.'}
    if(@($Rows|Where-Object Status -eq 'NotFound').Count -ne 1){throw 'Kill with no exact match must be reported as NotFound.'}
    Add-Answers '10','svchost','KILL','0'
    [void](Invoke-ServiceTaskOperationsMenu @C)
    $Rows=@(Import-Csv -LiteralPath (Join-Path $Temp 'Logs\ServiceTask\OP-1_ProcessKill.csv') -Delimiter ';')
    if($script:Terminated.Count -ne 0 -or $Rows[0].Status -ne 'Skipped'){throw 'Protected system process must not be terminated.'}
    Add-Answers '10','mysvc','KILL','0'
    [void](Invoke-ServiceTaskOperationsMenu @C)

    if(($script:Terminated -join ",") -ne "mysvc.exe"){throw "Exact name (without .exe) must terminate exactly that process."}
    $script:Return=@{Terminate=2}
    Add-Answers '10','notepad','KILL','0'
    [void](Invoke-ServiceTaskOperationsMenu @C)
    $Rows=@(Import-Csv -LiteralPath (Join-Path $Temp 'Logs\ServiceTask\OP-1_ProcessKill.csv') -Delimiter ';')
    if($Rows[0].Status -ne 'Failed'){throw 'Terminate with non-zero ReturnValue must be Failed.'}

    Write-Output 'PASS: registry/service/process structured results, ReturnValue checks, exact-name kill, protected processes, NotFound reporting.'
}
finally{if(Test-Path -LiteralPath $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue}}
