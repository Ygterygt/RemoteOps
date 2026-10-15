$ErrorActionPreference='Stop';$Root=Split-Path $PSScriptRoot -Parent;$Temp=Join-Path $env:TEMP ('ConditionUI_'+[guid]::NewGuid().ToString('N'));$Old=$env:APPDATA;$script:Window=$null;$script:OutputTimer=$null
function Assert($C,$M){if(-not $C){throw $M}}
function Click($B){$B.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))}
try{
 New-Item -ItemType Directory $Temp -Force|Out-Null;$env:APPDATA=Join-Path $Temp 'profiles'
 $Source=[IO.File]::ReadAllText((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1')).Replace('$script:AppRoot = Split-Path -Parent $PSCommandPath',('$script:AppRoot = '''+(Join-Path $Root 'RemoteOps.App')+'''' )).Replace('$script:DataRoot = ''C:\Temp\YD_RemoteOps.App''',('$script:DataRoot = '''+$Temp+'\data''')).Replace('[void]$script:Window.ShowDialog()','')
 . ([scriptblock]::Create($Source));$script:OutputTimer.Stop()
 $script:Dispatch=0;function Start-RemoteOpsRequest {$script:Dispatch++;throw 'Unexpected dispatch'}
 $C=$script:RecipeUi.Controls;Click $C.New;$C.Name.Text='Conditional fixture'
 Assert (@($C.Operation.Items|Where-Object Name -eq 'RecipeCondition').Count -eq 0) 'Standalone condition action still offered'
 $Step=[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Custom action';Operation='ServiceList';Values=(New-RemoteOpsRecipeStepValues 'ServiceList')}
 $script:RecipeUi.Draft.Steps=@($Step);Update-RemoteOpsRecipeStepList
 $Original=Get-RemoteOpsPreviewHash $script:RecipeUi.Draft
 $Dialog=New-RemoteOpsRecipeStepDialog;$C.StepName.Text='Cancelled';$Dialog.Controls.Enabled.IsChecked=$true;Set-RemoteOpsRecipeDialogCondition $Dialog;$Dialog.Window.Close()
 Assert ((Get-RemoteOpsPreviewHash $script:RecipeUi.Draft) -ceq $Original) 'Cancel changed draft'
 $Dialog=New-RemoteOpsRecipeStepDialog;$Dialog.Controls.Enabled.IsChecked=$true;Set-RemoteOpsRecipeDialogCondition $Dialog;$Dialog.Controls.Tabs.SelectedIndex=1
 $F=$script:RecipeUi.ConditionInputs;$F.Rows[0].Kind.SelectedItem='RegistryKey';$F.Rows[0].Path.Text='HKLM\SOFTWARE';$F.Match.SelectedItem='Any';$F.OnFalse.SelectedItem='Skip'
 Assert ($F.Rows[0].KindWrap.Visibility -eq 'Visible') 'Primary check kind unavailable inside action'
 $AddCheck=@($C.Fields.Children|Where-Object{$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Ek kontrol'})[0];Click $AddCheck
 Assert ($script:RecipeUi.ConditionInputs.Rows.Count -eq 2) 'Multiple check editor'
 $script:RecipeUi.ConditionInputs.Rows[1].Kind.SelectedItem='Service';$script:RecipeUi.ConditionInputs.Rows[1].Name.Text='Spooler'
 $Boxes=@($C.Fields.Children|Where-Object{$_ -is [Windows.Controls.StackPanel] -and @($_.Children|Where-Object{$_ -is [Windows.Controls.Button]}).Count -gt 0});$RemoveCheck=@($Boxes[1].Children|Where-Object{$_ -is [Windows.Controls.Button]})[0];Click $RemoveCheck
 Assert ($script:RecipeUi.ConditionInputs.Rows.Count -eq 1) 'Remove check editor'
 Assert ($null -ne $script:RecipeUi.ConditionInputs.Match.ItemTemplate) 'Translated choice template missing'
 $Translated=$script:RecipeUi.ConditionInputs.Match.ItemTemplate.LoadContent();$Translated.DataContext='Any';$Translated.Measure((New-Object Windows.Size 500,100));$Translated.UpdateLayout()
 Assert ($Translated.Text -ceq 'Herhangi biri sağlansın') 'Turkish choice label'
 Complete-RemoteOpsRecipeStepDialog $Dialog
 Assert ($Dialog.Applied) ('Condition apply failed: '+$Dialog.Controls.Error.Text)
 $D=Get-RemoteOpsRecipeEditorDefinition;Assert ($D.Steps.Count -eq 2 -and $D.Steps[1].ConditionId -ceq $D.Steps[0].Id) 'Owned condition not immediately before action'
 Assert ($D.Steps[1].Name -ceq 'Custom action') 'Existing custom name changed'
 Assert ($C.Steps.Items.Count -eq 1) 'Owned condition leaked into main action list'
 Assert ($D.Schema -ceq 'RemoteOps.Recipe/3' -and $D.Steps[0].Values.Match -ceq 'Any') 'Condition schema/fields lost'
 Save-RemoteOpsRecipeEditor;Assert ((Get-RemoteOpsRecipeEditorDefinition).Steps[1].ConditionId -ceq $D.Steps[0].Id) 'Save roundtrip lost link'
 Assert ((Get-RemoteOpsConditionPreviewLines $D.Steps[0]) -join ' ' -match 'HKLM') 'Preview missing checks'
 # Clearing the optional custom name creates a stable generated name and follows changed fields on the next apply.
 $Dialog=New-RemoteOpsRecipeStepDialog;$C.StepName.Text='';$script:RecipeUi.Fields.Filter.Text='Spooler';Complete-RemoteOpsRecipeStepDialog $Dialog
 Assert ($script:RecipeUi.Draft.Steps[1].Name -match 'Spooler') 'Automatic name missing subject'
 $Dialog=New-RemoteOpsRecipeStepDialog;Assert ($C.StepName.Text -ceq '') 'Generated name treated as custom';$script:RecipeUi.Fields.Filter.Text='BITS';Complete-RemoteOpsRecipeStepDialog $Dialog
 Assert ($script:RecipeUi.Draft.Steps[1].Name -match 'BITS') 'Automatic name stale'
 $Dialog=New-RemoteOpsRecipeStepDialog
 Assert ($null -ne $C.CustomizeName -and -not $C.CustomizeName.IsChecked -and $C.StepNameWrap.Visibility -eq 'Collapsed') 'Automatic step asks for custom name'
 $C.CustomizeName.IsChecked=$true;Assert ($C.StepNameWrap.Visibility -eq 'Visible') 'Custom name input remains hidden';$C.StepName.Text='  Exact custom title  ';Complete-RemoteOpsRecipeStepDialog $Dialog
 $Dialog=New-RemoteOpsRecipeStepDialog;Assert ($C.CustomizeName.IsChecked -and $C.StepName.Text -ceq '  Exact custom title  ') 'Custom checkbox/name not restored'
 $C.CustomizeName.IsChecked=$false;Assert ($C.StepNameWrap.Visibility -eq 'Collapsed') 'Unchecked custom input visible';$script:RecipeUi.Fields.Filter.Text='AutoAgain';Complete-RemoteOpsRecipeStepDialog $Dialog
 Assert ($script:RecipeUi.Draft.Steps[1].AutoName -eq $true -and $script:RecipeUi.Draft.Steps[1].Name -match 'AutoAgain') 'Unchecking did not restore automatic naming'
 Click $C.RemoveStep;Assert ($script:RecipeUi.Draft.Steps.Count -eq 0) 'Owned pair removal left condition'
 Assert ($script:Dispatch -eq 0) 'UI dispatched operation'
 Write-Host 'PASS condition WPF structured editor, links, scope guards, saved roundtrip and no dispatch'
}finally{if($script:OutputTimer){$script:OutputTimer.Stop()};if($script:Window){$script:Window.Close()};$env:APPDATA=$Old;if(Test-Path $Temp){Remove-Item $Temp -Recurse -Force}}
