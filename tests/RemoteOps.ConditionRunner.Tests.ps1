$ErrorActionPreference='Stop'
$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'RemoteOps.App\RemoteOps.RecipeExecution.ps1')
function Assert($C,$M){if(-not $C){throw $M}}
$Base=Join-Path $env:TEMP ('ConditionRunner-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $Base|Out-Null
$Fixture=Join-Path $Base 'fixture';New-Item -ItemType Directory $Fixture|Out-Null
Copy-Item (Join-Path $Root 'RemoteOps.App') $Fixture -Recurse;Copy-Item (Join-Path $Root 'Modules') $Fixture -Recurse
$Data=Join-Path $Base 'data';$MutationLog=Join-Path $Base 'mutations.txt'
$Runner=Join-Path $Fixture 'RemoteOps.App\RemoteOps.Runner.ps1';$Source=[IO.File]::ReadAllText($Runner)
$Source=$Source.Replace('$BasePath = ''C:\Temp\YD_RemoteOps.App''',('$BasePath = '''+$Data+''''))
$Mocks=@'
    function Read-RemoteOpsConditionProbe {
        param($Check,$ComputerName)
        if($ComputerName -eq 'PC3' -and $Check.Kind -eq 'Service'){throw 'Fixture denied'}
        [pscustomobject]@{Exists=$true;ValueType='';Value='';State=$(if($ComputerName -eq 'PC1'){'Running'}else{'Stopped'});Startup='Automatic';Detail='Fixture read only'}
    }
    function Test-RemoteOpsOperationAccess {param($ComputerName,$Operation,$InputValues) [pscustomobject]@{Status='Success';Detail='Fixture'}}
    function New-CimSessionOption {param($Protocol)}
    function New-CimSession {param($ComputerName,$SessionOption,$OperationTimeoutSec) [pscustomobject]@{ComputerName=$ComputerName}}
    function Remove-CimSession {param($CimSession)}
    function Get-CimInstance {param($CimSession,$ClassName,$Filter,$Namespace) [pscustomobject]@{Name='Spooler';DisplayName='Spooler';State='Running';StartMode='Auto'}}
    function Invoke-CimMethod {param($CimSession,$InputObject,$MethodName,$Arguments) Add-Content -LiteralPath '__MUTATION_LOG__' ($CimSession.ComputerName+'|'+$MethodName);[pscustomobject]@{ReturnValue=0}}
'@
$Source=$Source.Replace("    if(`$OperationName -ceq 'RecipeCondition'){",$Mocks.Replace('__MUTATION_LOG__',$MutationLog)+"`r`n    if(`$OperationName -ceq 'RecipeCondition'){")
[IO.File]::WriteAllText($Runner,$Source,(New-Object Text.UTF8Encoding $true))
$D=New-RemoteOpsRecipeDefinition 'Fixture condition';$D.Schema='RemoteOps.Recipe/2';$D.Revision=1
$C=[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Stopped';Operation='RecipeCondition';Values=(New-RemoteOpsConditionValues)}
$D.Steps=@($C,[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Start';Operation='ServiceControl';ConditionId=$C.Id;Values=@{ServiceName='Spooler';Action='Start'}})
$Profile=[pscustomobject]@{Domain='TEST';UserName='operator';IsMain=$true}
function Invoke-Fixture($D,$Targets,$Id){
 $S=New-RemoteOpsRecipeRunSnapshot $D $Targets $Profile $false;$RunRoot=Get-RemoteOpsRecipeRunRoot $Data $Id
 $R=[pscustomobject]@{Operation='RecipeRun';Category='Recipes';RecipeRunId=$Id;Targets=$S.Targets;Domain='TEST';UserName='operator';IsMain=$true;Parallelism=1;ProgressPath='';CancelPath=(Join-Path $RunRoot 'cancel.json');CheckpointRoot=(Join-Path $RunRoot 'state');Values=@{Snapshot=$S;Confirm='RECETE'}}
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Runner -RequestBase64 (ConvertTo-RemoteOpsRecipeRequestBase64 $R) *> (Join-Path $Base ($Id+'.log'))
 if($LASTEXITCODE -ne 0){Get-Content (Join-Path $Base ($Id+'.log')) -Tail 15;throw 'Condition coordinator failed'}
 @(Import-Csv (Join-Path $RunRoot 'Results.csv') -Delimiter ';')
}
$Rows=@(Invoke-Fixture $D @('PC1','PC2','PC3') 'GUI-20261015-120010-ABCDEF')
Assert ((Get-Content $MutationLog -Raw).Trim() -eq 'PC2|StartService') 'Conditional worker mutated wrong target'
Assert (@($Rows|Where-Object {$_.ComputerName -eq 'PC1' -and $_.Status -eq 'Skipped'}).Count -eq 1) 'False skip evidence missing'
Assert (@($Rows|Where-Object {$_.ComputerName -eq 'PC3' -and $_.Status -eq 'Error'}).Count -ge 1) 'Probe error evidence missing'
$C.Values.Match='Any';$C.Values.Checks=@([pscustomobject]@{Kind='RegistryKey';Path='HKLM\SOFTWARE';Name='';Operator='Exists';ExpectedType='';Expected=''},$C.Values.Checks[0])
$Rows=@(Invoke-Fixture $D @('PC3') 'GUI-20261015-120011-ABCDEF')
Assert ((Get-Content $MutationLog -Raw).Trim() -eq 'PC2|StartService') 'Any true bypassed probe error'
Assert (@($Rows|Where-Object Status -eq NotRun).Count -eq 1) 'Any error did not stop bound action'
$Standalone=[pscustomobject]@{Operation='RecipeCondition';Category='Recipes';Domain='TEST';UserName='operator';IsMain=$true;Targets=@('PC1');Values=$C.Values;ProgressPath=''}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Runner -RequestBase64 (ConvertTo-RemoteOpsRecipeRequestBase64 $Standalone) *> (Join-Path $Base 'standalone.log')
Assert ($LASTEXITCODE -ne 0) 'Standalone condition request allowed'
Write-Output 'PASS real isolated condition child workers, per-target skip, errors, Any error dominance and recipe-only dispatch; no remote endpoints'
