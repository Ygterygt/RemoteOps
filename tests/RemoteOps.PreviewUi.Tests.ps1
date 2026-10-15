param([string]$PreviewDirectory='')
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$Root=Split-Path $PSScriptRoot -Parent
$Temp=Join-Path $env:TEMP ('ROPreviewUI-'+[guid]::NewGuid().ToString('N'));$OldAppData=$env:APPDATA
function Assert($Ok,$Message){if(-not $Ok){throw $Message}}
function Click($Button){$Button.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))}
try{
 New-Item -ItemType Directory -Path $Temp -Force|Out-Null;$env:APPDATA=Join-Path $Temp 'profiles'
 $Source=[IO.File]::ReadAllText((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'))
 $Source=$Source.Replace('$script:AppRoot = Split-Path -Parent $PSCommandPath',('$script:AppRoot = '''+(Join-Path $Root 'RemoteOps.App')+''''))
 $Source=$Source.Replace('$script:DataRoot = ''C:\Temp\YD_RemoteOps.App''',('$script:DataRoot = '''+$Temp+'\data'''))
 $Source=$Source.Replace('[void]$script:Window.ShowDialog()','')
 . ([scriptblock]::Create($Source));$script:OutputTimer.Stop()
 foreach($Name in @('TargetGroups','Preview','PreviewUi')){$File=Join-Path $Root ('RemoteOps.App\RemoteOps.'+$Name+'.ps1');if(Test-Path $File){. $File}}
 $P=[pscustomobject]@{Display='TEST\operator';Domain='TEST';UserName='operator';IsMain=$true;ProtectedPassword='fixture'}
 $script:ProfileList.ItemsSource=@($P);$script:ProfileList.SelectedIndex=0
 $script:OperationPicker.SelectedItem=@($script:OperationCatalog|Where-Object Name -eq FilePull)[0];Show-OperationFields
 $script:OperationFields.Children|ForEach-Object{foreach($Input in $_.Children){if($Input.Tag -eq 'Path'){$Input.Text='C:\Temp\Example'};if($Input.Tag -eq 'Targets'){$Input.Text='PC-A PC-B'}}}
 $script:Dispatch=@();$script:OpenedPreview=$null
 function Start-RemoteOpsRequest {param($Operation,[hashtable]$Values)$script:Dispatch+=,[pscustomobject]@{Operation=$Operation;Values=$Values;Effective=(Get-EffectiveParallelism $Operation)}}
 $Preview=New-RemoteOpsOperationPreviewWindow $script:OperationPicker.SelectedItem (Get-OperationValues)
 Assert ($script:Dispatch.Count -eq 0 -and $Preview.Controls.Text.Text -match 'PC-A') 'Preview dispatched or lost target'
 Click $Preview.Controls.Cancel
 Assert ($script:Dispatch.Count -eq 0) 'Cancel dispatched'
 $Preview=New-RemoteOpsOperationPreviewWindow $script:OperationPicker.SelectedItem (Get-OperationValues)
 $Target=($script:OperationFields.Children|ForEach-Object{$_.Children}|Where-Object Tag -eq Targets)[0]
 $Target.Text='PC-C';Click $Preview.Controls.Start
 Assert ($script:Dispatch.Count -eq 0 -and $Preview.Controls.Error.Text) 'Stale preview started'
 $Preview.Window.Close()
 $Preview=New-RemoteOpsOperationPreviewWindow $script:OperationPicker.SelectedItem (Get-OperationValues)
 $P.Domain='OTHER';Click $Preview.Controls.Start
 Assert ($script:Dispatch.Count -eq 0 -and $Preview.Controls.Error.Text) 'Changed profile accepted by UI'
 $P.Domain='TEST';$Preview.Window.Close()
 $Preview=New-RemoteOpsOperationPreviewWindow $script:OperationPicker.SelectedItem (Get-OperationValues)
 $InputPath=($script:OperationFields.Children|ForEach-Object{$_.Children}|Where-Object Tag -eq Path)[0];$InputPath.Text='C:\Temp\Changed';Click $Preview.Controls.Start
 Assert ($script:Dispatch.Count -eq 0 -and $Preview.Controls.Error.Text) 'Changed parameter accepted by UI'
 $InputPath.Text='C:\Temp\Example';$Preview.Window.Close()
 $Preview=New-RemoteOpsOperationPreviewWindow $script:OperationPicker.SelectedItem (Get-OperationValues);Click $Preview.Controls.Start
 Assert ($script:Dispatch.Count -eq 1 -and $script:Dispatch[0].Values.Targets -eq 'PC-C') 'Approved preview dispatched wrong targets'
 function Show-RemoteOpsOperationPreview {param($Operation,$Values)$script:OpenedPreview=New-RemoteOpsOperationPreviewWindow $Operation $Values}
 Click $script:RunOperation
 Assert ($script:Dispatch.Count -eq 1 -and $null -ne $script:OpenedPreview) 'Run bypassed preview'
 $script:OpenedPreview.Window.Close()
 $Package=New-RemoteOpsPackageDefinition 'Fixture';$Package.Install.Enabled=$true;$Package.Install.PackagePath='\\server\packages';$Package.Install.PackageFile='install.cmd';$Package.Install.CheckMode='Trigger without checks'
 $Saved=Save-RemoteOpsPackageDefinition $script:PackageCatalogRoot $Package 0;Update-RemoteOpsPackageList
 $Before=$script:PackageControls.PackageTargets.Parent.Children.Count
 Update-RemoteOpsPackageList;Update-RemoteOpsPackageList
 Assert ($script:PackageControls.PackageTargets.Parent.Children.Count -eq $Before) 'Package refresh duplicates target-group pickers'
 $script:PackageControls.PackageList.SelectedItem=@($script:PackageControls.PackageList.Items|Where-Object Id -eq $Saved.Id)[0];$script:PackageControls.PackageTargets.Text='PC-A'
 Show-RemoteOpsPackageRunSummaryFromSelection Install
 Assert ($null -ne $script:PendingPackageRun.Preview) 'Package summary missing shared preview'
 $script:PackageControls.PackageTargets.Text='PC-B';$script:PackageControls.PackageRunConfirm.Text='TRIGGER';Click $script:PackageControls.PackageSummaryStart
 Assert ($script:Dispatch.Count -eq 1 -and $script:PackageControls.PackageRunError.Text) 'Changed package target started old preview'
 Show-RemoteOpsPackageRunSummaryFromSelection Install;$script:PackageControls.PackageRunConfirm.Text='TRIGGER';Click $script:PackageControls.PackageSummaryStart
 Assert ($script:Dispatch.Count -eq 2 -and $script:Dispatch[1].Values.Targets -eq 'PC-B') 'Package approved preview failed'
 $script:OperationPicker.SelectedItem=@($script:OperationCatalog|Where-Object Name -eq ApplicationInventory)[0];Show-OperationFields
 ($script:OperationFields.Children|ForEach-Object{$_.Children}|Where-Object Tag -eq Targets)[0].Text='PC1 PC2'
 $script:ParallelismPicker.SelectedItem=8
 $Preview=New-RemoteOpsOperationPreviewWindow $script:OperationPicker.SelectedItem (Get-OperationValues)
 Assert ($Preview.Preview.Snapshot.Parallelism -eq 8) 'Original parallel preview missing'
 $script:ParallelismPicker.SelectedItem=2;Click $Preview.Controls.Start
 Assert ($script:Dispatch.Count -eq 2 -and $Preview.Controls.Error.Text) 'Changed setting accepted by UI'
 $Preview.Window.Close();$script:ParallelismPicker.SelectedItem=8;$Preview=New-RemoteOpsOperationPreviewWindow $script:OperationPicker.SelectedItem (Get-OperationValues)
 Click $Preview.Controls.Start
 Assert ($script:Dispatch.Count -eq 3 -and $script:Dispatch[2].Effective -eq 8) 'Reviewed dispatch lost parallel execution metadata'
 $PackageOperation=@($script:OperationCatalog|Where-Object Name -eq PackageDeployment)[0];[void]$script:OperationPicker.Items.Add($PackageOperation);$script:OperationPicker.SelectedItem=$PackageOperation;Show-OperationFields
 ($script:OperationFields.Children|ForEach-Object{$_.Children}|Where-Object Tag -eq Targets)[0].Text='PC1'
 ($script:OperationFields.Children|ForEach-Object{$_.Children}|Where-Object Tag -eq SavedPackage)[0].SelectedIndex=0
 $Preview=New-RemoteOpsOperationPreviewWindow $script:OperationPicker.SelectedItem (Get-OperationValues)
 $Saved.Description='changed on disk';$Next=Save-RemoteOpsPackageDefinition $script:PackageCatalogRoot $Saved $Saved.Revision
 Click $Preview.Controls.Start
 Assert ($script:Dispatch.Count -eq 3 -and $Preview.Controls.Error.Text) 'General saved-package preview ignored changed disk revision'
 $Preview.Window.Close()
 if($PreviewDirectory){New-Item -ItemType Directory -Path $PreviewDirectory -Force|Out-Null}
 Write-Output 'PASS: real app preview/cancel/start events, stale target rejection, Run gate, shared package preview and target isolation.'
}finally{$env:APPDATA=$OldAppData;if($null -ne (Get-Variable OutputTimer -Scope Script -ErrorAction SilentlyContinue)){$script:OutputTimer.Stop()};if($null -ne (Get-Variable Window -Scope Script -ErrorAction SilentlyContinue)){$script:Window.Close()};if(Test-Path $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force}}
