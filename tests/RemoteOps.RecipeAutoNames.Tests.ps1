$ErrorActionPreference='Stop';$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Recipes.ps1')
$D=New-RemoteOpsRecipeDefinition 'Metadata';$D.Schema='RemoteOps.Recipe/4';$D.Steps=@([pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Automatic';Operation='ServiceList';Values=[pscustomobject]@{Filter=''};AutoName=$true})
Assert-RemoteOpsRecipeDefinition $D
$D.Schema='RemoteOps.Recipe/3';$Rejected=$false;try{Assert-RemoteOpsRecipeDefinition $D}catch{$Rejected=$true};if(-not $Rejected){throw 'Old schema accepted metadata'}
$D.Schema='RemoteOps.Recipe/4';$D.Steps[0].AutoName='true';$Rejected=$false;try{Assert-RemoteOpsRecipeDefinition $D}catch{$Rejected=$true};if(-not $Rejected){throw 'Non-boolean auto name accepted'}
Write-Host 'PASS schema4 explicit auto names and legacy schema guards'
