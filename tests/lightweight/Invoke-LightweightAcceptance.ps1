[CmdletBinding()]
param([string]$OutputRoot='', [switch]$Smoke)
$ErrorActionPreference='Stop'
$Root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if(-not $OutputRoot){$OutputRoot=Join-Path $Root ('docs\v27-offline-acceptance\Run-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))}
$OutputRoot=[IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Path $OutputRoot -Force|Out-Null
$Sandbox=Join-Path $env:TEMP ('RemoteOps-Lightweight-'+[guid]::NewGuid().ToString('N'))
$OldAppData=$env:APPDATA;$OldState=$env:REMOTEOPS_OFFLINE_STATE;$OldRunner=$env:REMOTEOPS_OFFLINE_RUNNER
$Clock=[Diagnostics.Stopwatch]::StartNew();$script:Cases=New-Object Collections.ArrayList;$script:AllRuns=New-Object Collections.ArrayList
$script:PendingConfig=$null;$script:DialogError=$null;$script:UiTimer=$null;$script:Window=$null;$script:OutputTimer=$null
$script:PeakCombinedBytes=0;$script:CaseId='setup';$script:CaseNumber=0
function Assert-Acceptance($Value,[string]$Message){if(-not $Value){throw $Message}}
function Click-TestControl($Control){$Control.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))}
function Read-Model {
 for($Attempt=0;$Attempt -lt 30;$Attempt++){
  $Stream=$null;$Reader=$null
  try{$Stream=[IO.File]::Open($script:ModelPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete));$Reader=New-Object IO.StreamReader $Stream;return (ConvertFrom-Json ($Reader.ReadToEnd()))}
  catch{if($Attempt -eq 29){throw};Start-Sleep -Milliseconds 10}
  finally{if($Reader){$Reader.Dispose()}elseif($Stream){$Stream.Dispose()}}
 }
}
function Write-Model($Model){[IO.File]::WriteAllText($script:ModelPath,($Model|ConvertTo-Json -Depth 50),(New-Object Text.UTF8Encoding $true))}
function New-ModelTarget([string]$State='Stopped',[string]$Version='16.0.444',[string]$ValueType='REG_SZ'){
 [pscustomobject]@{Service=[pscustomobject]@{Exists=$true;Name='OfflineDemo';State=$State;Startup='Automatic'};Registry=[pscustomobject]@{'HKLM\SOFTWARE\Fixture|Version'=[pscustomobject]@{Exists=$true;ValueType=$ValueType;Value=$Version}}}
}
function Reset-Model($Targets,[int]$PauseAfterMutationMs=0){Write-Model ([pscustomobject]@{Targets=[pscustomobject]$Targets;Events=@();PauseAfterMutationMs=$PauseAfterMutationMs})}
function Get-Mutations($Model){@($Model.Events|Where-Object{$_.Operation -in @('StartService','StopService','ChangeStartMode') -and -not [string]$_.Error})}
function Assert-OperationalEffect($Model,[string]$Target,[string]$State,[string[]]$Methods){
 Assert-Acceptance ($Model.Targets.($Target).Service.State -ceq $State) 'Success report does not match independently expected service state.'
 $Actual=@(Get-Mutations $Model|ForEach-Object{$_.Target+'|'+$_.Operation}) -join ','
 $Expected=@($Methods|ForEach-Object{$Target+'|'+$_}) -join ','
 Assert-Acceptance ($Actual -ceq $Expected) 'Mutation target or order differs from independent expectation.'
}
function Registry-Check([string]$Expected='16.0.444',[string]$Operator='Equals'){
 [pscustomobject]@{Kind='RegistryValue';Path='HKLM\SOFTWARE\Fixture';Name='Version';Operator=$Operator;ExpectedType='Auto';Expected=$Expected}
}
function Service-Check([string]$Expected='Stopped',[string]$Operator='State'){
 [pscustomobject]@{Kind='Service';Path='';Name='OfflineDemo';Operator=$Operator;ExpectedType='';Expected=$Expected}
}
function Gate($Checks,[string]$Match='All',[string]$OnFalse='Skip'){[pscustomobject]@{Checks=@($Checks);Match=$Match;OnFalse=$OnFalse}}
function Step([string]$Operation='ServiceControl',[string]$Action='Start',$Condition=$null){
 $Values=switch($Operation){ServiceControl{@{ServiceName='OfflineDemo';Action=$Action}}ServiceStartup{@{ServiceName='OfflineDemo';StartupType=$Action}}ServiceList{@{Filter='OfflineDemo'}}}
 [pscustomobject]@{Operation=$Operation;Values=$Values;Condition=$Condition}
}
function Fill-TestStepDialog {
 $D=$script:RecipeUi.Dialog;$Config=$script:PendingConfig;$C=$script:RecipeUi.Controls
 Assert-Acceptance ($null -ne $D) 'Add-step button did not open focused editor.'
 $D.Window.ShowActivated=$false;$D.Window.Left=-20000;$D.Window.Top=-20000
 $C.Operation.SelectedItem=@($C.Operation.Items|Where-Object Name -ceq $Config.Operation)[0]
 foreach($K in $Config.Values.Keys){$Input=$script:RecipeUi.Fields[$K];if($Input -is [Windows.Controls.ComboBox]){$Input.SelectedItem=$Config.Values[$K]}else{$Input.Text=[string]$Config.Values[$K]}}
 Assert-Acceptance (-not $C.CustomizeName.IsChecked -and $C.StepNameWrap.Visibility -eq 'Collapsed') 'New step requires a custom name.'
 if($Config.Condition){
  $D.Controls.Enabled.IsChecked=$true;Click-TestControl $D.Controls.Enabled;$D.Controls.Tabs.SelectedIndex=1
  for($I=0;$I -lt $Config.Condition.Checks.Count;$I++){
   if($I -gt 0){$Add=@($script:RecipeUi.Controls.Fields.Children|Where-Object{$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Ek kontrol'})[0];Click-TestControl $Add}
   $Row=$script:RecipeUi.ConditionInputs.Rows[$I];$Check=$Config.Condition.Checks[$I]
   $Row.Kind.SelectedItem=$Check.Kind;$Row.Path.Text=$Check.Path;$Row.Name.Text=$Check.Name;$Row.Operator.SelectedItem=$Check.Operator
   if($Check.Kind -eq 'Service' -and $Check.Operator -in @('State','Startup')){$Row.ExpectedChoice.SelectedItem=$Check.Expected}else{$Row.Expected.Text=$Check.Expected}
  }
  $script:RecipeUi.ConditionInputs.Match.SelectedItem=$Config.Condition.Match;$script:RecipeUi.ConditionInputs.OnFalse.SelectedItem=$Config.Condition.OnFalse
 }
 Click-TestControl $D.Controls.Apply
 Assert-Acceptance $D.Applied ('Dialog did not apply: '+$D.Controls.Error.Text)
}
function Add-TestUiStep($Config){
 $script:PendingConfig=$Config;$script:DialogError=$null
 $script:UiTimer=New-Object Windows.Threading.DispatcherTimer;$script:UiTimer.Interval=[TimeSpan]::FromMilliseconds(30)
 $script:UiTimer.Add_Tick({$script:UiTimer.Stop();try{Fill-TestStepDialog}catch{$script:DialogError=$_.Exception.Message;if($script:RecipeUi.Dialog){$script:RecipeUi.Dialog.Window.Close()}}})
 $script:UiTimer.Start();Click-TestControl $script:RecipeUi.Controls.AddStep
 if($script:DialogError){throw $script:DialogError}
}
function New-TestUiRecipe($Configs){
 $C=$script:RecipeUi.Controls;Click-TestControl $C.New;$C.Name.Text='Offline '+$script:CaseId;$C.Description.Text='Stateful offline acceptance fixture'
 foreach($Config in $Configs){Add-TestUiStep $Config}
 Click-TestControl $C.Save
 $Saved=@((Get-RemoteOpsRecipeCatalog $script:RecipeUi.Root).Recipes|Where-Object Name -ceq $C.Name.Text)
 Assert-Acceptance ($Saved.Count -eq 1) ('Recipe save failed: '+$C.Status.Text)
 $Before=Get-RemoteOpsPreviewHash $Saved[0]
 $C.List.SelectedItem=@($C.List.Items|Where-Object Id -ceq $Saved[0].Id)[0]
 Assert-Acceptance ((Get-RemoteOpsPreviewHash (Get-RemoteOpsRecipeEditorDefinition)) -ceq $Before) 'Saved/reopened recipe differs.'
 foreach($Action in @($script:RecipeUi.Draft.Steps|Where-Object Operation -ne 'RecipeCondition')){Assert-Acceptance ($Action.AutoName -and $Action.Name -ceq (Get-RemoteOpsRecipeAutoName $Action)) 'Automatic step name lost after reopen.'}
 Assert-Acceptance ($C.Steps.Items.Count -eq @($Configs).Count) 'Embedded condition leaked as standalone UI step.'
 return $Saved[0]
}
function Invoke-TestGuiRun([string[]]$Targets,[switch]$CancelAfterFirstMutation){
 $C=$script:RecipeUi.Controls;$C.Targets.Text=$Targets -join ' '
 $Preview=New-RemoteOpsRecipePreviewWindow (Get-RemoteOpsRecipeEditorDefinition) $Targets
 $Preview.Controls.Confirm.Text='RECETE';Click-TestControl $Preview.Controls.Start
 Assert-Acceptance $Preview.Started ('GUI did not start: '+$Preview.Controls.Error.Text)
 Assert-Acceptance ($script:ActiveRuns.Count -eq 1) 'GUI did not track exactly one coordinator.'
 $Run=$script:ActiveRuns[0];$Cancelled=$false;$Timer=[Diagnostics.Stopwatch]::StartNew()
 while(-not $Run.Process.HasExited){
  $Model=Read-Model
  if($CancelAfterFirstMutation -and -not $Cancelled -and @(Get-Mutations $Model).Count -ge 1){Request-RemoteOpsRunCancellation $Run.CancelPath;$Cancelled=$true}
  $Combined=(Get-Process -Id $PID).WorkingSet64
  foreach($ProcId in @($Run.Process.Id)+@($Model.Events|ForEach-Object PID|Select-Object -Unique)){if($ProcId -ne $PID){$P=Get-Process -Id $ProcId -ErrorAction SilentlyContinue;if($P){$Combined+=$P.WorkingSet64}}}
  if($Combined -gt $script:PeakCombinedBytes){$script:PeakCombinedBytes=$Combined}
  if($Timer.Elapsed.TotalSeconds -gt 120){throw 'Offline coordinator timeout; no new test may start.'}
  Start-Sleep -Milliseconds 40;$Run.Process.Refresh()
 }
 $Run.Process.WaitForExit()
 if($Run.Process.ExitCode -ne 0){throw ('Runner process failed: '+(Get-Content -LiteralPath $Run.StdErrPath -Raw -Encoding UTF8)+' '+(Get-Content -LiteralPath $Run.StdOutPath -Raw -Encoding UTF8))}
 $RunRoot=Split-Path $Run.CancelPath -Parent
 $Rows=@(Import-Csv (Join-Path $RunRoot 'Results.csv') -Delimiter ';' -Encoding UTF8)
 $RunId=Split-Path $RunRoot -Leaf;$Ledger=@(Import-Csv (Join-Path $script:TestData ('Logs\Reports\Ledger\'+$RunId+'.csv')) -Delimiter ';' -Encoding UTF8)
 Assert-Acceptance (Test-Path -LiteralPath (Join-Path $RunRoot 'Results.html')) 'HTML result report missing.'
 Assert-Acceptance (Test-Path -LiteralPath (Join-Path $RunRoot 'state\reported.json')) 'Coordinator completion receipt missing.'
 Assert-Acceptance ($Ledger.Count -eq $Targets.Count) 'Ledger target count differs.'
 foreach($Target in $Targets){Assert-Acceptance (@($Ledger|Where-Object ComputerName -ceq $Target).Count -eq 1) 'Ledger target identity differs.'}
 $After=Read-Model
 $Artifact=Join-Path $OutputRoot $script:CaseId;New-Item -ItemType Directory -Path $Artifact -Force|Out-Null
 Copy-Item -LiteralPath $RunRoot -Destination (Join-Path $Artifact 'report') -Recurse
 Copy-Item -LiteralPath (Join-Path $script:TestData ('Logs\Reports\Ledger\'+$RunId+'.csv')) -Destination (Join-Path $Artifact 'ledger.csv')
 [IO.File]::WriteAllText((Join-Path $Artifact 'after.json'),($After|ConvertTo-Json -Depth 50),(New-Object Text.UTF8Encoding $true))
 [IO.File]::WriteAllText((Join-Path $Artifact 'recipe.json'),((Get-RemoteOpsRecipeEditorDefinition)|ConvertTo-Json -Depth 30),(New-Object Text.UTF8Encoding $true))
 [void]$script:AllRuns.Add([pscustomobject]@{Case=$script:CaseId;RunId=$RunId;CoordinatorPid=$Run.Process.Id;WorkerPids=@($After.Events|ForEach-Object PID|Select-Object -Unique);Seconds=[Math]::Round($Timer.Elapsed.TotalSeconds,2);Cancelled=$Cancelled;Report=$Artifact})
 $script:ActiveRuns.Clear();$Run.Process.Dispose();Update-StopButton
 return [pscustomobject]@{Rows=$Rows;Ledger=$Ledger;Model=$After;Root=$RunRoot;Cancelled=$Cancelled}
}
function Run-Case([string]$Id,[string]$Title,[scriptblock]$Work){
 $script:CaseId=$Id;$script:CaseNumber++;$Timer=[Diagnostics.Stopwatch]::StartNew()
 try{& $Work|Out-Null;$Status='PASS';$Detail='Expected state, ordering and report assertions passed.'}catch{$Status='FAIL';$Detail=$_.Exception.Message}
 [void]$script:Cases.Add([pscustomobject]@{Id=$Id;Title=$Title;Status=$Status;Detail=$Detail;Seconds=[Math]::Round($Timer.Elapsed.TotalSeconds,2)})
 $script:Cases|Export-Csv (Join-Path $OutputRoot 'cases.csv') -NoTypeInformation -Encoding UTF8
 Write-Output ($Id+' '+$Status+' '+$Detail)
 if($script:ActiveRuns.Count){throw 'A coordinator remains active; refusing additional tests.'}
}
try{
 New-Item -ItemType Directory -Path $Sandbox -Force|Out-Null
 $script:ModelPath=Join-Path $Sandbox 'state.json';$script:TestData=Join-Path $Sandbox 'data';$env:APPDATA=Join-Path $Sandbox 'profiles'
 Reset-Model @{ 'SIM-PC1'=(New-ModelTarget) }
 . (Join-Path $PSScriptRoot 'New-OfflineRunnerFixture.ps1')
 $Runner=New-RemoteOpsOfflineRunnerFixture -SourceRoot $Root -FixtureRoot (Join-Path $Sandbox 'fixture') -DataRoot $script:TestData -StatePath $script:ModelPath
 . (Join-Path $PSScriptRoot 'FixtureBoundary.ps1')
 function Start-Process {[CmdletBinding()]param([string]$FilePath,[string[]]$ArgumentList,[string]$WorkingDirectory,[switch]$Wait,[switch]$PassThru,[string]$RedirectStandardOutput,[string]$RedirectStandardError,[string]$WindowStyle) Invoke-OfflineStartProcess @PSBoundParameters}
 $App=Join-Path (Split-Path $Runner -Parent) 'RemoteOps.App.ps1';$Source=[IO.File]::ReadAllText($App)
 $Source=$Source.Replace('$script:AppRoot = Split-Path -Parent $PSCommandPath',('$script:AppRoot = '''+(Split-Path $Runner -Parent).Replace("'","''")+''''))
 $Source=$Source.Replace('''C:\Temp\YD_RemoteOps.App''',("'"+$script:TestData.Replace("'","''")+"'"))
 Assert-Acceptance (-not $Source.Contains("'C:\Temp\YD_RemoteOps.App'")) 'GUI runtime root redirection incomplete.'
 $Source=$Source.Replace('[void]$script:Window.ShowDialog()','')
 . ([scriptblock]::Create($Source));$script:OutputTimer.Stop()
 $Profile=[pscustomobject]@{Domain='OFFLINE';UserName='operator';Display='OFFLINE\operator';IsMain=$true;ProtectedPassword=''}
 $script:ProfileList.ItemsSource=@($Profile);$script:ProfileList.SelectedIndex=0
 Run-Case '01-stateful-chain' 'Registry + service condition, start, later state read, stop, startup and list' {
  Reset-Model @{'SIM-PC1'=(New-ModelTarget)}
  $D=New-TestUiRecipe @((Step ServiceControl Start (Gate @((Registry-Check),(Service-Check)))),(Step ServiceControl Stop (Gate @((Service-Check Running)))),(Step ServiceStartup Manual),(Step ServiceList))
  $R=Invoke-TestGuiRun @('SIM-PC1');$M=@(Get-Mutations $R.Model)
  Assert-Acceptance (($M.Operation -join ',') -ceq 'StartService,StopService,ChangeStartMode') 'Stateful mutation order differs.'
  Assert-OperationalEffect $R.Model 'SIM-PC1' 'Stopped' @('StartService','StopService','ChangeStartMode')
  Assert-Acceptance ($R.Model.Targets.'SIM-PC1'.Service.State -ceq 'Stopped' -and $R.Model.Targets.'SIM-PC1'.Service.Startup -ceq 'Manual') 'Final service state/startup differs.'
  $Later=@($R.Rows|Where-Object{$_.Operation -eq 'ServiceList' -and $_.Status -eq 'Success'})
  Assert-Acceptance ($Later.Count -eq 1 -and $Later[0].State -ceq 'Stopped' -and $Later[0].StartMode -ceq 'Manual') 'Real service list report did not observe final model state.'
  Assert-Acceptance (@($R.Ledger|Where-Object Outcome -cne 'Completed').Count -eq 0) 'Chain did not complete.'
  Assert-Acceptance (@($R.Model.Events|ForEach-Object PID|Select-Object -Unique).Count -ge 2) 'Child process evidence absent.'
 }
 if(-not $Smoke){
  Run-Case '02-target-scope' 'Match, nonmatch and missing value across three independent targets' {
   $Missing=New-ModelTarget;$Missing.Registry.'HKLM\SOFTWARE\Fixture|Version'.Exists=$false
   Reset-Model @{'SIM-PC1'=(New-ModelTarget);'SIM-PC2'=(New-ModelTarget Stopped '16.0.333');'SIM-PC3'=$Missing}
   $D=New-TestUiRecipe @((Step ServiceControl Start (Gate @((Registry-Check)))),(Step ServiceList))
   $R=Invoke-TestGuiRun @('SIM-PC1','SIM-PC2','SIM-PC3')
   Assert-Acceptance ((@(Get-Mutations $R.Model).Target -join ',') -ceq 'SIM-PC1') 'Mutation reached wrong target.'
   Assert-Acceptance (@($R.Rows|Where-Object Status -eq 'Skipped').Count -eq 2) 'Nonmatching/missing targets not skipped.'
   Assert-Acceptance (@($R.Rows|Where-Object Operation -eq 'ServiceList').Count -eq 3) 'Skip suppressed later unconditional step.'
  }
  Run-Case '03-automatic-types' 'Automatic number and string registry comparison' {
   Reset-Model @{'SIM-PC1'=(New-ModelTarget Stopped '1' REG_DWORD);'SIM-PC2'=(New-ModelTarget Stopped '1' REG_SZ);'SIM-PC3'=(New-ModelTarget Stopped '2' REG_DWORD)}
   $D=New-TestUiRecipe @((Step ServiceControl Start (Gate @((Registry-Check '1')))))
   $R=Invoke-TestGuiRun @('SIM-PC1','SIM-PC2','SIM-PC3')
   Assert-Acceptance ((@(Get-Mutations $R.Model).Target -join ',') -ceq 'SIM-PC1,SIM-PC2') 'Observed-type automatic comparison differs.'
  }
  Run-Case '04-missing-not-equal' 'Missing registry value never satisfies NotEquals' {
   $Missing=New-ModelTarget;$Missing.Registry.'HKLM\SOFTWARE\Fixture|Version'.Exists=$false
   Reset-Model @{'SIM-PC1'=(New-ModelTarget Stopped '16.0.333');'SIM-PC2'=$Missing}
   $D=New-TestUiRecipe @((Step ServiceControl Start (Gate @((Registry-Check '16.0.444' NotEquals)))))
   $R=Invoke-TestGuiRun @('SIM-PC1','SIM-PC2');Assert-Acceptance ((@(Get-Mutations $R.Model).Target -join ',') -ceq 'SIM-PC1') 'Missing value matched inequality.'
  }
  Run-Case '05-all-false' 'All requires every check' {
   Reset-Model @{'SIM-PC1'=(New-ModelTarget Running)}
   $D=New-TestUiRecipe @((Step ServiceControl Stop (Gate @((Registry-Check),(Service-Check)))))
   $R=Invoke-TestGuiRun @('SIM-PC1');Assert-Acceptance (@(Get-Mutations $R.Model).Count -eq 0 -and @($R.Rows|Where-Object Status -eq 'Skipped').Count -eq 1) 'All accepted one false check.'
  }
  Run-Case '06-any-true' 'Any permits one true check' {
   Reset-Model @{'SIM-PC1'=(New-ModelTarget Running)}
   $D=New-TestUiRecipe @((Step ServiceControl Stop (Gate @((Registry-Check),(Service-Check)) Any)))
   $R=Invoke-TestGuiRun @('SIM-PC1');Assert-Acceptance ($R.Model.Targets.'SIM-PC1'.Service.State -ceq 'Stopped') 'Any failed to dispatch matching action.'
  }
  Run-Case '07-any-error' 'Any true never overrides a failed service read' {
   $T=New-ModelTarget;$T|Add-Member NoteProperty ProbeErrors ([pscustomobject]@{Service='Fixture read denied'})
   Reset-Model @{'SIM-PC1'=$T}
   $D=New-TestUiRecipe @((Step ServiceControl Start (Gate @((Registry-Check),(Service-Check)) Any)),(Step ServiceList))
   $R=Invoke-TestGuiRun @('SIM-PC1');Assert-Acceptance (@(Get-Mutations $R.Model).Count -eq 0) 'Read error allowed mutation.'
   Assert-Acceptance (@($R.Rows|Where-Object Status -eq 'NotRun').Count -eq 2 -and $R.Ledger[0].Outcome -ceq 'Error') 'Read failure was treated as false/skip.'
  }
  Run-Case '08-onfalse-stop' 'False Stop halts only that target' {
   Reset-Model @{'SIM-PC1'=(New-ModelTarget Stopped 'wrong');'SIM-PC2'=(New-ModelTarget)}
   $D=New-TestUiRecipe @((Step ServiceControl Start (Gate @((Registry-Check)) All Stop)),(Step ServiceStartup Manual))
   $R=Invoke-TestGuiRun @('SIM-PC1','SIM-PC2');Assert-Acceptance ((@(Get-Mutations $R.Model).Target -join ',') -ceq 'SIM-PC2,SIM-PC2') 'False Stop leaked across targets or continued.'
   Assert-Acceptance ($R.Model.Targets.'SIM-PC1'.Service.Startup -ceq 'Automatic') 'Stopped target changed.'
  }
  Run-Case '09-action-error' 'Mutation failure halts chain and next target continues' {
   $T=New-ModelTarget;$T|Add-Member NoteProperty MutationError 'Fixture mutation denied'
   Reset-Model @{'SIM-PC1'=$T;'SIM-PC2'=(New-ModelTarget)}
   $D=New-TestUiRecipe @((Step ServiceControl),(Step ServiceStartup Manual))
   $R=Invoke-TestGuiRun @('SIM-PC1','SIM-PC2')
   Assert-Acceptance ($R.Model.Targets.'SIM-PC1'.Service.State -ceq 'Stopped' -and $R.Model.Targets.'SIM-PC1'.Service.Startup -ceq 'Automatic') 'Failed mutation modified target.'
   Assert-Acceptance ((@(Get-Mutations $R.Model).Target -join ',') -ceq 'SIM-PC2,SIM-PC2') 'Error did not isolate target.'
  }
  Run-Case '10-restart' 'Restart performs stop, observes stopped, then starts' {
   Reset-Model @{'SIM-PC1'=(New-ModelTarget Running)};$D=New-TestUiRecipe @((Step ServiceControl Restart),(Step ServiceList))
   $R=Invoke-TestGuiRun @('SIM-PC1');$M=@(Get-Mutations $R.Model)
   Assert-Acceptance (($M.Operation -join ',') -ceq 'StopService,StartService' -and $M[0].After.Service.State -ceq 'Stopped' -and $M[1].Before.Service.State -ceq 'Stopped') 'Restart state ordering differs.'
   Assert-Acceptance ($R.Model.Targets.'SIM-PC1'.Service.State -ceq 'Running') 'Restart did not finish running.'
   Assert-OperationalEffect $R.Model 'SIM-PC1' 'Running' @('StopService','StartService')
  }
  Run-Case '11-cancellation' 'Real cancellation request after first mutation prevents later work' {
   Reset-Model @{'SIM-PC1'=(New-ModelTarget);'SIM-PC2'=(New-ModelTarget)} 600
   $D=New-TestUiRecipe @((Step ServiceControl),(Step ServiceStartup Manual),(Step ServiceControl Stop))
   $R=Invoke-TestGuiRun @('SIM-PC1','SIM-PC2') -CancelAfterFirstMutation
   Assert-Acceptance ($R.Cancelled -and @(Get-Mutations $R.Model).Count -eq 1) 'Cancellation allowed additional mutations.'
   Assert-Acceptance (@($R.Ledger|Where-Object Outcome -ceq 'Cancelled').Count -eq 2) 'Cancelled targets not reported.'
  }
  Run-Case '12-legacy-shared' 'Existing common condition evaluated once despite changed state' {
   Reset-Model @{'SIM-PC1'=(New-ModelTarget)}
   $D=New-RemoteOpsRecipeDefinition 'Offline shared legacy';$D.Schema='RemoteOps.Recipe/2'
   $Cnd=[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Legacy stopped';Operation='RecipeCondition';Values=(Gate @((Service-Check)))}
   $D.Steps=@($Cnd);foreach($A in @('Start','Stop')){$D.Steps+=,[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name=('Legacy custom '+$A);Operation='ServiceControl';ConditionId=$Cnd.Id;Values=[pscustomobject]@{ServiceName='OfflineDemo';Action=$A}}}
   Open-RemoteOpsRecipeEditor $D;Save-RemoteOpsRecipeEditor;$R=Invoke-TestGuiRun @('SIM-PC1')
   Assert-Acceptance (@($R.Model.Events|Where-Object Operation -ceq 'Probe').Count -eq 1 -and (@(Get-Mutations $R.Model).Operation -join ',') -ceq 'StartService,StopService') 'Legacy gate re-evaluated or scope changed.'
  }
  Run-Case '13-approval-stale-cancel' 'Approval, stale snapshot and preview cancel never launch' {
   Reset-Model @{'SIM-PC1'=(New-ModelTarget)};$D=New-TestUiRecipe @((Step ServiceControl));$script:RecipeUi.Controls.Targets.Text='SIM-PC1'
   $P=New-RemoteOpsRecipePreviewWindow (Get-RemoteOpsRecipeEditorDefinition) @('SIM-PC1');Click-TestControl $P.Controls.Start
   Assert-Acceptance (-not $P.Started -and $P.Controls.Error.Text -and $script:ActiveRuns.Count -eq 0) 'Missing approval launched.';$P.Window.Close()
   $P=New-RemoteOpsRecipePreviewWindow (Get-RemoteOpsRecipeEditorDefinition) @('SIM-PC1');$P.Controls.Confirm.Text='RECETE';$script:RecipeUi.Controls.Name.Text='Stale edit';Click-TestControl $P.Controls.Start
   Assert-Acceptance (-not $P.Started -and $P.Controls.Error.Text -and $script:ActiveRuns.Count -eq 0) 'Stale snapshot launched.';$P.Window.Close();$script:RecipeUi.Controls.Name.Text=$D.Name
   $P=New-RemoteOpsRecipePreviewWindow (Get-RemoteOpsRecipeEditorDefinition) @('SIM-PC1');Click-TestControl $P.Controls.Cancel
   Assert-Acceptance ($script:ActiveRuns.Count -eq 0 -and (Read-Model).Events.Count -eq 0) 'Preview cancellation performed work.'
  }
  Run-Case '14-oracle-negative-controls' 'Real CSV success with suppressed mutation is rejected by independent checker' {
   $T=New-ModelTarget;$T|Add-Member NoteProperty SuppressMutation $true;Reset-Model @{'SIM-PC1'=$T}
   $D=New-TestUiRecipe @((Step ServiceControl));$R=Invoke-TestGuiRun @('SIM-PC1')
   Assert-Acceptance (@($R.Rows|Where-Object{$_.Operation -ceq 'ServiceControl' -and $_.Status -ceq 'Success'}).Count -eq 1) 'No-op negative fixture did not produce actual success report.'
   $Caught=0;try{Assert-OperationalEffect $R.Model 'SIM-PC1' 'Running' @('StartService')}catch{$Caught++}
   $Wrong=ConvertFrom-Json ($R.Model|ConvertTo-Json -Depth 50);$Wrong.Targets.'SIM-PC1'.Service.State='Running';@($Wrong.Events|Where-Object Operation -ceq 'StartService')[0].Target='SIM-PC2'
   try{Assert-OperationalEffect $Wrong 'SIM-PC1' 'Running' @('StartService')}catch{$Caught++}
   Assert-Acceptance ($Caught -eq 2) 'Acceptance checker accepted no-op success or deliberately changed target evidence.'
  }
  Run-Case '15-service-startup' 'Startup change is observed by later startup and service existence condition' {
   Reset-Model @{'SIM-PC1'=(New-ModelTarget)}
   $Exists=Service-Check '' Exists
   $D=New-TestUiRecipe @((Step ServiceStartup Manual),(Step ServiceControl Start (Gate @((Service-Check Manual Startup),$Exists))))
   $R=Invoke-TestGuiRun @('SIM-PC1');Assert-OperationalEffect $R.Model 'SIM-PC1' 'Running' @('ChangeStartMode','StartService')
   Assert-Acceptance ($R.Model.Targets.'SIM-PC1'.Service.Startup -ceq 'Manual') 'Startup condition did not observe changed startup.'
  }
  Run-Case '16-key-and-service-existence' 'Registry key and service existence gate the correct target' {
   $Missing=New-ModelTarget;$Missing.Service.Exists=$false;$Missing.Registry.'HKLM\SOFTWARE\Fixture|Version'.Exists=$false
   Reset-Model @{'SIM-PC1'=(New-ModelTarget);'SIM-PC2'=$Missing}
   $Key=[pscustomobject]@{Kind='RegistryKey';Path='HKLM\SOFTWARE\Fixture';Name='';Operator='Exists';ExpectedType='';Expected=''}
   $D=New-TestUiRecipe @((Step ServiceControl Start (Gate @($Key,(Service-Check '' Exists)))))
   $R=Invoke-TestGuiRun @('SIM-PC1','SIM-PC2');Assert-Acceptance ((@(Get-Mutations $R.Model).Target -join ',') -ceq 'SIM-PC1') 'Existence conditions dispatched wrong target.'
   Assert-Acceptance (@($R.Rows|Where-Object Status -eq 'Skipped').Count -eq 1) 'Missing key/service did not skip action.'
  }
  Run-Case '17-malformed-actual' 'Malformed observed numeric registry data stops target instead of matching' {
   Reset-Model @{'SIM-PC1'=(New-ModelTarget Stopped 'not-a-number' REG_DWORD);'SIM-PC2'=(New-ModelTarget Stopped '1' REG_DWORD)}
   $D=New-TestUiRecipe @((Step ServiceControl Start (Gate @((Registry-Check '1')))))
   $R=Invoke-TestGuiRun @('SIM-PC1','SIM-PC2');Assert-Acceptance ((@(Get-Mutations $R.Model).Target -join ',') -ceq 'SIM-PC2') 'Malformed actual value allowed mutation.'
   Assert-Acceptance (@($R.Ledger|Where-Object{$_.ComputerName -ceq 'SIM-PC1' -and $_.Outcome -ceq 'Error'}).Count -eq 1) 'Malformed observed data not recorded as error.'
  }
 }
}catch{
 [void]$script:Cases.Add([pscustomobject]@{Id='fatal';Title='Harness setup or cleanup';Status='FAIL';Detail=$_.Exception.Message;Seconds=0});Write-Output ('FATAL '+$_.Exception.Message)
}finally{
 if(Get-Variable RecipeUi -Scope Script -ErrorAction SilentlyContinue){if($script:RecipeUi.Dialog){$script:RecipeUi.Dialog.Window.Close()}}
 if(Get-Variable ActiveRuns -Scope Script -ErrorAction SilentlyContinue){foreach($Pending in @($script:ActiveRuns)){if(-not $Pending.Process.HasExited){Request-RemoteOpsRunCancellation $Pending.CancelPath;while(-not $Pending.Process.HasExited){[void]$Pending.Process.WaitForExit(1000);$Pending.Process.Refresh()}}};$script:ActiveRuns.Clear()}
 if($script:UiTimer){$script:UiTimer.Stop()};if($script:OutputTimer){$script:OutputTimer.Stop()};if($script:Window){$script:Window.Close()}
 $env:APPDATA=$OldAppData;$env:REMOTEOPS_OFFLINE_STATE=$OldState;$env:REMOTEOPS_OFFLINE_RUNNER=$OldRunner
 $Failed=@($script:Cases|Where-Object Status -ne 'PASS')
 $BlockedFile=Join-Path $Sandbox 'state.json.blocked.jsonl';$Blocks=if(Test-Path -LiteralPath $BlockedFile){@(Get-Content -LiteralPath $BlockedFile).Count}else{0}
 $Summary=[pscustomobject]@{SubjectVersion=26;DeliveryVersion=27;Total=$script:Cases.Count;Passed=$script:Cases.Count-$Failed.Count;Failed=$Failed.Count;UnexpectedBoundaryBlocks=$Blocks;Seconds=[Math]::Round($Clock.Elapsed.TotalSeconds,2);SampledPeakCombinedWorkingSetMiB=[Math]::Round($script:PeakCombinedBytes/1MB,1);Sandbox=$Sandbox;OutputRoot=$OutputRoot;Cases=@($script:Cases);Runs=@($script:AllRuns);LiveEndpointTests=$false;ActualTransportTested=$false;CancellationButtonDialogTested=$false}
 [IO.File]::WriteAllText((Join-Path $OutputRoot 'summary.json'),($Summary|ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding $true))
 $script:Cases|Export-Csv (Join-Path $OutputRoot 'cases.csv') -NoTypeInformation -Encoding UTF8
 Write-Output ('SUMMARY '+$Summary.Passed+'/'+$Summary.Total+' PASS; blocks='+$Blocks+'; output='+$OutputRoot)
}
if($Failed.Count -or $Blocks){exit 1}
