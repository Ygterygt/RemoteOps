$ErrorActionPreference='Stop';$Root=Split-Path $PSScriptRoot -Parent;$Temp=Join-Path $env:TEMP ('RecipeUI_'+[guid]::NewGuid().ToString('N'));$Old=$env:APPDATA;$script:Window=$null;$script:OutputTimer=$null
function Assert($C,$M){if(-not $C){throw $M}}
function Click($B){$B.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))}
try{
 New-Item -ItemType Directory $Temp -Force|Out-Null;$env:APPDATA=Join-Path $Temp 'profiles'
 $Source=[IO.File]::ReadAllText((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1')).Replace('$script:AppRoot = Split-Path -Parent $PSCommandPath',('$script:AppRoot = '''+(Join-Path $Root 'RemoteOps.App')+'''' )).Replace('$script:DataRoot = ''C:\Temp\YD_RemoteOps.App''',('$script:DataRoot = '''+$Temp+'\data''')).Replace('[void]$script:Window.ShowDialog()','')
 . ([scriptblock]::Create($Source));$script:OutputTimer.Stop();Assert ($script:MainTabs.Items.Count -eq 9) 'Ninth tab missing'
 Assert ($script:RecipeUi.Controls.ContainsKey('EditorTabs')) 'Compact editor tabs missing'
 $P=[pscustomobject]@{Domain='TEST';UserName='operator';Display='TEST\operator';IsMain=$true;ProtectedPassword=''};$script:ProfileList.ItemsSource=@($P);$script:ProfileList.SelectedIndex=0
 $C=$script:RecipeUi.Controls;Click $C.New;$C.Name.Text='Pilot';$script:RecipeUi.Draft.Steps=@([pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Servisleri listele';Operation='ServiceList';Values=(New-RemoteOpsRecipeStepValues 'ServiceList')});Update-RemoteOpsRecipeStepList;$Dialog=New-RemoteOpsRecipeStepDialog
 $C.StepName.Text='List spooler';$script:RecipeUi.Fields.Filter.Text='Spooler';Complete-RemoteOpsRecipeStepDialog $Dialog;Save-RemoteOpsRecipeEditor
 Assert ((Get-RemoteOpsRecipeCatalog $script:RecipeUi.Root).Recipes.Count -eq 1) 'Save failed'
 $C.Targets.Text='PC1 PC2';$script:Dispatch=@();function Start-RemoteOpsRequest {param($Operation,$Values)$script:Dispatch+=,[pscustomobject]@{Operation=$Operation;Values=$Values}}
 $State=New-RemoteOpsRecipePreviewWindow (Get-RemoteOpsRecipeEditorDefinition) @('PC1','PC2');Click $State.Controls.Cancel;Assert ($script:Dispatch.Count -eq 0) 'Cancel dispatch'
 $State=New-RemoteOpsRecipePreviewWindow (Get-RemoteOpsRecipeEditorDefinition) @('PC1','PC2');Click $State.Controls.Start;Assert ($script:Dispatch.Count -eq 0 -and $State.Controls.Error.Text) 'Missing approval accepted';$State.Window.Close()
 $State=New-RemoteOpsRecipePreviewWindow (Get-RemoteOpsRecipeEditorDefinition) @('PC1','PC2');$State.Controls.Confirm.Text='RECETE';$P.Domain='OTHER';Click $State.Controls.Start;Assert ($script:Dispatch.Count -eq 0) 'Profile stale';$P.Domain='TEST';$State.Window.Close()
 $State=New-RemoteOpsRecipePreviewWindow (Get-RemoteOpsRecipeEditorDefinition) @('PC1','PC2');$State.Controls.Confirm.Text='RECETE';$C.Name.Text='Unsaved';Click $State.Controls.Start;Assert ($script:Dispatch.Count -eq 0) 'Unsaved edit accepted';$C.Name.Text='Pilot';$State.Window.Close()
 $State=New-RemoteOpsRecipePreviewWindow (Get-RemoteOpsRecipeEditorDefinition) @('PC1','PC2');$State.Controls.Confirm.Text='RECETE';Click $State.Controls.Start;Click $State.Controls.Start;Assert ($script:Dispatch.Count -eq 1 -and $script:Dispatch[0].Operation.Name -eq 'RecipeRun') 'Once-only snapshot dispatch'
 Write-Host 'PASS recipe WPF editor, saved preview, cancel, stale identity/edits, typed approval and once dispatch'
}finally{if($script:OutputTimer){$script:OutputTimer.Stop()};if($script:Window){$script:Window.Close()};$env:APPDATA=$Old;if(Test-Path $Temp){Remove-Item $Temp -Recurse -Force}}
