function Get-RemoteOpsRecipeAutoName {
 param($Step)
 $Meta=@(Get-RemoteOpsRecipeOperations|Where-Object Name -eq $Step.Operation)[0];$Title=$Meta.Title;$Subject=''
 foreach($Key in @('ServiceName','RegistryPath','Path','Filter')){if($Step.Values.PSObject.Properties[$Key] -and [string]$Step.Values.$Key){$Subject=[string]$Step.Values.$Key;break}}
 if($Step.Operation -eq 'PackageDeployment' -and $Step.Values.PackageDefinition){$Subject=$Step.Values.PackageDefinition.Name}
 $Words=@{Start='Başlat';Stop='Durdur';Restart='Yeniden başlat';Install='Kur';Uninstall='Kaldır';Downgrade='Sürüm düşür'}
 if($Step.Values.PSObject.Properties['Action'] -and $Words.ContainsKey([string]$Step.Values.Action)){$Title=$Words[[string]$Step.Values.Action];if($Step.Operation -eq 'ServiceControl'){$Title='Servisi '+$Title.ToLowerInvariant()}elseif($Step.Operation -eq 'PackageDeployment'){$Title='Paketi '+$Title.ToLowerInvariant()}}
 $Name=if($Subject){$Title+' · '+$Subject}else{$Title};if($Name.Length -gt 100){return ($Name.Substring(0,97)+'...')};return $Name
}
function Get-RemoteOpsRecipeUiUnits {
 param($Steps)
 $Units=@();$I=0
 while($I -lt $Steps.Count){$Members=@($Steps[$I]);$Head=$Steps[$I];$I++
  if($Head.Operation -eq 'RecipeCondition'){while($I -lt $Steps.Count -and [string](Get-RemoteOpsPreviewValue $Steps[$I] ConditionId '') -ceq $Head.Id){$Members+=,$Steps[$I];$I++}}
  $Units+=,[pscustomobject]@{Steps=$Members}
 };return $Units
}
function Update-RemoteOpsRecipeStepList {
 param([int]$Index=0)
 $S=$script:RecipeUi;$Visible=@()
 foreach($Unit in @(Get-RemoteOpsRecipeUiUnits $S.Draft.Steps)){if($Unit.Steps.Count -eq 2 -and $Unit.Steps[0].Operation -eq 'RecipeCondition'){$Visible+=,$Unit.Steps[1]}else{$Visible+=@($Unit.Steps)}}
 $S.Loading=$true;try{$S.Controls.Steps.ItemsSource=@($Visible);$S.Controls.Steps.SelectedIndex=[Math]::Min($Index,$Visible.Count-1)}finally{$S.Loading=$false};Show-RemoteOpsRecipeStepForm
}
function Save-RemoteOpsRecipeStepForm {
 $S=$script:RecipeUi;if(-not $S.PSObject.Properties['Dialog'] -or $null -eq $S.Dialog){return}
 if($null -eq $S.CurrentStep){return};if($S.CurrentStep.Operation -eq 'RecipeCondition'){Save-RemoteOpsConditionForm}else{Save-RemoteOpsRecipeStepFormCore}
}
function Show-RemoteOpsRecipeStepForm {
 $S=$script:RecipeUi
 if(-not $S.PSObject.Properties['Dialog'] -or $null -eq $S.Dialog){$S.CurrentStep=$S.Controls.Steps.SelectedItem;foreach($Key in @('EditStep','RemoveStep','Up','Down')){$S.Controls[$Key].IsEnabled=($null -ne $S.CurrentStep)};if($null -eq $S.CurrentStep){$S.Controls.Status.Text='Adım ekle ile başlayın. İşlem ve koşulu açılan pencerede düzenleyin.'};return}
 if($S.CurrentStep -and $S.CurrentStep.Operation -eq 'RecipeCondition'){$S.Controls.Fields.Children.Clear();Show-RemoteOpsConditionForm $S.CurrentStep.Values;return}
 Show-RemoteOpsRecipeStepFormCore
}
function Move-RemoteOpsRecipeStep {
 param([int]$Delta)
 $S=$script:RecipeUi;$Selected=$S.Controls.Steps.SelectedItem;if($null -eq $Selected){return};$Units=@(Get-RemoteOpsRecipeUiUnits $S.Draft.Steps);$I=-1
 for($N=0;$N -lt $Units.Count;$N++){if(@($Units[$N].Steps|Where-Object Id -ceq $Selected.Id).Count){$I=$N;break}}
 $J=$I+$Delta;if($I -lt 0 -or $J -lt 0 -or $J -ge $Units.Count){return};$Old=$Units[$I];$Units[$I]=$Units[$J];$Units[$J]=$Old
 $S.Draft.Steps=@(foreach($Unit in $Units){$Unit.Steps});Assert-RemoteOpsRecipeUiScope $S.Draft.Steps;Update-RemoteOpsRecipeStepList;$S.Controls.Steps.SelectedItem=$Selected
}
function Remove-RemoteOpsRecipeAction {
 $S=$script:RecipeUi;$Selected=$S.Controls.Steps.SelectedItem;if($null -eq $Selected){return}
 $Unit=@(Get-RemoteOpsRecipeUiUnits $S.Draft.Steps|Where-Object{@($_.Steps|Where-Object Id -ceq $Selected.Id).Count})[0]
 if($Unit.Steps.Count -gt 2){$S.Controls.Status.Text='Paylaşılan eski koşul grubu korunur; tek adım silinemez. Grup birlikte taşınır.';return}
 $Ids=@($Unit.Steps|ForEach-Object Id);$S.Draft.Steps=@($S.Draft.Steps|Where-Object{$Ids -cnotcontains $_.Id});Update-RemoteOpsRecipeStepList
}
function Add-RemoteOpsRecipeAction {
 $S=$script:RecipeUi;if($S.Draft.Steps.Count -ge 20){$S.Controls.Status.Text='Koşullar dahil en fazla 20 adım eklenebilir.';return}
 $Before=Copy-RemoteOpsRecipeDefinition $S.Draft;$Step=[pscustomobject]@{Id=[guid]::NewGuid().ToString('D');Name='';AutoName=$true;Operation='ServiceList';Values=(New-RemoteOpsRecipeStepValues 'ServiceList')};$Step.Name=Get-RemoteOpsRecipeAutoName $Step
 $S.Draft.Schema='RemoteOps.Recipe/4';$S.Draft.Steps+=,$Step;Update-RemoteOpsRecipeStepList 999;$State=New-RemoteOpsRecipeStepDialog;$State.Before=$Before;[void]$State.Window.ShowDialog()
}
function New-RemoteOpsRecipeStepDialog {
 $S=$script:RecipeUi;$Action=$S.Controls.Steps.SelectedItem;if($null -eq $Action){return};$Before=Copy-RemoteOpsRecipeDefinition $S.Draft
 $Xml=[xml]@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Adımı düzenle" Background="#EFF4F8" FontFamily="Segoe UI" FontSize="12" Width="680" Height="640" MinWidth="460" MinHeight="360" WindowStartupLocation="CenterScreen"><DockPanel Margin="16"><StackPanel DockPanel.Dock="Bottom"><TextBlock x:Name="Error" Foreground="#A44721" TextWrapping="Wrap"/><WrapPanel Margin="0,10,0,0"><Button x:Name="Apply" Content="Uygula" Padding="16,7" Margin="0,0,8,0"/><Button x:Name="Cancel" Content="Vazgeç" Padding="16,7"/></WrapPanel></StackPanel><TabControl Style="{x:Null}" x:Name="Tabs"><TabItem Style="{x:Null}" Header="İşlem"><ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="ActionHost"/></ScrollViewer></TabItem><TabItem Style="{x:Null}" Header="Çalışma koşulu"><ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel><TextBlock x:Name="Scope" TextWrapping="Wrap" Margin="0,0,0,8"/><CheckBox x:Name="Enabled" Content="Bu işlem yalnızca koşul sağlanırsa çalışsın" Margin="0,0,0,8"/><StackPanel x:Name="ConditionHost"/></StackPanel></ScrollViewer></TabItem></TabControl></DockPanel></Window>
'@
 $W=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $Xml));$W.Height=[Math]::Min(640,[Windows.SystemParameters]::WorkArea.Height-40);if($script:Window){$W.Resources=$script:Window.Resources}
 $C=@{};foreach($K in @('Apply','Cancel','Tabs','ActionHost','ConditionHost','Enabled','Scope','Error')){$C[$K]=$W.FindName($K)}
 $Link=[string](Get-RemoteOpsPreviewValue $Action ConditionId '');$Condition=$null
 if($Action.Operation -eq 'RecipeCondition'){$Condition=$Action}else{if($Link){$Condition=@($S.Draft.Steps|Where-Object Id -ceq $Link)[0]}}
 $Shared=$null -ne $Condition -and @($S.Draft.Steps|Where-Object{[string](Get-RemoteOpsPreviewValue $_ ConditionId '') -ceq $Condition.Id}).Count -gt 1
 $State=[pscustomobject]@{Window=$W;Controls=$C;Before=$Before;Action=$Action;Condition=$Condition;Shared=$Shared;Applied=$false;ActionFields=$S.Controls.Fields;Editor=$S.Controls.StepEditor;SelectedId=$Action.Id}
 $S|Add-Member NoteProperty Dialog $State -Force;$Parent=$State.Editor.Parent;[void]$Parent.Children.Remove($State.Editor);$State|Add-Member NoteProperty EditorParent $Parent
 $State.Editor.Visibility='Visible';[void]$C.ActionHost.Children.Add($State.Editor);$S.CurrentStep=$Action;Show-RemoteOpsRecipeStepFormCore;if($Action.Operation -eq 'RecipeCondition'){$S.Controls.Operation.IsEnabled=$false}
 if([bool](Get-RemoteOpsPreviewValue $Action AutoName $false)){$S.Controls.StepName.Text='';$S.Controls.CustomizeName.IsChecked=$false}else{$S.Controls.CustomizeName.IsChecked=$true};Set-RemoteOpsRecipeCustomNameVisibility
 $C.Enabled.IsChecked=($null -ne $Condition);$C.Enabled.IsEnabled=(-not $Shared -and $Action.Operation -ne 'RecipeCondition')
 $C.Scope.Text=if($Shared){'Eski paylaşılan koşul grubu: tek kez değerlendirilir. Düzenleme tüm bağlı adımları etkiler; grup birlikte taşınır.'}elseif($Action.Operation -eq 'RecipeCondition'){'Eski koşul grubu. Mevcut kapsamı korunur.'}else{'Bu işlemin koşulunu burada düzenleyin. Kontrol hedefte okunur.'}
 $C.Enabled.Tag=$State;$C.Enabled.Add_Click({Set-RemoteOpsRecipeDialogCondition $this.Tag})
 $C.Tabs.Tag=$State;$C.Tabs.Add_SelectionChanged({if($_.Source -ne $this){return};Switch-RemoteOpsRecipeDialogTab $this.Tag})
 $C.Apply.Tag=$State;$C.Apply.Add_Click({Complete-RemoteOpsRecipeStepDialog $this.Tag});$C.Cancel.Tag=$State;$C.Cancel.Add_Click({$this.Tag.Window.Close()})
 $W.Tag=$State;$W.Add_Closed({Close-RemoteOpsRecipeStepDialog $this.Tag});Initialize-RemoteOpsRecipeDialogCondition $State
 if($Action.Operation -eq 'RecipeCondition'){$C.Tabs.SelectedIndex=1};return $State
}
function Initialize-RemoteOpsRecipeDialogCondition {
 param($State)
 $S=$script:RecipeUi;$Saved=$S.CurrentStep;$Fields=$S.Controls.Fields
 try{$S.Controls.Fields=$State.Controls.ConditionHost;$S.Controls.Fields.Children.Clear();if($State.Condition){$S.CurrentStep=$State.Condition;Show-RemoteOpsConditionForm $State.Condition.Values}}finally{$S.CurrentStep=$Saved;$S.Controls.Fields=$Fields}
}
function Set-RemoteOpsRecipeDialogCondition {
 param($State)
 if($State.Controls.Enabled.IsChecked -and $null -eq $State.Condition){
  if($script:RecipeUi.Draft.Steps.Count -ge 20){$State.Controls.Enabled.IsChecked=$false;$State.Controls.Error.Text='Koşullar dahil en fazla 20 adım eklenebilir.';return}
  $State.Condition=[pscustomobject]@{Id=[guid]::NewGuid().ToString('D');Name='İşlem koşulu';Operation='RecipeCondition';Values=(New-RemoteOpsConditionUiValues)};Initialize-RemoteOpsRecipeDialogCondition $State
 };$State.Controls.ConditionHost.IsEnabled=[bool]$State.Controls.Enabled.IsChecked
 if($State.Controls.Tabs.SelectedIndex -eq 1){$script:RecipeUi.CurrentStep=$State.Condition}
}
function Switch-RemoteOpsRecipeDialogTab {
 param($State)
 $S=$script:RecipeUi;Save-RemoteOpsRecipeStepForm
 if($State.Controls.Tabs.SelectedIndex -eq 1){$S.CurrentStep=$State.Condition;$S.Controls.Fields=$State.Controls.ConditionHost;$State.Controls.ConditionHost.IsEnabled=[bool]$State.Controls.Enabled.IsChecked}else{$S.CurrentStep=$State.Action;$S.Controls.Fields=$State.ActionFields}
}
function Complete-RemoteOpsRecipeStepDialog {
 param($State)
 $S=$script:RecipeUi
 try{
  Save-RemoteOpsRecipeStepForm
  if($State.Action.Operation -ne 'RecipeCondition'){
   $S.CurrentStep=$State.Action;$S.Controls.Fields=$State.ActionFields;Save-RemoteOpsRecipeStepFormCore
   $Custom=$S.Controls.StepName.Text;$State.Action.Name=if($Custom.Trim()){$Custom}else{Get-RemoteOpsRecipeAutoName $State.Action};if(-not $Custom.Trim() -or $State.Action.PSObject.Properties['AutoName']){$State.Action|Add-Member NoteProperty AutoName (-not [bool]$Custom.Trim()) -Force;$S.Draft.Schema='RemoteOps.Recipe/4'}
   if($State.Condition -and $State.Controls.Enabled.IsChecked){$S.CurrentStep=$State.Condition;Save-RemoteOpsConditionForm
    if(-not @($S.Draft.Steps|Where-Object Id -ceq $State.Condition.Id).Count){$New=@();foreach($Step in $S.Draft.Steps){if($Step.Id -ceq $State.Action.Id){$New+=,$State.Condition};$New+=,$Step};$S.Draft.Steps=$New}
    $State.Action|Add-Member NoteProperty ConditionId $State.Condition.Id -Force;if($S.Draft.Schema -cne 'RemoteOps.Recipe/4'){$S.Draft.Schema='RemoteOps.Recipe/3'}
   }elseif(-not $State.Shared){$Old=[string](Get-RemoteOpsPreviewValue $State.Action ConditionId '');$State.Action.PSObject.Properties.Remove('ConditionId');if($Old){$S.Draft.Steps=@($S.Draft.Steps|Where-Object Id -cne $Old)}}
  };Assert-RemoteOpsRecipeUiScope $S.Draft.Steps;$State.Applied=$true;$State.Window.Close()
 }catch{$State.Controls.Error.Text=$_.Exception.Message}
}
function Close-RemoteOpsRecipeStepDialog {
 param($State)
 $S=$script:RecipeUi;if(-not $State.Applied){$S.Draft=$State.Before};[void]$State.Controls.ActionHost.Children.Remove($State.Editor);$State.Editor.Visibility='Collapsed';[void]$State.EditorParent.Children.Add($State.Editor)
 $S.Controls.Fields=$State.ActionFields;$S.Dialog=$null;$S.CurrentStep=$null;$S.ConditionInputs=$null;Update-RemoteOpsRecipeStepList;$S.Controls.Steps.SelectedItem=@($S.Controls.Steps.Items|Where-Object Id -ceq $State.SelectedId)[0]
}
function Open-RemoteOpsRecipeStepDialog {if($null -ne $script:RecipeUi.Controls.Steps.SelectedItem){$State=New-RemoteOpsRecipeStepDialog;[void]$State.Window.ShowDialog()}}
function Find-RemoteOpsRecipeRowHint {
 param($Root)
 if($Root -is [Windows.Controls.TextBlock] -and $Root.Name -eq 'ScopeHint'){return $Root}
 for($I=0;$I -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($Root);$I++){$Found=Find-RemoteOpsRecipeRowHint ([Windows.Media.VisualTreeHelper]::GetChild($Root,$I));if($Found){return $Found}}
}
function Update-RemoteOpsRecipeRowHints {
 if($null -eq $script:RecipeUi){return};$S=$script:RecipeUi
 foreach($Step in $S.Controls.Steps.Items){
  $Container=$S.Controls.Steps.ItemContainerGenerator.ContainerFromItem($Step);if($null -eq $Container){continue};$Hint=Find-RemoteOpsRecipeRowHint $Container;if($null -eq $Hint){continue}
  $Link=[string](Get-RemoteOpsPreviewValue $Step ConditionId '');$Text='İşlem · düzenlemek için çift tıklayın'
  if($Step.Operation -eq 'RecipeCondition'){$Text='Eski paylaşılan koşul grubu · tek kez değerlendirilir'}elseif($Link){$Condition=@($S.Draft.Steps|Where-Object Id -ceq $Link)[0];if($Condition){$Text='Koşul: '+(@(Get-RemoteOpsConditionPreviewLines $Condition|Select-Object -Skip 2) -join '; ').Trim();if($Text.Length -gt 160){$Text=$Text.Substring(0,157)+'...'}}}
  if($Hint.Text -cne $Text){$Hint.Text=$Text};$Hint.TextWrapping='Wrap'
 }
}

function Set-RemoteOpsRecipeCustomNameVisibility {
 $S=$script:RecipeUi;$C=$S.Controls
 $C.StepNameWrap.Visibility=if($C.CustomizeName.IsChecked){'Visible'}else{'Collapsed'}
 if(-not $S.PSObject.Properties['Dialog'] -or $null -eq $S.Dialog){return}
 if($C.CustomizeName.IsChecked){if(-not $C.StepName.Text.Trim()){$C.StepName.Text=Get-RemoteOpsRecipeAutoName $S.Dialog.Action}}else{$C.StepName.Clear()}
}
