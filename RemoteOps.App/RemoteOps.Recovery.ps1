# Local-only discovery and immutable selection boundary for the recovery center.
. (Join-Path $PSScriptRoot 'RemoteOps.Backups.ps1')
function Get-RemoteOpsRecoveryHash {
 param([string]$Text)
 $Sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($Sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()}finally{$Sha.Dispose()}
}
function Assert-RemoteOpsRecoveryLocalPath {
 param([string]$Path,[string]$Root,[switch]$Directory)
 if(-not [IO.Path]::IsPathRooted($Path) -or $Path.StartsWith('\\') -or $Path -match '[*?]'){throw 'Local backup path is invalid.'}
 $Full=[IO.Path]::GetFullPath($Path);$Boundary=[IO.Path]::GetFullPath($Root).TrimEnd('\')
 if(-not $Full.StartsWith($Boundary+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Path is outside its backup root.'}
 $Current=$Full
 while($Current){
  if(Test-Path -LiteralPath $Current){$Item=Get-Item -LiteralPath $Current -Force -ErrorAction Stop;if($Item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point is not allowed in backup paths.'}}
  $Parent=Split-Path $Current -Parent;if($Parent -eq $Current){break};$Current=$Parent
 }
 if(-not(Test-Path -LiteralPath $Full)){throw 'Required backup or manifest is missing.'}
 $Item=Get-Item -LiteralPath $Full -Force
 if($Directory){if(-not $Item.PSIsContainer){throw 'Directory backup required.'}}elseif($Item.PSIsContainer){throw 'File backup required.'}
 return $Full
}
function Assert-RemoteOpsRecoveryRemotePath {
 param([string]$Path,[string]$Computer,[switch]$DrivePath)
 if($Path -match '[*?]' -or $Path -match '(^|\\)\.\.?($|\\)' -or $Path.Contains('/')){throw 'Unsafe destination path.'}
 if($DrivePath){if($Path -cnotmatch '^[A-Za-z]:\\[^:]+' ){throw 'Expected an absolute drive path.'}}
 else{if($Path -cnotmatch '^\\\\([^\\]+)\\[A-Za-z]\$\\[^:]+' -or $Matches[1] -ine $Computer){throw 'Destination host does not match the selected computer.'}}
}
function Read-RemoteOpsRecoveryTaskXml {
 param([string]$Path)
 $Settings=New-Object Xml.XmlReaderSettings;$Settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$Settings.XmlResolver=$null
 $Stream=New-Object IO.StreamReader($Path,(New-Object Text.UTF8Encoding($false,$true)),$true)
 $Reader=[Xml.XmlReader]::Create($Stream,$Settings)
 try{$Doc=New-Object Xml.XmlDocument;$Doc.XmlResolver=$null;$Doc.Load($Reader);if($Doc.DocumentElement.LocalName -ne 'Task' -or $Doc.DocumentElement.NamespaceURI -ne 'http://schemas.microsoft.com/windows/2004/02/mit/task'){throw 'Invalid scheduled task XML.'};return $Doc.OuterXml}finally{$Reader.Dispose();$Stream.Dispose()}
}
function Get-RemoteOpsRecoveryEntryKey {
 param($Entry)
 $Parts=@(foreach($P in $Entry.PSObject.Properties|Sort-Object Name){$P.Name+'='+[string]$P.Value})
 Get-RemoteOpsRecoveryHash (ConvertTo-Json -InputObject $Parts -Compress)
}
function Assert-RemoteOpsRecoveryEntry {
 param([string]$BasePath,[string]$Kind,$Entry,[string]$ManifestPath)
 $Computer=Get-RemoteOpsManifestField $Entry ComputerName
 if($Computer -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$'){throw 'Invalid computer name.'}
 switch($Kind){
  FileRestore {
   Assert-RemoteOpsRecoveryRemotePath $Entry.OriginalPath $Computer -DrivePath
   if($Entry.ItemType -notin @('File','Directory')){throw 'Unknown backup item type.'}
   $Status=Get-RemoteOpsManifestField $Entry BackupStatus
   if($Status -and $Status -ne 'Success'){throw 'Backup was not successful.'}
   $RunRoot=Split-Path $ManifestPath -Parent
   [void](Assert-RemoteOpsRecoveryLocalPath $Entry.BackupPath $RunRoot -Directory:($Entry.ItemType -eq 'Directory'))
  }
  FileRollback {
   if($Entry.Action -notin @('Move','Replace')){throw 'Unsupported file rollback action.'}
   Assert-RemoteOpsRecoveryRemotePath $Entry.OriginalPath $Computer
   if($Entry.Action -eq 'Move'){Assert-RemoteOpsRecoveryRemotePath $Entry.ChangedPath $Computer}
   [void](Assert-RemoteOpsRecoveryLocalPath $Entry.BackupPath (Split-Path $ManifestPath -Parent))
  }
  Registry {
   foreach($Name in @('RegistryKey','ValueName','OldExists')){if(-not $Entry.PSObject.Properties[$Name]){throw ('Missing registry field: '+$Name)}}
   $Path=Get-RemoteOpsRegistryManifestPath $Entry
   if($Path.HiveName -eq 'HKEY_CURRENT_USER'){throw 'Recorded HKU SID path is required.'}
   if($Entry.OldExists -notin @('True','False')){throw 'Invalid OldExists value.'}
   if($Entry.OldExists -eq 'True'){if(-not $Entry.PSObject.Properties['OldValue']){throw 'Missing recorded old registry value.'};$Type=Get-RemoteOpsManifestField $Entry OldType;if(-not $Type){$Type='REG_SZ'};[void](ConvertTo-RemoteOpsRegistryData $Type ([string]$Entry.OldValue))}
  }
  Service {
   if(-not $Entry.ObjectName -or $Entry.ObjectName -match '[\\/*?]'){throw 'Invalid service name.'}
   if($Entry.Action -eq 'StartStop'){if($Entry.OldState -notin @('Running','Stopped')){throw 'Unsupported previous service state.'}}
   elseif($Entry.Action -eq 'StartupType'){if($Entry.OldStartMode -notin @('Auto','Automatic','Manual','Disabled','Demand')){throw 'Invalid service start mode.'}}
   else{throw 'Unsupported service action.'}
  }
  ScheduledTask {
   if(-not $Entry.TaskName -or $Entry.TaskName -match '[\\/*?]' -or $Entry.TaskPath -notmatch '^\\' -or $Entry.TaskPath -match '[*?]' -or $Entry.TaskPath -match '(^|\\)\.\.($|\\)'){throw 'Invalid task name or folder.'}
   if($Entry.Action -eq 'EnableDisable'){if($Entry.OldEnabled -notin @('True','False')){throw 'Invalid previous enabled state.'}}
   elseif($Entry.Action -eq 'Delete'){$Xml=Assert-RemoteOpsRecoveryLocalPath $Entry.BackupXml (Join-Path $BasePath 'ServiceTaskRollbacks');[void](Read-RemoteOpsRecoveryTaskXml $Xml)}
   else{throw 'Unsupported task action.'}
  }
  default{throw 'This operation has no supported recovery.'}
 }
}
function Get-RemoteOpsRecoveryIndex {
 param([Parameter(Mandatory=$true)][string]$BasePath)
 $Records=New-Object Collections.ArrayList;$Issues=New-Object Collections.ArrayList
 $Receipts=@(Get-RemoteOpsRecoveryReceiptIndex $BasePath)
 foreach($Folder in @('DeleteBackups','FileRollbacks','RegistryRollback','ServiceTaskRollbacks')){
  $Root=Join-Path $BasePath $Folder
  if(-not(Test-Path -LiteralPath $Root)){continue}
  # Only known manifest layouts are traversed; junctions are never followed.
  $Files=@()
  if($Folder -in @('DeleteBackups','FileRollbacks')){
   foreach($Dir in Get-ChildItem -LiteralPath $Root -Directory -Force -ErrorAction SilentlyContinue){if(-not($Dir.Attributes -band [IO.FileAttributes]::ReparsePoint)){$Candidate=Join-Path $Dir.FullName 'manifest.csv';if(Test-Path -LiteralPath $Candidate){$Files+=Get-Item -LiteralPath $Candidate}}}
  }else{$Files=@(Get-ChildItem -LiteralPath $Root -File -Filter '*.csv' -ErrorAction SilentlyContinue)}
  foreach($File in $Files){
   $Rows=@();$Problem='';$Hash=''
   try{[void](Assert-RemoteOpsRecoveryLocalPath $File.FullName $Root);$Hash=(Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash;$Rows=@(Import-Csv -LiteralPath $File.FullName -Delimiter ';' -ErrorAction Stop);if(-not $Rows.Count){throw 'Empty manifest.'}}catch{$Problem=$_.Exception.Message}
   if(-not $Rows.Count){$Rows=@([pscustomobject]@{ComputerName='[unknown]'})}
   $Groups=@{}
   foreach($Row in $Rows){
    $Kind=switch($Folder){DeleteBackups{'FileRestore'}FileRollbacks{'FileRollback'}RegistryRollback{'Registry'}default{$T=Get-RemoteOpsManifestField $Row ObjectType;if($T -in @('Service','ScheduledTask')){$T}else{'Unsupported'}}}
    $Computer=Get-RemoteOpsManifestField $Row ComputerName '[unknown]';$Key=$Computer.ToUpperInvariant()+'|'+$Kind
    if(-not $Groups.ContainsKey($Key)){$Groups[$Key]=[pscustomobject]@{Computer=$Computer;Kind=$Kind;Rows=(New-Object Collections.ArrayList)}}
    [void]$Groups[$Key].Rows.Add($Row)
   }
   foreach($Group in $Groups.Values){
    $Errors=New-Object Collections.ArrayList;if($Problem){[void]$Errors.Add($Problem)}
    $Keys=@();foreach($Row in $Group.Rows){$Keys+=Get-RemoteOpsRecoveryEntryKey $Row;try{Assert-RemoteOpsRecoveryEntry $BasePath $Group.Kind $Row $File.FullName}catch{[void]$Errors.Add($_.Exception.Message)}}
    if(@($Keys|Select-Object -Unique).Count -ne $Keys.Count){[void]$Errors.Add('Duplicate manifest rows are ambiguous.')}
    $Relative=$File.FullName.Substring([IO.Path]::GetFullPath($BasePath).TrimEnd('\').Length).ToLowerInvariant()
    $Id=Get-RemoteOpsRecoveryHash ($Relative+'|'+$Group.Computer.ToUpperInvariant()+'|'+$Group.Kind)
    $Operation=switch($Group.Kind){Registry{'RegistryRollback'}Service{'ServiceTaskRollback'}ScheduledTask{'ServiceTaskRollback'}default{$Group.Kind}}
    $Summary=('{0} nesne | {1}' -f $Group.Rows.Count,(@($Group.Rows|ForEach-Object{if($_.PSObject.Properties['OriginalPath']){$_.OriginalPath}elseif($_.PSObject.Properties['RegistryKey']){$_.RegistryKey+' ['+$_.ValueName+']'}else{Get-RemoteOpsManifestField $_ ObjectName}}) -join '; '))
    $Stamps=@(foreach($Row in $Group.Rows){foreach($Name in @('BackupPath','BackupXml')){$Artifact=Get-RemoteOpsManifestField $Row $Name;if($Artifact -and -not $Errors.Count){$Item=Get-Item -LiteralPath $Artifact -Force -ErrorAction Stop;$Item.FullName+'|'+$Item.LastWriteTimeUtc.Ticks+'|'+$(if($Item.PSIsContainer){'directory'}else{$Item.Length})+'|'+$(if($Name -eq 'BackupXml'){(Get-FileHash -LiteralPath $Artifact -Algorithm SHA256).Hash}else{''})}}})
    $Stamp=Get-RemoteOpsRecoveryHash (@($Stamps|Sort-Object) -join ';')
    $Record=[pscustomobject]@{BackupStamp=$Stamp;AvailabilityLabel=$(if($Errors.Count){'Kullanılamaz'}else{'Yerel yedek hazır'});Id=$Id;Kind=$Group.Kind;Operation=$Operation;ComputerName=$Group.Computer;RecordedAt=$File.LastWriteTime;Summary=$Summary;ManifestPath=$File.FullName;ManifestHash=$Hash;EntryKeys=@($Keys|Sort-Object);Available=($Errors.Count -eq 0);UnavailableReason=(@($Errors|Select-Object -Unique) -join ' ')}
    $Presentation=Get-RemoteOpsRecoveryPresentation $BasePath $Record -Receipts $Receipts -UseCachedReceipts
    foreach($Name in @('LocalLabel','HistoryLabel','LiveLabel','NextAction')){$Record|Add-Member -NotePropertyName $Name -NotePropertyValue $Presentation.$Name}
    $Record.AvailabilityLabel=$Presentation.LocalLabel
    [void]$Records.Add($Record);if($Errors.Count){[void]$Issues.Add([pscustomobject]@{Path=$File.FullName;RecordId=$Id;Message=$Record.UnavailableReason})}
   }
  }
 }
 [pscustomobject]@{Records=@($Records|Sort-Object @{Expression='RecordedAt';Descending=$true},Id);Issues=@($Issues)}
}
function Get-RemoteOpsRecoveryDetails {
 param([string]$BasePath,$Record)
 $Index=Get-RemoteOpsRecoveryIndex $BasePath;$Fresh=@($Index.Records|Where-Object Id -eq $Record.Id)
 if($Fresh.Count -ne 1){throw 'Recovery record no longer exists.'}
 $R=$Fresh[0];$Entries=@(Import-Csv -LiteralPath $R.ManifestPath -Delimiter ';'|Where-Object{(Get-RemoteOpsRecoveryEntryKey $_) -in $R.EntryKeys -and $_.ComputerName -ieq $R.ComputerName})
 if($Entries.Count -ne @($R.EntryKeys).Count){throw 'Manifest rows changed during read.'}
 $Artifacts=@(foreach($Entry in $Entries){foreach($Name in @('BackupPath','BackupXml')){$P=Get-RemoteOpsManifestField $Entry $Name;if($P){$P}}})
 [pscustomobject]@{Record=$R;Entries=$Entries;BackupArtifacts=$Artifacts;Issues=@($Index.Issues|Where-Object RecordId -eq $R.Id)}
}
function Find-RemoteOpsRecoveryRecords {
 param([object[]]$Records,[string]$Computer='',[string]$Kind='',[string]$Availability='',[Nullable[datetime]]$From,[Nullable[datetime]]$To,[int]$Page=0,[int]$PageSize=50)
 $PageSize=[Math]::Max(1,[Math]::Min(200,$PageSize));$Page=[Math]::Max(0,$Page)
 $Filtered=@($Records|Where-Object{(-not $Computer -or $_.ComputerName.IndexOf($Computer,[StringComparison]::OrdinalIgnoreCase) -ge 0) -and (-not $Kind -or $_.Kind -eq $Kind) -and (-not $Availability -or ($Availability -eq 'Available' -and $_.Available) -or ($Availability -eq 'Unavailable' -and -not $_.Available)) -and ($null -eq $From -or $_.RecordedAt -ge $From) -and ($null -eq $To -or $_.RecordedAt -le $To)}|Sort-Object @{Expression='RecordedAt';Descending=$true},Id)
 $Max=[Math]::Max(0,[int][Math]::Ceiling($Filtered.Count/[double]$PageSize)-1);$Page=[Math]::Min($Page,$Max)
 [pscustomobject]@{Items=@($Filtered|Select-Object -Skip ($Page*$PageSize) -First $PageSize);Total=$Filtered.Count;Page=$Page;PageSize=$PageSize}
}
function Assert-RemoteOpsRecoverySelection {
 param([string]$BasePath,$Selection,[string[]]$Targets)
 if($Selection.Schema -cne 'RemoteOps.RecoverySelection/1' -or @($Targets).Count -ne 1 -or $Targets[0] -ine $Selection.ComputerName){throw 'Recovery selection target/schema mismatch.'}
 $Index=Get-RemoteOpsRecoveryIndex $BasePath;$Matches=@($Index.Records|Where-Object Id -eq $Selection.RecordId)
 if($Matches.Count -ne 1){throw 'Recovery record was removed.'};$R=$Matches[0]
 if(-not $R.Available){throw $R.UnavailableReason}
 if($R.Kind -cne $Selection.Kind -or $R.ManifestPath -ine $Selection.ManifestPath -or $R.ManifestHash -cne $Selection.ManifestHash -or $R.BackupStamp -cne $Selection.BackupStamp -or $R.ComputerName -ine $Selection.ComputerName -or (@($R.EntryKeys) -join '|') -cne (@($Selection.EntryKeys|Sort-Object) -join '|')){throw 'Recovery manifest or selection changed. Preview again.'}
 $Details=Get-RemoteOpsRecoveryDetails $BasePath $R
 if($Details.Record.ManifestHash -cne $Selection.ManifestHash -or -not $Details.Record.Available){throw 'Recovery data changed during validation.'}
 # Directory descendants are checked only for the selected restore, never for index browsing.
 foreach($Entry in $Details.Entries){if($R.Kind -eq 'FileRestore' -and $Entry.ItemType -eq 'Directory'){
  $Queue=New-Object 'Collections.Generic.Queue[string]';$Queue.Enqueue([string]$Entry.BackupPath)
  while($Queue.Count){foreach($Item in Get-ChildItem -LiteralPath $Queue.Dequeue() -Force -ErrorAction Stop){if($Item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Backup contains a reparse point.'};if($Item.PSIsContainer){$Queue.Enqueue($Item.FullName)}}}
 }}
 return $Details
}
function New-RemoteOpsRecoveryRequest {
 param([string]$BasePath,$Record)
 $Selection=[pscustomobject]@{Schema='RemoteOps.RecoverySelection/1';BackupStamp=$Record.BackupStamp;RecordId=$Record.Id;Kind=$Record.Kind;ManifestPath=$Record.ManifestPath;ManifestHash=$Record.ManifestHash;ComputerName=$Record.ComputerName;EntryKeys=@($Record.EntryKeys)}
 [void](Assert-RemoteOpsRecoverySelection $BasePath $Selection @($Record.ComputerName))
 $Values=@{Targets=$Record.ComputerName;ManifestPath=$Record.ManifestPath;RecoverySelection=$Selection;Confirm='';BackupPath=(Split-Path (Split-Path $Record.ManifestPath -Parent) -Leaf)}
 [pscustomobject]@{Operation=$Record.Operation;Values=$Values;Targets=@($Record.ComputerName);Selection=$Selection;Summary=$Record.Summary}
}
function Assert-RemoteOpsRecoveryDispatch {
 param([string]$BasePath,$Values,[string]$Operation,[string[]]$Targets)
 $Details=Assert-RemoteOpsRecoverySelection $BasePath $Values.RecoverySelection $Targets
 if($Details.Record.Operation -cne $Operation){throw 'Recovery operation mismatch.'}
 $Word=if($Operation -eq 'FileRestore'){'RESTORE'}else{'ROLLBACK'}
 if([string]$Values.Confirm -cne $Word){throw ('Recovery approval required: '+$Word)}
 return $Details
}

function Write-RemoteOpsRecoveryTaskXml {
 param([string]$Path,[string]$Text)
 $Settings=New-Object Xml.XmlReaderSettings;$Settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$Settings.XmlResolver=$null
 $String=New-Object IO.StringReader($Text);$Reader=[Xml.XmlReader]::Create($String,$Settings)
 try{$Doc=New-Object Xml.XmlDocument;$Doc.PreserveWhitespace=$true;$Doc.XmlResolver=$null;$Doc.Load($Reader)}finally{$Reader.Dispose();$String.Dispose()}
 if($Doc.DocumentElement.LocalName -ne 'Task' -or $Doc.DocumentElement.NamespaceURI -ne 'http://schemas.microsoft.com/windows/2004/02/mit/task'){throw 'Invalid scheduled task XML.'}
 $Options=New-Object Xml.XmlWriterSettings;$Options.Encoding=New-Object Text.UTF8Encoding($true);$Options.Indent=$false
 $Writer=[Xml.XmlWriter]::Create($Path,$Options)
 try{$Doc.Save($Writer)}finally{$Writer.Dispose()}
}

# Local presentation evidence only; this never queries or changes a remote target.
function Write-RemoteOpsRecoveryReceipt {
 param([string]$ReportRoot,$Selection,$Result,[string]$OperationID)
 $Rows=@();if($null -ne $Result.PSObject.Properties['Rows']){$Rows=@($Result.Rows)}elseif($Result.ResultCsv -and (Test-Path -LiteralPath $Result.ResultCsv)){$Rows=@(Import-Csv -LiteralPath $Result.ResultCsv -Delimiter ';' -Encoding UTF8)}
 $Rows=@($Rows|Where-Object {(Get-RemoteOpsManifestField $_ ComputerName (Get-RemoteOpsManifestField $_ IstemciAdi)) -ieq $Selection.ComputerName})
 $Success=$Rows.Count -ge @($Selection.EntryKeys).Count -and $Rows.Count -gt 0 -and @($Rows|Where-Object {(Get-RemoteOpsManifestField $_ Status (Get-RemoteOpsManifestField $_ Durum)) -ne 'Success'}).Count -eq 0
 $Receipt=[pscustomobject]@{Schema='RemoteOps.RecoveryReceipt/1';OperationID=$OperationID;RecordedAt=(Get-Date).ToString('o');RecordId=$Selection.RecordId;ManifestHash=$Selection.ManifestHash;BackupStamp=$Selection.BackupStamp;ComputerName=$Selection.ComputerName;Kind=$Selection.Kind;EntryKeys=@($Selection.EntryKeys);ReportedSuccess=$Success}
 Write-RemoteOpsAtomicJson (Join-Path $ReportRoot 'RecoveryReceipt.json') $Receipt
}
function Get-RemoteOpsRecoveryReceiptIndex {
 param([string]$BasePath)
 $Items=@();$Root=Join-Path $BasePath 'Logs\Operations'
 foreach($Operation in @('FileRestore','FileRollback','RegistryRollback','ServiceTaskRollback')){
  $Folder=Join-Path $Root $Operation;if(-not(Test-Path -LiteralPath $Folder -PathType Container)){continue}
  try{[void](Assert-RemoteOpsRecoveryLocalPath $Folder $Root -Directory)}catch{continue}
  foreach($Run in @(Get-ChildItem -LiteralPath $Folder -Directory -ErrorAction SilentlyContinue)){
   try{
    if($Run.Name -cnotmatch '^[A-Za-z0-9_-]+$'){continue}
    $Path=Join-Path $Run.FullName 'RecoveryReceipt.json';if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){continue}
    [void](Assert-RemoteOpsRecoveryLocalPath $Path $Root)
    if((Get-Item -LiteralPath $Path).Length -gt 1048576){continue}
    $Item=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json -ErrorAction Stop
    $When=[datetimeoffset]::MinValue
    if($Item.Schema -cne 'RemoteOps.RecoveryReceipt/1' -or $Item.OperationID -cne $Run.Name -or $Item.ReportedSuccess -isnot [bool] -or -not [datetimeoffset]::TryParse([string]$Item.RecordedAt,[ref]$When)){continue}
    $Expected=switch($Item.Kind){Registry{'RegistryRollback'}Service{'ServiceTaskRollback'}ScheduledTask{'ServiceTaskRollback'}default{[string]$Item.Kind}}
    if($Expected -cne $Operation){continue}
    $Item|Add-Member -NotePropertyName SortTime -NotePropertyValue $When.UtcTicks;$Items+=@($Item)
   }catch{continue}
  }
 }
 return @($Items|Sort-Object SortTime -Descending)
}
function Get-RemoteOpsRecoveryPresentation {
 param([string]$BasePath,$Record,[object[]]$Receipts,[switch]$UseCachedReceipts)
 $Local='Yerel yedek hazır';$Action='Geri alma önizlemesinde kapsamı inceleyin.'
 if(-not $Record.Available){
  $Local='Yedek okunamıyor veya doğrulanamıyor';$Action='Ayrıntıdaki özgün hatayı ve yerel yedek dosyalarını kontrol edin.'
  if($Record.UnavailableReason -match '(?i)missing|not found'){$Local='Gerekli yedek veya manifest eksik';$Action='Eksik dosyayı özgün yedekten sağlayıp listeyi yenileyin.'}
  elseif($Record.UnavailableReason -match '(?i)XML|Unicode|encoding|Load'){$Local='Görev XML yedeği okunamıyor';$Action='XML dosyasının bütünlüğünü kontrol edin; özgün hata ayrıntıda korunur.'}
 }
 if(-not $UseCachedReceipts){$Receipts=@(Get-RemoteOpsRecoveryReceiptIndex $BasePath)}
 $Matches=@($Receipts|Where-Object {$_.RecordId -ceq $Record.Id -and $_.ComputerName -ieq $Record.ComputerName -and $_.Kind -ceq $Record.Kind -and $_.ManifestHash -ceq $Record.ManifestHash -and $_.BackupStamp -ceq $Record.BackupStamp -and (@($_.EntryKeys|Sort-Object)-join '|') -ceq (@($Record.EntryKeys|Sort-Object)-join '|')})
 $History='Bu yedek için eşleşen yerel geri alma sonuç kaydı yok.'
 if($Matches.Count){$Latest=$Matches[0];$Date=([datetimeoffset]::Parse($Latest.RecordedAt)).ToLocalTime().ToString('dd.MM.yyyy HH:mm');$History='Son geri alma: '+$(if($Latest.ReportedSuccess){'başarılı bildirildi'}else{'tam başarı doğrulanamadı'})+' · '+$Date+' (yerel sonuç kaydı)'}
 return [pscustomobject]@{LocalLabel=$Local;HistoryLabel=$History;LiveLabel='Hedefin güncel durumu sorgulanmadı.';NextAction=$Action}
}
