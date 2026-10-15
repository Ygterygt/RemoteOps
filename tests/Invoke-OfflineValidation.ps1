[CmdletBinding()]
param([string]$OutputRoot='')
$ErrorActionPreference='Stop'
$Root=Split-Path $PSScriptRoot -Parent
if(-not $OutputRoot){$OutputRoot=Join-Path $Root 'TestResults\Offline'}
New-Item -ItemType Directory -Path $OutputRoot -Force|Out-Null
$Engine=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$Rows=@()
foreach($Name in @('Conditions','ConditionAuto','Recipes','RecipeAutoNames','RecipeFocused','ConditionUi','ConditionFriendlyUi','RecipeUi','V26Compatibility','V26Layout','RecipeResults','ConditionAutoExecution')){
 $File='RemoteOps.'+$Name+'.Tests.ps1'
 $Previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
 try{& $Engine -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $File) 1> (Join-Path $OutputRoot ($File+'.out.txt')) 2> (Join-Path $OutputRoot ($File+'.err.txt'));$Code=$LASTEXITCODE}finally{$ErrorActionPreference=$Previous}
 $Rows+=[pscustomobject]@{Test=$File;ExitCode=$Code};Write-Host ($File+': '+$Code)
}
$Rows|Export-Csv (Join-Path $OutputRoot 'regression.csv') -NoTypeInformation -Encoding UTF8
if(@($Rows|Where-Object ExitCode -ne 0).Count){throw 'Offline regression failed.'}
$Acceptance=Join-Path $OutputRoot 'acceptance'
& $Engine -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'lightweight\Invoke-LightweightAcceptance.ps1') -OutputRoot $Acceptance
if($LASTEXITCODE -ne 0){throw 'Offline acceptance failed.'}
& $Engine -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'lightweight\IndependentChecks.ps1') -EvidenceRoot $Acceptance
if($LASTEXITCODE -ne 0){throw 'Independent evidence check failed.'}
Write-Host 'PASS: 12 regression files, 17 operational scenarios, independent persisted evidence checks. No live targets.'
