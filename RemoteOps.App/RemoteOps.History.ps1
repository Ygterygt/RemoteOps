# Read-only history; never dispatches a remote operation.
function Resolve-RemoteOpsHistoryPath {
    param([string]$BasePath,[string]$Path,[ValidateSet('Operations','Ledger','PulledLogs','PulledFiles')][string]$Scope='Operations')
    $Relative=switch($Scope){Operations{'Logs\Operations'} Ledger{'Logs\Reports\Ledger'} default{$Scope}}
    $Allowed=[IO.Path]::GetFullPath((Join-Path $BasePath $Relative)).TrimEnd('\')
    $Full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    if(-not ($Full.Equals($Allowed,[StringComparison]::OrdinalIgnoreCase) -or $Full.StartsWith($Allowed+'\',[StringComparison]::OrdinalIgnoreCase))){throw 'Path outside allowed data directory.'}
    # Inspect all ancestors including the configured base; never follow junctions.
    $Current=$Full
    while($Current){
        if(Test-Path -LiteralPath $Current){
            $Item=Get-Item -LiteralPath $Current -Force -ErrorAction Stop
            if(($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Reparse paths are not allowed.'}
        }
        $Parent=[IO.Path]::GetDirectoryName($Current)
        if($Parent -eq $Current){break};$Current=$Parent
    }
    return $Full
}
function Read-RemoteOpsHistoryCsv {
    param([string]$Path,[switch]$Ledger)
    $Rows=@(Import-Csv -LiteralPath $Path -Delimiter ';' -Encoding UTF8 -ErrorAction Stop)
    if($Rows.Count -eq 0){
        $Header=Get-Content -LiteralPath $Path -Encoding UTF8 -TotalCount 1
        if(-not $Ledger -and $Header -match '(?:^|;)"?(?:Status|Durum|ExecutionStatus|CollectionStatus|OperasyonSonucu)"?(?:;|$)'){return @()}
        throw 'Empty or malformed result file.'
    }
    $Names=@($Rows[0].PSObject.Properties.Name)
    if($Ledger -and -not ($Names -contains 'ComputerName')){throw 'Ledger computer column is missing.'}
    if($Ledger -and (-not ($Names -contains 'OperationID') -or -not ($Names -contains 'Outcome'))){throw 'Ledger columns are missing.'}
    if(-not $Ledger -and -not @($Names|Where-Object{$_ -in @('Status','Durum','ExecutionStatus','CollectionStatus','OperasyonSonucu')}).Count){throw 'Result status column is missing.'}
    return $Rows
}
function Get-RemoteOpsHistoryRowComputer {
    param($Row)
    $Computer=Get-RemoteOpsRowValue $Row @('ComputerName','IstemciAdi','ClientName')
    if($Computer){return $Computer}
    return '(çalışma)'
}
function ConvertTo-RemoteOpsHistoryTargets {
    param([object[]]$Rows,[object[]]$Ledger=@())
    $Groups=@{}
    foreach($Row in @($Rows)){
        $Computer=Get-RemoteOpsHistoryRowComputer $Row
        if(-not $Computer){continue}
        if(-not $Groups.ContainsKey($Computer)){$Groups[$Computer]=New-Object System.Collections.ArrayList}
        [void]$Groups[$Computer].Add($Row)
    }
    $Targets=@{}
    foreach($Computer in $Groups.Keys){
        $Targets[$Computer]=[pscustomobject]@{ComputerName=$Computer;Outcome=(Get-RemoteOpsComputerOutcome @($Groups[$Computer]));Detail=''}
    }
    foreach($Row in @($Ledger)){
        $Computer=Get-RemoteOpsRowValue $Row @('ComputerName')
        if($Computer){$Targets[$Computer]=[pscustomobject]@{ComputerName=$Computer;Outcome=(Get-RemoteOpsRowValue $Row @('Outcome'));Detail=(Get-RemoteOpsRowValue $Row @('Detail'))}}
    }
    return @($Targets.Values|Sort-Object ComputerName)
}
function Get-RemoteOpsHistoryResultPaths {
    param([string]$BasePath,[string]$ReportRoot)
    [void](Resolve-RemoteOpsHistoryPath $BasePath $ReportRoot)
    $Id=[IO.Path]::GetFileName($ReportRoot)
    # Fixed producer names only: no arbitrary CSV/HTML files from the directory.
    $Suffix='ApplicationCheck|InstalledApplications|PackageOperations|PackageDeployment|FilePull|FilePush|FileDelete|FileCompare|FileRestore|FileRollback|FileBrowser|EndpointInventory|HealthCheck|RegistryOperations|RegistryRollback|ServiceList|ServiceControl|ServiceStartup|ServiceTaskRollback|ScheduledTaskList|ScheduledTaskAction|ScheduledTaskDelete|ProcessQuery|ProcessKill'
    $Pattern='^(?:Results|Error|'+[regex]::Escape($Id)+'(?:_(?:'+$Suffix+')|-access))\.csv$'
    return @(Get-ChildItem -LiteralPath $ReportRoot -File -Filter '*.csv' -ErrorAction Stop|Where-Object{$_.Name -match $Pattern}|Sort-Object Name|ForEach-Object{Resolve-RemoteOpsHistoryPath $BasePath $_.FullName})
}
function Test-RemoteOpsHistoryRowIdentity {
    param($Row,[string]$OperationID)
    $Id=Get-RemoteOpsRowValue $Row @('OperationID')
    return (-not $Id -or $Id -match ('^'+[regex]::Escape($OperationID)+'(?:-\d{4,})?(?:-S\d{2,})?$'))
}
function Get-RemoteOpsHistoryIndex {
    param([string]$BasePath)
    $Issues=New-Object System.Collections.ArrayList;$Runs=@{}
    $LedgerRoot=Join-Path $BasePath 'Logs\Reports\Ledger'
    if(Test-Path -LiteralPath $LedgerRoot){
        try{
            [void](Resolve-RemoteOpsHistoryPath $BasePath $LedgerRoot Ledger)
            foreach($File in @(Get-ChildItem -LiteralPath $LedgerRoot -File -Filter '*.csv')){
                try{
                    [void](Resolve-RemoteOpsHistoryPath $BasePath $File.FullName Ledger)
                    $Rows=@(Read-RemoteOpsHistoryCsv $File.FullName -Ledger)
                    $Ids=@($Rows|ForEach-Object{[string]$_.OperationID}|Select-Object -Unique)
                    if($Ids.Count -ne 1 -or $Ids[0] -cnotmatch '^[A-Za-z0-9_-]+$'){throw 'Invalid or mixed run identity.'}
                    $Id=$Ids[0];$First=$Rows[0]
                    if($Runs.ContainsKey($Id)){throw 'Duplicate ledger run identity.'}
                    $Runs[$Id]=[pscustomobject]@{OperationID=$Id;Operation=(Get-RemoteOpsRowValue $First @('Operation'));CompletedAt=(Get-RemoteOpsRowValue $First @('CompletedAt'));Identity=(Get-RemoteOpsRowValue $First @('Identity'));Targets=@(ConvertTo-RemoteOpsHistoryTargets @() $Rows);Outcomes=@();ReportRoot='';LedgerPath=$File.FullName;PackageName=(Get-RemoteOpsRowValue $First @('PackageName','RecipeName'));Source='Ledger'}
                }catch{[void]$Issues.Add([pscustomobject]@{Path=$File.FullName;Message=$_.Exception.Message})}
            }
        }catch{[void]$Issues.Add([pscustomobject]@{Path=$LedgerRoot;Message=$_.Exception.Message})}
    }
    $OperationsRoot=Join-Path $BasePath 'Logs\Operations'
    if(Test-Path -LiteralPath $OperationsRoot){
        try{
            [void](Resolve-RemoteOpsHistoryPath $BasePath $OperationsRoot)
            foreach($OperationFolder in @(Get-ChildItem -LiteralPath $OperationsRoot -Directory)){
                try{[void](Resolve-RemoteOpsHistoryPath $BasePath $OperationFolder.FullName)}catch{[void]$Issues.Add([pscustomobject]@{Path=$OperationFolder.FullName;Message=$_.Exception.Message});continue}
                foreach($Folder in @(Get-ChildItem -LiteralPath $OperationFolder.FullName -Directory)){
                    try{
                        [void](Resolve-RemoteOpsHistoryPath $BasePath $Folder.FullName)
                        $Id=$Folder.Name
                        if($Id -cnotmatch '^[A-Za-z0-9_-]+$'){throw 'Invalid run folder identity.'}
                        if($Runs.ContainsKey($Id) -and $Runs[$Id].ReportRoot){throw 'Multiple report folders for the same run.'}
                        if($Runs.ContainsKey($Id) -and $Runs[$Id].Operation -and $Runs[$Id].Operation -ne $OperationFolder.Name){throw 'Ledger/report operation mismatch.'}
                        if(-not $Runs.ContainsKey($Id)){
                            $When=$Folder.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
                            if($Id -match '^GUI-(\d{8})-(\d{6})-'){
                                $Parsed=[datetime]::MinValue
                                if([datetime]::TryParseExact($Matches[1]+$Matches[2],'yyyyMMddHHmmss',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$Parsed)){$When=$Parsed.ToString('yyyy-MM-dd HH:mm:ss')}
                            }
                            $Runs[$Id]=[pscustomobject]@{OperationID=$Id;Operation=$OperationFolder.Name;CompletedAt=$When;Identity='';Targets=@();Outcomes=@();ReportRoot='';LedgerPath='';PackageName='';Source='Results'}
                        }
                        $Run=$Runs[$Id];$Run.ReportRoot=$Folder.FullName
                        if(-not $Run.LedgerPath){
                            $Paths=@(Get-RemoteOpsHistoryResultPaths $BasePath $Folder.FullName)
                            if(-not $Paths.Count){throw 'Result CSV is missing.'}
                            $ResultRows=@(foreach($ResultPath in $Paths){try{Read-RemoteOpsHistoryCsv $ResultPath}catch{[void]$Issues.Add([pscustomobject]@{Path=$ResultPath;Message=$_.Exception.Message})}})
                            $ResultRows=@($ResultRows|Where-Object{Test-RemoteOpsHistoryRowIdentity $_ $Id})
                            $Run.Targets=@(ConvertTo-RemoteOpsHistoryTargets $ResultRows)
                            if($ResultRows.Count){$Run.PackageName=Get-RemoteOpsRowValue $ResultRows[0] @('PackageName','RecipeName')}
                        }
                    }catch{[void]$Issues.Add([pscustomobject]@{Path=$Folder.FullName;Message=$_.Exception.Message})}
                }
            }
        }catch{[void]$Issues.Add([pscustomobject]@{Path=$OperationsRoot;Message=$_.Exception.Message})}
    }
    foreach($Run in $Runs.Values){$Run.Outcomes=@($Run.Targets|ForEach-Object{$_.Outcome}|Select-Object -Unique)}
    return [pscustomobject]@{Runs=@($Runs.Values|Sort-Object @{Expression='CompletedAt';Descending=$true},OperationID);Issues=@($Issues)}
}
function Find-RemoteOpsHistoryRuns {
    param([object[]]$Runs,[string]$Operation='',[string]$Computer='',[string]$Outcome='',[Nullable[datetime]]$From=$null,[Nullable[datetime]]$To=$null,[ValidateRange(0,2147483647)][int]$Page=0,[ValidateRange(1,500)][int]$PageSize=50)
    $Filtered=@(foreach($Run in @($Runs)){
        if($Operation -and $Run.Operation.IndexOf($Operation,[StringComparison]::OrdinalIgnoreCase) -lt 0){continue}
        $Targets=@($Run.Targets|Where-Object{(-not $Computer -or $_.ComputerName.IndexOf($Computer,[StringComparison]::OrdinalIgnoreCase) -ge 0) -and (-not $Outcome -or $_.Outcome -eq $Outcome)})
        if(($Computer -or $Outcome) -and $Targets.Count -eq 0){continue}
        $When=[datetime]::MinValue;$HasDate=[datetime]::TryParse([string]$Run.CompletedAt,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$When)
        if($null -ne $From -and (-not $HasDate -or $When.Date -lt ([datetime]$From).Date)){continue}
        if($null -ne $To -and (-not $HasDate -or $When.Date -gt ([datetime]$To).Date)){continue}
        $Run
    })
    $LastPage=[Math]::Max(0,[int][Math]::Ceiling($Filtered.Count/[double]$PageSize)-1)
    $Page=[Math]::Min($Page,$LastPage)
    return [pscustomobject]@{Items=@($Filtered|Select-Object -Skip ($Page*$PageSize) -First $PageSize);Total=$Filtered.Count;Page=$Page;PageSize=$PageSize}
}
function Get-RemoteOpsHistoryDetails {
    param([string]$BasePath,$Run)
    $Issues=New-Object System.Collections.ArrayList;$Artifacts=New-Object System.Collections.ArrayList;$Rows=@();$Ledger=@()
    if($Run.LedgerPath){try{$Path=Resolve-RemoteOpsHistoryPath $BasePath $Run.LedgerPath Ledger;$Ledger=@(Read-RemoteOpsHistoryCsv $Path -Ledger|Where-Object{$_.OperationID -eq $Run.OperationID})}catch{[void]$Issues.Add([pscustomobject]@{Path=$Run.LedgerPath;Message=$_.Exception.Message})}}
    if($Run.ReportRoot){
        try{
            $ReportRoot=Resolve-RemoteOpsHistoryPath $BasePath $Run.ReportRoot
            $Expected=Join-Path (Join-Path (Join-Path $BasePath 'Logs\Operations') $Run.Operation) $Run.OperationID
            if(-not $ReportRoot.Equals([IO.Path]::GetFullPath($Expected),[StringComparison]::OrdinalIgnoreCase)){throw 'Report identity mismatch.'}
            [void]$Artifacts.Add([pscustomobject]@{Kind='Folder';Path=$ReportRoot;Exists=(Test-Path -LiteralPath $ReportRoot -PathType Container)})
            foreach($Name in @('Results.csv','Results.html','Activity.csv','Activity.html','RemoteOps.log','Health.html','PackageDefinition.json')){
                $Path=Resolve-RemoteOpsHistoryPath $BasePath (Join-Path $ReportRoot $Name)
                [void]$Artifacts.Add([pscustomobject]@{Kind=$Name;Path=$Path;Exists=(Test-Path -LiteralPath $Path -PathType Leaf)})
            }
            $Paths=@(Get-RemoteOpsHistoryResultPaths $BasePath $ReportRoot)
            if(-not $Paths.Count){throw 'Result CSV is missing.'}
            $Rows=@(foreach($ResultPath in $Paths){
                try{
                    foreach($ArtifactPath in @($ResultPath,[IO.Path]::ChangeExtension($ResultPath,'.html'))){
                        [void](Resolve-RemoteOpsHistoryPath $BasePath $ArtifactPath)
                        if(-not @($Artifacts|Where-Object Path -eq $ArtifactPath).Count){[void]$Artifacts.Add([pscustomobject]@{Kind=[IO.Path]::GetFileName($ArtifactPath);Path=$ArtifactPath;Exists=(Test-Path -LiteralPath $ArtifactPath -PathType Leaf)})}
                    }
                    $ResultRows=@(Read-RemoteOpsHistoryCsv $ResultPath)
                    $ResultRows
                }catch{[void]$Issues.Add([pscustomobject]@{Path=$ResultPath;Message=$_.Exception.Message})}
            })
            $Rows=@($Rows|Where-Object{Test-RemoteOpsHistoryRowIdentity $_ $Run.OperationID})
        }catch{[void]$Issues.Add([pscustomobject]@{Path=$Run.ReportRoot;Message=$_.Exception.Message})}
    }else{[void]$Issues.Add([pscustomobject]@{Path='';Message='Report folder is missing.'})}
    return [pscustomobject]@{Targets=@(ConvertTo-RemoteOpsHistoryTargets $Rows $Ledger);Rows=@($Rows);Artifacts=@($Artifacts);Issues=@($Issues)}
}

function Get-RemoteOpsDiagnosisRunLabel {
 param($Run)
 $Names=@{PackageDeployment='Paket dağıtımı';PackageOperations='Paket işlemleri';ScheduledTaskDelete='Zamanlanmış görev silme';ScheduledTaskAction='Zamanlanmış görev işlemi';ServiceTaskRollback='Servis / görev geri alma';RegistryRollback='Kayıt defteri geri alma';RegistryOperations='Kayıt defteri işlemleri';FilePush='Dosya gönderme';FilePull='Dosya çekme';Recipe='Operasyon reçetesi';RecipeExecution='Operasyon reçetesi'}
 $Names+=@{RecipeRun='Operasyon reçetesi';ApplicationCheck='Uygulama kontrolü';ApplicationInventory='Uygulama envanteri';InstalledApplications='Uygulama envanteri';PackageTrigger='Paket çalıştırma';FileDelete='Dosya yedekleme ve silme';FileCompare='Dosya karşılaştırma';FileBrowser='Dosya işlemleri';FileRestore='Dosya geri yükleme';FileRollback='Dosya değişikliğini geri alma';EndpointInventory='Bilgisayar envanteri';HealthCheck='Sağlık kontrolü';RegistryQuery='Kayıt defteri sorgusu';RegistrySet='Kayıt defteri düzenleme';RegistryDelete='Kayıt defteri silme';ServiceList='Servis listesi';ServiceControl='Servis işlemi';ServiceStartup='Servis başlangıç ayarı';ScheduledTaskList='Zamanlanmış görev listesi';ProcessQuery='Süreç sorgusu';ProcessKill='Süreç sonlandırma'}
 $Name=[string]$Run.Operation;if($Names.ContainsKey($Name)){$Name=$Names[$Name]}
 $When=[datetime]::MinValue;$Date=[string]$Run.CompletedAt
 if([datetime]::TryParse($Date,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$When)){$Date=$When.ToString('dd.MM.yyyy HH:mm:ss')}elseif(-not $Date){$Date='Tarih bilinmiyor'}
 if($Run.PackageName){$Name+=' · '+[string]$Run.PackageName}
 return $Name+' · '+$Date
}
