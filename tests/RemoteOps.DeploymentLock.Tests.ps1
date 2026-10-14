$ErrorActionPreference='Stop';$Root=Split-Path -Parent $PSScriptRoot
$File=Join-Path $Root 'RemoteOps.App\RemoteOps.Deployment.ps1'
if(-not(Test-Path $File)){throw 'Deployment lock is missing.'};. $File
$Temp=Join-Path $env:TEMP ('RemoteOpsLocks-'+[guid]::NewGuid().ToString('N'));$A=$null;$B=$null
try{
    $A=Enter-RemoteOpsDeploymentLock $Temp PC1 'Example' RUN1
    $Script=Join-Path $Temp 'probe.ps1'
    @"
`$ErrorActionPreference='Stop'
. '$($File.Replace("'","''"))'
try {`$l=Enter-RemoteOpsDeploymentLock '$Temp' 'pc1' 'example' RUN2;Exit-RemoteOpsDeploymentLock `$l;exit 1} catch {exit 0}
"@|Set-Content -LiteralPath $Script -Encoding UTF8
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File $Script
    if($LASTEXITCODE -ne 0){throw 'Other process acquired active target lock.'}
    $B=Enter-RemoteOpsDeploymentLock $Temp PC2 Example RUN2;Exit-RemoteOpsDeploymentLock $B;$B=$null
    Exit-RemoteOpsDeploymentLock $A;$A=$null
    $B=Enter-RemoteOpsDeploymentLock $Temp PC1 Example RUN3
    Write-Output 'PASS: target locks exclude another process, isolate targets and release for the next run.'
}finally{if($A){Exit-RemoteOpsDeploymentLock $A};if($B){Exit-RemoteOpsDeploymentLock $B};if(Test-Path $Temp){Remove-Item $Temp -Recurse -Force}}
