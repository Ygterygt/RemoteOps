$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
$Tokens=$null;$ParseErrors=$null
$Ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.Runner.ps1'),[ref]$Tokens,[ref]$ParseErrors)
if($ParseErrors.Count){throw ($ParseErrors|Out-String)}
foreach($Name in @('Convert-ApplicationSearchMode','Invoke-RegistryCheckWorker','Invoke-ApplicationCheckRequest','Write-ApplicationRows')){
    $Definition=$Ast.Find({param($Node)$Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq $Name},$true)
    Set-Item -Path ('Function:'+$Name) -Value $Definition.Body.GetScriptBlock()
}
function Write-Host {param([Parameter(Position=0)][object[]]$Object,[object]$ForegroundColor)}
function Write-RemoteOpsLog {param($Level,$Message)}
$script:Match=@(
    [PSCustomObject]@{DisplayName='Microsoft Edge';DisplayVersion='1';ProductID='';ProductIDSource='';RegistryKey='SOFTWARE\A\Edge'},
    [PSCustomObject]@{DisplayName='Microsoft Edge WebView2';DisplayVersion='2';ProductID='';ProductIDSource='';RegistryKey='SOFTWARE\A\WebView2'})
function Get-HostScriptBlock {param($VariableName)return {param($ComputerName,$SearchMode,$SearchValue,$TimeoutSeconds,$SelectedApplication,$PackageOperation)[PSCustomObject]@{Status='CokluEslesme';Applications=$script:Match;DisplayName='';DisplayVersion='';ProductID='';ProductIDSource='';ErrorDetail=''}}}
$Temp=Join-Path $env:TEMP ('RemoteOpsAppCheck-'+[guid]::NewGuid().ToString('N'))
try{
    $BasePath=$Temp;$OperationID='APPCHECK-1';$Systems=@('PC1');$ReachableSystems=@('PC1')
    # several matches and no exact key: every match is listed (found), with a hint to pick a key
    $Result=Invoke-ApplicationCheckRequest -InputValues ([PSCustomObject]@{SearchType='DisplayName contains';SearchValue='Edge';RegistryKey=''})
    if(@($Result.Rows).Count -ne 2 -or @($Result.Rows|Where-Object Status -ne 'Var').Count -ne 0 -or $Result.Rows[0].RegistryKey -ne 'SOFTWARE\A\Edge' -or $Result.Rows[1].DisplayName -ne 'Microsoft Edge WebView2' -or $Result.Rows[0].ErrorDetail -notmatch '2 matches'){throw "Multiple matches must list every application: $($Result.Rows|Out-String)"}
    # exact key selects exactly one application
    $Result=Invoke-ApplicationCheckRequest -InputValues ([PSCustomObject]@{SearchType='DisplayName contains';SearchValue='Edge';RegistryKey='software\a\webview2'})
    if($Result.Rows[0].Status -ne 'Var' -or $Result.Rows[0].DisplayName -ne 'Microsoft Edge WebView2' -or $Result.Rows[0].DisplayVersion -ne '2'){throw "Exact key selection failed: $($Result.Rows[0]|Out-String)"}
    # key that matches nothing is still reported as ambiguous
    $Result=Invoke-ApplicationCheckRequest -InputValues ([PSCustomObject]@{SearchType='DisplayName contains';SearchValue='Edge';RegistryKey='SOFTWARE\Nope'})
    if(@($Result.Rows).Count -ne 2 -or @($Result.Rows|Where-Object Status -ne 'Ambiguous').Count -ne 0){throw 'Unknown key must list the matches as ambiguous.'}
    Write-Output 'PASS: application check with several matches (ambiguous, exact key, unknown key) under StrictMode.'
}
finally{if(Test-Path -LiteralPath $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue}}
