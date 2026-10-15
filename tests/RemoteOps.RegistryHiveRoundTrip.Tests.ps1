$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$Root=Split-Path -Parent $PSScriptRoot
function Register-AOModule {param($Name,$Version,$MinimumHostApiVersion,$SourcePath)}
function Register-AOModuleOperation {param($ModuleName,$Name,$DisplayName,$EntryPointName,$Handler)}
. (Join-Path $Root 'Modules\RegistryOperations.ps1')
$script:Calls=@();$script:Sid='S-1-5-21-100'
$script:Answers=New-Object 'System.Collections.Generic.Queue[string]'
function Read-Host {param($Prompt)if(-not $script:Answers.Count){throw "Unexpected prompt $Prompt"};$script:Answers.Dequeue()}
function Write-Host {param([Parameter(Position=0)]$Object,$ForegroundColor)}
function New-CimSession {param($ComputerName,$SessionOption,$OperationTimeoutSec)'fixture'}
function New-CimSessionOption {param($Protocol)}
function Remove-CimSession {param($CimSession)}
function Get-CimInstance {param($CimSession,$ClassName,$Filter)[pscustomobject]@{LogonId='123'}}
function Get-CimAssociatedInstance {param($CimSession,$InputObject,$Association,$ResultClassName)[pscustomobject]@{SID=$script:Sid}}
function Invoke-CimMethod {
 param($CimSession,$Namespace,$ClassName,$MethodName,$Arguments)
 if($MethodName -eq 'EnumValues'){return [pscustomobject]@{ReturnValue=0;sNames=@('Mode');Types=@(1)}}
 $script:Calls+=[pscustomobject]@{Method=$MethodName;Hive=$Arguments.hDefKey;Key=$Arguments.sSubKeyName;Value=$(if($Arguments.ContainsKey('sValue')){$Arguments.sValue}else{''})}
 [pscustomobject]@{ReturnValue=0;sValue='old'}
}
function Write-ApplicationRows {param($Name,$Rows)$script:ResultRows=$Rows;return 'mock.csv'}
$t=$null;$e=$null;$Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.Runner.ps1'),[ref]$t,[ref]$e)
foreach($Name in 'New-TargetScopedManifest','Invoke-RegistryRollbackRequest'){
 $F=$Ast.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq $Name},$true);. ([scriptblock]::Create($F.Extent.Text))
}
$BasePath=Join-Path $env:TEMP ('RORegistryHive-'+[guid]::NewGuid().ToString('N'))
$Systems=@('PC1');$OperationID='RB'
try{
 $Index=0
 foreach($Case in @(@('HKLM\Software\T',[uint32]2147483650,'Software\T'),@('HKEY_LOCAL_MACHINE:\Software\T',[uint32]2147483650,'Software\T'),@('HKU\S-1-5-21-999\Software\T',[uint32]2147483651,'S-1-5-21-999\Software\T'),@('HKEY_USERS\S-1-5-21-999\Software\T',[uint32]2147483651,'S-1-5-21-999\Software\T'),@('HKCU\Software\T',[uint32]2147483651,'S-1-5-21-100\Software\T'))){
  foreach($Action in '1','2','3'){
   $Index++;$script:Calls=@();$script:Sid='S-1-5-21-100'
   foreach($Answer in @($Action,$Case[0],'Mode')){$script:Answers.Enqueue($Answer)}
   if($Action -eq '2'){$script:Answers.Enqueue('new');$script:Answers.Enqueue('EDIT')}
   if($Action -eq '3'){$script:Answers.Enqueue('DELETE')}
   $script:Answers.Enqueue('0')
   $Result=Invoke-RegistryOperationsMenu -BasePath $BasePath -Systems $Systems -ReachableSystems $Systems -UnreachableSystems @() -OperationID "OP$Index" -OperationDate test -OperationTime test
   $Calls=@($script:Calls|Where-Object{$_.Method -ne 'EnumKey'})
   if(@($Result.Rows|Where-Object{$_.Status -ne 'Success'}).Count -or -not $Calls.Count){throw 'Registry menu failed'}
   foreach($Call in $Calls){if($Call.Hive -ne $Case[1] -or $Call.Key -ne $Case[2]){throw "Wrong hive/key for $($Case[0]) action $Action"}}
   if($Action -ne '1'){
    $Manifest=Join-Path $BasePath ('RegistryRollback\OP'+$Index+'_'+$(if($Action -eq '2'){'Edit'}else{'Delete'})+'.csv')
    $script:Calls=@();$script:Sid='S-1-5-21-CHANGED'
    Invoke-RegistryRollbackRequest ([pscustomobject]@{ManifestPath=$Manifest})|Out-Null
    if($script:Calls.Count -ne 1 -or $script:Calls[0].Hive -ne $Case[1] -or $script:Calls[0].Key -ne $Case[2] -or $script:Calls[0].Value -ne 'old' -or $script:ResultRows[0].Status -ne 'Success'){throw 'Runner rollback must restore recorded hive and SID, not current user'}
   }
  }
 }
 Write-Output 'PASS: 15 mocked read/edit/delete operations across registry roots; runner rollback restores the recorded hive and pinned user SID.'
}finally{if((Split-Path $BasePath -Parent) -ne $env:TEMP){throw 'Unsafe cleanup'};if(Test-Path -LiteralPath $BasePath){Remove-Item -LiteralPath $BasePath -Recurse -Force}}
