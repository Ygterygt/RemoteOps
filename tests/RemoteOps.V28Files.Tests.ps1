$ErrorActionPreference='Stop';$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Verification.ps1')
function Assert($Value,$Message){if(-not $Value){throw $Message}}
if(-not(Get-Command Get-RemoteOpsPushManifest -ErrorAction SilentlyContinue)){throw 'FAIL: push content verification is missing'}
$Temp=Join-Path $env:TEMP ('V28-Files-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory (Join-Path $Temp 'source\tree\empty') -Force|Out-Null
New-Item -ItemType Directory (Join-Path $Temp 'remote') -Force|Out-Null
[IO.File]::WriteAllText((Join-Path $Temp 'source\tree\a.txt'),'before')
$script:Remote=Join-Path $Temp 'remote'
function ConvertTo-AORemoteAdminPath {param($ComputerName,$LocalPath) if($ComputerName -cne 'SIM-PC1'){throw 'live target rejected'};$script:Remote}
$V=@{LocalPath=(Join-Path $Temp 'source\tree');Path='C:\Fixture';Overwrite=$true}
$M=Get-RemoteOpsPushManifest $V.LocalPath
Copy-Item -LiteralPath $V.LocalPath -Destination $script:Remote -Recurse
$R=[pscustomobject]@{Durum='Success';AtlananAdet=0}
Set-RemoteOpsPostVerification FilePush $V @($R) SIM-PC1 -PushManifest $M
Assert ($R.VerificationStatus -ceq 'Verified') 'Folder contents and empty directory not verified'
[IO.File]::WriteAllText((Join-Path $script:Remote 'tree\a.txt'),'after!')
Set-RemoteOpsPostVerification FilePush $V @($R) SIM-PC1 -PushManifest $M
Assert ($R.VerificationStatus -ceq 'Failed') 'Same-length corrupt destination accepted'
[IO.File]::WriteAllText((Join-Path $script:Remote 'tree\a.txt'),'before')
Remove-Item -LiteralPath (Join-Path $script:Remote 'tree\empty') -Force
Set-RemoteOpsPostVerification FilePush $V @($R) SIM-PC1 -PushManifest $M
Assert ($R.VerificationStatus -ceq 'Failed') 'Missing empty directory accepted'
[IO.File]::WriteAllText((Join-Path $Temp 'source\tree\a.txt'),'changed')
Set-RemoteOpsPostVerification FilePush $V @($R) SIM-PC1 -PushManifest $M
Assert ($R.VerificationStatus -ceq 'Unknown') 'Changed source was verified against new content'
$V.LocalPath=Join-Path $Temp 'source\tree\a.txt';$M=Get-RemoteOpsPushManifest $V.LocalPath
Copy-Item -LiteralPath $V.LocalPath -Destination $script:Remote -Force
Set-RemoteOpsPostVerification FilePush $V @($R) SIM-PC1 -PushManifest $M
Assert ($R.VerificationStatus -ceq 'Verified') 'Single file verification failed'
$R.AtlananAdet=1
Set-RemoteOpsPostVerification FilePush $V @($R) SIM-PC1
Assert ($R.VerificationStatus -ceq 'NotPerformed') 'Skipped overwrite became verified'
$R.AtlananAdet=0
Set-RemoteOpsPostVerification FilePush $V @($R) SIM-PC1
Assert ($R.VerificationStatus -ceq 'Unknown') 'Missing baseline became verified'
$V.LocalPath=Join-Path $Temp 'source\tree\*.txt';$M=Get-RemoteOpsPushManifest $V.LocalPath
Assert (@($M.Items).Count -eq 1) 'Wildcard source scope incorrect'
Write-Output 'PASS local file/tree SHA256 readback; empty directories; corruption; source change; skipped overwrite; missing baseline; wildcard'

$Junction=Join-Path $Temp 'remote-link';New-Item -ItemType Junction -Path $Junction -Target $script:Remote|Out-Null
$script:Remote=$Junction;$V.LocalPath=Join-Path $Temp 'source\tree\a.txt';$M=Get-RemoteOpsPushManifest $V.LocalPath
Set-RemoteOpsPostVerification FilePush $V @($R) SIM-PC1 -PushManifest $M
Assert ($R.VerificationStatus -ceq 'Unknown') 'Destination junction root was followed and verified'
$Junction=Join-Path $Temp 'source-link';New-Item -ItemType Junction -Path $Junction -Target (Join-Path $Temp 'source')|Out-Null
$Rejected=$false;try{Get-RemoteOpsPushManifest (Join-Path $Junction 'tree\a.txt')|Out-Null}catch{$Rejected=$true}
Assert $Rejected 'Source junction ancestor was followed'
