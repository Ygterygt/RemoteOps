function Initialize-RemoteOpsTargetGroupsUi {
    param($Tabs,[string]$CatalogRoot)
    $Xml=[xml]@'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Margin="2">
 <Grid.ColumnDefinitions><ColumnDefinition Width="280"/><ColumnDefinition Width="14"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
 <Border Background="White" BorderBrush="#CFDCE5" BorderThickness="1" CornerRadius="8" Padding="14"><DockPanel>
  <StackPanel DockPanel.Dock="Top"><TextBlock Text="Hedef Grupları" FontSize="22" FontWeight="SemiBold" Foreground="#1F3342"/><TextBlock Text="Kişisel bilgisayar listeleriniz" Foreground="#62778A" Margin="0,4,0,10"/><TextBox x:Name="Search" ToolTip="Grup adı/açıklama ara" MinHeight="30"/><WrapPanel Margin="0,8"><Button x:Name="New" Content="Yeni" Margin="0,0,7,0"/><Button x:Name="Reload" Content="Yenile"/></WrapPanel></StackPanel>
  <TextBlock x:Name="Count" DockPanel.Dock="Bottom" Foreground="#62778A" Margin="0,8,0,0"/>
  <ListBox x:Name="List" DisplayMemberPath="Name" BorderThickness="0" VirtualizingStackPanel.IsVirtualizing="True"/>
 </DockPanel></Border>
 <Border Grid.Column="2" Background="White" BorderBrush="#CFDCE5" BorderThickness="1" CornerRadius="8" Padding="16"><DockPanel>
  <StackPanel DockPanel.Dock="Top"><TextBlock Text="Grup bilgileri" FontSize="22" FontWeight="SemiBold" Foreground="#1F3342"/><TextBlock Text="Kaydetmek hedefe bağlanmaz. Kullanmak için paket/operasyon hedef alanından Ekle veya Değiştir'i seçin." TextWrapping="Wrap" Foreground="#62778A" Margin="0,5,0,12"/></StackPanel>
  <StackPanel DockPanel.Dock="Bottom" Margin="0,10,0,0"><TextBlock x:Name="Status" TextWrapping="Wrap" Foreground="#A44721" MaxHeight="80"/><WrapPanel Margin="0,8,0,0"><Button x:Name="Save" Content="Grubu kaydet" Padding="14,7" Margin="0,0,8,0"/><Button x:Name="Copy" Content="Kopya hazırla" Padding="12,7" Margin="0,0,8,0"/><Button x:Name="Delete" Content="Grubu sil" Padding="12,7"/></WrapPanel></StackPanel>
  <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel><TextBlock Text="Grup adı"/><TextBox x:Name="Name" MinHeight="30" Margin="0,5,0,10"/><TextBlock Text="Açıklama"/><TextBox x:Name="Description" Height="55" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Margin="0,5,0,10"/><TextBlock Text="Hedef bilgisayarlar"/><TextBox x:Name="Targets" MinHeight="120" Height="160" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Margin="0,5,0,5"/><TextBlock Text="Her satıra bir bilgisayar; boşluk, virgül ve noktalı virgül de kullanılabilir. Aynı hedefler tekilleştirilir. Grup içinde parola veya çalıştırma onayı tutulmaz." TextWrapping="Wrap" Foreground="#62778A"/></StackPanel></ScrollViewer>
 </DockPanel></Border>
</Grid>
'@
    $View=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $Xml))
    $Controls=@{};foreach($Name in @('Search','New','Reload','List','Count','Name','Description','Targets','Status','Save','Copy','Delete')){$Controls[$Name]=$View.FindName($Name)}
    $script:TargetGroupUi=[pscustomobject]@{Root=$CatalogRoot;Controls=$Controls;Catalog=$null;Editing=$null;Loading=$false}
    $Tab=New-Object Windows.Controls.TabItem;$Tab.Header='Hedef Grupları';$Tab.Name='TargetGroupsTab';$Tab.Content=$View;[void]$Tabs.Items.Add($Tab)
    $Controls.New.Add_Click({Clear-RemoteOpsTargetGroupEditor})
    $Controls.Reload.Add_Click({Update-RemoteOpsTargetGroupList -Reload})
    $Controls.Search.Add_TextChanged({Update-RemoteOpsTargetGroupList})
    $Controls.List.Add_SelectionChanged({if(-not $script:TargetGroupUi.Loading){Show-RemoteOpsTargetGroupEditor}})
    $Controls.Save.Add_Click({Save-RemoteOpsTargetGroupEditor})
    $Controls.Copy.Add_Click({$C=$script:TargetGroupUi.Controls;$script:TargetGroupUi.Editing=$null;$C.Name.Text=$C.Name.Text+' (kopya)';$C.Status.Text='Kopya henüz kaydedilmedi.';$C.Delete.IsEnabled=$false})
    $Controls.Delete.Add_Click({
        $S=$script:TargetGroupUi;$C=$S.Controls
        if($null -ne $S.Editing -and [Windows.MessageBox]::Show('Yalnızca kişisel grup kaydı silinsin mi? Bilgisayarlarda işlem yapılmaz.','Hedef grubu','YesNo','Question') -eq 'Yes'){
            try{Remove-RemoteOpsTargetGroup $S.Root $S.Editing.Id $S.Editing.Revision;Clear-RemoteOpsTargetGroupEditor;Update-RemoteOpsTargetGroupList -Reload}catch{$C.Status.Text=$_.Exception.Message}
        }
    })
    Update-RemoteOpsTargetGroupList -Reload;Clear-RemoteOpsTargetGroupEditor
    return [pscustomobject]@{Tab=$Tab;Controls=$Controls;Refresh={Update-RemoteOpsTargetGroupList -Reload}}
}
function Clear-RemoteOpsTargetGroupEditor {
    $S=$script:TargetGroupUi;$C=$S.Controls;$S.Editing=$null
    $S.Loading=$true;try{$C.List.SelectedItem=$null}finally{$S.Loading=$false}
    $C.Name.Clear();$C.Description.Clear();$C.Targets.Clear();$C.Status.Text='Yeni grup: kaydetmek için ad ve hedef girin.';$C.Delete.IsEnabled=$false
}
function Update-RemoteOpsTargetGroupList {
    param([switch]$Reload)
    $S=$script:TargetGroupUi;$C=$S.Controls
    if($null -eq $S.Catalog -or $Reload){$S.Catalog=Get-RemoteOpsTargetGroupCatalog $S.Root}
    $Id=if($null -ne $C.List.SelectedItem){$C.List.SelectedItem.Id}else{''}
    $Needle=$C.Search.Text.Trim()
    $Items=@($S.Catalog.Groups|Where-Object{-not $Needle -or $_.Name.IndexOf($Needle,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or $_.Description.IndexOf($Needle,[StringComparison]::OrdinalIgnoreCase) -ge 0})
    $S.Loading=$true
    try{$C.List.ItemsSource=$Items;$Match=@($Items|Where-Object Id -eq $Id);if($Match.Count){$C.List.SelectedItem=$Match[0]}}finally{$S.Loading=$false}
    if($Reload -and $null -ne $C.List.SelectedItem -and $null -ne $S.Editing){Show-RemoteOpsTargetGroupEditor}
    $C.Count.Text=$Items.Count.ToString()+' grup'
    if($S.Catalog.Errors.Count){$C.Status.Text=(@($S.Catalog.Errors|ForEach-Object{$_.Path+' | '+$_.Message}) -join "`r`n")}
}
function Show-RemoteOpsTargetGroupEditor {
    $S=$script:TargetGroupUi;$C=$S.Controls;$Selected=$C.List.SelectedItem
    if($null -eq $Selected){return}
    $S.Editing=$Selected|ConvertTo-Json -Depth 8|ConvertFrom-Json
    $C.Name.Text=$Selected.Name;$C.Description.Text=$Selected.Description;$C.Targets.Text=$Selected.Targets -join "`r`n";$C.Status.Text='Revizyon: '+$Selected.Revision;$C.Delete.IsEnabled=$true
}
function Save-RemoteOpsTargetGroupEditor {
    $S=$script:TargetGroupUi;$C=$S.Controls
    try{
        $Group=New-RemoteOpsTargetGroup $C.Name.Text $C.Description.Text $C.Targets.Text;$Revision=0
        if($null -ne $S.Editing){$Group.Id=$S.Editing.Id;$Group.CreatedAt=$S.Editing.CreatedAt;$Group.Revision=$S.Editing.Revision;$Revision=$S.Editing.Revision}
        $Saved=Save-RemoteOpsTargetGroup $S.Root $Group $Revision
        $C.Search.Clear();Update-RemoteOpsTargetGroupList -Reload;$C.List.SelectedItem=@($C.List.Items|Where-Object Id -eq $Saved.Id)[0];Show-RemoteOpsTargetGroupEditor
        $C.Status.Text='Kaydedildi. '+$Saved.Targets.Count+' bilgisayar | Revizyon: '+$Saved.Revision
    }catch{$C.Status.Text=$_.Exception.Message}
}
function Add-RemoteOpsTargetGroupPicker {
    param($Parent,[Windows.Controls.TextBox]$TargetBox,[string]$CatalogRoot)
    $HostPanel=New-Object Windows.Controls.StackPanel;$HostPanel.Margin='0,6,0,6'
    $Bar=New-Object Windows.Controls.WrapPanel;$Picker=New-Object Windows.Controls.ComboBox;$Picker.Width=190;$Picker.DisplayMemberPath='Name';$Picker.ToolTip='Grup seçimi hedefleri otomatik değiştirmez.';$Picker.Margin='0,0,6,3'
    [void]$Bar.Children.Add($Picker)
    $Controls=@{}
    foreach($Pair in @(@('Add','Ekle'),@('Replace','Değiştir'),@('Refresh','Grupları yenile'))){$Button=New-Object Windows.Controls.Button;$Button.Content=$Pair[1];$Button.Margin='0,0,6,3';$Button.Padding='8,4';$Controls[$Pair[0]]=$Button;[void]$Bar.Children.Add($Button)}
    $Message=New-Object Windows.Controls.TextBlock;$Message.TextWrapping='Wrap';$Message.Foreground=[Windows.Media.Brushes]::DarkOrange;$Message.FontSize=11
    [void]$HostPanel.Children.Add($Bar);[void]$HostPanel.Children.Add($Message);[void]$Parent.Children.Add($HostPanel)
    $State=[pscustomobject]@{Root=$CatalogRoot;TargetBox=$TargetBox;Picker=$Picker;Add=$Controls.Add;Replace=$Controls.Replace;Refresh=$Controls.Refresh;Message=$Message}
    foreach($Button in $Controls.Values){$Button.Tag=$State};$Picker.Tag=$State
    $Controls.Add.Add_Click({Set-RemoteOpsTargetGroupPickerTargets $this.Tag Add})
    $Controls.Replace.Add_Click({Set-RemoteOpsTargetGroupPickerTargets $this.Tag Replace})
    $Controls.Refresh.Add_Click({Update-RemoteOpsTargetGroupPicker $this.Tag})
    $Picker.Add_SelectionChanged({$S=$this.Tag;$S.Add.IsEnabled=$null -ne $this.SelectedItem;$S.Replace.IsEnabled=$null -ne $this.SelectedItem})
    if(Get-Command Add-RemoteOpsTargetTools -ErrorAction SilentlyContinue){Add-RemoteOpsTargetTools $State $HostPanel}
    Update-RemoteOpsTargetGroupPicker $State
    return $State
}
function Update-RemoteOpsTargetGroupPicker {
    param($State)
    $Id=if($null -ne $State.Picker.SelectedItem){$State.Picker.SelectedItem.Id}else{''}
    $Catalog=Get-RemoteOpsTargetGroupCatalog $State.Root;$State.Picker.ItemsSource=$Catalog.Groups
    $Matches=@($Catalog.Groups|Where-Object Id -eq $Id)
    if($Matches.Count){$State.Picker.SelectedItem=$Matches[0]}else{$State.Picker.SelectedItem=$null}
    $State.Add.IsEnabled=$null -ne $State.Picker.SelectedItem;$State.Replace.IsEnabled=$null -ne $State.Picker.SelectedItem
    $State.Message.Text=if($Catalog.Errors.Count){'Bazı gruplar okunamadı. Hedef Grupları sekmesinde Yenile ile ayrıntıları inceleyin.'}elseif($Id -and -not $Matches.Count){'Seçili grup artık mevcut değil; başka grup otomatik seçilmedi.'}else{''}
}
function Set-RemoteOpsTargetGroupPickerTargets {
    param($State,[ValidateSet('Add','Replace')][string]$Mode)
    try{
        $Selected=$State.Picker.SelectedItem;if($null -eq $Selected){throw 'Önce bir hedef grubu seçin.'}
        $Fresh=@((Get-RemoteOpsTargetGroupCatalog $State.Root).Groups|Where-Object Id -eq $Selected.Id)
        if($Fresh.Count -ne 1 -or $Fresh[0].Revision -ne $Selected.Revision){throw 'Grup değişmiş/silinmiş. Grupları yenileyip tekrar seçin.'}
        $Targets=@(Merge-RemoteOpsTargetGroup $State.TargetBox.Text $Fresh[0].Targets $Mode)
        $State.TargetBox.Text=$Targets -join "`r`n";$State.Message.Text=$Targets.Count.ToString()+' bilgisayar hedef alanına aktarıldı.'
    }catch{$State.Message.Text=$_.Exception.Message}
}
