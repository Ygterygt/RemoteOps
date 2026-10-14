$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Packages.ps1')
$File=Join-Path $Root 'RemoteOps.App\RemoteOps.Deployment.ps1'
if(-not(Test-Path $File)){throw 'Deployment state machine is missing.'};. $File
$t=$null;$e=$null;$Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'Modules\ApplicationWorkers.ps1'),[ref]$t,[ref]$e)
. ([scriptblock]::Create($Ast.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq 'Compare-ApplicationVersion'},$true).Extent.Text))
$P=New-RemoteOpsPackageDefinition 'Example';$P.TargetVersion='2.0';$P.DowngradeEnabled=$true
foreach($A in @('Install','Uninstall')){$P.$A.Enabled=$true;$P.$A.PackagePath='\\server\share';$P.$A.PackageFile=($A+'.cmd');$P.$A.Application=($A+'-ID');$P.$A.SearchType='ProductID'}
$P.Downgrade=($P.Install|Select-Object *);$P.Downgrade.Enabled=$true;$P.Downgrade.CheckMode='Version controlled';$P.DowngradeVersion='2.0'
$script:Events=New-Object 'System.Collections.Generic.List[string]'
$script:Version='3.0';$script:Installed=$true;$script:Scenario='Good';$script:Cancel=$false
$script:RequestedAction='Downgrade'
$Detect={param($Identity,$Computer)
    $script:Events.Add('Detect:'+ $Identity.Application)
    if(($script:Scenario -eq 'ThrowAfterRemove' -and -not $script:Installed) -or ($script:Scenario -eq 'ThrowAfterInstall' -and $script:Version -eq '2.0')){throw 'RPC unavailable'}
    if($script:Scenario -eq 'LostAfterRemove' -and -not $script:Installed){return [PSCustomObject]@{Status='Hata';DisplayVersion='';ErrorDetail='RPC unavailable'}}
    if($script:Scenario -eq 'LostAfterInstall' -and $script:Version -eq '2.0'){return [PSCustomObject]@{Status='Hata';DisplayVersion='';ErrorDetail='RPC unavailable'}}
    if($script:Scenario -eq 'Ambiguous'){return [PSCustomObject]@{Status='CokluEslesme';DisplayVersion='';ErrorDetail='Two matches'}}
    $Present=if($script:Scenario -eq 'DifferentCurrentIdentity'){$Identity.Application -eq 'Install-ID'}elseif($Identity.Application -eq 'Uninstall-ID'){$script:Installed}else{$script:Version -eq '2.0' -and $script:Installed}
    return [PSCustomObject]@{Status=$(if($Present){'Var'}else{'Yok'});DisplayVersion=$script:Version;ErrorDetail=''}
}
$Execute={param($Part,$Action,$Policy,$StepId)
    $script:Events.Add('Execute:'+ $Action+':'+$Policy)
    if($script:RequestedAction -eq 'Downgrade' -and $Action -eq 'Install' -and $Policy -ne 'Exact'){throw 'Downgrade installation did not request Exact.'}
    if($script:Scenario -eq 'Timeout'){return [PSCustomObject]@{ExecutionStatus='Timeout';ExitCode=$null;ErrorDetail='Timeout'}}
    if($script:Scenario -eq 'LaunchedUnknown'){return [PSCustomObject]@{ExecutionStatus='Hata';Triggered=$true;ExitCode=$null;ErrorDetail='Connection lost after launch'}}
    if(($script:Scenario -eq 'RemoveFail' -and $Action -eq 'Uninstall') -or ($script:Scenario -eq 'InstallFail' -and $Action -eq 'Install')){return [PSCustomObject]@{ExecutionStatus='Failed';ExitCode=1603;ErrorDetail='Package failed'}}
    if($Action -eq 'Uninstall'){
        if($script:Scenario -ne 'StillPresent'){$script:Installed=$false}
        if($script:Scenario -eq 'CancelAfterRemove'){$script:Cancel=$true}
    }else{$script:Installed=$true;$script:Version=if($script:Scenario -eq 'WrongVersion'){'4.0'}else{'2.0'}}
    return [PSCustomObject]@{ExecutionStatus='Success';ExitCode=$(if($script:Scenario -eq 'Reboot'){3010}else{0});ErrorDetail=''}
}
$Validate={param($Part,$Computer)$script:Events.Add('Validate:'+ $Part.PackageFile);if($script:Scenario -eq 'SourceFail'){throw 'Source inaccessible'}}
foreach($Case in @(@('Good','3.0','Success',2),@('Equal','2.0','Skipped',0),@('Older','1.0','Skipped',0),@('Missing','','Skipped',0),@('DifferentCurrentIdentity','3.0','Error',0),@('Ambiguous','3.0','Error',0),@('SourceFail','3.0','Error',0),@('RemoveFail','3.0','Error',1),@('StillPresent','3.0','Error',1),@('InstallFail','3.0','Error',2),@('WrongVersion','3.0','Error',2),@('Reboot','3.0','RebootRequired',1),@('Timeout','3.0','Indeterminate',1),@('LaunchedUnknown','3.0','Indeterminate',1),@('LostAfterRemove','3.0','Indeterminate',1),@('LostAfterInstall','3.0','Indeterminate',2),@('ThrowAfterRemove','3.0','Indeterminate',1),@('ThrowAfterInstall','3.0','Indeterminate',2),@('CancelAfterRemove','3.0','Cancelled',1))){
    $script:Events.Clear();$script:Scenario=$Case[0];$script:Version=$Case[1];$script:Installed=$Case[0] -ne 'Missing';$script:Cancel=$false
    $Result=Invoke-RemoteOpsPackageDeployment -Definition $P -Action Downgrade -ComputerName PC1 -OperationID RUN1 -Detect $Detect -Execute $Execute -ValidateSource $Validate -VersionComparer ${function:Compare-ApplicationVersion} -IsCancelled {$script:Cancel} -Checkpoint {param($State)}
    if($Result.Outcome.Outcome -ne $Case[2]){throw "Case $($Case[0]) returned $($Result.Outcome.Outcome): $($Result.Outcome.Detail)"}
    $Calls=@($script:Events|Where-Object{$_ -like 'Execute:*'})
    if($Calls.Count -ne $Case[3]){throw "Case $($Case[0]) executed $($Calls.Count) steps instead of $($Case[3])."}
    if($Case[0] -eq 'Good'){
        if(($Calls -join ',') -ne 'Execute:Uninstall:AtLeast,Execute:Install:Exact'){throw 'Wrong identity/action sequence.'}
        if($script:Events.IndexOf('Validate:Install.cmd') -gt $script:Events.IndexOf('Execute:Uninstall:AtLeast')){throw 'Install source was validated after uninstall.'}
        if(@($Result.Rows|Where-Object Status -eq 'Success').Count -lt 4){throw 'Successful step details missing.'}
    }
    if($Case[0] -eq 'InstallFail' -and $Result.Outcome.Detail -notmatch 'removed'){throw 'Removed-but-not-installed recovery detail missing.'}
}
foreach($Case in @(@('Install','LaunchedUnknown'),@('Uninstall','LaunchedUnknown'),@('Install','LostAfterInstall'),@('Uninstall','LostAfterRemove'))){
    $script:RequestedAction=$Case[0];$script:Scenario=$Case[1];$script:Installed=$true;$script:Version='3.0';$script:Cancel=$false
    $Result=Invoke-RemoteOpsPackageDeployment -Definition $P -Action $Case[0] -ComputerName PC1 -OperationID BASIC -Detect $Detect -Execute $Execute -ValidateSource $Validate -VersionComparer ${function:Compare-ApplicationVersion}
    if($Result.Outcome.Outcome -ne 'Indeterminate'){throw "Basic $($Case[0]) $($Case[1]) lost unknown-state classification."}
}
Write-Output 'PASS: downgrade decision matrix, separate identities, source checks, errors, exact version, reboot, timeout and cancellation.'
