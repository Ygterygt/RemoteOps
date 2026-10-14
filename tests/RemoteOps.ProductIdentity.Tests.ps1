$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot;$T=$null;$E=$null
$Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'Modules\ApplicationWorkers.ps1'),[ref]$T,[ref]$E)
$Assignment=$Ast.Find({param($N)$N -is [Management.Automation.Language.AssignmentStatementAst] -and $N.Left.Extent.Text -eq '$RegistryCheckScript'},$true)
$Block=$Assignment.Right.Find({param($N)$N -is [Management.Automation.Language.ScriptBlockExpressionAst]},$true).ScriptBlock
# Execute the actual detection body with registry reads and transport replaced by fixtures.
$Source=$Block.Extent.Text
foreach($Name in @('Invoke-StdRegEnumKey','Invoke-StdRegGetString')){
    $F=$Block.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq $Name},$true)
    $Source=$Source.Replace($F.Extent.Text,'')
}
$Source=[regex]::Replace($Source,'(?s)\$ConnectionOptions = .*?\$FoundDisplayName    =','$FoundDisplayName    =')
$Source=$Source.Substring(1,$Source.Length-2)
function Invoke-StdRegEnumKey{param($RegClass,$Hive,$SubKeyName,$MethodOptions)[PSCustomObject]@{Exists=$true;SubKeys=$(if($SubKeyName -match 'WOW6432Node'){@()}else{@('FirstApp','SecondApp')})}}
function Invoke-StdRegGetString{param($RegClass,$Hive,$SubKeyName,$ValueName,$MethodOptions)switch($ValueName){ProductID{'DUPLICATE-PRODUCT'}DisplayName{$SubKeyName.Split('\')[-1]}DisplayVersion{'3.0'}Publisher{'Vendor'}}}
$RegClass=$null;$MethodOptions=$null
$Result=& ([scriptblock]::Create($Source)) 'LOCAL-FAKE' ProductID DUPLICATE-PRODUCT 1
if($Result.Status -ne 'CokluEslesme' -or @($Result.Applications).Count -ne 2){throw 'Duplicate ProductID was silently treated as one installed application.'}
if(@($Result.Applications|Where-Object DisplayName -eq SecondApp).Count -ne 1){throw 'Exact-key selection cannot see the second valid ProductID candidate.'}
Write-Output 'PASS: ProductID scan enumerates all matches and reports ambiguity; later exact-key selection retains all candidates.'
