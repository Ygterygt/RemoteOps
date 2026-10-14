$ErrorActionPreference='Stop';Set-StrictMode -Version 2
Add-Type -AssemblyName PresentationFramework
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'Modules\FileOperations.ps1')
$t=$null;$e=$null;$Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'),[ref]$t,[ref]$e)
foreach($Name in 'Get-OptionalPropertyValue','Get-RemoteOpsRunLogInfo','Open-RemoteOpsLogFolder'){
 $F=$Ast.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq $Name},$true)
 if($F){. ([scriptblock]::Create($F.Extent.Text))}
}
$Temp=Join-Path $env:TEMP ('RemoteOpsLogNav-'+[guid]::NewGuid().ToString('N'))
try{
 $script:DataRoot=$Temp;$Remote=Join-Path $Temp 'remote';New-Item -ItemType Directory -Path $Remote -Force|Out-Null
 Set-Content (Join-Path $Remote 'example.log') 'fixture'
 function ConvertTo-AORemoteAdminPath {param($ComputerName,$LocalPath)return $Remote}
 $A=Get-AORecentLogs -ComputerName YIGIT1 -BasePath $Temp -OperationName Package_Install -OperationID STEP1 -CollectionGroup GUI-RUN1
 $B=Get-AORecentLogs -ComputerName YIGIT1 -BasePath $Temp -OperationName Package_Install -OperationID STEP1 -CollectionGroup GUI-RUN2
 if($A.Status -ne 'Success' -or $B.Status -ne 'Success' -or $A.Destination -eq $B.Destination -or $A.Destination -notlike '*\GUI-RUN1\YIGIT1\*'){throw 'Collected logs are not isolated by run and target.'}
 $Run=[pscustomobject]@{ProgressPath=(Join-Path $Temp 'progress')}
 $ReportRoot=Join-Path $Temp 'Logs\Operations\PackageDeployment\GUI-RUN1';New-Item -ItemType Directory -Path $ReportRoot -Force|Out-Null
 [IO.File]::WriteAllText(($Run.ProgressPath+'.reportroot'),$ReportRoot)
 $Info=Get-RemoteOpsRunLogInfo $Run YIGIT1 'Success'
 if(-not $Info.CanOpen -or $Info.Path -ne (Join-Path $Temp 'PulledLogs\GUI-RUN1\YIGIT1')){throw 'Client shortcut does not resolve to selected run/target.'}
 $Info=Get-RemoteOpsRunLogInfo $Run PC2 'Failed'
 if($Info.CanOpen -or $Info.Status -notmatch 'basarisiz'){throw 'Failed collection offered a shortcut.'}
 $Partial=Get-RemoteOpsRunLogInfo $Run YIGIT1 'Failed'
 if(-not $Partial.CanOpen -or $Partial.Status -notmatch 'Kismi'){throw 'Partial collected files must remain accessible with a failure label.'}
 New-Item -ItemType Directory -Path (Join-Path $Temp 'PulledLogs\GUI-RUN1\PC3') -Force|Out-Null
 $Empty=Get-RemoteOpsRunLogInfo $Run PC3 'NoRecentLogs'
 if($Empty.CanOpen -or $Empty.Status -ne 'Log bulunamadi'){throw 'Empty collection must not offer a log shortcut.'}
 $Info=Get-RemoteOpsRunLogInfo $Run '' ''
 if(-not $Info.CanOpen -or $Info.Path -ne (Join-Path $Temp 'PulledLogs\GUI-RUN1')){throw 'Run shortcut does not isolate selected run.'}
 if((Get-RemoteOpsRunLogInfo $Run '..' '').CanOpen){throw 'Traversal accepted.'}
 [IO.File]::WriteAllText(($Run.ProgressPath+'.reportroot'),$Temp)
 if((Get-RemoteOpsRunLogInfo $Run YIGIT1 '').CanOpen){throw 'Invalid report root accepted.'}
 Write-Output 'PASS: collected files isolated by run and client, shortcuts select exact folders, missing/failed paths disabled.'
}finally{if(Test-Path $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force}}
