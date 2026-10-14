$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
$Library=Join-Path $Root 'RemoteOps.App\RemoteOps.Packages.ps1'
if(-not(Test-Path $Library)){throw 'Package catalog API is missing.'}
. $Library
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
$Temp=Join-Path $env:TEMP ('RemoteOpsPackages-'+[guid]::NewGuid().ToString('N'))
try{
    $P=New-RemoteOpsPackageDefinition -Name ('Uygulama '+[char]0x00e7+' <>&')
    $P.Install.Enabled=$true;$P.Install.PackagePath='\\server\packages';$P.Install.PackageFile='install.cmd'
    $P.Install.Application='Example';$P.TargetVersion='2.0'
    $P.Uninstall.Enabled=$true;$P.Uninstall.PackagePath='\\server\packages';$P.Uninstall.PackageFile='remove.cmd';$P.Uninstall.Application='OLD-ID';$P.Uninstall.SearchType='ProductID'
    $P.DowngradeEnabled=$true
$P.Downgrade=($P.Install|Select-Object *);$P.Downgrade.Enabled=$true;$P.Downgrade.CheckMode='Version controlled';$P.DowngradeVersion='2.0'
    Assert (Test-RemoteOpsPackageDefinition $P 'Downgrade').Valid 'Valid downgrade rejected.'
    $Saved=Save-RemoteOpsPackageDefinition $Temp $P 0
    Assert ($Saved.Revision -eq 1) 'Initial revision must be 1.'
    $Cat=Get-RemoteOpsPackageCatalog $Temp
    Assert ($Cat.Packages.Count -eq 1 -and $Cat.Packages[0].Name -ceq $P.Name) 'Catalog reload lost package/Unicode.'
    $Saved.Description='changed';$Edited=Save-RemoteOpsPackageDefinition $Temp $Saved 1
    Assert ($Edited.Revision -eq 2) 'Edit revision not increased.'
    $Rejected=$false;try{Save-RemoteOpsPackageDefinition $Temp $Saved 1|Out-Null}catch{$Rejected=$true}
    Assert $Rejected 'Stale edit overwrote a newer revision.'
    Add-Member -InputObject $Edited -NotePropertyName Password -NotePropertyValue 'DO-NOT-EXPORT'
    Add-Member -InputObject $Edited -NotePropertyName Targets -NotePropertyValue @('PC1')
    $Copy=Copy-RemoteOpsPackageDefinition $Edited -NewIdentity
    Assert ($Copy.Id -ne $Edited.Id -and $Copy.Revision -eq 1) 'Copy shares identity.'
    Assert ($null -eq $Copy.PSObject.Properties['Password'] -and $null -eq $Copy.PSObject.Properties['Targets']) 'Snapshot retained private fields.'
    $Bad=Copy-RemoteOpsPackageDefinition $Edited;$Bad.Install.Enabled='true'
    Assert (-not(Test-RemoteOpsPackageDefinition $Bad).Valid) 'String true accepted as boolean.'
    $Bad=Copy-RemoteOpsPackageDefinition $Edited;$Bad.Install.PackageFile='..\install.cmd'
    Assert (-not(Test-RemoteOpsPackageDefinition $Bad).Valid) 'Path escape accepted.'
    $Bad=Copy-RemoteOpsPackageDefinition $Edited;$Bad.DowngradeVersion=''
    Assert (-not(Test-RemoteOpsPackageDefinition $Bad 'Downgrade').Valid) 'Downgrade has no target version.'
    $Export=Join-Path $Temp 'export.json';Export-RemoteOpsPackageDefinitions @($Edited) $Export
    $Preview=Get-RemoteOpsPackageImportPreview $Temp $Export
    Assert ($Preview.Conflicts.Count -eq 1 -and $Preview.Packages.Count -eq 1) 'Import preview must show conflicts before any writes.'
    Assert ((Get-Content $Export -Raw) -notmatch 'DO-NOT-EXPORT|"Targets"') 'Export leaked private data.'
    $Import=Import-RemoteOpsPackageDefinitions $Temp $Export Skip
    Assert ($Import.Imported.Count -eq 0 -and $Import.Conflicts.Count -eq 1) 'Skip did not report conflict.'
    $Import=Import-RemoteOpsPackageDefinitions $Temp $Export Copy
    Assert ($Import.Imported.Count -eq 1 -and $Import.Imported[0].Id -ne $Edited.Id) 'Copy import replaced identity.'
    $Import=Import-RemoteOpsPackageDefinitions $Temp $Export Replace
    Assert ($Import.Imported.Count -eq 1 -and $Import.Imported[0].Revision -eq 3) 'Replace did not version record.'
    Set-Content -LiteralPath (Join-Path $Temp 'broken.json') -Value '{invalid' -Encoding UTF8
    $Cat=Get-RemoteOpsPackageCatalog $Temp
    Assert ($Cat.Packages.Count -eq 2 -and $Cat.Errors.Count -ge 1) 'Broken records must be visible without losing good records.'
    $Bad=Copy-RemoteOpsPackageDefinition $Edited;$Bad.Id='..\escape';$Rejected=$false
    try{Save-RemoteOpsPackageDefinition $Temp $Bad 0|Out-Null}catch{$Rejected=$true}
    Assert $Rejected 'Non-GUID record path accepted.'
    Remove-RemoteOpsPackageDefinition $Temp $Edited.Id 3
    Assert (-not(Test-Path (Join-Path $Temp ($Edited.Id+'.json')))) 'Delete did not remove selected record.'
    Write-Output 'PASS: package catalog, validation, revisions, Unicode, snapshots, import/export and path boundaries.'
}finally{if(Test-Path $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force}}
