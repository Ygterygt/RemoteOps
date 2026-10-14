$ErrorActionPreference='Stop';Set-StrictMode -Version 2
Add-Type -AssemblyName PresentationFramework
$Root=Split-Path -Parent $PSScriptRoot
$t=$null;$e=$null;$Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'),[ref]$t,[ref]$e)
foreach($Name in 'T','Get-OptionalPropertyValue','Get-RemoteOpsOperationExample','Get-RemoteOpsPulledFileInfo'){$F=$Ast.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq $Name},$true);if($F){. ([scriptblock]::Create($F.Extent.Text))}}
foreach($Pair in @(@('FilePull','Path'),@('RegistryEdit','RegistryPath'),@('ScheduledTaskAction','TaskName'),@('ServiceControl','ServiceName'),@('ProcessKill','ProcessFilter'))){
 $Hint=Get-RemoteOpsOperationExample ([pscustomobject]@{Name=$Pair[0]}) ([pscustomobject]@{Key=$Pair[1]})
 if([string]::IsNullOrWhiteSpace($Hint)){throw "Missing example $($Pair -join '/')"}
}
$Temp=Join-Path $env:TEMP ('ROPulledUi-'+[guid]::NewGuid().ToString('N'))
try{
 $script:DataRoot=$Temp
 foreach($RunId in 'GUI-RUN1','GUI-RUN2'){$Dir=Join-Path $Temp ('PulledFiles\'+$RunId+'\YIGIT1');New-Item -ItemType Directory -Path $Dir -Force|Out-Null;Set-Content (Join-Path $Dir 'example.txt') $RunId}
 $Run=[pscustomobject]@{ProgressPath=(Join-Path $Temp 'one.progress')}
 $ReportRoot=Join-Path $Temp 'Logs\Operations\FilePull\GUI-RUN1';New-Item -ItemType Directory -Path $ReportRoot -Force|Out-Null
 [IO.File]::WriteAllText(($Run.ProgressPath+'.reportroot'),$ReportRoot)
 $Info=Get-RemoteOpsPulledFileInfo $Run YIGIT1
 if(-not $Info.CanOpen -or $Info.Path -notlike '*\GUI-RUN1\YIGIT1\example.txt'){throw 'Pulled-file shortcut is not scoped to exact run/client/file.'}
 if((Get-RemoteOpsPulledFileInfo $Run PC2).CanOpen){throw 'Missing client file offers a shortcut.'}
 if((Get-RemoteOpsPulledFileInfo $Run '..').CanOpen){throw 'Unsafe client path accepted.'}
 Write-Output 'PASS: operation examples and pulled-file shortcut isolate run/client, missing paths disabled.'
}finally{if(Test-Path $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force}}
