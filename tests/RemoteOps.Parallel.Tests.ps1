$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
# End-to-end test of the parallel coordinator with the REAL runner in an isolated copy of the package.
# A test plugin sleeps 3 s per computer and records its start/end time, so concurrency can be measured.
$Temp=Join-Path $env:TEMP ('RemoteOpsParallel-'+[guid]::NewGuid().ToString('N'))
$Pkg=Join-Path $Temp 'pkg';$Data=Join-Path $Temp 'data'
try{
    New-Item -ItemType Directory -Path $Pkg,$Data -Force|Out-Null
    Copy-Item -LiteralPath (Join-Path $Root 'RemoteOps.App') -Destination (Join-Path $Pkg 'RemoteOps.App') -Recurse
    Copy-Item -LiteralPath (Join-Path $Root 'Modules') -Destination (Join-Path $Pkg 'Modules') -Recurse
    # MD_Script.ps1 bilerek KOPYALANMAZ: GUI/Runner onsuz calisabilmeli (worker'lar Modules\ApplicationWorkers.ps1'de).
    $Runner=Join-Path $Pkg 'RemoteOps.App\RemoteOps.Runner.ps1'
    $RunnerText=Get-Content -LiteralPath $Runner -Raw
    $DataLiteral="'"+$Data+"'"
    if($RunnerText -notmatch [regex]::Escape("`$BasePath = 'C:\Temp\YD_RemoteOps.App'")){throw 'Runner data root literal not found; update the test.'}
    Set-Content -LiteralPath $Runner -Value $RunnerText.Replace("`$BasePath = 'C:\Temp\YD_RemoteOps.App'","`$BasePath = $DataLiteral") -Encoding UTF8
    Add-Content -LiteralPath (Join-Path $Pkg 'RemoteOps.App\RemoteOps.Deployment.ps1') -Value 'function Test-RemoteOpsOperationAccess {param($ComputerName,$Operation,$InputValues)[pscustomobject]@{Status="Success";Detail="parallel fixture"}}'
    # never open a browser from the test
    $Reports=Join-Path $Pkg 'RemoteOps.App\RemoteOps.Reports.ps1'
    $ReportsText=Get-Content -LiteralPath $Reports -Raw
    if($ReportsText -notmatch [regex]::Escape('Microsoft.PowerShell.Management\Start-Process -FilePath $Path -ErrorAction Stop')){throw 'Report opener not found; update the test.'}
    Set-Content -LiteralPath $Reports -Value $ReportsText.Replace('Microsoft.PowerShell.Management\Start-Process -FilePath $Path -ErrorAction Stop','$null=$Path') -Encoding UTF8
    # test plugin
    $PluginRoot=Join-Path $Pkg 'RemoteOps.App\Plugins\ParTest'
    New-Item -ItemType Directory -Path $PluginRoot -Force|Out-Null
    Set-Content -LiteralPath (Join-Path $PluginRoot 'manifest.json') -Encoding UTF8 -Value (@{Name='ParTest';Version='1';Script='Invoke-ParTest.ps1';Operations=@(@{Name='ParSafe';Title='Parallel safe';ParallelSafe=$true;Fields=@(@{Key='Targets';Label='t';Type='Targets'})},@{Name='ParSerial';Title='Serial only';Fields=@(@{Key='Targets';Label='t';Type='Targets'})})}|ConvertTo-Json -Depth 6)
    Set-Content -LiteralPath (Join-Path $PluginRoot 'Invoke-ParTest.ps1') -Encoding UTF8 -Value @'
param($Request,$Context)
$Target=@($Context.Systems)[0]
$Start=Get-Date
Start-Sleep -Seconds 3
if($Target -eq 'FAIL-PC'){throw 'Simulated target failure'}
$Out=Join-Path (Join-Path $Context.BasePath 'Logs\RemoteOps') ($Context.OperationID+'_ParTest.csv')
New-Item -ItemType Directory -Path (Split-Path -Parent $Out) -Force|Out-Null
$Row=[PSCustomObject]@{OperationID=$Context.OperationID;ComputerName=$Target;Status='Success';Start=$Start.ToString('o');End=(Get-Date).ToString('o');Pid=$PID}
$Row|Export-Csv -LiteralPath $Out -Delimiter ';' -NoTypeInformation
Write-Host "$Target plugin done"
return [PSCustomObject]@{Completed=$true;ResultCsv=$Out;Rows=@($Row)}
'@
    function Invoke-TestRun {
        param([string]$Operation,[int]$Parallelism,[bool]$PluginSafe,[string[]]$Targets)
        $Plugin=Join-Path $PluginRoot 'manifest.json'
        $ProgressFile=Join-Path (Join-Path $Data ('Logs\Operations\'+$Operation)) ([guid]::NewGuid().ToString('N')+'.progress.json')
        $Request=[PSCustomObject]@{Operation=$Operation;Category='ParTest';Domain='D';UserName='u';IsMain=$true;Targets=$Targets;Values=[PSCustomObject]@{};ProgressPath=$ProgressFile;PluginName='ParTest';PluginScript='Invoke-ParTest.ps1';PluginRoot=$PluginRoot;PluginParallelSafe=$PluginSafe;Parallelism=$Parallelism;RequestedAt=(Get-Date).ToString('o')}
        $Base64=[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($Request|ConvertTo-Json -Depth 6 -Compress)))
        $Watch=[System.Diagnostics.Stopwatch]::StartNew()
        $Process=Start-Process -FilePath "$PSHOME\powershell.exe" -ArgumentList ('-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -RequestBase64 {1}' -f $Runner,$Base64) -RedirectStandardOutput (Join-Path $Temp 'run.out') -RedirectStandardError (Join-Path $Temp 'run.err') -WindowStyle Hidden -PassThru -Wait
        $Watch.Stop()
        $RunFolder=@(Get-ChildItem -LiteralPath (Join-Path $Data "Logs\Operations\$Operation") -Directory|Sort-Object LastWriteTime -Descending)[0]
        if(-not(Test-Path -LiteralPath (Join-Path $RunFolder.FullName 'Results.csv'))){throw ('Run produced no Results.csv. Output: '+((Get-Content -LiteralPath (Join-Path $Temp 'run.out') -ErrorAction SilentlyContinue) -join ' / ')+' | Errors: '+((Get-Content -LiteralPath (Join-Path $Temp 'run.err') -ErrorAction SilentlyContinue) -join ' / '))}
        $Progress=Get-Content -LiteralPath $ProgressFile -Raw|ConvertFrom-Json
        if(@($Progress.Targets).Count -ne $Targets.Count -or @($Progress.Targets|Where-Object Stage -ne Completed).Count){throw 'Parallel/serial live target snapshot lost terminal targets.'}
        return [PSCustomObject]@{ExitCode=$Process.ExitCode;Seconds=$Watch.Elapsed.TotalSeconds;Folder=$RunFolder.FullName;Progress=$Progress;Output=@(Get-Content -LiteralPath (Join-Path $Temp 'run.out') -ErrorAction SilentlyContinue)}
    }
    function Get-MaxConcurrency {
        param([object[]]$Rows)
        $Events=@();foreach($Row in $Rows){$Events+=[PSCustomObject]@{T=[datetime]$Row.Start;D=1};$Events+=[PSCustomObject]@{T=[datetime]$Row.End;D=-1}}
        $Current=0;$Max=0
        foreach($Event in ($Events|Sort-Object T,D)){$Current+=$Event.D;if($Current -gt $Max){$Max=$Current}}
        return $Max
    }
    $Targets=@('PC-1','PC-2','PC-3','PC-4','PC-5','FAIL-PC')

    # ---- parallel: 3 workers over 6 targets
    $Run=Invoke-TestRun -Operation 'ParSafe' -Parallelism 3 -PluginSafe $true -Targets $Targets
    if($Run.ExitCode -ne 0){throw "Parallel run exit code $($Run.ExitCode)"}
    $Rows=@(Import-Csv -LiteralPath (Join-Path $Run.Folder 'Results.csv') -Delimiter ';')
    if($Rows.Count -ne 6 -or (($Rows|ForEach-Object ComputerName) -join ',') -ne ($Targets -join ',')){throw ('Rows missing or out of input order: '+(($Rows|ForEach-Object ComputerName) -join ','))}
    $Failed=@($Rows|Where-Object{$_.ComputerName -eq 'FAIL-PC'})
    if($Failed.Count -ne 1 -or $Failed[0].Status -ne 'Failed' -or $Failed[0].ErrorDetail -notmatch 'Simulated target failure'){throw 'Failing target must be reported as Failed with its error.'}
    if(@($Run.Progress.Targets|Where-Object{$_.ComputerName -eq 'FAIL-PC' -and $_.Outcome -eq 'Error'}).Count -ne 1){throw 'Parallel live view lost a worker failure.'}
    $Good=@($Rows|Where-Object{$_.Status -eq 'Success'})
    if($Good.Count -ne 5){throw ('Five targets must succeed: '+(($Rows|ForEach-Object{$_.ComputerName+'='+$_.Status+'['+$_.ErrorDetail+']'}) -join ' | '))}
    $Concurrency=Get-MaxConcurrency -Rows $Good
    if($Concurrency -lt 2 -or $Concurrency -gt 3){throw "Measured concurrency $Concurrency is outside 2..3."}
    if(@($Good|ForEach-Object Pid|Select-Object -Unique).Count -lt 2){throw 'Targets did not run in separate processes.'}
    if($Run.Seconds -gt 40){throw "Parallel run too slow ($([int]$Run.Seconds) s)."}
    $Ledger=@(Import-Csv -LiteralPath (Get-ChildItem (Join-Path $Data 'Logs\Reports\Ledger') -Filter '*.csv'|Select-Object -First 1).FullName -Delimiter ';')
    if($Ledger.Count -ne 6 -or @($Ledger|Where-Object Outcome -eq 'Error').Count -ne 1 -or @($Ledger|Where-Object Outcome -eq 'Success').Count -ne 5){throw 'Ledger outcomes are wrong for the parallel run.'}
    foreach($Name in 'Results.csv','Results.html','Activity.html','RemoteOps.log'){if(-not(Test-Path -LiteralPath (Join-Path $Run.Folder $Name))){throw "Missing run artifact: $Name"}}
    if(@(Get-ChildItem -LiteralPath (Join-Path $Data 'Logs\Operations\ParSafe') -Directory).Count -ne 1){throw 'A parallel run must create exactly one run folder.'}
    $Log=Get-Content -LiteralPath (Join-Path $Run.Folder 'RemoteOps.log') -Raw
    if($Log -notmatch 'PARALLEL \| Workers=3 \| Targets=6' -or ([regex]::Matches($Log,'\] START \|')).Count -ne 1){throw 'Technical log must be one shared log with a single START.'}
    if(@($Run.Output|Where-Object{$_ -match '^PC-\d - Success$|^FAIL-PC - Error$'}).Count -ne 6){throw "Per-target result lines missing from output: $($Run.Output -join ' / ')"}
    if(@(Get-ChildItem -LiteralPath (Join-Path $Run.Folder 'Workers') -Filter '*.result.xml').Count -ne 6){throw 'Worker result files missing.'}

    # ---- not opted in: stays sequential even when 3 is requested
    $Serial=Invoke-TestRun -Operation 'ParSerial' -Parallelism 3 -PluginSafe $false -Targets @('PC-1','PC-2','PC-3')
    $SerialRows=@(Import-Csv -LiteralPath (Join-Path $Serial.Folder 'Results.csv') -Delimiter ';')
    if($SerialRows.Count -ne 3 -or (Get-MaxConcurrency -Rows $SerialRows) -ne 1){throw 'Operation without ParallelSafe must run one computer at a time.'}
    if(@($Serial.Output|Where-Object{$_ -match 'paralel calismayi desteklemiyor'}).Count -ne 1){throw 'User must be told that the operation runs sequentially.'}
    if(Test-Path -LiteralPath (Join-Path $Serial.Folder 'Workers')){throw 'Sequential run must not create workers.'}

    # ---- parallelism 1 keeps the old behaviour
    $One=Invoke-TestRun -Operation 'ParSafe' -Parallelism 1 -PluginSafe $true -Targets @('PC-1','PC-2')
    $OneRows=@(Import-Csv -LiteralPath (Join-Path $One.Folder 'Results.csv') -Delimiter ';')
    if($OneRows.Count -ne 2 -or (Get-MaxConcurrency -Rows $OneRows) -ne 1 -or (Test-Path -LiteralPath (Join-Path $One.Folder 'Workers'))){throw 'Parallelism 1 must be the unchanged sequential path.'}
    Write-Output ('PASS: parallel coordinator (3 workers, measured concurrency {0}, {1:N0}s for 6 targets), ordered merge, failure isolation, shared log, ledger, opt-in gate and sequential fallback.' -f $Concurrency,$Run.Seconds)
}
finally{if(Test-Path -LiteralPath $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue}}
