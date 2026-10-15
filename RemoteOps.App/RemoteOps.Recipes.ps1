. (Join-Path $PSScriptRoot 'RemoteOps.Packages.ps1')
. (Join-Path $PSScriptRoot 'RemoteOps.TargetGroups.ps1')
. (Join-Path $PSScriptRoot 'RemoteOps.Preview.ps1')
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Modules\RegistryPaths.ps1')
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Modules\RegistryValues.ps1')
. (Join-Path $PSScriptRoot 'RemoteOps.Conditions.ps1')
function Get-RemoteOpsRecipeOperations {
 @(
  [pscustomobject]@{Name='RecipeCondition';Title='Koşul grubu';Fields=@('Match','OnFalse','Checks')},
  [pscustomobject]@{Name='ServiceList';Title='Servisleri listele';Fields=@('Filter')},
  [pscustomobject]@{Name='ServiceControl';Title='Servisi başlat / durdur / yeniden başlat';Fields=@('ServiceName','Action')},
  [pscustomobject]@{Name='ServiceStartup';Title='Servis başlangıcını değiştir';Fields=@('ServiceName','StartupType')},
  [pscustomobject]@{Name='FilePush';Title='Dosya gönder';Fields=@('LocalPath','Path','Overwrite')},
  [pscustomobject]@{Name='FileCompare';Title='Dosya karşılaştır (farkta durur)';Fields=@('LocalPath','Path')},
  [pscustomobject]@{Name='FileDelete';Title='Yedekle ve sil';Fields=@('Path')},
  [pscustomobject]@{Name='RegistryRead';Title='Registry oku';Fields=@('RegistryPath','ValueName')},
  [pscustomobject]@{Name='RegistryEdit';Title='Registry düzenle';Fields=@('RegistryPath','ValueName','ValueType','Value')},
  [pscustomobject]@{Name='RegistryDelete';Title='Registry sil';Fields=@('RegistryPath','ValueName')},
  [pscustomobject]@{Name='PackageDeployment';Title='Kayıtlı paket uygula';Fields=@('Action','PackageDefinition')}
 )
}
function Get-RemoteOpsRecipeKeys {
 param($Object)
 if($Object -is [Collections.IDictionary]){return @($Object.Keys)}
 if($Object -isnot [pscustomobject]){throw 'Expected a data object.'};return @($Object.PSObject.Properties.Name)
}
function Assert-RemoteOpsRecipeFields {
 param($Object,[string[]]$Allowed,[string[]]$Required=$Allowed)
 $Keys=@(Get-RemoteOpsRecipeKeys $Object)
 foreach($Key in $Keys){if($Key -cnotin $Allowed){throw ('Unknown recipe field: '+$Key)}}
 foreach($Key in $Required){if($Key -cnotin $Keys){throw ('Missing recipe field: '+$Key)}}
}
function New-RemoteOpsRecipeDefinition {
 param([string]$Name='',[string]$Description='')
 [pscustomobject]@{Schema='RemoteOps.Recipe/1';Id=[guid]::NewGuid().ToString('D');Revision=0;Name=$Name;Description=$Description;CreatedAt=(Get-Date).ToString('o');UpdatedAt=(Get-Date).ToString('o');Steps=@()}
}
function Copy-RemoteOpsRecipeDefinition {
 param($Definition,[switch]$NewIdentity)
 $Copy=ConvertFrom-Json (ConvertTo-Json -InputObject $Definition -Depth 20)
 if($NewIdentity){
  $Copy.Id=[guid]::NewGuid().ToString('D');$Copy.Revision=0;$Copy.CreatedAt=(Get-Date).ToString('o');$Copy.UpdatedAt=$Copy.CreatedAt;$Map=@{}
  foreach($Step in $Copy.Steps){$Old=$Step.Id;$Step.Id=[guid]::NewGuid().ToString('D');$Map[$Old]=$Step.Id}
  foreach($Step in $Copy.Steps){$ConditionId=[string](Get-RemoteOpsPreviewValue $Step ConditionId '');if($ConditionId){if(-not $Map.ContainsKey($ConditionId)){throw 'Missing copied condition.'};$Step.ConditionId=$Map[$ConditionId]}}
 }
 return $Copy
}
function Assert-RemoteOpsRecipeDefinition {
 param($Definition)
 Assert-RemoteOpsRecipeFields $Definition @('Schema','Id','Revision','Name','Description','CreatedAt','UpdatedAt','Steps')
 if($Definition.Schema -cnotin @('RemoteOps.Recipe/1','RemoteOps.Recipe/2','RemoteOps.Recipe/3','RemoteOps.Recipe/4')){throw 'Unsupported recipe schema.'}
 $Guid=[guid]::Empty;if(-not [guid]::TryParse([string]$Definition.Id,[ref]$Guid)){throw 'Invalid recipe ID.'}
 if($Definition.Revision -isnot [int] -or $Definition.Revision -lt 0){throw 'Invalid recipe revision.'}
 if($Definition.Name -isnot [string] -or -not $Definition.Name.Trim() -or $Definition.Name.Length -gt 100 -or $Definition.Description -isnot [string] -or $Definition.Description.Length -gt 2000){throw 'Recipe name/description is invalid.'}
 foreach($Date in @($Definition.CreatedAt,$Definition.UpdatedAt)){$Parsed=[datetime]::MinValue;if(-not [datetime]::TryParse($Date,[ref]$Parsed)){throw 'Invalid recipe date.'}}
 if($Definition.Steps -isnot [array] -or $Definition.Steps.Count -lt 1 -or $Definition.Steps.Count -gt 20){throw 'A recipe needs 1 to 20 steps.'}
 $Seen=@{};$ActiveCondition=''
 foreach($Step in $Definition.Steps){
  Assert-RemoteOpsRecipeFields $Step @('Id','Name','Operation','Values','ConditionId','AutoName') @('Id','Name','Operation','Values')
  $G=[guid]::Empty;if(-not [guid]::TryParse([string]$Step.Id,[ref]$G) -or $Seen.ContainsKey($G.ToString())){throw 'Invalid or duplicate step ID.'};$Seen[$G.ToString()]=$true
  if($Step.Name -isnot [string] -or -not $Step.Name.Trim() -or $Step.Name.Length -gt 100){throw 'Invalid step name.'}
  if('AutoName' -cin @(Get-RemoteOpsRecipeKeys $Step)){if($Definition.Schema -cne 'RemoteOps.Recipe/4' -or $Step.AutoName -isnot [bool]){throw 'Automatic step names require schema 4 and boolean metadata.'}}
  $ConditionId=Get-RemoteOpsPreviewValue $Step ConditionId ''
  if($ConditionId -isnot [string]){throw 'Invalid condition reference.'}
  if($Definition.Schema -ceq 'RemoteOps.Recipe/1' -and ($Step.Operation -ceq 'RecipeCondition' -or 'ConditionId' -cin @(Get-RemoteOpsRecipeKeys $Step))){throw 'Conditions require recipe schema 2.'}
  if($Step.Operation -ceq 'RecipeCondition'){
   if($ConditionId){throw 'Nested condition rejected.'}
   Assert-RemoteOpsConditionValues $Step.Values
   if($Definition.Schema -cnotin @('RemoteOps.Recipe/3','RemoteOps.Recipe/4') -and @($Step.Values.Checks|Where-Object ExpectedType -ceq 'Auto').Count){throw 'Automatic registry comparisons require recipe schema 3.'}
   $ActiveCondition=$Step.Id;continue
  }
  if($ConditionId){if(-not $ActiveCondition -or $ConditionId -cne $ActiveCondition){throw 'Action condition must reference the immediately preceding condition block.'}}
  else{$ActiveCondition=''}
  $Meta=@(Get-RemoteOpsRecipeOperations|Where-Object Name -CEQ $Step.Operation);if($Meta.Count -ne 1){throw 'Unsupported recipe operation.'}
  Assert-RemoteOpsRecipeFields $Step.Values $Meta[0].Fields
  foreach($Key in $Meta[0].Fields){$V=Get-RemoteOpsPreviewValue $Step.Values $Key
   if($Key -eq 'PackageDefinition'){Assert-RemoteOpsRecipeFields $V @(Get-RemoteOpsRecipeKeys (New-RemoteOpsPackageDefinition)) @();foreach($Part in @('Install','Uninstall','Downgrade')){if($null -ne (Get-RemoteOpsPreviewValue $V $Part $null)){Assert-RemoteOpsRecipeFields (Get-RemoteOpsPreviewValue $V $Part) @(Get-RemoteOpsRecipeKeys (New-RemoteOpsPackageAction)) @()}};Assert-RemoteOpsPackageDefinition $V ([string](Get-RemoteOpsPreviewValue $Step.Values Action));continue}
   if($Key -eq 'Overwrite'){if($V -isnot [bool]){throw 'Overwrite must be boolean.'};continue}
   if($V -isnot [string] -or $V.Contains([char]0)){throw ('Invalid text field: '+$Key)}
   if($Key -notin @('Filter','Value','ValueName') -and -not $V.Trim()){throw ('Empty field: '+$Key)}
  }
  $V=$Step.Values
  if($Step.Operation -eq 'ServiceControl' -and (Get-RemoteOpsPreviewValue $V Action) -cnotin @('Start','Stop','Restart')){throw 'Invalid service action.'}
  if($Step.Operation -eq 'ServiceStartup' -and (Get-RemoteOpsPreviewValue $V StartupType) -cnotin @('Automatic','Manual','Disabled')){throw 'Invalid startup type.'}
  if($Step.Operation -eq 'PackageDeployment' -and (Get-RemoteOpsPreviewValue $V Action) -cnotin @('Install','Uninstall','Downgrade')){throw 'Invalid package action.'}
  if($Step.Operation -in @('ServiceControl','ServiceStartup') -and (Get-RemoteOpsPreviewValue $V ServiceName) -match '[*?\\/]'){throw 'A single exact service name is required.'}
  if($Step.Operation -like 'Registry*'){
   [void](ConvertTo-RemoteOpsRegistryPath ([string](Get-RemoteOpsPreviewValue $V RegistryPath)))
   if($Step.Operation -eq 'RegistryEdit'){$Type=Get-RemoteOpsPreviewValue $V ValueType;if($Type -cne 'Auto'){[void](ConvertTo-RemoteOpsRegistryData $Type (Get-RemoteOpsPreviewValue $V Value))}}
  }
 }
}
function Get-RemoteOpsRecipeRecordPath {
 param([string]$Root,[string]$Id)
 $Guid=[guid]::Empty;if(-not [guid]::TryParse($Id,[ref]$Guid)){throw 'Invalid recipe ID.'}
 $Full=[IO.Path]::GetFullPath($Root);$Current=$Full
 while($Current){if(Test-Path -LiteralPath $Current){if((Get-Item -LiteralPath $Current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse catalog path not allowed.'}};$Parent=Split-Path $Current -Parent;if($Parent -eq $Current){break};$Current=$Parent}
 $Path=Join-Path $Full ($Guid.ToString('D')+'.json')
 if(Test-Path -LiteralPath $Path){if((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse recipe file not allowed.'}}
 return $Path
}
function Get-RemoteOpsRecipeCatalog {
 param([string]$Root)
 $Recipes=New-Object Collections.ArrayList;$Issues=New-Object Collections.ArrayList
 if(Test-Path -LiteralPath $Root){foreach($File in Get-ChildItem -LiteralPath $Root -Filter '*.json' -File){try{
  if($File.Length -gt 1MB){throw 'Recipe file exceeds 1 MiB.'}
  [void](Get-RemoteOpsRecipeRecordPath $Root $File.BaseName)
  $D=ConvertFrom-Json ([IO.File]::ReadAllText($File.FullName));Assert-RemoteOpsRecipeDefinition $D
  if($File.BaseName -ine $D.Id -or $D.Revision -lt 1){throw 'Recipe identity mismatch.'};[void]$Recipes.Add($D)
 }catch{[void]$Issues.Add([pscustomobject]@{Path=$File.FullName;Message=$_.Exception.Message})}}}
 [pscustomobject]@{Recipes=@($Recipes|Sort-Object Name,Id);Issues=@($Issues)}
}
function Save-RemoteOpsRecipeDefinition {
 param([string]$Root,$Definition,[int]$ExpectedRevision=0)
 Assert-RemoteOpsRecipeDefinition $Definition;$Path=Get-RemoteOpsRecipeRecordPath $Root $Definition.Id
 New-Item -ItemType Directory -Path $Root -Force|Out-Null;$Lock=$null
 try{
  $Lock=[IO.File]::Open($Path+'.lock',[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  $Copy=Copy-RemoteOpsRecipeDefinition $Definition
  if(Test-Path -LiteralPath $Path){$Old=ConvertFrom-Json ([IO.File]::ReadAllText($Path));Assert-RemoteOpsRecipeDefinition $Old;if($Old.Revision -ne $ExpectedRevision){throw 'Recipe changed. Reload before saving.'};$Copy.Revision=$Old.Revision+1;$Copy.CreatedAt=$Old.CreatedAt}
  else{if($ExpectedRevision -ne 0){throw 'Recipe removed. Reload.'};$Copy.Revision=1}
  $Copy.UpdatedAt=(Get-Date).ToString('o');Write-RemoteOpsAtomicJson $Path $Copy 20;return $Copy
 }finally{if($null -ne $Lock){$Lock.Dispose()}}
}
function Remove-RemoteOpsRecipeDefinition {
 param([string]$Root,[string]$Id,[int]$ExpectedRevision)
 $Path=Get-RemoteOpsRecipeRecordPath $Root $Id;$Lock=$null
 try{$Lock=[IO.File]::Open($Path+'.lock',[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$Old=ConvertFrom-Json ([IO.File]::ReadAllText($Path));Assert-RemoteOpsRecipeDefinition $Old;if($Old.Revision -ne $ExpectedRevision){throw 'Recipe changed. Reload.'};Remove-Item -LiteralPath $Path -Force}finally{if($Lock){$Lock.Dispose()}}
}
function ConvertTo-RemoteOpsRecipeRequestBase64 {
 param($Request)
 $Json=ConvertTo-Json -InputObject $Request -Depth 20 -Compress;$Bytes=[Text.Encoding]::UTF8.GetBytes($Json)
 if($Bytes.Length -gt 1MB){throw 'Recipe request exceeds 1 MiB.'}
 $Base64=[Convert]::ToBase64String($Bytes);if($Base64.Length -gt 22000){throw 'Reçete isteği 22000 karakter sınırını aşıyor. Adım/veri kapsamını azaltın.'};return $Base64
}
function New-RemoteOpsRecipeRunSnapshot {
 param($Definition,[string[]]$Targets,$Profile,[bool]$CleanupLogs=$false)
 Assert-RemoteOpsRecipeDefinition $Definition;if($Definition.Revision -lt 1){throw 'Save the recipe before running.'};if($null -eq $Profile){throw 'Select a profile.'}
 $Seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
 $Hosts=@(foreach($Target in $Targets){$T=$Target.Trim();if($T -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$'){throw 'Invalid target computer.'};if($Seen.Add($T)){$T}})
 if(-not $Hosts.Count){throw 'Add at least one target.'}
 $S=[pscustomobject]@{Schema='RemoteOps.RecipeRun/1';Definition=(Copy-RemoteOpsRecipeDefinition $Definition);Targets=$Hosts;Identity=[pscustomobject]@{Domain=[string](Get-RemoteOpsPreviewValue $Profile Domain);UserName=[string](Get-RemoteOpsPreviewValue $Profile UserName);IsMain=[bool](Get-RemoteOpsPreviewValue $Profile IsMain $false)};CleanupLogs=$CleanupLogs;Hash=''}
 $S.Hash=Get-RemoteOpsPreviewHash @{Schema=$S.Schema;Definition=$S.Definition;Targets=$S.Targets;Identity=$S.Identity;CleanupLogs=$S.CleanupLogs}
 [void](ConvertTo-RemoteOpsRecipeRequestBase64 @{Operation='RecipeRun';Targets=$Hosts;Values=@{Snapshot=$S;Confirm='RECETE'}});return $S
}
function Assert-RemoteOpsRecipeRunSnapshot {
 param($Snapshot)
 Assert-RemoteOpsRecipeFields $Snapshot @('Schema','Definition','Targets','Identity','CleanupLogs','Hash')
 Assert-RemoteOpsRecipeFields $Snapshot.Identity @('Domain','UserName','IsMain')
 if($Snapshot.Schema -cne 'RemoteOps.RecipeRun/1' -or $Snapshot.CleanupLogs -isnot [bool] -or $Snapshot.Identity.IsMain -isnot [bool]){throw 'Invalid recipe snapshot.'}
 $Fresh=New-RemoteOpsRecipeRunSnapshot $Snapshot.Definition @($Snapshot.Targets) $Snapshot.Identity $Snapshot.CleanupLogs
 if($Fresh.Hash -cne $Snapshot.Hash -or $Fresh.Targets.Count -ne @($Snapshot.Targets).Count){throw 'Recipe snapshot changed.'}
}
