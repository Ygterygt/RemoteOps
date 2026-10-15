param([string]$OutputDirectory=(Join-Path (Split-Path -Parent $PSScriptRoot) 'screenshots-v18'))
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Sandbox=Join-Path $env:TEMP ('RemoteOps-v18-visual-'+[guid]::NewGuid().ToString('N'));$OldAppData=$env:APPDATA
try{
 New-Item -ItemType Directory -Path $Sandbox -Force|Out-Null;$env:APPDATA=$Sandbox
 $Source=[IO.File]::ReadAllText((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'))
 $Source=$Source.Replace('$script:AppRoot = Split-Path -Parent $PSCommandPath',('$script:AppRoot = '''+(Join-Path $Root 'RemoteOps.App')+''''))
 $Source=$Source.Replace('$script:DataRoot = ''C:\Temp\YD_RemoteOps.App''',('$script:DataRoot = '''+$Sandbox+''''))
 $Source=$Source.Replace('[void]$script:Window.ShowDialog()','')
 . ([scriptblock]::Create($Source));$script:OutputTimer.Stop()
 $Profile=[pscustomobject]@{Display='TEST\operator';Domain='TEST';UserName='operator';IsMain=$true;ProtectedPassword=''}
 $script:ProfileList.ItemsSource=@($Profile);$script:ProfileList.SelectedIndex=0;$script:ActiveIdentity.Text='TEST\operator (örnek veri)'
 $D=New-RemoteOpsRecipeDefinition 'Örnek ayar güncellemesi' 'Servisi durdur, dosyayı gönder, servisi başlat. Gerçek hedef değildir.'
 $D.Steps=@([pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Servisi durdur';Operation='ServiceControl';Values=@{ServiceName='OrnekServis';Action='Stop'}},[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Ayar dosyasını gönder';Operation='FilePush';Values=@{LocalPath='C:\Temp\Ornek\ayarlar.json';Path='C:\ProgramData\Ornek';Overwrite=$true}},[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Servisi başlat';Operation='ServiceControl';Values=@{ServiceName='OrnekServis';Action='Start'}})
 $Saved=Save-RemoteOpsRecipeDefinition $script:RecipeUi.Root $D 0;Update-RemoteOpsRecipeUi -Reload;Open-RemoteOpsRecipeEditor $Saved
 $script:RecipeUi.Controls.Targets.Text='PC-IST-001 PC-IST-002'
 New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
 function Save-WpfView($Visual,[string]$Name,[int]$Width=1280,[int]$Height=810,[int]$Dpi=96){
  $Visual.Measure((New-Object Windows.Size $Width,$Height));$Visual.Arrange((New-Object Windows.Rect 0,0,$Width,$Height));$Visual.UpdateLayout()
  $Scale=$Dpi/96.0;$Bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]($Width*$Scale)),([int]($Height*$Scale)),$Dpi,$Dpi,([Windows.Media.PixelFormats]::Pbgra32);$Bitmap.Render($Visual)
  $Encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$Encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($Bitmap));$Stream=[IO.File]::Create((Join-Path $OutputDirectory ($Name+'.png')));try{$Encoder.Save($Stream)}finally{$Stream.Dispose()}
 }
 $Content=$script:Window.Content;$Content.Background=$script:Window.Background
 $script:MainTabs.SelectedItem=$script:RecipeUi.Tab;$script:RecipeUi.Controls.Steps.SelectedIndex=1
 Save-WpfView $Content 'operasyon-receteleri';Save-WpfView $Content 'operasyon-receteleri-125' 1060 570 120
 $script:RecipeUi.Controls.EditorScroll.ScrollToEnd();Save-WpfView $Content 'recete-calistirma';Save-WpfView $Content 'recete-calistirma-125' 1060 570 120
 $Preview=New-RemoteOpsRecipePreviewWindow (Get-RemoteOpsRecipeEditorDefinition) @('PC-IST-001','PC-IST-002');$Preview.Window.Content.Background=$Preview.Window.Background
 Save-WpfView $Preview.Window.Content 'recete-onizleme' 740 610 96;Save-WpfView $Preview.Window.Content 'recete-onizleme-125' 640 480 120;$Preview.Window.Close()
 Write-Output 'PASS: v18 real WPF fixture views at normal/125%; no Runner or remote operation launched.'
}finally{$env:APPDATA=$OldAppData;if($null -ne (Get-Variable OutputTimer -Scope Script -ErrorAction SilentlyContinue)){$script:OutputTimer.Stop()};if($null -ne (Get-Variable Window -Scope Script -ErrorAction SilentlyContinue)){$script:Window.Close()};if(Test-Path $Sandbox){Remove-Item -LiteralPath $Sandbox -Recurse -Force}}
