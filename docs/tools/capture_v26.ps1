param([string]$OutputDirectory=(Join-Path (Split-Path -Parent $PSScriptRoot) 'screenshots-v26'))
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Sandbox=Join-Path $env:TEMP ('RemoteOps-v26-visual-'+[guid]::NewGuid().ToString('N'));$OldAppData=$env:APPDATA
try{
 New-Item -ItemType Directory -Path $Sandbox -Force|Out-Null;$env:APPDATA=$Sandbox
 $Source=[IO.File]::ReadAllText((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'))
 $Source=$Source.Replace('$script:AppRoot = Split-Path -Parent $PSCommandPath',('$script:AppRoot = '''+(Join-Path $Root 'RemoteOps.App')+''''))
 $Source=$Source.Replace('$script:DataRoot = ''C:\Temp\YD_RemoteOps.App''',('$script:DataRoot = '''+$Sandbox+'\data'''))
 $Source=$Source.Replace('[void]$script:Window.ShowDialog()','')
 . ([scriptblock]::Create($Source));$script:OutputTimer.Stop()
 function Start-RemoteOpsRequest {throw 'Visual verification must never dispatch.'}
 $Profile=[pscustomobject]@{Display='TEST\operator';Domain='TEST';UserName='operator';IsMain=$true;ProtectedPassword=''}
 $script:ProfileList.ItemsSource=@($Profile);$script:ProfileList.SelectedIndex=0;$script:ActiveIdentity.Text='TEST\operator (örnek veri)'
 New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
 function Save-WpfView($Visual,[string]$Name,[int]$Width=1280,[int]$Height=810,[int]$Dpi=96){
  $Visual.Measure((New-Object Windows.Size $Width,$Height));$Visual.Arrange((New-Object Windows.Rect 0,0,$Width,$Height));$Visual.UpdateLayout()
  $Scale=$Dpi/96.0;$Bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]($Width*$Scale)),([int]($Height*$Scale)),$Dpi,$Dpi,([Windows.Media.PixelFormats]::Pbgra32);$Bitmap.Render($Visual)
  $Encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$Encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($Bitmap));$Stream=[IO.File]::Create((Join-Path $OutputDirectory ($Name+'.png')));try{$Encoder.Save($Stream)}finally{$Stream.Dispose()}
 }
 $D=New-RemoteOpsRecipeDefinition 'Uygulama servisini hazırla' 'Sürüm uygunsa servisi başlat ve durumunu listele.';$D.Schema='RemoteOps.Recipe/4'
 $Gate=[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Sürüm kontrolü';Operation='RecipeCondition';Values=[pscustomobject]@{Match='All';OnFalse='Skip';Checks=@([pscustomobject]@{Kind='RegistryValue';Path='HKLM\SOFTWARE\OrnekUygulama';Name='Version';Operator='Equals';ExpectedType='Auto';Expected='16.0.444'})}}
 $D.Steps=@($Gate,[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Servisi başlat · OrnekServis';Operation='ServiceControl';ConditionId=$Gate.Id;Values=[pscustomobject]@{ServiceName='OrnekServis';Action='Start'}},[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Servisleri listele · OrnekServis';Operation='ServiceList';Values=[pscustomobject]@{Filter='OrnekServis'}})
 foreach($Action in @($D.Steps|Where-Object Operation -ne 'RecipeCondition')){$Action|Add-Member NoteProperty AutoName $true}
 Open-RemoteOpsRecipeEditor $D;Save-RemoteOpsRecipeEditor
 $script:RecipeUi.Controls.Targets.Text='PC-IST-001, PC-IST-002'
 $script:MainTabs.SelectedItem=$script:RecipeUi.Tab
 $Content=$script:Window.Content;$Content.Background=$script:Window.Background
 Save-WpfView $Content 'recete-ana'
 Save-WpfView $Content 'recete-ana-125' 1060 700 120
 Save-WpfView $Content 'recete-ana-dar' 960 550
  $script:RecipeUi.Controls.Steps.SelectedIndex=0
 $State=New-RemoteOpsRecipeStepDialog
 $State.Window.Content.Background=$State.Window.Background
 $State.Controls.Tabs.SelectedIndex=0
 Save-WpfView $State.Window.Content 'adim-islemi' 648 580
 $State.Controls.Tabs.SelectedIndex=1
 Save-WpfView $State.Window.Content 'adim-kosulu' 648 580
 Save-WpfView $State.Window.Content 'adim-kosulu-125' 648 580 120
 $State.Window.Close()
 $State=New-RemoteOpsRecipeStepDialog;$State.Window.Content.Background=$State.Window.Background;$State.Controls.Tabs.SelectedIndex=1
 $Row=$script:RecipeUi.ConditionInputs.Rows[0];$Row.Kind.SelectedItem='Service';$Row.Name.Text='OrnekServis';$Row.Operator.SelectedItem='State';$Row.ExpectedChoice.SelectedItem='Stopped'
 Save-WpfView $State.Window.Content 'adim-servis-kosulu' 648 580
 $State.Window.Close()
 $script:RecipeUi.Controls.EditorTabs.SelectedIndex=1
 Save-WpfView $Content 'recete-hedefler' 1280 810
 $script:RecipeUi.Controls.EditorTabs.SelectedIndex=0
 Write-Output 'PASS v26 real WPF sample rendering; no remote operation dispatched.'
}finally{
 $env:APPDATA=$OldAppData
 if(Get-Variable OutputTimer -Scope Script -ErrorAction SilentlyContinue){$script:OutputTimer.Stop()}
 if(Get-Variable Window -Scope Script -ErrorAction SilentlyContinue){$script:Window.Close()}
}

