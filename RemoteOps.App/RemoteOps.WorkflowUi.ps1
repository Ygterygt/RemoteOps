# Single-operator presentation helpers. Never dispatch requests or probe endpoints.
function Add-RemoteOpsTargetTools {
 param($State,$Parent)
 $Summary=New-Object Windows.Controls.TextBlock;$Summary.Foreground=[Windows.Media.Brushes]::SlateGray;$Summary.TextWrapping='Wrap';$Summary.Margin='0,4,0,4'
 $Bar=New-Object Windows.Controls.WrapPanel
 foreach($Pair in @(@('Normalize','Tekrarları temizle'),@('Edit','Hedefleri düzenle'),@('Groups','Hedef gruplarına git'))){
  $Button=New-Object Windows.Controls.Button;$Button.Content=$Pair[1];$Button.Padding='8,4';$Button.Margin='0,0,6,3';$Button.Tag=$State
  Add-Member -InputObject $State -NotePropertyName $Pair[0] -NotePropertyValue $Button;[void]$Bar.Children.Add($Button)
 }
 Add-Member -InputObject $State -NotePropertyName Summary -NotePropertyValue $Summary
 [void]$Parent.Children.Add($Summary);[void]$Parent.Children.Add($Bar)
 $State.Normalize.Add_Click({$S=$this.Tag;try{$Targets=@(ConvertTo-RemoteOpsTargets $S.TargetBox.Text);$S.TargetBox.Text=$Targets -join "`r`n";$S.Message.Text='Hedefler düzenlendi. Çalıştırma başlatılmadı.'}catch{$S.Message.Text=$_.Exception.Message}})
 $State.Edit.Add_Click({try{$Editor=New-RemoteOpsTargetEditor $this.Tag;[void]$Editor.Window.ShowDialog()}catch{$this.Tag.Message.Text=$_.Exception.Message}})
 $State.Groups.Add_Click({$script:MainTabs.SelectedItem=$script:TargetGroupsUi.Tab})
 Add-Member -InputObject $State.TargetBox -NotePropertyName TargetSelectionState -NotePropertyValue $State
 $State.TargetBox.Add_TextChanged({Update-RemoteOpsTargetSummary $this.TargetSelectionState})
 Update-RemoteOpsTargetSummary $State
}
function Update-RemoteOpsTargetSummary {
 param($State)
 try{
  $Targets=@(ConvertTo-RemoteOpsTargets $State.TargetBox.Text)
  $Entered=@($State.TargetBox.Text -split '[\s,;]+'|Where-Object{$_}).Count
  $State.Summary.Text=('{0} hedef seçili · {1} tekrar · Listeyi düzenlemek hedefte işlem başlatmaz.' -f $Targets.Count,($Entered-$Targets.Count))
 }catch{$State.Summary.Text=$_.Exception.Message}
}
function New-RemoteOpsTargetEditor {
 param($State)
 $Original=$State.TargetBox.Text;$Targets=@(ConvertTo-RemoteOpsTargets $Original)
 $Xml=[xml]@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Hedefleri düzenle" Width="540" Height="520" MinWidth="350" MinHeight="300" WindowStartupLocation="CenterScreen" Background="#EDF1F5" FontFamily="Segoe UI" FontSize="13"><DockPanel Margin="18"><StackPanel DockPanel.Dock="Top"><TextBlock Text="Seçili hedefler" FontSize="22" FontWeight="SemiBold"/><TextBlock Text="Arayın, seçili bilgisayarları çıkarın ve değişikliği uygulayın." TextWrapping="Wrap" Margin="0,7"/><TextBlock Text="Bilgisayar ara"/><TextBox x:Name="Search" Padding="6" Margin="0,4,0,8"/></StackPanel><StackPanel DockPanel.Dock="Bottom"><TextBlock x:Name="Error" Foreground="#A44721" TextWrapping="Wrap" Margin="0,8"/><WrapPanel><Button x:Name="Remove" Content="Seçileni çıkar" Padding="10,7" Margin="0,0,8,5"/><Button x:Name="Apply" Content="Listeyi uygula" Padding="10,7" Margin="0,0,8,5"/><Button x:Name="Cancel" Content="Vazgeç" Padding="10,7"/></WrapPanel></StackPanel><ListBox x:Name="List" SelectionMode="Extended"/></DockPanel></Window>
'@
 $W=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $Xml));$C=@{}
 $W.Resources=$script:Window.Resources
 foreach($Name in @('Search','List','Error','Remove','Apply','Cancel')){$C[$Name]=$W.FindName($Name)}
 $S=[pscustomobject]@{Window=$W;Controls=$C;Picker=$State;Original=$Original;Targets=$Targets}
 foreach($Control in $C.Values){$Control.Tag=$S}
 $C.List.ItemsSource=$Targets
 $C.Search.Add_TextChanged({$S=$this.Tag;$Query=$this.Text;$S.Controls.List.ItemsSource=@($S.Targets|Where-Object{$_.IndexOf($Query,[StringComparison]::OrdinalIgnoreCase) -ge 0})})
 $C.Remove.Add_Click({$S=$this.Tag;$Removed=@($S.Controls.List.SelectedItems);$S.Targets=@($S.Targets|Where-Object{$_ -notin $Removed});$Query=$S.Controls.Search.Text;$S.Controls.List.ItemsSource=@($S.Targets|Where-Object{$_.IndexOf($Query,[StringComparison]::OrdinalIgnoreCase) -ge 0})})
 $C.Apply.Add_Click({$S=$this.Tag;if($S.Picker.TargetBox.Text -cne $S.Original){$S.Controls.Error.Text='Hedef alanı değişti. Pencereyi kapatıp güncel listeyi yeniden açın.';return};$S.Picker.TargetBox.Text=$S.Targets -join "`r`n";$S.Window.Close()})
 $C.Cancel.Add_Click({$this.Tag.Window.Close()})
 $Area=[Windows.SystemParameters]::WorkArea;$W.Height=[Math]::Min(520,$Area.Height-40);$W.Width=[Math]::Min(540,$Area.Width-32)
 return $S
}
function Get-RemoteOpsFilteredTargets {
 param([object[]]$Rows,[string]$Computer='',[string]$Outcome='')
 foreach($Row in $Rows){
  $Code=[string](Get-OptionalPropertyValue $Row 'OutcomeCode');if(-not $Code){$Code=[string]$Row.Outcome}
  if($Computer -and ([string]$Row.ComputerName).IndexOf($Computer,[StringComparison]::OrdinalIgnoreCase) -lt 0){continue}
  if($Outcome -and $Code -ne $Outcome){continue}
  $Row
 }
}
function Initialize-RemoteOpsWorkflowUi {
 $Bar=New-Object Windows.Controls.WrapPanel;$Bar.Margin='0,6,0,2'
 $Search=New-Object Windows.Controls.TextBox;$Search.Width=145;$Search.Margin='0,0,8,4';$Search.ToolTip='Bilgisayar adında ara'
 $Outcome=New-Object Windows.Controls.ComboBox;$Outcome.Width=170;$Outcome.DisplayMemberPath='Label';$Outcome.SelectedValuePath='Value';$Outcome.Margin='0,0,8,4'
 foreach($Pair in @(@('','Tüm sonuçlar'),@('Success','Başarılı'),@('Error','Hata'),@('Failed','Başarısız'),@('Unreachable','Erişilemedi'),@('Indeterminate','Belirsiz'),@('Skipped','Atlandı'),@('RebootRequired','Yeniden başlatma'),@('Cancelled','İptal'))){[void]$Outcome.Items.Add([pscustomobject]@{Value=$Pair[0];Label=$Pair[1]})};$Outcome.SelectedIndex=0
 $Label=New-Object Windows.Controls.TextBlock;$Label.Text='Bilgisayar / sonuç';$Label.Margin='0,4,8,0';[void]$Bar.Children.Add($Label);[void]$Bar.Children.Add($Search);[void]$Bar.Children.Add($Outcome)
 $C=@{Search=$Search;Outcome=$Outcome}
 foreach($Pair in @(@('Reset','Filtreleri temizle'),@('Diagnose','Seçili sonucu teşhis et'),@('Recovery','Seçili hedefin yedekleri'))){$B=New-Object Windows.Controls.Button;$B.Content=$Pair[1];$B.Padding='8,4';$B.Margin='0,0,7,4';[void]$Bar.Children.Add($B);$C[$Pair[0]]=$B}
 $Message=New-Object Windows.Controls.TextBlock;$Message.TextWrapping='Wrap';$Message.Foreground=[Windows.Media.Brushes]::DarkOrange;$C.Message=$Message
 $Parent=$script:SelectedRunSummary.Parent;[void]$Parent.Children.Add($Bar);[void]$Parent.Children.Add($Message)
 $script:WorkflowUi=[pscustomobject]$C
 $Search.Add_TextChanged({Update-RemoteOpsRunSelection});$Outcome.Add_SelectionChanged({Update-RemoteOpsRunSelection})
 $C.Reset.Add_Click({$script:WorkflowUi.Search.Clear();$script:WorkflowUi.Outcome.SelectedIndex=0;Update-RemoteOpsRunSelection})
 $C.Diagnose.Add_Click({Open-RemoteOpsSelectedTargetDiagnosis})
 $C.Recovery.Add_Click({if($null -ne $script:DeploymentTargets.SelectedItem){Open-RemoteOpsComputerRecovery ([string]$script:DeploymentTargets.SelectedItem.ComputerName)}})
 $script:DeploymentTargets.Add_SelectionChanged({$S=$script:WorkflowUi;$Selected=$null -ne $script:DeploymentTargets.SelectedItem;$S.Diagnose.IsEnabled=$Selected;$S.Recovery.IsEnabled=$Selected;$S.Message.Text=''})
 $C.Diagnose.IsEnabled=$false;$C.Recovery.IsEnabled=$false
 # History already offers run filters; this adds target-level filtering without changing saved evidence.
 $HC=$script:HistoryControls
 $TargetBar=New-Object Windows.Controls.WrapPanel
 $TargetSearch=New-Object Windows.Controls.TextBox;$TargetSearch.Width=125;$TargetSearch.ToolTip='Hedef bilgisayar ara';$TargetSearch.Margin='0,0,5,4'
 $TargetOutcome=New-Object Windows.Controls.ComboBox;$TargetOutcome.Width=140;$TargetOutcome.DisplayMemberPath='Label';$TargetOutcome.SelectedValuePath='Value';$TargetOutcome.Margin='0,0,5,4'
 foreach($Item in $Outcome.Items){[void]$TargetOutcome.Items.Add([pscustomobject]@{Value=$Item.Value;Label=$Item.Label})};$TargetOutcome.SelectedIndex=0
 $Clear=New-Object Windows.Controls.Button;$Clear.Content='Temizle';$Clear.Padding='6,3'
 foreach($Control in @($TargetSearch,$TargetOutcome,$Clear)){[void]$TargetBar.Children.Add($Control)}
 [Windows.Controls.DockPanel]::SetDock($TargetBar,'Top');$HC.Targets.Parent.Children.Insert(0,$TargetBar)
 $script:WorkflowHistory=[pscustomobject]@{Search=$TargetSearch;Outcome=$TargetOutcome}
 $TargetSearch.Add_TextChanged({Update-RemoteOpsHistoryTargetFilter});$TargetOutcome.Add_SelectionChanged({Update-RemoteOpsHistoryTargetFilter})
 $Clear.Add_Click({$script:WorkflowHistory.Search.Clear();$script:WorkflowHistory.Outcome.SelectedIndex=0;Update-RemoteOpsHistoryTargetFilter})
 $Recovery=New-Object Windows.Controls.Button;$Recovery.Content='Hedefin yedekleri';$Recovery.Padding='10,5';$Recovery.Margin='8,0,0,0'
 [void]$HC.Diagnose.Parent.Children.Add($Recovery);$Recovery.Add_Click({if($null -ne $script:HistoryControls.Targets.SelectedItem){Open-RemoteOpsComputerRecovery ([string]$script:HistoryControls.Targets.SelectedItem.ComputerName)}})
 $Recovery.IsEnabled=$false;$HC.Targets.Add_SelectionChanged({$this.Tag.IsEnabled=$null -ne $this.SelectedItem});$HC.Targets.Tag=$Recovery
 $DiagRecovery=New-Object Windows.Controls.Button;$DiagRecovery.Content='Bu hedefin yedekleri';$DiagRecovery.Padding='10,5';$DiagRecovery.Margin='8,0,0,0'
 [void]$HC.Back.Parent.Children.Add($DiagRecovery)
 $DiagRecovery.IsEnabled=$false;$HC.DiagTarget.Tag=$DiagRecovery
 $HC.DiagTarget.Add_SelectionChanged({$this.Tag.IsEnabled=$null -ne $this.SelectedItem})
 $DiagRecovery.Add_Click({if($null -ne $script:HistoryControls.DiagTarget.SelectedItem){Open-RemoteOpsComputerRecovery ([string]$script:HistoryControls.DiagTarget.SelectedItem.ComputerName)}})
}
function Update-RemoteOpsHistoryTargetFilter {
 if(-not (Get-Variable WorkflowHistory -Scope Script -ErrorAction SilentlyContinue)){return}
 $S=$script:HistoryState;$F=$script:WorkflowHistory;$C=$script:HistoryControls
 $Computer=if($null -ne $C.Targets.SelectedItem){[string]$C.Targets.SelectedItem.ComputerName}else{''}
 $Rows=if($null -ne $S.Details){@($S.Details.Targets)}else{@()}
 $C.Targets.ItemsSource=@(Get-RemoteOpsFilteredTargets $Rows $F.Search.Text ([string]$F.Outcome.SelectedItem.Value))
 $Match=@($C.Targets.Items|Where-Object ComputerName -eq $Computer);if($Match.Count){$C.Targets.SelectedItem=$Match[0]}
 Update-RemoteOpsHistoryTarget
}
function Open-RemoteOpsComputerRecovery {
 param([string]$Computer)
 if(-not $Computer){return}
 $C=$script:RecoveryUi.Controls;$C.Computer.Text=$Computer;$C.Kind.SelectedIndex=0;$C.Availability.SelectedIndex=0;$C.From.SelectedDate=$null;$C.To.SelectedDate=$null
 Update-RemoteOpsRecoveryUi -Reload;$C.List.SelectedItem=$null;$script:MainTabs.SelectedItem=$script:RecoveryUi.Tab
}
function Open-RemoteOpsSelectedTargetDiagnosis {
 $Row=$script:DeploymentTargets.SelectedItem;if($null -eq $Row){return}
 $script:WorkflowUi.Message.Text=''
 try{
  $Run=$script:MonitorRuns[[string]$Row.MonitorRunId];$Ref=[string]$Run.ProgressPath+'.reportroot'
  if(-not (Test-Path -LiteralPath $Ref)){throw 'Bu çalışma için rapor henüz oluşmadı. İş tamamlandığında yeniden deneyin.'}
  $ReportRoot=Resolve-RemoteOpsHistoryPath $script:DataRoot ([IO.File]::ReadAllText($Ref).Trim())
  Update-RemoteOpsHistoryView -Reload
  $Matches=@($script:HistoryState.Index.Runs|Where-Object {$_.OperationID -ceq (Split-Path $ReportRoot -Leaf) -and $_.ReportRoot -and ([IO.Path]::GetFullPath($_.ReportRoot)).Equals([IO.Path]::GetFullPath($ReportRoot),[StringComparison]::OrdinalIgnoreCase)})
  if($Matches.Count -ne 1){throw 'Seçili çalışmanın geçmiş kaydı bulunamadı veya kimliği belirsiz.'}
  $C=$script:HistoryControls;$C.DiagRun.SelectedItem=$Matches[0];Update-RemoteOpsDiagnosisRun
  $Targets=@($C.DiagTarget.Items|Where-Object ComputerName -eq $Row.ComputerName)
  if($Targets.Count -ne 1){$C.DiagTarget.SelectedItem=$null;throw 'Seçili hedef için teşhis kaydı henüz oluşmadı.'}
  $C.DiagTarget.SelectedItem=$Targets[0];$script:MainTabs.SelectedItem=$script:HistoryUi.DiagnosticsTab
 }catch{$script:WorkflowUi.Message.Text=$_.Exception.Message}
}
