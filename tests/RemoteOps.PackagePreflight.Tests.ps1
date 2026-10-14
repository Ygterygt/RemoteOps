$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot;$t=$null;$e=$null
$Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'),[ref]$t,[ref]$e)
$Start=$Ast.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq 'Start-RemoteOpsRequest'},$true)
$Branch=@($Start.FindAll({param($N)$N -is [Management.Automation.Language.IfStatementAst] -and $N.Extent.Text -like '*$PsExecCommand=Get-Command*' -and $N.Extent.Text -like '*$Operation.Name*'},$true)|Sort-Object {$_.Extent.Text.Length}|Select-Object -First 1)[0]
if(-not $Branch){throw 'Preflight source selection branch not found.'}
$Temp=Join-Path $env:TEMP ('ROPreflight-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path $Temp -Force|Out-Null;Set-Content (Join-Path $Temp 'PsExec.exe') 'local';Set-Content (Join-Path $Temp 'global.exe') 'global'
    function Get-Command {param($Name,$ErrorAction)return [PSCustomObject]@{Source=(Join-Path $Temp 'global.exe')}}
    $ProjectRoot=$Temp;$Operation=[PSCustomObject]@{Name='PackageDeployment'};$PsExecPath=''
    Invoke-Expression $Branch.Extent.Text
    if($PsExecPath -ne (Join-Path $Temp 'PsExec.exe')){throw 'Saved deployment preflight did not resolve the same local PsExec as runtime.'}
    $Operation.Name='PackageTrigger';$PsExecPath='';Invoke-Expression $Branch.Extent.Text
    if($PsExecPath -ne (Join-Path $Temp 'global.exe')){throw 'Legacy package preflight PATH preference changed.'}
    Write-Output 'PASS: saved and legacy package preflight select readable PsExec paths consistently with runtime.'
}finally{if(Test-Path $Temp){Remove-Item $Temp -Recurse -Force}}
