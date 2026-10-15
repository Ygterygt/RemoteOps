$ErrorActionPreference='Stop'
$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Recipes.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.ConditionUi.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.RecipeUi.ps1')
if(-not (Get-Command Get-RemoteOpsRecipeAutoName -ErrorAction SilentlyContinue)){throw 'Missing automatic action names'}
$Step=[pscustomobject]@{Id='a';Name='';Operation='ServiceControl';Values=[pscustomobject]@{ServiceName='Spooler';Action='Restart'}}
if((Get-RemoteOpsRecipeAutoName $Step) -notmatch 'Spooler'){throw 'Auto name omits subject'}
$C=[pscustomobject]@{Id='c';Operation='RecipeCondition';Name='Legacy';Values=@{}}
$A=[pscustomobject]@{Id='a';Operation='ServiceList';ConditionId='c';Name='A';Values=@{}}
$B=[pscustomobject]@{Id='b';Operation='ServiceList';ConditionId='c';Name='B';Values=@{}}
if(@(Get-RemoteOpsRecipeUiUnits @($C,$A,$B)).Count -ne 1){throw 'Shared legacy scope must stay one move unit'}
if(@(Get-RemoteOpsRecipeUiUnits @($C,$A,$B))[0].Steps.Count -ne 3){throw 'Shared scope split'}
Write-Host 'PASS action names and scope units'
