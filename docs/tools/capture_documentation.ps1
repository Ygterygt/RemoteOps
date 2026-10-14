param([string]$OutputDirectory=(Join-Path (Split-Path -Parent $PSScriptRoot) ''))
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$TaskTemporary=Join-Path $env:TEMP ('RemoteOpsDocs-'+[guid]::NewGuid().ToString('N'))
$PreviousAppData=$env:APPDATA
try {
    New-Item -ItemType Directory -Path $TaskTemporary -Force|Out-Null
    $env:APPDATA=$TaskTemporary
    $AppPath=Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'
    $Source=[IO.File]::ReadAllText($AppPath)
    $Source=$Source.Replace('$script:AppRoot = Split-Path -Parent $PSCommandPath',('$script:AppRoot = '''+(Join-Path $Root 'RemoteOps.App').Replace("'","''")+''''))
    $Source=$Source.Replace('$script:DataRoot = ''C:\Temp\YD_RemoteOps.App''',('$script:DataRoot = '''+$TaskTemporary.Replace("'","''")+''''))
    $Source=$Source.Replace('[void]$script:Window.ShowDialog()','')
    . ([scriptblock]::Create($Source))
    $script:OutputTimer.Stop()
    $script:ProfileList.ItemsSource=$null
    $ExampleProfile=[PSCustomObject]@{Display='TEST\operator';Domain='TEST';UserName='operator';IsMain=$true;ProtectedPassword=''}
    $script:ProfileList.ItemsSource=@($ExampleProfile);$script:ProfileList.SelectedIndex=0
    $script:ActiveIdentity.Text='TEST\operator (example)'
    $script:ActivityLog.Clear()
    New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
    function Save-DocumentationView([string]$Name){
        $Content=$script:Window.Content;$Width=1280;$Height=730
        $Content.Background=$script:Window.Background
        $Content.Measure((New-Object Windows.Size $Width,$Height))
        $Content.Arrange((New-Object Windows.Rect 0,0,$Width,$Height));$Content.UpdateLayout()
        $Bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap $Width,$Height,96,96,([Windows.Media.PixelFormats]::Pbgra32)
        $Background=New-Object Windows.Media.DrawingVisual;$Drawing=$Background.RenderOpen()
        $Drawing.DrawRectangle($script:Window.Background,$null,(New-Object Windows.Rect 0,0,$Width,$Height));$Drawing.Close()
        $Bitmap.Render($Background);$Bitmap.Render($Content)
        $Encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
        $Encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($Bitmap))
        $Stream=[IO.File]::Create((Join-Path $OutputDirectory ($Name+'.png')))
        try{$Encoder.Save($Stream)}finally{$Stream.Dispose()}
    }
    $script:MainTabs.SelectedItem=$script:OperationTab
    $Operation=$script:OperationCatalog|Where-Object Name -eq 'ApplicationCheck'
    $script:OperationPicker.SelectedItem=$Operation
    Show-OperationFields $Operation
    Save-DocumentationView 'operasyon'
    foreach($Pair in @(@('FilePull','ornek-dosya'),@('RegistryEdit','ornek-registry'),@('ServiceControl','ornek-servis'),@('ScheduledTaskAction','ornek-task'),@('ProcessKill','ornek-process'))){
        $script:OperationPicker.SelectedItem=@($script:OperationCatalog|Where-Object Name -eq $Pair[0])[0]
        Show-OperationFields
        Save-DocumentationView $Pair[1]
    }
    $script:OperationPicker.SelectedItem=$Operation;Show-OperationFields

    $MonitorPath=Join-Path $TaskTemporary 'demo-progress.json'
    [PSCustomObject]@{Total=2;Completed=1;CurrentTarget='PC-TEST-002';Stage='Running';Targets=@(
        [PSCustomObject]@{ComputerName='PC-TEST-001';Stage='Completed';Outcome='Success'},
        [PSCustomObject]@{ComputerName='PC-TEST-002';Stage='Running';Outcome=''}
    )}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $MonitorPath -Encoding UTF8
    $DemoRun=[PSCustomObject]@{ProgressPath=$MonitorPath;Title='Install or uninstall package';TargetLabel='Example / Install';Targets=@('PC-TEST-001','PC-TEST-002');Total=2;Completed=0;CurrentTarget='';Stage='Running';StartedAt=(Get-Date);Stopped=$false;ProgressBar=(New-Object Windows.Controls.ProgressBar);ProgressText=(New-Object Windows.Controls.TextBlock)}
    $DemoRun.ProgressBar.Maximum=2
    $DemoReport=Join-Path $script:DataRoot 'Logs\Operations\PackageTrigger\DOCS-DEMO'
    $DemoLogs=Join-Path $script:DataRoot 'PulledLogs\DOCS-DEMO\PC-TEST-001\Install'
    New-Item -ItemType Directory -Path $DemoReport,$DemoLogs -Force|Out-Null
    Set-Content (Join-Path $DemoLogs 'example.log') 'Example log; fixture only.'
    [IO.File]::WriteAllText(($MonitorPath+'.reportroot'),$DemoReport)
    Update-RunProgress $DemoRun
    [void]$script:RunProgressPanel.Children.Add($DemoRun.ProgressText)
    $script:SharedRuns.IsExpanded=$true
    $script:CommonRunSummary.Text='Devam eden is: 1 (ornek)'
    Save-DocumentationView 'operasyon-izleme'
    $OfflineSnapshot=Get-Content -LiteralPath $MonitorPath -Raw|ConvertFrom-Json
    $OfflineSnapshot.Completed=2;$OfflineSnapshot.Stage='Completed';$OfflineSnapshot.Targets[1].Stage='Completed';$OfflineSnapshot.Targets[1].Outcome='Unreachable'
    $OfflineSnapshot|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $MonitorPath -Encoding UTF8
    Update-RunProgress $DemoRun
    Save-DocumentationView 'operasyon-erisilemedi'
    $script:SharedRuns.IsExpanded=$false;$script:RunProgressPanel.Children.Clear()
    $SampleOutcomes=@(
        [PSCustomObject]@{ComputerName='PC-TEST-001';Outcome='Success';CompletedAt=(Get-Date);PackageName='Example 2.0';PackageId='DEMO';Action='Downgrade'},
        [PSCustomObject]@{ComputerName='PC-TEST-002';Outcome='Unreachable';CompletedAt=(Get-Date);PackageName='Example 2.0';PackageId='DEMO';Action='Downgrade'}
    )
    [void](Write-RemoteOpsLedger -BasePath $script:DataRoot -OperationID DOCS-DEMO -Operation PackageDeployment -Category Applications -Outcomes $SampleOutcomes)
    $script:MainTabs.SelectedItem=$script:ReportTab;Update-ReportView
    Save-DocumentationView 'rapor'
    $ReportScroll=$script:CategoryPanel
    while($null -ne $ReportScroll -and $ReportScroll -isnot [Windows.Controls.ScrollViewer]){$ReportScroll=[Windows.Media.VisualTreeHelper]::GetParent($ReportScroll)}
    if($null -ne $ReportScroll){$ReportScroll.ScrollToEnd();Save-DocumentationView 'rapor-paketler';$ReportScroll.ScrollToTop()}
    $script:SettingsOverlay.Visibility='Visible'
    Save-DocumentationView 'ayarlar'
    $script:SettingsOverlay.Visibility='Collapsed'
    $script:ProfileOverlay.Visibility='Visible'
    Save-DocumentationView 'profiller'
    $script:ProfileOverlay.Visibility='Collapsed'
    $ExamplePackage=New-RemoteOpsPackageDefinition 'Example'
    $ExamplePackage.TargetVersion='2.0';$ExamplePackage.DowngradeEnabled=$true
    foreach($Action in @('Install','Uninstall')){
        $ExamplePackage.$Action.Enabled=$true
        $ExamplePackage.$Action.PackagePath='\\server\share\Example\2.0'
        $ExamplePackage.$Action.PackageFile=($Action.ToLowerInvariant()+'.cmd')
        $ExamplePackage.$Action.SearchType='ProductID'
        $ExamplePackage.$Action.Application=if($Action -eq 'Install'){'NEW-ID'}else{'OLD-ID'}
    }
    $ExamplePackage.Downgrade=($ExamplePackage.Install|Select-Object *);$ExamplePackage.Downgrade.Enabled=$true;$ExamplePackage.DowngradeVersion='1.0';$ExamplePackage.Downgrade.PackagePath='\\server\share\Example\1.0';$ExamplePackage.Downgrade.Application='LEGACY-ID'
    Show-RemoteOpsPackageEditor $ExamplePackage
    Save-DocumentationView 'paket-editor-genel'
    $Visual=$script:PackageControls.InstallFields
    while($null -ne $Visual -and $Visual -isnot [Windows.Controls.ScrollViewer]){
        $Visual=[Windows.Media.VisualTreeHelper]::GetParent($Visual)
    }
    if($null -eq $Visual){throw 'Editor scroll viewer missing.'}
    $Visual.ScrollToVerticalOffset(260)
    Save-DocumentationView 'paket-editor-eylemler'
    $Visual.ScrollToEnd()
    Save-DocumentationView 'paket-editor-eski-surum'
    $script:MainTabs.SelectedItem=$script:PackagesTab
    Show-RemoteOpsPackageRunSummary $ExamplePackage 'Downgrade' @('PC-TEST-001','PC-TEST-002') $ExampleProfile
    Save-DocumentationView 'paket-onay'
    Write-Output 'Documentation captures created from actual WPF; no remote operation started.'
} finally {
    if($null -ne (Get-Variable Window -Scope Script -ErrorAction SilentlyContinue)){$script:Window.Close()}
    $env:APPDATA=$PreviousAppData
    $Resolved=[IO.Path]::GetFullPath($TaskTemporary)
    $TempRoot=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
    if($Resolved.StartsWith($TempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $Resolved)){
        Remove-Item -LiteralPath $Resolved -Recurse -Force
    }
}
