$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
# Starts the real runner as a hidden process (like the GUI) against non-existent computers only. Nothing is changed anywhere:
# wrong confirmation words and empty target lists are refused before any work, and unreachable names end as Error rows.
$Base='C:\Temp\YD_RemoteOps.App'
$Created=New-Object System.Collections.Generic.List[string]
function Invoke-Runner {
    param([string]$Operation,[string[]]$Targets,[hashtable]$Values=@{})
    $Progress=Join-Path $Base ('Logs\Operations\'+$Operation+'\'+[guid]::NewGuid().ToString('N')+'.progress.json')
    $Request=[ordered]@{Operation=$Operation;Category='Test';Domain=$env:USERDOMAIN;UserName=$env:USERNAME;IsMain=$true;Targets=$Targets;Values=$Values;ProgressPath=$Progress;PluginName=$null;PluginScript=$null;PluginRoot=$null;PluginParallelSafe=$false;Parallelism=3;CleanupPackageLogs=$false;CleanupUserName='';RequestedAt=(Get-Date).ToString('o')}
    $Encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Request -Depth 8 -Compress)))
    $OperationRoot=Join-Path $Base ('Logs\Operations\'+$Operation)
    $Known=@();if(Test-Path -LiteralPath $OperationRoot){$Known=@(Get-ChildItem -LiteralPath $OperationRoot -Directory|ForEach-Object{$_.Name})}
    $OutFile=[IO.Path]::GetTempFileName();$ErrFile=[IO.Path]::GetTempFileName()
    try{
        $Arguments='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -RequestBase64 {1}' -f (Join-Path $Root 'RemoteOps.App\RemoteOps.Runner.ps1'),$Encoded
        $Process=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $Arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $OutFile -RedirectStandardError $ErrFile
        [void]$Process.Handle
        if(-not $Process.WaitForExit(120000)){Stop-Process -Id $Process.Id -Force;throw "Runner timed out for $Operation."}
        $New=@();if(Test-Path -LiteralPath $OperationRoot){$New=@(Get-ChildItem -LiteralPath $OperationRoot -Directory|Where-Object{$Known -notcontains $_.Name})}
        foreach($Folder in $New){[void]$Created.Add($Folder.FullName)}
        $Rows=@();$Csv=@($New|ForEach-Object{Join-Path $_.FullName 'Results.csv'}|Where-Object{Test-Path -LiteralPath $_})
        if($Csv.Count -gt 0){$Rows=@(Import-Csv -LiteralPath $Csv[0] -Delimiter ';')}
        return [PSCustomObject]@{ExitCode=$Process.ExitCode;Rows=$Rows;Runs=$New.Count;Output=(Get-Content -LiteralPath $OutFile -Raw)}
    }
    finally{Remove-Item -LiteralPath $OutFile,$ErrFile -Force -ErrorAction SilentlyContinue}
}
try{
    # empty target list
    $R=Invoke-Runner -Operation 'ProcessQuery' -Targets @() -Values @{ProcessFilter='x'}
    if($R.ExitCode -ne 1 -or $R.Output -notmatch 'no target computers'){throw 'Empty target list must be refused (exit 1).'}
    # every confirmation-gated operation refuses a wrong word (before any connection is attempted)
    foreach($Case in @(@('FileDelete',@{Path='C:\x'}),@('RegistryEdit',@{RegistryPath='SOFTWARE\x';ValueName='v';Value='1'}),@('RegistryDelete',@{RegistryPath='SOFTWARE\x';ValueName='v'}),@('ServiceControl',@{ServiceName='x';Action='Stop'}),@('ServiceStartup',@{ServiceName='x';StartupType='Manual'}),@('ScheduledTaskDelete',@{TaskName='x'}),@('ScheduledTaskAction',@{TaskName='x';Action='Run'}),@('ProcessKill',@{ProcessFilter='zz_none'}),@('PackageTrigger',@{}),@('FileRestore',@{}),@('FileRollback',@{}),@('RegistryRollback',@{}),@('ServiceTaskRollback',@{}))){
        $Values=@{}+$Case[1];$Values.Confirm='wrong'
        $R=Invoke-Runner -Operation $Case[0] -Targets @('NOPE-PC-1') -Values $Values
        if($R.ExitCode -ne 1 -or $R.Output -notmatch 'Confirmation mismatch'){throw "$($Case[0]) must refuse a wrong confirmation word (exit $($R.ExitCode))."}
    }
    # duplicate targets differing only in case/whitespace are processed once; unreachable names are Error rows, exit code stays 0
    $R=Invoke-Runner -Operation 'ProcessQuery' -Targets @('NOPE-PC-1','nope-pc-1',' NOPE-PC-1 ','NOPE-PC-2') -Values @{ProcessFilter='x'}
    if($R.ExitCode -ne 0 -or $R.Runs -ne 1){throw "Unreachable targets must give exit 0 and exactly one run folder (exit $($R.ExitCode), runs $($R.Runs))."}
    if($R.Rows.Count -ne 2){throw "Case-insensitive duplicate targets must be processed once (got $($R.Rows.Count) rows)."}
    foreach($Row in $R.Rows){if($Row.Status -ne 'Unreachable'){throw 'Unreachable computer must be reported separately from failures.'}}
    # an operation name the runner does not know is an Error row, not success
    $R=Invoke-Runner -Operation 'NoSuchOperation' -Targets @('NOPE-PC-1')
    if($R.ExitCode -ne 1 -or $R.Output -notmatch 'not connected to a runner'){throw 'Unknown operation must be rejected before access checks.'}
    Write-Output 'PASS: real runner process: empty targets and wrong confirmation words refused (13 operations), case-insensitive target de-duplication, unreachable names as neutral rows, unknown operation rejected before access.'
}
finally{
    foreach($Folder in $Created){Remove-Item -LiteralPath $Folder -Recurse -Force -ErrorAction SilentlyContinue}
}
