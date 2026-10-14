# WPF package library and editor. Package definitions are data, never credentials.
function New-RemoteOpsPackageView {
    param([string]$Xaml)
    $Xml=[xml]$Xaml
    $View=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $Xml))
    $Ns=New-Object Xml.XmlNamespaceManager $Xml.NameTable;$Ns.AddNamespace('x','http://schemas.microsoft.com/winfx/2006/xaml')
    foreach($Node in $Xml.SelectNodes('//*[@x:Name]',$Ns)){$Name=$Node.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml');$script:PackageControls[$Name]=$View.FindName($Name)}
    return $View
}
function Add-RemoteOpsPackageEditorField {
    param($Parent,[string]$Name,[string]$Label,[string]$Type='Text',[object[]]$Options=@(),[string]$Hint='')
    $Row=New-Object Windows.Controls.Grid;$Row.Margin='0,4,0,4'
    $Left=New-Object Windows.Controls.ColumnDefinition;$Left.Width=145;$Right=New-Object Windows.Controls.ColumnDefinition;$Right.Width=New-Object Windows.GridLength 1,([Windows.GridUnitType]::Star)
    $Row.ColumnDefinitions.Add($Left);$Row.ColumnDefinitions.Add($Right)
    $Text=New-Object Windows.Controls.TextBlock;$Text.Text=T $Label;$Text.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#4A6073');$Text.VerticalAlignment='Center';$Text.TextWrapping='Wrap';$Text.Margin='0,0,10,0'
    [void]$Row.Children.Add($Text)
    if($Type -eq 'Choice'){
        $Control=New-Object Windows.Controls.ComboBox;$Control.DisplayMemberPath='Title';$Control.SelectedValuePath='Key';$Control.Padding='5,4'
        foreach($Option in $Options){[void]$Control.Items.Add([PSCustomObject]@{Key=$Option[0];Title=(T $Option[1])})}
    }else{
        $Control=New-Object Windows.Controls.TextBox;$Control.MinHeight=30
        if($Type -eq 'Multiline'){$Control.AcceptsReturn=$true;$Control.Height=55;$Control.TextWrapping='Wrap';$Control.VerticalScrollBarVisibility='Auto'}
    }
    $Control.ToolTip=if($Hint -match '\\u[0-9A-Fa-f]{4}'){T $Hint}else{$Hint};[Windows.Controls.Grid]::SetColumn($Control,1);[void]$Row.Children.Add($Control);[void]$Parent.Children.Add($Row);$script:PackageControls[$Name]=$Control
}
function Initialize-RemoteOpsPackageUi {
    param($Window,[string]$CatalogRoot)
    $script:PackageCatalogRoot=$CatalogRoot;$script:PackageControls=@{};$script:PackageUiLoading=$false;$script:PendingPackageRun=$null;$script:EditingPackage=$null;$script:EditingPackageRevision=0
    $Library=New-RemoteOpsPackageView @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"><Grid.ColumnDefinitions><ColumnDefinition Width="300" /><ColumnDefinition Width="12" /><ColumnDefinition Width="*" /></Grid.ColumnDefinitions><Border Style="{DynamicResource Card}" Padding="14"><DockPanel><StackPanel DockPanel.Dock="Top"><DockPanel><Button x:Name="PackageNew" DockPanel.Dock="Right" Content="+ Yeni paket" Style="{DynamicResource PrimaryButton}" Padding="10,5" /><TextBlock Text="Paketlerim" FontSize="22" FontWeight="SemiBold" Foreground="#1F3342" /></DockPanel><TextBlock x:Name="PackageCount" Foreground="#62778A" Margin="0,5,0,12" /><TextBox x:Name="PackageSearch" ToolTip="Paket adı, açıklama veya sürüm ara" MinHeight="32" /><ComboBox x:Name="PackageCategoryFilter" Margin="0,8,0,10" Padding="5,4" /></StackPanel><StackPanel DockPanel.Dock="Bottom"><TextBlock x:Name="PackageCatalogErrors" Foreground="#B02A2A" TextWrapping="Wrap" FontSize="11" Margin="0,6" /><WrapPanel><Button x:Name="PackageImport" Content="İçe aktar" Margin="0,0,6,0" /><Button x:Name="PackageExport" Content="Dışa aktar" /><Button x:Name="PackageReload" Content="Yenile" Margin="6,0,0,0" /></WrapPanel></StackPanel><ListBox x:Name="PackageList" BorderThickness="0" Background="Transparent" HorizontalContentAlignment="Stretch" ScrollViewer.HorizontalScrollBarVisibility="Disabled"><ListBox.ItemTemplate><DataTemplate><Border Padding="8,9"><StackPanel><TextBlock Text="{Binding Name}" FontSize="14" FontWeight="SemiBold" TextTrimming="CharacterEllipsis" /><TextBlock Text="{Binding TargetVersion, StringFormat='Hedef sürüm: {0}'}" Foreground="#62778A" FontSize="11.5" Margin="0,3,0,0" /></StackPanel></Border></DataTemplate></ListBox.ItemTemplate></ListBox></DockPanel></Border><Border Grid.Column="2" Style="{DynamicResource Card}" Padding="18"><DockPanel><StackPanel DockPanel.Dock="Top"><DockPanel><WrapPanel DockPanel.Dock="Right" Margin="10,0,0,0"><Button x:Name="PackageEdit" Content="Düzenle" Margin="0,0,6,0" /><Button x:Name="PackageCopy" Content="Kopyala" Margin="0,0,6,0" /><Button x:Name="PackageDelete" Content="Kaydı sil" Style="{DynamicResource DangerButton}" /></WrapPanel><TextBlock x:Name="PackageSelectedName" Text="Bir paket seçin" FontSize="24" FontWeight="SemiBold" Foreground="#1F3342" TextTrimming="CharacterEllipsis" /></DockPanel><TextBlock x:Name="PackageSelectedDescription" Foreground="#62778A" Margin="0,3,0,8" TextWrapping="Wrap" /></StackPanel><StackPanel DockPanel.Dock="Bottom" Margin="0,8,0,0"><WrapPanel><Button x:Name="PackageInstall" Content="Kur" Style="{DynamicResource PrimaryButton}" Padding="22,9" Margin="0,0,8,6" /><Button x:Name="PackageUninstall" Content="Kaldır" Padding="22,9" Margin="0,0,8,6" /><Button x:Name="PackageDowngrade" Content="Eski sürüme dön" Padding="18,9" Margin="0,0,0,6" /></WrapPanel><TextBlock x:Name="PackageActionHint" Foreground="#62778A" TextWrapping="Wrap" FontSize="11" /></StackPanel><ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,14,0,0"><StackPanel><Expander Header="Paket bilgileri ve kaynaklar" IsExpanded="False"><Border Background="#F3F7FA" CornerRadius="8" Padding="13"><TextBlock x:Name="PackageDetail" Text="Paket bilgilerini bir kez tanımlayın. Sonraki dağıtımlarda yalnızca hedefleri seçin." Foreground="#31536B" TextWrapping="Wrap" /></Border></Expander><TextBlock Text="Hedef bilgisayarlar" FontWeight="SemiBold" Foreground="#31536B" Margin="0,16,0,6" /><TextBox x:Name="PackageTargets" Height="56" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" ToolTip="Boşluk, virgül, noktalı virgül veya satır sonu ile ayırın" /><TextBlock Text="Hedefler paket kaydına yazılmaz. Çalıştırma hesabını yukarıdan seçin." Foreground="#62778A" FontSize="11" Margin="0,5,0,10" /></StackPanel></ScrollViewer></DockPanel></Border><Border x:Name="PackageSummaryPanel" Grid.ColumnSpan="3" Background="#F7FAFC" BorderBrush="#0B64A8" BorderThickness="1" CornerRadius="10" Padding="24" Visibility="Collapsed"><DockPanel><StackPanel DockPanel.Dock="Top"><TextBlock Text="Dağıtım özeti" FontSize="24" FontWeight="SemiBold" Foreground="#1F3342" /><TextBlock Text="Başlatmadan önce paket, hedefler ve hesabı kontrol edin." Foreground="#62778A" Margin="0,6,0,16" /></StackPanel><StackPanel DockPanel.Dock="Bottom"><TextBlock x:Name="PackageConfirmHint" Foreground="#31536B" FontWeight="SemiBold" Margin="0,10,0,6" /><TextBox x:Name="PackageRunConfirm" Width="260" HorizontalAlignment="Left" MinHeight="34" /><TextBlock x:Name="PackageRunError" Foreground="#B02A2A" TextWrapping="Wrap" Margin="0,6" /><WrapPanel Margin="0,10,0,0"><Button x:Name="PackageSummaryStart" Content="Dağıtımı başlat" Style="{DynamicResource PrimaryButton}" Padding="20,9" Margin="0,0,10,0" /><Button x:Name="PackageSummaryCancel" Content="Vazgeç" Padding="18,9" /></WrapPanel></StackPanel><ScrollViewer VerticalScrollBarVisibility="Auto"><TextBlock x:Name="PackageRunSummary" FontSize="15" Foreground="#31536B" TextWrapping="Wrap" /></ScrollViewer></DockPanel></Border></Grid>
'@
    $Window.FindName('PackageLibraryHost').Content=$Library
    $Editor=New-RemoteOpsPackageView @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
 <StackPanel Margin="0,0,0,12"><TextBlock x:Name="PackageEditorTitle" Text="Paket olu&#x15F;tur" FontSize="23" FontWeight="SemiBold" Foreground="#1F3342"/><TextBlock Text="Haz&#x131;r UNC paketini tan&#x131;mlay&#x131;n; desteklenecek i&#x15F;lemleri se&#xE7;in." Foreground="#62778A" Margin="0,4,0,0"/></StackPanel>
 <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto"><StackPanel>
  <Border Style="{DynamicResource Card}" Margin="0,0,0,12"><StackPanel><TextBlock Text="Paket bilgileri" FontSize="16" FontWeight="SemiBold" Foreground="#31536B" Margin="0,0,0,10"/><StackPanel x:Name="PackageGeneralFields"/><WrapPanel Margin="0,10,0,0"><CheckBox x:Name="PackageCollectLogs" Content="Paket loglar&#x131;n&#x131; topla" Margin="0,0,24,0"/><CheckBox x:Name="PackageDowngradeEnabled" Content="Eski s&#xFC;r&#xFC;me d&#xF6;n&#xFC;&#x15F; tan&#x131;m&#x131; ekle"/></WrapPanel></StackPanel></Border>
  <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Border Style="{DynamicResource Card}"><StackPanel><CheckBox x:Name="InstallEnabled" Content="Kurulum tan&#x131;m&#x131; ekle" FontWeight="SemiBold" FontSize="16" Foreground="#31536B" Margin="0,0,0,10"/><StackPanel x:Name="InstallFields"/></StackPanel></Border><Border Grid.Column="2" Style="{DynamicResource Card}"><StackPanel><DockPanel Margin="0,0,0,10"><Button x:Name="CopyInstallIdentity" Content="Kimli&#x11F;i kopyala" DockPanel.Dock="Right" Padding="8,3" FontSize="11"/><CheckBox x:Name="UninstallEnabled" Content="Kald&#x131;rma tan&#x131;m&#x131; ekle" FontWeight="SemiBold" FontSize="16" Foreground="#31536B" VerticalAlignment="Center"/></DockPanel><StackPanel x:Name="UninstallFields"/></StackPanel></Border></Grid>
  <Border x:Name="DowngradeCard" Style="{DynamicResource Card}" Margin="0,12,0,0" Visibility="Collapsed"><StackPanel>
    <TextBlock Text="Eski s&#xFC;r&#xFC;me d&#xF6;n&#xFC;&#x15F; paketi" FontSize="16" FontWeight="SemiBold" Foreground="#31536B" Margin="0,0,0,8"/>
    <TextBlock Text="Normal kurulumdan ba&#x11F;&#x131;ms&#x131;zd&#x131;r. &#xD6;nce Kald&#x131;rma tan&#x131;m&#x131; &#xE7;al&#x131;&#x15F;&#x131;r; yokluk do&#x11F;rulan&#x131;nca a&#x15F;a&#x11F;&#x131;daki eski s&#xFC;r&#xFC;m kurulur ve tam s&#xFC;r&#xFC;m do&#x11F;rulan&#x131;r." Foreground="#62778A" TextWrapping="Wrap" Margin="0,0,0,8"/>
    <StackPanel x:Name="DowngradeFields"/>
  </StackPanel></Border>
  <TextBlock Text="Tan&#x131;mlar otomatik s&#x131;rayla &#xE7;al&#x131;&#x15F;maz; eylemi Paketlerim'de se&#xE7;in. Eski s&#xFC;r&#xFC;me d&#xF6;n&#xFC;&#x15F; i&#xE7;in Kald&#x131;rma ve ayr&#x131; eski s&#xFC;r&#xFC;m paketi zorunludur. Eski kay&#x131;tlarda &#xF6;nceki kurulum bilgileri eski s&#xFC;r&#xFC;m alan&#x131;na ta&#x15F;&#x131;n&#x131;r; yollar&#x131; ve s&#xFC;r&#xFC;mleri kontrol edin." Foreground="#62778A" TextWrapping="Wrap" Margin="4,12"/>

 </StackPanel></ScrollViewer>
 <DockPanel Grid.Row="2" Margin="0,12,0,0"><WrapPanel DockPanel.Dock="Right"><Button x:Name="PackageSave" Content="Paketi kaydet" Style="{DynamicResource PrimaryButton}" Padding="20,9" Margin="8,0"/><Button x:Name="PackageEditorCancel" Content="Vazge&#xE7;" Padding="18,9"/></WrapPanel><TextBlock x:Name="PackageValidation" Visibility="Collapsed" Foreground="#B02A2A" TextWrapping="Wrap" MaxHeight="95"/></DockPanel>
</Grid>
'@
    $Window.FindName('PackageEditorHost').Content=$Editor
    $UI=$script:PackageControls
    foreach($Field in @(@('PackageNameInput','Paket ad\u0131','Text'),@('PackageVersionInput','Hedef s\u00FCr\u00FCm','Text'),@('PackageCategoryInput','Kategori','Text'),@('PackageFamilyInput','Uygulama ailesi','Text'),@('PackageDescriptionInput','A\u00E7\u0131klama','Multiline'))){Add-RemoteOpsPackageEditorField $UI.PackageGeneralFields $Field[0] $Field[1] $Field[2]}
    $GeneralRows=@($UI.PackageGeneralFields.Children);$UI.PackageGeneralFields.Children.Clear()
    $GeneralGrid=New-Object Windows.Controls.Grid
    foreach($Width in @('*','12','*')){$Column=New-Object Windows.Controls.ColumnDefinition;$Column.Width=[Windows.GridLengthConverter]::new().ConvertFromString($Width);$GeneralGrid.ColumnDefinitions.Add($Column)}
    for($Index=0;$Index -lt 3;$Index++){$Row=New-Object Windows.Controls.RowDefinition;$Row.Height=[Windows.GridLength]::Auto;$GeneralGrid.RowDefinitions.Add($Row)}
    for($Index=0;$Index -lt $GeneralRows.Count;$Index++){
        [Windows.Controls.Grid]::SetRow($GeneralRows[$Index],[int][math]::Floor($Index/2));[Windows.Controls.Grid]::SetColumn($GeneralRows[$Index],($Index%2)*2)
        if($Index -eq 4){[Windows.Controls.Grid]::SetColumnSpan($GeneralRows[$Index],3)}
        [void]$GeneralGrid.Children.Add($GeneralRows[$Index])
    }
    [void]$UI.PackageGeneralFields.Children.Add($GeneralGrid)
    $UI.PackageFamilyInput.ToolTip=T 'Ayn\u0131 uygulaman\u0131n b\u00FCt\u00FCn s\u00FCr\u00FCmlerinde ayn\u0131 aile anahtar\u0131n\u0131 kullan\u0131n; ayn\u0131 PC i\u00E7in \u00E7ak\u0131\u015Fan da\u011F\u0131t\u0131mlar engellenir.'
    $SearchOptions=@(@('DisplayName exact','DisplayName tam e\u015Fle\u015Fme'),@('DisplayName contains','DisplayName i\u00E7erir'),@('ProductID','ProductID'))
    $ModeOptions=@(@('Version controlled','S\u00FCr\u00FCm kontroll\u00FC'),@('Presence only','Varl\u0131k kontroll\u00FC'),@('Trigger without checks','Kontrols\u00FCz tetikle'))
    $UI.DowngradeEnabled=$UI.PackageDowngradeEnabled
    Add-RemoteOpsPackageEditorField $UI.DowngradeFields 'DowngradeVersionInput' 'Eski hedef s\u00FCr\u00FCm'
    foreach($Action in @('Install','Uninstall','Downgrade')){
        $Parent=$UI[$Action+'Fields']
        Add-RemoteOpsPackageEditorField $Parent ($Action+'PathInput') 'UNC klas\u00F6r\u00FC' Text @() '\\sunucu\paylasim\paket'
        Add-RemoteOpsPackageEditorField $Parent ($Action+'FileInput') 'Paket dosyas\u0131' Text @() 'install.cmd, uninstall.bat, script.ps1 veya script.vbs'
        Add-RemoteOpsPackageEditorField $Parent ($Action+'SearchInput') 'Kimlik t\u00FCr\u00FC' Choice $SearchOptions
        Add-RemoteOpsPackageEditorField $Parent ($Action+'IdentityInput') 'Uygulama kimli\u011Fi'
        Add-RemoteOpsPackageEditorField $Parent ($Action+'RegistryInput') 'Kesin registry anahtar\u0131' Text @() '\u0130ste\u011Fe ba\u011Fl\u0131; \u00E7oklu e\u015Fle\u015Fmede tek uygulama se\u00E7mek i\u00E7in.'
        Add-RemoteOpsPackageEditorField $Parent ($Action+'ModeInput') 'Kontrol modu' Choice $ModeOptions
    }
    # Keep the independent old-version definition compact enough to review together.
    $OldRows=@($UI.DowngradeFields.Children);$UI.DowngradeFields.Children.Clear()
    $OldGrid=New-Object Windows.Controls.Grid
    foreach($Width in @('*','12','*')){$Column=New-Object Windows.Controls.ColumnDefinition;$Column.Width=[Windows.GridLengthConverter]::new().ConvertFromString($Width);$OldGrid.ColumnDefinitions.Add($Column)}
    for($Index=0;$Index -lt [math]::Ceiling($OldRows.Count/2);$Index++){$Row=New-Object Windows.Controls.RowDefinition;$Row.Height=[Windows.GridLength]::Auto;$OldGrid.RowDefinitions.Add($Row)}
    for($Index=0;$Index -lt $OldRows.Count;$Index++){
        [Windows.Controls.Grid]::SetRow($OldRows[$Index],[int][math]::Floor($Index/2));[Windows.Controls.Grid]::SetColumn($OldRows[$Index],($Index%2)*2)
        [void]$OldGrid.Children.Add($OldRows[$Index])
    }
    [void]$UI.DowngradeFields.Children.Add($OldGrid)
    $UI.DowngradeModeInput.IsEnabled=$false
    $UI.PackageNew.Add_Click({Show-RemoteOpsPackageEditor})
    $UI.PackageEdit.Add_Click({if($script:PackageControls.PackageList.SelectedItem){Show-RemoteOpsPackageEditor $script:PackageControls.PackageList.SelectedItem}})
    $UI.PackageCopy.Add_Click({if($script:PackageControls.PackageList.SelectedItem){Show-RemoteOpsPackageEditor $script:PackageControls.PackageList.SelectedItem -AsCopy}})
    $UI.PackageSave.Add_Click({try{Save-RemoteOpsPackageEditor|Out-Null}catch{$script:PackageControls.PackageValidation.Text=$_.Exception.Message;$script:PackageControls.PackageValidation.Visibility='Visible'}})
    $UI.PackageEditorCancel.Add_Click({$script:Window.FindName('MainTabs').SelectedItem=$script:Window.FindName('PackagesTab')})
    $UI.PackageList.Add_SelectionChanged({Update-RemoteOpsPackageDetail})
    $UI.PackageSearch.Add_TextChanged({if(-not $script:PackageUiLoading){Update-RemoteOpsPackageList $script:PackageControls.PackageSearch.Text ([string]$script:PackageControls.PackageCategoryFilter.SelectedItem)}})
    $UI.PackageCategoryFilter.Add_SelectionChanged({if(-not $script:PackageUiLoading){Update-RemoteOpsPackageList $script:PackageControls.PackageSearch.Text ([string]$script:PackageControls.PackageCategoryFilter.SelectedItem)}})
    $UI.PackageReload.Add_Click({Update-RemoteOpsPackageList})
    $UI.PackageInstall.Add_Click({Show-RemoteOpsPackageRunSummaryFromSelection 'Install'})
    $UI.PackageUninstall.Add_Click({Show-RemoteOpsPackageRunSummaryFromSelection 'Uninstall'})
    $UI.PackageDowngrade.Add_Click({Show-RemoteOpsPackageRunSummaryFromSelection 'Downgrade'})
    $UI.PackageSummaryCancel.Add_Click({$script:PackageControls.PackageSummaryPanel.Visibility='Collapsed';$script:PendingPackageRun=$null})
    $UI.PackageSummaryStart.Add_Click({try{
        $Pending=$script:PendingPackageRun
        if($null -eq $Pending){throw 'Open a deployment summary first.'}
        if($script:ProfileList.SelectedItem.Display -cne $Pending.Identity){throw (T 'Hesap de\u011Fi\u015Fti. \u00D6zeti yeniden a\u00E7\u0131n.')}
        Start-RemoteOpsSavedPackageRun $Pending.Definition $Pending.Action $Pending.Targets $script:PackageControls.PackageRunConfirm.Text
        $script:PackageControls.PackageSummaryPanel.Visibility='Collapsed';$script:PendingPackageRun=$null
    }catch{$script:PackageControls.PackageRunError.Text=$_.Exception.Message}})
    $UI.CopyInstallIdentity.Add_Click({foreach($Suffix in @('SearchInput','IdentityInput','RegistryInput')){if($Suffix -eq 'SearchInput'){$script:PackageControls['Uninstall'+$Suffix].SelectedValue=$script:PackageControls['Install'+$Suffix].SelectedValue}else{$script:PackageControls['Uninstall'+$Suffix].Text=$script:PackageControls['Install'+$Suffix].Text}}})
    foreach($Action in @('Install','Uninstall','Downgrade')){$UI[$Action+'Enabled'].Add_Checked({Update-RemoteOpsPackageEditorActions});$UI[$Action+'Enabled'].Add_Unchecked({Update-RemoteOpsPackageEditorActions})}
    $UI.PackageDelete.Add_Click({$P=$script:PackageControls.PackageList.SelectedItem;if($P -and [Windows.MessageBox]::Show((T 'Paket kayd\u0131 silinsin mi? UNC dosyalar\u0131 etkilenmez.')+' '+$P.Name,'REMOTE OPS','YesNo','Question') -eq 'Yes'){try{Remove-RemoteOpsPackageDefinition $script:PackageCatalogRoot $P.Id $P.Revision;Update-RemoteOpsPackageList}catch{[Windows.MessageBox]::Show($_.Exception.Message,'REMOTE OPS','OK','Warning')|Out-Null}}})
    $UI.PackageExport.Add_Click({try{
        $P=$script:PackageControls.PackageList.SelectedItem;if(-not $P){throw (T 'D\u0131\u015Fa aktarmak i\u00E7in bir paket se\u00E7in.')}
        $Dialog=New-Object Microsoft.Win32.SaveFileDialog;$Dialog.Filter='JSON (*.json)|*.json';$Dialog.FileName='RemoteOps-Packages.json'
        if($Dialog.ShowDialog($script:Window)){Export-RemoteOpsPackageDefinitions @($P) $Dialog.FileName;Write-AppLog (T 'Paket d\u0131\u015Fa aktar\u0131ld\u0131.')}
    }catch{[Windows.MessageBox]::Show($_.Exception.Message,'REMOTE OPS','OK','Warning')|Out-Null}})
    $UI.PackageImport.Add_Click({try{
        $Dialog=New-Object Microsoft.Win32.OpenFileDialog;$Dialog.Filter='JSON (*.json)|*.json'
        if($Dialog.ShowDialog($script:Window)){
            $Preview=Get-RemoteOpsPackageImportPreview $script:PackageCatalogRoot $Dialog.FileName;$Policy='Skip'
            if($Preview.Conflicts.Count -gt 0){$Choice=[Windows.MessageBox]::Show((T 'Ayn\u0131 kimlikte paket kay\u0131tlar\u0131 var. Evet: yeni kopya olarak ekle. Hay\u0131r: mevcut kay\u0131tlar\u0131 g\u00FCncelle. \u0130ptal: mevcut kay\u0131tlar\u0131 koru.'),'REMOTE OPS','YesNoCancel','Question');if($Choice -eq 'Yes'){$Policy='Copy'}elseif($Choice -eq 'No'){$Policy='Replace'}}
            $Result=Import-RemoteOpsPackageDefinitions $script:PackageCatalogRoot $Dialog.FileName $Policy
            Update-RemoteOpsPackageList
            if($Result.Errors.Count){throw (($Result.Errors|ForEach-Object{$_.Message}) -join "`r`n")}
            Write-AppLog ((T '\u0130\u00E7e aktar\u0131lan paket: ')+$Result.Imported.Count)
        }
    }catch{[Windows.MessageBox]::Show($_.Exception.Message,'REMOTE OPS','OK','Warning')|Out-Null}})
    Show-RemoteOpsPackageEditor;$Window.FindName('MainTabs').SelectedItem=$Window.FindName('PackagesTab');Update-RemoteOpsPackageList
}
function Update-RemoteOpsPackageList {
    param([string]$Search='',[string]$Category='')
    $UI=$script:PackageControls;$Selected=$UI.PackageList.SelectedItem;$SelectedId=if($Selected){$Selected.Id}else{''}
    $Catalog=Get-RemoteOpsPackageCatalog $script:PackageCatalogRoot;$script:PackageCatalog=$Catalog.Packages
    $script:PackageUiLoading=$true
    try{
        if(-not $Search){$Search=$UI.PackageSearch.Text}
        if(-not $Category){$Category=[string]$UI.PackageCategoryFilter.SelectedItem}
        $UI.PackageCategoryFilter.Items.Clear();[void]$UI.PackageCategoryFilter.Items.Add((T 'T\u00FCm kategoriler'))
        foreach($Name in @($Catalog.Packages|ForEach-Object{$_.Category}|Where-Object{$_}|Sort-Object -Unique)){[void]$UI.PackageCategoryFilter.Items.Add($Name)}
        if($Category -and $UI.PackageCategoryFilter.Items.Contains($Category)){$UI.PackageCategoryFilter.SelectedItem=$Category}else{$UI.PackageCategoryFilter.SelectedIndex=0}
        $AllCategories=[string]$UI.PackageCategoryFilter.Items[0]
        $Category=[string]$UI.PackageCategoryFilter.SelectedItem
        $Matches=@($Catalog.Packages|Where-Object{(-not $Search -or ($_.Name+' '+$_.Description+' '+$_.TargetVersion).IndexOf($Search,[StringComparison]::OrdinalIgnoreCase) -ge 0) -and (-not $Category -or $Category -eq $AllCategories -or $_.Category -eq $Category)})
        $UI.PackageList.Items.Clear();foreach($P in $Matches){[void]$UI.PackageList.Items.Add($P);if($P.Id -eq $SelectedId){$UI.PackageList.SelectedItem=$P}}
        $UI.PackageCount.Text=('{0} / {1} paket' -f $Matches.Count,$Catalog.Packages.Count)
        $UI.PackageCatalogErrors.Text=if($Catalog.Errors.Count){(T 'Okunamayan kay\u0131t: ')+$Catalog.Errors.Count+' - '+$Catalog.Errors[0].Message}else{''}
        if($UI.PackageList.SelectedIndex -lt 0 -and $Matches.Count){$UI.PackageList.SelectedIndex=0}
    }finally{$script:PackageUiLoading=$false}
    Update-RemoteOpsPackageDetail
}
function Update-RemoteOpsPackageDetail {
    $UI=$script:PackageControls;$P=$UI.PackageList.SelectedItem
    foreach($Name in @('PackageEdit','PackageCopy','PackageDelete','PackageExport')){$UI[$Name].IsEnabled=$null -ne $P}
    foreach($Pair in @(@('PackageInstall','Install'),@('PackageUninstall','Uninstall'),@('PackageDowngrade','Downgrade'))){$UI[$Pair[0]].IsEnabled=$null -ne $P -and (Test-RemoteOpsPackageDefinition $P $Pair[1]).Valid}
    if($null -eq $P){$UI.PackageSelectedName.Text=T 'Bir paket se\u00E7in';$UI.PackageSelectedDescription.Text=T 'Yeni paket olu\u015Fturun veya payla\u015F\u0131lan bir kayd\u0131 i\u00E7e aktar\u0131n.';$UI.PackageDetail.Text=T 'Paket bilgilerini bir kez tan\u0131mlay\u0131n. Sonraki da\u011F\u0131t\u0131mlarda yaln\u0131zca hedefleri se\u00E7in.';$UI.PackageActionHint.Text='';return}
    $UI.PackageSelectedName.Text=$P.Name;$UI.PackageSelectedDescription.Text=$P.Description
    $UI.PackageSelectedDescription.Visibility=if([string]::IsNullOrWhiteSpace($P.Description)){'Collapsed'}else{'Visible'}
    $Details=New-Object 'System.Collections.Generic.List[string]';$Details.Add((T 'Hedef s\u00FCr\u00FCm: ')+$P.TargetVersion+'    |    '+(T 'Revizyon: ')+$P.Revision)
    foreach($A in @('Install','Uninstall','Downgrade')){if($P.$A.Enabled){$Details.Add("`r`n"+$(if($A -eq 'Install'){T 'Kurulum'}elseif($A -eq 'Uninstall'){T 'Kald\u0131rma'}else{T 'Eski s\u00FCr\u00FCm'})+': '+(Join-Path $P.$A.PackagePath $P.$A.PackageFile));$Details.Add($P.$A.SearchType+': '+$P.$A.Application);if($A -eq 'Downgrade'){$Details.Add((T 'Eski hedef s\u00FCr\u00FCm: ')+$P.DowngradeVersion)}}}
    $UI.PackageDetail.Text=$Details -join "`r`n";$UI.PackageActionHint.Text=if($P.DowngradeEnabled){T 'Eski s\u00FCr\u00FCme d\u00F6n\u00FC\u015F: kald\u0131r \u2192 yoklu\u011Fu do\u011Frula \u2192 kur \u2192 tam s\u00FCr\u00FCm\u00FC do\u011Frula.'}else{T 'Etkin olmayan i\u015Flemler i\u00E7in paket tan\u0131m\u0131n\u0131 d\u00FCzenleyin.'}
}
function Show-RemoteOpsPackageEditor {
    param($Definition=$null,[switch]$AsCopy)
    $UI=$script:PackageControls
    if($null -eq $Definition){$Definition=New-RemoteOpsPackageDefinition;$Definition.Install.Enabled=$true;$script:EditingPackageRevision=0}
    elseif($AsCopy){$Definition=Copy-RemoteOpsPackageDefinition $Definition -NewIdentity;$script:EditingPackageRevision=0}
    else{$script:EditingPackageRevision=[int]$Definition.Revision}
    $Definition=Copy-RemoteOpsPackageDefinition $Definition
    $script:EditingPackage=Copy-RemoteOpsPackageDefinition $Definition
    $UI.PackageEditorTitle.Text=if($script:EditingPackageRevision){T 'Paketi d\u00FCzenle'}elseif($AsCopy){T 'Paketin kopyas\u0131n\u0131 olu\u015Ftur'}else{T 'Paket olu\u015Ftur'}
    foreach($Pair in @(@('PackageNameInput','Name'),@('PackageVersionInput','TargetVersion'),@('DowngradeVersionInput','DowngradeVersion'),@('PackageCategoryInput','Category'),@('PackageFamilyInput','ApplicationKey'),@('PackageDescriptionInput','Description'))){$UI[$Pair[0]].Text=[string]$Definition.($Pair[1])}
    $UI.PackageCollectLogs.IsChecked=$Definition.CollectLogs;$UI.PackageDowngradeEnabled.IsChecked=$Definition.DowngradeEnabled
    foreach($A in @('Install','Uninstall','Downgrade')){
        $UI[$A+'Enabled'].IsChecked=$Definition.$A.Enabled
        foreach($Pair in @(@('PathInput','PackagePath'),@('FileInput','PackageFile'),@('IdentityInput','Application'),@('RegistryInput','RegistryKey'))){$UI[$A+$Pair[0]].Text=[string]$Definition.$A.($Pair[1])}
        $UI[$A+'SearchInput'].SelectedValue=$Definition.$A.SearchType;$UI[$A+'ModeInput'].SelectedValue=$Definition.$A.CheckMode
    }
    $UI.PackageValidation.Text='';$UI.PackageValidation.Visibility='Collapsed';Update-RemoteOpsPackageEditorActions
    $script:Window.FindName('MainTabs').SelectedItem=$script:Window.FindName('PackageEditorTab');[void]$UI.PackageNameInput.Focus()
}
function Update-RemoteOpsPackageEditorActions {
    foreach($A in @('Install','Uninstall','Downgrade')){
        $script:PackageControls[$A+'Fields'].IsEnabled=[bool]$script:PackageControls[$A+'Enabled'].IsChecked
        $script:PackageControls[$A+'Fields'].Opacity=if($script:PackageControls[$A+'Fields'].IsEnabled){1}else{0.45}
    }
    $script:PackageControls.DowngradeCard.Visibility=if($script:PackageControls.PackageDowngradeEnabled.IsChecked){'Visible'}else{'Collapsed'}
}
function Get-RemoteOpsPackageEditorDefinition {
    $UI=$script:PackageControls;$P=Copy-RemoteOpsPackageDefinition $script:EditingPackage
    foreach($Pair in @(@('PackageNameInput','Name'),@('PackageVersionInput','TargetVersion'),@('DowngradeVersionInput','DowngradeVersion'),@('PackageCategoryInput','Category'),@('PackageFamilyInput','ApplicationKey'),@('PackageDescriptionInput','Description'))){$P.($Pair[1])=$UI[$Pair[0]].Text.Trim()}
    if(-not $P.ApplicationKey){$P.ApplicationKey=$P.Name.ToLowerInvariant()}
    $P.CollectLogs=[bool]$UI.PackageCollectLogs.IsChecked;$P.DowngradeEnabled=[bool]$UI.PackageDowngradeEnabled.IsChecked
    foreach($A in @('Install','Uninstall','Downgrade')){
        $P.$A.Enabled=[bool]$UI[$A+'Enabled'].IsChecked
        foreach($Pair in @(@('PathInput','PackagePath'),@('FileInput','PackageFile'),@('IdentityInput','Application'),@('RegistryInput','RegistryKey'))){$P.$A.($Pair[1])=$UI[$A+$Pair[0]].Text.Trim()}
        $P.$A.SearchType=[string]$UI[$A+'SearchInput'].SelectedValue;$P.$A.CheckMode=[string]$UI[$A+'ModeInput'].SelectedValue
    }
    return $P
}
function Show-RemoteOpsPackageValidation {
    param($Check)
    $Map=@{DowngradeVersion='DowngradeVersionInput';'Downgrade.PackagePath'='DowngradePathInput';'Downgrade.PackageFile'='DowngradeFileInput';'Downgrade.Application'='DowngradeIdentityInput';Name='PackageNameInput';ApplicationKey='PackageFamilyInput';TargetVersion='PackageVersionInput';'Install.PackagePath'='InstallPathInput';'Install.PackageFile'='InstallFileInput';'Install.Application'='InstallIdentityInput';'Uninstall.PackagePath'='UninstallPathInput';'Uninstall.PackageFile'='UninstallFileInput';'Uninstall.Application'='UninstallIdentityInput'}
    foreach($Name in $Map.Values){$script:PackageControls[$Name].ClearValue([Windows.Controls.Control]::BorderBrushProperty)}
    foreach($Error in $Check.Errors){if($Map.ContainsKey([string]$Error.Field)){$script:PackageControls[$Map[$Error.Field]].BorderBrush=[Windows.Media.Brushes]::Firebrick}}
    $script:PackageControls.PackageValidation.Text=($Check.Errors|ForEach-Object{$_.Field+': '+$_.Message}) -join "`r`n";$script:PackageControls.PackageValidation.Visibility=if($Check.Valid){'Collapsed'}else{'Visible'}
}
function Save-RemoteOpsPackageEditor {
    $P=Get-RemoteOpsPackageEditorDefinition;$Check=Test-RemoteOpsPackageDefinition $P;Show-RemoteOpsPackageValidation $Check
    if(-not $Check.Valid){throw (T 'Paket kaydedilmedi. \u0130\u015Faretli alanlar\u0131 d\u00FCzeltin.')}
    $Saved=Save-RemoteOpsPackageDefinition $script:PackageCatalogRoot $P $script:EditingPackageRevision
    $script:EditingPackage=$Saved;$script:EditingPackageRevision=$Saved.Revision;Update-RemoteOpsPackageList
    $script:PackageControls.PackageList.SelectedItem=@($script:PackageCatalog|Where-Object Id -eq $Saved.Id)[0]
    $script:Window.FindName('MainTabs').SelectedItem=$script:Window.FindName('PackagesTab');Write-AppLog ((T 'Paket kaydedildi: ')+$Saved.Name)
    return $Saved
}
function Show-RemoteOpsPackageRunSummaryFromSelection {
    param([string]$Action)
    try{
        $P=$script:PackageControls.PackageList.SelectedItem
        if(-not $P){throw (T 'Bir paket se\u00E7in.')}
        $Targets=@(Get-TargetList $script:PackageControls.PackageTargets.Text)
        if($Targets.Count -eq 0){throw (T 'En az bir hedef bilgisayar girin.')}
        $Profile=$script:ProfileList.SelectedItem;if(-not $Profile){throw (T 'Bir \u00E7al\u0131\u015Ft\u0131rma hesab\u0131 se\u00E7in.')}
        Show-RemoteOpsPackageRunSummary $P $Action $Targets $Profile
    }catch{[Windows.MessageBox]::Show($_.Exception.Message,'REMOTE OPS','OK','Warning')|Out-Null}
}
function Show-RemoteOpsPackageRunSummary {
    param($Definition,[string]$Action,[string[]]$Targets,$Profile)
    Assert-RemoteOpsPackageDefinition $Definition $Action
    $P=Copy-RemoteOpsPackageDefinition $Definition
    $script:PendingPackageRun=[PSCustomObject]@{Definition=$P;Action=$Action;Targets=$Targets;Identity=$Profile.Display}
    $Text=(T 'Paket: ')+$P.Name+"`r`n"+(T '\u0130\u015Flem: ')+$(switch($Action){'Install'{T 'Kurulum'}'Uninstall'{T 'Kald\u0131rma'}'Downgrade'{T 'Eski s\u00FCr\u00FCme d\u00F6n\u00FC\u015F'}})+"`r`n"+(T 'Hedef s\u00FCr\u00FCm: ')+$(if($Action -eq 'Downgrade'){$P.DowngradeVersion}else{$P.TargetVersion})+"`r`n"+(T 'Hesap: ')+$Profile.Display+"`r`n"+(T 'Bilgisayar say\u0131s\u0131: ')+$Targets.Count+"`r`n`r`n"+($Targets -join ', ')
    foreach($A in $(if($Action -eq 'Downgrade'){@('Uninstall','Downgrade')}else{@($Action)})){$Text+="`r`n`r`n"+$A+': '+(Join-Path $P.$A.PackagePath $P.$A.PackageFile)+"`r`n"+$P.$A.SearchType+': '+$P.$A.Application;if($P.$A.CheckMode -eq 'Trigger without checks'){$Text+="`r`n"+(T 'Uygulama do\u011Frulamas\u0131 yap\u0131lmayacak.')}}
    if($Action -eq 'Downgrade'){$Text+="`r`n`r`n"+(T 'Kald\u0131rma do\u011Frulanmadan kurulum ba\u015Flamaz. Yeniden ba\u015Flatma gerekiyorsa zincir durur.')}
    $script:PackageControls.PackageRunSummary.Text=$Text;$script:PackageControls.PackageRunConfirm.Text='';$script:PackageControls.PackageRunError.Text=''
    $script:PackageControls.PackageConfirmHint.Text=(T 'Ba\u015Flatmak i\u00E7in yaz\u0131n: ')+$(if($Action -eq 'Downgrade'){'DOWNGRADE'}else{'TRIGGER'})
    $script:PackageControls.PackageSummaryPanel.Visibility='Visible';[void]$script:PackageControls.PackageRunConfirm.Focus()
}
function Start-RemoteOpsSavedPackageRun {
    param($Definition,[string]$Action,[string[]]$Targets,[string]$Confirm)
    Assert-RemoteOpsPackageDefinition $Definition $Action
    $Operation=@($script:OperationCatalog|Where-Object Name -eq PackageDeployment)[0]
    $Values=@{Action=$Action;Targets=($Targets -join ' ');Confirm=$Confirm;PackageDefinition=(Copy-RemoteOpsPackageDefinition $Definition)}
    Start-RemoteOpsRequest -Operation $Operation -Values $Values
}
function Add-SavedPackageOperationField {
    $Row=New-Object Windows.Controls.StackPanel;$Row.Margin='0,0,0,12'
    $Label=New-Object Windows.Controls.TextBlock;$Label.Text=T 'Kay\u0131tl\u0131 paket';$Label.Margin='0,0,0,5';[void]$Row.Children.Add($Label)
    $Picker=New-Object Windows.Controls.ComboBox;$Picker.Tag='SavedPackage';$Picker.DisplayMemberPath='Name'
    foreach($P in (Get-RemoteOpsPackageCatalog $script:PackageCatalogRoot).Packages){[void]$Picker.Items.Add($P)}
    [void]$Row.Children.Add($Picker);$script:OperationFields.Children.Insert(0,$Row)
}
function Add-RemoteOpsManualPackageSaveShortcut {
    $Button=New-Object Windows.Controls.Button;$Button.Content=T 'Bu tan\u0131m\u0131 paket olarak kaydet';$Button.HorizontalAlignment='Left';$Button.Margin='0,8,0,0'
    $Button.Add_Click({
        try{
        $V=Get-OperationValues;$P=New-RemoteOpsPackageDefinition ([string]$V.Application);$A=[string]$V.Action
        if($A -notin @('Install','Uninstall')){throw (T 'Kurulum veya kald\u0131rma i\u015Flemini se\u00E7in.')}
        $P.$A.Enabled=$true;$P.$A.PackagePath=[string]$V.PackagePath;$P.$A.PackageFile=[string]$V.PackageFile;$P.$A.SearchType=[string]$V.SearchType;$P.$A.Application=[string]$V.Application;$P.$A.RegistryKey=[string]$V.RegistryKey;$P.$A.CheckMode=if([string]::IsNullOrWhiteSpace([string]$V.Application)){'Trigger without checks'}else{[string]$V.CheckMode}
        $P.TargetVersion=[string]$V.Version;$P.CollectLogs=[bool]$V.CollectLogs
        Show-RemoteOpsPackageEditor $P -AsCopy
        }catch{
            Write-AppLog ('Manual package definition: '+$_.Exception.Message)
            [void][Windows.MessageBox]::Show($_.Exception.Message,'REMOTE OPS','OK','Warning')
        }
    })
    [void]$script:OperationFields.Children.Add($Button)
}
function Update-RemoteOpsDeploymentRunView {
    param($Run)
    $States=@(Get-RemoteOpsRunCheckpoints $Run.CheckpointRoot)
    $Outcomes=@($States|Where-Object{$_.Terminal -eq $true}|ForEach-Object{$_.Outcome})
    if($Run.Stopped -or $Run.Stage -eq 'Failed'){
        $Missing=if($Run.Stopped){'Cancelled'}else{'Error'}
        $Partial=Get-RemoteOpsPartialDeploymentResult @($Run.Targets) $States -MissingOutcome $Missing
        $Outcomes=@($Partial.Outcomes)
    }
    $StepNames=@{AccessCheck='Erisim kontrolu';Precheck='Kontrol ediliyor';Uninstall='Kaldiriliyor';VerifyUninstall='Kaldirma dogrulaniyor';Install='Kuruluyor';VerifyVersion='Surum dogrulaniyor';VerifyInstall='Kurulum dogrulaniyor';Result='Bitti'}
    $Items=@(foreach($Target in $Run.Targets){
        $State=@($States|Where-Object ComputerName -eq $Target|Select-Object -First 1)
        $Outcome=@($Outcomes|Where-Object ComputerName -eq $Target|Select-Object -First 1)
        $Step=if($State.Count){[string]$State[0].Step}else{'Pending'}
        if($Outcome.Count){$Step='Result'}
        $Text=if($StepNames.ContainsKey($Step)){$StepNames[$Step]}else{'Bekliyor'}
        $Status=if($Outcome.Count){[string]$Outcome[0].Outcome}elseif($State.Count){'Running'}else{'Pending'}
        $Display=if($script:RemoteOpsOutcomeTitles.ContainsKey($Status)){$script:RemoteOpsOutcomeTitles[$Status]}elseif($Status -eq 'Running'){'Isleniyor'}else{'Bekliyor'}
        if($Status -eq 'Unreachable'){$Display=(T 'Atland\u0131 - Eri\u015Filemedi; paket \u00E7al\u0131\u015Ft\u0131r\u0131lmad\u0131');$Text=(T 'Ba\u015Flat\u0131lmad\u0131')}
        if($Outcome.Count -and [string](Get-RemoteOpsPackageValue $Outcome[0] Detail '') -like 'Yetki hatasi*'){$Display=(T 'Yetki hatas\u0131 - paket \u00E7al\u0131\u015Ft\u0131r\u0131lmad\u0131');$Text=(T 'Ba\u015Flat\u0131lmad\u0131')}
        $LogStates=if($State.Count){@(Get-RemoteOpsPackageValue $State[0] Rows @()|ForEach-Object{Get-RemoteOpsPackageValue $_ LogCollectionStatus ''}|Where-Object{$_})}else{@()}
        $LogStatus=if($LogStates -contains 'Failed'){'Failed'}elseif($LogStates -contains 'Success'){'Success'}elseif($LogStates -contains 'NoRecentLogs'){'NoRecentLogs'}else{'NotRequested'}
        [PSCustomObject]@{ComputerName=$Target;PackageName=$(if($State.Count){$State[0].PackageName}else{$Run.Title});Step=$Text;PreviousVersion=$(if($State.Count){Get-RemoteOpsPackageValue $State[0] PreviousVersion ''}else{''});FinalVersion=$(if($State.Count){Get-RemoteOpsPackageValue $State[0] FinalVersion ''}else{''});Outcome=$Display;OutcomeCode=$Status;LogStatusRaw=$LogStatus}
    })
    Set-RemoteOpsRunTargetRows $Run $Items
    $Success=@($Outcomes|Where-Object Outcome -eq Success).Count;$Skipped=@($Outcomes|Where-Object Outcome -eq Skipped).Count
    $Unreachable=@($Outcomes|Where-Object Outcome -eq Unreachable).Count;$Errors=@($Outcomes|Where-Object Outcome -eq Error).Count;$Cancelled=@($Outcomes|Where-Object Outcome -eq Cancelled).Count
    $Unknown=@($Outcomes|Where-Object Outcome -eq Indeterminate).Count;$Reboot=@($Outcomes|Where-Object Outcome -eq RebootRequired).Count
    $Run.FinalSummary=(T 'Ba\u015Far\u0131l\u0131: ')+$Success+' | '+(T 'Atlanan: ')+$Skipped+' | '+(T 'Hata: ')+$Errors
    if($Unreachable){$Run.FinalSummary+=' | '+(T 'Eri\u015Filemedi: ')+$Unreachable}
    if($Cancelled){$Run.FinalSummary+=' | '+(T '\u0130ptal: ')+$Cancelled};if($Unknown){$Run.FinalSummary+=' | '+(T 'Belirsiz: ')+$Unknown};if($Reboot){$Run.FinalSummary+=' | '+(T 'Yeniden ba\u015Flatma: ')+$Reboot}
    if($Run.CancelRequested -and -not $Run.Process.HasExited){$Run.FinalSummary+=' | '+(T '\u0130ptal bekleniyor')}
    if(($Errors+$Unreachable+$Unknown+$Reboot) -gt 0){$Run.ProgressBar.Foreground=[Windows.Media.Brushes]::DarkOrange}
}
