$ErrorActionPreference='Stop';Set-StrictMode -Version 2
Add-Type -AssemblyName PresentationFramework
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Backups.ps1')
$t=$null;$e=$null;$Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'),[ref]$t,[ref]$e)
foreach($Name in 'Add-OperationField','Get-RemoteOpsOperationExample','Get-OperationValues','Assert-OperationInputs'){$F=$Ast.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq $Name},$true);. ([scriptblock]::Create($F.Extent.Text))}
$Catalog=$Ast.Find({param($N)$N -is [Management.Automation.Language.AssignmentStatementAst] -and $N.Left.Extent.Text -eq '$script:OperationCatalog'},$true)
Invoke-Expression $Catalog.Extent.Text
$Temp=Join-Path $env:TEMP ('ROTypedUi-'+[guid]::NewGuid().ToString('N'))
function Save-Preview {param($Panel,[string]$Name,[int]$Height)
 $Border=New-Object Windows.Controls.Border;$Border.Width=1100;$Border.Height=$Height;$Border.Background=[Windows.Media.Brushes]::White;$Border.Child=$Panel
 $Border.Measure([Windows.Size]::new(1100,$Height));$Border.Arrange([Windows.Rect]::new(0,0,1100,$Height));$Border.UpdateLayout()
 $Bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(1100,$Height,96,96,[Windows.Media.PixelFormats]::Pbgra32);$Bitmap.Render($Border)
 $Encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$Encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($Bitmap))
 $Stream=[IO.File]::Create((Join-Path $Root ('docs\'+$Name)));try{$Encoder.Save($Stream)}finally{$Stream.Dispose()}
}
try{
 $script:DataRoot=$Temp;$script:OperationFields=New-Object Windows.Controls.StackPanel
 $Operation=@($script:OperationCatalog|Where-Object Name -eq RegistryEdit)[0];$script:OperationPicker=[pscustomobject]@{SelectedItem=$Operation}
 foreach($Field in $Operation.Fields){Add-OperationField $Field}
 $Inputs=@{};foreach($Row in $script:OperationFields.Children){foreach($Control in $Row.Children){if($Control.Tag){$Inputs[[string]$Control.Tag]=$Control}}}
 if($Inputs.ValueType.Items.Count -ne 6 -or $Inputs.ValueType.SelectedItem -ne 'Auto' -or -not $Inputs.Value.AcceptsReturn){throw 'Typed edit controls missing'}
 $Inputs.RegistryPath.Text='HKLM\Software\Example';$Inputs.ValueName.Text='Limit';$Inputs.ValueType.SelectedItem='REG_QWORD';$Inputs.Value.Text='18446744073709551615';$Inputs.Targets.Text='PC1'
 $Values=Get-OperationValues
 if($Values.ValueType -ne 'REG_QWORD' -or $Values.Value -ne '18446744073709551615'){throw 'UI lost type or QWORD text precision'}
 Assert-OperationInputs $Operation $Values
 $Values.Value='';Assert-OperationInputs $Operation $Values
 $ValueHint=Get-RemoteOpsOperationExample $Operation @{Key='Value'}
 if(-not $ValueHint.Contains('DWORD/QWORD') -or -not $ValueHint.Contains('REG_MULTI_SZ')){throw 'Value hint must explain typed input'}
 Save-Preview $script:OperationFields 'registry-edit-v14.png' 550
 New-Item -ItemType Directory -Path (Join-Path $Temp 'RegistryRollback') -Force|Out-Null
 @([pscustomobject]@{ComputerName='PC1';RegistryKey='Software\Example';ValueName='Limit';OldExists='True';OldType='REG_QWORD';NewType='REG_QWORD';OldValue='18446744073709551615';NewValue='9007199254740993';Action='Edit';ReturnValue='0'},[pscustomobject]@{ComputerName='PC2';RegistryKey='Software\Example';ValueName='Paths';OldExists='True';OldType='REG_MULTI_SZ';NewType='REG_MULTI_SZ';OldValue='["old","second"]';NewValue='["new"]';Action='Edit';ReturnValue='0'})|Export-Csv (Join-Path $Temp 'RegistryRollback\typed.csv') -Delimiter ';' -NoTypeInformation
 $script:OperationFields=New-Object Windows.Controls.StackPanel;$script:OperationPicker=[pscustomobject]@{SelectedItem=[pscustomobject]@{Name='RegistryRollback'}}
 Add-OperationField @{Key='ManifestPath';Label='Registry rollback';Type='RollbackChoice'}
 $Combo=@($script:OperationFields.Children[0].Children|Where-Object{$_ -is [Windows.Controls.ComboBox]})[0]
 foreach($Text in 'REG_QWORD','REG_MULTI_SZ','9007199254740993 -> 18446744073709551615','["new"] -> ["old","second"]'){if(-not $Combo.SelectedItem.Display.Contains($Text)){throw "Typed rollback UI detail missing $Text"}}
 Save-Preview $script:OperationFields 'registry-rollback-types-v14.png' 150
 Write-Output 'PASS: WPF type selector, exact QWORD text, empty strings, multiline input and typed rollback summaries.'
}finally{if((Split-Path $Temp -Parent) -ne $env:TEMP){throw 'Unsafe cleanup'};if(Test-Path -LiteralPath $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force}}
