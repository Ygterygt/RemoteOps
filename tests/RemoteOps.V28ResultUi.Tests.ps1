param([string]$PreviewDirectory='')
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
Add-Type -AssemblyName PresentationFramework
$Root=Split-Path $PSScriptRoot -Parent
foreach($N in @('Reports','History','Diagnostics','HistoryUi')){. (Join-Path $Root ('RemoteOps.App\RemoteOps.'+$N+'.ps1'))}
function Assert($V,$M){if(-not $V){throw $M}}
$Sandbox=Join-Path $env:TEMP ('RemoteOpsV28Ui-'+[guid]::NewGuid().ToString('N'))
$W=New-Object Windows.Window
try{
 $Tabs=New-Object Windows.Controls.TabControl;$W.Content=$Tabs;$W.Width=1200;$W.Height=760
 $AppSource=[IO.File]::ReadAllText((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'))
 $Match=[regex]::Match($AppSource,'(?s)\$script:WindowXaml = @''\r?\n(.*?)\r?\n''@')
 Assert $Match.Success 'App visual resources not found'
 $StyleWindow=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader ([xml]$Match.Groups[1].Value)))
 $StyleWindow.Resources.Remove([type][Windows.Controls.TabControl]);$StyleWindow.Resources.Remove([type][Windows.Controls.TabItem])
 $W.Resources=$StyleWindow.Resources;$W.FontFamily='Segoe UI';$W.FontSize=13;$Tabs.Resources=$W.Resources;$Tabs.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#EDF1F5')
 $Ui=Initialize-RemoteOpsHistoryUi $Tabs $Sandbox;$C=$Ui.Controls
 $Id='GUI-20261016-101010-ABCDEF';$Folder=Join-Path $Sandbox ('Logs\Operations\RecipeRun\'+$Id)
 New-Item -ItemType Directory -Path $Folder -Force|Out-Null
 $Rows=@(
 [pscustomobject]@{ComputerName='SIM-PC1';OperationID=$Id;StepIndex=1;StepName='Demo servisini durdur';Operation='ServiceControl';Status='Success';CommandStatus='Success';VerificationStatus='Verified';VerificationExpected='OfflineDemo · Durmuş';VerificationObserved='State=Stopped; Startup=Automatic';VerificationDetail='Hedef tekrar okundu; servis durmuş durumda.';VerifiedAt='2026-10-16T10:10:10Z'},
 [pscustomobject]@{ComputerName='SIM-PC1';OperationID=$Id;StepIndex=2;StepName='Yapılandırma dosyasını gönder';Operation='FilePush';Status='Success';CommandStatus='Success';VerificationStatus='Failed';VerificationExpected='Kaynak ve hedef SHA256 aynı olmalı.';VerificationObserved='config.json · İçerik farklı';VerificationDetail='Komut kabul edildi ancak hedef dosya içeriği farklı. Önceki adımda servis durduruldu; otomatik geri alma yapılmadı.';VerifiedAt='2026-10-16T10:10:12Z'},
 [pscustomobject]@{ComputerName='SIM-PC1';OperationID=$Id;StepIndex=3;StepName='Demo servisini başlat';Operation='ServiceControl';Status='NotRun';ErrorDetail='Önceki adım doğrulanamadığı için çalıştırılmadı.'}
 )
 $Headers=@($Rows|ForEach-Object{$_.PSObject.Properties.Name}|Select-Object -Unique)
 $Rows|Select-Object $Headers|Export-Csv (Join-Path $Folder 'Results.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8
 [void](Write-RemoteOpsLedger -BasePath $Sandbox -OperationID $Id -Operation RecipeRun -Outcomes @([pscustomobject]@{ComputerName='SIM-PC1';Outcome='Error';CompletedAt=(Get-Date);Detail='Dosya içeriği beklenenden farklı.'}))
 & $Ui.Refresh;$C.Runs.SelectedIndex=0;$C.Targets.SelectedIndex=0
 Assert ($C.Steps.Columns.Count -eq 4 -and $C.Steps.Items.Count -eq 3 -and -not $C.Steps.AutoGenerateColumns) 'Friendly grid not shown for recipe'
 $C.Steps.SelectedIndex=1
 Assert ($C.Steps.Tag.Text -like '*İçerik farklı*' -and $C.Steps.Tag.Text -like '*SHA256*') 'Selected detail missing expectation/observation'
 $Tabs.SelectedItem=$Ui.HistoryTab;$W.ShowActivated=$false;$W.Left=-20000;$W.Top=-20000;$W.Show();$W.UpdateLayout()
 $Tabs.Measure((New-Object Windows.Size 1200,720));$Tabs.Arrange((New-Object Windows.Rect 0,0,1200,720));$Tabs.UpdateLayout()
 Assert ($C.Steps.Columns[1].ActualWidth -ge 190) 'Step name column collapsed'
 Assert ($C.Steps.ActualHeight -ge 70) ('Step grid clipped by detail panel: '+$C.Steps.ActualHeight)
 if($PreviewDirectory){
  New-Item -ItemType Directory -Path $PreviewDirectory -Force|Out-Null
  $Bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap 1500,900,120,120,([Windows.Media.PixelFormats]::Pbgra32);$Bitmap.Render($Tabs)
  $Encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$Encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($Bitmap));$Stream=[IO.File]::Create((Join-Path $PreviewDirectory 'v28-adim-sonuclari.png'));try{$Encoder.Save($Stream)}finally{$Stream.Dispose()}
 }
 $StyleWindow.Close()
 Write-Output 'PASS actual WPF history selection, readable columns, selected expected/observed detail and visible grid'
}finally{$W.Close()}
