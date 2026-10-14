$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
$Tokens=$null;$Errors=$null
$Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'),[ref]$Tokens,[ref]$Errors)
foreach($Name in @('T','Get-OptionalPropertyValue','Read-TargetProgress','Update-RunProgress','Set-RemoteOpsRunTargetRows','Update-RemoteOpsOperationRunView')){
    $F=$Ast.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq $Name},$true)
    if($null -ne $F){. ([scriptblock]::Create($F.Extent.Text))}
}
$Temp=Join-Path $env:TEMP ('RemoteOpsMonitor-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path $Temp|Out-Null
    $script:DeploymentTargets=[PSCustomObject]@{ItemsSource=@()}
    $Run=[PSCustomObject]@{ProgressPath=(Join-Path $Temp 'one.json');Title='Manual install';TargetLabel='Example / Install';Total=3;Completed=0;Stage='Running';CurrentTarget='';StartedAt=(Get-Date);Stopped=$false;ProgressBar=[PSCustomObject]@{Value=0};ProgressText=[PSCustomObject]@{Text=''};Targets=@('PC1','PC2','PC3')}
    [PSCustomObject]@{Total=3;Completed=1;CurrentTarget='PC2';Stage='Running';Targets=@([PSCustomObject]@{ComputerName='PC1';Stage='Completed';Outcome='Success';LogCollectionStatus='Failed'},[PSCustomObject]@{ComputerName='PC2';Stage='Running';Outcome=''},[PSCustomObject]@{ComputerName='PC3';Stage='Completed';Outcome='Unreachable'})}|ConvertTo-Json -Depth 6|Set-Content $Run.ProgressPath -Encoding UTF8
    Update-RunProgress $Run
    if(@($script:DeploymentTargets.ItemsSource).Count -ne 3){throw 'Operations are missing from the shared target table.'}
    $Items=@($script:DeploymentTargets.ItemsSource)
    if($Items[0].Outcome -ne $script:RemoteOpsOutcomeTitles.Success -or $Items[1].Step -notmatch 'leniyor' -or $Items[0].PackageName -ne 'Example / Install'){throw 'Live target outcome/phase/package label is wrong.'}
    if($Items[2].OutcomeCode -ne 'Unreachable' -or $Items[2].Outcome -ne $script:RemoteOpsOutcomeTitles.Unreachable){throw 'Monitor lost neutral unreachable outcome'}
    if($Items[0].LogStatusRaw -ne 'Failed'){throw 'Generic target view lost collection failure status.'}
    $Other=$Run|Select-Object *;$Other.ProgressPath=Join-Path $Temp 'two.json';$Other.Targets=@('PC1');$Other.Total=1;$Other.Title='Inventory';$Other.TargetLabel='Inventory'
    Update-RunProgress $Other
    if(@($script:DeploymentTargets.ItemsSource).Count -ne 4){throw 'A concurrent operation replaced another operation in the shared target table.'}
    $Run.Stage='Stopped';$Run.Stopped=$true
    Update-RunProgress $Run
    $Items=@($script:DeploymentTargets.ItemsSource|Where-Object PackageName -eq 'Example / Install')
    if($Run.Stage -ne 'Stopped' -or $Items[0].Outcome -ne $script:RemoteOpsOutcomeTitles.Success -or $Items[1].Outcome -eq $script:RemoteOpsOutcomeTitles.Success){throw 'Stop erased known results or invented success for unfinished targets.'}
    Add-Type -AssemblyName PresentationFramework
    $Xaml=$Ast.Find({param($N)$N -is [Management.Automation.Language.AssignmentStatementAst] -and $N.Left.Extent.Text -eq '$script:WindowXaml'},$true)
    Invoke-Expression $Xaml.Extent.Text
    $View=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader ([xml]$script:WindowXaml)))
    try{
        $View.FindName('SharedRuns').IsExpanded=$true
        $Grid=$View.FindName('DeploymentTargets');$Grid.ItemsSource=$Items
        $View.Content.Measure((New-Object Windows.Size 1280,730));$View.Content.Arrange((New-Object Windows.Rect 0,0,1280,730));$View.Content.UpdateLayout()
        $OfflineRow=$Grid.ItemContainerGenerator.ContainerFromItem($Items[2])
        if($null -eq $OfflineRow -or $OfflineRow.Background.ToString() -ne '#FFFBF0D9'){throw 'Actual WPF unreachable row must be yellow'}
        if($Grid.Columns[1].ActualWidth -lt 150){throw 'Package/operation column is too narrow to identify the running job.'}
    }finally{$View.Close()}
    Write-Output 'PASS: manual and generic operation target monitoring, concurrent runs and honest stopped results.'
}finally{if(Test-Path -LiteralPath $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force}}
