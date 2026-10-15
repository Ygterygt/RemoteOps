param([string]$PreviewDirectory='')
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Packages.ps1')
foreach($Module in @('TargetGroups','TargetGroupsUi','Preview','PreviewUi')){. (Join-Path $Root ('RemoteOps.App\RemoteOps.'+$Module+'.ps1'))}
$Library=Join-Path $Root 'RemoteOps.App\RemoteOps.PackageUi.ps1'
if(-not(Test-Path $Library)){throw 'Saved package screens are missing.'}
. $Library
Add-Type -AssemblyName PresentationFramework
$t=$null;$e=$null;$Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'),[ref]$t,[ref]$e)
if($e.Count){throw ($e|Out-String)}
foreach($Name in @('Get-OptionalPropertyValue','Get-TargetList','T','Get-OperationDescription','Show-OperationFields','Get-RemoteOpsOperationExample','Add-OperationField','Get-OperationValues','Assert-OperationInputs')){
    $F=$Ast.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq $Name},$true)
    . ([scriptblock]::Create($F.Extent.Text))
}
$Xaml=$Ast.Find({param($N)$N -is [Management.Automation.Language.AssignmentStatementAst] -and $N.Left.Extent.Text -eq '$script:WindowXaml'},$true)
Invoke-Expression $Xaml.Extent.Text
$script:Window=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader ([xml]$script:WindowXaml)))
foreach($Name in @('MainTabs','ProfileList','OperationPicker','OperationFields','OperationDescription','ParallelismPicker')){Set-Variable -Scope Script -Name $Name -Value $script:Window.FindName($Name)}
$C=$Ast.Find({param($N)$N -is [Management.Automation.Language.AssignmentStatementAst] -and $N.Left.Extent.Text -eq '$script:OperationCatalog'},$true);Invoke-Expression $C.Extent.Text
foreach($O in $script:OperationCatalog){[void]$script:OperationPicker.Items.Add($O)}
$Temp=Join-Path $env:TEMP ('RemoteOpsLibraryUi-'+[guid]::NewGuid().ToString('N'))
$script:DataRoot=$Temp;$script:ActiveRuns=New-Object Collections.ArrayList
function Write-AppLog {param($Message)}
$script:Started=@()
function Start-RemoteOpsRequest {param($Operation,$Values)$script:Started+=,[PSCustomObject]@{Operation=$Operation;Values=$Values}}
try{
    Initialize-RemoteOpsPackageUi -Window $script:Window -CatalogRoot $Temp -TargetGroupRoot (Join-Path $Temp 'groups')
    if($script:MainTabs.Items.Count -ne 4 -or $script:MainTabs.SelectedItem -ne $script:Window.FindName('PackagesTab')){throw 'Package tabs or default selection missing.'}
    $script:OperationPicker.SelectedItem=@($script:OperationCatalog|Where-Object Name -eq PackageTrigger)[0]
    Show-OperationFields
    foreach($Row in $script:OperationFields.Children){
        if($Row -isnot [Windows.Controls.Panel]){continue}
        $Control=$Row.Children|Where-Object Tag|Select-Object -First 1
        if($null -eq $Control){continue}
        switch([string]$Control.Tag){
            'Application'{$Control.Text='Manual example'}
            'PackagePath'{$Control.Text='\\server\share'}
            'PackageFile'{$Control.Text='install.cmd'}
            'Version'{$Control.Text='2.0'}
        }
    }
    $ManualValues=Get-OperationValues
    if($ManualValues.Application -ne 'Manual example'){throw 'Manual package fields were not read.'}
    $Shortcut=@($script:OperationFields.Children|Where-Object{$_ -is [Windows.Controls.Button]})[0]
    $Shortcut.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
    if($script:MainTabs.SelectedItem -ne $script:Window.FindName('PackageEditorTab') -or $script:PackageControls.InstallFileInput.Text -ne 'install.cmd' -or $script:PackageControls.PackageNameInput.Text -ne 'Manual example'){throw 'Manual shortcut did not open a populated editable package definition.'}
    $script:PackageControls.PackageNameInput.Text='Operator package name';$script:PackageControls.PackageCategoryInput.Text='Company category'
    $ManualDefinition=Get-RemoteOpsPackageEditorDefinition
    if($ManualDefinition.Name -ne 'Operator package name' -or $ManualDefinition.Category -ne 'Company category'){throw 'Manual conversion lost editable name/category.'}
    $script:PackageCatalogRoot=Join-Path $Temp 'manual-conversion'
    [void](Save-RemoteOpsPackageEditor)
    $ManualSaved=@((Get-RemoteOpsPackageCatalog $script:PackageCatalogRoot).Packages)
    if($ManualSaved.Count -ne 1 -or $ManualSaved[0].Name -ne 'Operator package name' -or $ManualSaved[0].Category -ne 'Company category' -or $ManualSaved[0].Install.PackageFile -ne 'install.cmd'){throw 'Converted manual package was not durably saved with edited metadata.'}
    $script:PackageCatalogRoot=$Temp
    Show-RemoteOpsPackageEditor
    $UI=$script:PackageControls
    $UI.PackageNameInput.Text='Example';$UI.PackageVersionInput.Text='2.0';$UI.InstallPathInput.Text='\\server\share';$UI.InstallFileInput.Text='install.cmd';$UI.InstallIdentityInput.Text='NEW-ID';$UI.InstallSearchInput.SelectedValue='ProductID'
    $UI.UninstallEnabled.IsChecked=$true;$UI.UninstallPathInput.Text='\\server\share';$UI.UninstallFileInput.Text='uninstall.cmd';$UI.UninstallIdentityInput.Text='OLD-ID';$UI.UninstallSearchInput.SelectedValue='ProductID';$UI.PackageDowngradeEnabled.IsChecked=$true
    if($UI.DowngradeCard.Visibility -ne 'Visible'){throw 'Old-version definition did not expand.'}
    $UI.DowngradeVersionInput.Text='1.0';$UI.DowngradePathInput.Text='\\server\share\old';$UI.DowngradeFileInput.Text='old.cmd';$UI.DowngradeIdentityInput.Text='LEGACY-ID';$UI.DowngradeSearchInput.SelectedValue='ProductID'
    $P=Get-RemoteOpsPackageEditorDefinition
    if($P.Install.Application -ne 'NEW-ID' -or $P.Uninstall.Application -ne 'OLD-ID'){throw 'Independent identities lost in editor.'}
    $Saved=Save-RemoteOpsPackageEditor
    if($Saved.Downgrade.PackageFile -ne 'old.cmd' -or $Saved.DowngradeVersion -ne '1.0' -or $Saved.TargetVersion -ne '2.0'){throw 'Third action was not persisted independently.'}
    if((Get-RemoteOpsPackageCatalog $Temp).Packages.Count -ne 1){throw 'UI save did not persist record.'}
    Update-RemoteOpsPackageList 'not-present' ''
    if($UI.PackageList.Items.Count -ne 0){throw 'Search ignored.'}
    Update-RemoteOpsPackageList 'example' ''
    if($UI.PackageList.Items.Count -ne 1){throw 'Search lost matching package.'}
    $UI.PackageList.SelectedIndex=0
    if(-not $UI.PackageDowngrade.IsEnabled -or $UI.PackageDetail.Text -notmatch '2.0'){throw 'Selected package actions/details missing.'}
    Show-RemoteOpsPackageEditor $Saved;$UI.PackageCategoryInput.Text='Old category';$Saved=Save-RemoteOpsPackageEditor
    $UI.PackageSearch.Text='';Update-RemoteOpsPackageList '' 'Old category'
    Show-RemoteOpsPackageEditor $Saved;$UI.PackageCategoryInput.Text='New category';$Saved=Save-RemoteOpsPackageEditor
    if($UI.PackageCategoryFilter.SelectedIndex -ne 0 -or $UI.PackageList.Items.Count -ne 1){throw 'Changing the last package category leaves All categories selected but the list empty.'}
    Show-RemoteOpsPackageEditor -Definition $Saved -AsCopy
    $Copy=Get-RemoteOpsPackageEditorDefinition
    if($Copy.Id -eq $Saved.Id){throw 'UI copy retained original identity.'}
    $UI.InstallFileInput.Text='..\bad.cmd'
    $Check=Test-RemoteOpsPackageDefinition (Get-RemoteOpsPackageEditorDefinition)
    Show-RemoteOpsPackageValidation $Check
    if($UI.PackageValidation.Visibility -ne 'Visible' -or $UI.PackageValidation.Text -notmatch 'PackageFile'){throw 'Editor validation was not displayed.'}
    $Profile=[PSCustomObject]@{Display='TEST\operator';Domain='TEST';UserName='operator';IsMain=$true;ProtectedPassword=''}
    [void]$script:ProfileList.Items.Add($Profile);$script:ProfileList.SelectedItem=$Profile
    Show-RemoteOpsPackageRunSummary $Saved Downgrade @('PC1','PC2') $Profile
    if($UI.PackageRunSummary.Text -notmatch '1.0' -or $UI.PackageRunSummary.Text -notmatch 'old.cmd' -or $UI.PackageRunSummary.Text -match 'Install:.*install.cmd'){throw 'Downgrade confirmation shows normal installation source/version.'}
    Start-RemoteOpsSavedPackageRun -Definition $Saved -Action Downgrade -Targets @('PC1','PC2') -Confirm DOWNGRADE
    if($script:Started.Count -ne 1 -or $script:Started[0].Values.PackageDefinition.Uninstall.Application -ne 'OLD-ID' -or $script:Started[0].Values.Targets -ne 'PC1 PC2'){throw 'Saved package run submitted wrong values.'}
    if($PreviewDirectory){
        New-Item -ItemType Directory -Path $PreviewDirectory -Force|Out-Null
        Show-RemoteOpsPackageEditor -Definition $Saved
        $UI.PackageList.SelectedIndex=0;$UI.PackageTargets.Text="PC-IST-001`r`nPC-IST-002`r`nPC-IST-003"
        foreach($Case in @(@('library',0,1280,650,96),@('editor',1,1280,650,96),@('library125',0,1060,545,120),@('editor125',1,1060,545,120))){
            $script:Window.Content.Background=$script:Window.Background
            $script:MainTabs.SelectedIndex=$Case[1];$Content=$script:Window.Content;$Content.Measure((New-Object Windows.Size $Case[2],$Case[3]));$Content.Arrange((New-Object Windows.Rect 0,0,$Case[2],$Case[3]));$Content.UpdateLayout()
            $Scale=$Case[4]/96;$Bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]($Case[2]*$Scale)),([int]($Case[3]*$Scale)),$Case[4],$Case[4],([Windows.Media.PixelFormats]::Pbgra32)
            $Background=New-Object Windows.Media.DrawingVisual;$Drawing=$Background.RenderOpen();$Drawing.DrawRectangle($script:Window.Background,$null,(New-Object Windows.Rect 0,0,$Case[2],$Case[3]));$Drawing.Close();$Bitmap.Render($Background);$Bitmap.Render($Content)
            if($Case[1] -eq 0){$ButtonPoint=$UI.PackageInstall.TransformToAncestor($Content).Transform((New-Object Windows.Point 0,$UI.PackageInstall.ActualHeight));if($ButtonPoint.Y -gt $Case[3]){throw 'Primary deployment action falls outside short-screen viewport.'}}
            $Encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$Encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($Bitmap));$Stream=[IO.File]::Create((Join-Path $PreviewDirectory ($Case[0]+'.png')));try{$Encoder.Save($Stream)}finally{$Stream.Dispose()}
        }
    }
    Write-Output 'PASS: WPF saved package editor, validation, persistence, search, copying, independent identities, action availability and request snapshot.'
}finally{$script:Window.Close();if(Test-Path $Temp){Remove-Item $Temp -Recurse -Force}}
