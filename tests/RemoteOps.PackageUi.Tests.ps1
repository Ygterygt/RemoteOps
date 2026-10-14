param([string]$PreviewDirectory='')
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
$Tokens=$null;$Errors=$null
$Ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'),[ref]$Tokens,[ref]$Errors)
if($Errors.Count){throw ($Errors|Out-String)}
foreach($Name in @('Get-OperationDescription','Get-OptionalPropertyValue','Assert-OperationInputs','Get-RemoteOpsOperationExample','Add-OperationField','Show-OperationFields','Get-OperationValues','Read-TargetProgress','Update-RunProgress')){
    $Definition=$Ast.Find({param($Node)$Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq $Name},$true)
    Set-Item ('Function:\'+$Name) -Value $Definition.Body.GetScriptBlock()
}
$Catalog=$Ast.Find({param($Node)$Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $Node.Left.Extent.Text -eq '$script:OperationCatalog'},$true)
Invoke-Expression $Catalog.Extent.Text
foreach($Operation in $script:OperationCatalog){
    if([string]::IsNullOrWhiteSpace((Get-OperationDescription $Operation))){throw "Missing description: $($Operation.Name)"}
}
if($script:OperationCatalog.Name -notcontains 'ScheduledTaskDelete'){throw 'Task delete is missing from UI.'}
$Operation=$script:OperationCatalog|Where-Object Name -eq 'PackageTrigger'
$Values=@{Action='Install';CheckMode='Version controlled';SearchType='DisplayName exact';PackagePath='\\server\packages';PackageFile='install.bat';Application='';Version=''}
Assert-OperationInputs -Operation $Operation -Values $Values
$Values.Application='Example'
$Refused=$false
try{Assert-OperationInputs -Operation $Operation -Values $Values}catch{$Refused=$true}
if(-not $Refused){throw 'Named version-controlled install allowed a missing version.'}
Add-Type -AssemblyName PresentationFramework
$Xaml=$Ast.Find({param($Node)$Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $Node.Left.Extent.Text -eq '$script:WindowXaml'},$true)
Invoke-Expression $Xaml.Extent.Text
$Reader=New-Object System.Xml.XmlNodeReader ([xml]$script:WindowXaml)
$Window=[Windows.Markup.XamlReader]::Load($Reader)
if($null -eq $Window.FindName('OperationDescription')){throw 'Description control is missing.'}
$script:OperationPicker=$Window.FindName('OperationPicker');$script:OperationFields=$Window.FindName('OperationFields');$script:OperationDescription=$Window.FindName('OperationDescription')
foreach($Operation in $script:OperationCatalog){[void]$script:OperationPicker.Items.Add($Operation)}
$script:OperationPicker.SelectedItem=$script:OperationCatalog|Where-Object Name -eq 'PackageTrigger'
Show-OperationFields
$ApplicationRow=$script:OperationFields.Children|Where-Object{@($_.Children|Where-Object Tag -eq 'Application').Count -eq 1}
if(@($ApplicationRow.Children|Where-Object{$_.GetType().Name -eq 'TextBlock' -and $_.Text -match 'Bos birakilirsa'}).Count -ne 1){throw 'Package identity hint is not below its input.'}
$ProgressBar=New-Object System.Windows.Controls.ProgressBar;$ProgressBar.Maximum=28;$ProgressBar.Height=12
$ProgressText=New-Object System.Windows.Controls.TextBlock
$Run=[PSCustomObject]@{ProgressPath=(Join-Path $env:TEMP ('MissingProgress-'+[guid]::NewGuid().ToString('N')));Total=28;Completed=10;Stage='Running';CurrentTarget='PC-11';StartedAt=(Get-Date);Title='Task list';ProgressBar=$ProgressBar;ProgressText=$ProgressText}
Update-RunProgress $Run
if($ProgressBar.Value -ne 10 -or $ProgressText.Text -notmatch 'Tamamlanan: 10 / 28.*Bekleyen: 18.*PC-11'){throw 'Progress view counters or current target are incorrect.'}
if($null -eq $Window.FindName('RunProgressPanel')){throw 'Progress panel is missing.'}
foreach($Operation in $script:OperationCatalog){
    $script:OperationPicker.SelectedItem=$Operation;Show-OperationFields
    $ActualValues=Get-OperationValues
    if($ActualValues.Count -ne $Operation.Fields.Count){throw "Input controls missing for $($Operation.Name)"}
}
$script:OperationPicker.SelectedItem=$script:OperationCatalog|Where-Object Name -eq 'PackageTrigger';Show-OperationFields
if($PreviewDirectory){
    New-Item -ItemType Directory -Path $PreviewDirectory -Force|Out-Null
    $PreviewRow=New-Object System.Windows.Controls.StackPanel
    $ProgressText.TextWrapping='Wrap';[void]$PreviewRow.Children.Add($ProgressText);[void]$PreviewRow.Children.Add($ProgressBar)
    [void]$Window.FindName('RunProgressPanel').Children.Add($PreviewRow)
    $Window.Show()
    foreach($Size in @(@(1320,850),@(1050,700))){
        $Window.Width=$Size[0];$Window.Height=$Size[1];$Window.UpdateLayout()
        $Bitmap=New-Object System.Windows.Media.Imaging.RenderTargetBitmap ([int]$Window.ActualWidth),([int]$Window.ActualHeight),96,96,([System.Windows.Media.PixelFormats]::Pbgra32)
        $Bitmap.Render($Window)
        $Encoder=New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $Encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($Bitmap))
        $Path=Join-Path $PreviewDirectory ("RemoteOps-$($Size[0]).png")
        $Stream=[System.IO.File]::Create($Path)
        try{$Encoder.Save($Stream)}finally{$Stream.Dispose()}
        Write-Output "Preview: $Path"
    }
}
$Window.Close()
Write-Output 'PASS: descriptions, task delete catalog, blank identity validation, package hint, WPF XAML and 28-PC progress view.'