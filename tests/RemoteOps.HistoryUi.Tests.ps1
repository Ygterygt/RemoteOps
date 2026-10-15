param([string]$PreviewDirectory='')
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
Add-Type -AssemblyName PresentationFramework
$Root=Split-Path $PSScriptRoot -Parent
foreach($Name in @('Reports','History','Diagnostics','HistoryUi')){$File=Join-Path $Root ('RemoteOps.App\RemoteOps.'+$Name+'.ps1');if(Test-Path $File){. $File}}
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
function Click($Button){$Button.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))}
$Sandbox=Join-Path $env:TEMP ('RemoteOpsHistoryUI-'+[guid]::NewGuid().ToString('N'))
$Window=New-Object Windows.Window
try{
 $Tabs=New-Object Windows.Controls.TabControl;$Window.Content=$Tabs
 $Ui=Initialize-RemoteOpsHistoryUi $Tabs $Sandbox
 $C=$Ui.Controls
 & $Ui.Refresh
 Assert ($C.Runs.Items.Count -eq 0 -and -not $C.OpenArtifact.IsEnabled) 'Empty view must not enable output'
 foreach($Case in @(@('RUN-1','Error',50010),@('RUN-2','Success',0))){
  $Folder=Join-Path $Sandbox ('Logs\Operations\PackageDeployment\'+$Case[0]);New-Item -ItemType Directory -Path $Folder -Force|Out-Null
  @([pscustomobject]@{ComputerName='PC-I';Step='Install';Status=$Case[1];ExitCode=$Case[2];ErrorDetail='Fixture only';OperationID=$Case[0]})|Export-Csv (Join-Path $Folder 'Results.csv') -Delimiter ';' -NoTypeInformation
  [void](Write-RemoteOpsLedger -BasePath $Sandbox -OperationID $Case[0] -Operation PackageDeployment -Outcomes @([pscustomobject]@{ComputerName='PC-I';Outcome=$Case[1];CompletedAt=[datetime]'2026-10-15T12:00:00'}))
 }
 & $Ui.Refresh
 Assert ($C.Runs.Items.Count -eq 2) 'Refresh lost actual runs'
 $C.Runs.SelectedItem=@($C.Runs.Items|Where-Object OperationID -eq 'RUN-1')[0]
 Assert ($C.Targets.Items.Count -eq 1) 'Selection did not load target'
 $C.Targets.SelectedIndex=0
 Assert (-not $C.OpenLogs.IsEnabled -and -not $C.OpenPulled.IsEnabled) 'Missing target collections enabled'
 Click $C.Diagnose
 Assert ($Tabs.SelectedItem -eq $Ui.DiagnosticsTab -and $C.Diagnosis.Text -match '50010') 'Wrong run/target diagnosis'
 $Tabs.SelectedItem=$Ui.HistoryTab
 & $Ui.Refresh
 Assert ($C.Runs.SelectedItem.OperationID -eq 'RUN-1') 'Refresh lost selected identity'
 $C.Computer.Text='PC-*';Click $C.Apply
 Assert ($C.Runs.Items.Count -eq 0 -and -not $C.OpenArtifact.IsEnabled -and -not $C.Diagnose.IsEnabled) 'Filter leaked stale actions'
 $C.Computer.Text='';Click $C.Apply
 $C.Runs.SelectedItem=@($C.Runs.Items|Where-Object OperationID -eq 'RUN-2')[0];$C.Targets.SelectedIndex=0;Click $C.Diagnose
 Assert ($C.Diagnosis.Text -notmatch '50010' -and $C.Diagnosis.Text -match 'Success') 'Diagnosis leaked another run'
 $C.DiagRun.SelectedItem=@($C.DiagRun.Items|Where-Object OperationID -eq 'RUN-1')[0];$C.DiagTarget.SelectedIndex=0
 if($PreviewDirectory){
  New-Item -ItemType Directory -Path $PreviewDirectory -Force|Out-Null
  foreach($Pair in @(@($Ui.HistoryTab,'gecmis'),@($Ui.DiagnosticsTab,'hata-teshisi'))){
   $Tabs.SelectedItem=$Pair[0];$Tabs.Measure((New-Object Windows.Size 1000,540));$Tabs.Arrange((New-Object Windows.Rect 0,0,1000,540));$Tabs.UpdateLayout()
   $Bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap 1250,675,120,120,([Windows.Media.PixelFormats]::Pbgra32);$Bitmap.Render($Tabs)
   $Encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$Encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($Bitmap));$Stream=[IO.File]::Create((Join-Path $PreviewDirectory ($Pair[1]+'.png')));try{$Encoder.Save($Stream)}finally{$Stream.Dispose()}
  }
 }
 Write-Output 'PASS: real WPF empty/refresh/filter/selection events, diagnosis navigation, target isolation, disabled missing outputs.'
}finally{$Window.Close();if(Test-Path $Sandbox){Remove-Item -LiteralPath $Sandbox -Recurse -Force}}
