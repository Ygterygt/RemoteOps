$ErrorActionPreference='Stop'
$Root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Log=Join-Path $Root 'docs\v26-test-logs\final';New-Item -ItemType Directory -Path $Log -Force|Out-Null
$Rows=@()
foreach($Name in @('ConditionFriendlyUi','ConditionUi','RecipeUi','RecipeAutoNames','RecipeFocused','V26Compatibility','V26Layout','Recipes','PackageAppStartup')){
 $File='RemoteOps.'+$Name+'.Tests.ps1'
 $ErrorActionPreference='Continue'
 & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $Root ('tests\'+$File)) 1> (Join-Path $Log ($File+'.txt')) 2> (Join-Path $Log ($File+'.err.txt'))
 $Code=$LASTEXITCODE;$ErrorActionPreference='Stop'
 $Rows+=[pscustomobject]@{Test=$File;ExitCode=$Code};$Rows|Export-Csv (Join-Path $Root 'docs\V26_RERUN_RESULTS.csv') -NoTypeInformation -Encoding UTF8
 Write-Output ($File+': '+$Code)
}
if(@($Rows|Where-Object ExitCode -ne 0).Count){throw 'Final targeted checks failed.'}
