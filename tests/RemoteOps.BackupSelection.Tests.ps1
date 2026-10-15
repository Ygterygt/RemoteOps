$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Backups.ps1')
$Temp=Join-Path $env:TEMP ('ROBackupSelection-'+[guid]::NewGuid().ToString('N'))
try {
 New-Item -ItemType Directory -Path (Join-Path $Temp 'DeleteBackups\old_Delete') -Force|Out-Null
 @([pscustomobject]@{ComputerName='PC1';OriginalPath='C:\data\one.txt';BackupPath='fixture-one'},[pscustomobject]@{ComputerName='PC2';OriginalPath='D:\two.txt';BackupPath='fixture-two'}) | Export-Csv (Join-Path $Temp 'DeleteBackups\old_Delete\manifest.csv') -Delimiter ';' -NoTypeInformation
 $Items=@(Get-RemoteOpsBackupChoices -BasePath $Temp)
 if($Items.Count -ne 1 -or $Items[0].Id -ne 'old_Delete' -or $Items[0].Display -notlike '*PC1*C:\data\one.txt*PC2*D:\two.txt*'){throw 'Backup display must identify all computers and paths.'}
 New-Item -ItemType Directory -Path (Join-Path $Temp 'DeleteBackups\new_Delete') -Force|Out-Null
 if((Get-RemoteOpsBackupChoices -BasePath $Temp).Id -ne 'old_Delete'){throw 'Incomplete backups should not be offered.'}
 Add-Type -AssemblyName PresentationFramework
 $t=$null;$e=$null
 $Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'),[ref]$t,[ref]$e)
 if($e.Count){throw 'App syntax error'}
 foreach($Name in 'Add-OperationField','Get-RemoteOpsOperationExample','Get-OperationValues'){
  $F=$Ast.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq $Name},$true)
  . ([scriptblock]::Create($F.Extent.Text))
 }
 $script:DataRoot=$Temp
 $script:OperationFields=New-Object Windows.Controls.StackPanel
 $script:OperationPicker=[pscustomobject]@{SelectedItem=[pscustomobject]@{Name='FileRestore'}}
 Add-OperationField @{Key='BackupPath';Label='Backup';Type='BackupChoice'}
 $Combo=@($script:OperationFields.Children[0].Children|Where-Object{$_ -is [Windows.Controls.ComboBox]})[0]
 if($Combo.IsEditable -or $Combo.Items.Count -ne 1 -or (Get-OperationValues).BackupPath -ne 'old_Delete'){throw 'WPF selection must submit backup ID.'}
 $Window=New-Object Windows.Controls.Border
 $Window.Width=1000;$Window.Height=200;$Window.Background=[Windows.Media.Brushes]::White;$Window.Child=$script:OperationFields
 $Window.Measure([Windows.Size]::new(1000,200));$Window.Arrange([Windows.Rect]::new(0,0,1000,200));$Window.UpdateLayout()
 $Bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(1000,200,96,96,[Windows.Media.PixelFormats]::Pbgra32)
 $Bitmap.Render($Window)
 $Encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
 $Encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($Bitmap))
 $Stream=[IO.File]::Create((Join-Path $Root 'docs\backup-selection-v12.png'))
 try{$Encoder.Save($Stream)}finally{$Stream.Dispose()}
 $script:DataRoot=Join-Path $Temp 'empty'
 $script:OperationFields.Children.Clear()
 Add-OperationField @{Key='BackupPath';Label='Backup';Type='BackupChoice'}
 $Combo=@($script:OperationFields.Children[0].Children|Where-Object{$_ -is [Windows.Controls.ComboBox]})[0]
 if($Combo.IsEnabled -or (Get-OperationValues).BackupPath -ne ''){throw 'Empty backup list must be disabled with no selection.'}
 . (Join-Path $Root 'Modules\FileOperations.ps1')
 $Failed=$false
 try {Restore-AODeleteBackup -BasePath $Temp -ReachableSystems @('PC1') -OperationID TEST -OperationDate TEST -OperationTime TEST -BackupRunId 'missing_Delete'}catch{$Failed=$true}
 if(-not $Failed){throw 'Missing selected backup must fail instead of selecting latest.'}
 $script:BackupAnswers=New-Object 'System.Collections.Generic.Queue[string]'
 $script:BackupAnswers.Enqueue('old_Delete');$script:BackupAnswers.Enqueue('RESTORE')
 function Read-Host {param($Prompt) if($script:BackupAnswers.Count -eq 0){throw 'Unexpected prompt'};$script:BackupAnswers.Dequeue()}
 function Add-AOFileOperationRows {param($BasePath,$OperationName,$OperationID,$OperationDate,$OperationTime,$Rows,$TechnicalLogWriter,$OperationHistoryWriter) if(@($Rows|Where-Object{$_.KaynakOperationID -ne 'old'}).Count){throw 'Wrong backup restored'};return 'fixture.csv'}
 $Result=Restore-AODeleteBackup -BasePath $Temp -ReachableSystems @() -OperationID TEST -OperationDate TEST -OperationTime TEST
 if(-not $Result.Completed -or $Result.ResultCsv -ne 'fixture.csv'){throw 'Stable backup ID was not accepted by restore prompt.'}
 $script:BackupAnswers.Enqueue('missing_Delete')
 $Failed=$false
 try{Restore-AODeleteBackup -BasePath $Temp -ReachableSystems @() -OperationID TEST -OperationDate TEST -OperationTime TEST}catch{$Failed=$true}
 if(-not $Failed){throw 'Missing prompt ID must fail.'}
 Write-Output 'PASS: manifest details, incomplete backups, stable ID and missing-selection rejection.'
}finally{
 if((Split-Path $Temp -Parent) -ne $env:TEMP){throw 'Unsafe cleanup path'}
 if(Test-Path -LiteralPath $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force}
}
