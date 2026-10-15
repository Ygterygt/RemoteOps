$ErrorActionPreference='Stop'
$Root=Split-Path $PSScriptRoot -Parent;$Old=$env:APPDATA
$Temp=Join-Path $env:TEMP ('RemoteOpsV26Layout_'+[guid]::NewGuid().ToString('N'))
function Assert($Value,$Message){if(-not $Value){throw $Message}}
function Assert-Fits($Control,$Ancestor,[string]$Label){
 try{$P=$Control.TransformToAncestor($Ancestor).Transform((New-Object Windows.Point 0,0))}catch{throw ($Label+": "+$_.Exception.Message)}
 Assert ($Control.ActualHeight -gt 0 -and $Control.ActualWidth -gt 0) ($Label+' has no layout area')
 Assert ($P.X -ge -1 -and $P.Y -ge -1 -and ($P.X+$Control.ActualWidth) -le ($Ancestor.ActualWidth+1) -and ($P.Y+$Control.ActualHeight) -le ($Ancestor.ActualHeight+1)) ($Label+' clipped: '+$P+' size '+$Control.ActualWidth+','+$Control.ActualHeight+' within '+$Ancestor.ActualWidth+','+$Ancestor.ActualHeight)
}
try{
 New-Item -ItemType Directory $Temp -Force|Out-Null;$env:APPDATA=$Temp
 $Source=[IO.File]::ReadAllText((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1')).Replace('$script:AppRoot = Split-Path -Parent $PSCommandPath',('$script:AppRoot = '''+(Join-Path $Root 'RemoteOps.App')+'''')).Replace('$script:DataRoot = ''C:\Temp\YD_RemoteOps.App''',('$script:DataRoot = '''+$Temp+'\data''')).Replace('[void]$script:Window.ShowDialog()','')
 . ([scriptblock]::Create($Source));$script:OutputTimer.Stop()
 $script:MainTabs.SelectedItem=$script:RecipeUi.Tab;$C=$script:RecipeUi.Controls;$script:Window.ShowActivated=$false;$script:Window.Left=-20000;$script:Window.Top=-20000;$script:Window.Show();$Content=$script:Window.Content;[void]$Content.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle)
 foreach($Size in @(@(1280,810),@(1060,700),@(960,550))){
  $Content.Measure((New-Object Windows.Size $Size[0],$Size[1]));$Content.Arrange((New-Object Windows.Rect 0,0,$Size[0],$Size[1]));$Content.UpdateLayout()
  foreach($Name in @('Name','AddStep','Save','Preview')){Assert-Fits $C[$Name] $Content ($Name+' at '+($Size -join 'x'))}
  Assert ($C.Steps.ActualHeight -ge 24) ('No usable step list at '+($Size -join 'x'))
  $Node=$C.Save.Parent
  while($null -ne $Node -and $Node -ne $script:RecipeUi.Tab.Content){Assert ($Node -isnot [Windows.Controls.ScrollViewer]) 'Save is inside outer page scrolling';$Node=[Windows.Media.VisualTreeHelper]::GetParent($Node)}
 }
 $D=New-RemoteOpsRecipeDefinition 'Layout fixture';$D.Schema='RemoteOps.Recipe/3'
 $Gate=[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Layout gate';Operation='RecipeCondition';Values=(New-RemoteOpsConditionUiValues)}
 $Gate.Values.Checks[0].Path='HKLM\SOFTWARE\Fixture';$Gate.Values.Checks[0].Name='Version';$Gate.Values.Checks[0].Expected='16.0.444'
 $D.Steps=@($Gate,[pscustomobject]@{Id=[guid]::NewGuid().ToString();Name='Layout action';Operation='ServiceList';ConditionId=$Gate.Id;Values=[pscustomobject]@{Filter=''}})
 Open-RemoteOpsRecipeEditor $D;$Dialog=New-RemoteOpsRecipeStepDialog;$Dialog.Controls.Tabs.SelectedIndex=1
 $Dialog.Window.ShowActivated=$false;$Dialog.Window.Left=-20000;$Dialog.Window.Top=-20000;$Dialog.Window.Show()
 $Visual=$Dialog.Window.Content;$Visual.Measure((New-Object Windows.Size 648,580));$Visual.Arrange((New-Object Windows.Rect 0,0,648,580));$Visual.UpdateLayout()
 Assert-Fits $Dialog.Controls.Apply $Visual 'Dialog apply';Assert-Fits $Dialog.Controls.Cancel $Visual 'Dialog cancel'
 function Assert-NoPageScroll($Visual){
  if($Visual -is [Windows.Controls.ScrollViewer]){Assert ($Visual.ScrollableHeight -lt 1) 'Single registry check requires vertical scrolling'}
  for($I=0;$I -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($Visual);$I++){Assert-NoPageScroll ([Windows.Media.VisualTreeHelper]::GetChild($Visual,$I))}
 }
 Assert-NoPageScroll $Dialog.Controls.Tabs
 $Dialog.Window.Close()
 Assert ($script:ActiveRuns.Count -eq 0) 'Layout verification dispatched a request'
 Write-Output 'PASS real WPF main recipe layout 1280x810, 1060x700, 960x550: name/add/save/preview visible without page scrolling; no dispatch'
}finally{
 if(Get-Variable OutputTimer -Scope Script -ErrorAction SilentlyContinue){$script:OutputTimer.Stop()}
 if(Get-Variable Window -Scope Script -ErrorAction SilentlyContinue){$script:Window.Close()}
 $env:APPDATA=$Old
}


