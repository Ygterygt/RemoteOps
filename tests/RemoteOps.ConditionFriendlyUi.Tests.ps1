$ErrorActionPreference='Stop';$Root=Split-Path $PSScriptRoot -Parent;$Temp=Join-Path $env:TEMP ('ConditionUI_'+[guid]::NewGuid().ToString('N'));$Old=$env:APPDATA;$script:Window=$null;$script:OutputTimer=$null
function Assert($C,$M){if(-not $C){throw $M}}
function Click($B){$B.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))}
try{
 New-Item -ItemType Directory $Temp -Force|Out-Null;$env:APPDATA=Join-Path $Temp 'profiles'
 $Source=[IO.File]::ReadAllText((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1')).Replace('$script:AppRoot = Split-Path -Parent $PSCommandPath',('$script:AppRoot = '''+(Join-Path $Root 'RemoteOps.App')+'''' )).Replace('$script:DataRoot = ''C:\Temp\YD_RemoteOps.App''',('$script:DataRoot = '''+$Temp+'\data''')).Replace('[void]$script:Window.ShowDialog()','')
 . ([scriptblock]::Create($Source));$script:OutputTimer.Stop()
 $script:Dispatch=0;function Start-RemoteOpsRequest {$script:Dispatch++;throw 'Unexpected dispatch'}
 $C=$script:RecipeUi.Controls;Click $C.New;$script:RecipeUi.Draft.Steps=@([pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Custom';Operation='ServiceList';Values=(New-RemoteOpsRecipeStepValues 'ServiceList')});Update-RemoteOpsRecipeStepList;$Dialog=New-RemoteOpsRecipeStepDialog
 Assert ($C.AddCondition.Visibility -eq 'Collapsed') 'Separate condition flow visible'
 Assert ($script:RecipeUi.CurrentStep.Operation -eq 'ServiceList') 'Default action changed'
 Assert (@($C.Operation.Items|Where-Object Name -eq 'RecipeCondition').Count -eq 0) 'Standalone condition presets still offered'
 $Dialog.Controls.Enabled.IsChecked=$true;Set-RemoteOpsRecipeDialogCondition $Dialog;$Dialog.Controls.Tabs.SelectedIndex=1
 Assert ($C.RecipeEffectHint.Visibility -eq 'Collapsed') 'Unrelated action warning visible on condition'
 $R=$script:RecipeUi.ConditionInputs.Rows[0]
 Assert ($R.PathWrap.Visibility -eq 'Visible' -and $R.NameWrap.Visibility -eq 'Visible' -and $R.ExpectedWrap.Visibility -eq 'Visible' -and $R.ChoiceWrap.Visibility -eq 'Collapsed') 'Registry value form visibility'
 Assert ($R.KindWrap.Visibility -eq 'Visible') 'Primary check kind is not editable'
 Assert (-not $R.ContainsKey('ExpectedType')) 'Technical type editor still present'
 $R.Path.Text='HKLM\SOFTWARE\Fixture';$R.Name.Text='Version';$R.Expected.Text='16.0.444';Save-RemoteOpsRecipeStepForm
 Assert ($script:RecipeUi.CurrentStep.Values.Checks[0].ExpectedType -ceq 'Auto') 'New value not Auto'
 $R.Operator.SelectedItem='Exists';Save-RemoteOpsRecipeStepForm
 Assert ($R.ExpectedWrap.Visibility -eq 'Collapsed' -and $script:RecipeUi.CurrentStep.Values.Checks[0].Expected -ceq '') 'Existence retains hidden expected'
 $R.Operator.SelectedItem='Equals';Save-RemoteOpsRecipeStepForm
 Assert ($script:RecipeUi.CurrentStep.Values.Checks[0].Expected -ceq '16.0.444') 'Relevant value edit lost across operator selection'
 $R.Kind.SelectedItem='RegistryKey';Save-RemoteOpsRecipeStepForm
 Assert ($R.NameWrap.Visibility -eq 'Collapsed' -and $R.ExpectedWrap.Visibility -eq 'Collapsed') 'Key irrelevant fields visible'
 Assert ($script:RecipeUi.CurrentStep.Values.Checks[0].Path -ceq 'HKLM\SOFTWARE\Fixture') 'Registry path lost across relevant kinds'
 $R.Kind.SelectedItem='Service';$R.Name.Text='Spooler';$R.Operator.SelectedItem='State';$R.ExpectedChoice.SelectedItem='Stopped';Save-RemoteOpsRecipeStepForm
 $V=$script:RecipeUi.CurrentStep.Values.Checks[0]
 Assert ($R.PathWrap.Visibility -eq 'Collapsed' -and $R.NameWrap.Visibility -eq 'Visible' -and $R.ExpectedWrap.Visibility -eq 'Collapsed' -and $R.ChoiceWrap.Visibility -eq 'Visible') 'Service contextual form visibility'
 Assert ($V.Path -ceq '' -and $V.ExpectedType -ceq '' -and $V.Name -ceq 'Spooler' -and $V.Expected -ceq 'Stopped') 'Service fields/codes not normalized'
 $R.ExpectedChoice.SelectedItem='Start Pending';Save-RemoteOpsRecipeStepForm
 Assert ($script:RecipeUi.CurrentStep.Values.Checks[0].Expected -ceq 'Start Pending') 'Canonical pending state lost'
 $R.Operator.SelectedItem='Startup';$R.ExpectedChoice.SelectedItem='Manual';Save-RemoteOpsRecipeStepForm
 Assert ($script:RecipeUi.CurrentStep.Values.Checks[0].Expected -ceq 'Manual') 'Startup code not retained'
 $R.Kind.SelectedItem='RegistryValue';Save-RemoteOpsRecipeStepForm
 Assert ($script:RecipeUi.CurrentStep.Values.Checks[0].Name -ceq '' -and $script:RecipeUi.CurrentStep.Values.Checks[0].ExpectedType -ceq 'Auto') 'Service data leaked into registry'
 $script:RecipeUi.CurrentStep.Values.Checks[0].ExpectedType='REG_DWORD';$script:RecipeUi.CurrentStep.Values.Checks[0].Expected='1';Show-RemoteOpsRecipeStepForm;Save-RemoteOpsRecipeStepForm
 Assert ($script:RecipeUi.CurrentStep.Values.Checks[0].ExpectedType -ceq 'REG_DWORD') 'Legacy pinned type silently migrated'
 $script:RecipeUi.ConditionInputs.Rows[0].Expected.Text='16.0.444';Save-RemoteOpsRecipeStepForm
 Assert ($script:RecipeUi.CurrentStep.Values.Checks[0].ExpectedType -ceq 'Auto' -and $script:RecipeUi.Draft.Schema -ceq 'RemoteOps.Recipe/3') 'Edited legacy expectation not promoted to automatic comparison'
 $script:RecipeUi.ConditionInputs.Rows[0].Expected.Text='Running';Save-RemoteOpsRecipeStepForm
 Assert (((Get-RemoteOpsConditionPreviewLines $script:RecipeUi.CurrentStep) -join ' ') -match 'Running') 'Registry literal translated as service state'
 $Dialog.Window.Close()
 Assert ($script:Dispatch -eq 0) 'UI dispatched operation'
 Write-Host 'PASS friendly WPF unified entry, contextual visibility, selection normalization, raw codes and legacy type preservation'
}finally{if($script:OutputTimer){$script:OutputTimer.Stop()};if($script:Window){$script:Window.Close()};$env:APPDATA=$Old;if(Test-Path $Temp){Remove-Item $Temp -Recurse -Force}}
