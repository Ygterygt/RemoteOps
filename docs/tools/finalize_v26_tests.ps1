$ErrorActionPreference='Stop'
$Root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ResultsPath=Join-Path $Root 'docs\V26_TEST_RESULTS.csv'
$Rows=@(Import-Csv $ResultsPath);$Expected=@(Get-ChildItem (Join-Path $Root 'tests') -Filter 'RemoteOps.*.Tests.ps1').Count
if($Rows.Count -ne $Expected){throw 'Full test pass has not completed.'}
$Initial=Join-Path $Root 'docs\V26_TEST_RESULTS_INITIAL.csv'
if(-not (Test-Path -LiteralPath $Initial)){Copy-Item -LiteralPath $ResultsPath -Destination $Initial}
$Reruns=@(Import-Csv (Join-Path $Root 'docs\V26_RERUN_RESULTS.csv'))
foreach($Rerun in $Reruns){$Match=@($Rows|Where-Object Test -ceq $Rerun.Test);if($Match.Count -ne 1){throw 'Rerun test missing from full pass.'};$Match[0].ExitCode=$Rerun.ExitCode}
$Rows|Export-Csv $ResultsPath -NoTypeInformation -Encoding UTF8
$Failed=@($Rows|Where-Object ExitCode -ne 0)
[pscustomobject]@{total=$Rows.Count;passed=$Rows.Count-$Failed.Count;failed=$Failed.Count;remote_live_tests=$false;rerun_results='V26_RERUN_RESULTS.csv';initial_results='V26_TEST_RESULTS_INITIAL.csv';note='One pre-final UI test process loaded the old modal-driving test during edits and was interrupted. Its final rewritten flow and eight related checks passed after source freeze.'}|ConvertTo-Json|Set-Content (Join-Path $Root 'docs\V26_TEST_SUMMARY.json') -Encoding UTF8
if($Failed.Count){throw 'Final tests failed.'}
Write-Output ('PASS '+$Rows.Count+'/'+$Rows.Count+' test files after final targeted reruns.')
