$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
$t=$null;$e=$null;$Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'Modules\ApplicationWorkers.ps1'),[ref]$t,[ref]$e)
$Fn=$Ast.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq 'Compare-ApplicationVersion'},$true)
. ([scriptblock]::Create($Fn.Extent.Text))
foreach($Case in @(@('Exact','3.0','Error'),@('Exact','2.0','Completed'),@('AtLeast','3.0','Completed'),@('Exact','1.0','Error'))){
    $Row=[PSCustomObject]@{ExecutionStatus='Success';PostCheckStatus='Var';PostCheckErrorDetail='';PostCheckDisplayVersion=$Case[1];Decision='OlderVersion'}
    Set-RemoteOpsPackageOutcome -Rows @($Row) -Action INSTALL -CheckMode VersiyonKontrollu -TargetVersion '2.0' -VersionComparer ${function:Compare-ApplicationVersion} -VersionMatchPolicy $Case[0]
    if($Row.Outcome -ne $Case[2]){throw "Policy $($Case[0]), version $($Case[1]) produced $($Row.Outcome), expected $($Case[2])."}
}
$Worker=$Ast.Find({param($N)$N -is [Management.Automation.Language.AssignmentStatementAst] -and $N.Left.Extent.Text -eq '$PackageScript'},$true).Right.Find({param($N)$N -is [Management.Automation.Language.ScriptBlockExpressionAst]},$true)
$PolicyFn=$Worker.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq 'Test-AOVersionSatisfied'},$true)
. ([scriptblock]::Create($PolicyFn.Extent.Text))
$VersionMatchPolicy='Exact'
if(Test-AOVersionSatisfied '3.0' '2.0'){throw 'Worker accepted newer version in Exact mode.'}
if(-not(Test-AOVersionSatisfied '2.0.0' '2.0')){throw 'Equivalent numeric versions not accepted.'}
$VersionMatchPolicy='AtLeast'
if(-not(Test-AOVersionSatisfied '3.0' '2.0')){throw 'Legacy AtLeast behavior changed.'}
Write-Output 'PASS: Exact and AtLeast policies agree in worker and report classification.'
