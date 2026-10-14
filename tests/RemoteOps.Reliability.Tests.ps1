$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Packages.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.RunState.ps1')
$Failures=New-Object 'System.Collections.Generic.List[string]'
function Check([string]$Name,[scriptblock]$Test){try{& $Test;Write-Output "PASS: $Name"}catch{$Failures.Add($Name+': '+$_.Exception.Message);Write-Output "FAIL: $Name"}}
$Temp=Join-Path $env:TEMP ('RemoteOpsReliability-'+[guid]::NewGuid().ToString('N'))
try{
    $P=New-RemoteOpsPackageDefinition 'Example';$P.Install.Enabled=$true;$P.Install.PackagePath='\\server\share';$P.Install.PackageFile='install.cmd';$P.Install.Application='Example';$P.TargetVersion='2.0'
    Check 'Malformed JSON string fields rejected' {
        foreach($Field in @('Name','ApplicationKey','Category','Description','TargetVersion')){
            $Bad=Copy-RemoteOpsPackageDefinition $P;$Bad.$Field=@('A','B')
            if((Test-RemoteOpsPackageDefinition $Bad).Valid){throw "Array accepted for $Field"}
        }
        $Bad=Copy-RemoteOpsPackageDefinition $P;$Bad.Install.Application=[PSCustomObject]@{Name='bad'}
        if((Test-RemoteOpsPackageDefinition $Bad).Valid){throw 'Object accepted for action text'}
        $Bad=Copy-RemoteOpsPackageDefinition $P;$Bad.Name=@('A','B')
        $ImportPath=Join-Path $Temp 'invalid-import.json';Write-RemoteOpsAtomicJson $ImportPath ([PSCustomObject]@{Schema='RemoteOps.PackageExport/1';Packages=@($Bad)})
        $Rejected=$false;try{Get-RemoteOpsPackageImportPreview (Join-Path $Temp 'import-target') $ImportPath|Out-Null}catch{$Rejected=$true}
        if(-not $Rejected -or (Test-Path -LiteralPath (Join-Path $Temp 'import-target'))){throw 'Invalid import was not rejected before catalog mutation'}
    }
    Check 'Serialized completion date survives ledger/recovery' {
        $DateText='2025-03-04T05:06:07.0000000+03:00'
        $Path=Write-RemoteOpsLedger -BasePath $Temp -OperationID DATE -Operation PackageDeployment -Outcomes @([PSCustomObject]@{ComputerName='PC1';Outcome='Success';CompletedAt=$DateText})
        $Stored=@(Import-Csv $Path -Delimiter ';')[0]
        if($Stored.CompletedAt -ne '2025-03-04 05:06:07'){throw ('Serialized date replaced: '+$Stored.CompletedAt)}
    }
    Check 'Locked rollback manifest preserves previous backup atomically' {
        function Register-AOModule{param($Name,$Version,$MinimumHostApiVersion,$SourcePath,$Initializer)}
        function Register-AOModuleOperation{param($ModuleName,$Name,$DisplayName,$EntryPointName,$Handler)}
        . (Join-Path $Root 'Modules\RegistryOperations.ps1')
        . (Join-Path $Root 'Modules\ServiceTaskOperations.ps1')
        foreach($Writer in @('Write-RegistryOperationsManifest','Write-ServiceTaskManifest')){
            $Path=Join-Path $Temp ($Writer+'.csv')
            & $Writer -Path $Path -Rows @([PSCustomObject]@{ComputerName='PC1';OldValue='ORIGINAL'})
            $Before=[IO.File]::ReadAllText($Path)
            $Held=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            try{
                $Rejected=$false;try{& $Writer -Path $Path -Rows @([PSCustomObject]@{ComputerName='PC2';OldValue='NEW'})}catch{$Rejected=$true}
                if(-not $Rejected -or [IO.File]::ReadAllText($Path) -cne $Before){throw 'Locked replacement lost an existing rollback record'}
            }finally{$Held.Dispose()}
            if(@(Get-ChildItem -LiteralPath $Temp -Filter '*.tmp' -File).Count){throw 'Failed rollback replacement leaked a temporary file'}
        }
    }
    Check 'Stale checkpoint cannot become new success' {
        $Old=[PSCustomObject]@{ComputerName='PC1';OperationID='OLD';PackageId='OLD-PACKAGE';Terminal=$true;Rows=@([PSCustomObject]@{ComputerName='PC1';Step='Result';Status='Success'});Outcome=[PSCustomObject]@{ComputerName='PC1';Outcome='Success'};UpdatedAt=(Get-Date).ToString('o')}
        $Result=Get-RemoteOpsPartialDeploymentResult @('PC1') @($Old) $P Install NEW -MissingOutcome Error
        if($Result.Outcomes[0].Outcome -ne 'Error'){throw 'Old Success reused by new operation'}
        $Active=[PSCustomObject]@{ComputerName='PC1';OperationID='NEW-10000';PackageId=$P.Id;Terminal=$false;Rows=@();UpdatedAt=(Get-Date).ToString('o')}
        $Child=Get-RemoteOpsPartialDeploymentResult @('PC1') @($Active) $P Install NEW -MissingOutcome Error
        if($Child.Outcomes[0].Outcome -ne 'Indeterminate'){throw 'A five-digit target index was incorrectly rejected as another operation'}
    }
    Check 'Deleting main never promotes another credential identity' {
        $T=$null;$E=$null;$Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'),[ref]$T,[ref]$E)
        $Handler=$Ast.Find({param($N)$N -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $N.Expression.Extent.Text -eq '$script:RemoveProfile' -and $N.Member.Value -eq 'Add_Click'},$true)
        $Code=$Handler.Arguments[0].ScriptBlock.Extent.Text;$Code=$Code.Substring(1,$Code.Length-2)
        $Code=(@($Code -split "`r?`n"|Where-Object{$_ -notmatch '\[System.Windows.MessageBox\]::Show'}) -join "`n")
        $Main=[PSCustomObject]@{Domain='D';UserName='current';IsMain=$true;Display='current'}
        $Other=[PSCustomObject]@{Domain='D';UserName='admin';IsMain=$false;Display='admin'}
        $script:Profiles=New-Object Collections.ArrayList;[void]$script:Profiles.Add($Main);[void]$script:Profiles.Add($Other)
        $script:ProfileList=[PSCustomObject]@{SelectedItem=$Main}
        function Save-ProfileStore{};function Refresh-ProfileList{};function Write-AppLog{param($Message)}
        & ([scriptblock]::Create($Code))
        if($script:Profiles.Count -ne 1 -or $Other.IsMain){throw 'Credential account silently promoted to current-token Main'}
    }
    Check 'Unexpected deployment exit ends live target states honestly' {
        Add-Type -AssemblyName PresentationFramework
        . (Join-Path $Root 'RemoteOps.App\RemoteOps.PackageUi.ps1')
        $T=$null;$E=$null;$Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'),[ref]$T,[ref]$E)
        foreach($Name in @('T','Get-OptionalPropertyValue','Read-TargetProgress','Set-RemoteOpsRunTargetRows','Update-RunProgress')){
            $F=$Ast.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq $Name},$true)
            . ([scriptblock]::Create($F.Extent.Text))
        }
        Write-RemoteOpsRunCheckpoint $Temp ([PSCustomObject]@{ComputerName='PC1';OperationID='FAILRUN';PackageName=$P.Name;Step='Install';Terminal=$false;Rows=@();UpdatedAt=(Get-Date).ToString('o')})
        $script:DeploymentTargets=[PSCustomObject]@{ItemsSource=@()}
        $Run=[PSCustomObject]@{CheckpointRoot=$Temp;ProgressPath='failed-run';Targets=@('PC1','PC2');Title=$P.Name;Stage='Failed';Stopped=$false;CancelRequested=$false;FinalSummary='';Total=2;Completed=0;CurrentTarget='';StartedAt=(Get-Date);ProgressText=[PSCustomObject]@{Text=''};ProgressBar=[PSCustomObject]@{Foreground=$null;Value=0};Process=[PSCustomObject]@{HasExited=$true}}
        Update-RemoteOpsDeploymentRunView $Run
        $Items=@($script:DeploymentTargets.ItemsSource)
        if($Items[0].Outcome -ne $script:RemoteOpsOutcomeTitles.Indeterminate -or $Items[1].Outcome -ne $script:RemoteOpsOutcomeTitles.Error){throw 'Failed deployment targets still appear running/pending instead of unknown/error'}
        $Run.FinalSummary='OLD SUMMARY';Update-RunProgress $Run
        if($Run.ProgressText.Text -match 'OLD SUMMARY' -or $Run.ProgressText.Text -notmatch [regex]::Escape($Run.FinalSummary)){throw 'Final progress text still displays stale success/error counts'}
    }
}finally{if(Test-Path -LiteralPath $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force}}
if($Failures.Count){throw ($Failures -join "`n")}
