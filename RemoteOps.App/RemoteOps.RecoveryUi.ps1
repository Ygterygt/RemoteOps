function Initialize-RemoteOpsRecoveryUi {
 param($Tabs,[string]$BasePath)
 $Xml=[xml]@'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Margin="6">
 <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
 <StackPanel Margin="4,4,4,10"><TextBlock Text="Geri Alma Merkezi" FontSize="23" FontWeight="SemiBold" Foreground="#1F3342"/><TextBlock Text="Yerel yedekleri inceleyin, seçilen bilgisayarın kaydedilmiş kapsamını geri alın." Foreground="#62778A" TextWrapping="Wrap" Margin="0,4"/>
 <WrapPanel>
 <StackPanel Margin="0,3,7,3"><TextBlock Text="Bilgisayar"/><TextBox x:Name="Computer" Width="120" ToolTip="Bilgisayar ara"/></StackPanel>
 <StackPanel Margin="0,3,7,3"><TextBlock Text="Yedek türü"/><ComboBox x:Name="Kind" Width="140"/></StackPanel>
 <StackPanel Margin="0,3,7,3"><TextBlock Text="Yerel durum"/><ComboBox x:Name="Availability" Width="140"/></StackPanel>
 <StackPanel Margin="0,3,7,3"><TextBlock Text="Başlangıç"/><DatePicker x:Name="From" Width="115"/></StackPanel>
 <StackPanel Margin="0,3,7,3"><TextBlock Text="Bitiş (dahil)"/><DatePicker x:Name="To" Width="115"/></StackPanel>
 <Button x:Name="Reload" Content="Yenile" Padding="12,5" VerticalAlignment="Bottom" Margin="0,3"/></WrapPanel>
 <TextBlock x:Name="Status" TextWrapping="Wrap" Foreground="#62778A" Margin="0,6,0,0"/></StackPanel>
 <Grid Grid.Row="1"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
 <DockPanel><WrapPanel DockPanel.Dock="Bottom" Margin="6,10"><Button x:Name="Previous" Content="Önceki" Padding="12,5"/><TextBlock x:Name="Page" VerticalAlignment="Center" Margin="12,0"/><Button x:Name="Next" Content="Sonraki" Padding="12,5"/></WrapPanel><ListBox x:Name="List" HorizontalContentAlignment="Stretch" ScrollViewer.HorizontalScrollBarVisibility="Disabled"><ListBox.ItemTemplate><DataTemplate><Border Padding="10" BorderBrush="#DFE7ED" BorderThickness="0,0,0,1"><StackPanel><TextBlock Text="{Binding ComputerName}" FontSize="15" FontWeight="SemiBold"/><TextBlock Text="{Binding Kind}" Foreground="#366888"/><TextBlock Text="{Binding RecordedAt, StringFormat={}{0:dd.MM.yyyy HH:mm}}"/><TextBlock Text="{Binding Summary}" TextWrapping="Wrap" MaxHeight="48"/><TextBlock Text="{Binding AvailabilityLabel}" Foreground="#62778A"/><TextBlock Text="{Binding HistoryLabel}" TextWrapping="Wrap" Foreground="#31536B"/><TextBlock Text="{Binding LiveLabel}" TextWrapping="Wrap" Foreground="#62778A"/><TextBlock Text="{Binding UnavailableReason}" TextWrapping="Wrap" Foreground="#A44721" MaxHeight="45"/></StackPanel></Border></DataTemplate></ListBox.ItemTemplate></ListBox></DockPanel>
 <GridSplitter Grid.Column="1" Width="5" HorizontalAlignment="Center" VerticalAlignment="Stretch" Background="#CFDCE5" ResizeBehavior="PreviousAndNext"/><DockPanel Grid.Column="2"><Button x:Name="Preview" Content="Geri almayı önizle" DockPanel.Dock="Bottom" HorizontalAlignment="Left" Padding="18,9" Margin="0,10,0,0" IsEnabled="False"/><ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel><StackPanel x:Name="RecoveryCards" Visibility="Collapsed">
 <Border Background="#EAF3FB" CornerRadius="8" Padding="12" Margin="0,0,0,8"><StackPanel><TextBlock Text="YEREL YEDEK" FontWeight="SemiBold" Foreground="#31536B"/><TextBlock x:Name="RecoveryLocal" TextWrapping="Wrap" Margin="0,5,0,0"/></StackPanel></Border>
 <Border Background="White" CornerRadius="8" Padding="12" Margin="0,0,0,8"><StackPanel><TextBlock Text="SON GERİ ALMA KAYDI" FontWeight="SemiBold" Foreground="#31536B"/><TextBlock x:Name="RecoveryHistory" TextWrapping="Wrap" Margin="0,5,0,0"/></StackPanel></Border>
 <Border Background="#FFF5E6" CornerRadius="8" Padding="12" Margin="0,0,0,8"><StackPanel><TextBlock Text="HEDEFİN GÜNCEL DURUMU" FontWeight="SemiBold" Foreground="#81551A"/><TextBlock x:Name="RecoveryLive" TextWrapping="Wrap" Margin="0,5,0,0"/><TextBlock x:Name="RecoveryNext" TextWrapping="Wrap" Margin="0,8,0,0"/></StackPanel></Border>
 </StackPanel><Expander Header="Kapsam ve teknik ayrıntılar"><TextBox x:Name="Details" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Padding="12" Background="White" BorderBrush="#CFDCE5" Text="Ayrıntılar için bir kayıt seçin."/></Expander></StackPanel></ScrollViewer></DockPanel>
 </Grid>
</Grid>
'@
 $View=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $Xml));$C=@{}
 foreach($Name in @('Computer','Kind','Availability','From','To','Reload','Status','List','Details','Preview','Previous','Next','Page','RecoveryCards','RecoveryLocal','RecoveryHistory','RecoveryLive','RecoveryNext')){$C[$Name]=$View.FindName($Name)}
 $C.Kind.ItemsSource=@('Tüm türler','FileRestore','FileRollback','Registry','Service','ScheduledTask','Unsupported');$C.Kind.SelectedIndex=0
 $C.Availability.ItemsSource=@('Tüm kayıtlar','Kullanılabilir','Kullanılamaz');$C.Availability.SelectedIndex=0
 $Tab=New-Object Windows.Controls.TabItem;$Tab.Header='Geri Alma Merkezi';$Tab.Name='RecoveryTab';$Tab.Content=$View;[void]$Tabs.Items.Add($Tab)
 $script:RecoveryUi=[pscustomobject]@{Tab=$Tab;Root=$BasePath;Controls=$C;Index=$null;Page=0;Loading=$false}
 $C.Reload.Add_Click({Update-RemoteOpsRecoveryUi -Reload})
 $C.Computer.Add_TextChanged({$script:RecoveryUi.Page=0;Update-RemoteOpsRecoveryUi})
 foreach($Name in @('Kind','Availability')){$C[$Name].Add_SelectionChanged({$script:RecoveryUi.Page=0;Update-RemoteOpsRecoveryUi})}
 foreach($Name in @('From','To')){$C[$Name].Add_SelectedDateChanged({$script:RecoveryUi.Page=0;Update-RemoteOpsRecoveryUi})}
 $C.Previous.Add_Click({$script:RecoveryUi.Page--;Update-RemoteOpsRecoveryUi});$C.Next.Add_Click({$script:RecoveryUi.Page++;Update-RemoteOpsRecoveryUi})
 $C.List.Add_SelectionChanged({if(-not $script:RecoveryUi.Loading){Show-RemoteOpsRecoveryDetails}})
 $C.Preview.Add_Click({try{$State=New-RemoteOpsRecoveryPreviewWindow $script:RecoveryUi.Controls.List.SelectedItem;[void]$State.Window.ShowDialog()}catch{$script:RecoveryUi.Controls.Status.Text=$_.Exception.Message}})
 $Tabs.Add_SelectionChanged({if($script:RecoveryUi.Tab.IsSelected -and $null -eq $script:RecoveryUi.Index){Update-RemoteOpsRecoveryUi -Reload}})
 Add-Member -InputObject $script:RecoveryUi -NotePropertyName Refresh -NotePropertyValue {Update-RemoteOpsRecoveryUi -Reload};return $script:RecoveryUi
}
function Update-RemoteOpsRecoveryUi {
 param([switch]$Reload)
 $S=$script:RecoveryUi;$C=$S.Controls
 if($null -eq $S.Index -and -not $Reload){return}
 try{
  $Id=if($null -ne $C.List.SelectedItem){$C.List.SelectedItem.Id}else{''}
  if($Reload){$S.Index=Get-RemoteOpsRecoveryIndex $S.Root}
  $Args=@{Records=$S.Index.Records;Computer=$C.Computer.Text.Trim();Page=$S.Page;PageSize=50}
  if($C.Kind.SelectedIndex -gt 0){$Args.Kind=[string]$C.Kind.SelectedItem}
  if($C.Availability.SelectedIndex -gt 0){$Args.Availability=if($C.Availability.SelectedIndex -eq 1){'Available'}else{'Unavailable'}}
  if($null -ne $C.From.SelectedDate){$Args.From=$C.From.SelectedDate}
  if($null -ne $C.To.SelectedDate){$Args.To=([datetime]$C.To.SelectedDate).Date.AddDays(1).AddTicks(-1)}
  $Result=Find-RemoteOpsRecoveryRecords @Args;$S.Page=$Result.Page
  $S.Loading=$true;try{$C.List.ItemsSource=@($Result.Items);$Match=@($Result.Items|Where-Object Id -eq $Id);if($Match.Count){$C.List.SelectedItem=$Match[0]}}finally{$S.Loading=$false}
  $C.Page.Text=('{0} / {1}' -f ($Result.Page+1),[Math]::Max(1,[Math]::Ceiling($Result.Total/50)))
  $C.Previous.IsEnabled=$S.Page -gt 0;$C.Next.IsEnabled=(($S.Page+1)*50 -lt $Result.Total)
  $C.Status.Text=('{0} kayıt | {1} sorun. Yerel kullanılabilirlik, hedefe erişim veya canlı durum garantisi değildir.' -f $Result.Total,$S.Index.Issues.Count)
  Show-RemoteOpsRecoveryDetails
 }catch{
  $Message=$_.Exception.Message
  $C.List.SelectedItem=$null
  Show-RemoteOpsRecoveryDetails
  $C.Status.Text=$Message;$C.Preview.IsEnabled=$false
 }
}
function Format-RemoteOpsRecoveryDetails {
 param($Details)
 $R=$Details.Record
 $Lines=@('YEREL YEDEK DURUMU', $R.LocalLabel, '', 'GERİ ALMA GEÇMİŞİ', $R.HistoryLabel, '', 'HEDEFİN GÜNCEL DURUMU', $R.LiveLabel, '', 'NE YAPMALIYIM?', $R.NextAction, '', "Bilgisayar: $($R.ComputerName)","Tür: $($R.Kind)","Tarih: $($R.RecordedAt.ToString('dd.MM.yyyy HH:mm'))","Kapsam: $($R.Summary)",'',"Manifest: $($R.ManifestPath)",'','Kaydedilen işlem sonrası durum → geri yüklenecek eski durum (canlı sorgu değildir):')
 foreach($Entry in $Details.Entries){
  switch($R.Kind){
   Registry {$Old=if($Entry.OldExists -eq 'True'){'['+(Get-RemoteOpsManifestField $Entry OldType 'REG_SZ')+'] '+(ConvertTo-Json -InputObject ([string]$Entry.OldValue) -Compress)}else{'[değer yok]'};$Lines+=((Get-RemoteOpsRegistryManifestPath $Entry).FullPath+' ['+$Entry.ValueName+']: '+(Get-RemoteOpsManifestField $Entry NewValue '[bilinmiyor]')+' → '+$Old)}
   Service {$Lines+=($Entry.ObjectName+': '+$Entry.Action+' → '+(Get-RemoteOpsManifestField $Entry OldState)+' '+(Get-RemoteOpsManifestField $Entry OldStartMode))}
   ScheduledTask {$Lines+=($Entry.TaskPath+$Entry.TaskName+': '+$Entry.Action+' → '+$(if($Entry.Action -eq 'Delete'){'XML yedeğini kaydet (var olan görev ezilmez)'}else{'Enabled='+$Entry.OldEnabled}))}
   default {$Lines+=($Entry.OriginalPath+' ← '+$Entry.BackupPath+$(if((Get-RemoteOpsManifestField $Entry Action) -eq 'Move'){' | Taşınan konum: '+$Entry.ChangedPath}else{''}))}
  }
 }
 $Lines+=@('','Gerekli yerel yedekler:')+@($Details.BackupArtifacts)+@('',('Yerel durum: '+$(if($R.Available){'Kullanılabilir'}else{$R.UnavailableReason})),'','Dosyalarda aynı adlı içeriklerin üzerine yazılabilir. Klasör geri yükleme hedefteki ek dosyaları silmez. Kaydedilen eski servis/registry durumu uygulanır; daha sonraki değişiklikler etkilenebilir. Otomatik geri alma zinciri yoktur.')
 $Lines -join "`r`n"
}
function Show-RemoteOpsRecoveryDetails {
 $S=$script:RecoveryUi;$C=$S.Controls;$R=$C.List.SelectedItem;$C.Preview.IsEnabled=$false
 $C.RecoveryCards.Visibility='Collapsed';foreach($Name in @('RecoveryLocal','RecoveryHistory','RecoveryLive','RecoveryNext')){$C[$Name].Text=''}
 if($null -eq $R){$C.Details.Text='Ayrıntılar için bir kayıt seçin.';return}
 try{$Details=Get-RemoteOpsRecoveryDetails $S.Root $R;$C.Details.Text=Format-RemoteOpsRecoveryDetails $Details;$C.RecoveryLocal.Text=$Details.Record.LocalLabel;$C.RecoveryHistory.Text=$Details.Record.HistoryLabel;$C.RecoveryLive.Text=$Details.Record.LiveLabel;$C.RecoveryNext.Text=$Details.Record.NextAction;$C.RecoveryCards.Visibility='Visible';$C.Preview.IsEnabled=$Details.Record.Available}catch{$C.Details.Text=$_.Exception.Message}
}
function New-RemoteOpsRecoveryPreviewWindow {
 param($Record)
 if($null -eq $Record){throw 'Önce bir kayıt seçin.'}
 $Request=New-RemoteOpsRecoveryRequest $script:RecoveryUi.Root $Record
 $Op=@($script:OperationCatalog|Where-Object Name -eq $Request.Operation)[0]
 $Settings=Get-RemoteOpsPreviewUiSettings $Op
 $Preview=New-RemoteOpsOperationPreview $Op $Request.Values $script:ProfileList.SelectedItem $Settings.Parallelism $Settings.CleanupLogs
 $Xml=[xml]@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Geri alma önizlemesi" Width="780" Height="650" MinWidth="480" MinHeight="350" WindowStartupLocation="CenterScreen" Background="#EFF4F8"><DockPanel Margin="18"><TextBlock DockPanel.Dock="Top" Text="Seçilen kapsamı geri al" FontSize="24" FontWeight="SemiBold" Foreground="#1F3342" Margin="0,0,0,12"/><StackPanel DockPanel.Dock="Bottom" Margin="0,10,0,0"><TextBlock x:Name="Prompt" TextWrapping="Wrap"/><TextBox x:Name="Confirm" MinHeight="30" Margin="0,6,0,6"/><TextBlock x:Name="Error" Foreground="#A44721" TextWrapping="Wrap" MaxHeight="60"/><WrapPanel Margin="0,8,0,0"><Button x:Name="Start" Content="İnceledim, başlat" Padding="18,9" Margin="0,0,10,0"/><Button x:Name="Cancel" Content="Vazgeç" Padding="18,9"/></WrapPanel></StackPanel><TextBox x:Name="Text" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Padding="12"/></DockPanel></Window>
'@
 $W=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $Xml));$Area=[Windows.SystemParameters]::WorkArea;$W.Width=[Math]::Min(780,$Area.Width-32);$W.Height=[Math]::Min(650,$Area.Height-40)
 $C=@{};foreach($Name in @('Prompt','Confirm','Error','Start','Cancel','Text')){$C[$Name]=$W.FindName($Name)}
 $Word=if($Request.Operation -eq 'FileRestore'){'RESTORE'}else{'ROLLBACK'};$C.Prompt.Text='Başlatmak için yazın: '+$Word
 $C.Text.Text=(Format-RemoteOpsOperationPreview $Preview)+"`r`n`r`n"+(Format-RemoteOpsRecoveryDetails (Get-RemoteOpsRecoveryDetails $script:RecoveryUi.Root $Record))
 $State=[pscustomobject]@{Window=$W;Controls=$C;Preview=$Preview;Values=(Copy-RemoteOpsPreviewInputValues $Request.Values);Selection=$Request.Selection;Record=$Record;Started=$false;Word=$Word}
 $C.Start.Tag=$State;$C.Cancel.Tag=$State;$C.Cancel.Add_Click({$this.Tag.Window.Close()});$C.Start.Add_Click({Start-RemoteOpsReviewedRecovery $this.Tag})
 return $State
}
function Start-RemoteOpsReviewedRecovery {
 param($State)
 if($State.Started){return}
 try{
  if($State.Controls.Confirm.Text -cne $State.Word){throw ('Başlatmak için yazın: '+$State.Word)}
  $Selected=$script:RecoveryUi.Controls.List.SelectedItem
  if($null -eq $Selected -or $Selected.Id -cne $State.Selection.RecordId){throw 'Seçili kayıt değişti. Önizlemeyi yeniden açın.'}
  $Request=New-RemoteOpsRecoveryRequest $script:RecoveryUi.Root $State.Record
  $Op=@($script:OperationCatalog|Where-Object Name -eq $Request.Operation)[0];$Settings=Get-RemoteOpsPreviewUiSettings $Op
  if(-not(Test-RemoteOpsOperationPreviewCurrent $State.Preview $Op $Request.Values $script:ProfileList.SelectedItem $Settings.Parallelism $Settings.CleanupLogs)){throw 'Hesap, kapsam veya ayarlar değişti. Önizlemeyi yeniden açın.'}
  $Values=Copy-RemoteOpsPreviewInputValues $State.Values;$Values.Confirm=$State.Controls.Confirm.Text
  [void](Assert-RemoteOpsRecoveryDispatch $script:RecoveryUi.Root $Values $Op.Name @($Request.Targets))
  $State.Controls.Start.IsEnabled=$false
  Start-RemoteOpsRequest -Operation $State.Preview.Operation -Values $Values
  $State.Started=$true;$State.Window.Close()
 }catch{$State.Controls.Error.Text=$_.Exception.Message;if(-not $State.Started){$State.Controls.Start.IsEnabled=$true}}
}
