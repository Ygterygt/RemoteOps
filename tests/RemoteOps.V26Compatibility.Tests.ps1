$ErrorActionPreference='Stop'
$Root=Split-Path $PSScriptRoot -Parent
$Temp=Join-Path $env:TEMP ('V26Compatibility_'+[guid]::NewGuid().ToString('N'))
$Old=$env:APPDATA;$script:Window=$null;$script:OutputTimer=$null
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
function Action($Name,$Link=''){
 $Step=[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name=$Name;Operation='ServiceList';Values=[pscustomobject]@{Filter='Spooler'}}
 if($Link){$Step|Add-Member NoteProperty ConditionId $Link};return $Step
}
try{
 New-Item -ItemType Directory $Temp -Force|Out-Null;$env:APPDATA=Join-Path $Temp 'profiles'
 $Source=[IO.File]::ReadAllText((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1')).Replace('$script:AppRoot = Split-Path -Parent $PSCommandPath',('$script:AppRoot = '''+(Join-Path $Root 'RemoteOps.App')+'''' )).Replace('$script:DataRoot = ''C:\Temp\YD_RemoteOps.App''',('$script:DataRoot = '''+$Temp+'\data''')).Replace('[void]$script:Window.ShowDialog()','')
 . ([scriptblock]::Create($Source));$script:OutputTimer.Stop()
 $script:Dispatch=0;function Start-RemoteOpsRequest {$script:Dispatch++;throw 'Unexpected live dispatch'}
 foreach($Version in 1..3){
  $D=New-RemoteOpsRecipeDefinition ('Legacy '+$Version);$D.Schema='RemoteOps.Recipe/'+$Version;$D.Revision=1
  if($Version -eq 1){$D.Steps=@((Action '  Özel eski ad · aynen  '),(Action 'Second custom action'))}
  else{
   $Condition=[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='  Legacy shared gate  ';Operation='RecipeCondition';Values=(New-RemoteOpsConditionValues)}
   if($Version -eq 3){$Condition.Values.Checks[0]=[pscustomobject]@{Kind='RegistryValue';Path='HKLM\SOFTWARE\Fixture';Name='Value';Operator='Equals';ExpectedType='Auto';Expected='001'}}
   $D.Steps=@($Condition,(Action '  First custom action  ' $Condition.Id),(Action 'Second custom action' $Condition.Id),(Action 'Always action'))
  }
  Assert-RemoteOpsRecipeDefinition $D;$Hash=Get-RemoteOpsPreviewHash $D
  Open-RemoteOpsRecipeEditor $D
  for($Index=0;$Index -lt $script:RecipeUi.Controls.Steps.Items.Count;$Index++){$script:RecipeUi.Controls.Steps.SelectedIndex=$Index}
  $After=Get-RemoteOpsRecipeEditorDefinition
  Assert ((Get-RemoteOpsPreviewHash $After) -ceq $Hash) ('Untouched schema '+$Version+' mutated through editor')
  Assert ((Get-RemoteOpsPreviewHash $D) -ceq $Hash) ('Original schema '+$Version+' mutated')
  $script:RecipeUi.Controls.Steps.SelectedIndex=0;$Dialog=New-RemoteOpsRecipeStepDialog
  if($Dialog.Action.Operation -ne 'RecipeCondition'){$script:RecipeUi.Controls.StepName.Text='Cancelled name';$script:RecipeUi.Fields.Filter.Text='Cancelled filter'}
  $Dialog.Window.Close()
  Assert ((Get-RemoteOpsPreviewHash (Get-RemoteOpsRecipeEditorDefinition)) -ceq $Hash) ('Cancel changed schema '+$Version+' draft')
  if($Version -gt 1){
   $script:RecipeUi.Controls.Steps.SelectedIndex=1;Remove-RemoteOpsRecipeAction
   Assert ((Get-RemoteOpsPreviewHash (Get-RemoteOpsRecipeEditorDefinition)) -ceq $Hash) 'Shared gate action removal changed legacy scope'
   Move-RemoteOpsRecipeStep 1
   Assert ($script:RecipeUi.Draft.Steps[0].Name -ceq 'Always action' -and $script:RecipeUi.Draft.Steps[1].Id -ceq $Condition.Id) 'Shared condition did not move as intact block'
   Assert-RemoteOpsRecipeDefinition (Get-RemoteOpsRecipeEditorDefinition)
  }
 }
 $D=New-RemoteOpsRecipeDefinition 'Legacy generated-looking custom name';$Step=Action 'placeholder';$Step.Name=Get-RemoteOpsRecipeAutoName $Step;$D.Steps=@($Step)
 Open-RemoteOpsRecipeEditor $D;$ExpectedName=$Step.Name;$Dialog=New-RemoteOpsRecipeStepDialog;$script:RecipeUi.Fields.Filter.Text='Different subject';Complete-RemoteOpsRecipeStepDialog $Dialog
 Assert ($script:RecipeUi.Draft.Steps[0].Name -ceq $ExpectedName) 'Legacy custom name equal to generated text was overwritten'
 $D=New-RemoteOpsRecipeDefinition 'Explicit automatic label';$D.Schema='RemoteOps.Recipe/4';$Step=Action 'placeholder';$Step|Add-Member NoteProperty AutoName $true;$Step.Name=Get-RemoteOpsRecipeAutoName $Step;$D.Steps=@($Step)
 $Saved=Save-RemoteOpsRecipeDefinition $script:RecipeUi.Root $D 0
 Open-RemoteOpsRecipeEditor $Saved;$Dialog=New-RemoteOpsRecipeStepDialog;$script:RecipeUi.Fields.Filter.Text='ReopenedSubject';Complete-RemoteOpsRecipeStepDialog $Dialog
 Assert ($script:RecipeUi.Draft.Steps[0].Name -match 'ReopenedSubject') 'Saved automatic label did not refresh after reopening'
 Assert ($script:RecipeUi.Draft.Steps[0].AutoName -eq $true) 'Automatic label marker lost'
 $Condition=[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Automatic registry gate';Operation='RecipeCondition';Values=[pscustomobject]@{Match='All';OnFalse='Skip';Checks=@([pscustomobject]@{Kind='RegistryValue';Path='HKLM\SOFTWARE\Fixture';Name='Value';Operator='Equals';ExpectedType='Auto';Expected='001'})}}
 $D.Steps[0]|Add-Member NoteProperty ConditionId $Condition.Id;$D.Steps=@($Condition,$D.Steps[0]);Open-RemoteOpsRecipeEditor $D
 $Dialog=New-RemoteOpsRecipeStepDialog;$Dialog.Controls.Tabs.SelectedIndex=1;Complete-RemoteOpsRecipeStepDialog $Dialog
 Assert ($script:RecipeUi.Draft.Schema -ceq 'RemoteOps.Recipe/4') 'Automatic condition edit downgraded schema4'
 Assert-RemoteOpsRecipeDefinition (Get-RemoteOpsRecipeEditorDefinition)
 foreach($Version in 1..3){$Invalid=Copy-RemoteOpsRecipeDefinition $D;$Invalid.Schema='RemoteOps.Recipe/'+$Version;$Invalid.Steps=@((Action 'Valid legacy step'));$Invalid.Steps[0]|Add-Member NoteProperty AutoName $true;$Rejected=$false;try{Assert-RemoteOpsRecipeDefinition $Invalid}catch{$Rejected=$true};Assert $Rejected 'Legacy schema accepted automatic label metadata'}
 $Invalid=Copy-RemoteOpsRecipeDefinition $D;$Invalid.Steps[1].AutoName='true';$Rejected=$false;try{Assert-RemoteOpsRecipeDefinition $Invalid}catch{$Rejected=$true};Assert $Rejected 'Automatic label metadata accepted string boolean'
 $LongStep=[pscustomobject]@{Operation='FileDelete';Values=[pscustomobject]@{Path=('C:\'+('long-directory\'*20)+'file.txt')}}
 Assert ((Get-RemoteOpsRecipeAutoName $LongStep).Length -le 100) 'Generated name exceeds persisted step name limit'
 . (Join-Path $Root 'RemoteOps.App\RemoteOps.RecipeExecution.ps1')
 $D=New-RemoteOpsRecipeDefinition 'Shared cached gate';$D.Schema='RemoteOps.Recipe/2';$D.Revision=1
 $Condition=[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Gate evaluated once';Operation='RecipeCondition';Values=(New-RemoteOpsConditionValues)}
 $D.Steps=@($Condition,(Action 'First' $Condition.Id),(Action 'Second' $Condition.Id),(Action 'Always'))
 $Snapshot=New-RemoteOpsRecipeRunSnapshot $D @('SANDBOX-PC') ([pscustomobject]@{Domain='TEST';UserName='fixture';IsMain=$true}) $false
 $script:FixtureCalls=@();$script:FixtureState='Stopped'
 $Invoke={param($Request)
  $script:FixtureCalls+=,$Request.Operation
  $Rows=if($Request.Operation -ceq 'RecipeCondition'){
   $Evidence=Invoke-RemoteOpsConditionChecks $Request.Worker.Snapshot.Definition.Steps[$Request.Worker.StepIndex-1].Values $Request.Targets[0] $Request.Worker.StepOperationID -Probe {param($Check,$ComputerName)[pscustomobject]@{Exists=$true;ValueType='';Value='';State=$script:FixtureState;Startup='Automatic';Detail='sandbox'}}
   @($Evidence.Rows)
  }else{$script:FixtureState='Running';@([pscustomobject]@{ComputerName=$Request.Targets[0];OperationID=$Request.Worker.StepOperationID;Status='Success'})}
  New-RemoteOpsRecipeStepResult $Request $Rows @()
 }
 $Run=Invoke-RemoteOpsRecipeRun $Snapshot 'GUI-20261015-121500-ABCDEF' (Join-Path $Temp 'run') '' (Join-Path $Temp 'checkpoint') $Invoke
 Assert (($script:FixtureCalls -join ',') -ceq 'RecipeCondition,ServiceList,ServiceList,ServiceList') 'Legacy shared gate re-evaluated after first action changed fixture state'
 Assert (@($Run.Rows|Where-Object Status -eq 'Skipped').Count -eq 0) 'Legacy shared decision not reused'
 Assert ($script:Dispatch -eq 0) 'Editor dispatched a live request'
 Write-Host 'PASS v26 independent full-app sandbox: schema 1/2/3 exact untouched roundtrip, shared legacy links and custom name bytes preserved; no remote dispatch'
}finally{
 if($script:OutputTimer){$script:OutputTimer.Stop()};if($script:Window){$script:Window.Close()};$env:APPDATA=$Old
 if(Test-Path -LiteralPath $Temp){$Resolved=[IO.Path]::GetFullPath($Temp);if($Resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $Resolved -Recurse -Force}}
}
