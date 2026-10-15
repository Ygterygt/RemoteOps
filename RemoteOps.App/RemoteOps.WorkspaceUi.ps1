# Presentation only. Existing TabItems and their event handlers remain authoritative.
function Initialize-RemoteOpsWorkspaceNavigation {
 param($Window,$Tabs)
 $Tabs.ApplyTemplate() | Out-Null
 $HostPanel=$Tabs.Template.FindName('WorkspaceNavigationHost',$Tabs)
 $Current=$Tabs.Template.FindName('WorkspaceCurrentPage',$Tabs)
 $Entries=New-Object System.Collections.ArrayList
 foreach($Group in @(
  @('ÇALIŞTIR',@('PackagesTab','OperationTab','RecipesTab')),
  @('HAZIRLA',@('PackageEditorTab','TargetGroupsTab')),
  @('İNCELE VE KURTAR',@('ReportTab','HistoryTab','DiagnosticsTab','RecoveryTab'))
 )){
  $Label=New-Object Windows.Controls.TextBlock;$Label.Text=$Group[0];$Label.FontSize=11;$Label.FontWeight='SemiBold';$Label.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#62778A');$Label.Margin='12,18,8,7'
  [void]$HostPanel.Children.Add($Label)
  foreach($Name in $Group[1]){
   $Tab=@($Tabs.Items|Where-Object Name -eq $Name)[0]
   $Button=New-Object Windows.Controls.Button;$Button.Content=[string]$Tab.Header;$Button.Tag=$Tab;$Button.HorizontalContentAlignment='Left';$Button.Padding='12,10';$Button.Margin='0,0,0,4';$Button.BorderThickness=0
   $Button.Add_Click({$script:MainTabs.SelectedItem=$this.Tag})
   [void]$HostPanel.Children.Add($Button);[void]$Entries.Add([pscustomobject]@{Button=$Button;Tab=$Tab})
  }
 }
 $script:WorkspaceNavigation=[pscustomobject]@{Buttons=$Entries;Current=$Current;Tabs=$Tabs}
 $Tabs.Add_SelectionChanged({if([object]::ReferenceEquals($args[1].OriginalSource,$script:MainTabs)){Update-RemoteOpsWorkspaceNavigation}})
 Update-RemoteOpsWorkspaceNavigation
 $VersionPath=Join-Path (Split-Path $script:AppRoot -Parent) 'VERSION.json'
 $VersionLabel='YD RemoteOps'
 if(Test-Path -LiteralPath $VersionPath){try{$VersionLabel+=' · v'+([IO.File]::ReadAllText($VersionPath)|ConvertFrom-Json).version}catch{}}
 $Window.Title=$VersionLabel
 $Window.FindName('WorkspaceVersion').Text=$VersionLabel+' · Tek operatör'
}
function Update-RemoteOpsWorkspaceNavigation {
 $S=$script:WorkspaceNavigation
 foreach($Entry in $S.Buttons){
  $Selected=$Entry.Tab -eq $S.Tabs.SelectedItem
  $Entry.Button.Background=[Windows.Media.BrushConverter]::new().ConvertFromString($(if($Selected){'#E4F0FA'}else{'#FFFFFF'}))
  $Entry.Button.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString($(if($Selected){'#075A99'}else{'#31536B'}))
  $Entry.Button.FontWeight=if($Selected){'SemiBold'}else{'Normal'}
 }
 $S.Current.Text=[string]$S.Tabs.SelectedItem.Header
}
