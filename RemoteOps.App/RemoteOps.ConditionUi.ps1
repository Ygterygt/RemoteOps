$script:ConditionChoiceTemplate=$null
function Set-RemoteOpsConditionChoiceLabels {
 param($InputControl)
 if($null -eq $script:ConditionChoiceTemplate){
  $Labels=[ordered]@{Start='Başlat';Restart='Yeniden başlat';Install='Kur';Uninstall='Kaldır';Downgrade='Sürüm düşür';All='Tümü sağlansın';Any='Herhangi biri sağlansın';Skip='Bağlı adımları atla';Stop='Bu hedefin reçetesini durdur';RegistryKey='Registry anahtarı';RegistryValue='Registry değeri';Service='Servis';Exists='Var';NotExists='Yok';Equals='Eşit';NotEquals='Eşit değil';State='Servis durumu';Startup='Başlangıç türü';Running='Çalışıyor';Stopped='Durduruldu';Paused='Duraklatıldı';'Start Pending'='Başlatılıyor';'Stop Pending'='Durduruluyor';'Pause Pending'='Duraklatılıyor';'Continue Pending'='Devam ediyor';Automatic='Otomatik';Manual='El ile';Disabled='Devre dışı';Unknown='Bilinmiyor'}
  $Triggers='';foreach($Code in $Labels.Keys){$Triggers+='<DataTrigger Binding="{Binding}" Value="'+$Code+'"><Setter Property="Text" Value="'+$Labels[$Code]+'"/></DataTrigger>'}
  $Xml=[xml]('<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><TextBlock><TextBlock.Style><Style TargetType="TextBlock"><Setter Property="Text" Value="{Binding}"/><Style.Triggers>'+$Triggers+'</Style.Triggers></Style></TextBlock.Style></TextBlock></DataTemplate>')
  $script:ConditionChoiceTemplate=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $Xml))
 }
 $InputControl.ItemTemplate=$script:ConditionChoiceTemplate
}
function New-RemoteOpsConditionUiValues {
 param([string]$Kind='RegistryValue')
 [pscustomobject]@{Match='All';OnFalse='Skip';Checks=@([pscustomobject]@{Kind=$Kind;Path='';Name='';Operator=$(if($Kind -eq 'RegistryValue'){'Equals'}else{'Exists'});ExpectedType=$(if($Kind -eq 'RegistryValue'){'Auto'}else{''});Expected=''})}
}
function Assert-RemoteOpsRecipeUiScope {
 param($Steps)
 $Active=''
 foreach($Step in $Steps){
  $Link=[string](Get-RemoteOpsPreviewValue $Step ConditionId '')
  if($Step.Operation -eq 'RecipeCondition'){if($Link){throw 'Koşul başka koşula bağlanamaz.'};$Active=$Step.Id}
  elseif($Link){if($Link -cne $Active){throw 'Bağlı adımlar koşulun hemen ardından kesintisiz gelmelidir.'}}
  else{$Active=''}
 }
}
function Get-RemoteOpsRecipeConditionChoices {
 param($Step)
 $Result=@([pscustomobject]@{Id='';Name='Koşulsuz'})
 $Index=[array]::IndexOf($script:RecipeUi.Draft.Steps,$Step)
 for($I=$Index-1;$I -ge 0;$I--){$Previous=$script:RecipeUi.Draft.Steps[$I];if($Previous.Operation -eq 'RecipeCondition'){$Result+=,[pscustomobject]@{Id=$Previous.Id;Name=('Koşul: '+$Previous.Name)};break};if(-not [string](Get-RemoteOpsPreviewValue $Previous ConditionId '')){break}}
 return $Result
}
function Add-RemoteOpsConditionField {
 param($Panel,[string]$Label,$Control)
 $Wrap=New-Object Windows.Controls.StackPanel;$Wrap.Margin='0,1,0,2'
 $Text=New-Object Windows.Controls.TextBlock;$Text.Text=$Label;$Text.Margin='0,0,0,1'
 [void]$Wrap.Children.Add($Text);$Control.MinHeight=28;[void]$Wrap.Children.Add($Control);[void]$Panel.Children.Add($Wrap)
 return $Wrap
}
function Update-RemoteOpsConditionRow {
 param($Row,[switch]$KindChanged)
 if($Row.Busy){return};$Row.Busy=$true
 try{
  $Kind=[string]$Row.Kind.SelectedItem
  $Ops=if($Kind -eq 'Service'){@('Exists','NotExists','State','Startup')}elseif($Kind -eq 'RegistryValue'){@('Exists','NotExists','Equals','NotEquals')}else{@('Exists','NotExists')}
  $Op=[string]$Row.Operator.SelectedItem
  if($Ops -notcontains $Op){$Op=if($Kind -eq 'RegistryValue'){'Equals'}else{'Exists'}}
  $Row.Operator.ItemsSource=@($Ops);$Row.Operator.SelectedItem=$Op
  if($KindChanged){if($Kind -eq 'Service' -or $Row.PreviousKind -eq 'Service'){$Row.Path.Text='';$Row.Name.Text=''};if($Kind -eq 'RegistryKey'){$Row.Name.Text=''};$Row.Expected.Text='';$Row.LegacyType='';$Row.ExpectedChoice.SelectedIndex=-1};$Row.PreviousKind=$Kind
  $Row.PathWrap.Visibility=if($Kind -eq 'Service'){'Collapsed'}else{'Visible'}
  $Row.NameWrap.Visibility=if($Kind -eq 'RegistryKey'){'Collapsed'}else{'Visible'}
  $Row.NameLabel.Text=if($Kind -eq 'Service'){'Servis adı'}else{'Değer adı (varsayılan değer için boş bırakın)'}
  $Equality=$Kind -eq 'RegistryValue' -and $Op -in @('Equals','NotEquals')
  $Row.ExpectedLabel.Text=if($Op -eq 'NotEquals'){'Hangi değerden farklı olsun?'}else{'Hangi değere eşit olsun?'}
  $Row.ExpectedWrap.Visibility=if($Equality){'Visible'}else{'Collapsed'}
  $Row.ChoiceWrap.Visibility=if($Kind -eq 'Service' -and $Op -in @('State','Startup')){'Visible'}else{'Collapsed'}
  if($Kind -eq 'Service'){
   $Codes=if($Op -eq 'Startup'){@('Automatic','Manual','Disabled')}else{@('Running','Stopped','Paused','Start Pending','Stop Pending','Pause Pending','Continue Pending','Unknown')}
   $Previous=[string]$Row.ExpectedChoice.SelectedItem;$Row.ExpectedChoice.ItemsSource=@($Codes)
   $Row.ExpectedChoice.SelectedItem=if($Codes -contains $Previous){$Previous}else{$Codes[0]}
  }
 }finally{$Row.Busy=$false}
}
function Show-RemoteOpsConditionForm {
 param($Values)
 $S=$script:RecipeUi;$Panel=$S.Controls.Fields
 $S.ConditionInputs=[pscustomobject]@{Match=$null;OnFalse=$null;Rows=@()}
 $Heading=New-Object Windows.Controls.TextBlock;$Heading.Text=if($S.PSObject.Properties['Dialog'] -and $S.Dialog -and -not $S.Dialog.Shared -and $S.Dialog.Action.Operation -ne 'RecipeCondition'){'Bu koşul sağlanırsa bu adım çalışır.'}else{'Bu koşul sağlanırsa bağlı adımlar çalışır.'};$Heading.FontWeight='SemiBold';$Heading.Margin='0,0,0,3';[void]$Panel.Children.Add($Heading)
 foreach($Spec in @(@('Match','Birden fazla kontrol varsa ne sağlanmalı?','All','Any'),@('OnFalse','Koşul sağlanmazsa ne yapılsın?','Skip','Stop'))){$Input=New-Object Windows.Controls.ComboBox;Set-RemoteOpsConditionChoiceLabels $Input;$Input.ItemsSource=@($Spec[2],$Spec[3]);$Input.SelectedItem=[string]$Values.($Spec[0]);if($Spec[0] -eq 'OnFalse' -and $S.PSObject.Properties['Dialog'] -and $S.Dialog -and -not $S.Dialog.Shared -and $S.Dialog.Action.Operation -ne 'RecipeCondition'){$ChoiceXml=[xml]'<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><TextBlock><TextBlock.Style><Style TargetType="TextBlock"><Setter Property="Text" Value="{Binding}"/><Style.Triggers><DataTrigger Binding="{Binding}" Value="Skip"><Setter Property="Text" Value="Bu adımı atla"/></DataTrigger><DataTrigger Binding="{Binding}" Value="Stop"><Setter Property="Text" Value="Bu hedefin reçetesini durdur"/></DataTrigger></Style.Triggers></Style></TextBlock.Style></TextBlock></DataTemplate>';$Input.ItemTemplate=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $ChoiceXml))};$S.ConditionInputs.($Spec[0])=$Input;[void](Add-RemoteOpsConditionField $Panel $Spec[1] $Input)}
 $Options=@($Panel.Children|Where-Object{$_ -is [Windows.Controls.StackPanel]});foreach($Option in $Options){[void]$Panel.Children.Remove($Option)};if($Values.Checks.Count -le 1){$Options[0].Visibility='Collapsed'}
 $Number=0
 foreach($Check in $Values.Checks){
  $Number++;$Box=New-Object Windows.Controls.StackPanel;$Box.Margin='8,2,0,3';$Row=@{Busy=$true;LegacyType=[string]$Check.ExpectedType;OriginalKind=[string]$Check.Kind;OriginalOperator=[string]$Check.Operator;OriginalExpected=[string]$Check.Expected}
  $L=New-Object Windows.Controls.TextBlock;$L.Text=if($Number -eq 1){'Kontrol'}else{"Ek kontrol $($Number-1)"};$L.FontWeight='SemiBold';if($Values.Checks.Count -eq 1){$L.Visibility='Collapsed'};[void]$Box.Children.Add($L)
  foreach($K in @('Kind','Path','Name','Operator','Expected','ExpectedChoice')){
   $Label=@{Kind='Ne kontrol edilsin?';Path='Registry yolu';Name='Değer adı';Operator='Hangi koşul sağlansın?';Expected='Hangi değere eşit olsun?';ExpectedChoice='Beklenen durum'}[$K]
   if($K -in @('Kind','Operator','ExpectedChoice')){$Input=New-Object Windows.Controls.ComboBox;Set-RemoteOpsConditionChoiceLabels $Input}else{$Input=New-Object Windows.Controls.TextBox}
   if($K -eq 'Kind'){$Input.ItemsSource=@('RegistryValue','RegistryKey','Service');$Input.SelectedItem=[string]$Check.Kind}
   elseif($K -eq 'Operator'){$Input.ItemsSource=@('Exists','NotExists','Equals','NotEquals','State','Startup');$Input.SelectedItem=[string]$Check.Operator}
   elseif($K -eq 'ExpectedChoice'){$Input.ItemsSource=@('Running','Stopped','Paused','Start Pending','Stop Pending','Pause Pending','Continue Pending','Unknown','Automatic','Manual','Disabled');$Input.SelectedItem=[string]$Check.Expected}
   else{$Input.Text=[string]$Check.$K;if($K -eq 'Expected'){$Input.AcceptsReturn=$true;$Input.MinHeight=30;$Input.ToolTip='Metni olduğu gibi yazın. Çok satırlı değerler için her öğeyi ayrı satıra yazın.'}}
   $Row[$K]=$Input;$Wrap=Add-RemoteOpsConditionField $Box $Label $Input
   if($K -eq 'Kind'){$Row.KindWrap=$Wrap;}
   if($K -eq 'Name'){$Row.NameLabel=$Wrap.Children[0]};if($K -eq 'Path'){$Row.PathWrap=$Wrap};if($K -eq 'Name'){$Row.NameWrap=$Wrap};if($K -eq 'Expected'){$Row.ExpectedWrap=$Wrap;$Row.ExpectedLabel=$Wrap.Children[0]};if($K -eq 'ExpectedChoice'){$Row.ChoiceWrap=$Wrap}
  }
  $Row.Busy=$false;Update-RemoteOpsConditionRow $Row
  $Row.Kind.Tag=$Row;$Row.Operator.Tag=$Row
  $Row.Kind.Add_SelectionChanged({if(-not $script:RecipeUi.Loading -and -not $this.Tag.Busy){Update-RemoteOpsConditionRow $this.Tag -KindChanged}})
  $Row.Operator.Add_SelectionChanged({if(-not $script:RecipeUi.Loading -and -not $this.Tag.Busy){Update-RemoteOpsConditionRow $this.Tag}})
  $Remove=New-Object Windows.Controls.Button;$Remove.Content='Kontrolü kaldır';if($Values.Checks.Count -eq 1){$Remove.Visibility='Collapsed'};$Remove.HorizontalAlignment='Left';$Remove.Tag=$Number-1;$Remove.Add_Click({Save-RemoteOpsConditionForm;$S=$script:RecipeUi;if($S.CurrentStep.Values.Checks.Count -le 1){$S.Controls.Status.Text='En az bir kontrol gerekir.';return};$N=[int]$this.Tag;$S.CurrentStep.Values.Checks=@(for($I=0;$I -lt $S.CurrentStep.Values.Checks.Count;$I++){if($I -ne $N){$S.CurrentStep.Values.Checks[$I]}});Show-RemoteOpsRecipeStepForm});[void]$Box.Children.Add($Remove)
  $S.ConditionInputs.Rows+=,$Row;[void]$Panel.Children.Add($Box)
 }
 $Add=New-Object Windows.Controls.Button;$Add.Content='Ek kontrol';$Add.HorizontalAlignment='Left';$Add.Add_Click({Save-RemoteOpsConditionForm;if($script:RecipeUi.CurrentStep.Values.Checks.Count -ge 10){$script:RecipeUi.Controls.Status.Text='En fazla 10 kontrol eklenebilir.';return};$script:RecipeUi.CurrentStep.Values.Checks+=,(New-RemoteOpsConditionUiValues).Checks[0];Show-RemoteOpsRecipeStepForm});[void]$Panel.Children.Add($Add)
 foreach($Option in $Options){[void]$Panel.Children.Add($Option)}
 $Hint=New-Object Windows.Controls.TextBlock;$Hint.Text='Kontrol hedefte okunur; bir erişim hatası olursa o bilgisayardaki reçete durur.';$Hint.TextWrapping='Wrap';$Hint.Foreground='#62778A';$Hint.Margin='0,3,0,2';[void]$Panel.Children.Add($Hint)
}
function Save-RemoteOpsConditionForm {
 $S=$script:RecipeUi;$F=$S.ConditionInputs;if($null -eq $F){return};$Checks=@()
 foreach($Row in $F.Rows){
  $Kind=[string]$Row.Kind.SelectedItem;$Op=[string]$Row.Operator.SelectedItem
  $Equality=$Kind -eq 'RegistryValue' -and $Op -in @('Equals','NotEquals')
  $Expected=if($Equality){$Row.Expected.Text}elseif($Kind -eq 'Service' -and $Op -in @('State','Startup')){[string]$Row.ExpectedChoice.SelectedItem}else{''}
  $Type=if($Equality){if($Row.LegacyType -and $Kind -ceq $Row.OriginalKind -and $Op -ceq $Row.OriginalOperator -and $Expected -ceq $Row.OriginalExpected){$Row.LegacyType}else{'Auto'}}else{''}
  if($Type -eq 'Auto' -and $S.Draft.Schema -cne 'RemoteOps.Recipe/4'){$S.Draft.Schema='RemoteOps.Recipe/3'}
  $Checks+=,[pscustomobject]@{Kind=$Kind;Path=$(if($Kind -ne 'Service'){$Row.Path.Text}else{''});Name=$(if($Kind -ne 'RegistryKey'){$Row.Name.Text}else{''});Operator=$Op;ExpectedType=$Type;Expected=$Expected}
 }
 $S.CurrentStep.Values=[pscustomobject]@{Match=[string]$F.Match.SelectedItem;OnFalse=[string]$F.OnFalse.SelectedItem;Checks=$Checks}
}
function Get-RemoteOpsConditionPreviewLines {
 param($Step)
 $Lines=@($(if($Step.Values.Match -eq 'All'){'Kontrollerin tümü sağlanırsa bağlı adımlar çalışır.'}else{'En az bir kontrol sağlanırsa bağlı adımlar çalışır.'}),$(if($Step.Values.OnFalse -eq 'Skip'){'Sağlanmazsa bağlı adımlar atlanır.'}else{'Sağlanmazsa bu bilgisayarın reçetesi durur.'}))
 $Words=@{Exists='var olmalı';NotExists='bulunmamalı';Equals='şu değere eşit olmalı';NotEquals='şu değerden farklı olmalı';State='durumu şu olmalı';Startup='başlangıcı şu olmalı';Running='Çalışıyor';Stopped='Durduruldu';Automatic='Otomatik';Manual='El ile';Disabled='Devre dışı';Unknown='Bilinmiyor'}
 foreach($Check in $Step.Values.Checks){$Subject=if($Check.Kind -eq 'Service'){'Servis '+$Check.Name}elseif($Check.Kind -eq 'RegistryKey'){'Registry anahtarı '+$Check.Path}else{'Registry değeri '+$Check.Path+' / '+$(if($Check.Name){$Check.Name}else{'(varsayılan)'})};$Expected=if($Check.Kind -eq 'Service' -and $Words.ContainsKey([string]$Check.Expected)){$Words[[string]$Check.Expected]}else{$Check.Expected};$Lines+=('  '+$Subject+' '+$Words[$Check.Operator]+$(if($Expected){': '+$Expected}else{''})+'.')}
 return $Lines
}
