param([string]$OutputDirectory=(Join-Path (Split-Path -Parent $PSScriptRoot) 'screenshots-v24'))
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Sandbox=Join-Path $env:TEMP ('RemoteOps-v24-visual-'+[guid]::NewGuid().ToString('N'));$OldAppData=$env:APPDATA
try{
 New-Item -ItemType Directory -Path $Sandbox -Force|Out-Null;$env:APPDATA=$Sandbox
 $Source=[IO.File]::ReadAllText((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'))
 $Source=$Source.Replace('$script:AppRoot = Split-Path -Parent $PSCommandPath',('$script:AppRoot = '''+(Join-Path $Root 'RemoteOps.App')+''''))
 $Source=$Source.Replace('$script:DataRoot = ''C:\Temp\YD_RemoteOps.App''',('$script:DataRoot = '''+$Sandbox+''''))
 $Source=$Source.Replace('[void]$script:Window.ShowDialog()','')
 . ([scriptblock]::Create($Source));$script:OutputTimer.Stop()
 $Profile=[pscustomobject]@{Display='TEST\operator';Domain='TEST';UserName='operator';IsMain=$true;ProtectedPassword=''}
 $script:ProfileList.ItemsSource=@($Profile);$script:ProfileList.SelectedIndex=0;$script:ActiveIdentity.Text='TEST\operator (örnek veri)'
 $RunRoot=Join-Path $Sandbox 'Logs\Operations\PackageDeployment\GUI-20261015-135832-997816'
 New-Item -ItemType Directory $RunRoot -Force|Out-Null
 [pscustomobject]@{ComputerName='PC-IST-001';Status='Skipped';ErrorDetail='Target or newer version already installed.';OperationID='GUI-20261015-135832-997816'}|Export-Csv (Join-Path $RunRoot 'Results.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8
 Update-RemoteOpsHistoryView -Reload
 $script:HistoryControls.DiagRun.SelectedIndex=0
 if($script:HistoryControls.DiagRun.SelectedItem.DiagnosisLabel -notlike '*15.10.2026 13:58:32*'){throw 'UI label missing date'}
 New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
 function Save-WpfView($Visual,[string]$Name,[int]$Width=1280,[int]$Height=810,[int]$Dpi=96){
  $Visual.Measure((New-Object Windows.Size $Width,$Height));$Visual.Arrange((New-Object Windows.Rect 0,0,$Width,$Height));$Visual.UpdateLayout()
  $Scale=$Dpi/96.0;$Bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]($Width*$Scale)),([int]($Height*$Scale)),$Dpi,$Dpi,([Windows.Media.PixelFormats]::Pbgra32);$Bitmap.Render($Visual)
  $Encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$Encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($Bitmap));$Stream=[IO.File]::Create((Join-Path $OutputDirectory ($Name+'.png')));try{$Encoder.Save($Stream)}finally{$Stream.Dispose()}
 }
 $Content=$script:Window.Content;$Content.Background=$script:Window.Background
 $script:MainTabs.SelectedItem=$script:HistoryState.DiagnosticsTab
 Save-WpfView $Content 'hata-teshisi';Save-WpfView $Content 'hata-teshisi-125' 1060 700 120
 $TaskRoot=Join-Path $Sandbox 'ServiceTaskRollbacks';New-Item -ItemType Directory $TaskRoot -Force|Out-Null
 $TaskXml=Join-Path $TaskRoot 'task.xml';Write-RemoteOpsRecoveryTaskXml $TaskXml '<Task xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"><Actions/></Task>'
 [pscustomobject]@{ComputerName='PC-IST-001';ObjectType='ScheduledTask';ObjectName='OrnekGorev';TaskName='OrnekGorev';TaskPath='\';Action='Delete';OldEnabled='True';BackupXml=$TaskXml}|Export-Csv (Join-Path $TaskRoot 'example.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8
 $Record=@((Get-RemoteOpsRecoveryIndex $Sandbox).Records)[0];$Request=New-RemoteOpsRecoveryRequest $Sandbox $Record
 $Report=Join-Path $Sandbox 'Logs\Operations\ServiceTaskRollback\DEMO';New-Item -ItemType Directory $Report -Force|Out-Null
 Write-RemoteOpsRecoveryReceipt $Report $Request.Selection ([pscustomobject]@{Rows=@([pscustomobject]@{ComputerName='PC-IST-001';Status='Success'})}) 'DEMO'
 [pscustomobject]@{ComputerName='PC-IST-002';ObjectType='ScheduledTask';ObjectName='EksikYedek';TaskName='EksikYedek';TaskPath='\';Action='Delete';OldEnabled='True';BackupXml=(Join-Path $TaskRoot 'missing.xml')}|Export-Csv (Join-Path $TaskRoot 'missing.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8
 $script:MainTabs.SelectedItem=$script:RecoveryUi.Tab;Update-RemoteOpsRecoveryUi -Reload
 $script:RecoveryUi.Controls.List.SelectedItem=@($script:RecoveryUi.Controls.List.Items|Where-Object ComputerName -eq 'PC-IST-001')[0]
 Save-WpfView $Content 'geri-alma';Save-WpfView $Content 'geri-alma-125' 1060 700 120
 $script:RecoveryUi.Controls.List.SelectedItem=@($script:RecoveryUi.Controls.List.Items|Where-Object ComputerName -eq 'PC-IST-002')[0]
 Save-WpfView $Content 'geri-alma-eksik'
 foreach($Tab in @($script:MainTabs.Items)){
  $script:MainTabs.SelectedItem=$Tab
  Save-WpfView $Content ('ekran-'+$Tab.Name) 1280 810
 }
 $script:MainTabs.SelectedItem=$script:HistoryState.DiagnosticsTab
 Save-WpfView $Content 'dar-ekran-teshis' 960 550
 $script:MainTabs.SelectedItem=$script:RecoveryUi.Tab
 Save-WpfView $Content 'dar-ekran-geri-alma' 960 550
 $script:PackageControls.PackageTargets.Text='PC-IST-001,PC-IST-002;pc-ist-001'
 $script:MainTabs.SelectedItem=$script:PackagesTab
 Save-WpfView $Content 'ortak-hedefler' 1280 810
 $Editor=New-RemoteOpsTargetEditor $script:PackageGroupPicker
 $Editor.Window.Content.Background=$Editor.Window.Background
 Save-WpfView $Editor.Window.Content 'hedef-duzenle' 540 520
 $Editor.Window.Close()
 $Demo=[pscustomobject]@{ProgressPath=(Join-Path $Sandbox 'demo-progress');StartedAt=(Get-Date);Title='Örnek dağıtım';Targets=@('PC-IST-001','PC-IST-002','PC-IST-003');ProgressText=$null}
 [IO.File]::WriteAllText(($Demo.ProgressPath+'.reportroot'),$RunRoot)
 Set-RemoteOpsRunTargetRows $Demo @([pscustomobject]@{ComputerName='PC-IST-001';Outcome='Atlandı';OutcomeCode='Skipped';PackageName='Örnek paket';Step='Bitti'},[pscustomobject]@{ComputerName='PC-IST-002';Outcome='Hata';OutcomeCode='Error';PackageName='Örnek paket';Step='Bitti'},[pscustomobject]@{ComputerName='PC-IST-003';Outcome='Erişilemedi';OutcomeCode='Unreachable';PackageName='Örnek paket';Step='Bitti'})
 $script:SharedRuns.IsExpanded=$true
 $script:WorkflowUi.Outcome.SelectedValue='Error'
 Save-WpfView $Content 'sonuc-filtreleri' 1280 960
 Save-WpfView $Content 'sonuc-filtreleri-125' 1060 850 120
 $script:WorkflowUi.Reset.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
 $script:DeploymentTargets.SelectedItem=@($script:DeploymentTargets.Items|Where-Object ComputerName -eq 'PC-IST-001')[0]
 Open-RemoteOpsSelectedTargetDiagnosis
 Save-WpfView $Content 'sonuctan-teshise' 1280 960
 $script:SharedRuns.IsExpanded=$false
 $D=New-RemoteOpsRecipeDefinition 'Servis ve ayar kontrolü' 'Koşul uygunsa bağlı işlemleri çalıştır.'
 $D.Schema='RemoteOps.Recipe/2'
 $Gate=[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Ayar farklı ve servis durmuş';Operation='RecipeCondition';Values=[pscustomobject]@{Match='All';OnFalse='Skip';Checks=@([pscustomobject]@{Kind='RegistryValue';Path='HKLM\SOFTWARE\OrnekUygulama';Name='Mode';Operator='NotEquals';ExpectedType='REG_SZ';Expected='Enabled'},[pscustomobject]@{Kind='Service';Path='';Name='OrnekServis';Operator='State';ExpectedType='';Expected='Stopped'})}}
 $D.Steps=@($Gate,[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Ayarı güncelle';Operation='RegistryEdit';ConditionId=$Gate.Id;Values=@{RegistryPath='HKLM\SOFTWARE\OrnekUygulama';ValueName='Mode';ValueType='REG_SZ';Value='Enabled'}},[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Servisi başlat';Operation='ServiceControl';ConditionId=$Gate.Id;Values=@{ServiceName='OrnekServis';Action='Start'}})
 $script:RecipeUi.Draft=$D;Show-RemoteOpsRecipeDraft;Save-RemoteOpsRecipeEditor
 $script:MainTabs.SelectedItem=$script:RecipeUi.Tab;$script:RecipeUi.Controls.Steps.SelectedIndex=0
 Save-WpfView $Content 'recete-kosullari' 1280 960
 Save-WpfView $Content 'recete-kosullari-125' 1060 850 120
 $script:RecipeUi.Controls.EditorScroll.ScrollToVerticalOffset(330)
 Save-WpfView $Content 'recete-servis-kosulu' 1280 960
 $script:RecipeUi.Controls.Steps.SelectedIndex=1;$script:RecipeUi.Controls.EditorScroll.ScrollToTop()
 Save-WpfView $Content 'kosula-bagli-adim' 1280 900
 $Definition=Get-RemoteOpsRecipeEditorDefinition
 $Preview=New-RemoteOpsRecipePreviewWindow $Definition @('PC-IST-001','PC-IST-002')
 $Preview.Window.Content.Background=$Preview.Window.Background
 Save-WpfView $Preview.Window.Content 'kosul-onizlemesi' 780 650
 $Preview.Window.Close()
 Write-Output 'PASS: v24 diagnosis WPF fixture views at normal/125%; no Runner or remote operation launched.'
}finally{$env:APPDATA=$OldAppData;if($null -ne (Get-Variable OutputTimer -Scope Script -ErrorAction SilentlyContinue)){$script:OutputTimer.Stop()};if($null -ne (Get-Variable Window -Scope Script -ErrorAction SilentlyContinue)){$script:Window.Close()}}
