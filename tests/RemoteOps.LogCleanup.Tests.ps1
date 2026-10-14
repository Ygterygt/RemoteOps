$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'Modules\FileOperations.ps1')
$Temp=Join-Path $env:TEMP ('RemoteOpsLogCleanup-'+[guid]::NewGuid().ToString('N'))
$RemoteTemp=Join-Path $Temp 'remote\C$\Windows\Temp'
$Collected=Join-Path $Temp 'collected'
# the administrative share is simulated by a local folder
function ConvertTo-AORemoteAdminPath { param($ComputerName,$LocalPath) if($LocalPath -ne 'C:\Windows\Temp'){throw "Unexpected path $LocalPath"};return $script:SimulatedRemoteTemp }
$script:SimulatedRemoteTemp=$RemoteTemp
function New-RemoteLog { param([string]$Name,[string]$Content='log data',[switch]$NoCopy,[string]$Sub='')
    $Dir=if($Sub){Join-Path $RemoteTemp $Sub}else{$RemoteTemp}
    New-Item -ItemType Directory -Path $Dir -Force|Out-Null
    $Path=Join-Path $Dir $Name;Set-Content -LiteralPath $Path -Value $Content -Encoding ASCII
    if(-not $NoCopy){$Target=if($Sub){Join-Path (Join-Path $Collected $Sub) $Name}else{Join-Path $Collected $Name};New-Item -ItemType Directory -Path (Split-Path -Parent $Target) -Force|Out-Null;Copy-Item -LiteralPath $Path -Destination $Target -Force}
    return $Path
}
function Reset-Fixture { Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue;New-Item -ItemType Directory -Path $RemoteTemp,$Collected -Force|Out-Null }
try{
    # ---------------- user name validation
    foreach($Bad in @('','  ','a','abc','admin','Administrator','SYSTEM','user','test','temp','windows','*','yigit*','yi?git','a b c d','..\x','C:\x','12345678','yi..git','sccm','ccm','setup')){
        if((Test-AOLogCleanupUserName -UserName $Bad).Valid){throw "User name '$Bad' must be refused."}
    }
    foreach($Good in @('yigitery0','e123456','john.doe','svc_deploy-01','Yigit.Ery0')){
        if(-not (Test-AOLogCleanupUserName -UserName $Good).Valid){throw "User name '$Good' must be accepted."}
    }

    # ---------------- only the right files are deleted
    Reset-Fixture
    $Matching1=New-RemoteLog 'Setup_yigitery0.log'
    $Matching2=New-RemoteLog 'YIGITERY0_install.TXT'          # case-insensitive match
    $Matching3=New-RemoteLog 'app-yigitery0-20261006.log'
    $Unrelated=New-RemoteLog 'other.log'                       # collected but no user name
    $WrongExt=New-RemoteLog 'yigitery0.exe'                    # wrong extension
    $Protected=New-RemoteLog 'CBS_yigitery0.log'               # protected system log name
    $Sccm=New-RemoteLog 'SCCM_yigitery0.log'                   # package logs starting with SCCM are NOT protected
    $Changed=New-RemoteLog 'changed_yigitery0.log'
    Add-Content -LiteralPath $Changed -Value 'written after collection'
    $SameSizeDiff=New-RemoteLog 'diff_yigitery0.log' -Content 'AAAA'
    Set-Content -LiteralPath $SameSizeDiff -Value 'BBBB' -Encoding ASCII  # same length, different content
    $NotCollected=New-RemoteLog 'notcollected_yigitery0.log' -NoCopy      # on the target but never collected
    $InSub=New-RemoteLog 'sub_yigitery0.log' -Sub 'subfolder'             # collected from a subfolder
    $Locked=New-RemoteLog 'locked_yigitery0.log'
    $Handle=[System.IO.File]::Open($Locked,[System.IO.FileMode]::Open,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
    try{
        $Result=Remove-AOCollectedUserLogs -ComputerName 'PC1' -UserName 'yigitery0' -CollectedRoot $Collected
    }
    finally{$Handle.Dispose()}
    foreach($Gone in @($Matching1,$Matching2,$Matching3,$Sccm)){if(Test-Path -LiteralPath $Gone){throw "Should have been deleted: $Gone"}}
    foreach($Kept in @($Unrelated,$WrongExt,$Protected,$Changed,$SameSizeDiff,$NotCollected,$InSub,$Locked)){if(-not(Test-Path -LiteralPath $Kept)){throw "Must NOT be deleted: $Kept"}}
    if($Result.DeletedCount -ne 4 -or $Result.Status -ne 'Partial'){throw "Unexpected result: $($Result|Out-String)"}
    if($Result.Detail -notmatch 'Silindi: ' -or $Result.Detail -notmatch 'Silinmedi: '){throw "Detail text incomplete: $($Result.Detail)"}
    # the collected copies are never touched
    if(@(Get-ChildItem -LiteralPath $Collected -File).Count -ne 10){throw 'Collected copies must remain untouched.'}

    # ---------------- nothing matching
    Reset-Fixture;[void](New-RemoteLog 'other.log')
    $Result=Remove-AOCollectedUserLogs -ComputerName 'PC1' -UserName 'yigitery0' -CollectedRoot $Collected
    if($Result.Status -ne 'NothingToClean' -or $Result.DeletedCount -ne 0){throw 'No match must report NothingToClean.'}

    # ---------------- generic user name never deletes anything
    Reset-Fixture;$Victim=New-RemoteLog 'admin_setup.log'
    $Result=Remove-AOCollectedUserLogs -ComputerName 'PC1' -UserName 'admin' -CollectedRoot $Collected
    if($Result.Status -ne 'Skipped' -or -not(Test-Path -LiteralPath $Victim)){throw 'Generic user name must be refused without deleting.'}
    $Result=Remove-AOCollectedUserLogs -ComputerName 'PC1' -UserName '*' -CollectedRoot $Collected
    if($Result.Status -ne 'Skipped' -or -not(Test-Path -LiteralPath $Victim)){throw 'Wildcard user name must be refused.'}

    # ---------------- too many matches: safety cap
    Reset-Fixture;$Many=@(1..51|ForEach-Object{New-RemoteLog ('yigitery0_{0:D2}.log' -f $_)})
    $Result=Remove-AOCollectedUserLogs -ComputerName 'PC1' -UserName 'yigitery0' -CollectedRoot $Collected
    if($Result.Status -ne 'Skipped' -or @($Many|Where-Object{Test-Path -LiteralPath $_}).Count -ne 51){throw 'More than 50 matches must delete nothing.'}
    Reset-Fixture;$Fifty=@(1..50|ForEach-Object{New-RemoteLog ('yigitery0_{0:D2}.log' -f $_)})
    $Result=Remove-AOCollectedUserLogs -ComputerName 'PC1' -UserName 'yigitery0' -CollectedRoot $Collected
    if($Result.Status -ne 'Success' -or $Result.DeletedCount -ne 50){throw 'Exactly 50 matches must be deleted.'}

    # ---------------- missing collection folder / unreachable temp
    Reset-Fixture
    $Result=Remove-AOCollectedUserLogs -ComputerName 'PC1' -UserName 'yigitery0' -CollectedRoot (Join-Path $Temp 'nope')
    if($Result.Status -ne 'Skipped'){throw 'Missing collected folder must skip.'}
    [void](New-RemoteLog 'a_yigitery0.log');$script:SimulatedRemoteTemp=Join-Path $Temp 'unreachable'
    $Result=Remove-AOCollectedUserLogs -ComputerName 'PC1' -UserName 'yigitery0' -CollectedRoot $Collected
    if($Result.Status -ne 'Failed' -or -not(Test-Path -LiteralPath (Join-Path $RemoteTemp 'a_yigitery0.log'))){throw 'Unreachable Temp must fail without deleting.'}
    $script:SimulatedRemoteTemp=$RemoteTemp

    # ---------------- a folder named like a log is never removed
    Reset-Fixture;[void](New-RemoteLog 'dir_yigitery0.log')
    Remove-Item -LiteralPath (Join-Path $RemoteTemp 'dir_yigitery0.log') -Force;New-Item -ItemType Directory -Path (Join-Path $RemoteTemp 'dir_yigitery0.log')|Out-Null
    $Result=Remove-AOCollectedUserLogs -ComputerName 'PC1' -UserName 'yigitery0' -CollectedRoot $Collected
    if(-not(Test-Path -LiteralPath (Join-Path $RemoteTemp 'dir_yigitery0.log') -PathType Container) -or $Result.DeletedCount -ne 0){throw 'A directory must never be deleted.'}

    # ---------------- user name must be a separate word: 'yigitery0' must never touch logs of 'yigitery01' or 'xyigitery0'
    Reset-Fixture
    $Other1=New-RemoteLog 'setup_yigitery01.log'                 # another user whose name starts with the same text
    $Other2=New-RemoteLog 'xyigitery0.log'                        # name ends with it but is a longer word
    $Other3=New-RemoteLog 'yigitery0123_install.txt'
    $Own1=New-RemoteLog 'yigitery0.log'                           # whole name
    $Own2=New-RemoteLog 'Install-yigitery0.TXT'                   # delimiter before, extension after, other case
    $Own3=New-RemoteLog 'YIGITERY0_20261006.log'                  # delimiter after
    $Own4=New-RemoteLog ('yi'+[char]0x011F+'it_yigitery0.log')      # Turkish character elsewhere in the name
    $Own5=New-RemoteLog (('a'*110)+'_yigitery0.log')               # long name (kept below MAX_PATH)
    $Result=Remove-AOCollectedUserLogs -ComputerName 'PC1' -UserName 'yigitery0' -CollectedRoot $Collected
    foreach($Kept in @($Other1,$Other2,$Other3)){if(-not(Test-Path -LiteralPath $Kept)){throw "Log of another user must NOT be deleted: $Kept"}}
    foreach($Gone in @($Own1,$Own2,$Own3,$Own4,$Own5)){if(Test-Path -LiteralPath $Gone){throw "Own log should have been deleted: $Gone"}}
    if($Result.DeletedCount -ne 5 -or $Result.Status -ne 'Success'){throw "Unexpected word-boundary result: $($Result|Out-String)"}
    # the longer user name matches its own logs and not the shorter name's
    Reset-Fixture
    $ShortLog=New-RemoteLog 'run_yigitery0.log';$LongLog=New-RemoteLog 'run_yigitery01.log'
    $Result=Remove-AOCollectedUserLogs -ComputerName 'PC1' -UserName 'yigitery01' -CollectedRoot $Collected
    if(-not(Test-Path -LiteralPath $ShortLog) -or (Test-Path -LiteralPath $LongLog) -or $Result.DeletedCount -ne 1){throw 'Longer user name must only delete its own log.'}
    # user names with regex characters are matched literally ('.' is not a wildcard)
    Reset-Fixture
    $Dot=New-RemoteLog 'x_john.doe.log';$NoDot=New-RemoteLog 'x_johnXdoe.log'
    $Result=Remove-AOCollectedUserLogs -ComputerName 'PC1' -UserName 'john.doe' -CollectedRoot $Collected
    if((Test-Path -LiteralPath $Dot) -or -not(Test-Path -LiteralPath $NoDot)){throw 'Dots in the user name must match literally.'}
    # two targets with the same user name: each target only deletes its own collected files from its own temp folder
    Reset-Fixture
    $RemoteA=Join-Path $Temp 'remoteA\C$\Windows\Temp';$RemoteB=Join-Path $Temp 'remoteB\C$\Windows\Temp'
    $CollectedA=Join-Path $Temp 'collectedA';$CollectedB=Join-Path $Temp 'collectedB'
    New-Item -ItemType Directory -Path $RemoteA,$RemoteB,$CollectedA,$CollectedB -Force|Out-Null
    foreach($Pair in @(@($RemoteA,$CollectedA,'same_yigitery0.log'),@($RemoteB,$CollectedB,'same_yigitery0.log'),@($RemoteA,$CollectedA,'onlyA_yigitery0.log'))){
        Set-Content -LiteralPath (Join-Path $Pair[0] $Pair[2]) -Value ('data '+$Pair[0]) -Encoding ASCII;Copy-Item -LiteralPath (Join-Path $Pair[0] $Pair[2]) -Destination $Pair[1]
    }
    # PC-B's copy changed after collection: must survive while PC-A's identical file is deleted
    Add-Content -LiteralPath (Join-Path $RemoteB 'same_yigitery0.log') -Value 'changed'
    function ConvertTo-AORemoteAdminPath { param($ComputerName,$LocalPath) if($ComputerName -eq 'PC-A'){return $RemoteA};if($ComputerName -eq 'PC-B'){return $RemoteB};return $script:SimulatedRemoteTemp }
    $ResultA=Remove-AOCollectedUserLogs -ComputerName 'PC-A' -UserName 'yigitery0' -CollectedRoot $CollectedA
    $ResultB=Remove-AOCollectedUserLogs -ComputerName 'PC-B' -UserName 'yigitery0' -CollectedRoot $CollectedB
    if($ResultA.DeletedCount -ne 2 -or $ResultB.DeletedCount -ne 0 -or -not(Test-Path -LiteralPath (Join-Path $RemoteB 'same_yigitery0.log'))){throw "Per-target isolation failed: A=$($ResultA.DeletedCount) B=$($ResultB.DeletedCount)."}
    function ConvertTo-AORemoteAdminPath { param($ComputerName,$LocalPath) if($LocalPath -ne 'C:\Windows\Temp'){throw "Unexpected path $LocalPath"};return $script:SimulatedRemoteTemp }

    # ---------------- real package worker: cleanup is gated by log collection and normal completion
    $Tokens=$null;$ParseErrors=$null
    $Ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'Modules\ApplicationWorkers.ps1'),[ref]$Tokens,[ref]$ParseErrors)
    $Assignment=$Ast.Find({param($Node)$Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $Node.Left.Extent.Text -eq '$PackageScript'},$true)
    $Worker=$Assignment.Right.Find({param($Node)$Node -is [System.Management.Automation.Language.ScriptBlockExpressionAst]},$true).ScriptBlock.GetScriptBlock()
    $FakePsExec=Join-Path $Temp 'fakepsexec.cmd'
    Set-Content -LiteralPath $FakePsExec -Value "@echo off`r`nexit /b 0" -Encoding ASCII
    function Invoke-Worker { param([string]$Psexec,[bool]$Collect,[string]$User)
        $Out=& $Worker 'PC1' '\\server\share\pkg' 'install.bat' $Psexec 10 60 $Collect (Join-Path $Root 'Modules\FileOperations.ps1') $Temp 'INSTALL' 'CLEAN-1' 10 '{}' 'DisplayName' 'X' 6 '' 0 0 0 $true $false $null $User
        return @($Out|Where-Object{$null -ne $_ -and $null -ne $_.PSObject.Properties['ExecutionStatus']})|Select-Object -Last 1
    }
    $R=Invoke-Worker -Psexec $FakePsExec -Collect $false -User ''
    if($R.LogCleanupStatus -ne 'NotRequested'){throw "Cleanup must be NotRequested by default, got $($R.LogCleanupStatus)."}
    $R=Invoke-Worker -Psexec $FakePsExec -Collect $false -User 'yigitery0'
    if($R.LogCleanupStatus -ne 'Skipped' -or $R.ExecutionStatus -ne 'Success'){throw "Without log collection nothing may be cleaned: $($R.LogCleanupStatus)."}
    $R=Invoke-Worker -Psexec (Join-Path $Temp 'missing-psexec.exe') -Collect $true -User 'yigitery0'
    if($R.LogCleanupStatus -ne 'NotRun' -or $R.ExecutionStatus -ne 'Hata'){throw "A failed trigger must not clean anything: $($R.LogCleanupStatus)/$($R.ExecutionStatus)."}
    # ---------------- real package worker end to end (collection -> cleanup) against a simulated administrative share.
    # The worker dot-sources the module itself, so a copy of the module with a local ConvertTo-AORemoteAdminPath is used.
    Reset-Fixture
    Set-Content -LiteralPath $FakePsExec -Value "@echo off`r`nexit /b 0" -Encoding ASCII
    $SimRemote=Join-Path $Temp 'simremote';New-Item -ItemType Directory -Path $SimRemote -Force|Out-Null
    $SimModule=Join-Path $Temp 'FileOperationsSim.ps1'
    Copy-Item -LiteralPath (Join-Path $Root 'Modules\FileOperations.ps1') -Destination $SimModule
    Add-Content -LiteralPath $SimModule -Value ("`r`nfunction ConvertTo-AORemoteAdminPath { param(`$ComputerName,`$LocalPath) return '$SimRemote' }")
    function New-SimLogs { foreach($N in 'pkg_yigitery0.log','pkg_yigitery01.log','other.log','CBS_yigitery0.log'){Set-Content -LiteralPath (Join-Path $SimRemote $N) -Value 'recent log' -Encoding ASCII} }
    # the worker runs in a fresh process (like the real package runspace) so nothing from this test's scope leaks into it
    $ChildScript=Join-Path $Temp 'sim-worker.ps1'
    Set-Content -LiteralPath $ChildScript -Encoding ASCII -Value @'
param($Psexec,$TimeoutSec,$Id,$SimModule,$Temp,$Root)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$Ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'Modules\ApplicationWorkers.ps1'),[ref]$null,[ref]$null)
$Assignment=$Ast.Find({param($Node)$Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $Node.Left.Extent.Text -eq '$PackageScript'},$true)
$Worker=$Assignment.Right.Find({param($Node)$Node -is [System.Management.Automation.Language.ScriptBlockExpressionAst]},$true).ScriptBlock.GetScriptBlock()
$Out=& $Worker 'PC1' '\\server\share\pkg' 'install.bat' $Psexec 10 ([int]$TimeoutSec) $true $SimModule $Temp 'INSTALL' $Id 10 '{}' 'DisplayName' 'X' 6 '' 0 0 0 $true $false $null 'yigitery0'
$R=@($Out|Where-Object{$null -ne $_ -and $null -ne $_.PSObject.Properties['ExecutionStatus']})|Select-Object -Last 1
$R|Select-Object ExecutionStatus,ExitCode,LogCollectionStatus,LogCleanupStatus,LogCleanupCount,LogCleanupDetail|ConvertTo-Json -Compress
'@
    function Invoke-SimWorker { param([string]$Psexec,[int]$TimeoutSec,[string]$Id)
        $Json=& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $ChildScript -Psexec $Psexec -TimeoutSec $TimeoutSec -Id $Id -SimModule $SimModule -Temp $Temp -Root $Root
        return ($Json|Where-Object{$_ -like '{*'}|Select-Object -Last 1|ConvertFrom-Json)
    }
    New-SimLogs
    $R=Invoke-SimWorker -Psexec $FakePsExec -TimeoutSec 60 -Id 'E2E-1'
    if($R.ExecutionStatus -ne 'Success' -or $R.LogCollectionStatus -ne 'Success' -or $R.LogCleanupStatus -ne 'Success' -or [int]$R.LogCleanupCount -ne 1){throw "End-to-end cleanup failed: exec=$($R.ExecutionStatus) collect=$($R.LogCollectionStatus) cleanup=$($R.LogCleanupStatus)/$($R.LogCleanupCount) $($R.LogCleanupDetail)"}
    if(Test-Path -LiteralPath (Join-Path $SimRemote 'pkg_yigitery0.log')){throw 'Own log must be deleted by the worker.'}
    foreach($Kept in 'pkg_yigitery01.log','other.log','CBS_yigitery0.log'){if(-not(Test-Path -LiteralPath (Join-Path $SimRemote $Kept))){throw "Worker must not delete $Kept."}}
    # the cleanup result never changes the package result: a failing cleanup (module cannot delete) still reports Success for the package
    New-SimLogs
    $LockedPath=Join-Path $SimRemote 'pkg_yigitery0.log'
    $Lock=[System.IO.File]::Open($LockedPath,[System.IO.FileMode]::Open,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
    try{$R=Invoke-SimWorker -Psexec $FakePsExec -TimeoutSec 60 -Id 'E2E-2'}finally{$Lock.Dispose()}
    if($R.ExecutionStatus -ne 'Success' -or $R.LogCleanupStatus -eq 'Success'){throw "A failed cleanup must not change the package result: exec=$($R.ExecutionStatus) cleanup=$($R.LogCleanupStatus)."}
    if(-not(Test-Path -LiteralPath $LockedPath)){throw 'Locked log must survive.'}
    # timeout: nothing is cleaned and the package is reported as not completed
    New-SimLogs
    $SlowPsExec=Join-Path $Temp 'slowpsexec.cmd'
    Set-Content -LiteralPath $SlowPsExec -Value "@echo off`r`nping -n 8 127.0.0.1 >nul`r`nexit /b 0" -Encoding ASCII
    $R=Invoke-SimWorker -Psexec $SlowPsExec -TimeoutSec 1 -Id 'E2E-3'
    if($R.LogCleanupStatus -ne 'NotRun' -or $R.ExecutionStatus -eq 'Success'){throw "Timeout must not clean anything: exec=$($R.ExecutionStatus) cleanup=$($R.LogCleanupStatus)."}
    if(@('pkg_yigitery0.log','pkg_yigitery01.log','other.log','CBS_yigitery0.log'|Where-Object{Test-Path -LiteralPath (Join-Path $SimRemote $_)}).Count -ne 4){throw 'Timeout branch must delete nothing.'}
    # a package that fails (exit code != 0) keeps its Failed result
    New-SimLogs
    $FailPsExec=Join-Path $Temp 'failpsexec.cmd';Set-Content -LiteralPath $FailPsExec -Value "@echo off`r`nexit /b 1603" -Encoding ASCII
    $R=Invoke-SimWorker -Psexec $FailPsExec -TimeoutSec 60 -Id 'E2E-4'
    if($R.ExecutionStatus -ne 'Failed' -or [int]$R.ExitCode -ne 1603){throw 'Failed package must stay Failed whatever the cleanup does.'}
    if($R.LogCleanupStatus -ne 'NotRun'){throw "A failed package must not trigger log cleanup (got $($R.LogCleanupStatus))."}
    if(@('pkg_yigitery0.log','pkg_yigitery01.log','other.log','CBS_yigitery0.log'|Where-Object{Test-Path -LiteralPath (Join-Path $SimRemote $_)}).Count -ne 4){throw 'A failed package must keep all logs on the target.'}

    Write-Output 'PASS: log cleanup safety (name validation, user name as a separate word (yigitery0 vs yigitery01), Turkish/long names, per-target isolation, exact-file/hash/extension/protected-name rules, subfolders, folders, locked and changed files, 50-file cap, unreachable target) worker gating and the worker end to end (collect -> cleanup, failed cleanup, timeout, failed package).'
}
finally{Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue}
