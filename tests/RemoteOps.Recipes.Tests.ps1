$ErrorActionPreference='Stop';$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Recipes.ps1')
function Assert($C,$M){if(-not $C){throw $M}}
function Reject([scriptblock]$A){$F=$false;try{& $A}catch{$F=$true};Assert $F 'Expected rejection'}
$Temp=Join-Path $env:TEMP ('Recipes_'+[guid]::NewGuid().ToString('N'))
try{
 $D=New-RemoteOpsRecipeDefinition 'Pilot' 'Two steps';$D.Steps=@([pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='List';Operation='ServiceList';Values=@{Filter='Spooler'}},[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Start';Operation='ServiceControl';Values=@{ServiceName='Spooler';Action='Start'}})
 $Saved=Save-RemoteOpsRecipeDefinition $Temp $D 0;Assert ($Saved.Revision -eq 1) 'Revision1';Assert ((Get-RemoteOpsRecipeCatalog $Temp).Recipes.Count -eq 1) 'Catalog'
 Reject {Save-RemoteOpsRecipeDefinition $Temp $Saved 0}
 $Copy=Copy-RemoteOpsRecipeDefinition $Saved -NewIdentity;Assert ($Copy.Id -ne $Saved.Id -and $Copy.Steps[0].Id -ne $Saved.Steps[0].Id) 'New identities'
 $P=[pscustomobject]@{Domain='TEST';UserName='operator';IsMain=$true;ProtectedPassword='secret'}
 $S=New-RemoteOpsRecipeRunSnapshot $Saved @('PC-IST-001','pc-ist-001','PC2') $P $false
 Assert ($S.Targets.Count -eq 2 -and ($S|ConvertTo-Json -Depth 20) -notmatch 'secret|ProtectedPassword') 'Targets/secrets'
 Assert-RemoteOpsRecipeRunSnapshot $S
 $Saved.Steps[0].Name='Changed';Assert ($S.Definition.Steps[0].Name -eq 'List') 'Detached snapshot'
 $Bad=Copy-RemoteOpsRecipeDefinition $D;$Bad.Steps[0].Values|Add-Member -NotePropertyName Confirm -NotePropertyValue 'START';Reject {Assert-RemoteOpsRecipeDefinition $Bad}
 $Bad=Copy-RemoteOpsRecipeDefinition $D;$Bad.Steps[0].Operation='ProcessKill';Reject {Assert-RemoteOpsRecipeDefinition $Bad}
 $Bad=Copy-RemoteOpsRecipeDefinition $D;$Bad.Steps[1].Id=$Bad.Steps[0].Id;Reject {Assert-RemoteOpsRecipeDefinition $Bad}
 $Bad=Copy-RemoteOpsRecipeDefinition $D;$Bad.Description='x'*2001;Reject {Assert-RemoteOpsRecipeDefinition $Bad}
 $Bad=Copy-RemoteOpsRecipeDefinition $D;$Bad.Steps=@(1..21|ForEach-Object{[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='List';Operation='ServiceList';Values=@{Filter='x'}}});Reject {Assert-RemoteOpsRecipeDefinition $Bad}
 $S.Definition.Steps[0].Name='Tampered';Reject {Assert-RemoteOpsRecipeRunSnapshot $S}
 Set-Content (Join-Path $Temp 'broken.json') '{';Assert ((Get-RemoteOpsRecipeCatalog $Temp).Issues.Count -eq 1) 'Bad catalog visible'

 $Package=New-RemoteOpsPackageDefinition 'Fixture';$Package.Install.Enabled=$true;$Package.Install.PackagePath='\\server\packages';$Package.Install.PackageFile='install.cmd';$Package.Install.CheckMode='Trigger without checks'
 $D=New-RemoteOpsRecipeDefinition 'Package';$D.Revision=1;$D.Steps=@([pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Install';Operation='PackageDeployment';Values=@{Action='Install';PackageDefinition=$Package}})
 $Snap=New-RemoteOpsRecipeRunSnapshot $D @('PC1') $P $false;$Package.Name='Changed';Assert ($Snap.Definition.Steps[0].Values.PackageDefinition.Name -eq 'Fixture') 'Package snapshot changed'
 $Package|Add-Member -NotePropertyName ProtectedPassword -NotePropertyValue 'secret';Reject {Assert-RemoteOpsRecipeDefinition $D}
 $Package.PSObject.Properties.Remove('ProtectedPassword');$D.Description='İ'*2000;$D.Steps=@(1..20|ForEach-Object{[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Install';Operation='PackageDeployment';Values=@{Action='Install';PackageDefinition=$Package}}});Reject {New-RemoteOpsRecipeRunSnapshot $D @('PC1') $P $false}
 Write-Host 'PASS recipe schema, revisions, identities, snapshots, secrets and invalid records'
}finally{if(Test-Path $Temp){Remove-Item $Temp -Recurse -Force}}
