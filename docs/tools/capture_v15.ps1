param([string]$OutputDirectory=(Join-Path (Split-Path -Parent $PSScriptRoot) 'screenshots-v15'))
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Sandbox=Join-Path $env:TEMP ('RemoteOps-v15-visual-'+[guid]::NewGuid().ToString('N'))
$OldAppData=$env:APPDATA
try{
 New-Item -ItemType Directory -Path $Sandbox -Force|Out-Null;$env:APPDATA=$Sandbox
 $Source=[IO.File]::ReadAllText((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'))
 $Source=$Source.Replace('$script:AppRoot = Split-Path -Parent $PSCommandPath',('$script:AppRoot = '''+(Join-Path $Root 'RemoteOps.App')+''''))
 $Source=$Source.Replace('$script:DataRoot = ''C:\Temp\YD_RemoteOps.App''',('$script:DataRoot = '''+$Sandbox+''''))
 $Source=$Source.Replace('[void]$script:Window.ShowDialog()','')
 . ([scriptblock]::Create($Source));$script:OutputTimer.Stop()
 $script:ActiveIdentity.Text='TEST\operator (örnek veri)'
 $Rows=@(
 [pscustomobject]@{ComputerName='PC-TEST-001';Step='Install';Status='Success';ExitCode=0;ErrorDetail='';OperationID='GUI-20261015-140000-DEMO';PreviousVersion='2.0';TargetVersion='3.0';FinalVersion='3.0';PackageId='DEMO';PackageRevision=1},
 [pscustomobject]@{ComputerName='PC-TEST-002';Step='Install';Status='Failed';ExitCode=50010;ErrorDetail='Paket hata kodu döndürdü; neden loglarla incelenmeli. Örnek kayıttır.';OperationID='GUI-20261015-140000-DEMO';PreviousVersion='2.0';TargetVersion='3.0';FinalVersion='';PackageId='DEMO';PackageRevision=1})
 $Folder=Join-Path $Sandbox 'Logs\Operations\PackageDeployment\GUI-20261015-140000-DEMO';New-Item -ItemType Directory -Path $Folder -Force|Out-Null
 $Rows|Export-Csv (Join-Path $Folder 'Results.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8
 'Example log, no company data.'|Set-Content (Join-Path $Folder 'RemoteOps.log')
 [void](Write-RemoteOpsLedger -BasePath $Sandbox -OperationID GUI-20261015-140000-DEMO -Operation PackageDeployment -Identity 'TEST\operator' -Outcomes @(
 [pscustomobject]@{ComputerName='PC-TEST-001';Outcome='Success';CompletedAt=[datetime]'2026-10-15T14:00:00';PackageName='Örnek uygulama 3.0'},
 [pscustomobject]@{ComputerName='PC-TEST-002';Outcome='Error';CompletedAt=[datetime]'2026-10-15T14:00:00';PackageName='Örnek uygulama 3.0'}))
 & $script:HistoryUi.Refresh;$C=$script:HistoryUi.Controls;$C.Runs.SelectedIndex=0;$C.Targets.SelectedIndex=1
 New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
 foreach($Kind in @('gecmis','hata-teshisi')){
  if($Kind -eq 'gecmis'){$script:MainTabs.SelectedItem=$script:HistoryUi.HistoryTab}else{$C.Diagnose.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))}
  # Normal documentation view; a second capture exercises the smaller 125% viewport.
  $Content=$script:Window.Content;$Content.Background=$script:Window.Background
  $Content.Measure((New-Object Windows.Size 1280,810));$Content.Arrange((New-Object Windows.Rect 0,0,1280,810));$Content.UpdateLayout()
  $Bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap 1280,810,96,96,([Windows.Media.PixelFormats]::Pbgra32);$Bitmap.Render($Content)
  $Encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$Encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($Bitmap));$Stream=[IO.File]::Create((Join-Path $OutputDirectory ($Kind+'.png')));try{$Encoder.Save($Stream)}finally{$Stream.Dispose()}
 }
 $script:MainTabs.SelectedItem=$script:HistoryUi.HistoryTab
 $Content.Measure((New-Object Windows.Size 1060,570));$Content.Arrange((New-Object Windows.Rect 0,0,1060,570));$Content.UpdateLayout()
 $C.HistoryScroll.ScrollToEnd();$Content.UpdateLayout()
 if($C.HistoryScroll.ScrollableHeight -le 0 -or $C.HistoryScroll.VerticalOffset -le 0){throw 'Small viewport must allow reaching the target details.'}
 $Bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap 1325,713,120,120,([Windows.Media.PixelFormats]::Pbgra32);$Bitmap.Render($Content)
 $Encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$Encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($Bitmap));$Stream=[IO.File]::Create((Join-Path $OutputDirectory 'gecmis-125-alt.png'));try{$Encoder.Save($Stream)}finally{$Stream.Dispose()}
 Write-Output 'PASS: full app WPF renders at 125% with fixture data; no remote calls.'
}finally{if($null -ne (Get-Variable OutputTimer -Scope Script -ErrorAction SilentlyContinue)){$script:OutputTimer.Stop()};$env:APPDATA=$OldAppData;if(Test-Path $Sandbox){Remove-Item -LiteralPath $Sandbox -Recurse -Force}}
