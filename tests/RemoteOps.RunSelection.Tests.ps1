$ErrorActionPreference='Stop';Set-StrictMode -Version 2
Add-Type -AssemblyName PresentationFramework
$Root=Split-Path -Parent $PSScriptRoot
$t=$null;$e=$null;$Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'),[ref]$t,[ref]$e)
foreach($Name in 'T','Get-OptionalPropertyValue','Set-RemoteOpsRunTargetRows','Update-RemoteOpsRunSelection','Get-RemoteOpsSelectedReport'){
 $f=$Ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name},$true)
 if($f){. ([scriptblock]::Create($f.Extent.Text))}
}
$script:DeploymentTargets=New-Object Windows.Controls.DataGrid
$script:RunPicker=New-Object Windows.Controls.ComboBox
$script:RunPicker.DisplayMemberPath='Label';$script:RunPicker.SelectedValuePath='Id'
$script:SelectedRunSummary=New-Object Windows.Controls.TextBlock
$script:OpenRunReport=New-Object Windows.Controls.Button
$one=[pscustomobject]@{ProgressPath='one';StartedAt=[datetime]'2026-10-14T14:32:00';Title='A / Install';TargetLabel='A / Install';Stage='Completed';CheckpointRoot='';ProgressText=[pscustomobject]@{Parent=$null}}
$two=[pscustomobject]@{ProgressPath='two';StartedAt=[datetime]'2026-10-14T14:33:00';Title='B / Install';TargetLabel='B / Install';Stage='Running';CheckpointRoot='';ProgressText=[pscustomobject]@{Parent=$null}}
$a=[pscustomobject]@{ComputerName='PC1';Outcome='Success'};$b=[pscustomobject]@{ComputerName='PC1';Outcome='Pending'}
foreach($Run in @($one,$two)){Add-Member -InputObject $Run -NotePropertyName Targets -NotePropertyValue @('PC1')}
Set-RemoteOpsRunTargetRows $one @($a)
Set-RemoteOpsRunTargetRows $two @($b)
if(@($script:DeploymentTargets.ItemsSource).Count -ne 1){throw 'New run must show only its own targets.'}
if($script:RunPicker.SelectedValue -ne 'two'){throw 'Newest run not selected.'}
$script:RunPicker.SelectedValue='one';Update-RemoteOpsRunSelection
Set-RemoteOpsRunTargetRows $two @($b)
if($script:RunPicker.SelectedValue -ne 'one' -or @($script:DeploymentTargets.ItemsSource)[0].Outcome -ne 'Success'){throw 'Background update changed selection.'}
$script:RunPicker.SelectedValue='*';Update-RemoteOpsRunSelection
if(@($script:DeploymentTargets.ItemsSource).Count -ne 2 -or $script:DeploymentTargets.Items.Groups.Count -ne 2){throw 'All runs must retain repeated computers in separate groups.'}
if($script:OpenRunReport.IsEnabled){throw 'All runs must not open an arbitrary report.'}
$Temp=Join-Path $env:TEMP ('RunSelection-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path $Temp|Out-Null
    $script:DataRoot=$Temp
    foreach($Run in @($one,$two)){
        $Folder=Join-Path $Temp ('Logs\Operations\PackageDeployment\'+$Run.ProgressPath)
        New-Item -ItemType Directory -Path $Folder -Force|Out-Null
        Set-Content (Join-Path $Folder 'Results.html') '<html>fixture</html>'
        $Reference=Join-Path $Temp ($Run.ProgressPath+'.reportroot')
        [IO.File]::WriteAllText($Reference,$Folder)
        $OldId=$Run.ProgressPath
        # Keep dictionary identity unchanged; sidecar resolution uses the run object path.
        $Run.ProgressPath=Join-Path $Temp $OldId
    }
    $script:RunPicker.SelectedValue='one';Update-RemoteOpsRunSelection
    if(-not $script:OpenRunReport.IsEnabled -or (Get-RemoteOpsSelectedReport) -notlike '*\one\Results.html'){throw 'First run report mismatch.'}
    $script:RunPicker.SelectedValue='two';Update-RemoteOpsRunSelection
    if((Get-RemoteOpsSelectedReport) -notlike '*\two\Results.html'){throw 'Second run opened another report.'}
    [IO.File]::WriteAllText(($two.ProgressPath+'.reportroot'),$Temp)
    if(Get-RemoteOpsSelectedReport){throw 'Report outside operation directory accepted.'}
}finally{if(Test-Path $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force}}
Write-Output 'PASS: latest default, previous selection preserved, duplicate targets isolated and all-run grouping.'
