[CmdletBinding()]param([Parameter(Mandatory)][string]$EvidenceRoot)
$ErrorActionPreference='Stop'
function Require($Value,$Message){if(-not $Value){throw $Message}}
function Assert-Chain($Model,$Rows){
 $mutations=@($Model.Events|Where-Object{$_.Operation -in @('StartService','StopService','ChangeStartMode') -and -not $_.Error})
 Require (($mutations.Operation -join ',') -ceq 'StartService,StopService,ChangeStartMode') 'Chain mutation order differs.'
 Require (@($mutations|Where-Object Target -cne 'SIM-PC1').Count -eq 0) 'Chain mutated wrong target.'
 Require ($Model.Targets.'SIM-PC1'.Service.State -ceq 'Stopped' -and $Model.Targets.'SIM-PC1'.Service.Startup -ceq 'Manual') 'Chain final state differs.'
 $list=@($Rows|Where-Object{$_.Operation -ceq 'ServiceList' -and $_.Status -ceq 'Success'})
 Require ($list.Count -eq 1 -and $list[0].State -ceq 'Stopped' -and $list[0].StartMode -ceq 'Manual') 'Chain report contradicts final state.'
 $events=@($Model.Events);$start=-1;$later=-1;$stop=-1
 for($i=0;$i -lt $events.Count;$i++){if($events[$i].Operation -ceq 'StartService'){$start=$i};if($events[$i].Operation -ceq 'Probe' -and $events[$i].Before.Service.State -ceq 'Running'){$later=$i};if($events[$i].Operation -ceq 'StopService'){$stop=$i}}
 Require ($start -ge 0 -and $later -gt $start -and $stop -gt $later) 'No running-state probe between start and stop.'
}
$summary=Get-Content (Join-Path $EvidenceRoot 'summary.json') -Raw|ConvertFrom-Json
Require ($summary.Failed -eq 0 -and $summary.UnexpectedBoundaryBlocks -eq 0) 'Acceptance summary failed.'
$checked=0
foreach($run in $summary.Runs){
 $folder=Join-Path $EvidenceRoot $run.Case
 $model=Get-Content (Join-Path $folder 'after.json') -Raw|ConvertFrom-Json
 $rows=@(Import-Csv (Join-Path $folder 'report/Results.csv') -Delimiter ';')
 $ledger=@(Import-Csv (Join-Path $folder 'ledger.csv') -Delimiter ';')
 $states=@(Get-ChildItem (Join-Path $folder 'report/state') -Filter '*.target.json'|ForEach-Object{Get-Content $_.FullName -Raw|ConvertFrom-Json})
 Require ($states.Count -eq $ledger.Count) 'Checkpoint/ledger target counts differ.'
 foreach($entry in $ledger){$state=@($states|Where-Object ComputerName -ceq $entry.ComputerName);Require ($state.Count -eq 1 -and $state[0].Terminal) 'Terminal checkpoint missing.';Require (@($rows|Where-Object ComputerName -ceq $entry.ComputerName).Count -gt 0) 'Target missing CSV rows.'}
 if($run.Case -ceq '01-stateful-chain'){
  Assert-Chain $model $rows
  $badState=$model|ConvertTo-Json -Depth 50|ConvertFrom-Json;$badState.Targets.'SIM-PC1'.Service.State='Running'
  $badTarget=$model|ConvertTo-Json -Depth 50|ConvertFrom-Json;($badTarget.Events|Where-Object Operation -ceq 'StartService')[0].Target='SIM-PC2'
  $caught=0;foreach($bad in @($badState,$badTarget)){try{Assert-Chain $bad $rows}catch{$caught++}}
  Require ($caught -eq 2) 'Real evidence negative controls escaped checker.'
 }
 if($run.Case -ceq '10-restart'){
  $events=@($model.Events);$stop=-1;$start=-1;$observed=$false
  for($i=0;$i -lt $events.Count;$i++){if($events[$i].Operation -ceq 'StopService'){$stop=$i};if($events[$i].Operation -ceq 'StartService'){$start=$i}}
  for($i=$stop+1;$i -lt $start;$i++){if($events[$i].Operation -ceq 'GetService' -and $events[$i].Before.Service.State -ceq 'Stopped' -and $events[$i].Target -ceq 'SIM-PC1'){$observed=$true}}
  Require ($stop -ge 0 -and $start -gt $stop -and $observed) 'Restart did not observe stopped service between stop and start.'
 }
 foreach($row in @($rows|Where-Object{$_.Operation -in @('ServiceControl','ServiceStartup') -and $_.Status -ceq 'Success'})){
  Require ($row.CommandStatus -ceq 'Success' -and $row.VerificationStatus -in @('Verified','Failed','Unknown')) 'Accepted mutation lacks verification record.'
  Require (-not [string]::IsNullOrWhiteSpace($row.VerifiedAt)) 'Verification timestamp missing.'
  if($row.VerificationStatus -ceq 'Verified'){
   $expectedState=if($row.Action -ieq 'stop'){'Stopped'}else{'Running'}
   if($row.Operation -ceq 'ServiceControl'){
    Require (@($model.Events|Where-Object{$_.Operation -ceq 'Verify' -and $_.Target -ceq $row.ComputerName -and $_.Before.Service.Exists -and $_.Before.Service.State -ceq $expectedState -and -not $_.Error}).Count -gt 0) 'Verified service lacks independent observed-state event.'
   }else{
    $mode=switch([string]$row.NewStartMode){auto{'Automatic'}demand{'Manual'}disabled{'Disabled'}default{$row.NewStartMode}}
    Require (@($model.Events|Where-Object{$_.Operation -ceq 'Verify' -and $_.Target -ceq $row.ComputerName -and $_.Before.Service.Startup -ceq $mode -and -not $_.Error}).Count -gt 0) 'Verified startup lacks independent event.'
   }
  }else{
   Require (@($ledger|Where-Object{$_.ComputerName -ceq $row.ComputerName -and $_.Outcome -in @('Error','Indeterminate')}).Count -eq 1) 'Verification failure painted completed in ledger.'
  }
 }
 if($run.Case -ceq '14-oracle-negative-controls'){
  Require (@($rows|Where-Object VerificationStatus -ceq 'Failed').Count -eq 1 -and @($rows|Where-Object Status -ceq 'NotRun').Count -eq 1) 'No-op acceptance did not persist failed verification and stopped successor.'
 }
 $checked++
}
[pscustomobject]@{Status='PASS';RunArtifactsChecked=$checked;ChainNegativeControls=2;EvidenceRoot=$EvidenceRoot}|ConvertTo-Json
