$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework
$Root=Split-Path $PSScriptRoot -Parent
$Sandbox=Join-Path $env:TEMP ('RemoteOpsV23-'+[guid]::NewGuid().ToString('N'));$PreviousAppData=$env:APPDATA
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
function Click($Button){$Button.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))}
try{
 $env:APPDATA=$Sandbox
 $Source=[IO.File]::ReadAllText((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'))
 $Source=$Source.Replace('$script:AppRoot = Split-Path -Parent $PSCommandPath',('$script:AppRoot = '''+(Join-Path $Root 'RemoteOps.App')+''''))
 $Source=$Source.Replace('$script:DataRoot = ''C:\Temp\YD_RemoteOps.App''',('$script:DataRoot = '''+$Sandbox+'\data'''))
 $Source=$Source.Replace('[void]$script:Window.ShowDialog()','')
 . ([scriptblock]::Create($Source));$script:OutputTimer.Stop()
 $P=$script:PackageGroupPicker;$P.TargetBox.Text='PC1,pc1;PC2'
 Assert ($P.Summary.Text -match '2' -and $P.Summary.Text -match '1 tekrar') 'Target count and duplicate hint missing'
 Click $P.Normalize;Assert ($P.TargetBox.Text -eq "PC1`r`nPC2") 'Normalize did not preserve first occurrence'
 $W=New-RemoteOpsTargetEditor $P;$W.Controls.List.SelectedIndex=0;Click $W.Controls.Remove
 Click $W.Controls.Apply;Assert ($P.TargetBox.Text -eq 'PC2') 'Target removal not applied'
 $W=New-RemoteOpsTargetEditor $P;$P.TargetBox.Text='PC3';Click $W.Controls.Apply
 Assert ($P.TargetBox.Text -eq 'PC3' -and $W.Controls.Error.Text) 'Stale target editor overwrote changed targets';$W.Window.Close()
 $P.TargetBox.Text='bad*';Click $P.Normalize;Assert ($P.TargetBox.Text -eq 'bad*' -and $P.Message.Text) 'Invalid input was silently accepted'
 Assert ($null -ne $script:RecipeUi.GroupPicker.Summary -and $null -ne $script:OperationGroupPicker.Summary) 'Shared picker missing on recipe/operation'
 $script:OperationGroupPicker.TargetBox.Text='PC-OP'
 Assert ((Get-OperationValues).Targets -eq 'PC-OP') 'Target tools broke operation field identity'
 $Run=[pscustomobject]@{ProgressPath=(Join-Path $Sandbox 'fixture');StartedAt=(Get-Date);Title='Fixture';Targets=@('PC1','PC2','PC3');ProgressText=$null}
 Set-RemoteOpsRunTargetRows $Run @([pscustomobject]@{ComputerName='PC1';Outcome='Hata';OutcomeCode='Error'},[pscustomobject]@{ComputerName='PC2';Outcome='Başarılı';OutcomeCode='Success'},[pscustomobject]@{ComputerName='PC3';Outcome='Belirsiz';OutcomeCode='Indeterminate'})
 $F=$script:WorkflowUi;$F.Outcome.SelectedValue='Error'
 Assert (@($script:DeploymentTargets.ItemsSource).Count -eq 1 -and @($script:RunTargetRows[$Run.ProgressPath]).Count -eq 3) ('Filter lost source results: shown='+@($script:DeploymentTargets.ItemsSource).Count+' raw='+@($script:RunTargetRows[$Run.ProgressPath]).Count+' selected='+$F.Outcome.SelectedValue+' search='+$F.Search.Text)
 $F.Search.Text='PC2';Assert (@($script:DeploymentTargets.ItemsSource).Count -eq 0) 'Combined filters incorrect'
 Click $F.Reset;Assert (@($script:DeploymentTargets.ItemsSource).Count -eq 3) 'Reset failed'
 $F.Outcome.SelectedValue='Indeterminate';Assert (@($script:DeploymentTargets.ItemsSource).Count -eq 1) 'Indeterminate filter incorrect'
 Click $F.Reset
 $script:DeploymentTargets.SelectedIndex=0
 $Refresh=@([pscustomobject]@{ComputerName='PC1';Outcome='Hata';OutcomeCode='Error'},[pscustomobject]@{ComputerName='PC2';Outcome='Başarılı';OutcomeCode='Success'},[pscustomobject]@{ComputerName='PC3';Outcome='Belirsiz';OutcomeCode='Indeterminate'})
 Set-RemoteOpsRunTargetRows $Run $Refresh
 Assert ($null -ne $script:DeploymentTargets.SelectedItem -and $script:DeploymentTargets.SelectedItem.ComputerName -eq 'PC1') 'Progress refresh lost selected target'
 $script:DeploymentTargets.SelectedIndex=0;Open-RemoteOpsSelectedTargetDiagnosis
 Assert ($F.Message.Text -and $script:MainTabs.SelectedItem -ne $script:HistoryUi.DiagnosticsTab) 'Missing report opened unrelated diagnosis'
 $ReportRoot=Join-Path $script:DataRoot 'Logs\Operations\PackageDeployment\GUI-20261015-135832-997816'
 New-Item -ItemType Directory $ReportRoot -Force|Out-Null
 @([pscustomobject]@{ComputerName='PC1';Status='Error';ErrorDetail='Fixture only';OperationID='GUI-20261015-135832-997816'},[pscustomobject]@{ComputerName='PC2';Status='Success';ErrorDetail='';OperationID='GUI-20261015-135832-997816'})|Export-Csv (Join-Path $ReportRoot 'Results.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8
 [IO.File]::WriteAllText(($Run.ProgressPath+'.reportroot'),$ReportRoot)
 Open-RemoteOpsSelectedTargetDiagnosis
 Assert ($script:MainTabs.SelectedItem -eq $script:HistoryUi.DiagnosticsTab -and $script:HistoryControls.DiagTarget.SelectedItem.ComputerName -eq 'PC1') 'Diagnosis selected wrong run or target'
 $script:HistoryControls.Runs.SelectedItem=@($script:HistoryControls.Runs.Items|Where-Object OperationID -eq 'GUI-20261015-135832-997816')[0]
 $script:WorkflowHistory.Outcome.SelectedValue='Success'
 Assert ($script:HistoryControls.Targets.Items.Count -eq 1 -and $script:HistoryControls.Targets.Items[0].ComputerName -eq 'PC2') 'History target filter is incorrect'
 $script:WorkflowHistory.Search.Text='missing'
 Assert ($script:HistoryControls.Targets.Items.Count -eq 0 -and -not $script:HistoryControls.Diagnose.IsEnabled) 'Empty target filter retained stale action'
 $script:HistoryControls.Computer.Text='stale';Open-RemoteOpsComputerRecovery 'PC1'
 Assert ($script:RecoveryUi.Controls.Computer.Text -eq 'PC1' -and $script:MainTabs.SelectedItem -eq $script:RecoveryUi.Tab) 'Computer recovery transition incorrect'
 Assert ($script:ActiveRuns.Count -eq 0) 'Workflow dispatched remote operation'
 Write-Output 'PASS v23: shared targets, deduplication, remove, stale editor, invalid input, combined filters, reset, safe navigation and no dispatch'
}finally{
 $env:APPDATA=$PreviousAppData
 if(Get-Variable OutputTimer -Scope Script -ErrorAction SilentlyContinue){$script:OutputTimer.Stop()}
 if(Get-Variable Window -Scope Script -ErrorAction SilentlyContinue){$script:Window.Close()}
}
