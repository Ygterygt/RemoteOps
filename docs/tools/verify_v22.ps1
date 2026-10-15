$ErrorActionPreference='Stop'
$Root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$LogRoot=Join-Path $Root 'docs\v22-test-logs';New-Item -ItemType Directory $LogRoot -Force|Out-Null
$Results=@()
foreach($Test in @(Get-ChildItem (Join-Path $Root 'tests') -Filter 'RemoteOps.*.Tests.ps1'|Sort-Object Name)){
 $Out=Join-Path $LogRoot ($Test.Name+'.txt');$Err=Join-Path $LogRoot ($Test.Name+'.err.txt')
 $ErrorActionPreference='Continue'
 & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $Test.FullName 1> $Out 2> $Err
 $Code=$LASTEXITCODE
 $ErrorActionPreference='Stop'
 $Results+=[pscustomobject]@{Test=$Test.Name;ExitCode=$Code}
 $Results|Export-Csv (Join-Path $Root 'docs\V22_TEST_RESULTS.csv') -NoTypeInformation -Encoding UTF8
 Write-Output ($Test.Name+': '+$Code)
}
$Failures=@($Results|Where-Object ExitCode -ne 0)
[pscustomobject]@{total=$Results.Count;passed=$Results.Count-$Failures.Count;failed=$Failures.Count;remote_live_tests=$false}|ConvertTo-Json|Set-Content (Join-Path $Root 'docs\V22_TEST_SUMMARY.json') -Encoding UTF8
if($Failures.Count){throw ($Failures|Out-String)}
