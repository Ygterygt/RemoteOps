$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot;$Temp=Join-Path $env:TEMP ('ROStartup-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path $Temp -Force|Out-Null
    Copy-Item (Join-Path $Root 'RemoteOps.App') (Join-Path $Temp 'RemoteOps.App') -Recurse
    Copy-Item (Join-Path $Root 'Modules') (Join-Path $Temp 'Modules') -Recurse
    $App=Join-Path $Temp 'RemoteOps.App\RemoteOps.App.ps1';$Text=Get-Content $App -Raw -Encoding UTF8
    $Text=$Text.Replace("'C:\Temp\YD_RemoteOps.App'","'$Temp\data'")
    $End=@'
if($script:Window.FindName('MainTabs').Items.Count -ne 9){throw 'Full app startup lost tabs.'}
if($null -eq $script:TargetGroupsUi.Tab -or $null -eq $script:Window.FindName('PreviewOperation')){throw 'Target groups or preview action missing.'}
if(@($script:MainTabs.Items|Where-Object Header -eq 'Geçmiş').Count -ne 1 -or @($script:MainTabs.Items|Where-Object Header -eq 'Hata Teşhisi').Count -ne 1){throw 'History/diagnostics tabs missing.'}
$script:MainTabs.SelectedItem=$script:HistoryUi.HistoryTab
if($null -eq $script:HistoryState.Index){throw 'History did not load on first tab entry.'}
$script:MainTabs.SelectedItem=$script:PackagesTab
if($script:MainTabs.SelectedItem -ne $script:PackagesTab){throw 'Full app did not start on Paketlerim.'}
if($script:ActiveRuns.Count -ne 0){throw 'Startup dispatched operations.'}
if(@($script:OperationPicker.Items|Where-Object Name -eq PackageDeployment).Count){throw 'Saved package deployment must not appear in the Operation selector.'}
if(@($script:OperationCatalog|Where-Object Name -eq PackageDeployment).Count -ne 1){throw 'Paketlerim deployment operation is missing internally.'}
Import-RemoteOpsPlugins
if(@($script:OperationPicker.Items|Where-Object Name -eq PackageDeployment).Count){throw 'Refresh restored hidden saved package operation.'}
$script:ToggleProfiles.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
if($script:ProfileOverlay.Visibility -ne 'Visible'){throw 'Profile editor does not open.'}
$script:CloseProfileEditor.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
if($script:ProfileOverlay.Visibility -ne 'Collapsed'){throw 'Profile editor does not close.'}
$script:PackageControls.PackageNew.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
if($script:MainTabs.SelectedItem -ne $script:PackageEditorTab){throw 'New package button does not open editor.'}
$script:SharedRuns.IsExpanded=$true
$First=[pscustomobject]@{ProgressPath='fixture-one';StartedAt=(Get-Date);Title='Fixture';TargetLabel='Fixture / Install';Targets=@('PC1');ProgressText=[pscustomobject]@{Parent=$null}}
$Second=$First|Select-Object *;$Second.ProgressPath='fixture-two'
Set-RemoteOpsRunTargetRows $First @([pscustomobject]@{ComputerName='PC1';Outcome='Success'})
Set-RemoteOpsRunTargetRows $Second @([pscustomobject]@{ComputerName='PC1';Outcome='Pending'})
if($script:RunPicker.SelectedValue -ne 'fixture-two' -or @($script:DeploymentTargets.ItemsSource).Count -ne 1){throw 'Actual window did not select the new run.'}
$script:RunPicker.SelectedValue='fixture-one'
if(@($script:DeploymentTargets.ItemsSource)[0].Outcome -ne 'Success'){throw 'Actual selector event did not switch rows.'}
$script:RunPicker.SelectedValue='*'
if($script:DeploymentTargets.Items.Groups.Count -ne 2){throw 'Actual window did not group runs.'}
$script:Window.Content.Measure((New-Object Windows.Size 1280,730));$script:Window.Content.Arrange((New-Object Windows.Rect 0,0,1280,730));$script:Window.Content.UpdateLayout()
$LogRun=$First|Select-Object *;$LogRun.ProgressPath=Join-Path $script:DataRoot 'log-fixture'
$LogReport=Join-Path $script:DataRoot 'Logs\Operations\PackageDeployment\LOG-RUN'
$LogTarget=Join-Path $script:DataRoot 'PulledLogs\LOG-RUN\PC1'
New-Item -ItemType Directory -Path $LogReport,$LogTarget -Force|Out-Null
Set-Content (Join-Path $LogTarget 'test.log') 'fixture'
[IO.File]::WriteAllText(($LogRun.ProgressPath+'.reportroot'),$LogReport)
Set-RemoteOpsRunTargetRows $LogRun @([pscustomobject]@{ComputerName='PC1';Outcome='Success';LogStatusRaw='Success'})
if(-not $script:OpenCollectedLogs.IsEnabled -or -not @($script:DeploymentTargets.ItemsSource)[0].CanOpenLogs){throw 'Actual log shortcuts not enabled for collected client.'}
$script:OpenedLog=''
function Open-RemoteOpsLogFolder {param([string]$Path)$script:OpenedLog=$Path}
$script:OpenCollectedLogs.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
if($script:OpenedLog -ne (Split-Path $LogTarget -Parent)){throw 'Run log button opened wrong folder.'}
$script:Window.Content.Measure((New-Object Windows.Size 1280,730));$script:Window.Content.Arrange((New-Object Windows.Rect 0,0,1280,730));$script:Window.Content.UpdateLayout()
function Find-LogButton($Visual){
    if($Visual -is [Windows.Controls.Button] -and [string]$Visual.Tag -eq $LogTarget){return $Visual}
    for($i=0;$i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($Visual);$i++){
        $Found=Find-LogButton ([Windows.Media.VisualTreeHelper]::GetChild($Visual,$i));if($Found){return $Found}
    }
}
$RowButton=Find-LogButton $script:DeploymentTargets
if(-not $RowButton){throw 'Client log button not rendered or path binding missing.'}
$RowButton.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
if($script:OpenedLog -ne $LogTarget){throw 'Client log routed button opened wrong folder.'}
$script:RunPicker.SelectedValue='*'
if($script:OpenCollectedLogs.IsEnabled){throw 'All runs offered an ambiguous log folder.'}
$PulledFolder=Join-Path $script:DataRoot 'PulledFiles\LOG-RUN\PC1';New-Item -ItemType Directory -Path $PulledFolder -Force|Out-Null
$PulledFile=Join-Path $PulledFolder 'report.txt';Set-Content $PulledFile 'owned fixture'
Set-RemoteOpsRunTargetRows $LogRun @([pscustomobject]@{ComputerName='PC1';Outcome='Success'})
$script:RunPicker.SelectedValue=$LogRun.ProgressPath
if(-not $script:OpenPulledFiles.IsEnabled -or -not @($script:DeploymentTargets.ItemsSource)[0].CanOpenPulled){throw 'Pulled-file shortcuts disabled despite collected file.'}
$script:ShownPull=''
function Show-RemoteOpsPulledFile {param([string]$Path)$script:ShownPull=$Path}
$script:OpenPulledFiles.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
if($script:ShownPull -ne (Split-Path $PulledFolder -Parent)){throw 'Run pull button opened another work folder.'}
$script:Window.Content.Measure((New-Object Windows.Size 1280,730));$script:Window.Content.Arrange((New-Object Windows.Rect 0,0,1280,730));$script:Window.Content.UpdateLayout()
function Find-PullButton($Visual){
 if($Visual -is [Windows.Controls.Button] -and $Visual.Uid -eq 'PulledFile' -and [string]$Visual.Tag -eq $PulledFile){return $Visual}
 for($i=0;$i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($Visual);$i++){$Found=Find-PullButton ([Windows.Media.VisualTreeHelper]::GetChild($Visual,$i));if($Found){return $Found}}
}
$PullButton=Find-PullButton $script:DeploymentTargets
if(-not $PullButton){throw 'Pulled-file row button is not bound/rendered.'}
$PullButton.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
if($script:ShownPull -ne $PulledFile){throw 'Pulled-file row routed to log handler or wrong file.'}
$script:OperationPicker.SelectedItem=@($script:OperationCatalog|Where-Object Name -eq FilePull)[0];Show-OperationFields
$Values=Get-OperationValues
if($Values.Path -or $Values.Targets){throw 'Examples must not prefill actual operation input.'}
$Hints=@($script:OperationFields.Children|ForEach-Object{$_.Children}|Where-Object{$_ -is [Windows.Controls.TextBlock]}|ForEach-Object{$_.Text}) -join ' '
if($Hints -notlike '*C:\Temp\Ornek*'){throw 'File example is not visible in actual operation form.'}
$script:OutputTimer.Stop();$script:Window.Close()
Write-Output 'PASS: full isolated app startup, event wiring, default package tab, profile overlay and new package button; no operations launched.'
'@
    if(-not $Text.Contains('[void]$script:Window.ShowDialog()')){throw 'Startup entry point changed.'}
    $Text=$Text.Replace('[void]$script:Window.ShowDialog()',$End)
    Set-Content $App $Text -Encoding UTF8
    $Wrapper=Join-Path $Temp 'start.ps1'
    Set-Content $Wrapper ("`$env:APPDATA='$Temp\profiles';`$ErrorActionPreference='Stop'; & '$App'") -Encoding UTF8
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -File $Wrapper
    if($LASTEXITCODE -ne 0){throw 'Full app startup failed.'}
}finally{if(Test-Path $Temp){Remove-Item $Temp -Recurse -Force}}
