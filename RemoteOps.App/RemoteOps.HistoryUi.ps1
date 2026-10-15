. (Join-Path $PSScriptRoot 'RemoteOps.StepResults.ps1')
# UI state is separate from active-run monitoring and never dispatches requests.
function New-RemoteOpsHistoryView {
    param([string]$Xaml)
    $Xml=[xml]$Xaml;$View=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $Xml))
    $Ns=New-Object Xml.XmlNamespaceManager $Xml.NameTable;$Ns.AddNamespace('x','http://schemas.microsoft.com/winfx/2006/xaml')
    foreach($Node in $Xml.SelectNodes('//*[@x:Name]',$Ns)){$Name=$Node.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml');$script:HistoryControls[$Name]=$View.FindName($Name)}
    return $View
}
function Initialize-RemoteOpsHistoryUi {
    param([System.Windows.Controls.TabControl]$Tabs,[string]$BasePath)
    $script:HistoryControls=@{}
    $script:HistoryState=[pscustomobject]@{BasePath=$BasePath;Tabs=$Tabs;Index=$null;Page=0;Loading=$false;Run=$null;Details=$null;DiagRun=$null;DiagDetails=$null;HistoryTab=$null;DiagnosticsTab=$null}
    $History=New-RemoteOpsHistoryView @'
<ScrollViewer xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" x:Name="HistoryScroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"><Grid Margin="2" Height="500">
 <Grid.Resources><Style TargetType="DataGrid"><Setter Property="IsReadOnly" Value="True"/><Setter Property="AutoGenerateColumns" Value="False"/><Setter Property="CanUserAddRows" Value="False"/><Setter Property="SelectionMode" Value="Single"/><Setter Property="EnableRowVirtualization" Value="True"/><Setter Property="EnableColumnVirtualization" Value="True"/><Setter Property="HeadersVisibility" Value="Column"/><Setter Property="Background" Value="White"/><Setter Property="BorderBrush" Value="#CFDCE5"/><Setter Property="RowHeight" Value="29"/></Style><Style TargetType="Button"><Setter Property="Padding" Value="10,5"/><Setter Property="Margin" Value="0,0,7,3"/></Style></Grid.Resources>
 <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="1.2*" MinHeight="85"/><RowDefinition Height="Auto"/><RowDefinition Height="*" MinHeight="90"/></Grid.RowDefinitions>
 <DockPanel><Button x:Name="Reload" Content="Yenile" DockPanel.Dock="Right"/><StackPanel><TextBlock Text="Geçmiş" FontSize="23" FontWeight="SemiBold" Foreground="#1F3342"/><TextBlock Text="Geçmiş çalışmalar, hedef sonuçları ve çıktılar. Gerçek hedefte işlem başlatılmaz." Foreground="#62778A" Margin="0,3,0,7" TextWrapping="Wrap"/></StackPanel></DockPanel>
 <WrapPanel Grid.Row="1" Margin="0,3,0,6" VerticalAlignment="Center">
  <StackPanel Margin="0,0,8,0"><TextBlock Text="Başlangıç"/><DatePicker x:Name="From" Width="115"/></StackPanel>
  <StackPanel Margin="0,0,8,0"><TextBlock Text="Bitiş"/><DatePicker x:Name="To" Width="115"/></StackPanel>
  <StackPanel Margin="0,0,8,0"><TextBlock Text="Operasyon"/><TextBox x:Name="Operation" Width="145" MinHeight="27"/></StackPanel>
  <StackPanel Margin="0,0,8,0"><TextBlock Text="Bilgisayar"/><TextBox x:Name="Computer" Width="130" MinHeight="27"/></StackPanel>
  <StackPanel Margin="0,0,8,0"><TextBlock Text="Sonuç"/><ComboBox x:Name="Outcome" Width="150" MinHeight="27"/></StackPanel>
  <Button x:Name="Apply" Content="Filtrele" VerticalAlignment="Bottom"/><Button x:Name="Reset" Content="Temizle" VerticalAlignment="Bottom"/>
 </WrapPanel>
 <DockPanel Grid.Row="2" Margin="0,0,0,5"><StackPanel DockPanel.Dock="Right" Orientation="Horizontal"><Button x:Name="Prev" Content="Önceki"/><Button x:Name="Next" Content="Sonraki"/></StackPanel><StackPanel><TextBlock x:Name="Count" Foreground="#31536B"/><Expander x:Name="IssuesPanel" Header="Okunamayan kayıtlar / eksik çıktılar" Visibility="Collapsed"><TextBox x:Name="Issues" IsReadOnly="True" TextWrapping="Wrap" MaxHeight="80" VerticalScrollBarVisibility="Auto" Foreground="#A44721"/></Expander></StackPanel></DockPanel>
 <DataGrid x:Name="Runs" Grid.Row="3"><DataGrid.Columns><DataGridTextColumn Header="Tarih" Binding="{Binding CompletedAt}" Width="150"/><DataGridTextColumn Header="Operasyon" Binding="{Binding Operation}" Width="160"/><DataGridTextColumn Header="Paket / reçete" Binding="{Binding PackageName}" Width="*" MinWidth="100"/><DataGridTextColumn Header="Çalışma kimliği" Binding="{Binding OperationID}" Width="235"/><DataGridTextColumn Header="Hesap" Binding="{Binding Identity}" Width="145"/></DataGrid.Columns></DataGrid>
 <WrapPanel Grid.Row="4" Margin="0,9,0,5"><TextBlock Text="Çıktı:" VerticalAlignment="Center" Margin="0,0,6,0"/><ComboBox x:Name="Artifacts" Width="185" DisplayMemberPath="Kind" Margin="0,0,7,3"/><Button x:Name="OpenArtifact" Content="Aç"/><Button x:Name="OpenLogs" Content="Hedef logları"/><Button x:Name="OpenPulled" Content="Çekilen dosyalar"/><Button x:Name="Diagnose" Content="Hata teşhisini aç"/></WrapPanel>
 <Grid Grid.Row="5"><Grid.ColumnDefinitions><ColumnDefinition Width="285"/><ColumnDefinition Width="10"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><DockPanel><TextBlock DockPanel.Dock="Top" Text="Hedef sonuçları" Foreground="#31536B" FontWeight="SemiBold" Margin="0,0,0,5"/><DataGrid x:Name="Targets"><DataGrid.Columns><DataGridTextColumn Header="Bilgisayar" Binding="{Binding ComputerName}" Width="140" MinWidth="100"/><DataGridTextColumn Header="Sonuç" Binding="{Binding Outcome}" Width="130"/></DataGrid.Columns></DataGrid></DockPanel><DockPanel Grid.Column="2"><TextBlock DockPanel.Dock="Top" Text="Seçili hedefin adım sonuçları" Foreground="#31536B" FontWeight="SemiBold" Margin="0,0,0,5"/><DataGrid x:Name="Steps" AutoGenerateColumns="True"/></DockPanel></Grid>
</Grid></ScrollViewer>
'@
    $Diagnosis=New-RemoteOpsHistoryView @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Margin="2">
 <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
 <StackPanel><TextBlock Text="Hata Teşhisi" FontSize="23" FontWeight="SemiBold" Foreground="#1F3342"/><TextBlock Text="Özgün sonuçlar ve önerilen kontroller. Teşhis, hedefte otomatik işlem yapmaz." Foreground="#62778A" TextWrapping="Wrap" Margin="0,4,0,12"/></StackPanel>
 <Grid Grid.Row="1" Margin="0,0,0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="220"/></Grid.ColumnDefinitions><StackPanel><TextBlock Text="Çalışma"/><ComboBox x:Name="DiagRun" DisplayMemberPath="DiagnosisLabel" MinHeight="30"/></StackPanel><StackPanel Grid.Column="2"><TextBlock Text="Bilgisayar"/><ComboBox x:Name="DiagTarget" DisplayMemberPath="ComputerName" MinHeight="30"/></StackPanel></Grid>
 <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto"><StackPanel>
 <Border Background="#EAF3FB" BorderBrush="#C8DEEF" BorderThickness="1" CornerRadius="8" Padding="16" Margin="0,0,0,10"><StackPanel><TextBlock x:Name="DiagOutcome" Text="Sonuç özeti" FontWeight="SemiBold" Foreground="#075A99" Margin="0,0,0,7"/><TextBlock x:Name="DiagReason" Text="Geçmişten bir çalışma ve bilgisayar seçin." TextWrapping="Wrap" FontSize="15" Foreground="#1F3342"/></StackPanel></Border>
 <Border Background="White" BorderBrush="#CFDCE5" BorderThickness="1" CornerRadius="8" Padding="16" Margin="0,0,0,10"><StackPanel><TextBlock Text="NE YAPMALIYIM?" FontWeight="SemiBold" Foreground="#31536B" Margin="0,0,0,7"/><TextBlock x:Name="DiagNextAction" Text="Seçili sonuca ait öneri burada gösterilir." TextWrapping="Wrap" FontSize="14"/></StackPanel></Border>
 <Expander Header="Teknik ayrıntılar ve özgün kayıtlar" Padding="4"><Border Background="White" BorderBrush="#CFDCE5" BorderThickness="1" CornerRadius="6" Padding="14"><TextBox x:Name="Diagnosis" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" BorderThickness="0" Background="Transparent" FontFamily="Segoe UI" FontSize="13" Text="Geçmişten bir çalışma ve bilgisayar seçin."/></Border></Expander></StackPanel></ScrollViewer>
 <WrapPanel Grid.Row="3" Margin="0,12,0,0"><Button x:Name="Back" Content="Geçmişe dön" Padding="15,7" Margin="0,0,8,0"/><Button x:Name="Bundle" Content="Tanı paketi dışa aktar…" Padding="15,7"/><TextBlock Text="  Dosya listesi kaydetmeden önce gösterilir." Foreground="#62778A" VerticalAlignment="Center" TextWrapping="Wrap"/></WrapPanel>
</Grid>
'@
    foreach($Pair in @(@('HistoryTab','Geçmiş',$History),@('DiagnosticsTab','Hata Teşhisi',$Diagnosis))){
        $Tab=New-Object Windows.Controls.TabItem;$Tab.Header=$Pair[1];$Tab.Content=$Pair[2];$Tab.Name=$Pair[0];[void]$Tabs.Items.Add($Tab);$script:HistoryState.($Pair[0])=$Tab
    }
    $C=$script:HistoryControls
    $StepDetail=New-Object Windows.Controls.TextBox;$StepDetail.IsReadOnly=$true;$StepDetail.TextWrapping='Wrap';$StepDetail.VerticalScrollBarVisibility='Auto';$StepDetail.Height=100;$StepDetail.Margin='0,7,0,0';$StepDetail.Background=[Windows.Media.Brushes]::White;$StepDetail.Padding='8';$StepDetail.Visibility='Collapsed'
    [Windows.Controls.DockPanel]::SetDock($StepDetail,'Bottom');$C.Steps.Parent.Children.Insert(1,$StepDetail);$C.Steps.Tag=$StepDetail
    $C.Steps.Add_SelectionChanged({if($null -ne $this.SelectedItem -and $this.SelectedItem.PSObject.Properties['SourceRows']){$this.Tag.Text=Get-RemoteOpsStepViewDetail $this.SelectedItem}})
    $C.HistoryScroll.Add_SizeChanged({$this.Content.Height=[Math]::Max(500,$this.ActualHeight-4)})
    $C.Outcome.DisplayMemberPath='Label';$C.Outcome.SelectedValuePath='Value'
    foreach($Pair in @(@('','Tüm sonuçlar'),@('Success','Başarılı'),@('Error','Hata'),@('Unreachable','Erişilemedi'),@('Indeterminate','Belirsiz'),@('RebootRequired','Yeniden başlatma'),@('Cancelled','İptal'),@('Skipped','Atlandı'))){[void]$C.Outcome.Items.Add([pscustomobject]@{Value=$Pair[0];Label=$Pair[1]})};$C.Outcome.SelectedIndex=0
    $C.Reload.Add_Click({Update-RemoteOpsHistoryView -Reload})
    $C.Apply.Add_Click({$script:HistoryState.Page=0;Update-RemoteOpsHistoryView})
    $C.Reset.Add_Click({$C=$script:HistoryControls;$C.From.SelectedDate=$null;$C.To.SelectedDate=$null;$C.Operation.Clear();$C.Computer.Clear();$C.Outcome.SelectedIndex=0;$script:HistoryState.Page=0;Update-RemoteOpsHistoryView})
    $C.Prev.Add_Click({$script:HistoryState.Page=[Math]::Max(0,$script:HistoryState.Page-1);Update-RemoteOpsHistoryView})
    $C.Next.Add_Click({$script:HistoryState.Page++;Update-RemoteOpsHistoryView})
    $C.Runs.Add_SelectionChanged({if(-not $script:HistoryState.Loading){Update-RemoteOpsHistorySelection}})
    $C.Targets.Add_SelectionChanged({Update-RemoteOpsHistoryTarget})
    $C.Artifacts.Add_SelectionChanged({$script:HistoryControls.OpenArtifact.IsEnabled=$null -ne $script:HistoryControls.Artifacts.SelectedItem})
    $C.OpenArtifact.Add_Click({Open-RemoteOpsHistoryArtifact})
    $C.OpenLogs.Add_Click({Open-RemoteOpsHistoryCollection PulledLogs})
    $C.OpenPulled.Add_Click({Open-RemoteOpsHistoryCollection PulledFiles})
    $C.Diagnose.Add_Click({
        $S=$script:HistoryState;$C=$script:HistoryControls
        if($null -ne $S.Run){$C.DiagRun.SelectedItem=$S.Run;Update-RemoteOpsDiagnosisRun;if($null -ne $C.Targets.SelectedItem){$C.DiagTarget.SelectedItem=@($C.DiagTarget.Items|Where-Object ComputerName -eq $C.Targets.SelectedItem.ComputerName|Select-Object -First 1)[0]};$S.Tabs.SelectedItem=$S.DiagnosticsTab}
    })
    $C.DiagRun.Add_SelectionChanged({if(-not $script:HistoryState.Loading){Update-RemoteOpsDiagnosisRun}})
    $C.DiagTarget.Add_SelectionChanged({Update-RemoteOpsDiagnosisView})
    $C.Back.Add_Click({$script:HistoryState.Tabs.SelectedItem=$script:HistoryState.HistoryTab})
    $C.Bundle.Add_Click({Show-RemoteOpsDiagnosticExport})
    $Tabs.Add_SelectionChanged({if([object]::ReferenceEquals($args[1].OriginalSource,$script:HistoryState.Tabs) -and $script:HistoryState.Tabs.SelectedItem -in @($script:HistoryState.HistoryTab,$script:HistoryState.DiagnosticsTab) -and $null -eq $script:HistoryState.Index){Update-RemoteOpsHistoryView -Reload}})
    Update-RemoteOpsHistorySelection;Update-RemoteOpsDiagnosisView
    return [pscustomobject]@{HistoryTab=$script:HistoryState.HistoryTab;DiagnosticsTab=$script:HistoryState.DiagnosticsTab;Controls=$C;Refresh={Update-RemoteOpsHistoryView -Reload}}
}
function Update-RemoteOpsHistoryView {
    param([switch]$Reload)
    $S=$script:HistoryState;$C=$script:HistoryControls
    if($null -ne $C.From.SelectedDate -and $null -ne $C.To.SelectedDate -and $C.From.SelectedDate -gt $C.To.SelectedDate){$C.Count.Text='Başlangıç tarihi bitiş tarihinden sonra olamaz.';return}
    $Selected=if($null -ne $C.Runs.SelectedItem){[string]$C.Runs.SelectedItem.OperationID}else{''}
    $DiagId=if($null -ne $C.DiagRun.SelectedItem){[string]$C.DiagRun.SelectedItem.OperationID}else{''}
    $S.Loading=$true
    try{
        if($Reload -or $null -eq $S.Index){$S.Index=Get-RemoteOpsHistoryIndex $S.BasePath}
        $Page=Find-RemoteOpsHistoryRuns -Runs $S.Index.Runs -Operation $C.Operation.Text.Trim() -Computer $C.Computer.Text.Trim() -Outcome ([string]$C.Outcome.SelectedValue) -From $C.From.SelectedDate -To $C.To.SelectedDate -Page $S.Page
        $S.Page=$Page.Page;$C.Runs.ItemsSource=$Page.Items
        $C.Count.Text=('{0} çalışma | Sayfa {1} / {2} | Sayfada en çok 50 çalışma' -f $Page.Total,($Page.Page+1),([Math]::Max(1,[Math]::Ceiling($Page.Total/50.0))))
        $C.Prev.IsEnabled=$S.Page -gt 0;$C.Next.IsEnabled=(($S.Page+1)*50 -lt $Page.Total)
        if($Selected){$Match=@($Page.Items|Where-Object OperationID -eq $Selected);if($Match.Count){$C.Runs.SelectedItem=$Match[0]}}
        foreach($Run in $S.Index.Runs){$Run|Add-Member -NotePropertyName DiagnosisLabel -NotePropertyValue (Get-RemoteOpsDiagnosisRunLabel $Run) -Force}
        $C.DiagRun.ItemsSource=$S.Index.Runs
        $Match=@($S.Index.Runs|Where-Object OperationID -eq $DiagId);if($Match.Count){$C.DiagRun.SelectedItem=$Match[0]}
    }catch{$C.Count.Text='Geçmiş okunamadı: '+$_.Exception.Message}
    finally{$S.Loading=$false}
    Update-RemoteOpsHistorySelection;Update-RemoteOpsDiagnosisRun
}
function Update-RemoteOpsHistorySelection {
    $S=$script:HistoryState;$C=$script:HistoryControls
    $Computer=if($null -ne $C.Targets.SelectedItem){[string]$C.Targets.SelectedItem.ComputerName}else{''}
    $S.Run=$C.Runs.SelectedItem;$S.Details=$null;$C.Targets.ItemsSource=@();$C.Steps.ItemsSource=@();$C.Artifacts.ItemsSource=@();$C.Diagnose.IsEnabled=$false;$C.OpenArtifact.IsEnabled=$false
    $Issues=@();if($null -ne $S.Index){$Issues+=@($S.Index.Issues)}
    if($null -ne $S.Run){
        $S.Details=Get-RemoteOpsHistoryDetails $S.BasePath $S.Run;$Issues+=@($S.Details.Issues)
        $C.Targets.ItemsSource=$S.Details.Targets;$C.Artifacts.ItemsSource=@($S.Details.Artifacts|Where-Object Exists)
        if($C.Artifacts.Items.Count){$C.Artifacts.SelectedIndex=0}
        $Match=@($S.Details.Targets|Where-Object ComputerName -eq $Computer)
        if($Match.Count){$C.Targets.SelectedItem=$Match[0]}elseif($C.Targets.Items.Count){$C.Targets.SelectedIndex=0}
    }
    $C.Issues.Text=(@($Issues|ForEach-Object{$_.Path+' | '+$_.Message}) -join "`r`n")
    $C.IssuesPanel.Visibility=if($Issues.Count){'Visible'}else{'Collapsed'}
    if(Get-Command Update-RemoteOpsHistoryTargetFilter -ErrorAction SilentlyContinue){Update-RemoteOpsHistoryTargetFilter}
    Update-RemoteOpsHistoryTarget
}
function Update-RemoteOpsHistoryTarget {
    $S=$script:HistoryState;$C=$script:HistoryControls
    $C.OpenLogs.IsEnabled=$false;$C.OpenPulled.IsEnabled=$false;$C.Diagnose.IsEnabled=$false;$C.Steps.ItemsSource=@();$C.Steps.Tag.Text='';$C.Steps.Tag.Visibility='Collapsed'
    if($null -eq $S.Run -or $null -eq $S.Details -or $null -eq $C.Targets.SelectedItem){return}
    $Computer=[string]$C.Targets.SelectedItem.ComputerName
    Set-RemoteOpsStepResultGrid $C.Steps @($S.Details.Rows|Where-Object{(Get-RemoteOpsHistoryRowComputer $_) -eq $Computer})
    $C.Diagnose.IsEnabled=$true
    foreach($Pair in @(@('PulledLogs','OpenLogs'),@('PulledFiles','OpenPulled'))){try{$Path=Get-RemoteOpsHistoryCollectionPath $Pair[0];$C.($Pair[1]).IsEnabled=[bool]$Path}catch{}}
}
function Get-RemoteOpsHistoryCollectionPath {
    param([ValidateSet('PulledLogs','PulledFiles')][string]$Scope)
    $S=$script:HistoryState;$C=$script:HistoryControls
    if($null -eq $S.Run -or $null -eq $C.Targets.SelectedItem){return ''}
    $Id=[string]$S.Run.OperationID;$Computer=[string]$C.Targets.SelectedItem.ComputerName
    if($Id -cnotmatch '^[A-Za-z0-9_-]+$' -or $Computer -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $Computer.Contains('..')){return ''}
    $Path=Resolve-RemoteOpsHistoryPath $S.BasePath (Join-Path (Join-Path (Join-Path $S.BasePath $Scope) $Id) $Computer) $Scope
    if(Test-Path -LiteralPath $Path -PathType Container){return $Path};return ''
}
function Open-RemoteOpsHistoryCollection {
    param([ValidateSet('PulledLogs','PulledFiles')][string]$Scope)
    try{$Path=Get-RemoteOpsHistoryCollectionPath $Scope;if($Path){Microsoft.PowerShell.Management\Start-Process -FilePath $Path -ErrorAction Stop}}catch{[void][Windows.MessageBox]::Show($_.Exception.Message,'Çıktı açılamadı')}
}
function Open-RemoteOpsHistoryArtifact {
    $S=$script:HistoryState;$C=$script:HistoryControls
    try{
        if($null -eq $S.Run -or $null -eq $C.Artifacts.SelectedItem){return}
        $Selected=$C.Artifacts.SelectedItem
        $Fresh=Get-RemoteOpsHistoryDetails $S.BasePath $S.Run
        $Allowed=@($Fresh.Artifacts|Where-Object{$_.Path -eq $Selected.Path -and $_.Exists})
        if(-not $Allowed.Count){throw 'Çıktı artık mevcut değil veya doğrulanamadı.'}
        $Path=Resolve-RemoteOpsHistoryPath $S.BasePath $Allowed[0].Path
        Microsoft.PowerShell.Management\Start-Process -FilePath $Path -ErrorAction Stop
    }catch{[void][Windows.MessageBox]::Show($_.Exception.Message,'Çıktı açılamadı')}
}
function Update-RemoteOpsDiagnosisRun {
    $S=$script:HistoryState;$C=$script:HistoryControls
    $Computer=if($null -ne $C.DiagTarget.SelectedItem){[string]$C.DiagTarget.SelectedItem.ComputerName}else{''}
    $S.DiagRun=$C.DiagRun.SelectedItem;$S.DiagDetails=$null;$C.DiagTarget.ItemsSource=@()
    if($null -ne $S.DiagRun){
        $S.DiagDetails=Get-RemoteOpsHistoryDetails $S.BasePath $S.DiagRun
        $C.DiagTarget.ItemsSource=$S.DiagDetails.Targets
        $Match=@($S.DiagDetails.Targets|Where-Object ComputerName -eq $Computer)
        if($Match.Count){$C.DiagTarget.SelectedItem=$Match[0]}elseif($C.DiagTarget.Items.Count){$C.DiagTarget.SelectedIndex=0}
    }
    Update-RemoteOpsDiagnosisView
}
function Update-RemoteOpsDiagnosisView {
    $S=$script:HistoryState;$C=$script:HistoryControls;$C.Bundle.IsEnabled=$false
    $C.Diagnosis.Text='Geçmişten bir çalışma ve bilgisayar seçin.'
    $C.DiagOutcome.Text='Sonuç özeti';$C.DiagReason.Text=$C.Diagnosis.Text;$C.DiagNextAction.Text='Seçili sonuca ait öneri burada gösterilir.'
    if($null -eq $S.DiagRun -or $null -eq $S.DiagDetails){return}
    $C.Bundle.IsEnabled=@($S.DiagDetails.Artifacts|Where-Object{$_.Kind -eq 'Folder' -and $_.Exists}).Count -gt 0
    if($null -eq $C.DiagTarget.SelectedItem){$C.Diagnosis.Text='Bu çalışmada okunabilir hedef sonucu yok.';$C.DiagReason.Text=$C.Diagnosis.Text;return}
    $D=Get-RemoteOpsDiagnosis $S.DiagRun ([string]$C.DiagTarget.SelectedItem.ComputerName) $S.DiagDetails
    $Labels=@{Success='Başarılı';Skipped='Atlandı';Cancelled='İptal';Indeterminate='Sonuç belirsiz';Unreachable='Hedefe erişilemedi';RebootRequired='Yeniden başlatma gerekli';AccessDenied='Yetki reddi işareti';Source='Kaynak erişimi işareti';Verification='Son doğrulama';Execution='Operasyon / paket yürütme';Unknown='Yeterli kanıt yok'}
    $C.DiagOutcome.Text=if($Labels.ContainsKey($D.Outcome)){$Labels[$D.Outcome]}else{'Sonuç: '+$D.Outcome}
    $C.DiagReason.Text=$D.Reason;$C.DiagNextAction.Text=$D.NextAction
    $C.Diagnosis.Text=@(
        'NEDEN OLDU?', $D.Reason, '', 'NE YAPMALIYIM?', $D.NextAction, '', 'TEKNİK AYRINTILAR', ('Çalışma: '+$D.OperationID+' | '+$S.DiagRun.Operation),('Bilgisayar: '+$D.ComputerName),('Özgün sonuç: '+$D.Outcome),('Teşhis grubu: '+$Labels[$D.Category]),
        ('Paket kimliği: '+$D.PackageId+' | Revizyon: '+$D.PackageRevision),('Sürüm: '+$D.PreviousVersion+' → '+$D.TargetVersion+' | Son: '+$D.FinalVersion),
        '', 'ÖNERİLEN KONTROLLER',($D.Checks -join "`r`n"),'','ÖZGÜN KAYITLAR (adım | durum | kod | detay)',($D.Evidence -join "`r`n"),
        '',(@($S.DiagDetails.Issues|ForEach-Object{$_.Path+' | '+$_.Message}) -join "`r`n")
    ) -join "`r`n"
}
function Show-RemoteOpsDiagnosticExport {
    $S=$script:HistoryState
    try{
        if($null -eq $S.DiagRun){return}
        $Preview=Get-RemoteOpsDiagnosticFiles $S.BasePath $S.DiagRun
        if($Preview.Issues.Count){throw (($Preview.Issues|ForEach-Object{$_.Path+' | '+$_.Message}) -join "`r`n")}
        if(-not $Preview.Files.Count){throw 'Dışa aktarılabilir dosya yok.'}
        # Scrollable preview keeps all filenames reviewable before save.
        $Dialog=New-Object Windows.Window;$Dialog.Title='Tanı paketi önizlemesi';$Dialog.Width=640;$Dialog.Height=450;$Dialog.WindowStartupLocation='CenterScreen'
        $Owner=[Windows.Window]::GetWindow($S.Tabs);if($null -ne $Owner -and $Owner.IsVisible){$Dialog.Owner=$Owner}
        $Panel=New-Object Windows.Controls.DockPanel;$Panel.Margin='16';$Dialog.Content=$Panel
        $Hint=New-Object Windows.Controls.TextBlock;$Hint.Text='Aşağıdaki raporlar/loglar ZIP dosyasına eklenecek. Üçüncü taraf logları hassas içerik taşıyabilir; paylaşmadan önce inceleyin. Profil/parola kataloğu eklenmez.';$Hint.TextWrapping='Wrap';$Hint.Margin='0,0,0,12';[Windows.Controls.DockPanel]::SetDock($Hint,'Top');[void]$Panel.Children.Add($Hint)
        $Ok=New-Object Windows.Controls.Button;$Ok.Content='Bu dosyalarla kaydet…';$Ok.Padding='12,8';$Ok.Margin='0,12,0,0';[Windows.Controls.DockPanel]::SetDock($Ok,'Bottom');[void]$Panel.Children.Add($Ok)
        $Ok.Add_Click({[Windows.Window]::GetWindow($this).DialogResult=$true})
        $List=New-Object Windows.Controls.TextBox;$List.IsReadOnly=$true;$List.VerticalScrollBarVisibility='Auto';$List.Text=(@($Preview.Files|ForEach-Object{$_.RelativePath+' | '+$_.Length+' bayt'}) -join "`r`n");[void]$Panel.Children.Add($List)
        if($Dialog.ShowDialog() -ne $true){return}
        $Save=New-Object Microsoft.Win32.SaveFileDialog;$Save.Filter='ZIP (*.zip)|*.zip';$Save.FileName=$S.DiagRun.OperationID+'-tani.zip'
        if($Save.ShowDialog() -ne $true){return}
        $Result=Export-RemoteOpsDiagnosticBundle $S.BasePath $S.DiagRun $Preview.Files $Save.FileName
        [void][Windows.MessageBox]::Show(('Kaydedildi: '+$Result.Path+"`r`n"+$Result.EntryCount+' dosya | '+$Result.Bytes+' bayt'),'Tanı paketi')
    }catch{[void][Windows.MessageBox]::Show($_.Exception.Message,'Tanı paketi oluşturulamadı')}
}
