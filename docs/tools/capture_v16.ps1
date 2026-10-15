param([string]$OutputDirectory=(Join-Path (Split-Path -Parent $PSScriptRoot) 'screenshots-v16'))
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Sandbox=Join-Path $env:TEMP ('RemoteOps-v16-visual-'+[guid]::NewGuid().ToString('N'));$OldAppData=$env:APPDATA
try{
 New-Item -ItemType Directory -Path $Sandbox -Force|Out-Null;$env:APPDATA=$Sandbox
 $Source=[IO.File]::ReadAllText((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'))
 $Source=$Source.Replace('$script:AppRoot = Split-Path -Parent $PSCommandPath',('$script:AppRoot = '''+(Join-Path $Root 'RemoteOps.App')+''''))
 $Source=$Source.Replace('$script:DataRoot = ''C:\Temp\YD_RemoteOps.App''',('$script:DataRoot = '''+$Sandbox+''''))
 $Source=$Source.Replace('[void]$script:Window.ShowDialog()','')
 . ([scriptblock]::Create($Source));$script:OutputTimer.Stop()
 $Profile=[pscustomobject]@{Display='TEST\operator';Domain='TEST';UserName='operator';IsMain=$true;ProtectedPassword=''}
 $script:ProfileList.ItemsSource=@($Profile);$script:ProfileList.SelectedIndex=0;$script:ActiveIdentity.Text='TEST\operator (örnek veri)'
 $C=$script:TargetGroupsUi.Controls;$C.Name.Text='İstanbul Pilot';$C.Description.Text='İlk uygulama için ayrılmış örnek bilgisayarlar. Gerçek hedef değildir.';$C.Targets.Text="PC-IST-001`r`nPC-IST-002`r`nPC-IST-003";Save-RemoteOpsTargetGroupEditor
 New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
 function Save-WpfView($Visual,[string]$Name,[int]$Width=1280,[int]$Height=810,[int]$Dpi=96){
  $Visual.Measure((New-Object Windows.Size $Width,$Height));$Visual.Arrange((New-Object Windows.Rect 0,0,$Width,$Height));$Visual.UpdateLayout()
  $Scale=$Dpi/96.0;$Bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]($Width*$Scale)),([int]($Height*$Scale)),$Dpi,$Dpi,([Windows.Media.PixelFormats]::Pbgra32);$Bitmap.Render($Visual)
  $Encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$Encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($Bitmap));$Stream=[IO.File]::Create((Join-Path $OutputDirectory ($Name+'.png')));try{$Encoder.Save($Stream)}finally{$Stream.Dispose()}
 }
 $Content=$script:Window.Content;$Content.Background=$script:Window.Background
 $script:MainTabs.SelectedItem=$script:TargetGroupsUi.Tab
 Save-WpfView $Content 'hedef-gruplari';Save-WpfView $Content 'hedef-gruplari-125' 1060 570 120
 $script:MainTabs.SelectedItem=$script:OperationTab;$script:OperationPicker.SelectedItem=@($script:OperationCatalog|Where-Object Name -eq FilePush)[0];Show-OperationFields
 foreach($Row in $script:OperationFields.Children){foreach($Input in $Row.Children){switch([string]$Input.Tag){LocalPath{$Input.Text='C:\Temp\Ornek\ayarlar.json'} Path{$Input.Text='C:\ProgramData\Ornek'} Overwrite{$Input.IsChecked=$true}}}}
 Update-RemoteOpsTargetGroupPicker $script:OperationGroupPicker;$script:OperationGroupPicker.Picker.SelectedIndex=0;Set-RemoteOpsTargetGroupPickerTargets $script:OperationGroupPicker Add
 Save-WpfView $Content 'operasyon-grup';Save-WpfView $Content 'operasyon-grup-125' 1060 570 120
 $Preview=New-RemoteOpsOperationPreviewWindow $script:OperationPicker.SelectedItem (Get-OperationValues)
 $Preview.Window.Content.Background=$Preview.Window.Background
 Save-WpfView $Preview.Window.Content 'onizleme' 720 520 96;Save-WpfView $Preview.Window.Content 'onizleme-125' 640 430 120;$Preview.Window.Close()
 $P=New-RemoteOpsPackageDefinition 'Örnek uygulama';$P.TargetVersion='3.0';$P.Install.Enabled=$true;$P.Install.PackagePath='\\server\packages\Ornek';$P.Install.PackageFile='install.cmd';$P.Install.Application='Örnek uygulama';$P.Install.CheckMode='Version controlled'
 $Saved=Save-RemoteOpsPackageDefinition $script:PackageCatalogRoot $P 0;Update-RemoteOpsPackageList;$script:PackageControls.PackageList.SelectedItem=@($script:PackageControls.PackageList.Items|Where-Object Id -eq $Saved.Id)[0]
 Update-RemoteOpsTargetGroupPicker $script:PackageGroupPicker;$script:PackageGroupPicker.Picker.SelectedIndex=0;Set-RemoteOpsTargetGroupPickerTargets $script:PackageGroupPicker Add
 $script:MainTabs.SelectedItem=$script:PackagesTab;Save-WpfView $Content 'paket-grup';Save-WpfView $Content 'paket-grup-125' 1060 570 120
 Show-RemoteOpsPackageRunSummaryFromSelection Install;Save-WpfView $Content 'paket-onizleme';Save-WpfView $Content 'paket-onizleme-125' 1060 570 120
 Write-Output 'PASS: v16 real WPF fixture views at normal/125%; no Runner or remote operation launched.'
}finally{$env:APPDATA=$OldAppData;if($null -ne (Get-Variable OutputTimer -Scope Script -ErrorAction SilentlyContinue)){$script:OutputTimer.Stop()};if($null -ne (Get-Variable Window -Scope Script -ErrorAction SilentlyContinue)){$script:Window.Close()};if(Test-Path $Sandbox){Remove-Item -LiteralPath $Sandbox -Recurse -Force}}
