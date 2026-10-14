# Durable target checkpoints shared by the coordinator and GUI recovery.
function Request-RemoteOpsRunCancellation {param([string]$Path)Write-RemoteOpsAtomicJson $Path ([PSCustomObject]@{Cancel=$true;RequestedAt=(Get-Date).ToString('o')})}
function Test-RemoteOpsRunCancellation {param([string]$Path)return (-not[string]::IsNullOrWhiteSpace($Path) -and [IO.File]::Exists($Path))}
function Write-RemoteOpsRunCheckpoint {
    param([string]$Root,$State)
    if([string]::IsNullOrWhiteSpace($Root)){return}
    $Hash=[Security.Cryptography.SHA256]::Create()
    try{$Bytes=$Hash.ComputeHash([Text.Encoding]::UTF8.GetBytes(([string]$State.ComputerName).Trim().ToLowerInvariant()))}finally{$Hash.Dispose()}
    $Name=([BitConverter]::ToString($Bytes)).Replace('-','').Substring(0,32)+'.target.json'
    Write-RemoteOpsAtomicJson (Join-Path $Root $Name) $State 16
}
function Get-RemoteOpsRunCheckpoints {
    param([string]$Root)
    if([string]::IsNullOrWhiteSpace($Root) -or -not(Test-Path -LiteralPath $Root)){return}
    foreach($File in @(Get-ChildItem -LiteralPath $Root -Filter '*.target.json' -File)){
        try{$State=Get-Content -LiteralPath $File.FullName -Raw -Encoding UTF8|ConvertFrom-Json;if(-not[string]::IsNullOrWhiteSpace([string]$State.ComputerName)){$State}}catch{ }
    }
}
function Write-RemoteOpsDeploymentTerminalCheckpoint {
    param([string]$Root,[object[]]$Rows,$Outcome,$Definition,[string]$Action,[string]$OperationID)
    $State=[PSCustomObject]@{ComputerName=$Outcome.ComputerName;OperationID=$OperationID;PackageName=$Definition.Name;PackageId=$Definition.Id;PackageRevision=$Definition.Revision;Action=$Action;Step='Result';Terminal=$true;SideEffectActive=$false;PreviousVersion=[string](Get-RemoteOpsPackageValue $Outcome PreviousVersion '');FinalVersion=[string](Get-RemoteOpsPackageValue $Outcome FinalVersion '');Rows=$Rows;Outcome=$Outcome;UpdatedAt=(Get-Date).ToString('o')}
    Write-RemoteOpsRunCheckpoint $Root $State
}
function Get-RemoteOpsPartialDeploymentResult {
    param([string[]]$Targets,[object[]]$Checkpoints,$Definition=$null,[string]$Action='',[string]$OperationID='',
        [ValidateSet('Cancelled','Error')][string]$MissingOutcome='Cancelled',[string]$MissingDetail='')
    $Rows=New-Object 'System.Collections.Generic.List[object]';$Outcomes=New-Object 'System.Collections.Generic.List[object]'
    foreach($Target in $Targets){
        $State=@($Checkpoints|Where-Object{
            $MatchesTarget=[string]::Equals([string]$_.ComputerName,$Target,[StringComparison]::OrdinalIgnoreCase)
            $StoredRun=[string](Get-RemoteOpsPackageValue $_ OperationID '')
            $MatchesRun=([string]::IsNullOrWhiteSpace($OperationID) -or $StoredRun -match ('^'+[regex]::Escape($OperationID)+'(?:-\d{4,})?$'))
            $StoredPackage=[string](Get-RemoteOpsPackageValue $_ PackageId '')
            $ExpectedPackage=[string](Get-RemoteOpsPackageValue $Definition Id '')
            $MatchesPackage=(-not $ExpectedPackage -or -not $StoredPackage -or $StoredPackage -eq $ExpectedPackage)
            $MatchesTarget -and $MatchesRun -and $MatchesPackage
        }|Sort-Object UpdatedAt -Descending|Select-Object -First 1)
        if($State.Count -gt 0 -and (Get-RemoteOpsPackageValue $State[0] Terminal $false) -eq $true -and $null -ne (Get-RemoteOpsPackageValue $State[0] Outcome)){
            foreach($Row in @($State[0].Rows)){$Rows.Add($Row)};$Outcomes.Add($State[0].Outcome);continue
        }
        $Outcome=if($State.Count -gt 0){'Indeterminate'}else{$MissingOutcome}
        $Detail=if($State.Count -gt 0){'Execution was interrupted; remote application state must be checked before retrying.'}elseif($MissingDetail){$MissingDetail}else{'Cancelled before this computer started.'}
        if($State.Count -gt 0){foreach($Row in @($State[0].Rows)){$Rows.Add($Row)}}
        $Rows.Add([PSCustomObject]@{ComputerName=$Target;Step='Result';Action=$Action;Status=$Outcome;ErrorDetail=$Detail;OperationID=$OperationID;PackageName=[string](Get-RemoteOpsPackageValue $Definition Name '');PackageId=[string](Get-RemoteOpsPackageValue $Definition Id '');PackageRevision=(Get-RemoteOpsPackageValue $Definition Revision 0)})
        $Outcomes.Add([PSCustomObject]@{ComputerName=$Target;Outcome=$Outcome;CompletedAt=(Get-Date);Detail=$Detail;PackageName=[string](Get-RemoteOpsPackageValue $Definition Name '');PackageId=[string](Get-RemoteOpsPackageValue $Definition Id '');PackageRevision=(Get-RemoteOpsPackageValue $Definition Revision 0);Action=$Action})
    }
    return [PSCustomObject]@{Rows=@($Rows.ToArray());Outcomes=@($Outcomes.ToArray())}
}
function Complete-RemoteOpsInterruptedDeployment {
    param([string]$BasePath,[string]$CheckpointRoot,[ValidateSet('Cancelled','Error')][string]$MissingOutcome='Cancelled')
    $MetaPath=Join-Path $CheckpointRoot 'run.json'
    if(-not(Test-Path -LiteralPath $MetaPath)){throw 'Coordinator metadata is not available; check the technical logs.'}
    $Meta=Get-Content -LiteralPath $MetaPath -Raw -Encoding UTF8|ConvertFrom-Json
    $Allowed=[IO.Path]::GetFullPath((Join-Path $BasePath 'Logs\Operations')).TrimEnd('\')+'\'
    if(-not[IO.Path]::GetFullPath([string]$Meta.ReportRoot).StartsWith($Allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Recovery report path is outside the operation directory.'}
    $MissingDetail=if($MissingOutcome -eq 'Error'){'Runner ended before this computer produced a terminal result.'}else{''}
    $Partial=Get-RemoteOpsPartialDeploymentResult @($Meta.Targets) @(Get-RemoteOpsRunCheckpoints $CheckpointRoot) $Meta.Definition ([string]$Meta.Action) ([string]$Meta.OperationID) -MissingOutcome $MissingOutcome -MissingDetail $MissingDetail
    foreach($Row in $Partial.Rows){Add-Member -InputObject $Row -NotePropertyName OperationID -NotePropertyValue ([string]$Meta.OperationID) -Force}
    $Result=[PSCustomObject]@{Completed=$true;Rows=$Partial.Rows;Outcomes=$Partial.Outcomes;ResultCsv=(Join-Path $Meta.ReportRoot 'Results.csv')}
    [void](Write-RemoteOpsLedger -BasePath $BasePath -OperationID $Meta.OperationID -Operation PackageDeployment -Category Applications -Identity $Meta.Identity -Outcomes $Partial.Outcomes)
    Complete-RemoteOpsReports -Result $Result -Title ($Meta.Definition.Name+' / '+$Meta.Action+' / partial') -OperationID $Meta.OperationID -ReportRoot $Meta.ReportRoot -Messages @([PSCustomObject]@{Message='Execution interrupted; report rebuilt from durable checkpoints.'})
    return $Result
}
