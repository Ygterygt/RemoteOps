$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Packages.ps1')
$Path=Join-Path $Root 'RemoteOps.App\RemoteOps.TargetGroups.ps1';if(Test-Path $Path){. $Path}
function Assert($Ok,$Message){if(-not $Ok){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$Rejected=$false;try{& $Action|Out-Null}catch{$Rejected=$true};Assert $Rejected $Message}
$Temp=Join-Path $env:TEMP ('ROGroups-'+[guid]::NewGuid().ToString('N'))
$Previous=[Threading.Thread]::CurrentThread.CurrentCulture
try{
 [Threading.Thread]::CurrentThread.CurrentCulture=New-Object Globalization.CultureInfo tr-TR
 $Targets=@(ConvertTo-RemoteOpsTargets "PC-I, pc-i;pc-b`napp.example.com 10.20.30.40")
 Assert ($Targets.Count -eq 4 -and $Targets[0] -ceq 'PC-I') 'Ordinal normalization/order failed'
 foreach($Bad in @('PC-*','\\PC\C$','PC;whoami.exe/arg','::1','999.1.1.1','PC|whoami','PC..a','-bad','bad-',('PC'+[char]1))){Reject {ConvertTo-RemoteOpsTargets $Bad} ('Invalid target accepted: '+$Bad)}
 Reject {New-RemoteOpsTargetGroup 'Empty' '' ''} 'Empty group accepted'
 $G=New-RemoteOpsTargetGroup 'Test group' 'Description' 'PC-I PC-B'
 $Saved=Save-RemoteOpsTargetGroup $Temp $G 0
 Assert ($Saved.Revision -eq 1 -and $G.Revision -eq 0) 'Save mutated caller or wrong revision'
 $Saved.Name='Updated';$Next=Save-RemoteOpsTargetGroup $Temp $Saved 1
 Assert ($Next.Revision -eq 2) 'Revision did not increase'
 Reject {Save-RemoteOpsTargetGroup $Temp $Saved 1} 'Stale write accepted'
 $C=Get-RemoteOpsTargetGroupCatalog $Temp
 Assert ($C.Groups.Count -eq 1 -and $C.Groups[0].Name -eq 'Updated') 'Catalog reload failed'
 $Merge=@(Merge-RemoteOpsTargetGroup 'PC-A pc-i' @('PC-I','PC-B') Add)
 Assert (($Merge -join ',') -ceq 'PC-A,pc-i,PC-B') 'Add lost targets or normalization'
 Assert (((Merge-RemoteOpsTargetGroup 'PC-A' @('PC-B') Replace) -join ',') -eq 'PC-B') 'Replace failed'
 $SavedPath=Join-Path $Temp ($Next.Id+'.json')
 $Secret=$Next|Select-Object *;$Secret|Add-Member ProtectedPassword 'secret'
 Reject {Save-RemoteOpsTargetGroup $Temp $Secret 2} 'Credential field accepted'
 Reject {Remove-RemoteOpsTargetGroup $Temp $Next.Id 1} 'Stale delete accepted'
 Remove-RemoteOpsTargetGroup $Temp $Next.Id 2
 Reject {Save-RemoteOpsTargetGroup $Temp $Next 2} 'Deleted group resurrected'
 '{bad json'|Set-Content (Join-Path $Temp 'broken.json')
 $Other=New-RemoteOpsTargetGroup 'Other' '' PC1;$Other.Schema='bad';$Other|ConvertTo-Json|Set-Content (Join-Path $Temp ($Other.Id+'.json'))
 $C=Get-RemoteOpsTargetGroupCatalog $Temp
 Assert ($C.Groups.Count -eq 0 -and $C.Errors.Count -eq 2) 'Invalid records not isolated'
 $New=New-RemoteOpsTargetGroup 'Valid' '' PC1;$New.Name=@('invalid')
 Reject {Save-RemoteOpsTargetGroup $Temp $New 0} 'Non-string group name accepted'
 Reject {Remove-RemoteOpsTargetGroup $Temp '..\outside' 1} 'Invalid ID accepted'
 Write-Output 'PASS: targets/culture/validation, CRUD, revision conflicts, deleted records, merge semantics, corrupt catalog, credential exclusion.'
}finally{[Threading.Thread]::CurrentThread.CurrentCulture=$Previous;if(Test-Path $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force}}
