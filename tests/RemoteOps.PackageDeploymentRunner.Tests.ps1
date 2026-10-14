$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Packages.ps1')
$Temp=Join-Path $env:TEMP ('RemoteOpsDeploymentRunner-'+[guid]::NewGuid().ToString('N'));$Pkg=Join-Path $Temp 'pkg';$Data=Join-Path $Temp 'data'
try{
    New-Item -ItemType Directory -Path $Pkg,$Data -Force|Out-Null
    Copy-Item (Join-Path $Root 'RemoteOps.App') (Join-Path $Pkg 'RemoteOps.App') -Recurse
    Copy-Item (Join-Path $Root 'Modules') (Join-Path $Pkg 'Modules') -Recurse
    $Runner=Join-Path $Pkg 'RemoteOps.App\RemoteOps.Runner.ps1';$Text=Get-Content $Runner -Raw
    $Text=$Text.Replace("`$BasePath = 'C:\Temp\YD_RemoteOps.App'","`$BasePath = '$Data'")
    Set-Content $Runner $Text -Encoding UTF8
    $Reports=Join-Path $Pkg 'RemoteOps.App\RemoteOps.Reports.ps1';$Text=Get-Content $Reports -Raw
    Set-Content $Reports ($Text.Replace('Microsoft.PowerShell.Management\Start-Process -FilePath $Path -ErrorAction Stop','$null=$Path')) -Encoding UTF8
    $WorkerPath=Join-Path $Pkg 'Modules\ApplicationWorkers.ps1';$Text=Get-Content $WorkerPath -Raw;$t=$null;$e=$null
    $Ast=[Management.Automation.Language.Parser]::ParseFile($WorkerPath,[ref]$t,[ref]$e)
    $RegistryMock=@'
$RegistryCheckScript={
param($ComputerName,$SearchMode,$SearchValue,$TimeoutSeconds,$SelectedApplication,$PackageOperation)
$Path=Join-Path $env:RO_TEST_STATE ($ComputerName+'.txt');$V=if(Test-Path $Path){(Get-Content $Path -Raw).Trim()}else{'3.0'}
$Present=($V -ne 'absent') -and (($SearchValue -eq 'OLD-ID' -and $V -ne '2.0') -or ($SearchValue -eq 'NEW-ID' -and $V -eq '2.0'))
$App=[PSCustomObject]@{DisplayName='Example';DisplayVersion=$V;ProductID=$SearchValue;ProductIDSource='MSI';RegistryKey=$SearchValue;RegistryPath='SOFTWARE';Publisher='Test'}
return [PSCustomObject]@{Status=$(if($Present){'Var'}else{'Yok'});DisplayName='Example';DisplayVersion=$V;ProductID=$SearchValue;ProductIDSource='MSI';RegistryKey=$SearchValue;ErrorDetail='';Applications=@($App)}
}
'@
    $PackageMock=@'
$PackageScript={
param($ComputerName,$PackagePath,$BatFile,$PsExecPath,$PsExecConnectTimeoutSeconds,$PackageTimeoutSeconds,$CollectPackageLogs,$FileOperationsModulePath,$BasePath,$PackageOperation,$OperationID,$LogLookbackMinutes,$RegistryCheckScriptText,$SearchMode,$SearchValue,$WMITimeoutSeconds,$TargetInstallVersion,$PostCheckInitialDelaySec,$PostCheckRetryCount,$PostCheckRetryIntervalSec,$SkipPostCheck,$InstallRequiresVersionMatch,$SelectedApplication,$CleanupLogsUserName='',$VersionMatchPolicy='AtLeast')
if($SelectedApplication){throw 'Old application identity leaked into installation.'}
if($TargetInstallVersion -ne '2.0'){throw 'Worker received the normal target version during downgrade.'}
if($PackageOperation -eq 'INSTALL' -and $BatFile -ne 'old.cmd'){throw 'Worker used the normal installer during downgrade.'}
$P=Join-Path $env:RO_TEST_STATE ($ComputerName+'.txt')
if($PackageOperation -eq 'UNINSTALL'){Set-Content $P 'absent'}else{if($VersionMatchPolicy -ne 'Exact'){throw 'Wrong downgrade version policy'};Set-Content $P '2.0'}
Start-Sleep -Milliseconds 150
return [PSCustomObject]@{ComputerName=$ComputerName;ExecutionStatus='Success';ExitCode=0;ErrorDetail='';PostCheckStatus=$(if($PackageOperation -eq 'UNINSTALL'){'Yok'}else{'Var'});PostCheckDisplayVersion='2.0';PostCheckErrorDetail='';LogDestination='';LogCollectionStatus='NotRequested'}
}
'@
    foreach($Case in @(@('RegistryCheckScript',$RegistryMock),@('PackageScript',$PackageMock))){$Assignment=$Ast.Find({param($N)$N -is [Management.Automation.Language.AssignmentStatementAst] -and $N.Left.Extent.Text -eq ('$'+$Case[0])},$true);$Text=$Text.Replace($Assignment.Extent.Text,$Case[1])}
    Set-Content $WorkerPath $Text -Encoding UTF8
    $Probe=Join-Path $Pkg 'RemoteOps.App\RemoteOps.Deployment.ps1'
    if(Test-Path $Probe){$t=$null;$e=$null;$Ast=[Management.Automation.Language.Parser]::ParseFile($Probe,[ref]$t,[ref]$e);$F=$Ast.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq 'Invoke-RemoteOpsPackageProbe'},$true);if($F){$Text=Get-Content $Probe -Raw;Set-Content $Probe ($Text.Replace($F.Extent.Text,'function Invoke-RemoteOpsPackageProbe {param($Definition,$ComputerName,$PsExecPath) return $true}')) -Encoding UTF8}}
    Add-Content -LiteralPath $Probe -Value "`r`nfunction Test-RemoteOpsTargetAccess {param(`$ComputerName) if(`$ComputerName -eq 'OFFLINE'){return [PSCustomObject]@{Status='Unreachable';Detail='RPC fixture'}};if(`$ComputerName -eq 'DENIED'){return [PSCustomObject]@{Status='AccessDenied';Detail='Denied fixture'}};return [PSCustomObject]@{Status='Success';Detail='fixture'}}"
    Set-Content (Join-Path $Pkg 'PsExec.exe') 'placeholder'
    $env:RO_TEST_STATE=$Data
    $P=New-RemoteOpsPackageDefinition 'Saved Example';$P.TargetVersion='2.0';$P.DowngradeEnabled=$true
    foreach($A in @('Install','Uninstall')){$P.$A.Enabled=$true;$P.$A.PackagePath='\\server\share';$P.$A.PackageFile=$A+'.cmd';$P.$A.SearchType='ProductID';$P.$A.Application=$(if($A -eq 'Install'){'NEW-ID'}else{'OLD-ID'})}
    $P.Downgrade=($P.Install|Select-Object *);$P.Downgrade.Enabled=$true;$P.Downgrade.PackageFile='old.cmd';$P.DowngradeVersion='2.0';$P.Install.Application='LATEST-ID';$P.Install.PackageFile='latest.cmd';$P.TargetVersion='5.0'
    $Progress=Join-Path $Data 'Logs\Operations\PackageDeployment\run.progress.json'
    $Request=[PSCustomObject]@{Operation='PackageDeployment';Category='Applications';Domain='TEST';UserName='tester';IsMain=$true;Targets=@('PC1','pc1','PC2','OFFLINE','DENIED');Values=[PSCustomObject]@{Action='Downgrade';PackageDefinition=$P;Confirm='DOWNGRADE'};ProgressPath=$Progress;CancelPath=($Progress+'.cancel');CheckpointRoot=($Progress+'.state');PluginName='';PluginScript='';PluginRoot='';PluginParallelSafe=$false;Parallelism=2;CleanupPackageLogs=$false;CleanupUserName='';RequestedAt=(Get-Date).ToString('o')}
    $Encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Request|ConvertTo-Json -Depth 12 -Compress)))
    $Args='-NoProfile -ExecutionPolicy Bypass -File "{0}" -RequestBase64 {1}' -f $Runner,$Encoded
    $Process=Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $Args -WindowStyle Hidden -RedirectStandardOutput (Join-Path $Temp 'out') -RedirectStandardError (Join-Path $Temp 'err') -PassThru
    [void]$Process.Handle;if(-not $Process.WaitForExit(30000)){Stop-Process $Process.Id -Force;throw 'Runner timeout.'}
    $Folders=@(Get-ChildItem (Join-Path $Data 'Logs\Operations\PackageDeployment') -Directory|Where-Object Name -like 'GUI-*')
    if($Process.ExitCode -ne 0 -or $Folders.Count -ne 1){throw ((Get-Content (Join-Path $Temp 'out') -Raw)+(Get-Content (Join-Path $Temp 'err') -Raw))}
    $Csv=Join-Path $Folders[0].FullName 'Results.csv'
    if(-not(Test-Path $Csv)){throw 'No deployment report.'}
    $Rows=@(Import-Csv $Csv -Delimiter ';')
    if($null -eq $Rows[0].PSObject.Properties['Step']){throw ('Runner does not dispatch saved package deployments: '+(($Rows|ForEach-Object{$_.ComputerName+': '+$_.ErrorDetail}) -join "`n")+(Get-Content (Join-Path $Temp 'out') -Raw)+(Get-Content (Join-Path $Temp 'err') -Raw))}
    $Final=@($Rows|Where-Object Step -eq Result)
    if($Final.Count -ne 4 -or @($Final|Where-Object{ $_.ComputerName -in @('PC1','PC2') -and $_.Status -ne 'Success'}).Count){throw ('Deployment failed: '+($Rows|Out-String))}
    $Ledger=@(Get-ChildItem (Join-Path $Data 'Logs\Reports\Ledger') -Filter '*.csv'|ForEach-Object{Import-Csv $_.FullName -Delimiter ';'})
    if($Ledger.Count -ne 4 -or @($Ledger|Where-Object{ $_.ComputerName -in @('PC1','PC2') -and $_.Outcome -ne 'Success'}).Count){throw 'Ledger contains wrong terminal counts.'}
    if(-not(Test-Path (Join-Path $Folders[0].FullName 'PackageDefinition.json'))){throw 'Immutable package snapshot not saved.'}
    $Known=@($Folders.FullName);$Request.Targets=@('PC3','PC4')
    New-Item -ItemType File -Path $Request.CancelPath -Force|Out-Null
    $Encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Request|ConvertTo-Json -Depth 12 -Compress)));$Args='-NoProfile -ExecutionPolicy Bypass -File "{0}" -RequestBase64 {1}' -f $Runner,$Encoded
    $Process=Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $Args -WindowStyle Hidden -RedirectStandardOutput (Join-Path $Temp 'cancel.out') -RedirectStandardError (Join-Path $Temp 'cancel.err') -PassThru
    [void]$Process.Handle;if(-not $Process.WaitForExit(30000)){Stop-Process $Process.Id -Force;throw 'Cancellation runner timeout.'}
    $New=@(Get-ChildItem (Join-Path $Data 'Logs\Operations\PackageDeployment') -Directory|Where-Object{$_.Name -like 'GUI-*' -and $Known -notcontains $_.FullName})
    $Cancelled=@(Import-Csv (Join-Path $New[0].FullName 'Results.csv') -Delimiter ';')
    if($Cancelled.Count -ne 2 -or @($Cancelled|Where-Object Status -ne Cancelled).Count -ne 0 -or (Test-Path (Join-Path $Data 'PC3.txt'))){throw 'Cancelled coordinator started queued package work.'}
    . (Join-Path $Root 'RemoteOps.App\RemoteOps.RunState.ps1')
    $States=@(Get-RemoteOpsRunCheckpoints $Request.CheckpointRoot|Where-Object{$_.ComputerName -in @('PC3','PC4')})
    if($States.Count -ne 2 -or @($States|Where-Object{$_.Terminal -ne $true -or $_.Outcome.Outcome -ne 'Cancelled'}).Count){throw 'Queued cancellation did not persist terminal target states for the GUI.'}
    Remove-Item -LiteralPath $Request.CancelPath -Force
    $Text=Get-Content $Runner -Raw
    $Anchor='$WorkerProcess=Start-Process -FilePath $EnginePath'
    $Text=$Text.Replace($Anchor,'if($Item.Target -eq ''PC5''){throw ''Simulated worker launch failure''};'+$Anchor)
    Set-Content $Runner $Text -Encoding UTF8
    $Known=@(Get-ChildItem (Join-Path $Data 'Logs\Operations\PackageDeployment') -Directory|ForEach-Object{$_.FullName})
    $Request.Targets=@('PC5','PC6');$Encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Request|ConvertTo-Json -Depth 12 -Compress)));$Args='-NoProfile -ExecutionPolicy Bypass -File "{0}" -RequestBase64 {1}' -f $Runner,$Encoded
    $Process=Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $Args -WindowStyle Hidden -RedirectStandardOutput (Join-Path $Temp 'failure.out') -RedirectStandardError (Join-Path $Temp 'failure.err') -PassThru
    [void]$Process.Handle;if(-not $Process.WaitForExit(30000)){Stop-Process $Process.Id -Force;throw 'Failure runner timeout.'}
    $New=@(Get-ChildItem (Join-Path $Data 'Logs\Operations\PackageDeployment') -Directory|Where-Object{$_.Name -like 'GUI-*' -and $Known -notcontains $_.FullName})
    $Failed=@(Import-Csv (Join-Path $New[0].FullName 'Results.csv') -Delimiter ';'|Where-Object ComputerName -eq PC5)
    if($Failed.Count -ne 1 -or $Failed[0].Status -ne 'Error' -or $Failed[0].ErrorDetail -notmatch 'Simulated worker launch failure'){throw 'Unstarted abnormal worker was mislabeled as cancellation or lost startup diagnostic.'}
    Write-Output 'PASS: real isolated runner, saved snapshot, parallel targets, separate identities, exact downgrade, de-duplication, unified reports and ledger.'
}finally{Remove-Item Env:\RO_TEST_STATE -ErrorAction SilentlyContinue;if(Test-Path $Temp){Remove-Item $Temp -Recurse -Force}}
