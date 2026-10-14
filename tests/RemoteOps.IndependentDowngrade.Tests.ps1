$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Packages.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Deployment.ps1')
$P=New-RemoteOpsPackageDefinition 'Three independent actions'
$P.Schema='RemoteOps.Package/2';$P.TargetVersion='5.0';$P.DowngradeEnabled=$true
Add-Member -InputObject $P -NotePropertyName DowngradeVersion -NotePropertyValue '2.0' -Force
Add-Member -InputObject $P -NotePropertyName Downgrade -NotePropertyValue (New-RemoteOpsPackageAction) -Force
foreach($A in 'Install','Uninstall','Downgrade'){$P.$A.Enabled=$true;$P.$A.PackagePath='\\server\share\'+$A;$P.$A.PackageFile=$A+'.cmd';$P.$A.Application=$A+'-ID';$P.$A.SearchType='ProductID'}
if(-not(Test-RemoteOpsPackageDefinition $P 'Downgrade').Valid){throw 'Independent downgrade definition rejected.'}
$script:Events=@();$script:Version='3.0'
$Detect={param($Part,$Computer)
 $script:Events+=('Detect:'+ $Part.Application)
 $Present=if($script:Version -eq 'absent'){$false}elseif($Part.Application -eq 'Uninstall-ID'){$script:Version -eq '3.0'}elseif($Part.Application -eq 'Downgrade-ID'){$script:Version -eq '2.0'}else{$script:Version -in @('3.0','5.0')}
 [pscustomobject]@{Status=$(if($Present){'Var'}else{'Yok'});DisplayVersion=$script:Version;ErrorDetail=''}
}
$Execute={param($Part,$Action,$Policy,$StepId)
 $script:Events+=('Execute:'+ $Part.PackageFile+':'+$Policy)
 if($Action -eq 'Uninstall'){$script:Version='absent'}else{$script:Version=if($Part.Application -eq 'Downgrade-ID'){'2.0'}else{'5.0'}}
 [pscustomobject]@{ExecutionStatus='Success';ExitCode=0;ErrorDetail=''}
}
$Compare={param($Current,$Target)[pscustomobject]@{Comparable=$true;Result=([version]$Current).CompareTo([version]$Target)}}
$Validate={param($Part,$Computer)$script:Events+='Validate:'+$Part.PackageFile}
$R=Invoke-RemoteOpsPackageDeployment $P Downgrade PC1 RUN -Detect $Detect -Execute $Execute -ValidateSource $Validate -VersionComparer $Compare
if($R.Outcome.Outcome -ne 'Success' -or $R.Outcome.FinalVersion -ne '2.0' -or @($R.Rows|Where-Object TargetVersion -ne '2.0').Count){throw 'Downgrade did not verify/report the independent old target version.'}
if($script:Events -contains 'Validate:Install.cmd' -or $script:Events -contains 'Execute:Install.cmd:Exact' -or $script:Events -notcontains 'Execute:Downgrade.cmd:Exact'){throw 'Downgrade reused the normal installer.'}
$script:Events=@();$script:Version='3.0'
$R=Invoke-RemoteOpsPackageDeployment $P Install PC1 RUN -Detect $Detect -Execute $Execute -ValidateSource $Validate -VersionComparer $Compare
if($R.Outcome.FinalVersion -ne '5.0' -or $script:Events -notcontains 'Execute:Install.cmd:AtLeast'){throw 'Normal installation was changed by the old-version definition.'}
$Only=Copy-RemoteOpsPackageDefinition $P;$Only.Install.Enabled=$false
if(-not(Test-RemoteOpsPackageDefinition $Only 'Downgrade').Valid){throw 'Downgrade unnecessarily requires a normal installer.'}
$Bad=Copy-RemoteOpsPackageDefinition $P;$Bad.Downgrade.PackageFile=''
if((Test-RemoteOpsPackageDefinition $Bad 'Downgrade').Valid){throw 'Downgrade enabled without its installer.'}
$Legacy=$P|Select-Object * -ExcludeProperty Downgrade,DowngradeVersion;$Legacy.Schema='RemoteOps.Package/1';$Legacy.TargetVersion='2.0'
$Migrated=Copy-RemoteOpsPackageDefinition $Legacy
if($Migrated.Schema -ne 'RemoteOps.Package/2' -or $Migrated.Downgrade.PackagePath -ne $Legacy.Install.PackagePath -or $Migrated.DowngradeVersion -ne '2.0'){throw 'Legacy downgrade migration changed previous meaning.'}
$t=$null;$e=$null;$RunnerAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.Runner.ps1'),[ref]$t,[ref]$e)
$Sources=$RunnerAst.Find({param($N)$N -is [Management.Automation.Language.AssignmentStatementAst] -and $N.Left.Extent.Text -eq '$Actions'},$true)
$Values=[pscustomobject]@{Action='Downgrade';PackageDefinition=$P}
$Actions=& ([scriptblock]::Create($Sources.Right.Extent.Text))
if(@($Actions).Count -ne 2 -or $Actions -contains 'Install' -or $Actions -notcontains 'Downgrade'){throw 'Account preflight still validates the normal installer during downgrade.'}
$Temp=Join-Path $env:TEMP ('RODowngrade-'+[guid]::NewGuid().ToString('N'))
try{
 $Saved=Save-RemoteOpsPackageDefinition $Temp $P
 $Reload=(Get-RemoteOpsPackageCatalog $Temp).Packages[0]
 if($Reload.Downgrade.PackageFile -ne 'Downgrade.cmd' -or $Reload.TargetVersion -ne '5.0' -or $Reload.DowngradeVersion -ne '2.0'){throw 'Independent package fields lost on disk.'}
 $Legacy.Id=[guid]::NewGuid().ToString('D');$Legacy.Name='Legacy fixture'
 $LegacyPath=Join-Path $Temp ($Legacy.Id+'.json');Write-RemoteOpsAtomicJson $LegacyPath $Legacy
 $LegacyLoaded=@((Get-RemoteOpsPackageCatalog $Temp).Packages|Where-Object Id -eq $Legacy.Id)[0]
 if($LegacyLoaded.Schema -ne 'RemoteOps.Package/2' -or (Get-Content $LegacyPath -Raw|ConvertFrom-Json).Schema -ne 'RemoteOps.Package/1'){throw 'Legacy read migration changed the stored file or lost the record.'}
 $Upgraded=Save-RemoteOpsPackageDefinition $Temp $LegacyLoaded $Legacy.Revision
 if($Upgraded.Revision -ne 2 -or (Get-Content $LegacyPath -Raw|ConvertFrom-Json).Schema -ne 'RemoteOps.Package/2'){throw 'Explicit save did not persist the upgraded schema/revision.'}
 $OldExport=Join-Path $Temp 'v1-export.json';Write-RemoteOpsAtomicJson $OldExport ([pscustomobject]@{Schema='RemoteOps.PackageExport/1';Packages=@($Legacy)})
 $Imported=Import-RemoteOpsPackageDefinitions (Join-Path $Temp 'imported') $OldExport
 if($Imported.Imported.Count -ne 1 -or $Imported.Imported[0].DowngradeVersion -ne '2.0'){throw 'Legacy export migration failed.'}
 $Export=Join-Path $Temp 'export.json';Export-RemoteOpsPackageDefinitions @($Saved) $Export
 $Data=Get-Content $Export -Raw|ConvertFrom-Json
 if($Data.Schema -ne 'RemoteOps.PackageExport/2'){throw 'New export could be misread by an old app.'}
}finally{if(Test-Path $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force}}
Write-Output 'PASS: independent install/downgrade source, identity, version, safety validation, migration, persistence and versioned export.'
