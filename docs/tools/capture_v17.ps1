param([string]$OutputDirectory=(Join-Path (Split-Path -Parent $PSScriptRoot) 'screenshots-v17'))
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Sandbox=Join-Path $env:TEMP ('RemoteOps-v17-visual-'+[guid]::NewGuid().ToString('N'));$OldAppData=$env:APPDATA
try{
 New-Item -ItemType Directory -Path $Sandbox -Force|Out-Null;$env:APPDATA=$Sandbox
 $Source=[IO.File]::ReadAllText((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'))
 $Source=$Source.Replace('$script:AppRoot = Split-Path -Parent $PSCommandPath',('$script:AppRoot = '''+(Join-Path $Root 'RemoteOps.App')+''''))
 $Source=$Source.Replace('$script:DataRoot = ''C:\Temp\YD_RemoteOps.App''',('$script:DataRoot = '''+$Sandbox+''''))
 $Source=$Source.Replace('[void]$script:Window.ShowDialog()','')
 . ([scriptblock]::Create($Source));$script:OutputTimer.Stop()
 $Profile=[pscustomobject]@{Display='TEST\operator';Domain='TEST';UserName='operator';IsMain=$true;ProtectedPassword=''}
 $script:ProfileList.ItemsSource=@($Profile);$script:ProfileList.SelectedIndex=0;$script:ActiveIdentity.Text='TEST\operator (örnek veri)'
 $Dir=Join-Path $Sandbox 'RegistryRollback';New-Item -ItemType Directory $Dir -Force|Out-Null
 @([pscustomobject]@{ComputerName='PC-IST-001';RegistryKey='Software\Ornek';ValueName='Sunucu';OldExists='True';OldType='REG_SZ';OldValue='eski.ornek.local';NewValue='yeni.ornek.local'},[pscustomobject]@{ComputerName='PC-IST-002';RegistryKey='Software\Ornek';ValueName='Sunucu';OldExists='True';OldType='REG_SZ';OldValue='eski.ornek.local';NewValue='yeni.ornek.local'})|Export-Csv (Join-Path $Dir '20261015_Ornek.csv') -Delimiter ';' -NoTypeInformation
 $Dir=Join-Path $Sandbox 'DeleteBackups\20261015_Delete';New-Item -ItemType Directory $Dir -Force|Out-Null
 [pscustomobject]@{ComputerName='PC-IST-003';OriginalPath='C:\Ornek\ayarlar.json';BackupPath=(Join-Path $Dir 'eksik.json');ItemType='File';BackupStatus='Success'}|Export-Csv (Join-Path $Dir 'manifest.csv') -Delimiter ';' -NoTypeInformation
 New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
 function Save-WpfView($Visual,[string]$Name,[int]$Width=1280,[int]$Height=810,[int]$Dpi=96){
  $Visual.Measure((New-Object Windows.Size $Width,$Height));$Visual.Arrange((New-Object Windows.Rect 0,0,$Width,$Height));$Visual.UpdateLayout()
  $Scale=$Dpi/96.0;$Bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]($Width*$Scale)),([int]($Height*$Scale)),$Dpi,$Dpi,([Windows.Media.PixelFormats]::Pbgra32);$Bitmap.Render($Visual)
  $Encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$Encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($Bitmap));$Stream=[IO.File]::Create((Join-Path $OutputDirectory ($Name+'.png')));try{$Encoder.Save($Stream)}finally{$Stream.Dispose()}
 }
 $Content=$script:Window.Content;$Content.Background=$script:Window.Background
 $script:MainTabs.SelectedItem=$script:RecoveryUi.Tab;Update-RemoteOpsRecoveryUi -Reload
 $C=$script:RecoveryUi.Controls;$C.List.SelectedItem=@($C.List.Items|Where-Object ComputerName -eq PC-IST-001)[0]
 Save-WpfView $Content 'geri-alma-merkezi';Save-WpfView $Content 'geri-alma-merkezi-125' 1060 570 120
 $Preview=New-RemoteOpsRecoveryPreviewWindow $C.List.SelectedItem;$Preview.Window.Content.Background=$Preview.Window.Background
 Save-WpfView $Preview.Window.Content 'geri-alma-onizleme' 740 610 96;Save-WpfView $Preview.Window.Content 'geri-alma-onizleme-125' 640 480 120;$Preview.Window.Close()
 $C.List.SelectedItem=@($C.List.Items|Where-Object ComputerName -eq PC-IST-003)[0];Save-WpfView $Content 'eksik-yedek'
 Write-Output 'PASS: v17 real WPF fixture views at normal/125%; no Runner or remote operation launched.'
}finally{$env:APPDATA=$OldAppData;if($null -ne (Get-Variable OutputTimer -Scope Script -ErrorAction SilentlyContinue)){$script:OutputTimer.Stop()};if($null -ne (Get-Variable Window -Scope Script -ErrorAction SilentlyContinue)){$script:Window.Close()};if(Test-Path $Sandbox){Remove-Item -LiteralPath $Sandbox -Recurse -Force}}
