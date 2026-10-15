$ErrorActionPreference='Stop';Set-StrictMode -Version 2;Add-Type -AssemblyName PresentationFramework
$Root=Split-Path $PSScriptRoot -Parent
foreach($Name in @('Packages','TargetGroups','TargetGroupsUi')){$P=Join-Path $Root ('RemoteOps.App\RemoteOps.'+$Name+'.ps1');if(Test-Path $P){. $P}}
function Assert($Ok,$Message){if(-not $Ok){throw $Message}}
function Click($Button){$Button.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))}
$Temp=Join-Path $env:TEMP ('ROGroupUI-'+[guid]::NewGuid().ToString('N'))
try{
 $Tabs=New-Object Windows.Controls.TabControl;$Ui=Initialize-RemoteOpsTargetGroupsUi $Tabs $Temp;$C=$Ui.Controls
 $C.Name.Text='Pilot';$C.Description.Text='Local fixture';$C.Targets.Text='PC-I PC-B';Click $C.Save
 Assert ($C.List.Items.Count -eq 1 -and $C.List.SelectedItem.Name -eq 'Pilot') 'UI save/list selection failed'
 $First=$C.List.SelectedItem;$C.Name.Text='Pilot updated';Click $C.Save
 Assert ($C.List.SelectedItem.Revision -eq 2) 'UI revision update failed'
 $External=@((Get-RemoteOpsTargetGroupCatalog $Temp).Groups|Where-Object Id -eq $First.Id)[0];$External.Name='Externally changed';$External=Save-RemoteOpsTargetGroup $Temp $External 2
 Click $C.Reload
 Assert ($C.Name.Text -eq 'Externally changed') 'Explicit reload left stale editor revision'
 Click $C.Copy
 Assert ($C.List.Items.Count -eq 1) 'Copy wrote before save'
 Click $C.Save
 Assert ($C.List.Items.Count -eq 2) 'Copy did not create new group'
 $Host1=New-Object Windows.Controls.StackPanel;$Box1=New-Object Windows.Controls.TextBox;$Box1.Text='PC-OLD'
 $Host2=New-Object Windows.Controls.StackPanel;$Box2=New-Object Windows.Controls.TextBox;$Box2.Text='PC-OTHER'
 $Picker1=Add-RemoteOpsTargetGroupPicker $Host1 $Box1 $Temp;$Picker2=Add-RemoteOpsTargetGroupPicker $Host2 $Box2 $Temp
 $Picker1.Picker.SelectedItem=@($Picker1.Picker.Items|Where-Object Id -eq $First.Id)[0]
 Assert ($Box1.Text -eq 'PC-OLD') 'Selection changed existing target input'
 Click $Picker1.Add
 Assert (($Box1.Text -split '\s+' -join ',') -eq 'PC-OLD,PC-I,PC-B') 'Add did not merge targets'
 Assert ($Box2.Text -eq 'PC-OTHER') 'Picker affected another form'
 Click $Picker1.Replace
 Assert (($Box1.Text -split '\s+' -join ',') -eq 'PC-I,PC-B') 'Replace did not set targets'
 $Group=@((Get-RemoteOpsTargetGroupCatalog $Temp).Groups|Where-Object Id -eq $First.Id)[0];Remove-RemoteOpsTargetGroup $Temp $Group.Id $Group.Revision
 Click $Picker1.Refresh
 Assert ($null -eq $Picker1.Picker.SelectedItem -and -not $Picker1.Add.IsEnabled) 'Missing group silently selected another'
 $C.Search.Text='no match';Assert ($C.List.Items.Count -eq 0) 'Group search failed'
 Write-Output 'PASS: real WPF group create/edit/copy/search, explicit merge/replace, independent target fields, deleted selection reset.'
}finally{if(Test-Path $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force}}
