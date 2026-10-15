$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Backups.ps1')
$Temp=Join-Path $env:TEMP ('RORollbackChoices-'+[guid]::NewGuid().ToString('N'))
try{
 foreach($Folder in 'RegistryRollback','ServiceTaskRollbacks'){New-Item -ItemType Directory -Path (Join-Path $Temp $Folder) -Force|Out-Null}
 @([pscustomobject]@{ComputerName='PC1';RegistryKey='Software\T';RegistryHive='HKEY_LOCAL_MACHINE';ValueName='Mode';OldExists='True';OldValue='old';NewValue='new';Action='Edit'},[pscustomobject]@{ComputerName='PC2';RegistryKey='S-1-5-21-100\Software\T';RegistryHive='HKEY_USERS';ValueName='Token';OldExists='False';OldValue='';NewValue='';Action='Edit'}) | Export-Csv (Join-Path $Temp 'RegistryRollback\edit.csv') -Delimiter ';' -NoTypeInformation
 @([pscustomobject]@{ComputerName='PC1';RegistryKey='Software\T';ValueName='Mode';OldExists='True';OldValue='';NewValue='';Action='Delete'}) | Export-Csv (Join-Path $Temp 'RegistryRollback\delete.csv') -Delimiter ';' -NoTypeInformation
 @([pscustomobject]@{ComputerName='PC1';ObjectType='Service';ObjectName='Spooler';Action='StartupType';NewStartMode='disabled';OldStartMode='Auto';OldState='Running'}) | Export-Csv (Join-Path $Temp 'ServiceTaskRollbacks\service.csv') -Delimiter ';' -NoTypeInformation
 @([pscustomobject]@{ComputerName='PC1';ObjectType='Service';ObjectName='Spooler';Action='StartStop';NewState='Stopped';OldState='Running'}) | Export-Csv (Join-Path $Temp 'ServiceTaskRollbacks\state.csv') -Delimiter ';' -NoTypeInformation
 @([pscustomobject]@{ComputerName='PC1';ObjectType='ScheduledTask';ObjectName='Nightly';TaskPath='\Ops\';Action='EnableDisable';NewEnabled='False';OldEnabled='True'}) | Export-Csv (Join-Path $Temp 'ServiceTaskRollbacks\task.csv') -Delimiter ';' -NoTypeInformation
 $Registry=@(Get-RemoteOpsRollbackChoices -BasePath $Temp -OperationName RegistryRollback)
 if($Registry.Count -ne 2){throw 'Registry manifests missing'}
 $Edit=@($Registry|Where-Object{$_.Id -like '*edit.csv'})[0]
 foreach($Expected in 'PC1','HKEY_LOCAL_MACHINE\Software\T','Mode','"new" -> "old"','PC2','HKEY_USERS\S-1-5-21-100','"" -> [absent]'){if(-not $Edit.Display.Contains($Expected)){throw "Missing summary detail: $Expected"}}
 $Delete=@($Registry|Where-Object{$_.Id -like '*delete.csv'})[0]
 if($Delete.Display -notlike '*[[]absent] -> ""*'){throw 'Deletion and empty string must be distinguished'}
 $Services=@(Get-RemoteOpsRollbackChoices -BasePath $Temp -OperationName ServiceTaskRollback)
 if($Services.Count -ne 3 -or -not @($Services|Where-Object{$_.Display -like '*PC1*Spooler*disabled -> Auto*'}).Count){throw 'Service rollback summary missing'}
 if(-not @($Services|Where-Object{$_.Display.Contains('Stopped -> Running')}).Count){throw 'Service state transition missing'}
 if(-not @($Services|Where-Object{$_.Display.Contains('Enabled=False -> Enabled=True')}).Count){throw 'Task state transition missing'}
 Add-Type -AssemblyName PresentationFramework
 $t=$null;$e=$null;$Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'),[ref]$t,[ref]$e)
 foreach($Name in 'Add-OperationField','Get-RemoteOpsOperationExample','Get-OperationValues','Assert-OperationInputs'){
  $F=$Ast.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq $Name},$true);. ([scriptblock]::Create($F.Extent.Text))
 }
 foreach($Operation in 'RegistryRollback','ServiceTaskRollback'){
  $script:DataRoot=$Temp;$script:OperationFields=New-Object Windows.Controls.StackPanel
  $script:OperationPicker=[pscustomobject]@{SelectedItem=[pscustomobject]@{Name=$Operation}}
  Add-OperationField @{Key='ManifestPath';Label='Rollback';Type='RollbackChoice'}
  $Values=Get-OperationValues
  if(-not(Test-Path -LiteralPath $Values.ManifestPath -PathType Leaf)){throw 'WPF must submit an exact manifest path'}
  $Failed=$false;try{Assert-OperationInputs -Operation ([pscustomobject]@{Name=$Operation}) -Values @{ManifestPath=''}}catch{$Failed=$true}
  if(-not $Failed){throw 'Empty rollback choice must not fall back to latest'}
  $Panel=New-Object Windows.Controls.Border;$Panel.Width=1100;$Panel.Height=180;$Panel.Background=[Windows.Media.Brushes]::White;$Panel.Child=$script:OperationFields
  $Panel.Measure([Windows.Size]::new(1100,180));$Panel.Arrange([Windows.Rect]::new(0,0,1100,180));$Panel.UpdateLayout()
  $Bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(1100,180,96,96,[Windows.Media.PixelFormats]::Pbgra32);$Bitmap.Render($Panel)
  $Encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$Encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($Bitmap))
  $Stream=[IO.File]::Create((Join-Path $Root ('docs\'+$Operation+'-v13.png')));try{$Encoder.Save($Stream)}finally{$Stream.Dispose()}
 }
 Write-Output 'PASS: registry rollback direction, roots, empty/absent values, service summary, real WPF manifest selection and empty selection guards.'
}finally{if((Split-Path $Temp -Parent) -ne $env:TEMP){throw 'Unsafe cleanup'};if(Test-Path -LiteralPath $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force}}
