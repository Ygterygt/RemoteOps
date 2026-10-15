$ErrorActionPreference='Stop'
$Root=Split-Path $PSScriptRoot -Parent
$Temp=Join-Path $env:TEMP ('RecoveryUI_'+[guid]::NewGuid().ToString('N'));$OldAppData=$env:APPDATA;$script:OutputTimer=$null;$script:Window=$null
function Assert($C,$M){if(-not $C){throw $M}}
function Click($Button){$Button.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))}
try{
 New-Item -ItemType Directory $Temp -Force|Out-Null;$env:APPDATA=Join-Path $Temp 'profiles'
 $Source=[IO.File]::ReadAllText((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'))
 $Source=$Source.Replace('$script:AppRoot = Split-Path -Parent $PSCommandPath',('$script:AppRoot = '''+(Join-Path $Root 'RemoteOps.App')+''''))
 $Source=$Source.Replace('$script:DataRoot = ''C:\Temp\YD_RemoteOps.App''',('$script:DataRoot = '''+$Temp+'\data'''))
 $Source=$Source.Replace('[void]$script:Window.ShowDialog()','')
 . ([scriptblock]::Create($Source));$script:OutputTimer.Stop()
 Assert ($script:MainTabs.Items.Count -eq 9) 'Missing recovery tab'
 Update-RemoteOpsRecoveryUi -Reload;Assert ($script:RecoveryUi.Controls.List.Items.Count -eq 0 -and -not $script:RecoveryUi.Controls.Preview.IsEnabled) 'Empty list actionable'
 $P=[pscustomobject]@{Display='TEST\operator';Domain='TEST';UserName='operator';IsMain=$true;ProtectedPassword='fixture'};$script:ProfileList.ItemsSource=@($P);$script:ProfileList.SelectedIndex=0
 $Dir=Join-Path $script:DataRoot 'RegistryRollback';New-Item -ItemType Directory $Dir -Force|Out-Null
 $Manifest=Join-Path $Dir 'test.csv'
 [pscustomobject]@{ComputerName='PC1';RegistryKey='Software\Example';ValueName='Mode';OldExists='True';OldValue='old';NewValue='new'}|Export-Csv $Manifest -Delimiter ';' -NoTypeInformation
 $script:Dispatch=@();function Start-RemoteOpsRequest {param($Operation,$Values)$script:Dispatch+=,[pscustomobject]@{Operation=$Operation;Values=$Values}}
 Update-RemoteOpsRecoveryUi -Reload
 $C=$script:RecoveryUi.Controls;Assert ($C.List.Items.Count -eq 1) 'Refresh failed'
 $C.Computer.Text='*';Assert ($C.List.Items.Count -eq 0 -and -not $C.Preview.IsEnabled) 'UI literal filter/empty action failed';$C.Computer.Text=''
 $C.List.SelectedIndex=0;$Record=$C.List.SelectedItem
 Update-RemoteOpsRecoveryUi -Reload;Assert ($C.List.SelectedItem.Id -eq $Record.Id) 'Refresh lost stable selection'
 $State=New-RemoteOpsRecoveryPreviewWindow $Record;$State.Controls.Confirm.Text='ROLLBACK';$script:SettingCleanupLogs.IsChecked=$true;Click $State.Controls.Start;Assert ($script:Dispatch.Count -eq 0 -and $State.Controls.Error.Text) 'Changed settings accepted';$script:SettingCleanupLogs.IsChecked=$false;$State.Window.Close()
 $State=New-RemoteOpsRecoveryPreviewWindow $Record;Assert ($State.Controls.Text.Text -match 'old' -and $State.Controls.Text.Text -match 'PC1') 'Missing precise scope'
 Click $State.Controls.Cancel;Assert ($script:Dispatch.Count -eq 0) 'Cancel dispatched'
 $State=New-RemoteOpsRecoveryPreviewWindow $Record;Click $State.Controls.Start;Assert ($script:Dispatch.Count -eq 0 -and $State.Controls.Error.Text) 'Missing typed approval accepted';$State.Window.Close()
 $State=New-RemoteOpsRecoveryPreviewWindow $Record;$State.Controls.Confirm.Text='ROLLBACK';$P.Domain='CHANGED';Click $State.Controls.Start;Assert ($script:Dispatch.Count -eq 0) 'Changed identity accepted';$P.Domain='TEST';$State.Window.Close()
 $State=New-RemoteOpsRecoveryPreviewWindow $Record;$State.Controls.Confirm.Text='ROLLBACK';$C.List.SelectedItem=$null;Click $State.Controls.Start;Assert ($script:Dispatch.Count -eq 0) 'Lost selection accepted';$State.Window.Close();$C.List.SelectedIndex=0
 $State=New-RemoteOpsRecoveryPreviewWindow $Record;$State.Controls.Confirm.Text='ROLLBACK';Click $State.Controls.Start;Click $State.Controls.Start
 Assert ($script:Dispatch.Count -eq 1 -and $script:Dispatch[0].Values.Targets -eq 'PC1') 'Dispatch not exactly once'
 $State=New-RemoteOpsRecoveryPreviewWindow $Record;$State.Controls.Confirm.Text='ROLLBACK';Add-Content $Manifest 'changed';Click $State.Controls.Start;Assert ($script:Dispatch.Count -eq 1 -and $State.Controls.Error.Text) 'Stale selection accepted';$State.Window.Close()
 $Bad=Join-Path $Dir 'bad.csv';[pscustomobject]@{ComputerName='PC-BAD';RegistryKey='Software\Example';ValueName='Mode';OldExists='True'}|Export-Csv $Bad -Delimiter ';' -NoTypeInformation
 Update-RemoteOpsRecoveryUi -Reload;$C.List.SelectedItem=@($C.List.Items|Where-Object ComputerName -eq PC-BAD)[0];Assert (-not $C.Preview.IsEnabled -and $C.Details.Text) 'Unavailable record actionable'
 Write-Host 'PASS Recovery WPF list, scope, cancel, approval, identity, stale and once-only dispatch'
}finally{if($script:OutputTimer){$script:OutputTimer.Stop()};if($script:Window){$script:Window.Close()};$env:APPDATA=$OldAppData;if(Test-Path $Temp){Remove-Item $Temp -Recurse -Force}}
