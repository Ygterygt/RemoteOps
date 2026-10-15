$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$Root=Split-Path $PSScriptRoot -Parent
foreach($Name in @('Packages','TargetGroups','Preview')){$P=Join-Path $Root ('RemoteOps.App\RemoteOps.'+$Name+'.ps1');if(Test-Path $P){. $P}}
function Assert($Ok,$Message){if(-not $Ok){throw $Message}}
$T=$null;$E=$null;$Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'),[ref]$T,[ref]$E)
$Catalog=$Ast.Find({param($N)$N -is [Management.Automation.Language.AssignmentStatementAst] -and $N.Left.Extent.Text -eq '$script:OperationCatalog'},$true);Invoke-Expression $Catalog.Extent.Text
$Profile=[pscustomobject]@{Id='profile1';Display='TEST\operator';Domain='TEST';UserName='operator';IsMain=$true;ProtectedPassword='TOPSECRET'}
foreach($Op in $script:OperationCatalog){
 $V=@{Targets='PC-I pc-i PC-B';Action='Start';Confirm='DO_NOT_COPY';ValueType='REG_MULTI_SZ';Value="a`nb";Overwrite=$true}
 $P=New-RemoteOpsOperationPreview $Op $V $Profile 2 $false
 Assert ($P.Targets.Count -eq 2 -and $P.Effects -and $P.Rollback) ('Missing effect/targets: '+$Op.Name)
 Assert (($P|ConvertTo-Json -Depth 20) -notmatch 'TOPSECRET|DO_NOT_COPY|ProtectedPassword') 'Sensitive profile or approval leaked'
 Assert (Test-RemoteOpsOperationPreviewCurrent $P $Op $V $Profile 2 $false) 'Stable preview invalidated'
 Assert (-not(Test-RemoteOpsOperationPreviewCurrent $P $Op $V $Profile 3 $false)) 'Changed parallelism accepted'
 $Changed=$V.Clone();$Changed.Targets='PC-C'
 Assert (-not(Test-RemoteOpsOperationPreviewCurrent $P $Op $Changed $Profile 2 $false)) 'Changed targets accepted'
 $Profile.IsMain=$false;Assert (-not(Test-RemoteOpsOperationPreviewCurrent $P $Op $V $Profile 2 $false)) 'Changed profile semantics accepted';$Profile.IsMain=$true
}
$Op=@($script:OperationCatalog|Where-Object Name -eq RegistryEdit)[0]
$V=@{Targets='PC1';ValueType='REG_MULTI_SZ';Value="one`ntwo";RegistryPath='HKLM\Software\Example';ValueName='Items'}
$P=New-RemoteOpsOperationPreview $Op $V $Profile 1 $false
Assert ((Format-RemoteOpsOperationPreview $P) -match 'one\ntwo|one\r\ntwo') 'Multiline registry data lost'
$V.Value='';Assert (-not(Test-RemoteOpsOperationPreviewCurrent $P $Op $V $Profile 1 $false)) 'Changed blank registry value accepted'
$Package=New-RemoteOpsPackageDefinition 'Test';$Package.Install.Enabled=$true;$Package.Install.PackagePath='\\server\pkg';$Package.Install.PackageFile='install.cmd';$Package.Install.CheckMode='Trigger without checks'
$Op=@($script:OperationCatalog|Where-Object Name -eq PackageDeployment)[0]
$V=@{Targets='PC1';Action='Install';PackageDefinition=$Package;Confirm='TRIGGER'}
$P=New-RemoteOpsOperationPreview $Op $V $Profile 1 $false
Assert ((Format-RemoteOpsOperationPreview $P) -match 'install.cmd') 'Package source absent'
Assert (($P.Warnings -join ' ') -match 'doğrulanmayacak') 'Unchecked package warning absent'
$Package.DowngradeEnabled=$true;$Package.Downgrade.Enabled=$true;$Package.Downgrade.PackagePath='\\server\old';$Package.Downgrade.PackageFile='old.cmd';$Package.DowngradeVersion='1.0';$Package.TargetVersion='3.0'
$V.Action='Downgrade';$OldPreview=New-RemoteOpsOperationPreview $Op $V $Profile 1 $false
$OldText=Format-RemoteOpsOperationPreview $OldPreview
Assert ($OldText -match 'old.cmd' -and $OldText -notmatch 'install.cmd') 'Downgrade preview includes unrelated normal installer'
$V.Action='Install';$Package.DowngradeEnabled=$false;$P=New-RemoteOpsOperationPreview $Op $V $Profile 1 $false
$Package.Revision=2
Assert (-not(Test-RemoteOpsOperationPreviewCurrent $P $Op $V $Profile 1 $false)) 'Changed package revision accepted'
Assert ($P.Snapshot.Values.PackageDefinition.Revision -eq 1) 'Package snapshot mutated with source'
$Unknown=[pscustomobject]@{Name='CustomPlugin';Title='Custom';Category='Plugin';Fields=@(@{Key='Password'},@{Key='Public'})}
$P=New-RemoteOpsOperationPreview $Unknown @{Targets='PC1';Password='HIDDEN';Public='visible'} $Profile 1 $false
Assert (($P|ConvertTo-Json -Depth 20) -notmatch 'HIDDEN') 'Unknown private field leaked'
Assert (($P.Warnings -join ' ') -match 'bilinmiyor') 'Unknown plugin implied safe effects'
Write-Output 'PASS: 26 operation effects, immutable parameters, canonical fingerprint, stale profile/target/setting/package rejection, secret exclusion.'
