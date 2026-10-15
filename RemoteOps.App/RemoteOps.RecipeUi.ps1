. (Join-Path $PSScriptRoot 'RemoteOps.ConditionUi.ps1')
function Get-RemoteOpsRecipeUiOperations {
 foreach($Operation in @(Get-RemoteOpsRecipeOperations|Where-Object Name -ne 'RecipeCondition')){
  if($Operation.Name -eq 'ServiceControl'){[pscustomobject]@{Name=$Operation.Name;Title='Servisi başlat / durdur / yeniden başlat'}}else{$Operation}
 }

}
function Initialize-RemoteOpsRecipeUi {
 param($Tabs,[string]$CatalogRoot)
 $Xml=[xml]@'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Margin="4"><Grid.ColumnDefinitions><ColumnDefinition Width="220"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
 <DockPanel><StackPanel DockPanel.Dock="Top"><TextBlock Text="Operasyon Reçeteleri" FontSize="20" FontWeight="SemiBold" Foreground="#1F3342"/><TextBox x:Name="Search" Margin="0,10,0,5" ToolTip="Reçete ara"/><WrapPanel><Button x:Name="New" Content="Yeni" Margin="0,0,6,0"/><Button x:Name="Reload" Content="Yenile"/></WrapPanel></StackPanel><ListBox x:Name="List" DisplayMemberPath="Name" Margin="0,10,0,0"/></DockPanel>
 <Grid Grid.Column="2"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><StackPanel><TextBlock Text="Reçete adı"/><TextBox x:Name="Name" Margin="0,4,0,6"/><TextBox x:Name="Description" Height="35" ToolTip="Açıklama" Margin="0,0,0,6"/></StackPanel><TabControl Style="{x:Null}" x:Name="EditorTabs" Grid.Row="1"><TabItem Style="{x:Null}" Header="Adımlar"><DockPanel><WrapPanel DockPanel.Dock="Bottom" Margin="0,8"><Button x:Name="AddStep" Content="Adım ekle" Margin="0,0,6,0"/><Button x:Name="EditStep" Content="Düzenle" Margin="0,0,6,0"/><Button x:Name="AddCondition" Visibility="Collapsed"/><Button x:Name="RemoveStep" Content="Kaldır" Margin="0,0,6,0"/><Button x:Name="Up" Content="Yukarı" Margin="0,0,6,0"/><Button x:Name="Down" Content="Aşağı"/></WrapPanel><ListBox x:Name="Steps" Margin="0,5" ScrollViewer.HorizontalScrollBarVisibility="Disabled"><ListBox.ItemTemplate><DataTemplate><StackPanel Margin="3,4"><TextBlock Text="{Binding Name}" TextWrapping="Wrap"/><TextBlock x:Name="ScopeHint" Text="Koşullu işlem · düzenlemek için çift tıklayın" FontSize="11" Foreground="#62778A"/></StackPanel><DataTemplate.Triggers><DataTrigger Binding="{Binding ConditionId}" Value="{x:Null}"><Setter TargetName="ScopeHint" Property="Text" Value="İşlem · düzenlemek için çift tıklayın"/></DataTrigger><DataTrigger Binding="{Binding Operation}" Value="RecipeCondition"><Setter TargetName="ScopeHint" Property="Text" Value="Eski paylaşılan koşul grubu · tek kez değerlendirilir"/></DataTrigger></DataTemplate.Triggers></DataTemplate></ListBox.ItemTemplate></ListBox></DockPanel></TabItem><TabItem Style="{x:Null}" Header="Hedefler"><StackPanel><TextBlock Text="Çalıştırma hedefleri · bilgisayarlar sırayla işlenir" TextWrapping="Wrap"/><TextBox x:Name="Targets" Height="90" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" Margin="0,5"/></StackPanel></TabItem></TabControl><StackPanel Grid.Row="2"><TextBlock x:Name="Status" Foreground="#A44721" TextWrapping="Wrap" MaxHeight="40"/><WrapPanel Margin="0,6"><Button x:Name="Save" Content="Kaydet" Margin="0,0,7,0"/><Button x:Name="Copy" Content="Kopyala" Margin="0,0,7,0"/><Button x:Name="Delete" Content="Tanımı sil" Margin="0,0,7,0"/><Button x:Name="Preview" Content="Reçeteyi önizle"/></WrapPanel></StackPanel><StackPanel x:Name="StepEditor" Visibility="Collapsed"><CheckBox x:Name="CustomizeName" Content="Adı özelleştir" Margin="0,0,0,7"/><StackPanel x:Name="StepNameWrap" Visibility="Collapsed"><TextBlock Text="Özel ad"/><TextBox x:Name="StepName" Margin="0,4,0,8"/></StackPanel><TextBlock Text="Adımda ne yapılsın?"/><ComboBox x:Name="Operation" DisplayMemberPath="Title" Margin="0,4,0,8"/><StackPanel x:Name="Fields"/><TextBlock x:Name="RecipeEffectHint" Visibility="Collapsed" Text="Dosya gönderme üzerine yazabilir; otomatik yedek/geri alma yoktur." TextWrapping="Wrap"/></StackPanel></Grid>
</Grid>
'@
 $View=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $Xml));$C=@{}
 foreach($N in @('EditorTabs','StepEditor','CustomizeName','StepNameWrap','EditStep','Search','New','Reload','List','Save','Copy','Delete','Targets','Preview','Name','Description','Status','Steps','AddStep','AddCondition','RemoveStep','Up','Down','StepName','Operation','Fields','RecipeEffectHint')){$C[$N]=$View.FindName($N)}
 $Tab=New-Object Windows.Controls.TabItem;$Tab.Header='Operasyon Reçeteleri';$Tab.Name='RecipesTab';$Tab.Content=$View;[void]$Tabs.Items.Add($Tab)
 $script:RecipeUi=[pscustomobject]@{Tab=$Tab;Root=$CatalogRoot;Controls=$C;Draft=$null;SavedHash='';Fields=@{};ConditionInputs=$null;ConditionBinding=$null;CurrentStep=$null;Loading=$false;Catalog=$null;GroupPicker=$null}
 $C.Steps.Add_LayoutUpdated({Update-RemoteOpsRecipeRowHints})
 $C.Operation.ItemsSource=@(Get-RemoteOpsRecipeUiOperations)
 $C.CustomizeName.Add_Checked({Set-RemoteOpsRecipeCustomNameVisibility});$C.CustomizeName.Add_Unchecked({Set-RemoteOpsRecipeCustomNameVisibility})
 $C.New.Add_Click({New-RemoteOpsRecipeEditor});$C.Reload.Add_Click({Update-RemoteOpsRecipeUi -Reload})
 $C.Search.Add_TextChanged({Update-RemoteOpsRecipeUi})
 $C.List.Add_SelectionChanged({if(-not $script:RecipeUi.Loading -and $null -ne $script:RecipeUi.Controls.List.SelectedItem){Open-RemoteOpsRecipeEditor $script:RecipeUi.Controls.List.SelectedItem}})
 $C.Save.Add_Click({try{Save-RemoteOpsRecipeEditor}catch{$script:RecipeUi.Controls.Status.Text=$_.Exception.Message}})
 $C.Copy.Add_Click({try{$D=Get-RemoteOpsRecipeEditorDefinition;$script:RecipeUi.Draft=Copy-RemoteOpsRecipeDefinition $D -NewIdentity;$script:RecipeUi.Draft.Name+=' (kopya)';Show-RemoteOpsRecipeDraft;$script:RecipeUi.Controls.Status.Text='Kopyayı kaydedin.'}catch{$script:RecipeUi.Controls.Status.Text=$_.Exception.Message}})
 $C.Delete.Add_Click({try{if($script:RecipeUi.Draft.Revision -gt 0 -and [Windows.MessageBox]::Show('Yalnızca kişisel reçete tanımı silinsin mi?','Reçete','YesNo','Question') -eq 'Yes'){Remove-RemoteOpsRecipeDefinition $script:RecipeUi.Root $script:RecipeUi.Draft.Id $script:RecipeUi.Draft.Revision;New-RemoteOpsRecipeEditor;Update-RemoteOpsRecipeUi -Reload}}catch{$script:RecipeUi.Controls.Status.Text=$_.Exception.Message}})
 $C.AddStep.Add_Click({Add-RemoteOpsRecipeAction})
 $C.EditStep.Add_Click({Open-RemoteOpsRecipeStepDialog})
 $C.Steps.Add_MouseDoubleClick({Open-RemoteOpsRecipeStepDialog})
 $C.RemoveStep.Add_Click({Remove-RemoteOpsRecipeAction})
 $C.Up.Add_Click({Move-RemoteOpsRecipeStep -1});$C.Down.Add_Click({Move-RemoteOpsRecipeStep 1})
 $C.Steps.Add_SelectionChanged({if(-not $script:RecipeUi.Loading){Show-RemoteOpsRecipeStepForm}})
 $C.Operation.Add_SelectionChanged({
  $S=$script:RecipeUi;if($S.Loading -or $null -eq $S.CurrentStep -or $null -eq $S.Controls.Operation.SelectedItem){return}
  $Choice=$S.Controls.Operation.SelectedItem;Save-RemoteOpsRecipeStepForm;$Step=$S.CurrentStep
  if($Step.Operation -eq 'RecipeCondition' -and $Choice.Name -ne 'RecipeCondition' -and @($S.Draft.Steps|Where-Object{[string](Get-RemoteOpsPreviewValue $_ ConditionId '') -ceq $Step.Id}).Count){$S.Controls.Status.Text='Önce bu koşula bağlı adımların bağlantısını kaldırın.';Show-RemoteOpsRecipeStepForm;return}
  $OldOperation=$Step.Operation;$OldValues=$Step.Values;$OldLink=[string](Get-RemoteOpsPreviewValue $Step ConditionId '')
  if($Choice.Name -eq 'RecipeCondition'){
   if($OldOperation -eq 'RecipeCondition' -and $OldValues.Checks[0].Kind -eq $Choice.ConditionKind){return}
   if($OldOperation -eq 'RecipeCondition'){$Row=$S.ConditionInputs.Rows[0];$Row.Kind.SelectedItem=$Choice.ConditionKind;Save-RemoteOpsConditionForm}else{$Step.Operation='RecipeCondition';$Step.Values=New-RemoteOpsConditionUiValues $Choice.ConditionKind;$Step.PSObject.Properties.Remove('ConditionId')}
  }else{$Step.Operation=$Choice.Name;$Step.Values=New-RemoteOpsRecipeStepValues $Step.Operation}
  try{Assert-RemoteOpsRecipeUiScope $S.Draft.Steps}catch{$Step.Operation=$OldOperation;$Step.Values=$OldValues;$Step.PSObject.Properties.Remove('ConditionId');if($OldLink){$Step|Add-Member NoteProperty ConditionId $OldLink};$S.Controls.Status.Text=$_.Exception.Message;Show-RemoteOpsRecipeStepForm;return}
  if($Choice.Name -eq 'RecipeCondition' -and $S.Draft.Schema -cne 'RemoteOps.Recipe/4'){$S.Draft.Schema='RemoteOps.Recipe/3'}
  Show-RemoteOpsRecipeStepForm
 })
 $C.Preview.Add_Click({try{$D=Get-RemoteOpsRecipeEditorDefinition;$W=New-RemoteOpsRecipePreviewWindow $D @(ConvertTo-RemoteOpsTargets $script:RecipeUi.Controls.Targets.Text);[void]$W.Window.ShowDialog()}catch{$script:RecipeUi.Controls.Status.Text=$_.Exception.Message}})
 if(Get-Command Add-RemoteOpsTargetGroupPicker -ErrorAction SilentlyContinue){$script:RecipeUi.GroupPicker=Add-RemoteOpsTargetGroupPicker -Parent $C.Targets.Parent -TargetBox $C.Targets -CatalogRoot $script:TargetGroupCatalogRoot}
 New-RemoteOpsRecipeEditor;Update-RemoteOpsRecipeUi -Reload
 $Recovery=Repair-RemoteOpsRecipeReports $script:DataRoot;if($Recovery.Repaired -gt 0 -or $Recovery.Issues.Count -gt 0){$C.Status.Text=('Kesilen reçete raporları: '+$Recovery.Repaired+' tamamlandı, '+$Recovery.Issues.Count+' sorun. Geçmiş sekmesinden inceleyin.')}
 return $script:RecipeUi
}
function New-RemoteOpsRecipeStepValues {
 param([string]$Operation)
 $V=[ordered]@{};$Meta=@(Get-RemoteOpsRecipeOperations|Where-Object Name -eq $Operation)[0]
 foreach($K in $Meta.Fields){$V[$K]=switch($K){Overwrite{$false}Action{if($Operation -eq 'PackageDeployment'){'Install'}else{'Start'}}StartupType{'Automatic'}ValueType{'Auto'}PackageDefinition{$null}default{''}}};return [pscustomobject]$V
}
function New-RemoteOpsRecipeEditor {$script:RecipeUi.Draft=New-RemoteOpsRecipeDefinition;$script:RecipeUi.SavedHash='';Show-RemoteOpsRecipeDraft}
function Open-RemoteOpsRecipeEditor {param($Definition)$script:RecipeUi.Draft=Copy-RemoteOpsRecipeDefinition $Definition;$script:RecipeUi.SavedHash=Get-RemoteOpsPreviewHash $script:RecipeUi.Draft;Show-RemoteOpsRecipeDraft}
function Show-RemoteOpsRecipeDraft {
 $S=$script:RecipeUi;$C=$S.Controls;$S.CurrentStep=$null;$C.Name.Text=$S.Draft.Name;$C.Description.Text=$S.Draft.Description;$C.Status.Text='Kaydetmek hedefe bağlanmaz. Çalıştırmada yeni onay gerekir.';Update-RemoteOpsRecipeStepList 0
}
function Update-RemoteOpsRecipeUi {
 param([switch]$Reload)
 $S=$script:RecipeUi;$C=$S.Controls;if($null -eq $S.Catalog -and -not $Reload){return}
 if($Reload){$S.Catalog=Get-RemoteOpsRecipeCatalog $S.Root}
 $S.Loading=$true;try{$Needle=$C.Search.Text;$C.List.ItemsSource=@($S.Catalog.Recipes|Where-Object{-not $Needle -or $_.Name.IndexOf($Needle,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or $_.Description.IndexOf($Needle,[StringComparison]::OrdinalIgnoreCase) -ge 0})}finally{$S.Loading=$false}
 if($S.Catalog.Issues.Count){$C.Status.Text=@($S.Catalog.Issues|ForEach-Object{$_.Message}) -join "`r`n"}
}
function Update-RemoteOpsRecipeStepList {
 param([int]$Index=0)
 $S=$script:RecipeUi;$S.Loading=$true;try{$S.Controls.Steps.ItemsSource=@($S.Draft.Steps);$S.Controls.Steps.SelectedIndex=$Index}finally{$S.Loading=$false};Show-RemoteOpsRecipeStepForm
}
function Move-RemoteOpsRecipeStep {
 param([int]$Delta)
 Save-RemoteOpsRecipeStepForm;$S=$script:RecipeUi;$I=$S.Controls.Steps.SelectedIndex;$J=$I+$Delta
 if($I -lt 0 -or $J -lt 0 -or $J -ge $S.Draft.Steps.Count){return};$Old=$S.Draft.Steps[$I];$S.Draft.Steps[$I]=$S.Draft.Steps[$J];$S.Draft.Steps[$J]=$Old;try{Assert-RemoteOpsRecipeUiScope $S.Draft.Steps}catch{$S.Draft.Steps[$J]=$S.Draft.Steps[$I];$S.Draft.Steps[$I]=$Old;$S.Controls.Status.Text=$_.Exception.Message;return};Update-RemoteOpsRecipeStepList $J
}
function Save-RemoteOpsRecipeStepFormCore {
 $S=$script:RecipeUi;if($S.Loading -or $null -eq $S.CurrentStep){return};$S.CurrentStep.Name=$S.Controls.StepName.Text
 if($S.CurrentStep.Operation -eq 'RecipeCondition'){Save-RemoteOpsConditionForm;return}
 if($null -ne $S.ConditionBinding){$Old=[string](Get-RemoteOpsPreviewValue $S.CurrentStep ConditionId '');$Choice=$S.ConditionBinding.SelectedItem;$S.CurrentStep.PSObject.Properties.Remove('ConditionId');if($null -ne $Choice -and $Choice.Id){$S.CurrentStep|Add-Member NoteProperty ConditionId $Choice.Id};try{Assert-RemoteOpsRecipeUiScope $S.Draft.Steps}catch{$S.CurrentStep.PSObject.Properties.Remove('ConditionId');if($Old){$S.CurrentStep|Add-Member NoteProperty ConditionId $Old};$S.Controls.Status.Text=$_.Exception.Message};if([string](Get-RemoteOpsPreviewValue $S.CurrentStep ConditionId '')){if($S.Draft.Schema -ne 'RemoteOps.Recipe/3'){$S.Draft.Schema='RemoteOps.Recipe/2'}}}
 foreach($K in $S.Fields.Keys){$Input=$S.Fields[$K];$Value=if($Input -is [Windows.Controls.CheckBox]){[bool]$Input.IsChecked}elseif($Input -is [Windows.Controls.ComboBox]){if($K -eq 'PackageDefinition'){if($null -ne $Input.SelectedItem){Copy-RemoteOpsPackageDefinition $Input.SelectedItem}else{$null}}else{[string]$Input.SelectedItem}}else{$Input.Text};$S.CurrentStep.Values.$K=$Value}
}
function Show-RemoteOpsRecipeStepFormCore {
 $S=$script:RecipeUi;$C=$S.Controls;$S.CurrentStep=$C.Steps.SelectedItem;$S.Fields=@{};$S.ConditionBinding=$null;$C.Fields.Children.Clear();$S.Loading=$true
 try{
  if($null -eq $S.CurrentStep){$C.RecipeEffectHint.Visibility='Collapsed';$C.StepName.Clear();$C.Operation.SelectedIndex=-1;return}
  $Step=$S.CurrentStep;$C.RecipeEffectHint.Visibility=if($Step.Operation -in @('FilePush','FileCompare','PackageDeployment')){'Visible'}else{'Collapsed'};$C.StepName.Text=$Step.Name;$C.Operation.ItemsSource=@(Get-RemoteOpsRecipeUiOperations);$C.Operation.SelectedItem=@($C.Operation.Items|Where-Object{$_.Name -eq $Step.Operation -and ($Step.Operation -ne 'RecipeCondition' -or $_.ConditionKind -eq $Step.Values.Checks[0].Kind)})[0]
  $C.Operation.IsEnabled=$true
  if($Step.Operation -eq 'RecipeCondition'){Show-RemoteOpsConditionForm $Step.Values;return}
  foreach($K in @(Get-RemoteOpsRecipeKeys $Step.Values)){
   $Label=New-Object Windows.Controls.TextBlock;$Labels=@{Filter='Servis adı / görünen ad filtresi';ServiceName='Servis adı';Action='Eylem';StartupType='Başlangıç türü';LocalPath='Yerel kaynak / referans dosya';Path='Hedef dosya veya klasör yolu';Overwrite='Üzerine yazma';RegistryPath='Registry yolu';ValueName='Değer adı (varsayılan değer için boş)';ValueType='Değer türü';Value='Yeni değer';PackageDefinition='Kayıtlı paket · seçilen tanım reçeteye kopyalanır'};$Label.Text=$Labels[$K];$Label.Margin='0,5,0,3';[void]$C.Fields.Children.Add($Label)
   $Choices=switch($K){Action{if($Step.Operation -eq 'PackageDeployment'){@('Install','Uninstall','Downgrade')}else{@('Start','Stop','Restart')}}StartupType{@('Automatic','Manual','Disabled')}ValueType{@('Auto','REG_SZ','REG_DWORD','REG_QWORD','REG_MULTI_SZ','REG_EXPAND_SZ')}}
   $Value=Get-RemoteOpsPreviewValue $Step.Values $K
   if($K -eq 'Overwrite'){$Input=New-Object Windows.Controls.CheckBox;$Input.Content='Aynı adlı dosyanın üzerine yaz';$Input.IsChecked=[bool]$Value}
   elseif($K -eq 'PackageDefinition'){$Input=New-Object Windows.Controls.ComboBox;$Input.DisplayMemberPath='Name';$Packages=@((Get-RemoteOpsPackageCatalog $script:PackageCatalogRoot).Packages);if($null -ne $Value){$Packages=@($Value)+@($Packages|Where-Object{ $_.Id -ne $Value.Id -or $_.Revision -ne $Value.Revision})};$Input.ItemsSource=$Packages;if($null -ne $Value){$Input.SelectedIndex=0}}
   elseif($null -ne $Choices){$Input=New-Object Windows.Controls.ComboBox;$Input.ItemsSource=@($Choices);$Input.SelectedItem=[string]$Value;if($K -in @('Action','StartupType')){Set-RemoteOpsConditionChoiceLabels $Input;if($K -eq 'Action'){$ChoiceXml=[xml]([Windows.Markup.XamlWriter]::Save($Input.ItemTemplate).Replace('Bu hedefin reçetesini durdur','Durdur'));$Input.ItemTemplate=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $ChoiceXml))}}}
   else{$Input=New-Object Windows.Controls.TextBox;$Input.Text=[string]$Value;$Input.MinHeight=28;if($K -eq 'Value'){$Input.AcceptsReturn=$true;$Input.Height=60;$Input.VerticalScrollBarVisibility='Auto'}}
   $S.Fields[$K]=$Input;[void]$C.Fields.Children.Add($Input)
  }
 }finally{$S.Loading=$false}
}
function Get-RemoteOpsRecipeEditorDefinition {
 Save-RemoteOpsRecipeStepForm;$S=$script:RecipeUi;$S.Draft.Name=$S.Controls.Name.Text;$S.Draft.Description=$S.Controls.Description.Text;return Copy-RemoteOpsRecipeDefinition $S.Draft
}
function Save-RemoteOpsRecipeEditor {
 $S=$script:RecipeUi;$D=Get-RemoteOpsRecipeEditorDefinition;$Saved=Save-RemoteOpsRecipeDefinition $S.Root $D $D.Revision;Open-RemoteOpsRecipeEditor $Saved;Update-RemoteOpsRecipeUi -Reload;$S.Controls.Status.Text='Kaydedildi · revizyon '+$Saved.Revision
}
function New-RemoteOpsRecipePreviewWindow {
 param($Definition,[string[]]$Targets)
 $S=$script:RecipeUi
 if($S.SavedHash -cne (Get-RemoteOpsPreviewHash $Definition)){throw 'Önce reçetedeki değişiklikleri kaydedin.'}
 $Fresh=@((Get-RemoteOpsRecipeCatalog $S.Root).Recipes|Where-Object Id -eq $Definition.Id)
 if($Fresh.Count -ne 1 -or (Get-RemoteOpsPreviewHash $Fresh[0]) -cne $S.SavedHash){throw 'Kayıt değişti veya silindi. Yenileyip yeniden açın.'}
 $Settings=Get-RemoteOpsPreviewUiSettings ([pscustomobject]@{Name='RecipeRun';ParallelSafe=$false})
 $Snapshot=New-RemoteOpsRecipeRunSnapshot $Definition $Targets $script:ProfileList.SelectedItem $Settings.CleanupLogs
 for($T=1;$T -le $Snapshot.Targets.Count;$T++){for($I=1;$I -le $Definition.Steps.Count;$I++){[void](New-RemoteOpsRecipeStepRequest $Snapshot 'GUI-20000101-000000-ABCDEF' $T $I $script:DataRoot)}}
 $Xml=[xml]@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Reçete önizlemesi" Width="780" Height="650" MinWidth="480" MinHeight="350" Background="#EFF4F8" WindowStartupLocation="CenterScreen"><DockPanel Margin="18"><TextBlock DockPanel.Dock="Top" Text="Operasyon reçetesini incele" FontSize="24" FontWeight="SemiBold" Margin="0,0,0,12"/><StackPanel DockPanel.Dock="Bottom" Margin="0,8,0,0"><TextBlock Text="Başlatmak için RECETE yazın"/><TextBox x:Name="Confirm" MinHeight="30" Margin="0,6"/><TextBlock x:Name="Error" Foreground="#A44721" TextWrapping="Wrap" MaxHeight="70"/><WrapPanel Margin="0,8,0,0"><Button x:Name="Start" Content="İnceledim, başlat" Padding="18,9" Margin="0,0,10,0"/><Button x:Name="Cancel" Content="Vazgeç" Padding="18,9"/></WrapPanel></StackPanel><TextBox x:Name="Text" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Padding="12"/></DockPanel></Window>
'@
 $W=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $Xml));$Area=[Windows.SystemParameters]::WorkArea;$W.Height=[Math]::Min(650,$Area.Height-40);$W.Width=[Math]::Min(780,$Area.Width-32)
 $C=@{};foreach($K in @('Text','Confirm','Start','Cancel','Error')){$C[$K]=$W.FindName($K)}
 $Lines=@("Reçete: $($Definition.Name) · revizyon $($Definition.Revision)","Hesap: $($Snapshot.Identity.Domain)\$($Snapshot.Identity.UserName)",'Eşzamanlı bilgisayar: 1',('Hedefler: '+($Snapshot.Targets -join ', ')),'','Adımlar:')
 $I=0;foreach($Step in $Definition.Steps){$I++;$Title=@(Get-RemoteOpsRecipeOperations|Where-Object Name -ceq $Step.Operation)[0].Title;$Lines+="${I}. $($Step.Name) · $Title";if($Step.Operation -eq 'RecipeCondition'){$Lines+=@(Get-RemoteOpsConditionPreviewLines $Step);$Lines+='';continue};$Link=[string](Get-RemoteOpsPreviewValue $Step ConditionId '');if($Link){$Condition=@($Definition.Steps|Where-Object Id -ceq $Link)[0];$Lines+=('  Koşula bağlı: '+$Condition.Name)};foreach($K in Get-RemoteOpsRecipeKeys $Step.Values){$V=Get-RemoteOpsPreviewValue $Step.Values $K;$Lines+=($K+': '+$(if($K -eq 'PackageDefinition'){$V.Name+' / revizyon '+$V.Revision+' / hedef '+$V.TargetVersion}else{[string]$V}))};$Lines+=''}
 $Lines+=@('İlk hata, belirsiz sonuç, karşılaştırma farkı veya yeniden başlatma gereksiniminde o hedefin zinciri durur. Diğer hedefler devam eder. Durdur isteği bütün yeni adımları engeller.','Dosya gönderme aynı adlı içeriği ezebilir; otomatik yedek/geri alma yoktur. Servis/registry değişiklikleri mevcut durumu etkiler. Paket kaldırma/kurma yan etkileri otomatik geri alınmaz.','Yerel önizleme canlı hedef durumunu doğrulamaz. Kayıtlı paket snapshot kullanılır; otomatik tekrar/rollback yoktur.')
 $C.Text.Text=$Lines -join "`r`n"
 $State=[pscustomobject]@{Window=$W;Controls=$C;Snapshot=$Snapshot;Preview=$Snapshot;Started=$false}
 $C.Start.Tag=$State;$C.Cancel.Tag=$State;$C.Cancel.Add_Click({$this.Tag.Window.Close()});$C.Start.Add_Click({Start-RemoteOpsReviewedRecipe $this.Tag});return $State
}
function Start-RemoteOpsReviewedRecipe {
 param($State)
 if($State.Started){return}
 try{
  if($State.Controls.Confirm.Text -cne 'RECETE'){throw 'Başlatmak için RECETE yazın.'}
  $Definition=Get-RemoteOpsRecipeEditorDefinition;$Current=New-RemoteOpsRecipeRunSnapshot $Definition @(ConvertTo-RemoteOpsTargets $script:RecipeUi.Controls.Targets.Text) $script:ProfileList.SelectedItem ([bool]$script:SettingCleanupLogs.IsChecked)
  $Fresh=@((Get-RemoteOpsRecipeCatalog $script:RecipeUi.Root).Recipes|Where-Object Id -eq $Definition.Id)
  if($Fresh.Count -ne 1 -or (Get-RemoteOpsPreviewHash $Fresh[0]) -cne (Get-RemoteOpsPreviewHash $Definition) -or $Current.Hash -cne $State.Snapshot.Hash){throw 'Reçete, hedef, hesap veya ayarlar değişti. Kaydedip önizlemeyi yeniden açın.'}
  $State.Controls.Start.IsEnabled=$false
  $Operation=@($script:OperationCatalog|Where-Object Name -eq 'RecipeRun')[0]
  Start-RemoteOpsRequest $Operation @{Targets=($State.Snapshot.Targets -join ' ');Snapshot=$State.Snapshot;Confirm='RECETE'}
  $State.Started=$true;$State.Window.Close()
 }catch{$State.Controls.Error.Text=$_.Exception.Message;if(-not $State.Started){$State.Controls.Start.IsEnabled=$true}}
}

. (Join-Path $PSScriptRoot 'RemoteOps.RecipeFocusedUi.ps1')
