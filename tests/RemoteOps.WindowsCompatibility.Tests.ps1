$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'Modules\FileOperations.ps1')
$Previous=[Threading.Thread]::CurrentThread.CurrentCulture
try{
 [Threading.Thread]::CurrentThread.CurrentCulture=New-Object Globalization.CultureInfo tr-TR
 $Path=Get-AOFilePullRoot 'C:\Temp\fixture' 'GUI-LIVE-ISTANBUL'
 if($Path -notlike '*GUI-LIVE-ISTANBUL'){throw 'ASCII I rejected in a real GUI run ID.'}
 if(-not(Test-AOLogCleanupUserName 'YIGIT2026').Valid){throw 'ASCII I rejected in cleanup account.'}
}finally{[Threading.Thread]::CurrentThread.CurrentCulture=$Previous}
$t=$null;$e=$null;$Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.Runner.ps1'),[ref]$t,[ref]$e)
$F=$Ast.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq 'Invoke-ScheduledTaskActionRequest'},$true)
$Calls=@($F.FindAll({param($N)$N -is [Management.Automation.Language.CommandAst] -and $N.GetCommandName() -eq 'Unregister-ScheduledTask'},$true))
foreach($Call in $Calls){if(@($Call.CommandElements|Where-Object{$_ -is [Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'Confirm'}).Count){throw 'DCOM task deletion explicitly binds unsupported Confirm parameter.'}}
Write-Output 'PASS: Turkish culture permits ASCII I in GUI paths/account names; DCOM task deletion avoids unsupported Confirm binding.'
