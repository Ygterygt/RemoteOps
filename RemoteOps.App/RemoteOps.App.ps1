####################################################################
# REMOTE OPS - WPF ARAYUZ (UX katmani)  -  RemoteOps.App.ps1
#
# Bu dosya NE YAPAR?
# - Operatorun gordugu pencereyi (XAML/WPF) olusturur: profil secimi,
# operasyon secimi, girdi alanlari, Activity (log) paneli, ilerleme
# cubuklari, Rapor sekmesi ve Ayarlar paneli.
# - Uzak bilgisayarlara KENDISI BAGLANMAZ. Kullanici "Run operation"
# dediginde istegi (Request) JSON -> Base64 yapar ve ayri bir
# powershell.exe sureci olarak RemoteOps.Runner.ps1'i baslatir.
# - Runner'in stdout/stderr dosyalarini ve progress.json dosyasini
# 500 ms'de bir okuyarak ekrani gunceller (OutputTimer).
#
# Akis ozeti:
# RemoteOps.App.bat -> RemoteOps.App.ps1 (bu dosya)
# -> Start-RemoteOpsRequest -> powershell.exe RemoteOps.Runner.ps1 -RequestBase64 ...
# -> Runner, Modules\ApplicationWorkers.ps1 (worker'lar) ve diger Modules\*.ps1'i kullanir
# -> sonuc CSV/HTML'leri C:\Temp\YD_RemoteOps.App\Logs altina yazilir.
#
# Ayrintili diyagram: docs\CALISMA_MANTIGI.md
####################################################################
#
# Strict mode + hata olursa dur: tanimsiz degisken / sessiz hata kalmasin.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
# WPF penceresi icin gereken .NET derlemeleri.
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# --- Uygulama genel (script scope) durum degiskenleri ---
# AppRoot      : bu dosyanin klasoru (RemoteOps.App)
# ProfilePath  : kayitli domain profilleri (DPAPI ile korunan parola dahil)
# ActiveRuns   : su an calisan runner surecleri (ilerleme takibi icin)
# DataRoot     : tum log/rapor/yedeklerin kok klasoru
# SettingsPath : Ayarlar panelindeki secimler (paralellik, log temizleme)
$script:AppRoot = Split-Path -Parent $PSCommandPath
$script:ProfilePath = Join-Path $env:APPDATA 'MDRemoteOps\domains.json'
$script:Profiles = New-Object System.Collections.ArrayList
$script:ActiveRuns = New-Object System.Collections.ArrayList
$script:DataRoot = 'C:\Temp\YD_RemoteOps.App'
$script:LastReport = $null
$script:SettingsPath = Join-Path $env:APPDATA 'MDRemoteOps\settings.json'
# Paralel (ayni anda birden fazla bilgisayar) calismasina izin verilen
# operasyonlar. Sadece okuma yapan veya hedef basina ayri dosya yazan
# operasyonlar burada. Runner'da da AYNI liste vardir; ikisi birlikte guncellenmeli.
$script:ParallelSafeOperations = @('ApplicationCheck','ApplicationInventory','PackageTrigger','PackageDeployment','EndpointInventory','HealthCheck','RegistryRead','ServiceList','ProcessQuery','ScheduledTaskList')
# Rapor yardimcilari (gunluk rapor, HTML uretimi) bu pencerede de kullanilir.
. (Join-Path $script:AppRoot 'RemoteOps.Reports.ps1')
. (Join-Path $script:AppRoot 'RemoteOps.Packages.ps1')
. (Join-Path $script:AppRoot 'RemoteOps.RunState.ps1')
. (Join-Path $script:AppRoot 'RemoteOps.Backups.ps1')
. (Join-Path $script:AppRoot 'RemoteOps.PackageUi.ps1')
. (Join-Path $script:AppRoot 'RemoteOps.History.ps1')
. (Join-Path $script:AppRoot 'RemoteOps.Diagnostics.ps1')
. (Join-Path $script:AppRoot 'RemoteOps.HistoryUi.ps1')
. (Join-Path $script:AppRoot 'RemoteOps.WorkspaceUi.ps1')
. (Join-Path $script:AppRoot 'RemoteOps.WorkflowUi.ps1')
. (Join-Path $script:AppRoot 'RemoteOps.TargetGroups.ps1')
. (Join-Path $script:AppRoot 'RemoteOps.TargetGroupsUi.ps1')
. (Join-Path $script:AppRoot 'RemoteOps.Preview.ps1')
. (Join-Path $script:AppRoot 'RemoteOps.PreviewUi.ps1')
. (Join-Path $script:AppRoot 'RemoteOps.Recovery.ps1')
. (Join-Path $script:AppRoot 'RemoteOps.RecoveryUi.ps1')
. (Join-Path $script:AppRoot 'RemoteOps.RecipeExecution.ps1')
. (Join-Path $script:AppRoot 'RemoteOps.RecipeUi.ps1')
$script:RecipeCatalogRoot=Join-Path $env:APPDATA 'MDRemoteOps\Recipes'
$script:TargetGroupCatalogRoot=Join-Path $env:APPDATA 'MDRemoteOps\TargetGroups'
$script:PackageCatalogRoot=Join-Path $env:APPDATA 'MDRemoteOps\Packages'
# FileOperations modulu yalnizca Test-AOLogCleanupUserName (log temizleme kullanici
# adi dogrulamasi) icin yuklenir; yuklenemezse arayuz yine acilir.
try{. (Join-Path (Split-Path -Parent $script:AppRoot) 'Modules\FileOperations.ps1')}catch{ }
# ====================================================================
# OPERASYON KATALOGU
# Ekrandaki "Operasyon" listesinin kaynagi. Her satir:
# Category : grup adi (Rapor sekmesinde de kullanilir)
# Name     : Runner'daki switch'in esledigi teknik ad (DEGISTIRMEYIN)
# Title    : ekranda gorunen ad
# Fields   : dinamik olusturulacak girdi alanlari (Key = Request.Values icindeki anahtar)
# Type     : Text | Targets | Boolean | Choice(Options ile)
# Yeni operasyon eklerken: buraya satir + Runner switch + Reports.ps1
# RemoteOpsOperationMeta + (gerekirse) Assert-OperationInputs birlikte guncellenir.
# ====================================================================
$script:OperationCatalog = @(
    [pscustomobject]@{Category='Recipes';Name='RecipeRun';Title='Operasyon reçetesi';Fields=@(@{Key='Targets';Label='Target computers';Type='Targets'},@{Key='Confirm';Label='RECETE';Type='Text'})},
    [PSCustomObject]@{Category='Applications';Name='PackageDeployment';Title='Saved package deployment';Fields=@(@{Key='Action';Label='Action';Type='Choice';Options=@('Install','Uninstall','Downgrade')},@{Key='Targets';Label='Target computers';Type='Targets'},@{Key='Confirm';Label='Type TRIGGER or DOWNGRADE';Type='Text'})},
    [PSCustomObject]@{ Category='Applications'; Name='ApplicationCheck'; Title='Application presence check'; Fields=@(@{Key='SearchType';Label='Search by';Type='Choice';Options=@('DisplayName exact','DisplayName contains','ProductID')},@{Key='SearchValue';Label='Application name or ProductID';Type='Text'},@{Key='RegistryKey';Label='Exact registry key (optional)';Type='Text'},@{Key='Targets';Label='Target computers';Type='Targets'}) },
    [PSCustomObject]@{ Category='Applications'; Name='ApplicationInventory'; Title='List installed applications'; Fields=@(@{Key='Targets';Label='Target computers';Type='Targets'}) },
    [PSCustomObject]@{ Category='Applications'; Name='PackageTrigger'; Title='Install or uninstall package'; Fields=@(@{Key='Action';Label='Action';Type='Choice';Options=@('Install','Uninstall')},@{Key='CheckMode';Label='Check mode';Type='Choice';Options=@('Version controlled','Presence only','Trigger without checks')},@{Key='SearchType';Label='Application identity';Type='Choice';Options=@('DisplayName exact','DisplayName contains','ProductID')},@{Key='Application';Label='Application name or ProductID';Type='Text'},@{Key='RegistryKey';Label='Exact registry key (optional)';Type='Text'},@{Key='Version';Label='Target version';Type='Text'},@{Key='PackagePath';Label='Package folder (UNC)';Type='Text'},@{Key='PackageFile';Label='Package file';Type='Text'},@{Key='CollectLogs';Label='Collect package logs';Type='Boolean'},@{Key='Targets';Label='Target computers';Type='Targets'},@{Key='Confirm';Label='Type TRIGGER to confirm';Type='Text'}) },
    [PSCustomObject]@{ Category='Files'; Name='FilePull'; Title='Pull files'; Fields=@(@{Key='Path';Label='Remote path';Type='Text'},@{Key='Targets';Label='Target computers';Type='Targets'}) },
    [PSCustomObject]@{ Category='Files'; Name='FileDelete'; Title='Backup and delete'; Fields=@(@{Key='Path';Label='Remote path';Type='Text'},@{Key='Targets';Label='Target computers';Type='Targets'},@{Key='Confirm';Label='Type DELETE to confirm';Type='Text'}) },
    [PSCustomObject]@{ Category='Files'; Name='FilePush'; Title='Push files'; Fields=@(@{Key='LocalPath';Label='Local source path';Type='Text'},@{Key='Path';Label='Remote destination folder';Type='Text'},@{Key='Overwrite';Label='Overwrite existing files';Type='Boolean'},@{Key='Targets';Label='Target computers';Type='Targets'}) },
    [PSCustomObject]@{ Category='Files'; Name='FileCompare'; Title='Compare file'; Fields=@(@{Key='LocalPath';Label='Reference file';Type='Text'},@{Key='Path';Label='Remote file';Type='Text'},@{Key='Targets';Label='Target computers';Type='Targets'}) },
    [PSCustomObject]@{ Category='Files'; Name='FileBrowser'; Title='Browse file: pull / move / replace'; Fields=@(@{Key='BrowsePath';Label='Remote folder to browse';Type='Text'},@{Key='SelectedPath';Label='Exact remote file path';Type='Text'},@{Key='Action';Label='Action';Type='Choice';Options=@('Pull','Move','Replace')},@{Key='MoveTarget';Label='Move destination folder';Type='Text'},@{Key='ReplaceSource';Label='Replacement source file';Type='Text'},@{Key='Targets';Label='Target computers';Type='Targets'},@{Key='Confirm';Label='Type MOVE or REPLACE';Type='Text'}) },
    [PSCustomObject]@{ Category='Files'; Name='FileRestore'; Title='Restore file backup'; Fields=@(@{Key='BackupPath';Label='Backup (date / computer / file path)';Type='BackupChoice'},@{Key='Targets';Label='Target computers';Type='Targets'},@{Key='Confirm';Label='Type RESTORE to confirm';Type='Text'}) },
    [PSCustomObject]@{ Category='Files'; Name='FileRollback'; Title='Rollback file operation'; Fields=@(@{Key='BackupPath';Label='Rollback run number (blank for latest)';Type='Text'},@{Key='Targets';Label='Target computers';Type='Targets'},@{Key='Confirm';Label='Type ROLLBACK to confirm';Type='Text'}) },
    [PSCustomObject]@{ Category='Inventory'; Name='EndpointInventory'; Title='Endpoint inventory'; Fields=@(@{Key='Targets';Label='Target computers';Type='Targets'}) },
    [PSCustomObject]@{ Category='Inventory'; Name='HealthCheck'; Title='PC health check (detailed)'; Fields=@(@{Key='SkipApps';Label='Skip application scan (faster)';Type='Boolean'},@{Key='Targets';Label='Target computers';Type='Targets'}) },
    [PSCustomObject]@{ Category='Registry'; Name='RegistryRead'; Title='Read registry value'; Fields=@(@{Key='RegistryPath';Label='Registry path';Type='Text'},@{Key='ValueName';Label='Value name';Type='Text'},@{Key='Targets';Label='Target computers';Type='Targets'}) },
    [PSCustomObject]@{ Category='Registry'; Name='RegistryEdit'; Title='Edit registry value'; Fields=@(@{Key='RegistryPath';Label='Registry path';Type='Text'},@{Key='ValueName';Label='Value name';Type='Text'},@{Key='ValueType';Label='Value type';Type='Choice';Options=@('Auto','REG_SZ','REG_DWORD','REG_QWORD','REG_MULTI_SZ','REG_EXPAND_SZ')},@{Key='Value';Label='New value';Type='RegistryData'},@{Key='Targets';Label='Target computers';Type='Targets'},@{Key='Confirm';Label='Type EDIT to confirm';Type='Text'}) },
    [PSCustomObject]@{ Category='Registry'; Name='RegistryDelete'; Title='Delete registry value'; Fields=@(@{Key='RegistryPath';Label='Registry path';Type='Text'},@{Key='ValueName';Label='Value name';Type='Text'},@{Key='Targets';Label='Target computers';Type='Targets'},@{Key='Confirm';Label='Type DELETE to confirm';Type='Text'}) },
    [PSCustomObject]@{ Category='Registry'; Name='RegistryRollback'; Title='Rollback registry change'; Fields=@(@{Key='ManifestPath';Label='Rollback (date / computer / change)';Type='RollbackChoice'},@{Key='Targets';Label='Target computers';Type='Targets'},@{Key='Confirm';Label='Type ROLLBACK to confirm';Type='Text'}) },
    [PSCustomObject]@{ Category='Services'; Name='ServiceList'; Title='List services'; Fields=@(@{Key='Filter';Label='Service name/display filter';Type='Text'},@{Key='Targets';Label='Target computers';Type='Targets'}) },
    [PSCustomObject]@{ Category='Services'; Name='ServiceControl'; Title='Control service'; Fields=@(@{Key='Action';Label='Action';Type='Choice';Options=@('Start','Stop','Restart')},@{Key='ServiceName';Label='Service name';Type='Text'},@{Key='Targets';Label='Target computers';Type='Targets'},@{Key='Confirm';Label='Type the action to confirm';Type='Text'}) },
    [PSCustomObject]@{ Category='Services'; Name='ServiceStartup'; Title='Change service startup'; Fields=@(@{Key='ServiceName';Label='Service name';Type='Text'},@{Key='StartupType';Label='Startup type';Type='Choice';Options=@('Automatic','Manual','Disabled')},@{Key='Targets';Label='Target computers';Type='Targets'},@{Key='Confirm';Label='Type EDIT to confirm';Type='Text'}) },
    [PSCustomObject]@{ Category='Services'; Name='ServiceTaskRollback'; Title='Rollback service/task change'; Fields=@(@{Key='ManifestPath';Label='Rollback (date / computer / change)';Type='RollbackChoice'},@{Key='Targets';Label='Target computers';Type='Targets'},@{Key='Confirm';Label='Type ROLLBACK to confirm';Type='Text'}) },
    [PSCustomObject]@{ Category='Tasks'; Name='ScheduledTaskList'; Title='List scheduled tasks'; Fields=@(@{Key='TaskFilter';Label='Task name filter';Type='Text'},@{Key='Targets';Label='Target computers';Type='Targets'}) },
    [PSCustomObject]@{ Category='Tasks'; Name='ScheduledTaskDelete'; Title='Delete scheduled task (backup)'; Fields=@(@{Key='TaskName';Label='Exact task name';Type='Text'},@{Key='TaskPath';Label='Task folder (optional)';Type='Text'},@{Key='Targets';Label='Target computers';Type='Targets'},@{Key='Confirm';Label='Type DELETE to confirm';Type='Text'}) },
    [PSCustomObject]@{ Category='Tasks'; Name='ScheduledTaskAction'; Title='Run / enable / disable task'; Fields=@(@{Key='Action';Label='Action';Type='Choice';Options=@('Run','Enable','Disable')},@{Key='TaskName';Label='Task name';Type='Text'},@{Key='Targets';Label='Target computers';Type='Targets'},@{Key='Confirm';Label='Type the action to confirm';Type='Text'}) },
    [PSCustomObject]@{ Category='Processes'; Name='ProcessQuery'; Title='Query processes'; Fields=@(@{Key='ProcessFilter';Label='Name or PID (blank for all)';Type='Text'},@{Key='Targets';Label='Target computers';Type='Targets'}) },
    [PSCustomObject]@{ Category='Processes'; Name='ProcessKill'; Title='Kill process'; Fields=@(@{Key='ProcessFilter';Label='Exact name or PID';Type='Text'},@{Key='Targets';Label='Target computers';Type='Targets'},@{Key='Confirm';Label='Type KILL to confirm';Type='Text'}) }
)
# Yerlesik katalogun kopyasi; plugin yeniden yuklemede (Reload) buna geri donulur.
$script:BuiltInOperationCatalog = $script:OperationCatalog

# ====================================================================
# PENCERE TASARIMI (XAML)
# Asagidaki here-string pencerenin tamamini tanimlar. x:Name verilen her kontrol,
# dosyanin sonundaki foreach($Name in @(...)) satiri ile $script:<Ad> degiskenine baglanir.
# DIKKAT: Yeni x:Name eklenirse o listeye de eklenmeli (test bunu kontrol eder).
# ====================================================================
$script:WindowXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="REMOTE OPS" Height="760" Width="1280" MinHeight="550" MinWidth="960" WindowStartupLocation="CenterScreen" Background="#EDF1F5" FontFamily="Segoe UI" FontSize="13" UseLayoutRounding="True" SnapsToDevicePixels="True">
  <Window.Resources>
    <SolidColorBrush x:Key="Ink" Color="#1F3342" />
    <SolidColorBrush x:Key="Muted" Color="#62778A" />
    <SolidColorBrush x:Key="Line" Color="#D3DDE6" />
    <SolidColorBrush x:Key="Brand" Color="#0B64A8" />
    <SolidColorBrush x:Key="CardBg" Color="#FFFFFF" />
    <Style TargetType="Button">
      <Setter Property="Background" Value="#FFFFFF" />
      <Setter Property="Foreground" Value="#1F3342" />
      <Setter Property="BorderBrush" Value="#C3D0DB" />
      <Setter Property="BorderThickness" Value="1" />
      <Setter Property="Padding" Value="12,6" />
      <Setter Property="Cursor" Value="Hand" /><Setter Property="HorizontalContentAlignment" Value="Center" />
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center" />
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.85" />
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="#0B64A8"/><Setter TargetName="Bd" Property="BorderThickness" Value="2"/></Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.45" />
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="#0B64A8" />
      <Setter Property="Foreground" Value="White" />
      <Setter Property="BorderBrush" Value="#0B64A8" />
      <Setter Property="FontWeight" Value="SemiBold" />
    </Style>
    <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Foreground" Value="#B02A2A" />
      <Setter Property="BorderBrush" Value="#E2B4B4" />
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="BorderBrush" Value="#C3D0DB" />
      <Setter Property="Padding" Value="4,3" />
      <Setter Property="VerticalContentAlignment" Value="Center" />
    </Style>
    <Style TargetType="PasswordBox">
      <Setter Property="BorderBrush" Value="#C3D0DB" />
      <Setter Property="Padding" Value="4,3" />
      <Setter Property="VerticalContentAlignment" Value="Center" />
    </Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="#FFFFFF" />
      <Setter Property="BorderBrush" Value="#D3DDE6" />
      <Setter Property="BorderThickness" Value="1" />
      <Setter Property="CornerRadius" Value="10" />
      <Setter Property="Padding" Value="16" />
      <Setter Property="Effect">
        <Setter.Value>
          <DropShadowEffect BlurRadius="12" ShadowDepth="1" Opacity="0.08" Color="#10283C" />
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="SectionTitle" TargetType="TextBlock">
      <Setter Property="FontWeight" Value="SemiBold" />
      <Setter Property="Foreground" Value="#31536B" />
      <Setter Property="FontSize" Value="12" />
    </Style>
    <Style TargetType="TabControl">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TabControl">
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="194"/><ColumnDefinition Width="16"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Border Background="White" BorderBrush="#D3DDE6" BorderThickness="1" CornerRadius="10" Padding="8">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"><StackPanel x:Name="WorkspaceNavigationHost"/></ScrollViewer>
              </Border>
              <TabPanel IsItemsHost="True" Visibility="Collapsed"/>
              <DockPanel Grid.Column="2">
                <Border DockPanel.Dock="Top" Padding="2,0,2,9" Margin="0,0,0,8" BorderBrush="#D3DDE6" BorderThickness="0,0,0,1"><TextBlock x:Name="WorkspaceCurrentPage" Foreground="#62778A" FontSize="12"/></Border>
                <ContentPresenter ContentSource="SelectedContent"/>
              </DockPanel>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="TabItem">
      <Setter Property="Cursor" Value="Hand" /><Setter Property="HorizontalContentAlignment" Value="Center" />
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TabItem">
            <Border x:Name="Bd" Padding="24,10" Margin="0,0,6,-1" Background="Transparent" BorderThickness="0,0,0,3" BorderBrush="Transparent">
              <ContentPresenter x:Name="Cp" ContentSource="Header" TextElement.FontWeight="SemiBold" TextElement.FontSize="14" TextElement.Foreground="#62778A" />
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Cp" Property="TextElement.Foreground" Value="#0B64A8" />
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="#0B64A8" />
                <Setter TargetName="Cp" Property="TextElement.Foreground" Value="#0B64A8" />
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto" />
      <RowDefinition Height="Auto" />
      <RowDefinition Height="*" />
      <RowDefinition Height="Auto" />
      <RowDefinition Height="Auto" />
    </Grid.RowDefinitions>
    <Border Grid.Row="0" CornerRadius="10" Padding="16,8" Margin="0,0,0,8">
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
          <GradientStop Color="#073F73" Offset="0" />
          <GradientStop Color="#0B64A8" Offset="0.6" />
          <GradientStop Color="#0A8C83" Offset="1" />
        </LinearGradientBrush>
      </Border.Background>
      <DockPanel>
        <Border DockPanel.Dock="Right" Background="#33FFFFFF" CornerRadius="14" Padding="14,5" VerticalAlignment="Center">
          <TextBlock x:Name="ActiveIdentity" Foreground="White" FontSize="12.5" />
        </Border>
        <StackPanel>
          <TextBlock Text="REMOTE OPS" Foreground="White" FontSize="19" FontWeight="Bold" />
          <TextBlock x:Name="WorkspaceVersion" Text="YD RemoteOps · Tek operatör" Foreground="#CFE6F5" FontSize="12" />
        </StackPanel>
      </DockPanel>
    </Border>
    <Border Grid.Row="1" Style="{StaticResource Card}" Padding="12,8" Margin="0,0,0,10">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto" />
          <ColumnDefinition Width="230" />
          <ColumnDefinition Width="*" />
          <ColumnDefinition Width="Auto" />
          <ColumnDefinition Width="Auto" />
        </Grid.ColumnDefinitions>
        <TextBlock Text="Çalıştırma hesabı" VerticalAlignment="Center" Foreground="#62778A" Margin="0,0,12,0" />
        <ComboBox x:Name="ProfileList" Grid.Column="1" DisplayMemberPath="Display" Padding="6,4" />
        <TextBlock Grid.Column="2" Text="Main mevcut Windows oturumunu kullanır" Foreground="#62778A" VerticalAlignment="Center" Margin="12,0" TextTrimming="CharacterEllipsis" x:Name="RunModeLabel" />
        <StackPanel x:Name="SharedParallelHost" Grid.Column="3" Orientation="Horizontal">
          <TextBlock Text="Eşzamanlı PC" VerticalAlignment="Center" Foreground="#62778A" Margin="0,0,6,0" />
          <ComboBox x:Name="ParallelismPicker" Width="58" VerticalAlignment="Center" Margin="0,0,18,0" Padding="6,4" />
        </StackPanel>
        <StackPanel x:Name="ProfileToolsHost" Grid.Column="4" Orientation="Horizontal">
          <Button x:Name="ToggleProfiles" Content="Profiller" Margin="10,0,0,0" Padding="12,4" />
          <Button x:Name="OpenSettings" Content="" FontFamily="Segoe MDL2 Assets" FontSize="17" Width="36" Height="30" Padding="0" HorizontalAlignment="Right" Margin="8,0,0,0" ToolTip="Ayarlar" />
        </StackPanel>
      </Grid>
    </Border>
    <TabControl x:Name="MainTabs" Grid.Row="2" Background="Transparent" BorderThickness="0" Padding="0" SelectedIndex="0">
      <TabItem x:Name="PackagesTab" Header="Paketlerim">
        <ContentControl x:Name="PackageLibraryHost" />
      </TabItem>
      <TabItem x:Name="PackageEditorTab" Header="Paket Oluştur">
        <ContentControl x:Name="PackageEditorHost" />
      </TabItem>
      <TabItem Header="Operasyon" xmlns:d4p1="OperationTab" x:Name="OperationTab">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="*" />
          </Grid.RowDefinitions>
          <Grid Grid.Row="0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*" />
            </Grid.ColumnDefinitions>
            <Grid Grid.Column="0">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto" />
                <RowDefinition Height="*" />
                <RowDefinition Height="Auto" />
              </Grid.RowDefinitions>
              <Border Grid.Row="0" Style="{StaticResource Card}" Padding="14,10" Margin="0,0,0,10">
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="110" />
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="90" />
                  </Grid.ColumnDefinitions>
                  <TextBlock Text="OPERASYON" Style="{StaticResource SectionTitle}" VerticalAlignment="Center" />
                  <ComboBox x:Name="OperationPicker" Grid.Column="1" DisplayMemberPath="Display" Margin="8,0" Padding="6,5" />
                  <Button x:Name="RefreshModules" Grid.Column="2" Content="Yenile" ToolTip="Operasyon eklentilerini yeniden yükle" />
                </Grid>
              </Border>
              <Border Grid.Row="1" Style="{StaticResource Card}">
                <DockPanel>
                  <StackPanel DockPanel.Dock="Top">
                    <TextBlock Text="OPERASYON BİLGİLERİ" Style="{StaticResource SectionTitle}" Margin="0,0,0,6" />
                    <Border Background="#EAF3FA" CornerRadius="6" Padding="10,7" Margin="0,0,0,12">
                      <TextBlock x:Name="OperationDescription" Foreground="#2F5470" TextWrapping="Wrap" FontSize="12" />
                    </Border>
                  </StackPanel>
                  <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <StackPanel x:Name="OperationFields" />
                  </ScrollViewer>
                </DockPanel>
              </Border>
              <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
                <Button x:Name="PreviewOperation" Content="Önizle" Padding="18,10" Margin="0,0,8,0" FontSize="14" />
                <Button x:Name="RunOperation" Content="Operasyonu çalıştır" Style="{StaticResource PrimaryButton}" Padding="22,10" FontSize="14" />
              </StackPanel>
            </Grid>
          </Grid>
        </Grid>
      </TabItem>
      <TabItem Header="Rapor" xmlns:d4p1="ReportTab" x:Name="ReportTab">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
          </Grid.RowDefinitions>
          <DockPanel Grid.Row="0" Margin="0,0,0,12">
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
              <Button x:Name="ReportPrev" Content="‹" Width="34" FontSize="16" Padding="0,0,0,2" ToolTip="Önceki gün" />
              <DatePicker x:Name="ReportDate" Width="130" Margin="6,0" VerticalContentAlignment="Center" />
              <Button x:Name="ReportNext" Content="›" Width="34" FontSize="16" Padding="0,0,0,2" ToolTip="Sonraki gün" />
              <Button x:Name="ReportToday" Content="Bugün" Margin="10,0,0,0" />
              <Button x:Name="ReportRefresh" Content="Yenile" Margin="6,0,0,0" />
              <Button x:Name="ReportExport" Content="HTML olarak aç" Style="{StaticResource PrimaryButton}" Margin="6,0,0,0" />
            </StackPanel>
            <StackPanel>
              <TextBlock Text="Günlük Rapor" FontSize="20" FontWeight="SemiBold" Foreground="#1F3342" />
              <TextBlock x:Name="ReportSubtitle" Foreground="#62778A" FontSize="12" />
            </StackPanel>
          </DockPanel>
          <UniformGrid Grid.Row="1" Columns="5" Margin="0,0,0,12">
            <Border Style="{StaticResource Card}" Margin="0,0,10,0" BorderThickness="0,4,0,0" BorderBrush="#0B64A8">
              <StackPanel>
                <TextBlock Text="Tamamlanan İşlem" Foreground="#62778A" FontSize="12" />
                <TextBlock x:Name="CardTotal" Text="0" FontSize="32" FontWeight="SemiBold" Foreground="#1F3342" />
                <TextBlock x:Name="CardTotalSub" Foreground="#62778A" FontSize="11.5" />
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}" Margin="0,0,10,0" BorderThickness="0,4,0,0" BorderBrush="#5B7FA6">
              <StackPanel>
                <TextBlock Text="Benzersiz Bilgisayar" Foreground="#62778A" FontSize="12" />
                <TextBlock x:Name="CardComputers" Text="0" FontSize="32" FontWeight="SemiBold" Foreground="#1F3342" />
                <TextBlock x:Name="CardComputersSub" Foreground="#62778A" FontSize="11.5" />
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}" Margin="0,0,10,0" BorderThickness="0,4,0,0" BorderBrush="#17855A">
              <StackPanel>
                <TextBlock Text="Başarılı" Foreground="#62778A" FontSize="12" />
                <TextBlock x:Name="CardSuccess" Text="0" FontSize="32" FontWeight="SemiBold" Foreground="#17855A" />
                <TextBlock x:Name="CardSuccessSub" Foreground="#62778A" FontSize="11.5" />
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}" Margin="0,0,10,0" BorderThickness="0,4,0,0" BorderBrush="#B7791F">
              <StackPanel>
                <TextBlock Text="Atlanan / Yok / Erişilemedi" Foreground="#62778A" FontSize="12" />
                <TextBlock x:Name="CardSkipped" Text="0" FontSize="32" FontWeight="SemiBold" Foreground="#B7791F" />
                <TextBlock x:Name="CardSkippedSub" Foreground="#62778A" FontSize="11.5" />
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}" BorderThickness="0,4,0,0" BorderBrush="#C53A3A">
              <StackPanel>
                <TextBlock Text="Hata / Dikkat" Foreground="#62778A" FontSize="12" />
                <TextBlock x:Name="CardProblem" Text="0" FontSize="32" FontWeight="SemiBold" Foreground="#C53A3A" />
                <TextBlock x:Name="CardProblemSub" Foreground="#62778A" FontSize="11.5" />
              </StackPanel>
            </Border>
          </UniformGrid>
          <Border Grid.Row="2" Style="{StaticResource Card}" Padding="16,12" Margin="0,0,0,12">
            <StackPanel>
              <TextBlock Text="SONUÇ DAĞILIMI" Style="{StaticResource SectionTitle}" Margin="0,0,0,8" />
              <Border CornerRadius="7" Height="16" ClipToBounds="True" Background="#E6ECF1">
                <Grid x:Name="OutcomeBar" />
              </Border>
              <TextBlock x:Name="OutcomeLegend" Foreground="#4A6073" FontSize="12" Margin="0,8,0,0" TextWrapping="Wrap" />
            </StackPanel>
          </Border>
          <Grid Grid.Row="3">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="2*" />
              <ColumnDefinition Width="12" />
              <ColumnDefinition Width="*" />
            </Grid.ColumnDefinitions>
            <Border Grid.Column="0" Style="{StaticResource Card}">
              <DockPanel>
                <TextBlock DockPanel.Dock="Top" Text="İŞLEM YAPILAN KATEGORİLER" Style="{StaticResource SectionTitle}" Margin="0,0,0,8" />
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                  <StackPanel>
                    <TextBlock x:Name="ReportEmpty" Text="Seçilen günde kayıtlı işlem yok." Foreground="#62778A" Margin="0,24,0,0" HorizontalAlignment="Center" Visibility="Collapsed" />
                    <StackPanel x:Name="CategoryPanel" />
                  </StackPanel>
                </ScrollViewer>
              </DockPanel>
            </Border>
            <Grid Grid.Column="2">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto" />
                <RowDefinition Height="12" />
                <RowDefinition Height="*" />
              </Grid.RowDefinitions>
              <Border Grid.Row="0" Style="{StaticResource Card}">
                <StackPanel>
                  <TextBlock Text="SAATLİK YOĞUNLUK" Style="{StaticResource SectionTitle}" Margin="0,0,0,8" />
                  <Grid x:Name="HourPanel" Height="96" />
                  <Grid x:Name="HourLabels" Margin="0,3,0,0" />
                </StackPanel>
              </Border>
              <Border Grid.Row="2" Style="{StaticResource Card}">
                <DockPanel>
                  <TextBlock DockPanel.Dock="Top" Text="EN ÇOK İŞLEM YAPILAN BİLGİSAYARLAR" Style="{StaticResource SectionTitle}" Margin="0,0,0,8" />
                  <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <StackPanel x:Name="ComputerPanel" />
                  </ScrollViewer>
                </DockPanel>
              </Border>
            </Grid>
          </Grid>
        </Grid>
      </TabItem>
    </TabControl>
    <Grid x:Name="SettingsOverlay" Grid.RowSpan="5" Visibility="Collapsed" Background="#B3102030">
      <Border Style="{StaticResource Card}" MaxWidth="900" VerticalAlignment="Center" HorizontalAlignment="Center" Margin="40">
        <StackPanel>
          <DockPanel Margin="0,0,0,14">
            <Button x:Name="CloseSettings" DockPanel.Dock="Right" Content="Kapat" Padding="16,5" />
            <TextBlock Text="AYARLAR" FontSize="16" FontWeight="SemiBold" Foreground="#1F3342" VerticalAlignment="Center" />
          </DockPanel>
          <TextBlock Text="PAKET OPERASYONLARI" Style="{StaticResource SectionTitle}" Margin="0,0,0,10" />
          <CheckBox x:Name="SettingCleanupLogs" Content="Paket loglarını çektikten sonra hedefte kayıtlı kullanıcı adını içeren logları temizle" FontWeight="SemiBold" Margin="0,0,0,8" />
          <TextBlock x:Name="CleanupExplain" TextWrapping="Wrap" Foreground="#4A6073" FontSize="12" Margin="22,0,0,10" />
          <Border Background="#EAF3FA" CornerRadius="6" Padding="10,8" Margin="22,0,0,10">
            <TextBlock x:Name="CleanupPreview" TextWrapping="Wrap" Foreground="#2F5470" FontSize="12" />
          </Border>
          <TextBlock Text="Ayarlar bu Windows kullanıcısı için %APPDATA%\MDRemoteOps\settings.json dosyasında saklanır." Foreground="#62778A" FontSize="11" Margin="0,4,0,0" />
        </StackPanel>
      </Border>
    </Grid>
    <Expander x:Name="SharedRuns" Grid.Row="3" Header="Devam eden işler ve sonuçlar" Margin="0,8,0,0" IsExpanded="False">
      <Border Style="{StaticResource Card}" Padding="10">
        <DockPanel>
          <DockPanel DockPanel.Dock="Top">
            <StackPanel x:Name="SharedStopHost" DockPanel.Dock="Right" Orientation="Horizontal">
              <Button x:Name="ForceStopOperation" Content="Zorla durdur" Style="{StaticResource DangerButton}" IsEnabled="False" Padding="12,5" />
              <Button x:Name="StopOperation" Content="Durdur" Style="{StaticResource DangerButton}" Padding="12,5" FontSize="12" Margin="8,0,0,0" IsEnabled="False" ToolTip="Devam eden operasyonları durdurur" />
            </StackPanel>
            <TextBlock x:Name="CommonRunSummary" Text="Henüz çalışma yok" FontWeight="SemiBold" Foreground="#31536B" VerticalAlignment="Center" />
          </DockPanel>
          <StackPanel DockPanel.Dock="Top" Margin="0,8,0,0">
            <DockPanel>
              <Button x:Name="OpenPulledFiles" DockPanel.Dock="Right" Content="Çekilen dosyalar" IsEnabled="False" Padding="10,4" Margin="8,0,0,0" />
              <Button x:Name="OpenCollectedLogs" DockPanel.Dock="Right" Content="Toplanan loglar" IsEnabled="False" Padding="10,4" Margin="8,0,0,0" />
              <Button x:Name="OpenRunReport" DockPanel.Dock="Right" Content="HTML raporunu aç" IsEnabled="False" Padding="10,4" Margin="8,0,0,0" />
              <ComboBox x:Name="RunPicker" DisplayMemberPath="Label" SelectedValuePath="Id" MinHeight="30" ToolTip="Yeni iş başladığında son çalışma seçilir. Önceki işleri buradan seçebilirsiniz." />
            </DockPanel>
            <TextBlock x:Name="SelectedRunSummary" Text="Henüz çalışma yok" Margin="0,6,0,0" Foreground="#31536B" TextWrapping="Wrap" />
          </StackPanel>
          <ScrollViewer MaxHeight="225" VerticalScrollBarVisibility="Auto" Margin="0,8,0,0">
            <StackPanel>
              <StackPanel x:Name="RunProgressPanel" />
              <DataGrid x:Name="DeploymentTargets" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False" MaxHeight="180" HeadersVisibility="Column" BorderThickness="0" Background="White" Margin="0,8,0,0">
                <DataGrid.GroupStyle>
                  <GroupStyle><GroupStyle.HeaderTemplate><DataTemplate>
                    <Border Background="#E8F2F5" Padding="8,5" Margin="0,6,0,2"><TextBlock Text="{Binding Name}" FontWeight="SemiBold" Foreground="#31536B" /></Border>
                  </DataTemplate></GroupStyle.HeaderTemplate></GroupStyle>
                </DataGrid.GroupStyle>
                <DataGrid.RowStyle>
                  <Style TargetType="DataGridRow">
                    <Style.Triggers>
                      <DataTrigger Binding="{Binding OutcomeCode}" Value="Unreachable"><Setter Property="Background" Value="#FBF0D9" /><Setter Property="Foreground" Value="#885B18" /></DataTrigger>
                      <DataTrigger Binding="{Binding OutcomeCode}" Value="Skipped"><Setter Property="Background" Value="#FBF0D9" /></DataTrigger>
                      <DataTrigger Binding="{Binding OutcomeCode}" Value="Error"><Setter Property="Background" Value="#FBE5E5" /><Setter Property="Foreground" Value="#A02E2E" /></DataTrigger>
                    </Style.Triggers>
                  </Style>
                </DataGrid.RowStyle>
                <DataGrid.Columns>
                  <DataGridTextColumn Header="Bilgisayar" Binding="{Binding ComputerName}" Width="160" />
                  <DataGridTextColumn Header="Paket / İşlem" Binding="{Binding PackageName}" Width="*" MinWidth="200" />
                  <DataGridTextColumn Header="Aşama" Binding="{Binding Step}" Width="180" />
                  <DataGridTextColumn Header="Önceki sürüm" Binding="{Binding PreviousVersion}" Width="110" />
                  <DataGridTextColumn Header="Son sürüm" Binding="{Binding FinalVersion}" Width="110" />
                  <DataGridTextColumn Header="Sonuç" Binding="{Binding Outcome}" Width="170" />
                  <DataGridTextColumn Header="Log durumu" Binding="{Binding LogStatus}" Width="150" />
                  <DataGridTemplateColumn Header="Loglar" Width="95"><DataGridTemplateColumn.CellTemplate><DataTemplate>
                    <Button Content="Logları aç" Tag="{Binding LogPath}" IsEnabled="{Binding CanOpenLogs}" Padding="6,2" ToolTip="Bu çalıştırmadaki bilgisayarın toplanan loglarını açar" />
                  </DataTemplate></DataGridTemplateColumn.CellTemplate></DataGridTemplateColumn>
                  <DataGridTemplateColumn Header="Çekilen dosya" Width="115"><DataGridTemplateColumn.CellTemplate><DataTemplate>
                    <Button Content="Çekileni göster" Uid="PulledFile" Tag="{Binding PulledPath}" IsEnabled="{Binding CanOpenPulled}" Padding="6,2" ToolTip="{Binding PulledPath}" />
                  </DataTemplate></DataGridTemplateColumn.CellTemplate></DataGridTemplateColumn>
                </DataGrid.Columns>
              </DataGrid>
            </StackPanel>
          </ScrollViewer>
        </DockPanel>
      </Border>
    </Expander>
    <Expander Grid.Row="4" Header="Teknik etkinlik" Margin="0,6,0,0" IsExpanded="False">
      <Border Background="#1F3342" CornerRadius="10" Margin="0,4,0,0" Padding="12" Height="145">
        <DockPanel>
          <DockPanel DockPanel.Dock="Top" Margin="0,0,0,8">
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
              <Button x:Name="OpenLogs" Content="Log klasörü" Padding="10,2" Margin="0,0,6,0" />
              <Button x:Name="ClearActivity" Content="Temizle" Padding="10,2" />
            </StackPanel>
            <TextBlock Text="ETKİNLİK" Foreground="#B8D0DF" FontWeight="SemiBold" VerticalAlignment="Center" />
          </DockPanel>
          <TextBox x:Name="ActivityLog" IsReadOnly="True" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap" Background="#1F3342" Foreground="#E0E9EE" BorderThickness="0" FontFamily="Consolas" FontSize="12" />
        </DockPanel>
      </Border>
    </Expander>
    <Grid x:Name="ProfileOverlay" Grid.RowSpan="5" Visibility="Collapsed" Background="#B3102030">
      <Border Style="{StaticResource Card}" Width="560" MaxHeight="540" VerticalAlignment="Center" HorizontalAlignment="Center">
        <DockPanel>
          <DockPanel DockPanel.Dock="Top" Margin="0,0,0,10">
            <Button x:Name="CloseProfileEditor" DockPanel.Dock="Right" Content="Kapat" />
            <TextBlock Text="Çalıştırma profilleri" FontSize="19" FontWeight="SemiBold" Foreground="#1F3342" />
          </DockPanel>
          <ScrollViewer x:Name="ProfileEditorHost" VerticalScrollBarVisibility="Auto">
            <StackPanel x:Name="ProfileEditor" DockPanel.Dock="Top" Margin="0,0,0,8">
              <Grid Margin="0,10,0,0">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="82" />
                  <ColumnDefinition Width="*" />
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto" />
                  <RowDefinition Height="Auto" />
                  <RowDefinition Height="Auto" />
                  <RowDefinition Height="Auto" />
                  <RowDefinition Height="Auto" />
                </Grid.RowDefinitions>
                <TextBlock Text="Domain" VerticalAlignment="Center" Margin="0,4" />
                <TextBox x:Name="DomainInput" Grid.Column="1" Margin="0,3" />
                <TextBlock Text="Kullanıcı" Grid.Row="1" VerticalAlignment="Center" Margin="0,4" />
                <TextBox x:Name="UsernameInput" Grid.Row="1" Grid.Column="1" Margin="0,3" />
                <TextBlock Text="Parola" Grid.Row="2" VerticalAlignment="Center" Margin="0,4" />
                <PasswordBox x:Name="PasswordInput" Grid.Row="2" Grid.Column="1" Margin="0,3" />
                <TextBlock x:Name="PasswordState" Grid.Row="3" Grid.Column="1" FontSize="11" Foreground="#62778A" TextWrapping="Wrap" Margin="0,1,0,0" />
                <CheckBox x:Name="MainProfileInput" Grid.Row="4" Grid.Column="1" Content="Main domain olarak kullan" Margin="0,8,0,3" />
              </Grid>
              <WrapPanel Margin="0,8,0,0">
                <Button x:Name="AddProfile" Content="Ekle / Güncelle" Style="{StaticResource PrimaryButton}" Margin="0,0,6,6" />
                <Button x:Name="TestProfile" Content="Parolayı doğrula" Margin="0,0,6,6" ToolTip="Parolayı domain denetleyicisinde bir kez dener." />
                <Button x:Name="RemoveProfile" Content="Sil" Style="{StaticResource DangerButton}" Margin="0,0,0,6" />
              </WrapPanel>
              <TextBlock Text="Parola değiştiyse profili seçin, yeni parolayı yazın ve Ekle / Güncelle'ye basın. Parola alanı boşsa kayıtlı parola korunur." Foreground="#62778A" FontSize="11" TextWrapping="Wrap" Margin="0,2,0,0" />
            </StackPanel>
          </ScrollViewer>
        </DockPanel>
      </Border>
    </Grid>
  </Grid>
</Window>
'@

# ====================================================================
# YARDIMCI FONKSIYONLAR - PROFIL / PAROLA
# ====================================================================
#
# Activity paneline saat damgali bir satir yazar ve en alta kaydirir.
function Write-AppLog {
    param([Parameter(Mandatory=$true)][string]$Message)
    $script:ActivityLog.AppendText("[$(Get-Date -Format 'HH:mm:ss')] $Message`r`n")
    $script:ActivityLog.ScrollToEnd()
}
# Parolayi Windows DPAPI ile sifreler (yalnizca ayni Windows kullanicisi + makine cozebilir).
function Protect-ProfilePassword {
    param([Parameter(Mandatory=$true)][System.Security.SecureString]$Password)
    return ConvertFrom-SecureString -SecureString $Password
}
# DPAPI ile saklanan parolayi SecureString'e cevirir. Kullanici/makine
# degistiyse cozulemez; anlasilir bir hata mesaji firlatilir.
function Unprotect-ProfilePassword {
    param([Parameter(Mandatory=$true)][string]$ProtectedPassword)
    try{return ConvertTo-SecureString -String $ProtectedPassword}
    catch{
        throw ([regex]::Unescape('Kay\u0131tl\u0131 parola \u00E7\u00F6z\u00FClemedi (Windows kullan\u0131c\u0131s\u0131 veya bilgisayar de\u011Fi\u015Fmi\u015F olabilir). Profili se\u00E7ip parolay\u0131 yeniden yaz\u0131n ve Ekle / G\u00FCncelle d\u00FC\u011Fmesine bas\u0131n.'))
    }
}

# Profilleri %APPDATA%\MDRemoteOps\domains.json dosyasina yazar.
# Once .tmp dosyasina yazip sonra uzerine tasir (yarim yazilmis dosya kalmaz).
function Save-ProfileStore {
    $Parent = Split-Path -Parent $script:ProfilePath
    if (-not (Test-Path -LiteralPath $Parent)) { New-Item -ItemType Directory -Path $Parent -Force | Out-Null }
    $Rows = @()
    foreach ($Profile in $script:Profiles) {
        $Rows += [PSCustomObject]@{ Domain=$Profile.Domain; UserName=$Profile.UserName; ProtectedPassword=$Profile.ProtectedPassword; IsMain=[bool]$Profile.IsMain }
    }
    $Temporary=$script:ProfilePath+'.tmp'
    ConvertTo-Json -InputObject $Rows -Depth 4 | Set-Content -LiteralPath $Temporary -Encoding UTF8
    Move-Item -LiteralPath $Temporary -Destination $script:ProfilePath -Force
}
# Eski surumlerin yazdigi bozuk formati (her alan bir dizi) satir listesine
# donusturur. Normal formatta veriyi oldugu gibi dondurur.
function ConvertTo-ProfileStoreRows {
    param([Parameter(Mandatory=$true)]$StoredData)
    if ($StoredData -is [array]) { return @($StoredData) }
    $DomainValue=Get-OptionalPropertyValue -InputObject $StoredData -Name 'Domain'
    $UserValue=Get-OptionalPropertyValue -InputObject $StoredData -Name 'UserName'
    $PasswordValue=Get-OptionalPropertyValue -InputObject $StoredData -Name 'ProtectedPassword'
    $MainValue=Get-OptionalPropertyValue -InputObject $StoredData -Name 'IsMain'
    $HasArrayFields=($DomainValue -is [array] -or $UserValue -is [array] -or $PasswordValue -is [array] -or $MainValue -is [array])
    if (-not $HasArrayFields) { return @($StoredData) }
    $DomainValues=@($DomainValue)
    $UserValues=@($UserValue)
    $PasswordValues=@($PasswordValue)
    $MainValues=@($MainValue)
    $Count=[Math]::Max([Math]::Max($DomainValues.Count,$UserValues.Count),[Math]::Max($PasswordValues.Count,$MainValues.Count))
    $Rows=New-Object 'System.Collections.Generic.List[object]'
    for($Index=0;$Index -lt $Count;$Index++){
        $Rows.Add([PSCustomObject]@{
            Domain=$(if($Index -lt $DomainValues.Count){$DomainValues[$Index]}else{''})
            UserName=$(if($Index -lt $UserValues.Count){$UserValues[$Index]}else{''})
            ProtectedPassword=$(if($Index -lt $PasswordValues.Count){$PasswordValues[$Index]}else{''})
            IsMain=$(if($Index -lt $MainValues.Count){[bool]$MainValues[$Index]}else{$false})
        })
    }
    return $Rows.ToArray()
}
# Uygulama acilisinda kayitli profilleri okur ve $script:Profiles listesine ekler.
# Eski formatta kayit bulunduysa yeni formatla tekrar kaydeder (migrasyon).
function Load-ProfileStore {
    if (-not (Test-Path -LiteralPath $script:ProfilePath -PathType Leaf)) { return }
    try {
        $StoredData=Get-Content -LiteralPath $script:ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($Row in @(ConvertTo-ProfileStoreRows -StoredData $StoredData)) {
            $Domain=[string]$Row.Domain
            $UserName=[string]$Row.UserName
            if([string]::IsNullOrWhiteSpace($Domain)-or [string]::IsNullOrWhiteSpace($UserName)){continue}
            $IsMain=[bool]$Row.IsMain
            [void]$script:Profiles.Add([PSCustomObject]@{ Domain=$Domain; UserName=$UserName; ProtectedPassword=[string]$Row.ProtectedPassword; IsMain=$IsMain; Display=('{0}\{1}{2}' -f $Domain,$UserName,$(if($IsMain){'  [MAIN]'}else{''})) })
        }
        if($StoredData -isnot [array]){
            $LegacyFields=@(@('Domain','UserName','ProtectedPassword','IsMain')|Where-Object{(Get-OptionalPropertyValue -InputObject $StoredData -Name $_) -is [array]})
            if($LegacyFields.Count -gt 0){
                Save-ProfileStore
                Write-AppLog 'Recovered and migrated saved domain profiles.'
            }
        }
    }
    catch { Write-AppLog "Could not load saved profiles: $($_.Exception.Message)" }
}
# Profil listesini ve ust bantdaki "Main: DOMAIN\kullanici" yazisini yeniler.
# Main profil: mevcut Windows oturumu ile calisir (parola kullanilmaz).
function Refresh-ProfileList {
    $script:ProfileList.ItemsSource = $null; $script:ProfileList.ItemsSource = @($script:Profiles)
    $Main = @($script:Profiles | Where-Object IsMain | Select-Object -First 1)
    if ($Main.Count -gt 0) {
        $script:ActiveIdentity.Text = "Main: $($Main[0].Domain)\$($Main[0].UserName)"
        $script:RunModeLabel.Text = 'Main runs in current session'
        if($null -eq $script:ProfileList.SelectedItem){
            $script:ProfileList.SelectedItem=$Main[0]
        }
    }
    else {
        $script:ActiveIdentity.Text = 'No Main domain selected'
        $script:RunModeLabel.Text = 'Select a Main profile first'
    }
    Update-PasswordState
}
# ====================================================================
# DINAMIK GIRDI ALANLARI
# Secilen operasyonun Fields listesine gore form satirlari olusturulur.
# Her kontrolun Tag degeri = alan Key'i; Get-OperationValues bunu okur.
# ====================================================================
#
# Tek bir alan icin (etiket + kontrol) Grid satiri olusturur.
# Choice -> ComboBox, Boolean -> CheckBox, Targets -> cok satirli TextBox
# (+ "N bilgisayar" sayaci), diger -> TextBox.
function Get-RemoteOpsOperationExample {
    param($Operation,$Field)
    switch([string]$Field.Key){
        'Targets' {return 'Örn: PC-001 ve PC-002 (her satıra bir bilgisayar).'}
        'Path' {if($Operation.Name -eq 'FilePush'){return 'Örn: C:\Temp\Ornek\Hedef (hedef bilgisayardaki klasör).'};return 'Örn: C:\Temp\Ornek\rapor.txt veya C:\Temp\Ornek (hedef bilgisayar yolu).'}
        'LocalPath' {return 'Örn: C:\Paketler\ornek.txt (bu bilgisayardaki kaynak / referans dosya).'}
        'BrowsePath' {return 'Örn: C:\Temp\Ornek (hedefte listelenecek klasör).'}
        'SelectedPath' {return 'Örn: C:\Temp\Ornek\rapor.txt (listeden seçilen dosyanın tam yolu).'}
        'MoveTarget' {return 'Örn: C:\Temp\Ornek\Arsiv. Yalnızca Move için doldurun.'}
        'ReplaceSource' {return 'Örn: C:\Paketler\yeni.txt. Yalnızca Replace için yerel kaynak.'}
        'BackupPath' {if($Operation.Name -eq 'FileRestore'){return 'Tarih, bilgisayar ve dosya yoluna gore yedek secin. Listeyi yenilemek icin Refresh modules kullanin.'};return 'Örn: 1 (listelenen yedek/çalışma numarası). Boş bırakmak en son uygun kaydı seçer.'}
        'RegistryPath' {return 'HKLM\Software\Firma, HKEY_LOCAL_MACHINE\Software\Firma, HKCU\Software\Firma veya HKU\<SID>\Software\Firma. On eksiz yol HKLM sayilir. HKCU hedefte oturum acmis tek kullanicidir.'}
        'ValueName' {return 'Örn: InstallPath (registry değerinin adı).'}
        'ManifestPath' {return 'Kayitli islem sonrasi deger -> geri yuklenecek eski deger. Bu ozet canli sorgu degildir. Tarih ve bilgisayara gore secin; Refresh modules listeyi yeniler.'}
        'ServiceName' {return 'Örn: OrnekUygulamaSvc. Görünen başlığı değil, servis listesindeki Name alanını girin.'}
        'Filter' {return 'Örn: OrnekUygulama. Boş bırakılırsa bütün servisler listelenir.'}
        'TaskFilter' {return 'Örn: OrnekBakim. Boş bırakılırsa bütün görevler listelenir.'}
        'TaskName' {if($Operation.Name -eq 'ScheduledTaskDelete'){return 'Örn: OrnekBakim. Görev klasörünü ayrı Task folder alanına girin.'};return 'Örn: OrnekBakim. Aynı adda birden fazla görev varsa işlem reddedilir.'}
        'TaskPath' {return 'Örn: \OrnekFirma\ (görev zamanlayıcı klasörü; son ters eğik çizgi dahil).'}
        'ProcessFilter' {if($Operation.Name -eq 'ProcessKill'){return 'Örn: 12345 (PID) veya ornek.exe (tam ad). Önce süreç sorgusuyla doğru hedefi doğrulayın.'};return 'Örn: ornek veya 12345 (PID). Boş: bütün süreçler.'}
        'StartupType' {return 'Manual: elle başlatma; Automatic: otomatik; Disabled: devre dışı.'}
        'ValueType' {return 'Auto: mevcut tur korunur, yeni deger REG_SZ olur. Acik tur secimi yeni deger icindir; mevcut turle uyusmazsa islem reddedilir.'}
        'Value' {if($Operation.Name -eq 'RegistryEdit'){return 'DWORD/QWORD: 42 veya 0x2A. REG_MULTI_SZ: ["one","two"] (bos dizi: []). REG_EXPAND_SZ: %SystemRoot%\Temp ham olarak saklanir. Bos metin REG_SZ/REG_EXPAND_SZ icin gecerlidir.'}}
        'Confirm' {return 'İlgili işlemde istenen onay sözcüğünü büyük harflerle girin; örnekler otomatik doldurulmaz.'}
    }
    return ''
}
function Add-OperationField {
    param([Parameter(Mandatory=$true)]$Field)
    $Row = New-Object System.Windows.Controls.Grid
    $Row.Margin = '0,0,0,9'
    $LabelColumn = New-Object System.Windows.Controls.ColumnDefinition
    $LabelColumn.Width = [System.Windows.GridLength]::new(190)
    [void]$Row.ColumnDefinitions.Add($LabelColumn)
    $InputColumn = New-Object System.Windows.Controls.ColumnDefinition
    $InputColumn.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
    [void]$Row.ColumnDefinitions.Add($InputColumn)
    $Label = New-Object System.Windows.Controls.TextBlock
    $Label.Text=$(if($Field.Type -eq 'Boolean'){''}else{$Field.Label})
    $Label.VerticalAlignment='Center'
    $Label.Foreground=[System.Windows.Media.Brushes]::DarkSlateGray
    [System.Windows.Controls.Grid]::SetColumn($Label,0)
    [void]$Row.Children.Add($Label)
    # Alan tipine gore uygun WPF kontrolunu sec.
    if ($Field.Type -eq 'Choice') {
        $Control=New-Object System.Windows.Controls.ComboBox
        foreach($Option in $Field.Options){
            [void]$Control.Items.Add($Option)
        }
        if($Control.Items.Count -gt 0){
            $Control.SelectedIndex=0
        }
    }
    elseif ($Field.Type -in @('BackupChoice','RollbackChoice')) {
        $Control=New-Object System.Windows.Controls.ComboBox
        $Control.SelectedValuePath='Id'
        $Control.IsEditable=$false
        $Control.MinHeight=32
        $Control.MaxDropDownHeight=360
        $Control.ItemTemplate=[System.Windows.Markup.XamlReader]::Parse('<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><TextBlock Text="{Binding Display}" TextWrapping="Wrap" MaxWidth="760" Padding="4" ToolTip="{Binding Display}" /></DataTemplate>')
        $Choices=if($Field.Type -eq 'RollbackChoice'){@(Get-RemoteOpsRollbackChoices -BasePath $script:DataRoot -OperationName $script:OperationPicker.SelectedItem.Name)}else{@(Get-RemoteOpsBackupChoices -BasePath $script:DataRoot)}
        foreach($Backup in $Choices){[void]$Control.Items.Add($Backup)}
        if($Control.Items.Count -gt 0){$Control.SelectedIndex=0}else{
            [void]$Control.Items.Add([pscustomobject]@{Id='';Display='No restorable backups found. / Geri yuklenebilir yedek yok.'})
            $Control.SelectedIndex=0
            $Control.IsEnabled=$false
        }
        $Control.ToolTip='Date | computer: original file path | backup ID. Refresh modules to reload backups.'
    }
    elseif ($Field.Type -eq 'Boolean') {
        $Control=New-Object System.Windows.Controls.CheckBox
        $Control.Content=$Field.Label
        $Control.IsChecked=$false
    }
    elseif ($Field.Type -eq 'RegistryData') {
        $Control=New-Object System.Windows.Controls.TextBox
        $Control.AcceptsReturn=$true;$Control.Height=80;$Control.TextWrapping='Wrap';$Control.VerticalScrollBarVisibility='Auto'
    }
    elseif ($Field.Type -eq 'Targets') {
        $Control=New-Object System.Windows.Controls.TextBox
        $Control.AcceptsReturn=$true
        $Control.Height=116
        $Control.VerticalScrollBarVisibility='Auto'
        $Control.ToolTip='One computer name per line (commas and spaces also separate names).'
        [void]$Row.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
        [void]$Row.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
        $CountHint=New-Object System.Windows.Controls.TextBlock
        $CountHint.Name='TargetCount'
        $CountHint.Text='0 bilgisayar'
        $CountHint.FontSize=11
        $CountHint.Foreground=[System.Windows.Media.Brushes]::SlateGray
        $CountHint.Margin='0,3,0,0'
        [System.Windows.Controls.Grid]::SetColumn($CountHint,1)
        [System.Windows.Controls.Grid]::SetRow($CountHint,1)
        [void]$Row.Children.Add($CountHint)
        # Hedef listesi her degistiginde tekil bilgisayar sayisini guncelle.
        $Control.Add_TextChanged({
            $Names=@(([string]$args[0].Text -split '[\s,;]+')|Where-Object{-not [string]::IsNullOrWhiteSpace($_)}|ForEach-Object{$_.ToUpperInvariant()}|Select-Object -Unique)
            $Hint=@($args[0].Parent.Children|Where-Object{$_ -is [System.Windows.Controls.TextBlock] -and $_.Name -eq 'TargetCount'}|Select-Object -First 1)
            if($Hint.Count -gt 0){$Hint[0].Text='{0} bilgisayar' -f $Names.Count}
        })
    }
    else { $Control=New-Object System.Windows.Controls.TextBox }
    $Control.Name="Input_$($Field.Key)"
    $Control.Tag=$Field.Key
    if($Control -is [System.Windows.Controls.TextBox]){$Control.Padding='6,4';$Control.MinHeight=28}
    [System.Windows.Controls.Grid]::SetColumn($Control,1)
    [void]$Row.Children.Add($Control)
    [void]$script:OperationFields.Children.Add($Row)
    $Example=Get-RemoteOpsOperationExample $script:OperationPicker.SelectedItem $Field
    if($Example){
        if($Row.RowDefinitions.Count -eq 0){[void]$Row.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition))}
        $ExampleRow=$Row.RowDefinitions.Count;[void]$Row.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition))
        $ExampleText=New-Object Windows.Controls.TextBlock;$ExampleText.Text=$Example;$ExampleText.TextWrapping='Wrap';$ExampleText.FontSize=11;$ExampleText.Foreground=[Windows.Media.Brushes]::SlateGray;$ExampleText.Margin='0,3,0,2'
        [Windows.Controls.Grid]::SetColumn($ExampleText,1);[Windows.Controls.Grid]::SetRow($ExampleText,$ExampleRow);[void]$Row.Children.Add($ExampleText)
        $Control.ToolTip=$Example
    }
    if($Field.Type -eq 'Targets' -and (Get-Command Add-RemoteOpsTargetGroupPicker -ErrorAction SilentlyContinue) -and (Get-Variable TargetGroupCatalogRoot -Scope Script -ErrorAction SilentlyContinue)){
        $HostPanel=New-Object Windows.Controls.StackPanel
        $PickerRow=$Row.RowDefinitions.Count;[void]$Row.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition))
        [Windows.Controls.Grid]::SetColumn($HostPanel,1);[Windows.Controls.Grid]::SetRow($HostPanel,$PickerRow);[void]$Row.Children.Add($HostPanel)
        $script:OperationGroupPicker=Add-RemoteOpsTargetGroupPicker $HostPanel $Control $script:TargetGroupCatalogRoot
    }
    # Paket operasyonunda "Application" alani bos birakilabilir: kontrolsuz tetikleme ipucu.
    if($Field.Key -eq 'Application' -and $script:OperationPicker.SelectedItem.Name -eq 'PackageTrigger'){
        [void]$Row.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
        [void]$Row.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
        $Hint=New-Object System.Windows.Controls.TextBlock
        $Hint.Text='Bos birakilirsa uygulama varligi kontrol etmeden tetikleyebilirsiniz.'
        $Hint.FontSize=11
        $Hint.Foreground=[System.Windows.Media.Brushes]::SlateGray
        $Hint.TextWrapping='Wrap'
        $Hint.Margin='0,4,0,0'
        [System.Windows.Controls.Grid]::SetColumn($Hint,1)
        [System.Windows.Controls.Grid]::SetRow($Hint,1)
        [void]$Row.Children.Add($Hint)
    }
}
# Operasyon listesinde secilen islem icin bilgi kutusunda gosterilen aciklama.
# Plugin operasyonlarinda manifest'teki Description kullanilir.
function Get-OperationDescription {
    param($Operation)
    if($Operation.Name -eq 'RecipeRun'){return 'Kayıtlı reçetenin izin verilen adımları hedef başına sırayla uygulanır. Reçeteler sekmesinden hazırlayın.'}
    $Description=switch($Operation.Name){
        'PackageDeployment' {'Kayitli paketi secerek kurulum, kaldirma veya dogrulanan eski surume donus calistirir.'}
        'ApplicationCheck' {'Uygulamayi Display Name veya Product ID ile arar; varlik, surum ve registry bilgilerini raporlar.'}
        'ApplicationInventory' {'Secilen bilgisayarlardaki kurulu uygulamalari ve surumlerini listeler.'}
        'PackageTrigger' {'UNC paketini kurma/kaldirma icin tetikler. Uygulama kimligi bos ise varlik ve surum kontrolu yapilmaz.'}
        'FilePull' {'Uzak dosya veya klasoru yerel calisma dizinine kopyalar; kaynak dosyayi degistirmez.'}
        'FileDelete' {'Uzak dosya veya klasoru once yedekler, ardindan siler.'}
        'FilePush' {'Yerel dosya veya klasoru secilen bilgisayarlara kopyalar.'}
        'FileCompare' {'Uzak dosyayi referans dosya ile hash, boyut ve tarih bakimindan karsilastirir.'}
        'FileBrowser' {'Uzak klasoru listeler; secilen dosyayi ceker, tasir veya degistirir.'}
        'FileRestore' {'Onceki silme yedeginden dosya veya klasoru geri yukler.'}
        'FileRollback' {'Kayitli dosya operasyonunu manifest bilgileriyle geri alir.'}
        'EndpointInventory' {'Isletim sistemi, donanim, ag ve yeniden baslatma gereksinimini toplar.'}
        'HealthCheck' {'Her bilgisayar icin reboot durumu, son acilis, imaj tarihi, yama/uygulama, IP/subnet, model, build, SCCM servisi/cache/log, disk, CPU ve RAM bilgisini toplar. Tum liste icin tek HTML rapor uretir; bilgisayar adina tiklayinca detaylari gorursunuz.'}
        'RegistryRead' {'HKLM altindaki belirtilen registry degerini okur.'}
        'RegistryEdit' {'Registry degerini mevcut turunu koruyarak degistirir; tur ve onceki veri rollback icin kaydedilir.'}
        'RegistryDelete' {'Registry degerini siler; onceki degeri rollback icin kaydeder.'}
        'RegistryRollback' {'Secilen bilgisayarlarin kayitli registry degisikliklerini geri alir.'}
        'ServiceList' {'Servislerin durumunu ve baslangic tipini listeler.'}
        'ServiceControl' {'Belirtilen servisi baslatir, durdurur veya yeniden baslatir.'}
        'ServiceStartup' {'Servisin baslangic tipini degistirir; onceki tipi kaydeder.'}
        'ServiceTaskRollback' {'Servis/task degisikliklerini geri alir; silinen task XML yedeginden geri yuklenir. Mevcut task uzerine yazilmaz.'}
        'ScheduledTaskList' {'Zamanlanmis gorevleri ad, klasor, durum ve etkinlik bilgileriyle listeler.'}
        'ScheduledTaskAction' {'Task calistirir veya etkinlestirir/devre disi birakir. Etkinlik degisikligi geri alinabilir.'}
        'ScheduledTaskDelete' {'Task XML yedegi ve rollback kaydi alindiktan sonra silinir. Parola gerektiren task silinmez; XML parola icermedigi icin geri yukleme garanti edilemez.'}
        'ProcessQuery' {'Calisan processleri ad veya PID filtresiyle sorgular; bos filtre tumunu listeler.'}
        'ProcessKill' {'Belirtilen processi sonlandirir. Bu islem rollback ile geri alinamaz.'}
        default {Get-OptionalPropertyValue -InputObject $Operation -Name 'Description'}
    }
    if([string]::IsNullOrWhiteSpace([string]$Description)){return ('Plugin operasyonu: {0}' -f $Operation.Title)}
    return [string]$Description
}
# Secili operasyon degistiginde formu temizleyip yeniden olusturur.
function Show-OperationFields {
    $script:OperationFields.Children.Clear(); $Operation=$script:OperationPicker.SelectedItem
    $script:OperationDescription.Text=if($null -ne $Operation){Get-OperationDescription $Operation}else{''}
    if($null -ne $Operation){foreach($Field in $Operation.Fields){Add-OperationField -Field $Field}}
    if($null -ne $Operation -and $Operation.Name -eq 'PackageDeployment' -and (Get-Command Add-SavedPackageOperationField -ErrorAction SilentlyContinue)){Add-SavedPackageOperationField}
    if($null -ne $Operation -and $Operation.Name -eq 'PackageTrigger' -and (Get-Command Add-RemoteOpsManualPackageSaveShortcut -ErrorAction SilentlyContinue)){Add-RemoteOpsManualPackageSaveShortcut}
}
# Formdaki tum kontrollerin degerlerini @{ Key = Deger } hashtable'i olarak toplar.
# Bu hashtable Request.Values olarak runner'a gider.
function Get-OperationValues {
    $Values=@{}
    foreach($Row in $script:OperationFields.Children){
        if($Row -isnot [System.Windows.Controls.Panel]){continue}
        $Control=$Row.Children|Where-Object{$_.Tag}|Select-Object -First 1
        if($null -eq $Control){
            continue
        }
        if($Control.Tag -eq 'SavedPackage'){
            if($null -ne $Control.SelectedItem){$Values.PackageDefinition=Copy-RemoteOpsPackageDefinition $Control.SelectedItem}
        }elseif($Control -is [System.Windows.Controls.ComboBox] -and $Control.Tag -in @('BackupPath','ManifestPath') -and $Control.SelectedValuePath -eq 'Id'){
            $Values[[string]$Control.Tag]=[string]$Control.SelectedValue
        }elseif($Control -is [System.Windows.Controls.ComboBox]){
            $Values[[string]$Control.Tag]=[string]$Control.SelectedItem
        }elseif($Control -is [System.Windows.Controls.CheckBox]){
            $Values[[string]$Control.Tag]=[bool]$Control.IsChecked
        }else{
            $Values[[string]$Control.Tag]=[string]$Control.Text
        }
    }
    return $Values
}
# Nesnede ozellik yoksa $null dondurur (StrictMode altinda hata vermeden okuma).
function Get-OptionalPropertyValue {
    param([Parameter(Mandatory=$true)]$InputObject,[Parameter(Mandatory=$true)][string]$Name)
    $Property=$InputObject.PSObject.Properties[$Name]
    if($null -eq $Property){return $null}
    return $Property.Value
}
# Zorunlu alanlari kontrol eder; bos olan ilk alan icin hata firlatir.
# Kosullu zorunluluklar: versiyon kontrollu kurulumda Version, FileBrowser
# Move/Replace aksiyonlarinda hedef/kaynak alanlari.
function Assert-OperationInputs {
    param([Parameter(Mandatory=$true)]$Operation,[Parameter(Mandatory=$true)][hashtable]$Values)
    if($Operation.Name -eq 'RecipeRun'){if(-not $Values.ContainsKey('Snapshot')){throw 'Reçeteyi Operasyon Reçeteleri sekmesinden hazırlayın.'};Assert-RemoteOpsRecipeRunSnapshot $Values.Snapshot}
    $RequiredKeys=switch($Operation.Name){
        'ApplicationCheck' {@('SearchValue')}
        'PackageTrigger' {@('Action','CheckMode','SearchType','PackagePath','PackageFile')}
        'PackageDeployment' {@('Action')}
        'FilePull' {@('Path')}
        'FileDelete' {@('Path')}
        'FilePush' {@('LocalPath','Path')}
        'FileCompare' {@('LocalPath','Path')}
        'FileRestore' {@('BackupPath')}
        'FileBrowser' {@('BrowsePath','SelectedPath','Action')}
        'RegistryRollback' {@('ManifestPath')}
        'ServiceTaskRollback' {@('ManifestPath')}
        'RegistryRead' {@('RegistryPath','ValueName')}
        'RegistryEdit' {@('RegistryPath','ValueName')}
        'RegistryDelete' {@('RegistryPath','ValueName')}
        'ServiceControl' {@('ServiceName','Action')}
        'ServiceStartup' {@('ServiceName','StartupType')}
        'ScheduledTaskAction' {@('TaskName','Action')}
        'ScheduledTaskDelete' {@('TaskName')}
        'ProcessKill' {@('ProcessFilter')}
        default {@()}
    }
    if($Operation.Name -eq 'PackageTrigger' -and -not [string]::IsNullOrWhiteSpace([string]$Values.Application) -and $Values.Action -eq 'Install' -and $Values.CheckMode -eq 'Version controlled' -and [string]::IsNullOrWhiteSpace([string]$Values.Version)){
        $RequiredKeys+=@('Version')
    }
    if($Operation.Name -eq 'FileBrowser' -and $Values.Action -eq 'Move' -and [string]::IsNullOrWhiteSpace([string]$Values.MoveTarget)){
        $RequiredKeys+=@('MoveTarget')
    }
    if($Operation.Name -eq 'FileBrowser' -and $Values.Action -eq 'Replace' -and [string]::IsNullOrWhiteSpace([string]$Values.ReplaceSource)){
        $RequiredKeys+=@('ReplaceSource')
    }
    foreach($Key in $RequiredKeys){
        if([string]::IsNullOrWhiteSpace([string]$Values[$Key])){
            throw "Required input is empty: $Key"
        }
    }
    if($Operation.Name -in @('RegistryRead','RegistryEdit','RegistryDelete')){[void](ConvertTo-RemoteOpsRegistryPath ([string]$Values.RegistryPath))}
    if($Operation.Name -eq 'PackageDeployment'){
        if(-not $Values.ContainsKey('PackageDefinition')){throw 'Choose a saved package.'}
        Assert-RemoteOpsPackageDefinition $Values.PackageDefinition ([string]$Values.Action)
    }
}
    
# ====================================================================
# CALISAN ISLEMI IZLEME (stdout/stderr + progress.json)
# ====================================================================
#
# Runner'in stdout/stderr dosyasinin sadece YENI eklenen kismini dondurur.
# $ReadLength [ref] ile en son okunan karakter sayisi tutulur.
function Read-NewRunOutput {
    param([string]$Path,[ref]$ReadLength)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return ''}
    try{
        $Content=Get-Content -LiteralPath $Path -Raw -Encoding Default -ErrorAction Stop
        if($Content.Length -le $ReadLength.Value){
            return ''
        }
        $NewText=$Content.Substring($ReadLength.Value)
        $ReadLength.Value=$Content.Length
        return $NewText
    }
    catch{return ''}
}
# Runner'in yazdigi progress.json dosyasini paylasimli modda okur
# (runner ayni anda yazarken dosya kilitlenmesin diye ReadWrite/Delete paylasimi).
function Read-TargetProgress {
    param([string]$Path)
    $Stream=$null
    $Reader=$null
    try{
        $Sharing=[System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
        $Stream=[System.IO.File]::Open($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,$Sharing)
        $Reader=New-Object System.IO.StreamReader -ArgumentList $Stream,([System.Text.Encoding]::UTF8),$true
        return ($Reader.ReadToEnd()|ConvertFrom-Json -ErrorAction Stop)
    }
    finally{
        if($null -ne $Reader){$Reader.Dispose()}
        elseif($null -ne $Stream){$Stream.Dispose()}
    }
}
# Ilerleme cubugunu ve "Tamamlanan / Bekleyen / asama / sure" yazisini gunceller.
function Get-RemoteOpsRunLogInfo {
    param($Run,[string]$ComputerName='',[string]$CollectionStatus='')
    $Path='';$CanOpen=$false
    try{
        $Reference=[string]$Run.ProgressPath+'.reportroot'
        if(Test-Path -LiteralPath $Reference -PathType Leaf){
            $ReportRoot=[IO.Path]::GetFullPath([IO.File]::ReadAllText($Reference).Trim())
            $Allowed=[IO.Path]::GetFullPath((Join-Path $script:DataRoot 'Logs\Operations')).TrimEnd('\')+'\'
            if(-not $ReportRoot.StartsWith($Allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid report root.'}
            $Group=[IO.Path]::GetFileName($ReportRoot)
            if($Group -cnotmatch '^[A-Za-z0-9_-]+$'){throw 'Invalid run ID.'}
            $Path=Join-Path (Join-Path $script:DataRoot 'PulledLogs') $Group
            if($ComputerName){
                if($ComputerName -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $ComputerName -match '\.\.'){throw 'Invalid client name.'}
                $Path=Join-Path $Path $ComputerName
            }
            if(Test-Path -LiteralPath $Path -PathType Container){$CanOpen=[bool](Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction Stop|Select-Object -First 1)}
        }
    }catch{$Path='';$CanOpen=$false}
    $Status=if($CanOpen -and $CollectionStatus -match 'Failed|Partial'){'Kismi - toplama basarisiz'}elseif($CanOpen){'Toplandi'}elseif($CollectionStatus -eq 'Failed'){'Toplama basarisiz'}elseif($CollectionStatus -eq 'NoRecentLogs'){'Log bulunamadi'}else{'Toplanmadi'}
    return [PSCustomObject]@{Path=$(if($CanOpen){$Path}else{''});CanOpen=$CanOpen;Status=$Status}
}
function Open-RemoteOpsLogFolder {
    param([string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){return}
    $Allowed=[IO.Path]::GetFullPath((Join-Path $script:DataRoot 'PulledLogs')).TrimEnd('\')+'\'
    $Full=[IO.Path]::GetFullPath($Path)
    if(-not $Full.StartsWith($Allowed,[StringComparison]::OrdinalIgnoreCase) -or -not(Test-Path -LiteralPath $Full -PathType Container)){throw 'Collected log folder is not available.'}
    Microsoft.PowerShell.Management\Start-Process -FilePath $Full -ErrorAction Stop
}
function Get-RemoteOpsPulledFileInfo {
    param($Run,[string]$ComputerName='')
    $Path='';$CanOpen=$false
    try{
        $Ref=[string]$Run.ProgressPath+'.reportroot'
        if(Test-Path -LiteralPath $Ref -PathType Leaf){
            $ReportRoot=[IO.Path]::GetFullPath([IO.File]::ReadAllText($Ref).Trim())
            $Allowed=[IO.Path]::GetFullPath((Join-Path $script:DataRoot 'Logs\Operations')).TrimEnd('\')+'\'
            if(-not $ReportRoot.StartsWith($Allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid report path.'}
            $Group=[IO.Path]::GetFileName($ReportRoot)
            if($Group -cnotmatch '^[A-Za-z0-9_-]+$'){throw 'Invalid run.'}
            $Path=Join-Path (Join-Path $script:DataRoot 'PulledFiles') $Group
            if($ComputerName){if($ComputerName -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $ComputerName -match '\.\.'){throw 'Invalid target.'};$Path=Join-Path $Path $ComputerName}
            if(Test-Path -LiteralPath $Path -PathType Container){
                $Files=@(Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction Stop|Select-Object -First 2)
                $CanOpen=$Files.Count -gt 0
                if($ComputerName -and $Files.Count -eq 1){$Path=$Files[0].FullName}
            }
        }
    }catch{$Path='';$CanOpen=$false}
    return [PSCustomObject]@{Path=$(if($CanOpen){$Path}else{''});CanOpen=$CanOpen}
}
function Show-RemoteOpsPulledFile {
    param([string]$Path)
    if(-not $Path){return}
    $Allowed=[IO.Path]::GetFullPath((Join-Path $script:DataRoot 'PulledFiles')).TrimEnd('\')+'\'
    $Full=[IO.Path]::GetFullPath($Path)
    if(-not $Full.StartsWith($Allowed,[StringComparison]::OrdinalIgnoreCase) -or -not(Test-Path -LiteralPath $Full)){throw 'Pulled file is not available.'}
    if(Test-Path -LiteralPath $Full -PathType Leaf){Microsoft.PowerShell.Management\Start-Process explorer.exe -ArgumentList ('/select,"'+$Full+'"') -ErrorAction Stop}
    else{Microsoft.PowerShell.Management\Start-Process -FilePath $Full -ErrorAction Stop}
}
function Get-RemoteOpsSelectedReport {
    if(-not $script:RunPicker.SelectedItem -or $script:RunPicker.SelectedItem.Id -eq '*'){return ''}
    $Run=$script:MonitorRuns[[string]$script:RunPicker.SelectedItem.Id]
    $Reference=[string]$Run.ProgressPath+'.reportroot'
    if(-not(Test-Path -LiteralPath $Reference -PathType Leaf)){return ''}
    try{
        $Root=[IO.File]::ReadAllText($Reference).Trim()
        $Allowed=[IO.Path]::GetFullPath((Join-Path $script:DataRoot 'Logs\Operations'))+[IO.Path]::DirectorySeparatorChar
        if(-not [IO.Path]::GetFullPath($Root).StartsWith($Allowed,[StringComparison]::OrdinalIgnoreCase)){return ''}
        foreach($Name in 'Results.html','Health.html','Error.html'){$Path=Join-Path $Root $Name;if(Test-Path -LiteralPath $Path -PathType Leaf){return $Path}}
        $Report=Get-ChildItem -LiteralPath $Root -Filter '*.html' -File -ErrorAction Stop|Sort-Object @{Expression={$_.Name -eq 'Activity.html'}},Name|Select-Object -First 1
        if($Report){return $Report.FullName}
    }catch{ }
    return ''
}
function Update-RemoteOpsRunSelection {
    if(-not $script:RunPicker.SelectedItem){return}
    $SelectedRow=$null
    if($script:DeploymentTargets -is [Windows.Controls.DataGrid]){$SelectedRow=$script:DeploymentTargets.SelectedItem}
    $Id=[string]$script:RunPicker.SelectedItem.Id
    $Rows=@(foreach($Key in $script:RunTargetRows.Keys){if($Id -eq '*' -or $Id -eq $Key){foreach($Item in $script:RunTargetRows[$Key]){$Item}}})
    $TotalRows=$Rows.Count
    if(Get-Variable WorkflowUi -Scope Script -ErrorAction SilentlyContinue){$Rows=@(Get-RemoteOpsFilteredTargets $Rows $script:WorkflowUi.Search.Text ([string]$script:WorkflowUi.Outcome.SelectedItem.Value))}
    $script:DeploymentTargets.ItemsSource=$Rows
    if($null -ne $SelectedRow){
        $SelectedRunId=[string](Get-OptionalPropertyValue $SelectedRow 'MonitorRunId')
        $Matches=@($Rows|Where-Object {([string](Get-OptionalPropertyValue $_ 'MonitorRunId')) -ceq $SelectedRunId -and $_.ComputerName -ieq $SelectedRow.ComputerName})
        if($Matches.Count -eq 1){$script:DeploymentTargets.SelectedItem=$Matches[0]}
    }
    if($script:DeploymentTargets -is [Windows.Controls.DataGrid]){
        $View=[Windows.Data.CollectionViewSource]::GetDefaultView($script:DeploymentTargets.ItemsSource)
        $View.GroupDescriptions.Clear()
        if($Id -eq '*'){[void]$View.GroupDescriptions.Add((New-Object Windows.Data.PropertyGroupDescription 'RunLabel'))}
    }
    $Counts=@($Rows|Group-Object Outcome|ForEach-Object{[string]$_.Name+': '+$_.Count}) -join ' | '
    $script:SelectedRunSummary.Text=(T 'Hedef: ')+$Rows.Count+' / '+$TotalRows+' | '+$Counts
    $script:OpenRunReport.IsEnabled=([bool](Get-RemoteOpsSelectedReport))
    if($null -ne (Get-Variable OpenCollectedLogs -Scope Script -ErrorAction SilentlyContinue) -and $script:OpenCollectedLogs){
        $LogInfo=if($Id -ne '*'){Get-RemoteOpsRunLogInfo $script:MonitorRuns[$Id]}else{$null}
        $script:OpenCollectedLogs.IsEnabled=($null -ne $LogInfo -and $LogInfo.CanOpen)
        $script:OpenCollectedLogs.Tag=if($LogInfo){$LogInfo.Path}else{''}
    }
    if($null -ne (Get-Variable OpenPulledFiles -Scope Script -ErrorAction SilentlyContinue) -and $script:OpenPulledFiles){
        $PullInfo=if($Id -ne '*'){Get-RemoteOpsPulledFileInfo $script:MonitorRuns[$Id]}else{$null}
        $script:OpenPulledFiles.IsEnabled=($null -ne $PullInfo -and $PullInfo.CanOpen);$script:OpenPulledFiles.Tag=if($PullInfo){$PullInfo.Path}else{''}
    }
    foreach($Key in $script:MonitorRuns.Keys){
        $Text=Get-OptionalPropertyValue $script:MonitorRuns[$Key] 'ProgressText'
        if($Text -and $Text.Parent){$Text.Parent.Visibility=if($Id -eq '*' -or $Id -eq $Key){'Visible'}else{'Collapsed'}}
    }
}
function Set-RemoteOpsRunTargetRows {
    param($Run,[object[]]$Items)
    if($null -eq (Get-Variable RunTargetRows -Scope Script -ErrorAction SilentlyContinue)){$script:RunTargetRows=[ordered]@{}}
    if($null -eq (Get-Variable MonitorRuns -Scope Script -ErrorAction SilentlyContinue)){$script:MonitorRuns=[ordered]@{}}
    $Id=[string]$Run.ProgressPath;$New=-not $script:MonitorRuns.Contains($Id)
    $script:MonitorRuns[$Id]=$Run
    $TargetLabel=[string](Get-OptionalPropertyValue $Run 'TargetLabel');if(-not $TargetLabel){$TargetLabel=$Run.Title}
    $Label=([datetime]$Run.StartedAt).ToString('HH:mm:ss')+' | '+$TargetLabel+' | '+@($Run.Targets).Count+(T ' bilgisayar')+' | '+($script:MonitorRuns.Keys.IndexOf($Id)+1)
    foreach($Item in $Items){
        Add-Member -InputObject $Item -NotePropertyName MonitorRunId -NotePropertyValue $Id -Force
        Add-Member -InputObject $Item -NotePropertyName RunLabel -NotePropertyValue $Label -Force
        if(Get-Command Get-RemoteOpsRunLogInfo -ErrorAction SilentlyContinue){
            $LogInfo=Get-RemoteOpsRunLogInfo $Run ([string]$Item.ComputerName) ([string](Get-OptionalPropertyValue $Item 'LogStatusRaw'))
            Add-Member -InputObject $Item -NotePropertyName LogPath -NotePropertyValue $LogInfo.Path -Force
            Add-Member -InputObject $Item -NotePropertyName CanOpenLogs -NotePropertyValue $LogInfo.CanOpen -Force
            Add-Member -InputObject $Item -NotePropertyName LogStatus -NotePropertyValue $LogInfo.Status -Force
        }
        if(Get-Command Get-RemoteOpsPulledFileInfo -ErrorAction SilentlyContinue){
            $PullInfo=Get-RemoteOpsPulledFileInfo $Run ([string]$Item.ComputerName)
            Add-Member -InputObject $Item -NotePropertyName PulledPath -NotePropertyValue $PullInfo.Path -Force
            Add-Member -InputObject $Item -NotePropertyName CanOpenPulled -NotePropertyValue $PullInfo.CanOpen -Force
        }
    }
    $script:RunTargetRows[$Id]=@($Items)
    if($null -ne (Get-Variable RunPicker -Scope Script -ErrorAction SilentlyContinue) -and $script:RunPicker){
        if($New){
            $Choices=@([PSCustomObject]@{Id='*';Label=(T 'T\u00FCm \u00E7al\u0131\u015Fmalar')})+@(foreach($Key in @($script:MonitorRuns.Keys)){
                $Entry=$script:MonitorRuns[$Key]
                $EntryLabel=[string](Get-OptionalPropertyValue $Entry 'TargetLabel');if(-not $EntryLabel){$EntryLabel=$Entry.Title}
                [PSCustomObject]@{Id=$Key;Label=([datetime]$Entry.StartedAt).ToString('HH:mm:ss')+' | '+$EntryLabel+' | '+@($Entry.Targets).Count+(T ' bilgisayar')+' | '+($script:MonitorRuns.Keys.IndexOf($Key)+1)}
            })
            $script:RunPicker.ItemsSource=$Choices
            $script:RunPicker.SelectedValue=$Id
        }
        Update-RemoteOpsRunSelection
    }else{$script:DeploymentTargets.ItemsSource=@(foreach($Batch in $script:RunTargetRows.Values){foreach($Item in $Batch){$Item}})}
}
function Update-RemoteOpsOperationRunView {
    param($Run)
    $Live=@(Get-OptionalPropertyValue $Run 'LiveTargets')
    $Label=[string](Get-OptionalPropertyValue $Run 'TargetLabel');if(-not $Label){$Label=$Run.Title}
    $Items=@(foreach($Target in $Run.Targets){
        $Entry=@($Live|Where-Object{$_ -and $_.ComputerName -eq $Target}|Select-Object -First 1)
        $Outcome=if($Entry.Count){[string]$Entry[0].Outcome}else{''}
        $Stage=if($Entry.Count){[string]$Entry[0].Stage}else{'Pending'}
        $Step=if($Stage -eq 'Running'){T '\u0130\u015Fleniyor'}elseif($Stage -eq 'Completed'){T 'Bitti'}else{T 'Bekliyor'}
        if($Outcome -and $script:RemoteOpsOutcomeTitles.ContainsKey($Outcome)){$Display=$script:RemoteOpsOutcomeTitles[$Outcome]}
        elseif($Run.Stage -eq 'Stopped'){$Step=T 'Durduruldu';$Display=T 'Durduruldu; sonucu kontrol edin'}
        elseif($Run.Stage -eq 'Failed'){$Step=T 'Kesildi';$Display=T 'Sonu\u00E7 al\u0131namad\u0131; raporu kontrol edin'}
        elseif($Run.Stage -eq 'Completed'){$Step=T 'Bitti';$Display=T 'Raporu kontrol edin'}
        else{$Display=$Step}
        [PSCustomObject]@{ComputerName=$Target;PackageName=$Label;Step=$Step;PreviousVersion='';FinalVersion='';Outcome=$Display;OutcomeCode=$Outcome;LogStatusRaw=$(if($Entry.Count){[string](Get-OptionalPropertyValue $Entry[0] 'LogCollectionStatus')}else{''})}
    })
    Set-RemoteOpsRunTargetRows $Run $Items
}
function Update-RunProgress {
    param($Run)
    if(Test-Path -LiteralPath $Run.ProgressPath -PathType Leaf){
        try{
            $State=Read-TargetProgress -Path $Run.ProgressPath
            if([int]$State.Total -ne $Run.Total){return}
            $Run.Completed=[math]::Max(0,[math]::Min($Run.Total,[int]$State.Completed))
            $Run.Stage=[string]$State.Stage
            $Run.CurrentTarget=[string]$State.CurrentTarget
            if($null -ne $State.PSObject.Properties['Targets']){Add-Member -InputObject $Run -NotePropertyName LiveTargets -NotePropertyValue @($State.Targets) -Force}
        }
        catch{ }
    }
    if(Get-OptionalPropertyValue $Run 'Stopped'){$Run.Stage='Stopped'}
    $Run.ProgressBar.Value=$Run.Completed
    # Runner'in Ingilizce asama adlarini ekranda Turkce goster.
    $StageText=switch($Run.Stage){'Starting'{'Baslatiliyor'}'Running'{'Isleniyor'}'Reporting'{'Rapor hazirlaniyor'}'Completed'{'Tamamlandi'}'Failed'{'Basarisiz / kesildi'}'Stopped'{'Durduruldu'}default{$Run.Stage}}
    $Elapsed=[int]((Get-Date)-$Run.StartedAt).TotalSeconds
    $Run.ProgressText.Text=('{0} | Tamamlanan: {1} / {2} | Bekleyen: {3} | {4}{5} | {6} sn' -f $Run.Title,$Run.Completed,$Run.Total,($Run.Total-$Run.Completed),$StageText,$(if($Run.CurrentTarget){' - '+$Run.CurrentTarget}else{''}),$Elapsed)
    if((Get-OptionalPropertyValue $Run 'CheckpointRoot') -and (Get-Command Update-RemoteOpsDeploymentRunView -ErrorAction SilentlyContinue)){Update-RemoteOpsDeploymentRunView $Run}
    elseif((Get-OptionalPropertyValue $Run 'Targets') -and (Get-Command Update-RemoteOpsOperationRunView -ErrorAction SilentlyContinue)){Update-RemoteOpsOperationRunView $Run}
    if((Get-OptionalPropertyValue $Run 'FinalSummary')){$Run.ProgressText.Text+=' | '+$Run.FinalSummary}
}
# ====================================================================
# PLUGIN YUKLEME
# RemoteOps.App\Plugins\<Ad>\manifest.json dosyalari taranir; gecerli
# operasyonlar katalogun sonuna eklenir. Hatali manifest atlanir ve Activity'ye yazilir.
# ====================================================================
function Import-RemoteOpsPlugins {
    $script:OperationCatalog = @($script:BuiltInOperationCatalog)
    $PluginRoot = Join-Path $script:AppRoot 'Plugins'
    $ManifestFiles=if(Test-Path -LiteralPath $PluginRoot -PathType Container){@(Get-ChildItem -LiteralPath $PluginRoot -Filter 'manifest.json' -File -Recurse -ErrorAction SilentlyContinue)}else{@()}
    # Her manifest icin: zorunlu alanlar, tekil operasyon adi ve alan tipleri dogrulanir.
    foreach ($ManifestFile in $ManifestFiles) {
        try {
            $Manifest = Get-Content -LiteralPath $ManifestFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([string]::IsNullOrWhiteSpace([string]$Manifest.Name) -or [string]::IsNullOrWhiteSpace([string]$Manifest.Script)) {
                throw 'Manifest needs Name and Script.'
            }
            foreach ($PluginOperation in @($Manifest.Operations)) {
                if ([string]::IsNullOrWhiteSpace([string]$PluginOperation.Name) -or [string]::IsNullOrWhiteSpace([string]$PluginOperation.Title)) {
                    throw 'Every operation needs Name and Title.'
                }
                if ($script:OperationCatalog.Name -contains [string]$PluginOperation.Name) {
                    throw "Duplicate operation name: $($PluginOperation.Name)"
                }
                $Fields = @($PluginOperation.Fields | ForEach-Object {
                    $Options=@()
                    if($null -ne $_.PSObject.Properties['Options']){$Options=@($_.Options)}
                    @{Key=[string]$_.Key;Label=[string]$_.Label;Type=[string]$_.Type;Options=$Options}
                })
                foreach($Field in $Fields){
                    if($Field.Type -notin @('Text','Targets','Boolean','Choice')){
                        throw "Unsupported field type '$($Field.Type)' in $($PluginOperation.Name)."
                    }
                    if($Field.Type -eq 'Choice' -and @($Field.Options).Count -eq 0){
                        throw "Choice field '$($Field.Key)' needs Options."
                    }
                }
                $script:OperationCatalog += [PSCustomObject]@{Category=[string]$Manifest.Name;Name=[string]$PluginOperation.Name;Title=[string]$PluginOperation.Title;Fields=$Fields;PluginName=[string]$Manifest.Name;PluginScript=[string]$Manifest.Script;PluginRoot=$ManifestFile.DirectoryName;PluginParallelSafe=([bool](Get-OptionalPropertyValue -InputObject $PluginOperation -Name 'ParallelSafe'))}
            }
            Write-AppLog "Loaded plugin manifest: $($Manifest.Name)"
        }
        catch { Write-AppLog "Plugin manifest ignored ($($ManifestFile.Name)): $($_.Exception.Message)" }
    }
    # Listede gorunecek "Kategori | Baslik" metni ve paralel calisabilirlik bayragi eklenir.
    foreach ($Operation in $script:OperationCatalog) {
        Add-Member -InputObject $Operation -NotePropertyName Display -NotePropertyValue ('{0}  |  {1}' -f $Operation.Category,$Operation.Title) -Force
        Add-Member -InputObject $Operation -NotePropertyName ParallelSafe -NotePropertyValue (($script:ParallelSafeOperations -contains [string]$Operation.Name) -or [bool](Get-OptionalPropertyValue -InputObject $Operation -Name 'PluginParallelSafe')) -Force
    }
    $script:OperationPicker.Items.Clear()
    # Saved deployments are launched from Paketlerim; keep their internal catalog entry.
    foreach ($Operation in @($script:OperationCatalog | Where-Object Name -ne 'PackageDeployment')) { [void]$script:OperationPicker.Items.Add($Operation) }
    if ($script:OperationPicker.Items.Count -gt 0) { $script:OperationPicker.SelectedIndex = 0 }
}
# ====================================================================
# OPERASYONU BASLATMA  (UX -> Runner gecisi burada olur)
# 1) Girdiler ve onay kelimesi (DELETE/KILL/TRIGGER/...) kontrol edilir
# 2) Request nesnesi olusturulur -> JSON -> Base64
# 3) Main profil degilse: secili hesapla "preflight" (erisim testi) yapilir
# 4) Runner, secili hesapla (veya mevcut oturumla) gizli pencerede baslatilir
# 5) Ilerleme satiri eklenir ve $script:ActiveRuns listesine kaydedilir
# Parola ASLA komut satirina yazilmaz; Windows'a PSCredential ile verilir.
# ====================================================================
function Start-RemoteOpsRequest {
    param([Parameter(Mandatory=$true)]$Operation,[Parameter(Mandatory=$true)][hashtable]$Values)
    Assert-OperationInputs -Operation $Operation -Values $Values
    # Hedef bilgisayar listesi: bosluk/virgul/noktali virgul ile ayrilir, tekrarlar atilir.
    $Targets=@(Get-TargetList -Text ([string]$Values.Targets))
    if($Targets.Count -eq 0){throw 'Add at least one target computer.'}
    $Profile=$script:ProfileList.SelectedItem
    if($null -eq $Profile){throw 'Select a domain profile.'}
    if(-not $Profile.IsMain -and [string]::IsNullOrWhiteSpace($Profile.ProtectedPassword)){
        throw 'The selected domain profile has no saved password.'
    }
    # Degisiklik yapan operasyonlarda kullanicinin yazmasi gereken onay kelimesi.
    # Runner ayni kontrolu tekrar yapar (iki katmanli guvenlik).
    $Expected=if($Operation.Name -eq 'RecipeRun'){'RECETE'}elseif($Operation.Name -eq 'PackageDeployment'){if($Values.Action -eq 'Downgrade'){'DOWNGRADE'}else{'TRIGGER'}}elseif($Operation.Name -match 'Delete'){'DELETE'}elseif($Operation.Name -eq 'ProcessKill'){'KILL'}elseif($Operation.Name -eq 'PackageTrigger'){'TRIGGER'}elseif($Operation.Name -eq 'FileRestore'){'RESTORE'}elseif($Operation.Name -match 'Rollback'){'ROLLBACK'}elseif($Operation.Name -match 'Edit|Startup'){'EDIT'}elseif($Operation.Name -eq 'FileBrowser' -and $Values.Action -ne 'Pull'){([string]$Values.Action).ToUpperInvariant()}elseif($Operation.Name -in @('ServiceControl','ScheduledTaskAction')){([string]$Values.Action).ToUpperInvariant()}else{''}
    if($Expected -and $Values.Confirm -cne $Expected){throw "Type $Expected in the confirmation field."}
    if($Operation.Name -eq 'RegistryRollback' -and $Values.Confirm -cne 'ROLLBACK'){
        throw 'Type ROLLBACK in the confirmation field.'
    }
    # Ayarlarda "log temizleme" aciksa ve "Collect package logs" isaretliyse temizlik aktif olur.
    # Kullanici adi guvenli degilse kullaniciya sorulur; devam edilirse temizlik kapatilir.
    $CollectLogs=if($Operation.Name -eq 'PackageDeployment'){[bool]$Values.PackageDefinition.CollectLogs}elseif($Operation.Name -eq 'PackageTrigger'){[bool]$Values.CollectLogs}else{$false}
    $CleanupActive=($Operation.Name -in @('PackageTrigger','PackageDeployment') -and [bool]$script:SettingCleanupLogs.IsChecked -and $CollectLogs)
    if($CleanupActive){
        $CleanupCheck=Get-CleanupUserNameCheck -UserName ([string]$Profile.UserName)
        if(-not $CleanupCheck.Valid){
            $Proceed=[System.Windows.MessageBox]::Show(((T 'Log temizleme a\u00E7\u0131k ancak se\u00E7ili profilin kullan\u0131c\u0131 ad\u0131 g\u00FCvenli de\u011Fil:')+"`r`n"+$CleanupCheck.Reason+"`r`n`r`n"+(T 'Paket yine de tetiklensin mi? (Hedefte hi\u00E7bir log silinmez.)')),'REMOTE OPS','YesNo','Warning')
            if($Proceed -ne 'Yes'){throw (T '\u0130\u015Flem kullan\u0131c\u0131 taraf\u0131ndan iptal edildi.')}
            $CleanupActive=$false
        }
        else{
            Write-AppLog ((T 'Log temizleme A\u00C7IK: toplanan loglardan "{0}" i\u00E7erenler hedefte silinecek.') -f $Profile.UserName)
        }
    }
    # Runner'in ilerleme yazacagi progress.json dosyasinin yolu (her calisma icin benzersiz).
    $ProgressRoot=Join-Path (Join-Path 'C:\Temp\YD_RemoteOps.App' 'Logs\Operations') ($Operation.Name -creplace '[^A-Za-z0-9_-]','_')
    New-Item -ItemType Directory -Path $ProgressRoot -Force -ErrorAction Stop|Out-Null
    $ProgressPath=Join-Path $ProgressRoot (([guid]::NewGuid().ToString('N'))+'.progress.json')
    # Runner'a gidecek istek. Parola ICERMEZ. Alanlar:
    # Operation/Category, Domain/UserName/IsMain, Targets, Values (form degerleri),
    # ProgressPath, Plugin* bilgileri, Parallelism, log temizleme secimi.
    $Request=[PSCustomObject]@{Operation=$Operation.Name;Category=$Operation.Category;Domain=$Profile.Domain;UserName=$Profile.UserName;IsMain=[bool]$Profile.IsMain;Targets=$Targets;Values=$Values;ProgressPath=$ProgressPath;PluginName=(Get-OptionalPropertyValue -InputObject $Operation -Name 'PluginName');PluginScript=(Get-OptionalPropertyValue -InputObject $Operation -Name 'PluginScript');PluginRoot=(Get-OptionalPropertyValue -InputObject $Operation -Name 'PluginRoot');PluginParallelSafe=([bool](Get-OptionalPropertyValue -InputObject $Operation -Name 'PluginParallelSafe'));Parallelism=(Get-EffectiveParallelism -Operation $Operation);CleanupPackageLogs=$CleanupActive;CleanupUserName=$(if($CleanupActive){[string]$Profile.UserName}else{''});RequestedAt=(Get-Date).ToString('o')}
    if($Operation.Name -eq 'PackageDeployment'){
        $Values.PackageDefinition=Copy-RemoteOpsPackageDefinition $Values.PackageDefinition
        Add-Member -InputObject $Request -NotePropertyName CancelPath -NotePropertyValue ($ProgressPath+'.cancel')
        Add-Member -InputObject $Request -NotePropertyName CheckpointRoot -NotePropertyValue ($ProgressPath+'.state')
    }
    if($Operation.Name -eq 'RecipeRun'){
        $FreshSnapshot=New-RemoteOpsRecipeRunSnapshot $Values.Snapshot.Definition $Targets $Profile ([bool]$script:SettingCleanupLogs.IsChecked)
        if($FreshSnapshot.Hash -cne $Values.Snapshot.Hash){throw 'Recipe snapshot/account mismatch.'}
        $RecipeRunId='GUI-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),([guid]::NewGuid().ToString('N').Substring(0,6).ToUpperInvariant())
        $RecipeRoot=Get-RemoteOpsRecipeRunRoot $script:DataRoot $RecipeRunId
        Add-Member -InputObject $Request -NotePropertyName RecipeRunId -NotePropertyValue $RecipeRunId
        Add-Member -InputObject $Request -NotePropertyName CancelPath -NotePropertyValue (Join-Path $RecipeRoot 'cancel.json')
        Add-Member -InputObject $Request -NotePropertyName CheckpointRoot -NotePropertyValue (Join-Path $RecipeRoot 'state')
        [void](ConvertTo-RemoteOpsRecipeRequestBase64 $Request)
    }
    $RequestJson=ConvertTo-Json -InputObject $Request -Depth 20 -Compress
    $RequestBase64=[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($RequestJson))
    # Windows komut satiri limiti (~32K) asilmasin diye ust sinir; hedef listesi bolunmeli.
    if($RequestBase64.Length -gt 22000){
        throw 'Request is too large for a Windows process command line. Split the target list into smaller batches.'
    }
    $RunnerPath=Join-Path $script:AppRoot 'RemoteOps.Runner.ps1'
    if(-not (Test-Path -LiteralPath $RunnerPath -PathType Leaf)){throw "Runner is missing: $RunnerPath"}
    # Runner her zaman Windows PowerShell 5.1 (powershell.exe) ile baslatilir.
    $EnginePath=Join-Path $PSHOME 'powershell.exe'
    $Arguments='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -RequestBase64 {1}' -f $RunnerPath,$RequestBase64
    try {
        $LogRoot=Join-Path (Join-Path 'C:\Temp\YD_RemoteOps.App' 'Logs\Operations') ($Operation.Name -creplace '[^A-Za-z0-9_-]','_')
        if(-not(Test-Path -LiteralPath $LogRoot)){
            New-Item -ItemType Directory -Path $LogRoot -Force|Out-Null
        }
        # 14 gunden eski stdout/stderr dosyalarini temizle (sadece GUID adli olanlar).
        $OutputCutoff=(Get-Date).AddDays(-14)
        Get-ChildItem -LiteralPath $LogRoot -File -ErrorAction SilentlyContinue|Where-Object{$_.LastWriteTime -lt $OutputCutoff -and $_.Name -match '^[0-9a-f]{32}\.(stdout|stderr)\.log$'}|Remove-Item -Force -ErrorAction SilentlyContinue
        # --- PREFLIGHT (sadece Main olmayan profillerde) ---
        # Secili domain hesabi ile kisa bir runner sureci calistirilir; hesap uygulama
        # dosyalarini okuyabiliyor ve C:\Temp\YD_RemoteOps.App altina yazabiliyor mu
        # kontrol edilir. Cikti 'ACCESS_PREFLIGHT_OK' degilse operasyon baslatilmaz.
        if(-not $Profile.IsMain){
            $AppParent=Split-Path -Parent $script:AppRoot
            $ProjectRoot=@($AppParent,(Join-Path $AppParent 'MD_script'),(Join-Path $AppParent 'MD_Script'))|Where-Object{Test-Path -LiteralPath (Join-Path $_ 'Modules\ApplicationWorkers.ps1') -PathType Leaf}|Select-Object -First 1
            if([string]::IsNullOrWhiteSpace([string]$ProjectRoot)){
                throw 'Cannot preflight the project: Modules\ApplicationWorkers.ps1 was not found.'
            }
            $PluginScriptPath=''
            $OperationPluginRoot=[string](Get-OptionalPropertyValue -InputObject $Operation -Name 'PluginRoot')
            if(-not [string]::IsNullOrWhiteSpace($OperationPluginRoot)){
                $PluginFolder=[System.IO.Path]::GetFullPath($OperationPluginRoot)
                $PluginsRoot=[System.IO.Path]::GetFullPath((Join-Path $script:AppRoot 'Plugins'))
                if(-not $PluginFolder.StartsWith(($PluginsRoot.TrimEnd('\')+'\'),[System.StringComparison]::OrdinalIgnoreCase)){
                    throw 'Plugin folder is outside the Plugins directory.'
                }
                $PluginManifest=Get-Content -LiteralPath (Join-Path $PluginFolder 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
                $PluginScriptPath=Join-Path $PluginFolder ([string]$PluginManifest.Script)
            }
            $PsExecPath=''
            if($Operation.Name -in @('PackageTrigger','PackageDeployment')){
                $PsExecCommand=Get-Command 'PsExec.exe' -ErrorAction SilentlyContinue
                $LocalPsExec=Join-Path ([string]$ProjectRoot) 'PsExec.exe'
                $PsExecPath=if($Operation.Name -eq 'PackageDeployment' -and (Test-Path -LiteralPath $LocalPsExec -PathType Leaf)){$LocalPsExec}elseif($null -ne $PsExecCommand){$PsExecCommand.Source}else{$LocalPsExec}
            }
            $Preflight=[PSCustomObject]@{RunnerPath=$RunnerPath;WorkersPath=(Join-Path ([string]$ProjectRoot) 'Modules\ApplicationWorkers.ps1');ModulesRoot=(Join-Path ([string]$ProjectRoot) 'Modules');BasePath='C:\Temp\YD_RemoteOps.App';LogRoot=$LogRoot;Operation=$Operation.Name;Values=$Values;PsExecPath=$PsExecPath;PluginScript=$PluginScriptPath}
            $PreflightBase64=[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Preflight -Depth 6 -Compress)))
            $CredentialPassword=Unprotect-ProfilePassword -ProtectedPassword $Profile.ProtectedPassword
            $Credential=New-Object System.Management.Automation.PSCredential (('{0}\{1}' -f $Profile.Domain,$Profile.UserName),$CredentialPassword)
            $PreflightArguments='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -PreflightBase64 {1}' -f $RunnerPath,$PreflightBase64
            $PreflightKey=[guid]::NewGuid().ToString('N')
            $PreflightOut=Join-Path $LogRoot ($PreflightKey+'.stdout.log')
            $PreflightErr=Join-Path $LogRoot ($PreflightKey+'.stderr.log')
            try{
                $PreflightProcess=Start-Process -FilePath $EnginePath -ArgumentList $PreflightArguments -WorkingDirectory $script:AppRoot -Credential $Credential -LoadUserProfile -RedirectStandardOutput $PreflightOut -RedirectStandardError $PreflightErr -WindowStyle Hidden -PassThru
                # Handle'i hemen onbellege al: PS 5.1'de aksi halde ExitCode bos donebilir.
                [void]$PreflightProcess.Handle
                if(-not $PreflightProcess.WaitForExit(45000)){
                    Stop-Process -Id $PreflightProcess.Id -Force -ErrorAction SilentlyContinue
                    throw 'Selected-account access preflight timed out after 45 seconds.'
                }
                $PreflightOutput=if(Test-Path -LiteralPath $PreflightOut){Get-Content -LiteralPath $PreflightOut -Raw -ErrorAction SilentlyContinue}else{''}
                $PreflightError=if(Test-Path -LiteralPath $PreflightErr){Get-Content -LiteralPath $PreflightErr -Raw -ErrorAction SilentlyContinue}else{''}
                if($PreflightProcess.ExitCode -ne 0 -or $PreflightOutput -notmatch 'ACCESS_PREFLIGHT_OK'){
                    $Detail=(@($PreflightOutput,$PreflightError)|Where-Object{-not [string]::IsNullOrWhiteSpace($_)})-join ' '
                    throw "Selected account failed application/data access preflight (exit $($PreflightProcess.ExitCode)). $Detail Check read access to the app/project and write access to $LogRoot and C:\Temp\YD_RemoteOps.App."
                }
            }
            finally{Remove-Item -LiteralPath @($PreflightOut,$PreflightErr) -Force -ErrorAction SilentlyContinue}
            Write-AppLog "Access preflight passed for $($Profile.Domain)\$($Profile.UserName)."
        }
        # --- ASIL RUNNER SURECINI BASLAT ---
        # stdout/stderr dosyalari Activity paneline canli aktarilmak icin yonlendirilir.
        $RunKey=[guid]::NewGuid().ToString('N')
        $StdOutPath=Join-Path $LogRoot ($RunKey+'.stdout.log')
        $StdErrPath=Join-Path $LogRoot ($RunKey+'.stderr.log')
        # Main profil: mevcut oturumla dogrudan powershell.exe baslatilir.
        # Diger profiller: cmd.exe /d /c ile, secili hesabin kimligiyle (-Credential) baslatilir.
        # Iki yolda da surec handle'i hemen onbellege alinir (PS 5.1 exit code okuyabilsin diye).
        if($Profile.IsMain){
            $Process=Start-Process -FilePath $EnginePath -ArgumentList $Arguments -WorkingDirectory $script:AppRoot -RedirectStandardOutput $StdOutPath -RedirectStandardError $StdErrPath -WindowStyle Hidden -PassThru
            [void]$Process.Handle
        }
        else{
            $Password=Unprotect-ProfilePassword -ProtectedPassword $Profile.ProtectedPassword
            $Credential=New-Object System.Management.Automation.PSCredential (('{0}\{1}' -f $Profile.Domain,$Profile.UserName),$Password)
            $Command='"{0}" {1}' -f $EnginePath,$Arguments
            $CmdArguments='/d /c "{0}"' -f $Command
            $Process=Start-Process -FilePath $env:ComSpec -ArgumentList $CmdArguments -WorkingDirectory $script:AppRoot -Credential $Credential -LoadUserProfile -RedirectStandardOutput $StdOutPath -RedirectStandardError $StdErrPath -WindowStyle Hidden -PassThru
            [void]$Process.Handle
        }
        # Bu calisma icin ekrana bir ilerleme satiri (yazi + progress bar) ekle.
        if($script:ActiveRuns.Count -eq 0){$script:RunProgressPanel.Children.Clear()}
        $ProgressRow=New-Object System.Windows.Controls.StackPanel
        $ProgressRow.Margin='0,0,0,8'
        $ProgressText=New-Object System.Windows.Controls.TextBlock
        $ProgressText.TextWrapping='Wrap'
        $ProgressText.FontSize=12
        $ProgressText.Margin='0,0,0,4'
        $ProgressBar=New-Object System.Windows.Controls.ProgressBar
        $ProgressBar.Height=12
        $ProgressBar.Minimum=0
        $ProgressBar.Maximum=$Targets.Count
        $ProgressBar.Value=0
        $ProgressBar.Foreground=[System.Windows.Media.Brushes]::SeaGreen
        [void]$ProgressRow.Children.Add($ProgressText)
        [void]$ProgressRow.Children.Add($ProgressBar)
        [void]$script:RunProgressPanel.Children.Add($ProgressRow)
        # Takip kaydi: OutputTimer bu nesne uzerinden okuma/guncelleme yapar.
        $Run=[PSCustomObject]@{Process=$Process;StdOutPath=$StdOutPath;StdErrPath=$StdErrPath;StdOutLength=0;StdErrLength=0;Identity=('{0}\{1}' -f $Profile.Domain,$Profile.UserName);ProgressPath=$ProgressPath;ProgressBar=$ProgressBar;ProgressText=$ProgressText;Title=$Operation.Title;Total=$Targets.Count;Completed=0;Stage='Starting';CurrentTarget='';StartedAt=(Get-Date);Stopped=$false}
        Add-Member -InputObject $Run -NotePropertyName OperationName -NotePropertyValue $Operation.Name
        Add-Member -InputObject $Run -NotePropertyName CheckpointRoot -NotePropertyValue ([string](Get-RemoteOpsPackageValue $Request CheckpointRoot ''))
        Add-Member -InputObject $Run -NotePropertyName CancelPath -NotePropertyValue ([string](Get-RemoteOpsPackageValue $Request CancelPath ''))
        Add-Member -InputObject $Run -NotePropertyName CancelRequested -NotePropertyValue $false
        Add-Member -InputObject $Run -NotePropertyName FinalSummary -NotePropertyValue ''
        Add-Member -InputObject $Run -NotePropertyName Targets -NotePropertyValue $Targets
        $TargetLabel=$Operation.Title
        if($Operation.Name -eq 'PackageTrigger'){
            $PackageLabel=if([string]::IsNullOrWhiteSpace([string]$Values.Application)){[string]$Values.PackageFile}else{[string]$Values.Application}
            $TargetLabel='{0} / {1}' -f $PackageLabel,$Values.Action
        }elseif($Operation.Name -eq 'PackageDeployment'){$TargetLabel='{0} / {1}' -f $Values.PackageDefinition.Name,$Values.Action}
        Add-Member -InputObject $Run -NotePropertyName TargetLabel -NotePropertyValue $TargetLabel
        [void]$script:ActiveRuns.Add($Run)
        $script:SharedRuns.IsExpanded=$true
        Update-StopButton
        Update-RunProgress $Run
        Write-AppLog "Started $($Operation.Title) for $($Targets.Count) target(s) as $($Profile.Domain)\$($Profile.UserName); process $($Process.Id); parallel=$($Request.Parallelism)."
    }
    catch { throw }
}

# ====================================================================
# GENEL YARDIMCILAR VE AYARLAR
# ====================================================================
#
# T 'metin': \u00E7 gibi kacis dizilerini gercek Turkce karaktere cevirir
# (dosya kodlamasindan bagimsiz Turkce metin yazabilmek icin).
function T { param([string]$Text) return [regex]::Unescape($Text) }
# Serbest metni bilgisayar listesine cevirir (buyuk/kucuk harf duyarsiz tekillestirme).
function Get-TargetList {
    param([string]$Text)
    $Seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $List=New-Object 'System.Collections.Generic.List[string]'
    foreach($Item in ([string]$Text -split '[\s,;]+')){
        if(-not [string]::IsNullOrWhiteSpace($Item) -and $Seen.Add($Item)){
            $List.Add($Item)
        }
    }
    return $List.ToArray()
}
# "#RRGGBB" metninden WPF firca nesnesi uretir.
function Get-Brush {
    param([string]$Hex)
    return (New-Object System.Windows.Media.BrushConverter).ConvertFromString($Hex)
}
# settings.json icinden bir ayari okur; yoksa/okunamazsa varsayilani dondurur.
function Get-SavedSetting {
    param([string]$Name,$Default)
    try{
        if(Test-Path -LiteralPath $script:SettingsPath -PathType Leaf){
            $Saved=Get-Content -LiteralPath $script:SettingsPath -Raw -Encoding UTF8|ConvertFrom-Json
            $Value=Get-OptionalPropertyValue -InputObject $Saved -Name $Name
            if($null -ne $Value){
                return $Value
            }
        }
    }catch{ }
    return $Default
}
# Tek bir ayari settings.json'a yazar (diger ayarlari koruyarak, .tmp + tasima ile).
function Save-AppSetting {
    param([string]$Name,$Value)
    try{
        $Parent=Split-Path -Parent $script:SettingsPath
        if(-not (Test-Path -LiteralPath $Parent)){New-Item -ItemType Directory -Path $Parent -Force|Out-Null}
        $Current=[ordered]@{}
        try{
            if(Test-Path -LiteralPath $script:SettingsPath -PathType Leaf){
                $Existing=Get-Content -LiteralPath $script:SettingsPath -Raw -Encoding UTF8|ConvertFrom-Json
                foreach($Property in $Existing.PSObject.Properties){
                    $Current[$Property.Name]=$Property.Value
                }
            }
        }catch{ }
        $Current[$Name]=$Value
        $Temporary=$script:SettingsPath+'.tmp'
        ConvertTo-Json -InputObject ([PSCustomObject]$Current) | Set-Content -LiteralPath $Temporary -Encoding UTF8
        Move-Item -LiteralPath $Temporary -Destination $script:SettingsPath -Force
    }catch{ }
}
function Get-SavedBoolSetting {
    # Safety switches are ON only for a real JSON true: a hand-edited "false"/"0" string must never enable them.
    param([string]$Name)
    $Value=Get-SavedSetting -Name $Name -Default $false
    return ($Value -is [bool] -and [bool]$Value)
}
# Kayitli paralellik (1-10) degeri; gecersizse 1.
function Get-SavedParallelism {
    try{$Value=[int](Get-SavedSetting -Name 'Parallelism' -Default 1);if($Value -ge 1 -and $Value -le 10){return $Value}}catch{ }
    return 1
}
function Save-ParallelismSetting { param([int]$Value) Save-AppSetting -Name 'Parallelism' -Value $Value }
# Log temizlemede kullanilacak kullanici adinin yeterince ozgul olup olmadigini
# FileOperations modulundeki Test-AOLogCleanupUserName ile kontrol eder.
function Get-CleanupUserNameCheck {
    param([string]$UserName)
    if(-not (Get-Command -Name Test-AOLogCleanupUserName -ErrorAction SilentlyContinue)){
        return [PSCustomObject]@{Valid=$false;Reason=(T 'Do\u011Frulama mod\u00FCl\u00FC y\u00FCklenemedi.')}
    }
    return (Test-AOLogCleanupUserName -UserName $UserName)
}
# Ayarlar panelinde, secili profile gore hangi dosya deseninin silinecegini gosterir.
function Update-CleanupPreview {
    $Selected=$script:ProfileList.SelectedItem
    if($null -eq $Selected){
        $script:CleanupPreview.Text=T 'Profil se\u00E7ilmedi. Log temizleme, operasyon ba\u015Flat\u0131l\u0131rken se\u00E7ili profilin kullan\u0131c\u0131 ad\u0131yla \u00E7al\u0131\u015F\u0131r.'
        return
    }
    $Check=Get-CleanupUserNameCheck -UserName ([string]$Selected.UserName)
    $Head=((T 'Se\u00E7ili profil: {0}\\{1}') -f $Selected.Domain,$Selected.UserName)
    if($Check.Valid){
        $script:CleanupPreview.Text=$Head+"`r`n"+((T 'E\u015Fle\u015Fecek dosya deseni: C:\\Windows\\Temp\\*{0}*.log ve *.txt (ad\u0131n\u0131n i\u00E7inde ayr\u0131 bir s\u00F6zc\u00FCk olarak ge\u00E7mesi gerekir; yaln\u0131zca \u00E7ekilmi\u015F ve do\u011Frulanm\u0131\u015F dosyalar)') -f $Selected.UserName)
    }
    else{
        $script:CleanupPreview.Text=$Head+"`r`n"+(T 'Bu kullan\u0131c\u0131 ad\u0131yla log temizleme YAPILMAZ: ')+$Check.Reason
    }
}
# Paket operasyonu seciliyken log temizleme aciksa aciklama kutusuna uyari ekler.
function Update-CleanupHint {
    $Operation=$script:OperationPicker.SelectedItem
    if($null -ne $Operation -and $Operation.Name -eq 'PackageTrigger' -and [bool]$script:SettingCleanupLogs.IsChecked){
        $script:OperationDescription.Text=[string]$script:OperationDescription.Text+(T ' [Log temizleme A\u00C7IK: sa\u011F alttaki \u00E7ark (Ayarlar) simgesine bak\u0131n. Yaln\u0131zca "Collect package logs" i\u015Faretliyse uygulan\u0131r.]')
    }
}
# Operasyon paralel-guvenli degilse her zaman 1 (sirali); degilse secilen deger (1-10).
function Get-EffectiveParallelism {
    param($Operation)
    if($null -eq $Operation -or -not [bool](Get-OptionalPropertyValue -InputObject $Operation -Name 'ParallelSafe')){
        return 1
    }
    $Selected=$script:ParallelismPicker.SelectedItem
    if($null -eq $Selected){return 1}
    return [Math]::Max(1,[Math]::Min(10,[int]$Selected))
}
# Paralellik kutusunu yalnizca paralel-guvenli operasyonlarda aktif yapar.
function Update-ParallelismState {
    $Operation=$script:OperationPicker.SelectedItem
    $Safe=($null -ne $Operation -and [bool](Get-OptionalPropertyValue -InputObject $Operation -Name 'ParallelSafe'))
    $script:ParallelismPicker.IsEnabled=$Safe
    $script:ParallelismPicker.ToolTip=if($Safe){T 'Ayn\u0131 anda i\u015Flenecek bilgisayar say\u0131s\u0131 (1 = s\u0131rayla).'}else{T 'Bu operasyon g\u00FCvenlik nedeniyle bilgisayarlar\u0131 s\u0131rayla i\u015Fler.'}
}
# Calisan islem varsa Durdur butonu aktif.
function Update-StopButton {
    $script:StopOperation.IsEnabled=($script:ActiveRuns.Count -gt 0)
    $script:ForceStopOperation.IsEnabled=($script:ActiveRuns.Count -gt 0)
    $script:CommonRunSummary.Text=if($script:ActiveRuns.Count){(T 'Devam eden i\u015F: ')+$script:ActiveRuns.Count}else{T 'Devam eden i\u015F yok'}
}
# Durdur butonu: onay alir ve calisan runner surec agacini taskkill /T /F ile sonlandirir.
# Durdurulan calisma icin sonuc raporu uretilmez.
function Stop-ActiveRuns {
    param([switch]$Force)
    if($script:ActiveRuns.Count -eq 0){return}
    $Question=if($Force){T 'Akti\u0066 i\u015Fler zorla durdurulsun mu? Yerel s\u00FCre\u00E7ler sonland\u0131r\u0131l\u0131r; uzaktaki paket devam edebilir. Sonucu do\u011Frulanamayan paket hedefleri belirsiz olarak raporlan\u0131r.'}else{T 'Devam eden i\u015Fler durdurulsun mu? Paketler sonraki ad\u0131ma veya hedefe ge\u00E7mez; aktif paket ad\u0131m\u0131n\u0131n bitmesi beklenir. Di\u011Fer operasyonlar\u0131n yerel s\u00FCre\u00E7leri sonland\u0131r\u0131l\u0131r.'}
    if([Windows.MessageBox]::Show($Question,'REMOTE OPS','YesNo','Warning') -ne 'Yes'){return}
    foreach($Run in @($script:ActiveRuns)){
        try{
            if($Run.Process.HasExited){continue}
            if($Run.OperationName -in @('PackageDeployment','RecipeRun') -and -not $Force){
                Request-RemoteOpsRunCancellation $Run.CancelPath;$Run.CancelRequested=$true
                Write-AppLog (T 'Paket iptal iste\u011Fi g\u00F6nderildi; aktif ad\u0131m\u0131n bitmesi bekleniyor.')
                continue
            }
            $Run.Stopped=$true
            $Output=& "$env:SystemRoot\System32\taskkill.exe" /PID $Run.Process.Id /T /F 2>&1
            if($LASTEXITCODE -ne 0){$Run.Stopped=$false;Write-AppLog ("Durdurulamadi: "+(($Output|Out-String).Trim()))}else{Write-AppLog ("Operasyon durduruldu: "+$Run.Title)}
        }catch{$Run.Stopped=$false;Write-AppLog $_.Exception.Message}
    }
}
# Secili profilde kayitli parola olup olmadigini formda gosterir.
function Update-PasswordState {
    $Selected=$script:ProfileList.SelectedItem
    if($null -eq $Selected){$script:PasswordState.Text='';return}
    $script:PasswordState.Text=if([string]::IsNullOrWhiteSpace([string]$Selected.ProtectedPassword)){T 'Kayıtlı parola: yok'}else{T 'Kayıtlı parola: var (yenisini yazarsanız değişir)'}
}
# "Ekle / Guncelle": formdaki domain/kullanici/parola ile profil ekler veya gunceller.
# - "DOMAIN\kullanici" yazilirsa otomatik ayrilir.
# - Parola alani bossa kayitli parola korunur.
# - Main isaretlenirse diger profillerin Main bayragi kaldirilir.
function Save-ProfileFromForm {
    $Domain=$script:DomainInput.Text.Trim();$UserName=$script:UsernameInput.Text.Trim()
    if($UserName -match '^([^\\]+)\\(.+)$'){
        if([string]::IsNullOrWhiteSpace($Domain)){
            $Domain=$Matches[1]
        }
        $UserName=$Matches[2]
    }
    if([string]::IsNullOrWhiteSpace($Domain) -or [string]::IsNullOrWhiteSpace($UserName)){
        throw (T 'Domain ve kullanıcı adı gerekli.')
    }
    $Existing=@($script:Profiles|Where-Object{$_.Domain -ieq $Domain -and $_.UserName -ieq $UserName}|Select-Object -First 1)
    $Existing=if($Existing.Count){$Existing[0]}else{$null}
    $HasNewPassword=$script:PasswordInput.SecurePassword.Length -gt 0
    $Protected=if($HasNewPassword){Protect-ProfilePassword $script:PasswordInput.SecurePassword}elseif($null -ne $Existing){[string]$Existing.ProtectedPassword}else{''}
    $IsMain=[bool]$script:MainProfileInput.IsChecked
    if(-not $IsMain -and [string]::IsNullOrWhiteSpace($Protected)){throw (T 'Main olmayan profil için parola girin.')}
    if($IsMain){
        foreach($Item in $script:Profiles){
            $Item.IsMain=$false
            $Item.Display='{0}\{1}' -f $Item.Domain,$Item.UserName
        }
    }
    if($null -eq $Existing){
        $Existing=[PSCustomObject]@{Domain=$Domain;UserName=$UserName;ProtectedPassword=$Protected;IsMain=$IsMain;Display=''}
        [void]$script:Profiles.Add($Existing)
        $Action=T 'eklendi'
    }
    else{
        $Existing.Domain=$Domain
        $Existing.UserName=$UserName
        $Existing.ProtectedPassword=$Protected
        $Existing.IsMain=$IsMain
        $Action=if($HasNewPassword){T 'güncellendi (parola yenilendi)'}else{T 'güncellendi (parola değişmedi)'}
    }
    $Existing.Display='{0}\{1}{2}' -f $Domain,$UserName,$(if($Existing.IsMain){'  [MAIN]'}else{''})
    Save-ProfileStore
    Refresh-ProfileList
    $script:ProfileList.SelectedItem=$Existing
    $script:PasswordInput.Clear()
    Update-PasswordState
    Write-AppLog ("Profil {0}\{1} {2}." -f $Domain,$UserName,$Action)
}
# Parolayi domain controller'a karsi bir kez dogrular (PrincipalContext.ValidateCredentials).
# Duz metin parola sadece bellekte kisa sure tutulur ve ZeroFreeBSTR ile silinir.
function Test-ProfileCredential {
    param([Parameter(Mandatory=$true)][string]$Domain,[Parameter(Mandatory=$true)][string]$UserName,[Parameter(Mandatory=$true)][System.Security.SecureString]$Password)
    Add-Type -AssemblyName System.DirectoryServices.AccountManagement
    $Bstr=[IntPtr]::Zero
    $Context=$null
    try{
        $Bstr=[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        $Plain=[System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($Bstr)
        $Context=New-Object System.DirectoryServices.AccountManagement.PrincipalContext -ArgumentList @([System.DirectoryServices.AccountManagement.ContextType]::Domain,$Domain)
        return [bool]$Context.ValidateCredentials($UserName,$Plain)
    }
    finally{
        if($Bstr -ne [IntPtr]::Zero){[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Bstr)}
        if($null -ne $Context){$Context.Dispose()}
    }
}
# "Parolayi dogrula" butonu: kullaniciyi kilitlenme sayaci konusunda uyarir, sonra dogrular.
function Invoke-ProfileCredentialTest {
    $Domain=$script:DomainInput.Text.Trim();$UserName=$script:UsernameInput.Text.Trim()
    if($UserName -match '^([^\\]+)\\(.+)$'){
        if([string]::IsNullOrWhiteSpace($Domain)){
            $Domain=$Matches[1]
        }
        $UserName=$Matches[2]
    }
    if([string]::IsNullOrWhiteSpace($Domain) -or [string]::IsNullOrWhiteSpace($UserName)){
        throw (T 'Domain ve kullanıcı adı gerekli.')
    }
    $Password=$null
    if($script:PasswordInput.SecurePassword.Length -gt 0){$Password=$script:PasswordInput.SecurePassword}
    else{
        $Stored=@($script:Profiles|Where-Object{$_.Domain -ieq $Domain -and $_.UserName -ieq $UserName}|Select-Object -First 1)
        if($Stored.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$Stored[0].ProtectedPassword)){
            throw (T 'Doğrulamak için parolayı yazın veya parolası kayıtlı bir profil seçin.')
        }
        $Password=Unprotect-ProfilePassword -ProtectedPassword ([string]$Stored[0].ProtectedPassword)
    }
    $Answer=[System.Windows.MessageBox]::Show(((T 'Parola {0}\{1} için domain denetleyicisinde bir kez denenecek.') -f $Domain,$UserName)+"`r`n"+(T 'Hatalı parola hesabın kilitlenme sayaçını artırabilir. Devam edilsin mi?'),(T 'Parolayı doğrula'),'YesNo','Question')
    if($Answer -ne 'Yes'){return}
    $script:Window.Cursor=[System.Windows.Input.Cursors]::Wait
    try{$Valid=Test-ProfileCredential -Domain $Domain -UserName $UserName -Password $Password}
    catch{
        $script:Window.Cursor=$null
        [System.Windows.MessageBox]::Show(((T 'Doğrulama yapılamadı (domain erişilemiyor olabilir):')+"`r`n"+$_.Exception.Message),(T 'Parolayı doğrula'),'OK','Warning')|Out-Null
        Write-AppLog (T 'Parola doğrulaması yapılamadı.')
        return
    }
    $script:Window.Cursor=$null
    if($Valid){
        [System.Windows.MessageBox]::Show((T 'Kullanıcı adı ve parola doğru.'),(T 'Parolayı doğrula'),'OK','Information')|Out-Null
        Write-AppLog ("Parola dogrulandi: {0}\{1}" -f $Domain,$UserName)
    }
    else{
        [System.Windows.MessageBox]::Show((T 'Kullanıcı adı veya parola hatalı. Parola değişmişse yeni parolayı yazıp Ekle / Güncelle'+"'"+'ye basın.'),(T 'Parolayı doğrula'),'OK','Warning')|Out-Null
        Write-AppLog ("Parola dogrulanamadi: {0}\{1}" -f $Domain,$UserName)
    }
}
# ====================================================================
# RAPOR SEKMESI (gunluk ozet)
# Veri kaynagi: Logs\Reports\Ledger altindaki CSV'ler (Reports.ps1 -> Get-RemoteOpsDailyReport)
# ====================================================================
#
# Rapor sekmesinde kullanilan standart TextBlock olusturucu.
function New-ReportText {
    param([string]$Text,[double]$Size=12.5,[string]$Color='#1F3342',[bool]$Bold=$false)
    $Block=New-Object System.Windows.Controls.TextBlock
    $Block.Text=$Text
    $Block.FontSize=$Size
    $Block.Foreground=Get-Brush $Color
    $Block.VerticalAlignment='Center'
    $Block.TextTrimming='CharacterEllipsis'
    if($Bold){$Block.FontWeight='SemiBold'}
    return $Block
}
# Yuzde degerine gore dolan yatay cubuk (kategori/operasyon dagilimi icin).
function New-PercentBar {
    param([double]$Percent,[string]$Color='#0B64A8',[double]$Height=8)
    $Track=New-Object System.Windows.Controls.Border
    $Track.Height=$Height
    $Track.CornerRadius=[System.Windows.CornerRadius]::new($Height/2)
    $Track.Background=Get-Brush '#E6ECF1'
    $Track.ClipToBounds=$true
    $Grid=New-Object System.Windows.Controls.Grid
    $Fill=[math]::Max(0,[math]::Min(100,$Percent))
    $First=New-Object System.Windows.Controls.ColumnDefinition
    $First.Width=[System.Windows.GridLength]::new($Fill,[System.Windows.GridUnitType]::Star)
    [void]$Grid.ColumnDefinitions.Add($First)
    $Second=New-Object System.Windows.Controls.ColumnDefinition
    $Second.Width=[System.Windows.GridLength]::new(100-$Fill,[System.Windows.GridUnitType]::Star)
    [void]$Grid.ColumnDefinitions.Add($Second)
    $Bar=New-Object System.Windows.Controls.Border
    $Bar.Background=Get-Brush $Color
    [System.Windows.Controls.Grid]::SetColumn($Bar,0)
    [void]$Grid.Children.Add($Bar)
    $Track.Child=$Grid
    return $Track
}
# Teknik operasyon adini ekranda gorunen basliga cevirir.
function Get-OperationDisplayTitle {
    param([string]$Name)
    $Known=@($script:OperationCatalog|Where-Object{$_.Name -ceq $Name}|Select-Object -First 1)
    if($Known.Count -gt 0){return [string]$Known[0].Title}
    return (Get-RemoteOpsOperationTitle -Name $Name)
}
# Secili gunun raporunu okuyup kartlari, dagilim cubugunu, kategori listesini,
# saatlik yogunlugu ve en cok islem yapilan bilgisayarlari yeniden cizer.
function Update-ReportView {
    try{
        $Date=if($null -ne $script:ReportDate.SelectedDate){([datetime]$script:ReportDate.SelectedDate).Date}else{(Get-Date).Date}
        $Report=Get-RemoteOpsDailyReport -BasePath $script:DataRoot -Date $Date
    }
    catch{Write-AppLog ((T 'Rapor okunamadı: ')+$_.Exception.Message);return}
    $script:LastReport=$Report
    $Tr=[System.Globalization.CultureInfo]::GetCultureInfo('tr-TR')
    $Problem=[int]$Report.Error+[int]$Report.Indeterminate+[int]$Report.RebootRequired
    $script:ReportSubtitle.Text=$Date.ToString('dd MMMM yyyy, dddd',$Tr)
    $script:CardTotal.Text=[string]$Report.Total
    $script:CardTotalSub.Text=('{0} '+(T 'çalıştırma')) -f $Report.Runs
    $script:CardComputers.Text=[string]$Report.UniqueComputers
    $script:CardComputersSub.Text=if($Report.UniqueComputers -gt 0){('{0} '+(T 'kategori')) -f @($Report.Categories).Count}else{''}
    $script:CardSuccess.Text=[string]$Report.Success
    $script:CardSuccessSub.Text=Format-RemoteOpsPercent $Report.SuccessPercent
    $script:CardSkipped.Text=[string]$Report.Neutral
    $script:CardSkippedSub.Text=Format-RemoteOpsPercent $Report.NeutralPercent
    $script:CardProblem.Text=[string]$Problem
    $script:CardProblemSub.Text=Format-RemoteOpsPercent (Get-RemoteOpsPercent $Problem $Report.Total)
    # outcome distribution bar + legend
    $script:OutcomeBar.Children.Clear()
    $script:OutcomeBar.ColumnDefinitions.Clear()
    $Segments=@(
        @{Label=(T 'Başarılı');Value=[int]$Report.Success;Color='#17855A'},
        @{Label=(T 'Atlandı / Yok / Erişilemedi');Value=[int]$Report.Neutral;Color='#D69E2E'},
        @{Label=(T 'Hata / Dikkat');Value=$Problem;Color='#C53A3A'}
    )
    $Legend=@()
    foreach($Segment in $Segments){
        if($Segment.Value -le 0){continue}
        $Column=New-Object System.Windows.Controls.ColumnDefinition
        $Column.Width=[System.Windows.GridLength]::new($Segment.Value,[System.Windows.GridUnitType]::Star)
        [void]$script:OutcomeBar.ColumnDefinitions.Add($Column)
        $Piece=New-Object System.Windows.Controls.Border
        $Piece.Background=Get-Brush $Segment.Color
        $Piece.ToolTip=('{0}: {1}' -f $Segment.Label,$Segment.Value)
        [System.Windows.Controls.Grid]::SetColumn($Piece,$script:OutcomeBar.ColumnDefinitions.Count-1)
        [void]$script:OutcomeBar.Children.Add($Piece)
        $Legend+=('{0} {1} ({2})' -f $Segment.Label,$Segment.Value,(Format-RemoteOpsPercent (Get-RemoteOpsPercent $Segment.Value $Report.Total)))
    }
    $script:OutcomeLegend.Text=if($Legend.Count -gt 0){$Legend -join '     |     '}else{''}
    if($Report.Cancelled -or $Report.Indeterminate -or $Report.RebootRequired){$script:OutcomeLegend.Text+=' | '+(T '\u0130ptal: ')+$Report.Cancelled+' | '+(T 'Belirsiz: ')+$Report.Indeterminate+' | '+(T 'Yeniden ba\u015Flatma: ')+$Report.RebootRequired}
    # categories with operation distribution underneath
    $script:CategoryPanel.Children.Clear()
    $script:ReportEmpty.Visibility=if($Report.Total -eq 0){'Visible'}else{'Collapsed'}
    foreach($Category in @($Report.Categories)){
        $Block=New-Object System.Windows.Controls.StackPanel
        $Block.Margin='0,0,16,18'
        $Head=New-Object System.Windows.Controls.DockPanel
        $Summary=New-ReportText -Text ((T '{0} işlem  |  {1}  |  {2} bilgisayar') -f $Category.Count,(Format-RemoteOpsPercent $Category.Percent),$Category.Computers) -Size 12 -Color '#62778A'
        [System.Windows.Controls.DockPanel]::SetDock($Summary,'Right')
        [void]$Head.Children.Add($Summary)
        [void]$Head.Children.Add((New-ReportText -Text $Category.Title -Size 15 -Bold $true))
        [void]$Block.Children.Add($Head)
        $Bar=New-PercentBar -Percent $Category.Percent
        $Bar.Margin='0,6,0,6'
        [void]$Block.Children.Add($Bar)
        $CategoryProblem=[int]$Category.Error
        $Split=((T 'Başarılı {0} ({1})  |  Atlandı {2} ({3})  |  Hata {4} ({5})') -f $Category.Success,(Format-RemoteOpsPercent (Get-RemoteOpsPercent $Category.Success $Category.Count)),$Category.Neutral,(Format-RemoteOpsPercent (Get-RemoteOpsPercent $Category.Neutral $Category.Count)),$CategoryProblem,(Format-RemoteOpsPercent (Get-RemoteOpsPercent $CategoryProblem $Category.Count)))
        $SplitText=New-ReportText -Text $Split -Size 11.5 -Color '#4A6073'
        $SplitText.Margin='0,0,0,6'
        [void]$Block.Children.Add($SplitText)
        foreach($Operation in @($Category.Operations)){
            $Line=New-Object System.Windows.Controls.Grid
            $Line.Margin='14,2,0,2'
            foreach($Width in @(0,110,86)){
                $Column=New-Object System.Windows.Controls.ColumnDefinition
                if($Width -eq 0){
                    $Column.Width=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
                }else{
                    $Column.Width=[System.Windows.GridLength]::new($Width)
                }
                [void]$Line.ColumnDefinitions.Add($Column)
            }
            $Title=New-ReportText -Text (Get-OperationDisplayTitle -Name $Operation.Name) -Size 12
            [System.Windows.Controls.Grid]::SetColumn($Title,0)
            [void]$Line.Children.Add($Title)
            $MiniBar=New-PercentBar -Percent $Operation.Percent -Color '#5AA0D6' -Height 6
            $MiniBar.Margin='8,0,8,0'
            [System.Windows.Controls.Grid]::SetColumn($MiniBar,1)
            [void]$Line.Children.Add($MiniBar)
            $Count=New-ReportText -Text ('{0}  |  {1}' -f $Operation.Count,(Format-RemoteOpsPercent $Operation.Percent)) -Size 12 -Color '#4A6073'
            $Count.HorizontalAlignment='Right'
            [System.Windows.Controls.Grid]::SetColumn($Count,2)
            [void]$Line.Children.Add($Count)
            [void]$Block.Children.Add($Line)
        }
        [void]$script:CategoryPanel.Children.Add($Block)
    }
    if($null -ne $Report.PSObject.Properties['Packages'] -and @($Report.Packages).Count -gt 0){
        $Heading=New-ReportText -Text (T 'Paket ve eylem baz\u0131nda hedef sonu\u00E7lar\u0131') -Size 14 -Color '#1F3342'
        $Heading.Margin='0,12,0,8';[void]$script:CategoryPanel.Children.Add($Heading)
        foreach($Package in $Report.Packages){
            $Title=New-ReportText -Text ('{0} - {1} | {2} {3}' -f $Package.Name,$Package.ActionTitle,$Package.Count,(T 'hedef denemesi')) -Size 12 -Color '#0B64A8'
            $Title.TextWrapping='Wrap';$Title.Margin='0,4,0,3';[void]$script:CategoryPanel.Children.Add($Title)
            $Detail=New-ReportText -Text ((T 'Ba\u015Far\u0131l\u0131 {0} | Atland\u0131 {1} | Dikkat {2} | \u0130ptal {3}') -f $Package.Success,$Package.Skipped,$Package.Problems,$Package.Cancelled) -Size 11.5 -Color '#4A6073'
            $Detail.TextWrapping='Wrap';$Detail.Margin='0,0,0,8';[void]$script:CategoryPanel.Children.Add($Detail)
        }
    }
    # hourly distribution
    $script:HourPanel.Children.Clear()
    $script:HourPanel.ColumnDefinitions.Clear()
    $script:HourLabels.Children.Clear()
    $script:HourLabels.ColumnDefinitions.Clear()
    $MaxHour=[Math]::Max(1,(@($Report.Hours)|Measure-Object -Maximum).Maximum)
    for($Hour=0;$Hour -lt 24;$Hour++){
        [void]$script:HourPanel.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
        [void]$script:HourLabels.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
        $HourCount=[int]$Report.Hours[$Hour]
        $Column=New-Object System.Windows.Controls.Border
        $Column.VerticalAlignment='Bottom'
        $Column.Margin='1,0'
        $Column.Height=[math]::Max(2,88.0*$HourCount/$MaxHour)
        $Column.CornerRadius=[System.Windows.CornerRadius]::new(2,2,0,0)
        $Column.Background=if($HourCount -gt 0){Get-Brush '#0B64A8'}else{Get-Brush '#DCE5EC'}
        $Column.ToolTip=('{0:00}:00 - {1} '+(T 'işlem')) -f $Hour,$HourCount
        [System.Windows.Controls.Grid]::SetColumn($Column,$Hour)
        [void]$script:HourPanel.Children.Add($Column)
        if($Hour % 3 -eq 0){
            $Label=New-ReportText -Text ('{0:00}' -f $Hour) -Size 9.5 -Color '#62778A'
            $Label.HorizontalAlignment='Left'
            [System.Windows.Controls.Grid]::SetColumn($Label,$Hour)
            [void]$script:HourLabels.Children.Add($Label)
        }
    }
    # top computers
    $script:ComputerPanel.Children.Clear()
    $Rank=0
    foreach($Computer in @($Report.TopComputers)){
        $Rank++
        $Line=New-Object System.Windows.Controls.Grid
        $Line.Margin='0,3,14,3'
        foreach($Width in @(24,0,60,60)){
            $Column=New-Object System.Windows.Controls.ColumnDefinition
            if($Width -eq 0){
                $Column.Width=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
            }else{
                $Column.Width=[System.Windows.GridLength]::new($Width)
            }
            [void]$Line.ColumnDefinitions.Add($Column)
        }
        $Index=New-ReportText -Text ([string]$Rank) -Size 11.5 -Color '#62778A'
        [System.Windows.Controls.Grid]::SetColumn($Index,0)
        [void]$Line.Children.Add($Index)
        $Name=New-ReportText -Text $Computer.ComputerName -Size 12.5
        [System.Windows.Controls.Grid]::SetColumn($Name,1)
        [void]$Line.Children.Add($Name)
        $Total=New-ReportText -Text ([string]$Computer.Count) -Size 12.5 -Bold $true
        $Total.HorizontalAlignment='Right'
        [System.Windows.Controls.Grid]::SetColumn($Total,2)
        [void]$Line.Children.Add($Total)
        if([int]$Computer.Problems -gt 0){
            $Warn=New-ReportText -Text ('! {0}' -f $Computer.Problems) -Size 12 -Color '#C53A3A' -Bold $true
            $Warn.HorizontalAlignment='Right'
            $Warn.ToolTip=T 'Hata / erişilemedi sayısı'
            [System.Windows.Controls.Grid]::SetColumn($Warn,3)
            [void]$Line.Children.Add($Warn)
        }
        [void]$script:ComputerPanel.Children.Add($Line)
    }
    if($Rank -eq 0){
        [void]$script:ComputerPanel.Children.Add((New-ReportText -Text (T 'Kayıt yok.') -Size 12 -Color '#62778A'))
    }
}
# Gunluk raporu Logs\Reports\Daily_<tarih>.html olarak yazar ve tarayicida acar.
function Export-ReportHtml {
    Update-ReportView
    if($null -eq $script:LastReport){return}
    $Path=Join-Path $script:DataRoot ('Logs\Reports\Daily_{0}.html' -f $script:LastReport.Date.ToString('yyyy-MM-dd'))
    [void](Write-RemoteOpsDailyDashboardHtml -Path $Path -Report $script:LastReport)
    Microsoft.PowerShell.Management\Start-Process -FilePath $Path
    Write-AppLog ((T 'Günlük rapor açıldı: ')+$Path)
}

# ====================================================================
# UYGULAMA BASLANGICI
# 1) XAML'dan pencere olusturulur
# 2) x:Name'li kontroller $script: degiskenlerine baglanir
# 3) Profiller, plugin'ler ve ayarlar yuklenir
# 4) Buton/olay (event) baglantilari yapilir
# 5) OutputTimer baslatilir ve pencere acilir (ShowDialog)
# ====================================================================
$Reader=New-Object System.Xml.XmlNodeReader ([xml]$script:WindowXaml)
$script:Window=[Windows.Markup.XamlReader]::Load($Reader)
$WorkArea=[System.Windows.SystemParameters]::WorkArea
$script:Window.Width=[math]::Min(1380,[math]::Max(960,$WorkArea.Width-32))
$script:Window.Height=[math]::Min(900,[math]::Max(550,$WorkArea.Height-40))
# XAML'daki her x:Name'i ayni isimli $script: degiskenine bagla (orn. $script:RunOperation).
foreach($Name in @('ActiveIdentity','ToggleProfiles','ProfileEditor','ProfileList','DomainInput','UsernameInput','PasswordInput','MainProfileInput','AddProfile','RemoveProfile','OperationPicker','RefreshModules','OperationDescription','OperationFields','RunModeLabel','RunOperation','PreviewOperation','RunProgressPanel','ActivityLog','MainTabs','StopOperation','ParallelismPicker','SettingCleanupLogs','CleanupExplain','CleanupPreview','OpenSettings','SettingsOverlay','CloseSettings','PasswordState','TestProfile','OpenLogs','ClearActivity','ReportPrev','ReportNext','ReportToday','ReportRefresh','ReportExport','ReportDate','ReportSubtitle','CardTotal','CardTotalSub','CardComputers','CardComputersSub','CardSuccess','CardSuccessSub','CardSkipped','CardSkippedSub','CardProblem','CardProblemSub','OutcomeBar','OutcomeLegend','CategoryPanel','ReportEmpty','HourPanel','HourLabels','ComputerPanel','PackagesTab','PackageEditorTab','OperationTab','ReportTab','PackageLibraryHost','PackageEditorHost','SharedParallelHost','ProfileToolsHost','SharedRuns','SharedStopHost','CommonRunSummary','RunPicker','SelectedRunSummary','OpenRunReport','OpenCollectedLogs','OpenPulledFiles','DeploymentTargets','ForceStopOperation','ProfileOverlay','CloseProfileEditor','ProfileEditorHost')){Set-Variable -Scope Script -Name $Name -Value $script:Window.FindName($Name)}
# Kayitli profilleri ve plugin operasyonlarini yukle, ilk operasyonun formunu ciz.
Load-ProfileStore
Refresh-ProfileList
Initialize-RemoteOpsPackageUi -Window $script:Window -CatalogRoot $script:PackageCatalogRoot
$script:HistoryUi=Initialize-RemoteOpsHistoryUi -Tabs $script:MainTabs -BasePath $script:DataRoot
$script:TargetGroupsUi=Initialize-RemoteOpsTargetGroupsUi -Tabs $script:MainTabs -CatalogRoot $script:TargetGroupCatalogRoot
$script:RecoveryUi=Initialize-RemoteOpsRecoveryUi -Tabs $script:MainTabs -BasePath $script:DataRoot
$script:RecipeUi=Initialize-RemoteOpsRecipeUi -Tabs $script:MainTabs -CatalogRoot $script:RecipeCatalogRoot
Initialize-RemoteOpsWorkspaceNavigation -Window $script:Window -Tabs $script:MainTabs
Initialize-RemoteOpsWorkflowUi
Import-RemoteOpsPlugins
Show-OperationFields
Write-AppLog 'Application shell ready.'
# Paralellik secenekleri ve kayitli deger.
foreach($ParallelChoice in @(1,2,3,4,5,6,8,10)){[void]$script:ParallelismPicker.Items.Add($ParallelChoice)}
$script:ParallelismPicker.SelectedItem=Get-SavedParallelism
if($null -eq $script:ParallelismPicker.SelectedItem){$script:ParallelismPicker.SelectedIndex=0}
Update-ParallelismState
$script:ParallelismPicker.Add_SelectionChanged({if($null -ne $script:ParallelismPicker.SelectedItem){Save-ParallelismSetting -Value ([int]$script:ParallelismPicker.SelectedItem)}})
# Ayarlar panelindeki log temizleme guvenlik kurallari metni.
$script:CleanupExplain.Text=(T 'Paket tetiklendikten ve loglar \u00E7ekildikten sonra, hedef bilgisayarda C:\\Windows\\Temp i\u00E7inde ad\u0131nda kay\u0131tl\u0131 profilin kullan\u0131c\u0131 ad\u0131 ge\u00E7en loglar\u0131 siler. G\u00FCvenlik kurallar\u0131:')+"`r`n"+((@(
    '\u2022 Yaln\u0131zca "Collect package logs" i\u015Faretliyse ve loglar ba\u015Far\u0131yla \u00E7ekildiyse \u00E7al\u0131\u015F\u0131r; paket normal bitmediyse (zaman a\u015F\u0131m\u0131/hata) hi\u00E7bir \u015Fey silinmez.',
    '\u2022 Yaln\u0131zca bu i\u015Flemde \u00E7ekilen ve hedefteki dosyayla birebir ayn\u0131 (SHA256) olan .log/.txt dosyalar\u0131 silinir; \u00E7ekilmeyen veya sonradan de\u011Fi\u015Fen dosyaya dokunulmaz.',
    '\u2022 Yaln\u0131zca C:\\Windows\\Temp klas\u00F6r\u00FCn\u00FCn do\u011Frudan i\u00E7indeki dosyalar (alt klas\u00F6rler, klas\u00F6rler ve k\u0131sayol/reparse noktalar\u0131 hari\u00E7); CBS, DISM, MpCmdRun, WindowsUpdate, CCM gibi sistem log adlar\u0131 korunur (SCCM ile ba\u015Flayan paket loglar\u0131 kullan\u0131c\u0131 ad\u0131n\u0131 i\u00E7eriyorsa silinebilir).',
    '\u2022 Kullan\u0131c\u0131 ad\u0131 en az 4 karakter ve yeterince \u00F6zg\u00FCl olmal\u0131d\u0131r (admin, system, user, test gibi genel ad ya da * ? gibi karakter reddedilir).',
    '\u2022 Dosya ad\u0131nda kullan\u0131c\u0131 ad\u0131 ayr\u0131 bir s\u00F6zc\u00FCk olarak ge\u00E7melidir ("yigitery0" ad\u0131, "yigitery01" kullan\u0131c\u0131s\u0131n\u0131n loglar\u0131yla e\u015Fle\u015Fmez).',
    '\u2022 E\u015Fle\u015Fen dosya say\u0131s\u0131 50 sin\u0131r\u0131n\u0131 a\u015F\u0131yorsa g\u00FCvenlik i\u00E7in hi\u00E7bir \u015Fey silinmez. Kilitli/kullan\u0131mdaki dosyalar atlan\u0131r.',
    '\u2022 \u00C7ekilen kopyalar yerelde PulledLogs alt\u0131nda kal\u0131r; silinen dosya adlar\u0131 rapora (LogCleanupDetail) ve teknik loga yaz\u0131l\u0131r.') | ForEach-Object { T $_ }) -join "`r`n")
# --- OLAY BAGLANTILARI (event handler) ---
# Log temizleme kutusu: acilirken ek onay istenir, secim settings.json'a yazilir.
$script:SettingCleanupLogs.IsChecked=(Get-SavedBoolSetting -Name 'CleanupPackageLogs')
$script:CleanupSettingBusy=$false
$script:SettingCleanupLogs.Add_Click({
    if($script:CleanupSettingBusy){return}
    if([bool]$script:SettingCleanupLogs.IsChecked){
        $Confirm=[System.Windows.MessageBox]::Show((T 'Log temizleme a\u00E7\u0131ls\u0131n m\u0131?')+"`r`n`r`n"+(T 'Paket operasyonlar\u0131nda, loglar \u00E7ekildikten sonra hedef bilgisayardaki C:\\Windows\\Temp i\u00E7inde kay\u0131tl\u0131 kullan\u0131c\u0131 ad\u0131n\u0131 i\u00E7eren .log/.txt dosyalar\u0131 silinecek (yaln\u0131zca \u00E7ekilen ve do\u011Frulanan dosyalar). Kurallar\u0131 bu pencerede okuyabilirsiniz.'),'REMOTE OPS','YesNo','Question')
        if($Confirm -ne 'Yes'){
            $script:CleanupSettingBusy=$true
            $script:SettingCleanupLogs.IsChecked=$false
            $script:CleanupSettingBusy=$false
            return
        }
    }
    Save-AppSetting -Name 'CleanupPackageLogs' -Value ([bool]$script:SettingCleanupLogs.IsChecked)
    Write-AppLog ('Log temizleme ayari: '+$(if([bool]$script:SettingCleanupLogs.IsChecked){'ACIK'}else{'KAPALI'}))
    Update-CleanupPreview
    Update-CleanupHint
})
Update-CleanupPreview
# Ayarlar paneli: dislidan acilir; Kapat, arka plana tiklama veya Esc ile kapanir.
$script:OpenSettings.Add_Click({Update-CleanupPreview;$script:SettingsOverlay.Visibility='Visible'})
$script:CloseSettings.Add_Click({$script:SettingsOverlay.Visibility='Collapsed'})
$script:SettingsOverlay.Add_MouseLeftButtonDown({if([object]::ReferenceEquals($args[1].OriginalSource,$script:SettingsOverlay)){$script:SettingsOverlay.Visibility='Collapsed'}})
$script:Window.Add_PreviewKeyDown({if($args[1].Key -eq 'Escape' -and $script:SettingsOverlay.Visibility -eq 'Visible'){$script:SettingsOverlay.Visibility='Collapsed';$args[1].Handled=$true}})
# Operasyon degisince: formu yeniden ciz, paralellik ve log temizleme ipucunu guncelle.
$script:OperationPicker.Add_SelectionChanged({Show-OperationFields;Update-ParallelismState;Update-CleanupHint})
# Profil duzenleyicisini gizle/goster.
$script:ToggleProfiles.Add_Click({$script:ProfileOverlay.Visibility=if($script:ProfileOverlay.Visibility -eq 'Visible'){'Collapsed'}else{'Visible'}})
# Profil ekle/guncelle, parola dogrula ve profil sil butonlari.
$script:AddProfile.Add_Click({
    try{Save-ProfileFromForm}
    catch{[System.Windows.MessageBox]::Show($_.Exception.Message,'Profil hatas'+[char]0x0131,'OK','Warning')|Out-Null}
})
$script:TestProfile.Add_Click({
    try{Invoke-ProfileCredentialTest}
    catch{
        $script:Window.Cursor=$null
        [System.Windows.MessageBox]::Show($_.Exception.Message,'Profil hatas'+[char]0x0131,'OK','Warning')|Out-Null
    }
})
$script:RemoveProfile.Add_Click({
    if($null -eq $script:ProfileList.SelectedItem){return}
    $Removed=$script:ProfileList.SelectedItem
    $Question=([regex]::Unescape('Profil silinsin mi?'))+"`r`n{0}\{1}" -f $Removed.Domain,$Removed.UserName
    if([System.Windows.MessageBox]::Show($Question,'Profil sil','YesNo','Question') -ne 'Yes'){return}
    [void]$script:Profiles.Remove($Removed)
    Save-ProfileStore
    Refresh-ProfileList
    Write-AppLog "Removed profile $($Removed.Domain)\$($Removed.UserName)."
})
# Profil secilince form alanlarini doldur ve log temizleme onizlemesini guncelle.
$script:ProfileList.Add_SelectionChanged({Update-CleanupPreview;if($null -ne $script:ProfileList.SelectedItem){$Selected=$script:ProfileList.SelectedItem;$script:DomainInput.Text=$Selected.Domain;$script:UsernameInput.Text=$Selected.UserName;$script:MainProfileInput.IsChecked=[bool]$Selected.IsMain;$script:PasswordInput.Clear();Update-PasswordState;if($Selected.IsMain){$script:ActiveIdentity.Text="Main: $($Selected.Domain)\$($Selected.UserName)";$script:RunModeLabel.Text='Mevcut Windows oturumu'}else{$script:ActiveIdentity.Text="Selected: $($Selected.Domain)\$($Selected.UserName)";$script:RunModeLabel.Text='Launch cmd.exe as selected account'}}})
# the Main profile is pre-selected before this handler exists; re-select it so the form fields are filled
$InitialProfile=$script:ProfileList.SelectedItem
if($null -ne $InitialProfile){
    $script:ProfileList.SelectedItem=$null
    $script:ProfileList.SelectedItem=$InitialProfile
}
# Reload: plugin manifest'lerini yeniden tara.
$script:RefreshModules.Add_Click({Import-RemoteOpsPlugins;Show-OperationFields;Write-AppLog 'Operation list refreshed.'})
# RUN OPERATION: secili operasyonu ve form degerlerini Start-RemoteOpsRequest'e verir.
# Hata olursa kullaniciya mesaj kutusu ile gosterilir.
$script:RunOperation.Add_Click({try{$Operation=$script:OperationPicker.SelectedItem;if($null -eq $Operation){throw 'Choose an operation.'};Show-RemoteOpsOperationPreview -Operation $Operation -Values (Get-OperationValues)}catch{[System.Windows.MessageBox]::Show($_.Exception.Message,'Cannot start operation','OK','Warning')|Out-Null;Write-AppLog "Not started: $($_.Exception.Message)"}})
$script:PreviewOperation.Add_Click({$script:RunOperation.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))})
# Rapor sekmesi: tarih secimi, onceki/sonraki gun, bugun, yenile ve HTML disa aktar.
$script:ReportDate.SelectedDate=(Get-Date).Date
$script:ReportDate.Add_SelectedDateChanged({Update-ReportView})
$script:ReportPrev.Add_Click({if($null -ne $script:ReportDate.SelectedDate){$script:ReportDate.SelectedDate=([datetime]$script:ReportDate.SelectedDate).AddDays(-1)}})
$script:ReportNext.Add_Click({if($null -ne $script:ReportDate.SelectedDate){$script:ReportDate.SelectedDate=([datetime]$script:ReportDate.SelectedDate).AddDays(1)}})
$script:ReportToday.Add_Click({if($script:ReportDate.SelectedDate -eq (Get-Date).Date){Update-ReportView}else{$script:ReportDate.SelectedDate=(Get-Date).Date}})
$script:ReportRefresh.Add_Click({Update-ReportView})
$script:ReportExport.Add_Click({try{Export-ReportHtml}catch{[System.Windows.MessageBox]::Show($_.Exception.Message,'Rapor','OK','Warning')|Out-Null}})
$script:MainTabs.Add_SelectionChanged({if([object]::ReferenceEquals($args[1].OriginalSource,$script:MainTabs) -and $script:MainTabs.SelectedItem -eq $script:ReportTab){Update-ReportView}})
# Durdur, Activity temizle ve Log klasorunu ac butonlari.
$script:StopOperation.Add_Click({Stop-ActiveRuns})
$script:ForceStopOperation.Add_Click({Stop-ActiveRuns -Force})
$script:CloseProfileEditor.Add_Click({$script:ProfileOverlay.Visibility='Collapsed'})
$script:ClearActivity.Add_Click({$script:ActivityLog.Clear()})
$script:OpenLogs.Add_Click({$LogFolder=Join-Path $script:DataRoot 'Logs';if(-not(Test-Path -LiteralPath $LogFolder)){New-Item -ItemType Directory -Path $LogFolder -Force|Out-Null};Microsoft.PowerShell.Management\Start-Process -FilePath $LogFolder})
# Calisan islem varken pencere kapatilirsa uyar (islem arka planda devam edebilir).
$script:Window.Add_Closing({
    if($script:ActiveRuns.Count -gt 0){
        $Question=[regex]::Unescape('Devam eden operasyon var. Pencereyi kapatman\u0131z ilerleme takibini keser; i\u015Flem arka planda s\u00FCrebilir. Kapat\u0131ls\u0131n m\u0131?')
        if([System.Windows.MessageBox]::Show($Question,'REMOTE OPS','YesNo','Warning') -ne 'Yes'){$args[1].Cancel=$true}
    }
})
Update-ReportView
# ====================================================================
# OUTPUT TIMER (500 ms)
# Her calisan runner icin: progress.json -> ilerleme cubugu, stdout/stderr ->
# Activity paneli. Surec bittiginde exit code'a gore Tamamlandi / Basarisiz /
# Durduruldu olarak isaretlenir, progress dosyasi silinir ve rapor yenilenir.
# NOT: Exit code okunamazsa ($null) bu tek basina "basarisiz" sayilmaz.
# ====================================================================
$script:OpenPulledFiles.Add_Click({try{Show-RemoteOpsPulledFile ([string]$script:OpenPulledFiles.Tag)}catch{Write-AppLog ('Pulled files: '+$_.Exception.Message)}})
$script:OpenCollectedLogs.Add_Click({try{Open-RemoteOpsLogFolder ([string]$script:OpenCollectedLogs.Tag)}catch{Write-AppLog ('Collected logs: '+$_.Exception.Message)}})
$script:DeploymentTargets.AddHandler([Windows.Controls.Button]::ClickEvent,[Windows.RoutedEventHandler]{
    param($Sender,$EventArgs)
    $Button=$EventArgs.OriginalSource
    while($null -ne $Button -and $Button -isnot [Windows.Controls.Button]){$Button=[Windows.Media.VisualTreeHelper]::GetParent($Button)}
    if($Button -is [Windows.Controls.Button] -and $Button.Tag){
        try{if($Button.Uid -eq 'PulledFile'){Show-RemoteOpsPulledFile ([string]$Button.Tag)}else{Open-RemoteOpsLogFolder ([string]$Button.Tag)}}catch{Write-AppLog ('Client output: '+$_.Exception.Message)}
        $EventArgs.Handled=$true
    }
},$true)
$script:RunPicker.Add_SelectionChanged({Update-RemoteOpsRunSelection})
$script:OpenRunReport.Add_Click({
    try{$Path=Get-RemoteOpsSelectedReport;if($Path){Microsoft.PowerShell.Management\Start-Process -FilePath $Path -ErrorAction Stop}}
    catch{Write-AppLog ('Report: '+$_.Exception.Message)}
})
$script:OutputTimer=New-Object System.Windows.Threading.DispatcherTimer
$script:OutputTimer.Interval=[TimeSpan]::FromMilliseconds(500)
$script:OutputTimer.Add_Tick({
    foreach($Run in @($script:ActiveRuns)){
        Update-RunProgress $Run
        $StdOutLength=[int]$Run.StdOutLength
        $Text=Read-NewRunOutput -Path $Run.StdOutPath -ReadLength ([ref]$StdOutLength)
        $Run.StdOutLength=$StdOutLength
        if(-not [string]::IsNullOrEmpty($Text)){$script:ActivityLog.AppendText($Text);$script:ActivityLog.ScrollToEnd()}
        $StdErrLength=[int]$Run.StdErrLength
        $Text=Read-NewRunOutput -Path $Run.StdErrPath -ReadLength ([ref]$StdErrLength)
        $Run.StdErrLength=$StdErrLength
        if(-not [string]::IsNullOrEmpty($Text)){$script:ActivityLog.AppendText($Text);$script:ActivityLog.ScrollToEnd()}
        if($Run.Process.HasExited){
            Update-RunProgress $Run
            $RunExitCode=$null
            try{$Run.Process.WaitForExit();$RunExitCode=$Run.Process.ExitCode}catch{ }
            if($Run.OperationName -eq 'RecipeRun' -and ($Run.Stopped -or ($null -ne $RunExitCode -and $RunExitCode -ne 0) -or $Run.Completed -lt $Run.Total)){
                try{[void](Complete-RemoteOpsInterruptedRecipe -BasePath $script:DataRoot -CheckpointRoot $Run.CheckpointRoot -MissingOutcome $(if($Run.Stopped){'Cancelled'}else{'Error'}))}catch{Write-AppLog ('Recipe partial report: '+$_.Exception.Message)}
            }
            if($Run.Stopped){
                if($Run.OperationName -eq 'PackageDeployment'){
                    try{[void](Complete-RemoteOpsInterruptedDeployment -BasePath $script:DataRoot -CheckpointRoot $Run.CheckpointRoot);Write-AppLog (T 'K\u0131smi paket raporu kaydedildi.')}catch{Write-AppLog ('Partial report: '+$_.Exception.Message)}
                }
                $Run.Stage='Stopped'
                $Run.ProgressBar.Foreground=[System.Windows.Media.Brushes]::DarkOrange
            }elseif(($null -ne $RunExitCode -and [int]$RunExitCode -ne 0) -or $Run.Completed -lt $Run.Total){
                $Run.Stage='Failed'
                $Run.ProgressBar.Foreground=[System.Windows.Media.Brushes]::Firebrick
                if($Run.OperationName -eq 'PackageDeployment'){
                    try{[void](Complete-RemoteOpsInterruptedDeployment -BasePath $script:DataRoot -CheckpointRoot $Run.CheckpointRoot -MissingOutcome Error);Write-AppLog (T 'Kesilen paket raporu kaydedildi.')}catch{Write-AppLog ('Interrupted report: '+$_.Exception.Message)}
                }
            }else{
                $Run.Stage='Completed'
            }
            Remove-Item -LiteralPath $Run.ProgressPath -Force -ErrorAction SilentlyContinue
            Update-RunProgress $Run
            Write-AppLog "Process $($Run.Process.Id) exited with code $(if($null -eq $RunExitCode){'unknown'}else{$RunExitCode})."
            [void]$script:ActiveRuns.Remove($Run)
            Update-StopButton
            Update-ReportView
        }
    }
})
$script:OutputTimer.Start()
# Pencereyi ac; kullanici kapatana kadar bu satirda beklenir.
[void]$script:Window.ShowDialog()
