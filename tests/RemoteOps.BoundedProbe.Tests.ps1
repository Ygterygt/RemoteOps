$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Deployment.ps1')
foreach($Code in @(10051,10064,10065)){
 $script:SocketCode=$Code
 $R=Test-RemoteOpsTargetAccess PC1 -Connect {throw (New-Object Net.Sockets.SocketException $script:SocketCode)}
 if($R.Status -ne 'Unreachable'){throw "Offline socket $Code must be Unreachable"}
}
$Marker=Join-Path $env:TEMP ('RemoteOpsProbe-'+[guid]::NewGuid().ToString('N')+'.txt')
try{
 $Probe="[IO.File]::WriteAllText('"+$Marker.Replace("'","''")+"',[string]`$PID);Start-Sleep -Seconds 20"
 $Watch=[Diagnostics.Stopwatch]::StartNew();$TimedOut=$false
 try{Invoke-RemoteOpsBoundedProbe -ScriptText $Probe -TimeoutSeconds 2|Out-Null}catch{$TimedOut=$_.Exception.ToString() -match 'timed out'}
 if(-not $TimedOut -or $Watch.Elapsed.TotalSeconds -gt 8){throw 'Whole SMB probe must have a bounded timeout'}
 $ChildId=[int](Get-Content -LiteralPath $Marker -Raw)
 if(Get-Process -Id $ChildId -ErrorAction SilentlyContinue){throw 'Timed-out probe child leaked'}
}finally{if(Test-Path -LiteralPath $Marker){Remove-Item -LiteralPath $Marker -Force}}
Write-Output 'PASS: offline socket codes are neutral; whole read-only probe timeout terminates its child.'
