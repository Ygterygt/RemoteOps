$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.History.ps1')
$Module=Join-Path $Root 'RemoteOps.App\RemoteOps.Diagnostics.ps1';if(Test-Path $Module){. $Module}
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
$Sandbox=Join-Path $env:TEMP ('RemoteOpsDiagnostics-'+[guid]::NewGuid().ToString('N'))
try{
 $Folder=Join-Path $Sandbox 'Logs\Operations\PackageDeployment\RUN-A'
 New-Item -ItemType Directory -Path (Join-Path $Folder 'Workers') -Force|Out-Null
 $Run=[pscustomobject]@{OperationID='RUN-A';Operation='PackageDeployment';ReportRoot=$Folder;LedgerPath=''}
 $Cases=@(
 @('Success','0','','Success'),@('Indeterminate','','timeout','Indeterminate'),
 @('Unreachable','','RPC unavailable','Unreachable'),@('Error','5','Access denied','AccessDenied'),
 @('RebootRequired','3010','','RebootRequired'),@('Error','50010','unknown failure','Execution'),
 @('Error','','source inaccessible','Source'),@('Error','','version verification failed','Verification'))
 foreach($Case in $Cases){
  $Step=if($Case[3] -eq 'Verification'){'VerifyInstall'}elseif($Case[3] -eq 'Source'){'ValidateSource'}else{'Install'}
  $Row=[pscustomobject]@{ComputerName='PC1';Step=$Step;Status=$Case[0];ExitCode=$Case[1];ErrorDetail=$Case[2];OperationID='RUN-A';PreviousVersion='2';TargetVersion='3';FinalVersion='';PackageId='P1';PackageRevision='2'}
  $Detail=[pscustomobject]@{Targets=@([pscustomobject]@{ComputerName='PC1';Outcome=$Case[0];Detail=$Case[2]});Rows=@($Row);Artifacts=@();Issues=@()}
  $Diagnosis=Get-RemoteOpsDiagnosis $Run PC1 $Detail
  Assert ($Diagnosis.Category -eq $Case[3]) ('Wrong category: '+$Case[3])
  Assert ($Diagnosis.Rows.Count -eq 1 -and $Diagnosis.OperationID -eq 'RUN-A') 'Lost evidence identity'
  if($Case[1] -eq '50010'){Assert (($Diagnosis.Evidence -join ' ') -match '50010') 'Unknown exit code lost'}
 }
 $Detail.Targets[0].Outcome='Success';$Detail.Rows[0].Status='Success';$Detail.Rows[0].ExitCode='3010'
 $Diagnosis=Get-RemoteOpsDiagnosis $Run PC1 $Detail
 Assert ($Diagnosis.Outcome -eq 'Success' -and $Diagnosis.RebootRequired) 'Success reboot information lost'
 @([pscustomobject]@{ComputerName='PC1';Status='Error';ExitCode=50010})|Export-Csv (Join-Path $Folder 'Results.csv') -NoTypeInformation -Delimiter ';'
 'log evidence'|Set-Content (Join-Path $Folder 'RemoteOps.log')
 'worker evidence'|Set-Content (Join-Path $Folder 'Workers\0001.out.log')
 'secret'|Set-Content (Join-Path $Folder 'domains.json')
 @([pscustomobject]@{ComputerName='PC1';Status='Success';Salary='private'})|Export-Csv (Join-Path $Folder 'employee-export.csv') -NoTypeInformation -Delimiter ';'
 '<html>private</html>'|Set-Content (Join-Path $Folder 'employee-export.html')
 $Files=Get-RemoteOpsDiagnosticFiles $Sandbox $Run
 Assert ($Files.Files.Count -eq 3) 'Bundle allowlist failed'
 $Zip=Join-Path $Sandbox 'bundle.zip'
 $Bundle=Export-RemoteOpsDiagnosticBundle $Sandbox $Run $Files.Files $Zip
 Assert ($Bundle.EntryCount -eq 3 -and $Bundle.Bytes -gt 0) 'ZIP missing entries'
 $Archive=[IO.Compression.ZipFile]::OpenRead($Zip)
 try{Assert ($Archive.Entries.Count -eq 3 -and @($Archive.Entries|Where-Object FullName -eq 'domains.json').Count -eq 0) 'ZIP scope violated'}finally{$Archive.Dispose()}
 $Rejected=$false;try{Export-RemoteOpsDiagnosticBundle $Sandbox $Run $Files.Files $Zip|Out-Null}catch{$Rejected=$true};Assert $Rejected 'Existing ZIP overwritten'
 'changed evidence'|Add-Content (Join-Path $Folder 'RemoteOps.log')
 $Rejected=$false;try{Export-RemoteOpsDiagnosticBundle $Sandbox $Run $Files.Files (Join-Path $Sandbox 'changed.zip')|Out-Null}catch{$Rejected=$true};Assert $Rejected 'Changed preview source accepted'
 Assert (-not(Test-Path (Join-Path $Sandbox 'changed.zip'))) 'Failed export left partial ZIP'
 $Fake=@([pscustomobject]@{Path=(Join-Path $Folder 'domains.json');RelativePath='domains.json';Length=8;Hash='x'})
 $Rejected=$false;try{Export-RemoteOpsDiagnosticBundle $Sandbox $Run $Fake (Join-Path $Sandbox 'bad.zip')|Out-Null}catch{$Rejected=$true};Assert $Rejected 'Unapproved file allowed'
 $Outside=Join-Path $Sandbox 'outside';New-Item -ItemType Directory -Path $Outside|Out-Null
 $Junction=Join-Path $Folder 'link'
 New-Item -ItemType Junction -Path $Junction -Target $Outside|Out-Null
 try{$Rejected=$false;try{Resolve-RemoteOpsHistoryPath $Sandbox (Join-Path $Junction 'secret.log')|Out-Null}catch{$Rejected=$true};Assert $Rejected 'Junction accepted'}finally{[IO.Directory]::Delete($Junction)}
 Write-Output 'PASS: diagnosis evidence, unknown codes, reboot success, archive allowlist/roundtrip, changed source, overwrite, junction rejection.'
}finally{if(Test-Path $Sandbox){Remove-Item -LiteralPath $Sandbox -Recurse -Force}}
