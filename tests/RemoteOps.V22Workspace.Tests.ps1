$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework
$Root=Split-Path $PSScriptRoot -Parent
$Sandbox=Join-Path $env:TEMP ('RemoteOpsV22-'+[guid]::NewGuid().ToString('N'));$PreviousAppData=$env:APPDATA
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
try{
 $env:APPDATA=$Sandbox
 $Source=[IO.File]::ReadAllText((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'))
 $Source=$Source.Replace('$script:AppRoot = Split-Path -Parent $PSCommandPath',('$script:AppRoot = '''+(Join-Path $Root 'RemoteOps.App')+''''))
 $Source=$Source.Replace('$script:DataRoot = ''C:\Temp\YD_RemoteOps.App''',('$script:DataRoot = '''+$Sandbox+'\data'''))
 $Source=$Source.Replace('[void]$script:Window.ShowDialog()','')
 . ([scriptblock]::Create($Source));$script:OutputTimer.Stop()
 Assert ($null -ne $script:WorkspaceNavigation) 'Grouped workspace navigation is missing'
 Assert ($script:WorkspaceNavigation.Buttons.Count -eq 9) 'Navigation lost existing screens'
 foreach($Entry in $script:WorkspaceNavigation.Buttons){
  $Entry.Button.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
  Assert ($script:MainTabs.SelectedItem -eq $Entry.Tab) 'Navigation selected the wrong screen'
 }
 $script:MainTabs.SelectedItem=$script:PackageEditorTab
 Assert ($script:WorkspaceNavigation.Current.Text -eq 'Paket Oluştur') 'Programmatic navigation did not synchronize'
 Assert ($script:Window.Title -match ('v'+(Get-Content (Join-Path $Root 'VERSION.json') -Raw|ConvertFrom-Json).version)) 'Window does not identify the delivery'
 Assert ($script:HistoryControls.DiagReason.Text -and $script:HistoryControls.DiagNextAction.Text) 'Empty diagnosis cards are missing'
 Assert ($script:RecoveryUi.Controls.RecoveryCards.Visibility -eq 'Collapsed') 'Empty recovery selection shows stale status cards'
 $RunRoot=Join-Path $Sandbox 'data\Logs\Operations\PackageDeployment\GUI-20261015-135832-997816'
 New-Item -ItemType Directory $RunRoot -Force|Out-Null
 [pscustomobject]@{ComputerName='PC-DEMO';Status='Skipped';ErrorDetail='Target or newer version already installed.';OperationID='GUI-20261015-135832-997816'}|Export-Csv (Join-Path $RunRoot 'Results.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8
 Update-RemoteOpsHistoryView -Reload
 $script:HistoryControls.DiagRun.SelectedIndex=0
 Assert ($script:HistoryControls.DiagReason.Text -match 'sürüm' -and $script:HistoryControls.DiagOutcome.Text -eq 'Atlandı') 'Diagnosis cards do not reflect selected evidence'
 $script:HistoryControls.DiagRun.SelectedItem=$null
 Assert ($script:HistoryControls.DiagReason.Text -notmatch 'sürüm' -and $script:HistoryControls.DiagOutcome.Text -eq 'Sonuç özeti') 'Cleared diagnosis retains previous evidence'
 $TaskRoot=Join-Path $Sandbox 'data\ServiceTaskRollbacks';New-Item -ItemType Directory $TaskRoot -Force|Out-Null
 $TaskXml=Join-Path $TaskRoot 'task.xml';Write-RemoteOpsRecoveryTaskXml $TaskXml '<Task xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"><Actions/></Task>'
 [pscustomobject]@{ComputerName='PC-DEMO';ObjectType='ScheduledTask';ObjectName='DemoTask';TaskName='DemoTask';TaskPath='\';Action='Delete';OldEnabled='True';BackupXml=$TaskXml}|Export-Csv (Join-Path $TaskRoot 'demo.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8
 Update-RemoteOpsRecoveryUi -Reload;$script:RecoveryUi.Controls.List.SelectedIndex=0
 Assert ($script:RecoveryUi.Controls.RecoveryCards.Visibility -eq 'Visible' -and $script:RecoveryUi.Controls.RecoveryLive.Text -match 'sorgulanmadı') 'Recovery cards confuse recorded and live state'
 $script:RecoveryUi.Controls.List.SelectedItem=$null
 Assert ($script:RecoveryUi.Controls.RecoveryCards.Visibility -eq 'Collapsed' -and -not $script:RecoveryUi.Controls.RecoveryLocal.Text -and -not $script:RecoveryUi.Controls.Preview.IsEnabled) 'Cleared recovery selection retains actionable state'
 $script:RecoveryUi.Controls.List.SelectedIndex=0
 function Get-RemoteOpsRecoveryIndex {throw 'Fixture: index read failed'}
 Update-RemoteOpsRecoveryUi -Reload
 Assert ($script:RecoveryUi.Controls.RecoveryCards.Visibility -eq 'Collapsed' -and -not $script:RecoveryUi.Controls.RecoveryLocal.Text -and -not $script:RecoveryUi.Controls.Preview.IsEnabled) 'Failed reload retains previous recovery status'
 Assert ($script:ActiveRuns.Count -eq 0) 'Navigation dispatched an operation'
 Write-Output 'PASS: all nine navigation destinations, programmatic synchronization, version, empty cards and no dispatch'
}finally{
 $env:APPDATA=$PreviousAppData
 if(Get-Variable OutputTimer -Scope Script -ErrorAction SilentlyContinue){$script:OutputTimer.Stop()}
 if(Get-Variable Window -Scope Script -ErrorAction SilentlyContinue){$script:Window.Close()}
}
