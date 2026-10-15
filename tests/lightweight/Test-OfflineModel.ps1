$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'New-OfflineRunnerFixture.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('RemoteOpsModel-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root|Out-Null
$statePath=Join-Path $root 'state.json'
@{Targets=@{'SIM-PC1'=@{Service=@{Exists=$true;Name='FixtureSvc';State='Stopped';Startup='Manual'};Registry=@{'HKLM\SOFTWARE\Fixture|Version'=@{Exists=$true;ValueType='REG_SZ';Value='2.0'}}}};Events=@()}|ConvertTo-Json -Depth 20|Set-Content $statePath -Encoding UTF8
$source=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$runner=New-RemoteOpsOfflineRunnerFixture $source (Join-Path $root 'fixture') (Join-Path $root 'data') $statePath
. (Join-Path $PSScriptRoot 'FixtureBoundary.ps1')
$s=New-CimSession -ComputerName SIM-PC1
$svc=Get-CimInstance -CimSession $s -ClassName Win32_Service -Filter "Name='FixtureSvc'"
if($svc.State -cne 'Stopped'){throw 'Initial state mismatch'}
$r=Invoke-CimMethod -CimSession $s -InputObject $svc -MethodName StartService -Arguments @{}
if($r.ReturnValue -ne 0 -or (Get-CimInstance -CimSession $s -ClassName Win32_Service).State -cne 'Running'){throw 'Transition not persisted'}
# Failure is persisted as evidence without changing service state.
$st=Get-Content $statePath -Raw|ConvertFrom-Json
$st.Targets.'SIM-PC1'|Add-Member NoteProperty MutationError 'Fixture mutation denied'
$st|ConvertTo-Json -Depth 30|Set-Content $statePath -Encoding UTF8
try{Invoke-CimMethod -CimSession $s -InputObject $svc -MethodName StopService -Arguments @{};throw 'Denied mutation escaped'}catch{if($_.Exception.Message -notlike '*Fixture mutation denied*'){throw}}
$st=Get-Content $statePath -Raw|ConvertFrom-Json
if($st.Targets.'SIM-PC1'.Service.State -cne 'Running' -or $st.Events[-1].Error -cne 'Fixture mutation denied'){throw 'Failure evidence mismatch'}
# A successful provider return is insufficient: the independent state oracle catches a no-op.
$st.Targets.'SIM-PC1'.MutationError=''
$st.Targets.'SIM-PC1'.Service.State='Stopped'
$st.Targets.'SIM-PC1'|Add-Member NoteProperty SuppressMutation $true
$st|ConvertTo-Json -Depth 30|Set-Content $statePath -Encoding UTF8
$noOp=Invoke-CimMethod -CimSession $s -InputObject $svc -MethodName StartService -Arguments @{}
$st=Get-Content $statePath -Raw|ConvertFrom-Json
if($noOp.ReturnValue -ne 0 -or $st.Targets.'SIM-PC1'.Service.State -cne 'Stopped'){throw 'No-op negative-control setup failed'}
$oracleRejected=($st.Targets.'SIM-PC1'.Service.State -cne 'Running')
if(-not $oracleRejected -or $st.Events[-1].Before.Service.State -cne $st.Events[-1].After.Service.State){throw 'No-op escaped independent state oracle'}
$checks=0
foreach($bad in @({New-CimSession -ComputerName REAL-PC},{Invoke-CimMethod -CimSession $s -InputObject $svc -MethodName Delete},{Test-Connection localhost},{Assert-OfflineRequest ([pscustomobject]@{Operation='ProcessKill';Targets=@('SIM-PC1')})},{Invoke-OfflineStartProcess -FilePath 'cmd.exe' -ArgumentList '/c echo unsafe'})){
 try{& $bad;throw 'Negative check escaped boundary'}catch{if($_.Exception.Message -notlike 'OFFLINE_BOUNDARY_BLOCKED:*'){throw};$checks++}
}
$state=Get-Content $statePath -Raw|ConvertFrom-Json
if(@($state.Events|Where-Object Operation -eq StartService).Count -ne 2 -or $checks -ne 5){throw 'Event/guard mismatch'}
if(@(Get-Content ($statePath+'.blocked.jsonl')).Count -ne 5){throw 'Guard log mismatch'}
[pscustomobject]@{Status='PASS';FixtureRoot=$root;Runner=$runner;Events=@($state.Events).Count;Blocked=$checks}|ConvertTo-Json


