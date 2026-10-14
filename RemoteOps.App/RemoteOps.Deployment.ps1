# Deployment engine: callbacks own remote IO; this file owns ordering and results.
function Invoke-RemoteOpsPackageProbe {
    param($Definition,[string]$ComputerName,[string]$PsExecPath)
    $Source=Join-Path ([string]$Definition.PackagePath) ([string]$Definition.PackageFile)
    if(-not(Test-Path -LiteralPath $Source -PathType Leaf)){throw "Selected account cannot read package source: $Source"}
    $Escaped=$Source.Replace("'","''")
    $Probe="`$ErrorActionPreference='Stop';try{`$s=[IO.File]::OpenRead('$Escaped');`$s.Dispose();exit 0}catch{Write-Output `$_.Exception.Message;exit 9001}"
    $Encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Probe))
    $Args='\\{0} -s -accepteula -n 10 powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand {1}' -f $ComputerName,$Encoded
    $Out=[IO.Path]::GetTempFileName();$Err=[IO.Path]::GetTempFileName();$Process=$null
    try{
        $Process=Microsoft.PowerShell.Management\Start-Process -FilePath $PsExecPath -ArgumentList $Args -RedirectStandardOutput $Out -RedirectStandardError $Err -WindowStyle Hidden -PassThru -ErrorAction Stop
        [void]$Process.Handle
        if(-not $Process.WaitForExit(30000)){Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue;throw "Package source check timed out for $ComputerName."}
        if($Process.ExitCode -ne 0){throw ("Target SYSTEM cannot read package source: $Source | "+((@(Get-Content -LiteralPath $Out,$Err -ErrorAction SilentlyContinue)) -join ' '))}
        return $true
    }finally{Remove-Item -LiteralPath $Out,$Err -Force -ErrorAction SilentlyContinue;if($null -ne $Process){$Process.Dispose()}}
}
# Read-only probe inherits the selected identity; its entire SMB negotiation/read is bounded.
function Invoke-RemoteOpsBoundedProbe {
    param([string]$ScriptText,[ValidateRange(1,60)][int]$TimeoutSeconds=6)
    $Info=New-Object Diagnostics.ProcessStartInfo
    $Info.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $Info.Arguments='-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ScriptText))
    $Info.UseShellExecute=$false;$Info.CreateNoWindow=$true;$Info.RedirectStandardOutput=$true;$Info.RedirectStandardError=$true
    $Process=New-Object Diagnostics.Process;$Process.StartInfo=$Info
    try{
        [void]$Process.Start()
        $Output=$Process.StandardOutput.ReadToEndAsync();$Errors=$Process.StandardError.ReadToEndAsync()
        if(-not $Process.WaitForExit($TimeoutSeconds*1000)){
            if(-not $Process.HasExited){$Process.Kill();[void]$Process.WaitForExit(5000)}
            throw (New-Object Runtime.InteropServices.COMException 'SMB read-only access probe timed out.',([int]-2147023436))
        }
        if($Process.ExitCode -ne 0){throw ('Access probe failed: '+$Errors.Result)}
        return ($Output.Result|ConvertFrom-Json -ErrorAction Stop)
    }finally{$Process.Dispose()}
}
# Read-only transport check under the runner's selected identity. ICMP is never a gate.
function Test-RemoteOpsTargetAccess {
    param([string]$ComputerName,[int]$TimeoutSeconds=6,[scriptblock]$Connect=$null,
        [ValidateSet('Management','SMB')][string]$Transport='Management',[string]$Namespace='root\default')
    try{
        if($null -ne $Connect){& $Connect $ComputerName $TimeoutSeconds|Out-Null}
        elseif($Transport -eq 'SMB'){
            $EscapedComputer=$ComputerName.Replace("'","''")
            $Probe=@'
$ErrorActionPreference='Stop'
try{
 $Directory=New-Object IO.DirectoryInfo ('\\{0}\admin$' -f '__COMPUTER__')
 $Enumerator=$Directory.EnumerateFileSystemInfos().GetEnumerator()
 try{[void]$Enumerator.MoveNext()}finally{if($Enumerator -is [IDisposable]){$Enumerator.Dispose()}}
 @{Success=$true}|ConvertTo-Json -Compress
}catch{
 $E=$_.Exception;$Code=$E.HResult;$Native=0
 while($null -ne $E){$Code=$E.HResult;if($E -is [ComponentModel.Win32Exception]){$Native=$E.NativeErrorCode};$E=$E.InnerException}
 @{Success=$false;Code=$Code;Native=$Native;Detail=$_.Exception.Message}|ConvertTo-Json -Compress
}
'@
            $Result=Invoke-RemoteOpsBoundedProbe -ScriptText ($Probe.Replace('__COMPUTER__',$EscapedComputer)) -TimeoutSeconds $TimeoutSeconds
            if(-not $Result.Success){
                if([int]$Result.Native -ne 0){throw (New-Object ComponentModel.Win32Exception ([int]$Result.Native),([string]$Result.Detail))}
                throw (New-Object Runtime.InteropServices.COMException ([string]$Result.Detail),([int]$Result.Code))
            }
        }else{
            Add-Type -AssemblyName System.Management
            $Options=New-Object System.Management.ConnectionOptions
            $Options.Timeout=[TimeSpan]::FromSeconds($TimeoutSeconds)
            $Options.Impersonation=[System.Management.ImpersonationLevel]::Impersonate
            $Scope=New-Object System.Management.ManagementScope ("\\$ComputerName\$Namespace"),$Options
            $Scope.Connect()
        }
        return [PSCustomObject]@{Status='Success';Detail=($Transport+' connection established.')}
    }catch{
        $Status='Failed';$Codes=@();$Exception=$_.Exception
        while($null -ne $Exception){
            $Code=('{0:X8}' -f [int]$Exception.HResult);$Codes+=$Code
            $Native=if($Exception -is [ComponentModel.Win32Exception]){$Exception.NativeErrorCode}elseif($Code.StartsWith('8007')){[Convert]::ToInt32($Code.Substring(4),16)}else{0}
            if($Code -in @('80070005','80041003','8007052E') -or $Native -in @(5,1326)){$Status='AccessDenied'}
            elseif($Status -ne 'AccessDenied' -and ($Code -in @('800706BA','800706BE','80070035','80070043','800705B4','8007274C','80041015') -or $Native -in @(53,64,67,121,1231,1232,1236,1722,1726,10051,10060,10061,10064,10065,11001))){$Status='Unreachable'}
            $Exception=$Exception.InnerException
        }
        return [PSCustomObject]@{Status=$Status;Detail=($Transport+': '+$_.Exception.Message+' | HRESULT='+($Codes -join ','))}
    }
}
function Test-RemoteOpsOperationAccess {
    param([string]$ComputerName,[string]$Operation,$InputValues=$null)
    # Files use SMB only; registry and management operations use their actual namespaces.
    $Transports=if($Operation -like 'File*'){@('SMB')}elseif($Operation -in @('PackageTrigger','PackageDeployment')){@('SMB','Management')}else{@('Management')}
    if($Operation -eq 'PackageDeployment' -and $null -ne $InputValues){
        $Definition=Get-RemoteOpsPackageValue $InputValues PackageDefinition
        $Action=[string](Get-RemoteOpsPackageValue $InputValues Action '')
        $Part=Get-RemoteOpsPackageValue $Definition $Action
        if($Action -ne 'Downgrade' -and (Get-RemoteOpsPackageValue $Part CheckMode '') -eq 'Trigger without checks'){$Transports=@('SMB')}
    }
    if($Operation -eq 'PackageTrigger' -and $null -ne $InputValues -and ((Get-RemoteOpsPackageValue $InputValues CheckMode '') -eq 'Trigger without checks' -or [string]::IsNullOrWhiteSpace([string](Get-RemoteOpsPackageValue $InputValues Application '')))){$Transports=@('SMB')}
    foreach($Transport in $Transports){
        $Namespace=if($Operation -like 'Registry*' -or $Operation -in @('ApplicationCheck','ApplicationInventory','PackageTrigger','PackageDeployment')){'root\default'}else{'root\cimv2'}
        if($Transport -eq 'SMB'){$Access=Test-RemoteOpsTargetAccess -ComputerName $ComputerName -Transport SMB}
        else{$Access=Test-RemoteOpsTargetAccess -ComputerName $ComputerName -Transport Management -Namespace $Namespace}
        if($Access.Status -ne 'Success'){return $Access}
    }
    return [PSCustomObject]@{Status='Success';Detail='Required operation connections established.'}
}
function Get-RemoteOpsDetectionFailureDetail {
    param($Detection)
    $Status=[string](Get-RemoteOpsPackageValue $Detection Status '')
    $Detail=[string](Get-RemoteOpsPackageValue $Detection ErrorDetail '')
    $Message=if($Status -eq 'CokluEslesme'){'Birden fazla uygulama eslesti; paket kimligini veya tam registry anahtarini kontrol edin.'}else{'Hedefe erisim veya uygulama sorgusu basarisiz; baglanti ve hesap yetkilerini kontrol edin.'}
    if($Status){$Message+=' Status='+$Status+'.'}
    if(-not [string]::IsNullOrWhiteSpace($Detail)){$Message+=' '+$Detail}
    return $Message
}
function Get-RemoteOpsDowngradeDecision {
    param($Detection,[string]$TargetVersion,[scriptblock]$VersionComparer)
    $Status=[string](Get-RemoteOpsPackageValue $Detection Status '')
    $Version=[string](Get-RemoteOpsPackageValue $Detection DisplayVersion '')
    $Decision='DetectionFailed';$Reason=Get-RemoteOpsDetectionFailureDetail $Detection
    if($Status -eq 'Yok'){$Decision='NotInstalled';$Reason='Application not installed; use Install.'}
    elseif($Status -eq 'Var'){
        $Comparison=& $VersionComparer $Version $TargetVersion
        if($Comparison.Comparable){
            if($Comparison.Result -gt 0){$Decision='Downgrade';$Reason='Installed version is newer.'}
            elseif($Comparison.Result -eq 0){$Decision='AlreadyAtTarget';$Reason='Target version already installed.'}
            else{$Decision='OlderVersionPresent';$Reason='Installed version is older; use Install.'}
        }else{$Reason=[string]$Comparison.Reason}
    }
    return [PSCustomObject]@{Decision=$Decision;Reason=$Reason;PreviousVersion=$Version}
}
function Enter-RemoteOpsDeploymentLock {
    param([string]$Root,[string]$ComputerName,[string]$ApplicationKey,[string]$OperationID)
    New-Item -ItemType Directory -Path $Root -Force|Out-Null
    $Hash=[Security.Cryptography.SHA256]::Create()
    try{$Bytes=$Hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($ComputerName.Trim().ToLowerInvariant()+"`n"+$ApplicationKey.Trim().ToLowerInvariant()))}finally{$Hash.Dispose()}
    $Name=([BitConverter]::ToString($Bytes)).Replace('-','')+'.lock';$Path=Join-Path $Root $Name
    try{$Stream=[IO.File]::Open($Path,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw "Another deployment is active for $ComputerName / $ApplicationKey."}
    try{
        $Stream.SetLength(0);$Bytes=[Text.Encoding]::UTF8.GetBytes("$PID|$OperationID");$Stream.Write($Bytes,0,$Bytes.Length);$Stream.Flush()
        return [PSCustomObject]@{Stream=$Stream;Path=$Path}
    }catch{$Stream.Dispose();throw}
}
function Exit-RemoteOpsDeploymentLock {param($Lock)if($null -ne $Lock -and $null -ne $Lock.Stream){$Lock.Stream.Dispose()}}
function Test-RemoteOpsUnknownExecution {
    param($Result)
    return ([string](Get-RemoteOpsPackageValue $Result ExecutionStatus '') -eq 'Timeout' -or ((Get-RemoteOpsPackageValue $Result Triggered $false) -eq $true -and $null -eq (Get-RemoteOpsPackageValue $Result ExitCode)))
}

function Invoke-RemoteOpsPackageDeployment {
    param($Definition,[ValidateSet('Install','Uninstall','Downgrade')][string]$Action,[string]$ComputerName,[string]$OperationID,
        [scriptblock]$Detect,[scriptblock]$Execute,[scriptblock]$ValidateSource,[scriptblock]$VersionComparer,
        [scriptblock]$IsCancelled={return $false},[scriptblock]$Checkpoint={param($State)},[scriptblock]$CheckAccess=$null)
    Assert-RemoteOpsPackageDefinition $Definition $Action
    $Definition=Copy-RemoteOpsPackageDefinition $Definition
    $TargetVersion=if($Action -eq 'Downgrade'){$Definition.DowngradeVersion}else{$Definition.TargetVersion}
    $Rows=New-Object 'System.Collections.Generic.List[object]'
    $State=[PSCustomObject]@{ComputerName=$ComputerName;OperationID=$OperationID;PackageId=$Definition.Id;PackageName=$Definition.Name;PackageRevision=$Definition.Revision;Action=$Action;Step='Precheck';Terminal=$false;SideEffectActive=$false;VerificationPending=$false;Removed=$false;PreviousVersion='';FinalVersion='';Rows=@();Outcome=$null;UpdatedAt=''}
    $Save={
        $State.Rows=@($Rows.ToArray());$State.UpdatedAt=(Get-Date).ToString('o');& $Checkpoint $State|Out-Null
    }
    $AddRow={param($Step,$Status,$Detail='',$Code=$null,$Reboot=$false,$Raw=$null)
        $Row=[PSCustomObject]@{ComputerName=$ComputerName;Step=$Step;Action=$Action;Status=$Status;PreviousVersion=$State.PreviousVersion;TargetVersion=$TargetVersion;FinalVersion=$State.FinalVersion;ExitCode=$Code;RebootRequired=$Reboot;ErrorDetail=$Detail;OperationID=$OperationID;PackageId=$Definition.Id;PackageRevision=$Definition.Revision;PackageName=$Definition.Name;LogDestination=[string](Get-RemoteOpsPackageValue $Raw LogDestination '');LogCollectionStatus=[string](Get-RemoteOpsPackageValue $Raw LogCollectionStatus '');LogCleanupStatus=[string](Get-RemoteOpsPackageValue $Raw LogCleanupStatus '')}
        $Rows.Add($Row);$State.Step=$Step;& $Save
    }
    $Finish={param($Outcome,$Detail)
        $State.Terminal=$true;$State.SideEffectActive=$false;$State.VerificationPending=$false
        $State.Outcome=[PSCustomObject]@{ComputerName=$ComputerName;Outcome=$Outcome;CompletedAt=(Get-Date).ToString('o');Detail=$Detail;PackageId=$Definition.Id;PackageRevision=$Definition.Revision;PackageName=$Definition.Name;Action=$Action;PreviousVersion=$State.PreviousVersion;TargetVersion=$TargetVersion;FinalVersion=$State.FinalVersion}
        & $AddRow 'Result' $Outcome $Detail
        return [PSCustomObject]@{Rows=@($Rows.ToArray());Outcome=$State.Outcome}
    }
    $RunStep={param($Part,$StepAction,$Policy)
        $State.Step=$StepAction;$State.SideEffectActive=$true;& $Save
        $StepId='{0}-S{1:D2}' -f $OperationID,($Rows.Count+1)
        $Output=@(& $Execute $Part $StepAction $Policy $StepId)
        $Result=@($Output|Where-Object{$null -ne $_ -and $null -ne $_.PSObject.Properties['ExecutionStatus']}|Select-Object -Last 1)
        if($Result.Count -ne 1){throw 'Package worker returned no execution status.'}
        $State.SideEffectActive=Test-RemoteOpsUnknownExecution $Result[0]
        $Exec=$Result[0];$Status=[string]$Exec.ExecutionStatus
        $State.VerificationPending=$Status -like 'Success*'
        $Code=Get-RemoteOpsPackageValue $Exec ExitCode
        & $AddRow $StepAction $Status ([string](Get-RemoteOpsPackageValue $Exec ErrorDetail '')) $Code ($Code -in @(3010,1641)) $Exec
        return $Exec
    }
    try{
        & $Save
        if(& $IsCancelled){return (& $Finish 'Cancelled' 'Cancelled before deployment started.')}
        if($null -ne $CheckAccess){
            $Access=& $CheckAccess $ComputerName
            $AccessStatus=[string](Get-RemoteOpsPackageValue $Access Status '')
            if($AccessStatus -ne 'Success'){
                $Outcome=if($AccessStatus -eq 'Unreachable'){'Unreachable'}else{'Error'}
                $Reason=if($AccessStatus -eq 'Unreachable'){'Erisilemedi - paket calistirilmadi.'}elseif($AccessStatus -eq 'AccessDenied'){'Yetki hatasi - paket calistirilmadi.'}else{'Erisim kontrolu basarisiz - paket calistirilmadi.'}
                $Reason+=' '+[string](Get-RemoteOpsPackageValue $Access Detail '')
                & $AddRow 'AccessCheck' $Outcome $Reason
                return (& $Finish $Outcome $Reason)
            }
        }
        if($Action -eq 'Downgrade'){
            $Detection=& $Detect $Definition.Uninstall $ComputerName
            $CanUninstall=$Detection.Status -eq 'Var'
            if($Detection.Status -eq 'Yok'){$Detection=& $Detect $Definition.Downgrade $ComputerName}
            $Decision=Get-RemoteOpsDowngradeDecision $Detection $TargetVersion $VersionComparer
            $State.PreviousVersion=$Decision.PreviousVersion
            & $AddRow 'Precheck' $(if($Decision.Decision -eq 'DetectionFailed'){'Failed'}else{'Success'}) $Decision.Reason
            if($Decision.Decision -eq 'DetectionFailed'){return (& $Finish 'Error' $Decision.Reason)}
            if($Decision.Decision -ne 'Downgrade'){return (& $Finish 'Skipped' $Decision.Reason)}
            if(-not $CanUninstall){return (& $Finish 'Error' 'A newer application exists, but the configured uninstall identity does not match it. Correct the uninstall identity before downgrading.')}
            # Both sources are checked before the installed application is removed.
            & $ValidateSource $Definition.Downgrade $ComputerName|Out-Null
            & $ValidateSource $Definition.Uninstall $ComputerName|Out-Null
            if(& $IsCancelled){return (& $Finish 'Cancelled' 'Cancelled before uninstall.')}
            $Exec=& $RunStep $Definition.Uninstall 'Uninstall' 'AtLeast'
            if(Test-RemoteOpsUnknownExecution $Exec){return (& $Finish 'Indeterminate' 'Uninstall was launched but its result is unknown. Check the remote application and running package before retrying.')}
            if($Exec.ExecutionStatus -notlike 'Success*'){return (& $Finish 'Error' ('Uninstall failed: '+[string](Get-RemoteOpsPackageValue $Exec ErrorDetail '')))}
            if((Get-RemoteOpsPackageValue $Exec ExitCode) -in @(3010,1641)){return (& $Finish 'RebootRequired' 'Uninstall requires or initiated a reboot. Install was not started.')}
            $AfterRemove=& $Detect $Definition.Uninstall $ComputerName
            if($AfterRemove.Status -notin @('Var','Yok','CokluEslesme')){return (& $Finish 'Indeterminate' 'Uninstall completed, but the remote application state could not be read. Check the target before retrying; install was not started.')}
            & $AddRow 'VerifyUninstall' $(if($AfterRemove.Status -eq 'Yok'){'Success'}else{'Failed'}) 'Application absence checked using the uninstall identity.'
            if($AfterRemove.Status -ne 'Yok'){return (& $Finish 'Error' 'Uninstall did not establish application absence; install was not started.')}
            $State.Removed=$true;& $Save
            if(& $IsCancelled){return (& $Finish 'Cancelled' 'Application was removed; installation cancelled before it started.')}
            $Exec=& $RunStep $Definition.Downgrade 'Install' 'Exact'
            if(Test-RemoteOpsUnknownExecution $Exec){return (& $Finish 'Indeterminate' 'Application was removed; install was launched but its remote result is unknown. Check the target before retrying.')}
            if($Exec.ExecutionStatus -notlike 'Success*'){return (& $Finish 'Error' ('Application was removed but target installation failed: '+[string](Get-RemoteOpsPackageValue $Exec ErrorDetail '')))}
            $AfterInstall=& $Detect $Definition.Downgrade $ComputerName
            if($AfterInstall.Status -notin @('Var','Yok','CokluEslesme')){return (& $Finish 'Indeterminate' 'Application was removed and installation completed, but the target version cannot be read. Check the target before retrying.')}
            $State.FinalVersion=[string](Get-RemoteOpsPackageValue $AfterInstall DisplayVersion '')
            $Comparison=& $VersionComparer $State.FinalVersion $TargetVersion
            $Verified=$AfterInstall.Status -eq 'Var' -and $Comparison.Comparable -and $Comparison.Result -eq 0
            & $AddRow 'VerifyVersion' $(if($Verified){'Success'}else{'Failed'}) 'Exact target version checked using the install identity.'
            if(-not $Verified){
                if((Get-RemoteOpsPackageValue $Exec ExitCode) -in @(3010,1641)){return (& $Finish 'RebootRequired' 'Installation needs a reboot; exact target version was not yet verified.')}
                return (& $Finish 'Error' 'Application was removed; the installed target version could not be verified exactly.')
            }
            return (& $Finish 'Success' $(if((Get-RemoteOpsPackageValue $Exec ExitCode) -in @(3010,1641)){'Downgrade verified; a reboot is required.'}else{'Downgrade verified at the exact target version.'}))
        }
        $Part=$Definition.$Action;$Unchecked=$Part.CheckMode -eq 'Trigger without checks'
        if(-not $Unchecked){
            $Detected=& $Detect $Part $ComputerName;$State.PreviousVersion=[string](Get-RemoteOpsPackageValue $Detected DisplayVersion '')
            if($Detected.Status -notin @('Var','Yok')){return (& $Finish 'Error' (Get-RemoteOpsDetectionFailureDetail $Detected))}
            if($Action -eq 'Uninstall' -and $Detected.Status -eq 'Yok'){return (& $Finish 'Skipped' 'Application already absent.')}
            if($Action -eq 'Install' -and $Detected.Status -eq 'Var'){
                if($Part.CheckMode -eq 'Presence only'){return (& $Finish 'Skipped' 'Application already present.')}
                $Comparison=& $VersionComparer $State.PreviousVersion $Definition.TargetVersion
                if(-not $Comparison.Comparable){return (& $Finish 'Error' 'Installed version could not be compared.')}
                if($Comparison.Result -ge 0){return (& $Finish 'Skipped' 'Target or newer version already installed.')}
            }
        }
        & $ValidateSource $Part $ComputerName|Out-Null
        if(& $IsCancelled){return (& $Finish 'Cancelled' 'Cancelled before package execution.')}
        $Exec=& $RunStep $Part $Action 'AtLeast'
        if(Test-RemoteOpsUnknownExecution $Exec){return (& $Finish 'Indeterminate' 'Package was launched but its remote result is unknown. Check the target before retrying.')}
        if($Exec.ExecutionStatus -notlike 'Success*'){return (& $Finish 'Error' ([string](Get-RemoteOpsPackageValue $Exec ErrorDetail 'Package execution failed.')))}
        if($Unchecked){return (& $Finish 'Success' 'Package execution succeeded; application was not verified.')}
        $Detected=& $Detect $Part $ComputerName;$State.FinalVersion=[string](Get-RemoteOpsPackageValue $Detected DisplayVersion '')
        if($Detected.Status -notin @('Var','Yok','CokluEslesme')){return (& $Finish 'Indeterminate' 'Package completed, but the remote application state cannot be read. Check the target before retrying.')}
        $Verified=if($Action -eq 'Uninstall'){$Detected.Status -eq 'Yok'}else{$Detected.Status -eq 'Var'}
        if($Verified -and $Action -eq 'Install' -and $Part.CheckMode -eq 'Version controlled'){
            $Comparison=& $VersionComparer $State.FinalVersion $Definition.TargetVersion;$Verified=$Comparison.Comparable -and $Comparison.Result -ge 0
        }
        & $AddRow ('Verify'+$Action) $(if($Verified){'Success'}else{'Failed'}) 'Application state checked after execution.'
        if(-not $Verified){return (& $Finish $(if((Get-RemoteOpsPackageValue $Exec ExitCode) -in @(3010,1641)){'RebootRequired'}else{'Error'}) 'Package finished but application verification did not pass.')}
        return (& $Finish 'Success' $(if((Get-RemoteOpsPackageValue $Exec ExitCode) -in @(3010,1641)){'Application state verified; a reboot is required.'}else{'Application state verified.'}))
    }catch{
        $Outcome=if($State.SideEffectActive -or $State.VerificationPending){'Indeterminate'}else{'Error'}
        $Detail=$_.Exception.Message
        if($State.Removed){$Detail='Application was removed; '+$Detail}
        return (& $Finish $Outcome $Detail)
    }
}
