[CmdletBinding()]
param([Parameter(Mandatory=$true)][switch]$RunLive,[switch]$CleanupOwnedRegistryParent,[string]$OutputDirectory=(Join-Path (Split-Path -Parent $PSScriptRoot) 'docs\live-test'))
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
if(-not $RunLive){throw 'Explicit -RunLive is required.'}
$Workspace=Split-Path -Parent $PSScriptRoot
$Admin=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
$Report=Join-Path $OutputDirectory 'LOCAL_LIVE_TEST.json'
if(-not $Admin){[pscustomobject]@{Admin=$false;Status='Blocked';Reason='Elevated Windows token is required for the owned HKLM/service/task fixtures.'}|ConvertTo-Json|Set-Content $Report -Encoding UTF8;throw 'Live fixture test requires administrator token.'}
$Token=[guid]::NewGuid().ToString('N');$Short=$Token.Substring(0,12)
$Sandbox=Join-Path $env:ProgramData ('YD_RemoteOps_LiveTest_'+$Token)
if(Test-Path -LiteralPath $Sandbox){throw 'Fixture collision.'}
$Fixtures=Join-Path $Sandbox 'fixtures';$Data=Join-Path $Sandbox 'data'
$ServiceName='YDRemoteOpsTest_'+$Short;$TaskFolder='YDRemoteOpsTest_'+$Short;$TaskPath='\'+$TaskFolder+'\';$TaskName='FixtureTask_'+$Short
$RegistryKey='SOFTWARE\YD_RemoteOps_LiveTest\'+$Token
$RegistryNative='Registry::HKEY_LOCAL_MACHINE\'+$RegistryKey
$Scheduler=$null;$OwnedTaskFolder=$false;$RegistryParentExisted=Test-Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\YD_RemoteOps_LiveTest'
$script:OwnedService=$false;$script:OwnedTask=$false;$script:OwnedRegistry=$false;$script:OwnedProcess=$null
$script:Cases=New-Object 'System.Collections.Generic.List[object]'
$script:Answers=New-Object 'System.Collections.Generic.Queue[string]';$script:LastHtml=''
function Read-Host {param($Prompt)if($script:Answers.Count -eq 0){throw "Unexpected live menu prompt: $Prompt"};$script:Answers.Dequeue()}
# Only report auto-opening is suppressed. All CIM/SMB/registry/task/service/process calls below are real.
function Start-Process {param($FilePath)$script:LastHtml=[string]$FilePath}
function Register-AOModule {param($Name,$Version,$MinimumHostApiVersion,$SourcePath,$Initializer)}
function Register-AOModuleOperation {param($ModuleName,$Name,$DisplayName,$EntryPointName,$Handler)}
foreach($Module in 'FileOperations','RegistryOperations','ServiceTaskOperations'){. (Join-Path $Workspace ('Modules\'+$Module+'.ps1'))}
$t=$null;$e=$null;$Ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Workspace 'RemoteOps.App\RemoteOps.Runner.ps1'),[ref]$t,[ref]$e)
foreach($Name in 'Invoke-ScheduledTaskActionRequest','Invoke-ServiceTaskRollbackRequest','New-TargetScopedManifest','Write-ApplicationRows'){
 $F=$Ast.Find({param($N)$N -is [Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq $Name},$true)
 if($F){. ([scriptblock]::Create($F.Extent.Text))}
}
$BasePath=$Data;$Systems=@($env:COMPUTERNAME);$ReachableSystems=$Systems;$UnreachableSystems=@();$OperationID=''
function Write-RemoteOpsLog {param($Level,$Message)Write-Host "$Level $Message"}
function New-LiveCommon([string]$Id){return @{BasePath=$Data;Systems=$Systems;ReachableSystems=$Systems;UnreachableSystems=[string[]]@();OperationID=$Id;OperationDate=(Get-Date -Format dd.MM.yyyy);OperationTime=(Get-Date -Format HH:mm:ss)}}
function Assert-Live([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Test-LiveCase([string]$Name,[scriptblock]$Body){
 $Watch=[Diagnostics.Stopwatch]::StartNew()
 try{& $Body|Out-Null;$Status='PASS';$Detail='Verified against real local fixture.'}catch{$Status='FAIL';$Detail=$_.Exception.Message+' | '+$_.ScriptStackTrace}
 $Watch.Stop();$script:Cases.Add([pscustomobject]@{Case=$Name;Status=$Status;Seconds=[math]::Round($Watch.Elapsed.TotalSeconds,2);Detail=$Detail})
 $script:Cases|ConvertTo-Json -Depth 5|Set-Content (Join-Path $OutputDirectory 'progress.json') -Encoding UTF8
 Write-Host "$Name : $Status | $Detail"
}
function Invoke-LiveMenu([string]$Module,[string]$Id,[string[]]$InputAnswers){
 $script:Answers.Clear();foreach($Answer in $InputAnswers){$script:Answers.Enqueue($Answer)};$script:LastHtml=''
 $Common=New-LiveCommon $Id
 $Result=switch($Module){File{Invoke-AOFileOperationsMenu @Common -PullGroup 'LIVE-FILE-RUN'} Registry{Invoke-RegistryOperationsMenu @Common} Service{Invoke-ServiceTaskOperationsMenu @Common}}
 $Csv=if($Result -and $Result.PSObject.Properties['ResultCsv'] -and $Result.ResultCsv){[string]$Result.ResultCsv}elseif($script:LastHtml){[IO.Path]::ChangeExtension($script:LastHtml,'.csv')}else{''}
 if($Csv -and (Test-Path -LiteralPath $Csv)){
  $Rows=@(Import-Csv -LiteralPath $Csv -Delimiter ';')
  foreach($Row in $Rows){$Status=if($Row.PSObject.Properties['Status']){$Row.Status}elseif($Row.PSObject.Properties['Durum']){$Row.Durum}else{''};if($Status -match '^(Failed|Hata|Error|Blocked|Unreachable)$'){throw ($Rows|Out-String)}}
 }
 return $Result
}
try{
 New-Item -ItemType Directory -Path $Sandbox|Out-Null
 [IO.File]::WriteAllText((Join-Path $Sandbox '.owned'),$Token)
 New-Item -ItemType Directory -Path $Fixtures,$Data -Force|Out-Null
 Test-LiveCase 'Transport.CIM-DCOM' {$Session=Get-ServiceTaskSession $env:COMPUTERNAME;try{Assert-Live (@(Get-CimInstance -CimSession $Session Win32_OperatingSystem).Count -eq 1) 'No OS result'}finally{Remove-CimSession $Session}}
 Test-LiveCase 'Transport.AdminShare' {$Remote=ConvertTo-AORemoteAdminPath $env:COMPUTERNAME $Fixtures;Assert-Live (Test-Path -LiteralPath $Remote -PathType Container) 'Local admin SMB share is not accessible'}
 $Source=Join-Path $Fixtures 'source.txt';Set-Content -LiteralPath $Source 'owned fixture content'
 Test-LiveCase 'File.Pull' {$R=Invoke-LiveMenu File PULL @('1',$Source,'0');$CsvRows=@(Import-Csv $R.ResultCsv -Delimiter ';');$Pulled=[string]$CsvRows[0].LokalHedefPath;Assert-Live ($Pulled.StartsWith((Join-Path $Data 'PulledFiles\LIVE-FILE-RUN'))) 'File pull not in run group';Assert-Live (@(Get-ChildItem $Pulled -Recurse -File|Where-Object{(Get-Content $_.FullName -Raw) -match 'owned fixture'}).Count -eq 1) 'Pulled content differs'}
 $Push=Join-Path $Fixtures 'pushed'
 Test-LiveCase 'File.Push' {[void](Invoke-LiveMenu File PUSH @('3',$Source,$Push,'H','0'));Assert-Live (Test-Path (Join-Path $Push 'source.txt')) 'Push missing'}
 Test-LiveCase 'File.Compare' {$R=Invoke-LiveMenu File COMPARE @('4',$Source,(Join-Path $Push 'source.txt'),'0');$Rows=@(Import-Csv $R.ResultCsv -Delimiter ';');Assert-Live ([string]$Rows[0].HashEsit -eq 'True') 'Compare hash did not match'}
 Test-LiveCase 'File.BackupDeleteRestore' {
  $Delete=Join-Path $Fixtures 'delete-me.txt';Set-Content $Delete 'restore this owned fixture'
  [void](Invoke-LiveMenu File DELETE @('2',$Delete,'DELETE','0'));Assert-Live (-not(Test-Path $Delete)) 'Delete failed'
  [void](Invoke-LiveMenu File RESTORE @('5','1','RESTORE','0'));Assert-Live ((Get-Content $Delete -Raw) -match 'restore this owned fixture') 'Restore content differs'
 }
 Test-LiveCase 'File.BrowsePull' {
  $script:Answers.Clear();foreach($A in @($Push,'1','1')){$script:Answers.Enqueue($A)}
  $R=Invoke-AORemoteFileBrowseOperations -BasePath $Data -Systems $Systems -ReachableSystems $Systems -OperationID BROWSEPULL -PullGroup LIVE-BROWSE
  Assert-Live ($R.Rows[0].Status -eq 'Success' -and (Test-Path $R.Rows[0].LokalHedefPath)) 'Browse pull did not preserve local file path'
 }
 Test-LiveCase 'File.BrowseMoveRollback' {
  $Moved=Join-Path $Fixtures 'moved';$script:Answers.Clear();foreach($A in @($Push,'1','2',$Moved,'MOVE')){$script:Answers.Enqueue($A)}
  [void](Invoke-AORemoteFileBrowseOperations -BasePath $Data -Systems $Systems -ReachableSystems $Systems -OperationID BROWSEMOVE)
  Assert-Live (-not(Test-Path (Join-Path $Push 'source.txt')) -and (Test-Path (Join-Path $Moved 'source.txt'))) 'Move did not change the owned file location'
  $Runs=@(Get-ChildItem (Join-Path $Data 'FileRollbacks') -Directory|Sort-Object LastWriteTime -Descending);$Index=0
  for($i=0;$i -lt $Runs.Count;$i++){if($Runs[$i].Name -eq 'BROWSEMOVE'){$Index=$i+1}}
  Assert-Live ($Index -gt 0) 'Move manifest missing';$script:Answers.Clear();$script:Answers.Enqueue([string]$Index);$script:Answers.Enqueue('ROLLBACK')
  Invoke-AORemoteFileRollback -BasePath $Data
  Assert-Live (Test-Path (Join-Path $Push 'source.txt')) 'Move rollback did not restore original file'
 }
 Test-LiveCase 'File.BrowseReplaceRollback' {
  $Replacement=Join-Path $Fixtures 'replacement.txt';Set-Content $Replacement 'replacement fixture'
  $script:Answers.Clear();foreach($A in @($Push,'1','4',$Replacement,'REPLACE')){$script:Answers.Enqueue($A)}
  [void](Invoke-AORemoteFileBrowseOperations -BasePath $Data -Systems $Systems -ReachableSystems $Systems -OperationID BROWSEREPLACE)
  Assert-Live ((Get-Content (Join-Path $Push 'source.txt') -Raw) -match 'replacement fixture') 'Replace failed'
  $Runs=@(Get-ChildItem (Join-Path $Data 'FileRollbacks') -Directory|Sort-Object LastWriteTime -Descending);$Index=0
  for($i=0;$i -lt $Runs.Count;$i++){if($Runs[$i].Name -eq 'BROWSEREPLACE'){$Index=$i+1}}
  Assert-Live ($Index -gt 0) 'Replace manifest missing';$script:Answers.Clear();$script:Answers.Enqueue([string]$Index);$script:Answers.Enqueue('ROLLBACK')
  Invoke-AORemoteFileRollback -BasePath $Data
  Assert-Live ((Get-Content (Join-Path $Push 'source.txt') -Raw) -match 'owned fixture content') 'Replace rollback content differs'
 }
 Test-LiveCase 'Registry.CreateOwnedFixture' {Assert-Live (-not(Test-Path $RegistryNative)) 'Registry fixture collision';New-Item -Path $RegistryNative -Force|Out-Null;$script:OwnedRegistry=$true;New-ItemProperty -LiteralPath $RegistryNative -Name Fixture -Value old -PropertyType String -Force|Out-Null}
 Test-LiveCase 'Registry.ReadEditRollback' {
  Assert-Live $script:OwnedRegistry 'Registry fixture unavailable'
  [void](Invoke-LiveMenu Registry REGREAD @('1',$RegistryKey,'Fixture','0'))
  [void](Invoke-LiveMenu Registry REGEDIT @('2',$RegistryKey,'Fixture','new','EDIT','0'))
  Assert-Live ((Get-ItemPropertyValue -LiteralPath $RegistryNative -Name Fixture) -eq 'new') 'Registry edit failed'
  [void](Invoke-LiveMenu Registry REGROLL @('4',(Join-Path $Data 'RegistryRollback\REGEDIT_Edit.csv'),'ROLLBACK','0'))
  Assert-Live ((Get-ItemPropertyValue -LiteralPath $RegistryNative -Name Fixture) -eq 'old') 'Registry rollback failed'
 }
 Test-LiveCase 'Registry.DeleteRollback' {
  Assert-Live $script:OwnedRegistry 'Registry fixture unavailable'
  [void](Invoke-LiveMenu Registry REGDELETE @('3',$RegistryKey,'Fixture','DELETE','0'))
  Assert-Live ($null -eq (Get-ItemProperty -LiteralPath $RegistryNative).PSObject.Properties['Fixture']) 'Registry deletion failed'
  [void](Invoke-LiveMenu Registry REGRESTORE @('4',(Join-Path $Data 'RegistryRollback\REGDELETE_Delete.csv'),'ROLLBACK','0'))
  Assert-Live ((Get-ItemPropertyValue -LiteralPath $RegistryNative -Name Fixture) -eq 'old') 'Registry delete rollback failed'
 }
 $Executable=Join-Path $Sandbox 'OwnedFixture.exe'
 Test-LiveCase 'Service.CreateOwnedFixture' {
  Assert-Live ($null -eq (Get-Service $ServiceName -ErrorAction SilentlyContinue)) 'Service name collision'
  $Code='using System;using System.ServiceProcess;using System.Threading;public class OwnedFixture:ServiceBase{public OwnedFixture(){ServiceName="'+$ServiceName+'";}protected override void OnStart(string[] a){}protected override void OnStop(){}public static void Main(string[] a){if(a.Length>0 && a[0]=="--wait"){Thread.Sleep(300000);return;}ServiceBase.Run(new OwnedFixture());}}'
  Add-Type -TypeDefinition $Code -ReferencedAssemblies System.ServiceProcess -OutputAssembly $Executable -OutputType ConsoleApplication
  $Acl=Get-Acl $Sandbox;$Rule=New-Object Security.AccessControl.FileSystemAccessRule ([Security.Principal.SecurityIdentifier]'S-1-5-19'),'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow';$Acl.AddAccessRule($Rule);Set-Acl $Sandbox $Acl
  & sc.exe create $ServiceName binPath= ('"'+$Executable+'"') start= demand obj= 'NT AUTHORITY\LocalService' | Out-Host
  Assert-Live ($LASTEXITCODE -eq 0) 'Owned service creation failed';$script:OwnedService=$true
 }
 Test-LiveCase 'Service.ListStartRestartStop' {
  Assert-Live $script:OwnedService 'Service fixture unavailable'
  [void](Invoke-LiveMenu Service SVCLIST @('1',$ServiceName,'0'))
  foreach($Action in 'start','restart','stop'){
   [void](Invoke-LiveMenu Service ('SVC'+$Action) @('2',$ServiceName,$Action,$Action.ToUpperInvariant(),'0'))
   $Expected=if($Action -eq 'stop'){'Stopped'}else{'Running'};$End=(Get-Date).AddSeconds(10)
   do{$Current=Get-CimInstance Win32_Service -Filter "Name='$ServiceName'";if($Current.State -eq $Expected){break};Start-Sleep -Milliseconds 200}while((Get-Date) -lt $End)
   Assert-Live ($Current.State -eq $Expected) "Service did not reach $Expected"
  }
 }
 Test-LiveCase 'Service.StartupRollback' {
  Assert-Live $script:OwnedService 'Service fixture unavailable'
  [void](Invoke-LiveMenu Service SVCMODE @('3',$ServiceName,'disabled','EDIT','0'))
  Assert-Live ((Get-CimInstance Win32_Service -Filter "Name='$ServiceName'").StartMode -eq 'Disabled') 'Startup change failed'
  [void](Invoke-LiveMenu Service SVCROLL @('7',(Join-Path $Data 'ServiceTaskRollbacks\SVCMODE_Services.csv'),'ROLLBACK','0'))
  Assert-Live ((Get-CimInstance Win32_Service -Filter "Name='$ServiceName'").StartMode -eq 'Manual') 'Startup rollback failed'
 }
 Test-LiveCase 'Task.CreateOwnedFixture' {
  $script:Scheduler=New-Object -ComObject Schedule.Service;$Scheduler.Connect();[void]$Scheduler.GetFolder('\').CreateFolder($TaskFolder);$script:OwnedTaskFolder=$true
  $Action=New-ScheduledTaskAction -Execute $env:ComSpec -Argument '/d /c exit 0'
  $Principal=New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\LOCAL SERVICE' -LogonType ServiceAccount
  Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Action $Action -Principal $Principal -Force|Out-Null;$script:OwnedTask=$true
 }
 Test-LiveCase 'Task.ListDisableEnableRunDeleteRollback' {
  Assert-Live $script:OwnedTask 'Task fixture unavailable'
  [void](Invoke-LiveMenu Service TASKLIST @('4',$TaskName,'0'))
  foreach($Action in 'Disable','Enable','Run','Delete'){
   $OperationID='TASK'+$Action
   $R=Invoke-ScheduledTaskActionRequest ([pscustomobject]@{Action=$Action;TaskName=$TaskName;TaskPath=$TaskPath})
   Assert-Live ($R.Rows[0].Status -eq 'Success') ($R.Rows[0].ErrorDetail)
   if($Action -eq 'Disable'){Assert-Live (-not(Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath).Settings.Enabled) 'Task still enabled'}
   if($Action -eq 'Enable'){Assert-Live (Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath).Settings.Enabled 'Task still disabled'}
   if($Action -eq 'Run'){Start-Sleep -Seconds 2;Assert-Live ((Get-ScheduledTaskInfo -TaskName $TaskName -TaskPath $TaskPath).LastRunTime -gt (Get-Date).AddMinutes(-2)) 'Task never ran'}
  }
  Assert-Live ($null -eq (Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue)) 'Task delete failed'
  $OperationID='TASKRESTORE'
  $R=Invoke-ServiceTaskRollbackRequest ([pscustomobject]@{ManifestPath=(Join-Path $Data 'ServiceTaskRollbacks\TASKDelete_ScheduledTasks.csv')})
  Assert-Live ($null -ne (Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue)) 'Task rollback failed'
 }
 Test-LiveCase 'Process.QueryKillOwnedPID' {
  Assert-Live (Test-Path $Executable) 'Owned fixture executable unavailable'
  $script:OwnedProcess=Microsoft.PowerShell.Management\Start-Process -FilePath $Executable -ArgumentList '--wait' -WindowStyle Hidden -PassThru
  $OwnedId=$script:OwnedProcess.Id
  [void](Invoke-LiveMenu Service PROCQUERY @('9',[string]$OwnedId,'0'))
  [void](Invoke-LiveMenu Service PROCKILL @('10',[string]$OwnedId,'KILL','0'))
  Assert-Live ($script:OwnedProcess.WaitForExit(10000)) 'Owned PID did not exit'
 }
}finally{
 $CleanupErrors=@();$ProcessCleanupVerified=($null -eq $script:OwnedProcess);$TaskFolderAbsent=(-not $script:OwnedTaskFolder)
 try{if($script:OwnedProcess){if(-not $script:OwnedProcess.HasExited){Stop-Process -Id $script:OwnedProcess.Id -Force};$ProcessCleanupVerified=$script:OwnedProcess.WaitForExit(10000);$script:OwnedProcess.Dispose()}}catch{$CleanupErrors+='Process: '+$_.Exception.Message}
 try{if($script:OwnedTask){Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false -ErrorAction SilentlyContinue};if($script:OwnedTaskFolder -and $Scheduler){$Scheduler.GetFolder('\').DeleteFolder($TaskFolder,0);$TaskFolderAbsent=(@($Scheduler.GetFolder('\').GetFolders(0)|Where-Object Name -eq $TaskFolder).Count -eq 0)}}catch{$CleanupErrors+='Task: '+$_.Exception.Message}
 try{if($script:OwnedService){
  & sc.exe stop $ServiceName|Out-Null;$StopCode=$LASTEXITCODE
  if($StopCode -notin @(0,1060,1062)){throw "Owned service stop returned $StopCode"}
  $Until=(Get-Date).AddSeconds(15)
  do{$Svc=Get-CimInstance Win32_Service -Filter "Name='$ServiceName'";if($null -eq $Svc -or $Svc.State -eq 'Stopped'){break};Start-Sleep -Milliseconds 200}while((Get-Date) -lt $Until)
  if($null -ne $Svc -and $Svc.State -ne 'Stopped'){throw 'Owned service did not stop before cleanup deadline.'}
  & sc.exe delete $ServiceName|Out-Null;$DeleteCode=$LASTEXITCODE
  if($DeleteCode -notin @(0,1060,1072)){throw "Owned service delete returned $DeleteCode"}
  $Until=(Get-Date).AddSeconds(15)
  do{$Svc=Get-CimInstance Win32_Service -Filter "Name='$ServiceName'";if($null -eq $Svc){break};Start-Sleep -Milliseconds 200}while((Get-Date) -lt $Until)
  if($null -ne $Svc){throw 'Owned service remains after delete deadline.'}
 }}catch{$CleanupErrors+='Service: '+$_.Exception.Message}
 try{if($script:OwnedRegistry -and $RegistryNative.EndsWith($Token)){[Microsoft.Win32.Registry]::LocalMachine.DeleteSubKeyTree($RegistryKey,$false);if(-not $RegistryParentExisted -or $CleanupOwnedRegistryParent){$ParentKey=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\YD_RemoteOps_LiveTest');if($null -ne $ParentKey){try{$Empty=($ParentKey.SubKeyCount -eq 0 -and $ParentKey.ValueCount -eq 0)}finally{$ParentKey.Dispose()};if($Empty){[Microsoft.Win32.Registry]::LocalMachine.DeleteSubKey('SOFTWARE\YD_RemoteOps_LiveTest',$false)}}}}}catch{$CleanupErrors+='Registry: '+$_.Exception.Message}
 try{if(Test-Path (Join-Path $Data 'Logs')){Copy-Item -LiteralPath (Join-Path $Data 'Logs') -Destination (Join-Path $OutputDirectory ('evidence-'+$Short)) -Recurse -Force}}catch{$CleanupErrors+='Evidence: '+$_.Exception.Message}
 $Summary=[pscustomobject]@{ExecutedAt=(Get-Date).ToString('o');ComputerName=$env:COMPUTERNAME;Admin=$Admin;Sandbox=$Sandbox;Service=$ServiceName;TaskPath=$TaskPath;RegistryKey=$RegistryKey;RegistryParentExisted=$RegistryParentExisted;Cases=@($script:Cases.ToArray());CleanupErrors=$CleanupErrors;RemoteCallsMocked=$false;ReportAutoOpenSuppressed=$true}
 try{
  $Resolved=[IO.Path]::GetFullPath($Sandbox);$Allowed=[IO.Path]::GetFullPath($env:ProgramData).TrimEnd('\')+'\'
  if($Resolved.StartsWith($Allowed,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $Resolved -Leaf) -eq ('YD_RemoteOps_LiveTest_'+$Token) -and [IO.File]::ReadAllText((Join-Path $Resolved '.owned')) -eq $Token){Remove-Item -LiteralPath $Resolved -Recurse -Force}
 }catch{$Summary.CleanupErrors+=('Sandbox: '+$_.Exception.Message)}
 $Checks=[ordered]@{OwnedProcessExited=$ProcessCleanupVerified;TaskFolderAbsent=$TaskFolderAbsent;SandboxAbsent=(-not(Test-Path $Sandbox));RegistryAbsent=(-not(Test-Path $RegistryNative));ServiceAbsent=($null -eq (Get-Service $ServiceName -ErrorAction SilentlyContinue));TaskAbsent=($null -eq (Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue))}
 foreach($Key in $Checks.Keys){if(-not $Checks[$Key]){$Summary.CleanupErrors+=('Residual fixture: '+$Key)}}
 Add-Member -InputObject $Summary -NotePropertyName CleanupChecks -NotePropertyValue ([pscustomobject]$Checks)
 $Summary|ConvertTo-Json -Depth 7|Set-Content $Report -Encoding UTF8
 $script:Cases.ToArray()|Export-Csv (Join-Path $OutputDirectory 'LOCAL_LIVE_TEST.csv') -NoTypeInformation -Encoding UTF8
}
if(@($script:Cases|Where-Object Status -ne PASS).Count -or $Summary.CleanupErrors.Count){exit 1}
