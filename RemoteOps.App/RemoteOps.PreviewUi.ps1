function Get-RemoteOpsPreviewUiSettings {
    param($Operation)
    $Parallelism=1;$Cleanup=$false
    if(Get-Command Get-EffectiveParallelism -ErrorAction SilentlyContinue){$Parallelism=Get-EffectiveParallelism $Operation}
    $Setting=Get-Variable SettingCleanupLogs -Scope Script -ErrorAction SilentlyContinue
    if($null -ne $Setting -and $null -ne $Setting.Value){$Cleanup=[bool]$Setting.Value.IsChecked}
    return [pscustomobject]@{Parallelism=$Parallelism;CleanupLogs=$Cleanup}
}
function Copy-RemoteOpsPreviewInputValues {
    param([hashtable]$Values)
    $Copy=@{};$Object=ConvertFrom-Json (ConvertTo-Json -InputObject $Values -Depth 30)
    foreach($Property in $Object.PSObject.Properties){$Copy[$Property.Name]=$Property.Value}
    return $Copy
}
function New-RemoteOpsOperationPreviewWindow {
    param($Operation,[hashtable]$Values)
    Assert-OperationInputs $Operation $Values
    $Settings=Get-RemoteOpsPreviewUiSettings $Operation
    $Preview=New-RemoteOpsOperationPreview $Operation $Values $script:ProfileList.SelectedItem $Settings.Parallelism $Settings.CleanupLogs
    $Xml=[xml]@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="İşlem öncesi önizleme" Width="760" Height="590" MinWidth="480" MinHeight="330" WindowStartupLocation="CenterScreen" Background="#EFF4F8">
 <DockPanel Margin="18"><StackPanel DockPanel.Dock="Top"><TextBlock Text="İşlem öncesi önizleme" FontSize="24" FontWeight="SemiBold" Foreground="#1F3342"/><TextBlock Text="Hesap, hedef ve işlem etkisini inceleyin. Bu ekran hedefte işlem yapmaz." TextWrapping="Wrap" Foreground="#62778A" Margin="0,5,0,12"/></StackPanel>
 <StackPanel DockPanel.Dock="Bottom" Margin="0,10,0,0"><TextBlock x:Name="Error" Foreground="#A44721" TextWrapping="Wrap" MaxHeight="80"/><WrapPanel Margin="0,8,0,0"><Button x:Name="Start" Content="İnceledim, başlat" Padding="18,9" Margin="0,0,10,0"/><Button x:Name="Cancel" Content="Vazgeç" Padding="18,9"/></WrapPanel></StackPanel>
 <TextBox x:Name="Text" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Padding="12" Background="White" BorderBrush="#CFDCE5" FontSize="13"/>
 </DockPanel>
</Window>
'@
    $Window=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $Xml))
    $Area=[Windows.SystemParameters]::WorkArea;$Window.Width=[Math]::Min(760,$Area.Width-32);$Window.Height=[Math]::Min(590,$Area.Height-40)
    $Controls=@{};foreach($Name in @('Text','Error','Start','Cancel')){$Controls[$Name]=$Window.FindName($Name)}
    $Controls.Text.Text=Format-RemoteOpsOperationPreview $Preview
    $State=[pscustomobject]@{Window=$Window;Controls=$Controls;Preview=$Preview;Values=(Copy-RemoteOpsPreviewInputValues $Values);Started=$false}
    $Controls.Start.Tag=$State;$Controls.Cancel.Tag=$State
    $Controls.Cancel.Add_Click({$this.Tag.Window.Close()})
    $Controls.Start.Add_Click({Start-RemoteOpsReviewedOperation $this.Tag})
    return $State
}
function Show-RemoteOpsOperationPreview {
    param($Operation,[hashtable]$Values)
    $State=New-RemoteOpsOperationPreviewWindow $Operation $Values
    $Owner=Get-Variable Window -Scope Script -ErrorAction SilentlyContinue
    if($null -ne $Owner -and $null -ne $Owner.Value -and $Owner.Value.IsVisible){$State.Window.Owner=$Owner.Value}
    [void]$State.Window.ShowDialog()
}
function Start-RemoteOpsReviewedOperation {
    param($State)
    if($State.Started){return}
    try{
        $CurrentOperation=$script:OperationPicker.SelectedItem;$CurrentValues=Get-OperationValues
        if($null -ne $CurrentOperation -and $CurrentOperation.Name -eq 'PackageDeployment'){
            $Definition=Get-RemoteOpsPreviewValue $CurrentValues PackageDefinition
            $Id=[string](Get-RemoteOpsPreviewValue $Definition Id)
            $Fresh=@((Get-RemoteOpsPackageCatalog $script:PackageCatalogRoot).Packages|Where-Object Id -eq $Id)
            if($Fresh.Count -ne 1){throw 'Paket silinmiş veya okunamıyor. Önizlemeyi yeniden açın.'}
            $CurrentValues.PackageDefinition=$Fresh[0]
        }
        $Settings=Get-RemoteOpsPreviewUiSettings $CurrentOperation
        if(-not(Test-RemoteOpsOperationPreviewCurrent $State.Preview $CurrentOperation $CurrentValues $script:ProfileList.SelectedItem $Settings.Parallelism $Settings.CleanupLogs)){throw 'Hesap, hedef, işlem veya ayarlar değişti. Önizlemeyi kapatıp yeniden açın.'}
        Assert-OperationInputs $CurrentOperation $CurrentValues
        # Only approval text may be entered anew; reviewed parameters are detached.
        $Approved=Copy-RemoteOpsPreviewInputValues $State.Values
        if($CurrentValues.ContainsKey('Confirm')){$Approved.Confirm=[string]$CurrentValues.Confirm}
        $Approved.Targets=$State.Preview.Targets -join ' '
        $State.Controls.Start.IsEnabled=$false
        Start-RemoteOpsRequest -Operation $State.Preview.Operation -Values $Approved
        $State.Started=$true;$State.Window.Close()
    }catch{$State.Controls.Error.Text=$_.Exception.Message;if(-not $State.Started){$State.Controls.Start.IsEnabled=$true}}
}
function Start-RemoteOpsReviewedPackageRun {
    $Pending=$script:PendingPackageRun;$UI=$script:PackageControls
    if($null -eq $Pending){throw 'Önce dağıtım özetini açın.'}
    $Selected=$UI.PackageList.SelectedItem
    if($null -eq $Selected -or $Selected.Id -ne $Pending.Definition.Id){throw 'Paket seçimi değişti. Özeti yeniden açın.'}
    $Fresh=@((Get-RemoteOpsPackageCatalog $script:PackageCatalogRoot).Packages|Where-Object Id -eq $Selected.Id)
    if($Fresh.Count -ne 1){throw 'Paket kaydı silinmiş veya okunamıyor. Özeti yeniden açın.'}
    $Operation=@($script:OperationCatalog|Where-Object Name -eq PackageDeployment)[0]
    $Values=@{Action=$Pending.Action;Targets=$UI.PackageTargets.Text;PackageDefinition=$Fresh[0]}
    $Settings=Get-RemoteOpsPreviewUiSettings $Operation
    if(-not(Test-RemoteOpsOperationPreviewCurrent $Pending.Preview $Operation $Values $script:ProfileList.SelectedItem $Settings.Parallelism $Settings.CleanupLogs)){throw 'Hesap, hedef, paket veya ayarlar değişti. Özeti yeniden açın.'}
    $Expected=if($Pending.Action -eq 'Downgrade'){'DOWNGRADE'}else{'TRIGGER'}
    if($UI.PackageRunConfirm.Text -cne $Expected){throw ('Başlatmak için yazın: '+$Expected)}
    Start-RemoteOpsSavedPackageRun $Pending.Definition $Pending.Action $Pending.Targets $UI.PackageRunConfirm.Text
    $UI.PackageSummaryPanel.Visibility='Collapsed';$script:PendingPackageRun=$null
}
