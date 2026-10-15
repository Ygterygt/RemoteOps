. (Join-Path $PSScriptRoot 'RemoteOps.StepResults.ps1')
####################################################################
# REMOTE OPS - RAPOR KUTUPHANESI  -  RemoteOps.Reports.ps1
#
# Hem GUI (RemoteOps.App.ps1) hem Runner tarafindan dot-source edilir.
# Kendi basina bir sey CALISTIRMAZ; sadece fonksiyon ve tablo tanimlar.
# Icerik:
#   - Sonuc satirlarini Success / Skipped / Error siniflandirma (tek kural seti)
#   - Gunluk "Ledger" kayitlari (Rapor sekmesinin veri kaynagi)
#   - Sonuc ve gunluk dashboard HTML'lerinin uretilmesi
#   - Paket sonuclarinin (Completed/Skipped/Error) hesaplanmasi
####################################################################
#
# HTML'e yazilacak degeri guvenli hale getirir (<, >, & ... kacislari).
function ConvertTo-RemoteOpsHtml {
    param($Value)
    if($null -eq $Value){return ''}
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

# Satirda verilen kolon adlarindan ILK dolu olanin degerini dondurur.
# Moduller farkli kolon adlari kullandigi icin (Status/Durum/ExecutionStatus...) gerekli.
function Get-RemoteOpsRowValue {
    param($Row,[string[]]$Names)
    foreach($Name in $Names){
        $Property=$Row.PSObject.Properties[$Name]
        if($null -ne $Property -and -not [string]::IsNullOrWhiteSpace([string]$Property.Value)){
            return [string]$Property.Value
        }
    }
    return ''
}

# TEK SINIFLANDIRMA KURALI: bir sonuc satiri 'success' | 'neutral' (atlandi/yok) |
# 'issue' (hata) | 'other' olarak etiketlenir. Oncelik sirasi:
#   1) Outcome kolonu (paket satirlari)  2) Status/Durum degerleri  3) Hata kelimeleri
# Paket "Success" olsa bile son kontrol hatasi varsa 'issue' sayilir.
function Get-RemoteOpsRowCategory {
    param($Row)
    if((Get-RemoteOpsRowValue $Row @('VerificationStatus')) -in @('Failed','Unknown')){return 'issue'}
    $Outcome=Get-RemoteOpsRowValue -Row $Row -Names @('Outcome')
    if($Outcome -eq 'Completed'){return 'success'}
    if($Outcome -in @('Skipped','Unreachable')){return 'neutral'}
    if($Outcome -eq 'Error'){return 'issue'}
    $Status=Get-RemoteOpsRowValue -Row $Row -Names @('ExecutionStatus','Status','Durum','CollectionStatus','OperasyonSonucu')
    $Decision=Get-RemoteOpsRowValue -Row $Row -Names @('Decision')
    if($Status -eq 'NotRun' -and $Decision -eq 'Unreachable'){return 'neutral'}
    if($Status -eq 'NotRun' -and $Decision -match '(?i)CheckFailed|Ambiguous'){return 'issue'}
    if($Status -match '^(?i:Unreachable|Erisilemedi)$'){return 'neutral'}
    $PostStatus=Get-RemoteOpsRowValue -Row $Row -Names @('PostCheckStatus')
    $PostError=Get-RemoteOpsRowValue -Row $Row -Names @('PostCheckErrorDetail')
    if($Status -like 'Success*' -and ($PostStatus -match '(?i)Hata|Error|Failed|Coklu' -or -not [string]::IsNullOrWhiteSpace($PostError))){
        return 'issue'
    }
    if($Status -match '^(?i:Var|Success.*|Basarili|KontrolTamamlandi|Esit|Verified)$'){return 'success'}
    # 'Farkli' (FileCompare): karsilastirma basarili, dosyalar farkli -> hata degil, dikkat (sari).
    if($Status -match '^(?i:Yok|Skipped|Cancelled|Atlandi.*|NotRun|NotFound|Bulunamadi|Already.*|Farkli)$'){return 'neutral'}
    if($Status -match '(?i)Hata|Failed|Error|Unreachable|Erisilemedi|Timeout|Denied|Blocked|Ambiguous|Coklu|Indeterminate|RebootRequired'){
        return 'issue'
    }
    return 'other'
}

# Tarih/sayi bicimi: ekranda Turkce, dosyalarda kulturden bagimsiz (Invariant).
$script:RemoteOpsTr = [System.Globalization.CultureInfo]::GetCultureInfo('tr-TR')
$script:RemoteOpsInv = [System.Globalization.CultureInfo]::InvariantCulture

# Operation name -> category and display title (same titles as the GUI catalog).
$script:RemoteOpsOperationMeta = @{
    RecipeRun='Recipes|Operasyon reçetesi'
    ApplicationCheck='Applications|Application presence check'; ApplicationInventory='Applications|List installed applications'; PackageTrigger='Applications|Install or uninstall package'
    PackageDeployment='Applications|Saved package deployment'
    FilePull='Files|Pull files'; FileDelete='Files|Backup and delete'; FilePush='Files|Push files'; FileCompare='Files|Compare file'
    FileBrowser='Files|Browse file: pull / move / replace'; FileRestore='Files|Restore file backup'; FileRollback='Files|Rollback file operation'
    EndpointInventory='Inventory|Endpoint inventory'; HealthCheck='Inventory|PC health check (detailed)'
    RegistryRead='Registry|Read registry value'; RegistryEdit='Registry|Edit registry value'; RegistryDelete='Registry|Delete registry value'; RegistryRollback='Registry|Rollback registry change'
    ServiceList='Services|List services'; ServiceControl='Services|Control service'; ServiceStartup='Services|Change service startup'; ServiceTaskRollback='Services|Rollback service/task change'
    ScheduledTaskList='Tasks|List scheduled tasks'; ScheduledTaskDelete='Tasks|Delete scheduled task (backup)'; ScheduledTaskAction='Tasks|Run / enable / disable task'
    ProcessQuery='Processes|Query processes'; ProcessKill='Processes|Kill process'
}
$script:RemoteOpsCategoryTitles = @{
    Applications='Uygulamalar'; Files='Dosyalar'; Inventory='Envanter'; Registry='Kay'+[char]0x0131+'t Defteri'
    Services='Servisler'; Tasks='Zamanlanm'+[char]0x0131+''+[char]0x015F+' G'+[char]0x00F6+'revler'; Processes='S'+[char]0x00FC+'re'+[char]0x00E7+'ler'
}
$script:RemoteOpsOutcomeTitles = @{Success='Ba'+[char]0x015F+'ar'+[char]0x0131+'l'+[char]0x0131; Skipped='Atland'+[char]0x0131; Unreachable='Atland'+[char]0x0131+' - Eri'+[char]0x015F+'ilemedi'; Error='Hata'}
$script:RemoteOpsOutcomeTitles.Cancelled='Iptal edildi'
$script:RemoteOpsOutcomeTitles.Indeterminate='Sonuc belirsiz'
$script:RemoteOpsOutcomeTitles.RebootRequired='Yeniden baslatma gerekli'

# Teknik ad -> ekran basligi / kategori / kategori Turkce basligi donusumleri.
function Get-RemoteOpsOperationTitle {
    param([string]$Name)
    $Meta=$script:RemoteOpsOperationMeta[$Name]
    if($null -eq $Meta){return $Name}
    return ($Meta -split '\|',2)[1]
}
function Get-RemoteOpsOperationCategory {
    param([string]$Name)
    $Meta=$script:RemoteOpsOperationMeta[$Name]
    if($null -eq $Meta){return 'Other'}
    return ($Meta -split '\|',2)[0]
}
function Get-RemoteOpsCategoryTitle {
    param([string]$Name)
    if([string]::IsNullOrWhiteSpace($Name)){return 'Di'+[char]0x011F+'er'}
    $Title=$script:RemoteOpsCategoryTitles[$Name]
    if($null -eq $Title){return $Name}
    return $Title
}
# Yuzde yardimcilari (bolen 0 ise 0 dondurur).
function Format-RemoteOpsPercent {
    param([double]$Value)
    return ($Value.ToString('0.#',$script:RemoteOpsTr)+'%')
}
function Get-RemoteOpsPercent {
    param([double]$Part,[double]$Whole)
    if($Whole -le 0){return [double]0}
    return [math]::Round(100.0*$Part/$Whole,1)
}

# ---------------------------------------------------------------- daily ledger
# Ledger: her calisma icin Logs\Reports\Ledger\<OperationID>.csv (hedef basina bir satir).
function Get-RemoteOpsLedgerRoot {
    param([Parameter(Mandatory=$true)][string]$BasePath)
    return (Join-Path $BasePath 'Logs\Reports\Ledger')
}

# Bir bilgisayarin birden fazla satirini tek sonuca indirger: Error > Unreachable > Success > Skipped.
function Get-RemoteOpsComputerOutcome {
    # Reduces the result rows of one computer to Success / Skipped / Unreachable / Error (same rules as the runner).
    param([object[]]$Rows)
    $Terminal=@($Rows|Where-Object{(Get-RemoteOpsRowValue $_ @('Step')) -eq 'Result'}|Select-Object -Last 1)
    if($Terminal.Count -gt 0){
        $Status=Get-RemoteOpsRowValue $Terminal[0] @('Status')
        if($Status -in @('Success','Skipped','Error','Unreachable','Cancelled','Indeterminate','RebootRequired')){return $Status}
    }
    $HasError=$false
    $HasUnreachable=$false
    $HasSuccess=$false
    $HasSkipped=$false
    foreach($Row in @($Rows)){
        $Status=Get-RemoteOpsRowValue -Row $Row -Names @('ExecutionStatus','Status','Durum','CollectionStatus','OperasyonSonucu')
        $Decision=Get-RemoteOpsRowValue -Row $Row -Names @('Decision')
        if($Status -match '^(?i:Unreachable|Erisilemedi)$' -or $Decision -eq 'Unreachable'){
            $HasUnreachable=$true
            continue
        }
        switch(Get-RemoteOpsRowCategory $Row){'issue'{$HasError=$true}'success'{$HasSuccess=$true}'neutral'{$HasSkipped=$true}}
    }
    if($HasError){return 'Error'}
    if($HasUnreachable){return 'Unreachable'}
    if($HasSuccess){return 'Success'}
    if($HasSkipped){return 'Skipped'}
    return 'Error'
}

# Calisma bitince Runner tarafindan cagrilir; Rapor sekmesi bu dosyalari okur.
function Write-RemoteOpsLedger {
    # One CSV per run, one row per target attempt. Per-run files avoid write contention between parallel runs.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$BasePath,
        [Parameter(Mandatory=$true)][string]$OperationID,
        [string]$Operation='',[string]$Category='',[string]$Identity='',
        [AllowEmptyCollection()][object[]]$Outcomes=@()
    )
    if(@($Outcomes).Count -eq 0){return ''}
    try{
        $Root=Get-RemoteOpsLedgerRoot -BasePath $BasePath
        if(-not(Test-Path -LiteralPath $Root -PathType Container)){
            New-Item -ItemType Directory -Path $Root -Force -ErrorAction Stop|Out-Null
        }
        if([string]::IsNullOrWhiteSpace($Category)){$Category=Get-RemoteOpsOperationCategory -Name $Operation}
        $Now=Get-Date
        $Rows=@(foreach($Entry in @($Outcomes)){
            $When=$Now
            $Property=$Entry.PSObject.Properties['CompletedAt']
            if($null -ne $Property -and $Property.Value -is [datetime]){$When=[datetime]$Property.Value}
            elseif($null -ne $Property){
                $Parsed=[DateTimeOffset]::MinValue
                if([DateTimeOffset]::TryParse([string]$Property.Value,$script:RemoteOpsInv,[Globalization.DateTimeStyles]::None,[ref]$Parsed)){$When=$Parsed.DateTime}
            }
            [PSCustomObject]@{
                CompletedAt=$When.ToString('yyyy-MM-dd HH:mm:ss',$script:RemoteOpsInv)
                OperationID=$OperationID;Operation=$Operation;Category=$Category
                ComputerName=[string]$Entry.ComputerName;Outcome=[string]$Entry.Outcome;Identity=$Identity
                RecipeName=(Get-RemoteOpsRowValue $Entry @('RecipeName'));RecipeId=(Get-RemoteOpsRowValue $Entry @('RecipeId'));RecipeRevision=(Get-RemoteOpsRowValue $Entry @('RecipeRevision'));PackageName=(Get-RemoteOpsRowValue $Entry @('PackageName'));PackageId=(Get-RemoteOpsRowValue $Entry @('PackageId'));PackageRevision=(Get-RemoteOpsRowValue $Entry @('PackageRevision'));Action=(Get-RemoteOpsRowValue $Entry @('Action'));Detail=(Get-RemoteOpsRowValue $Entry @('Detail'))
            }
        })
        $SafeName=($OperationID -creplace '[^A-Za-z0-9_-]','_')
        $Path=Join-Path $Root ($SafeName+'.csv')
        $Rows|Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8 -Delimiter ';' -ErrorAction Stop
        return $Path
    }
    catch{Write-Warning "Daily report ledger could not be written: $($_.Exception.Message)";return ''}
}

# Secilen gune ait ledger satirlarini toplar. Ledger'dan once yapilmis calismalar
# icin Logs\Operations altindaki Results.csv dosyalarindan satir yeniden uretilir.
function Get-RemoteOpsLedgerRows {
    # Ledger rows of one day. Runs that predate the ledger are rebuilt from their Results.csv so history is not lost.
    param([Parameter(Mandatory=$true)][string]$BasePath,[Parameter(Mandatory=$true)][datetime]$Date)
    $DayText=$Date.ToString('yyyy-MM-dd',$script:RemoteOpsInv)
    $Result=New-Object 'System.Collections.Generic.List[object]'
    $KnownRuns=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $Root=Get-RemoteOpsLedgerRoot -BasePath $BasePath
    if(Test-Path -LiteralPath $Root -PathType Container){
        foreach($File in Get-ChildItem -LiteralPath $Root -Filter '*.csv' -File -ErrorAction SilentlyContinue){
            try{
                foreach($Row in @(Import-Csv -LiteralPath $File.FullName -Delimiter ';' -ErrorAction Stop)){
                    [void]$KnownRuns.Add([string]$Row.OperationID)
                    if(([string]$Row.CompletedAt).StartsWith($DayText)){$Result.Add($Row)}
                }
            }
            catch{Write-Warning "Ledger file skipped ($($File.Name)): $($_.Exception.Message)"}
        }
    }
    $Prefix='GUI-'+$Date.ToString('yyyyMMdd',$script:RemoteOpsInv)+'-'
    $OperationsRoot=Join-Path $BasePath 'Logs\Operations'
    if(Test-Path -LiteralPath $OperationsRoot -PathType Container){
        foreach($RunFolder in Get-ChildItem -LiteralPath $OperationsRoot -Directory -ErrorAction SilentlyContinue|ForEach-Object{Get-ChildItem -LiteralPath $_.FullName -Directory -Filter ($Prefix+'*') -ErrorAction SilentlyContinue}){
            if($KnownRuns.Contains($RunFolder.Name)){continue}
            $ResultsPath=Join-Path $RunFolder.FullName 'Results.csv'
            if(-not(Test-Path -LiteralPath $ResultsPath -PathType Leaf)){continue}
            try{
                $Operation=$RunFolder.Parent.Name
                $Category=Get-RemoteOpsOperationCategory -Name $Operation
                $Time='00:00:00'
                if($RunFolder.Name -match '^GUI-\d{8}-(\d{2})(\d{2})(\d{2})-'){
                    $Time='{0}:{1}:{2}' -f $Matches[1],$Matches[2],$Matches[3]
                }
                $ByComputer=[ordered]@{}
                foreach($Row in @(Import-Csv -LiteralPath $ResultsPath -Delimiter ';' -ErrorAction Stop)){
                    $Computer=Get-RemoteOpsRowValue -Row $Row -Names @('ComputerName','IstemciAdi','ClientName')
                    if([string]::IsNullOrWhiteSpace($Computer)){continue}
                    if(-not $ByComputer.Contains($Computer)){
                        $ByComputer[$Computer]=New-Object System.Collections.ArrayList
                    }
                    [void]$ByComputer[$Computer].Add($Row)
                }
                foreach($Computer in $ByComputer.Keys){
                    $Result.Add([PSCustomObject]@{CompletedAt=($DayText+' '+$Time);OperationID=$RunFolder.Name;Operation=$Operation;Category=$Category;ComputerName=$Computer;Outcome=(Get-RemoteOpsComputerOutcome -Rows @($ByComputer[$Computer]));Identity=''})
                }
            }
            catch{Write-Warning "Historical run skipped ($($RunFolder.Name)): $($_.Exception.Message)"}
        }
    }
    return @($Result.ToArray())
}

# Gunluk rapor nesnesi: toplamlar, yuzdeler, kategori/operasyon dagilimi,
# saatlik yogunluk (24 kova) ve en cok islem yapilan 10 bilgisayar.
function Get-RemoteOpsDailyReport {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$BasePath,[datetime]$Date=(Get-Date))
    $Rows=@(Get-RemoteOpsLedgerRows -BasePath $BasePath -Date $Date)
    $Total=$Rows.Count
    $Counts=[ordered]@{Success=0;Skipped=0;Unreachable=0;Error=0;Cancelled=0;Indeterminate=0;RebootRequired=0}
    foreach($Row in $Rows){$Key=[string]$Row.Outcome;if(-not $Counts.Contains($Key)){$Key='Error'};$Counts[$Key]++}
    $Computers=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $Runs=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($Row in $Rows){[void]$Computers.Add([string]$Row.ComputerName);[void]$Runs.Add([string]$Row.OperationID)}
    # Kategori bazinda grupla; her kategori icin operasyon dagilimini da hesapla.
    $Categories=@(foreach($Group in ($Rows|Group-Object {if([string]::IsNullOrWhiteSpace([string]$_.Category)){'Other'}else{[string]$_.Category}})){
        $GroupRows=@($Group.Group)
        $CategoryCounts=[ordered]@{Success=0;Skipped=0;Unreachable=0;Error=0;Cancelled=0;Indeterminate=0;RebootRequired=0}
        foreach($Row in $GroupRows){
            $Key=[string]$Row.Outcome
            if(-not $CategoryCounts.Contains($Key)){
                $Key='Error'
            }
            $CategoryCounts[$Key]++
        }
        $CategoryComputers=@($GroupRows|ForEach-Object{[string]$_.ComputerName}|Sort-Object -Unique).Count
        $Operations=@(foreach($OperationGroup in ($GroupRows|Group-Object Operation)){
            [PSCustomObject]@{Name=[string]$OperationGroup.Name;Title=(Get-RemoteOpsOperationTitle -Name ([string]$OperationGroup.Name));Count=$OperationGroup.Count;Percent=(Get-RemoteOpsPercent $OperationGroup.Count $GroupRows.Count)}
        })|Sort-Object @{Expression='Count';Descending=$true},Title
        [PSCustomObject]@{
            Name=[string]$Group.Name;Title=(Get-RemoteOpsCategoryTitle -Name ([string]$Group.Name));Count=$GroupRows.Count;Percent=(Get-RemoteOpsPercent $GroupRows.Count $Total)
            Success=$CategoryCounts.Success;Skipped=$CategoryCounts.Skipped;Neutral=($CategoryCounts.Skipped+$CategoryCounts.Unreachable);Unreachable=$CategoryCounts.Unreachable;Error=($CategoryCounts.Error+$CategoryCounts.Indeterminate+$CategoryCounts.RebootRequired);Cancelled=$CategoryCounts.Cancelled
            Computers=$CategoryComputers;Operations=@($Operations)
        }
    })|Sort-Object @{Expression='Count';Descending=$true},Title
    # Package identity/action comes from the immutable run snapshot in the ledger.
    $PackageRows=@($Rows|Where-Object{[string]$_.Operation -eq 'PackageDeployment' -and -not [string]::IsNullOrWhiteSpace((Get-RemoteOpsRowValue $_ @('PackageName')))})
    $Packages=@(foreach($Group in ($PackageRows|Group-Object {ConvertTo-Json -InputObject @((Get-RemoteOpsRowValue $_ @('PackageId')),(Get-RemoteOpsRowValue $_ @('PackageName')),(Get-RemoteOpsRowValue $_ @('Action'))) -Compress})){
        $First=$Group.Group[0]
        $PackageCounts=[ordered]@{Success=0;Skipped=0;Unreachable=0;Error=0;Cancelled=0;Indeterminate=0;RebootRequired=0}
        foreach($Row in $Group.Group){$Key=[string]$Row.Outcome;if(-not $PackageCounts.Contains($Key)){$Key='Error'};$PackageCounts[$Key]++}
        $Action=Get-RemoteOpsRowValue $First @('Action')
        $ActionTitle=switch($Action){'Install'{'Kur'}'Uninstall'{'Kald'+[char]0x0131+'r'}'Downgrade'{'Eski s'+[char]0x00FC+'r'+[char]0x00FC+'me d'+[char]0x00F6+'n'}default{$Action}}
        [PSCustomObject]@{Id=(Get-RemoteOpsRowValue $First @('PackageId'));Name=(Get-RemoteOpsRowValue $First @('PackageName'));Action=$Action;ActionTitle=$ActionTitle;Count=$Group.Count
            Runs=@($Group.Group|ForEach-Object{$_.OperationID}|Sort-Object -Unique).Count;Computers=@($Group.Group|ForEach-Object{$_.ComputerName}|Sort-Object -Unique).Count
            Success=$PackageCounts.Success;Skipped=($PackageCounts.Skipped+$PackageCounts.Unreachable);Unreachable=$PackageCounts.Unreachable;Cancelled=$PackageCounts.Cancelled
            Problems=($PackageCounts.Error+$PackageCounts.Indeterminate+$PackageCounts.RebootRequired)}
    })|Sort-Object @{Expression='Count';Descending=$true},Name,Action
    # Saatlik yogunluk: CompletedAt metninin saat kismina gore sayilir.
    $Hours=@(for($Hour=0;$Hour -lt 24;$Hour++){0})
    foreach($Row in $Rows){
        $Text=[string]$Row.CompletedAt
        if($Text.Length -ge 13){
            $Parsed=0
            if([int]::TryParse($Text.Substring(11,2),[ref]$Parsed) -and $Parsed -ge 0 -and $Parsed -lt 24){
                $Hours[$Parsed]++
            }
        }
    }
    $TopComputers=@(foreach($Group in ($Rows|Group-Object {([string]$_.ComputerName).ToUpperInvariant()})){
        $Problems=@($Group.Group|Where-Object{$_.Outcome -in @('Error','Indeterminate','RebootRequired')}).Count
        [PSCustomObject]@{ComputerName=[string]$Group.Group[0].ComputerName;Count=$Group.Count;Problems=$Problems}
    })|Sort-Object @{Expression='Count';Descending=$true},ComputerName|Select-Object -First 10
    return [PSCustomObject]@{
        Date=$Date.Date;Total=$Total;Success=$Counts.Success;Skipped=$Counts.Skipped;Unreachable=$Counts.Unreachable;Error=$Counts.Error
        Neutral=($Counts.Skipped+$Counts.Unreachable);NeutralPercent=(Get-RemoteOpsPercent ($Counts.Skipped+$Counts.Unreachable) $Total);Problems=($Counts.Error+$Counts.Indeterminate+$Counts.RebootRequired)
        Cancelled=$Counts.Cancelled;Indeterminate=$Counts.Indeterminate;RebootRequired=$Counts.RebootRequired
        SuccessPercent=(Get-RemoteOpsPercent $Counts.Success $Total);SkippedPercent=(Get-RemoteOpsPercent $Counts.Skipped $Total)
        UnreachablePercent=(Get-RemoteOpsPercent $Counts.Unreachable $Total);ErrorPercent=(Get-RemoteOpsPercent $Counts.Error $Total)
        UniqueComputers=$Computers.Count;Runs=$Runs.Count;Categories=@($Categories);Packages=@($Packages);Hours=@($Hours);TopComputers=@($TopComputers)
    }
}

# ---------------------------------------------------------------- HTML
# Sonuc ve dashboard HTML'lerinin ortak CSS'i (acik/koyu tema, yazdirma).
function Get-RemoteOpsHtmlStyle {
    return @'
:root{--bg:#f2f5f9;--card:#fff;--ink:#1a2a36;--muted:#5f7280;--line:#dbe3ea;--head:#e9eff5;--brand:#0b64a8;--brand2:#0a8c83;--ok:#17855a;--warn:#b7791f;--bad:#c53a3a;--oth:#6b7b89;--ok-bg:#e3f5ec;--warn-bg:#fbf0d9;--bad-bg:#fbe5e5;--oth-bg:#e9edf1;--shadow:0 1px 2px rgba(16,40,60,.06),0 6px 18px rgba(16,40,60,.07)}
@media(prefers-color-scheme:dark){:root{--bg:#0e1820;--card:#15242e;--ink:#e5edf2;--muted:#93a6b3;--line:#27394a;--head:#1c303d;--brand:#5aaee8;--brand2:#3cc2b6;--ok:#4cc590;--warn:#e0b04f;--bad:#ef7c7c;--oth:#93a6b3;--ok-bg:#16382d;--warn-bg:#3b3015;--bad-bg:#401f20;--oth-bg:#22343f;--shadow:0 1px 2px rgba(0,0,0,.3),0 6px 18px rgba(0,0,0,.28)}}
*{box-sizing:border-box}html{-webkit-text-size-adjust:100%}
body{margin:0;color:var(--ink);background:var(--bg);font:14px/1.45 'Segoe UI',system-ui,-apple-system,sans-serif}
.top{background:linear-gradient(120deg,#073f73,#0b64a8 55%,#0a8c83);color:#fff;padding:26px 32px 22px}
.brand{font-size:12px;font-weight:600;letter-spacing:.14em;opacity:.85}
.top h1{margin:6px 0 10px;font-size:26px;font-weight:600;letter-spacing:-.01em}
.chips{display:flex;flex-wrap:wrap;gap:8px}.chip{background:rgba(255,255,255,.16);border-radius:999px;padding:3px 12px;font-size:12px;overflow-wrap:break-word;word-break:normal}
main{max-width:1500px;margin:0 auto;padding:22px 32px 40px}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:14px}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px 16px;box-shadow:var(--shadow);border-top:4px solid var(--brand)}
.card.ok{border-top-color:var(--ok)}.card.warn{border-top-color:var(--warn)}.card.bad{border-top-color:var(--bad)}.card.oth{border-top-color:var(--oth)}
.card span{display:block;color:var(--muted);font-size:12px}.card strong{display:block;font-size:30px;line-height:1.15;margin-top:2px;font-variant-numeric:tabular-nums}.card em{font-style:normal;color:var(--muted);font-size:12px}
.panel{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px 18px;box-shadow:var(--shadow);margin-top:16px}
.panel h2{margin:0 0 12px;font-size:15px;font-weight:600}
.stack{display:flex;height:16px;border-radius:8px;overflow:hidden;background:var(--oth-bg)}.stack i{display:block;height:100%}
.legend{display:flex;flex-wrap:wrap;gap:6px 18px;margin-top:10px;font-size:12px;color:var(--muted)}.legend b{color:var(--ink);font-weight:600}
.dot{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:6px;vertical-align:-1px}
.c-ok{background:var(--ok)}.c-warn{background:var(--warn)}.c-bad{background:var(--bad)}.c-oth{background:var(--oth)}
.filters{display:flex;gap:12px;align-items:flex-end;flex-wrap:wrap;margin:18px 0 12px}
label{display:grid;gap:4px;font-size:12px;color:var(--muted)}
input,select{font:inherit;color:var(--ink);background:var(--card);border:1px solid var(--line);border-radius:8px;padding:8px 10px;max-width:100%}
input{width:280px}input:focus,select:focus,button:focus-visible,a:focus-visible{outline:2px solid var(--brand);outline-offset:1px}
.btn{font:inherit;display:inline-block;padding:8px 14px;color:#fff;background:var(--brand);border:0;border-radius:8px;text-decoration:none;cursor:pointer}.btn.alt{background:transparent;color:var(--brand);border:1px solid var(--brand)}
.visible{margin-left:auto;color:var(--muted)}
.table-wrap{overflow:auto;border:1px solid var(--line);border-radius:12px;background:var(--card);max-height:66vh;box-shadow:var(--shadow)}
table{width:100%;border-collapse:collapse;font-size:12.5px}
th{position:sticky;top:0;background:var(--head);z-index:1;text-align:left;white-space:nowrap}
th button{border:0;background:transparent;font:inherit;font-weight:600;padding:11px 12px;cursor:pointer;color:var(--ink);width:100%;text-align:left}
th[aria-sort=ascending] button::after{content:" \25B2";font-size:9px}th[aria-sort=descending] button::after{content:" \25BC";font-size:9px}
td{border-top:1px solid var(--line);padding:8px 12px;vertical-align:top;max-width:460px;overflow-wrap:anywhere}
.results-table{width:max-content;min-width:100%}
.results-table td{min-width:140px;word-break:normal;overflow-wrap:break-word}
.results-table td:first-child{min-width:190px}
.results-table td.report-message{min-width:300px}
.results-table .cell{max-width:460px}
.technical-details summary{cursor:pointer;white-space:nowrap;color:var(--brand)}
.technical-details[open]{width:380px;max-width:70vw}
.technical-details dl{margin:10px 0}.technical-details dt{font-weight:600;margin-top:8px}
.technical-details dd{margin:2px 0 0;overflow-wrap:anywhere;user-select:text}
td.long{cursor:pointer}td.long:not(.open){max-height:3.2em}td.long:not(.open) .cell{display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
tbody tr:nth-child(even){background:color-mix(in srgb,var(--head) 35%,transparent)}tbody tr:hover{background:color-mix(in srgb,var(--brand) 9%,transparent)}
.pill{display:inline-block;padding:2px 10px;border-radius:999px;font-size:11.5px;font-weight:600;white-space:nowrap}
.pill.success{background:var(--ok-bg);color:var(--ok)}.pill.neutral{background:var(--warn-bg);color:var(--warn)}.pill.issue{background:var(--bad-bg);color:var(--bad)}.pill.other{background:var(--oth-bg);color:var(--oth)}
.empty{padding:36px;text-align:center;color:var(--muted)}
footer{max-width:1500px;margin:0 auto;padding:0 32px 28px;color:var(--muted);font-size:12px}
.cat{padding:12px 0;border-top:1px solid var(--line)}.cat:first-of-type{border-top:0}
.cat-head{display:flex;justify-content:space-between;gap:12px;align-items:baseline;flex-wrap:wrap}.cat-head b{font-size:15px}.cat-head span{color:var(--muted)}
.bar{height:8px;border-radius:5px;background:var(--oth-bg);overflow:hidden;margin:7px 0}.bar i{display:block;height:100%;background:linear-gradient(90deg,var(--brand),var(--brand2))}
.ops{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:4px 22px;margin-top:6px;font-size:12.5px}.ops div{display:flex;justify-content:space-between;gap:10px;border-bottom:1px dashed var(--line);padding:2px 0}.ops span{color:var(--muted);white-space:nowrap}
.grid2{display:grid;grid-template-columns:2fr 1fr;gap:16px}@media(max-width:980px){.grid2{grid-template-columns:1fr}}
.hours{display:flex;align-items:flex-end;gap:3px;height:90px}.hours div{flex:1;background:linear-gradient(0deg,var(--brand),var(--brand2));border-radius:3px 3px 0 0;min-height:2px;opacity:.9}
.hours-x{display:flex;gap:3px;font-size:10px;color:var(--muted);margin-top:3px}.hours-x span{flex:1;text-align:center}
table.mini td,table.mini th{padding:6px 8px;position:static;max-width:none}
@media(max-width:640px){.top,main,footer{padding-left:16px;padding-right:16px}input{width:100%}.filters label{width:100%}.visible{margin-left:0}.top h1{font-size:21px}}
@media print{.results-table{width:100%;min-width:0}.results-table td{min-width:0!important}.results-table th,.results-table th button{white-space:normal}.filters,.noprint{display:none!important}.table-wrap{max-height:none;overflow:visible;box-shadow:none}th{position:static}body{background:#fff}.top{background:#fff;color:#000;border-bottom:3px solid #0b64a8;padding:12px}.chip{background:#eee;color:#000}main{padding:10px}}
'@
}

# Basarili / Atlandi / Hata yuzdelerini gosteren yigilmis cubuk + aciklama HTML'i.
function Get-RemoteOpsOutcomeBar {
    param([int]$Success,[int]$Skipped,[int]$Problem,[int]$Other=0)
    $Total=$Success+$Skipped+$Problem+$Other
    if($Total -le 0){return '<div class="stack" aria-hidden="true"></div>'}
    $Segments=@(
        @{Class='c-ok';Value=$Success;Label='Ba'+[char]0x015F+'ar'+[char]0x0131+'l'+[char]0x0131},
        @{Class='c-warn';Value=$Skipped;Label='Atland'+[char]0x0131+' / Yok / Eri'+[char]0x015F+'ilemedi'},
        @{Class='c-bad';Value=$Problem;Label='Hata / Dikkat'},
        @{Class='c-oth';Value=$Other;Label='Di'+[char]0x011F+'er'}
    )
    $Bar='<div class="stack" role="img" aria-label="Sonu'+[char]0x00E7+' da'+[char]0x011F+''+[char]0x0131+'l'+[char]0x0131+'m'+[char]0x0131+'">'
    $Legend='<div class="legend">'
    foreach($Segment in $Segments){
        if($Segment.Value -le 0){continue}
        $Percent=Get-RemoteOpsPercent $Segment.Value $Total
        $Bar+='<i class="'+$Segment.Class+'" style="width:'+$Percent.ToString('0.##',$script:RemoteOpsInv)+'%" title="'+$Segment.Label+': '+$Segment.Value+'"></i>'
        $Legend+='<span><span class="dot '+$Segment.Class+'"></span>'+$Segment.Label+' <b>'+$Segment.Value+'</b> ('+(Format-RemoteOpsPercent $Percent)+')</span>'
    }
    return ($Bar+'</div>'+$Legend+'</div>')
}

# SONUC HTML'I: satirlari aranabilir/filtrelenebilir/siralanabilir tablo olarak yazar.
# Her satira Get-RemoteOpsRowCategory ile durum etiketi (pill) eklenir.
function Test-RemoteOpsReportTechnicalColumn {
    param([string]$Name)
    foreach($Suffix in @('Id','Guid','Hash')){if($Name.EndsWith($Suffix,[StringComparison]::OrdinalIgnoreCase)){return $true}}
    return $Name -in @('RecipeRevision','PackageRevision')
}
function ConvertTo-RemoteOpsReportTechnicalDetails {
    param($Entry,[string[]]$Headers)
    $Parts=@(foreach($Column in $Headers){$Value=Get-RemoteOpsRowValue $Entry @($Column);if(-not [string]::IsNullOrWhiteSpace($Value)){'<dt>'+(ConvertTo-RemoteOpsHtml $Column)+'</dt><dd>'+(ConvertTo-RemoteOpsHtml $Value)+'</dd>'}})
    if(-not $Parts.Count){return '<span aria-label="Teknik kimlik yok">—</span>'}
    return '<details class="technical-details"><summary>Teknik kimlikler</summary><dl>'+($Parts -join '')+'</dl></details>'
}
function Get-RemoteOpsReportDisplayValue {
    param([string]$Column,$Value)
    if($Column -in @('Status','ExecutionStatus','Durum','Outcome') -and [string]$Value -ceq 'NotRun'){return 'Çalıştırılmadı'}
    return [string]$Value
}
function Write-RemoteOpsResultHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$OperationID,
        [AllowEmptyCollection()][object[]]$Rows=@(),
        [string]$CsvPath=''
    )
    $StepRows=@()
    $TerminalRows=@($Rows|Where-Object{(Get-RemoteOpsRowValue $_ @('Step')) -eq 'Result'})
    if($TerminalRows.Count -gt 0){
        $GroupKey={param($Entry)ConvertTo-Json -InputObject @((Get-RemoteOpsRowValue $Entry @('ComputerName','IstemciAdi','ClientName')),(Get-RemoteOpsRowValue $Entry @('OperationID')),(Get-RemoteOpsRowValue $Entry @('PackageId'))) -Compress}
        $TerminalKeys=@{};foreach($Terminal in $TerminalRows){$TerminalKeys[(& $GroupKey $Terminal)]=$true}
        $OtherRows=@($Rows|Where-Object{(Get-RemoteOpsRowValue $_ @('Step')) -ne 'Result'})
        $StepRows=@($OtherRows|Where-Object{$TerminalKeys.ContainsKey((& $GroupKey $_))})
        $UnmatchedRows=@($OtherRows|Where-Object{-not $TerminalKeys.ContainsKey((& $GroupKey $_))})
        $Rows=@(foreach($Terminal in $TerminalRows){
            $Copy=$Terminal|Select-Object *
            $Client=Get-RemoteOpsRowValue $Terminal @('ComputerName','IstemciAdi','ClientName')
            $RunId=Get-RemoteOpsRowValue $Terminal @('OperationID')
            $PackageId=Get-RemoteOpsRowValue $Terminal @('PackageId')
            $Execution=@($StepRows|Where-Object{
                (Get-RemoteOpsRowValue $_ @('ComputerName','IstemciAdi','ClientName')) -eq $Client -and
                (Get-RemoteOpsRowValue $_ @('OperationID')) -eq $RunId -and
                (Get-RemoteOpsRowValue $_ @('PackageId')) -eq $PackageId -and
                (Get-RemoteOpsRowValue $_ @('Step')) -in @('Install','Uninstall')
            }|Select-Object -Last 1)
            if($Execution.Count){
                foreach($Field in @('ExitCode','LogDestination','LogCollectionStatus','LogCleanupStatus')){
                    if([string]::IsNullOrWhiteSpace((Get-RemoteOpsRowValue $Copy @($Field)))){
                        $Property=$Execution[0].PSObject.Properties[$Field]
                        if($null -ne $Property){Add-Member -InputObject $Copy -NotePropertyName $Field -NotePropertyValue $Property.Value -Force}
                    }
                }
                Add-Member -InputObject $Copy -NotePropertyName ExecutionStep -NotePropertyValue ([string]$Execution[0].Step) -Force
                Add-Member -InputObject $Copy -NotePropertyName ExecutionDetail -NotePropertyValue (Get-RemoteOpsRowValue $Execution[0] @('ErrorDetail')) -Force
                Add-Member -InputObject $Copy -NotePropertyName RebootRequired -NotePropertyValue (@($StepRows|Where-Object{
                    (Get-RemoteOpsRowValue $_ @('ComputerName','IstemciAdi','ClientName')) -eq $Client -and
                    (Get-RemoteOpsRowValue $_ @('OperationID')) -eq $RunId -and
                    (Get-RemoteOpsRowValue $_ @('PackageId')) -eq $PackageId -and
                    (Get-RemoteOpsRowValue $_ @('RebootRequired')) -eq 'True'
                }).Count -gt 0 -or (Get-RemoteOpsRowValue $Terminal @('RebootRequired')) -eq 'True') -Force
            }
            $Copy
        })+@($UnmatchedRows)
    }
    $StepHtml=''
    if($StepRows.Count){
        $StepAllHeaders=@($StepRows|ForEach-Object{$_.PSObject.Properties.Name}|Select-Object -Unique)
        $StepTechnical=@($StepAllHeaders|Where-Object{Test-RemoteOpsReportTechnicalColumn $_});$StepHeaders=@($StepAllHeaders|Where-Object{-not(Test-RemoteOpsReportTechnicalColumn $_)})
        $StepHead=(@(foreach($Column in $StepHeaders){'<th>'+(ConvertTo-RemoteOpsHtml $Column)+'</th>'}) -join '')
        $StepBody=(@(foreach($Entry in $StepRows){'<tr>'+(@(foreach($Column in $StepHeaders){'<td>'+(ConvertTo-RemoteOpsHtml (Get-RemoteOpsReportDisplayValue $Column (Get-RemoteOpsRowValue $Entry @($Column))))+'</td>'}) -join '')+$(if($StepTechnical.Count){'<td>'+(ConvertTo-RemoteOpsReportTechnicalDetails $Entry $StepTechnical)+'</td>'}else{''})+'</tr>'}) -join '')
        if($StepTechnical.Count){$StepHead+='<th>Ayrıntı</th>'}
        $StepHtml='<details class="panel"><summary>Adim ayrintilari ('+$StepRows.Count+')</summary><p>Asagidaki satirlar ayni hedefin ayri yurutme/dogrulama adimlaridir; hedef sayisina eklenmez.</p><div class="table-wrap"><table class="results-table"><thead><tr>'+$StepHead+'</tr></thead><tbody>'+$StepBody+'</tbody></table></div></details>'
    }
    if(@($Rows|Where-Object{(Get-RemoteOpsRowValue $_ @('StepIndex','VerificationStatus'))}).Count){$StepHtml=(Get-RemoteOpsStepSummaryHtml $Rows)+$StepHtml}
    $AllHeaders=@($Rows|ForEach-Object{$_.PSObject.Properties.Name}|Select-Object -Unique)
    $TechnicalHeaders=@($AllHeaders|Where-Object{Test-RemoteOpsReportTechnicalColumn $_})
    $Headers=@($AllHeaders|Where-Object{-not(Test-RemoteOpsReportTechnicalColumn $_)})
    $Clients=@($Rows|ForEach-Object{Get-RemoteOpsRowValue -Row $_ -Names @('ComputerName','IstemciAdi','ClientName')}|Where-Object{-not [string]::IsNullOrWhiteSpace($_)}|Sort-Object -Unique)
    $Counts=@{success=0;neutral=0;issue=0;other=0}
    $SummaryRows=$Rows
    foreach($Row in $SummaryRows){$Counts[(Get-RemoteOpsRowCategory $Row)]++}
    $PillText=@{success='Ba'+[char]0x015F+'ar'+[char]0x0131+'l'+[char]0x0131;neutral='Atland'+[char]0x0131+' / Yok / Eri'+[char]0x015F+'ilemedi';issue='Hata';other='Di'+[char]0x011F+'er'}
    $Body=@(foreach($Row in $Rows){
        $Category=Get-RemoteOpsRowCategory -Row $Row
        $Client=Get-RemoteOpsRowValue -Row $Row -Names @('ComputerName','IstemciAdi','ClientName')
        $Cells=@(foreach($Header in $Headers){
            $Property=$Row.PSObject.Properties[$Header]
            $Value=if($null -ne $Property){$Property.Value}else{''}
            $Value=Get-RemoteOpsReportDisplayValue $Header $Value
            $CellClass=if($Header -in @('ErrorDetail','HataDetayi','Detail','ExecutionDetail','Reason')){'report-message'}else{'report-value'}
            $Text=[string]$Value
            if($Text.Length -gt 140){
                '<td class="long '+$CellClass+'" title="Detay i'+[char]0x00E7+'in t'+[char]0x0131+'klay'+[char]0x0131+'n"><div class="cell">'+(ConvertTo-RemoteOpsHtml $Value)+'</div></td>'
            }
            else{'<td class="'+$CellClass+'">'+(ConvertTo-RemoteOpsHtml $Value)+'</td>'}
        }) -join ''
        if($TechnicalHeaders.Count){$Cells+='<td>'+(ConvertTo-RemoteOpsReportTechnicalDetails $Row $TechnicalHeaders)+'</td>'}
        $Outcome=Get-RemoteOpsRowValue $Row @('Status','Outcome')
        $RowPill=if($Outcome -eq 'NotRun'){'Çalıştırılmadı'}else{$PillText[$Category]}
        '<tr data-client="'+(ConvertTo-RemoteOpsHtml $Client)+'" data-status="'+$Category+'" data-outcome="'+(ConvertTo-RemoteOpsHtml $Outcome)+'"><td><span class="pill '+$Category+'">'+$RowPill+'</span></td>'+$Cells+'</tr>'
    }) -join "`n"
    $HeaderHtml='<th scope="col"><button type="button" title="S'+[char]0x0131+'rala">Durum</button></th>'+(@(foreach($Header in $Headers){'<th scope="col"><button type="button" title="S'+[char]0x0131+'rala">'+(ConvertTo-RemoteOpsHtml $Header)+'</button></th>'}) -join '')
    if($TechnicalHeaders.Count){$HeaderHtml+='<th scope="col">Ayrıntı</th>'}
    $Options=@(foreach($Client in $Clients){'<option value="'+(ConvertTo-RemoteOpsHtml $Client)+'">'+(ConvertTo-RemoteOpsHtml $Client)+'</option>'}) -join ''
    $CsvLink=''
    if(-not [string]::IsNullOrWhiteSpace($CsvPath)){
        $CsvUri=New-Object System.Uri ([System.IO.Path]::GetFullPath($CsvPath))
        $CsvLink='<a class="btn csv" href="'+(ConvertTo-RemoteOpsHtml $CsvUri.AbsoluteUri)+'" download>CSV indir</a>'
    }
    if($Rows.Count -eq 0){
        $Body='<tr><td colspan="'+[Math]::Max(1,$Headers.Count+1+[int]($TechnicalHeaders.Count -gt 0))+'" class="empty">Sonu'+[char]0x00E7+' kayd'+[char]0x0131+' '+[char]0x00FC+'retilmedi.</td></tr>'
    }
    $DisplayTitle=Get-RemoteOpsOperationTitle -Name $Title
    $SafeTitle=ConvertTo-RemoteOpsHtml $DisplayTitle
    $SafeID=ConvertTo-RemoteOpsHtml $OperationID
    $Created=(Get-Date).ToString('dd MMMM yyyy HH:mm:ss',$script:RemoteOpsTr)
    $Bar=Get-RemoteOpsOutcomeBar -Success $Counts.success -Skipped $Counts.neutral -Problem $Counts.issue -Other $Counts.other
    $Style=Get-RemoteOpsHtmlStyle
    $Cards=@(
        @('','Bilgisayar',$Clients.Count,''),
        @('',('Kay'+[char]0x0131+'t'),$Rows.Count,''),
        @('ok',('Ba'+[char]0x015F+'ar'+[char]0x0131+'l'+[char]0x0131+' / Bulundu'),$Counts.success,(Format-RemoteOpsPercent (Get-RemoteOpsPercent $Counts.success $SummaryRows.Count))),
        @('warn','Atlanan / Yok / Erişilemedi',$Counts.neutral,(Format-RemoteOpsPercent (Get-RemoteOpsPercent $Counts.neutral $SummaryRows.Count))),
        @('bad','Hata / Dikkat',$Counts.issue,(Format-RemoteOpsPercent (Get-RemoteOpsPercent $Counts.issue $SummaryRows.Count))),
        @('oth',('Di'+[char]0x011F+'er'),$Counts.other,(Format-RemoteOpsPercent (Get-RemoteOpsPercent $Counts.other $SummaryRows.Count)))
    )
    $CardHtml=@(foreach($Card in $Cards){'<div class="card '+$Card[0]+'"><span>'+$Card[1]+'</span><strong>'+$Card[2]+'</strong><em>'+$(if($Card[3]){$Card[3]}else{'&nbsp;'})+'</em></div>'}) -join ''
    $Html=@"
<!doctype html>
<html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="color-scheme" content="light dark"><title>$SafeTitle | Remote Ops</title>
<style>
$Style
</style></head><body>
<div class="top"><div class="brand">REMOTE OPS &middot; SONU&Ccedil; RAPORU</div><h1>$SafeTitle</h1><div class="chips"><span class="chip">&#304;&#351;lem kodu: $SafeID</span><span class="chip">$Created</span></div></div>
<main><section class="cards" aria-label="Sonu&ccedil; &ouml;zeti">$CardHtml</section>
<section class="panel" aria-label="Sonu&ccedil; da&#287;&#305;l&#305;m&#305;"><h2>Sonu&ccedil; da&#287;&#305;l&#305;m&#305;</h2>$Bar</section>
<div class="filters"><label>Ara<input id="query" type="search" placeholder="Sonu&ccedil;larda ara"></label><label>Bilgisayar<select id="client"><option value="">T&uuml;m bilgisayarlar</option>$Options</select></label><label>Durum<select id="status"><option value="">T&uuml;m durumlar</option><option value="success">Ba&#351;ar&#305;l&#305; / Bulundu</option><option value="neutral">Atlanan / Yok / Eri&#351;ilemedi</option><option value="issue">Hata</option><option value="other">Di&#287;er</option></select></label><label>Hedef sonucu<select id="outcome"><option value="">T&uuml;m sonu&ccedil;lar</option><option>Success</option><option>Skipped</option><option>Error</option><option>Unreachable</option><option>Cancelled</option><option>Indeterminate</option><option>RebootRequired</option></select></label><button type="button" class="btn alt noprint" id="reset">Temizle</button>$CsvLink<button type="button" class="btn alt noprint" onclick="window.print()">Yazd&#305;r</button><span id="visible" class="visible"></span></div>
<div class="table-wrap"><table id="results" class="results-table"><thead><tr>$HeaderHtml</tr></thead><tbody>$Body</tbody></table></div>$StepHtml</main>
<footer>Remote Ops taraf&#305;ndan olu&#351;turuldu &middot; $Created</footer>
<script>
const body=document.querySelector('#results tbody');
const rows=Array.from(body.querySelectorAll('tr[data-client]'));
function filter(){const query=document.getElementById('query').value.toLowerCase();const client=document.getElementById('client').value;const status=document.getElementById('status').value;const outcome=document.getElementById('outcome').value;let count=0;rows.forEach(row=>{const show=(!client||row.dataset.client===client)&&(!status||row.dataset.status===status)&&(!outcome||row.dataset.outcome===outcome)&&row.textContent.toLowerCase().includes(query);row.hidden=!show;if(show)count++;});document.getElementById('visible').textContent=count+' / '+rows.length+' kay'+String.fromCharCode(305)+'t';}
['query','client','status','outcome'].forEach(id=>document.getElementById(id).addEventListener('input',filter));
document.getElementById('reset').addEventListener('click',()=>{['query','client','status','outcome'].forEach(id=>{document.getElementById(id).value='';});filter();});
document.querySelectorAll('#results th button').forEach((button,index)=>{let ascending=true;button.addEventListener('click',()=>{rows.sort((left,right)=>left.cells[index].textContent.localeCompare(right.cells[index].textContent,undefined,{numeric:true})*(ascending?1:-1));rows.forEach(row=>body.appendChild(row));document.querySelectorAll('#results th').forEach(header=>header.removeAttribute('aria-sort'));button.parentElement.setAttribute('aria-sort',ascending?'ascending':'descending');ascending=!ascending;});});
body.addEventListener('click',event=>{const cell=event.target.closest('td.long');if(cell)cell.classList.toggle('open');});
filter();
</script></body></html>
"@
    $Parent=Split-Path -Parent $Path
    if(-not(Test-Path -LiteralPath $Parent -PathType Container)){
        New-Item -ItemType Directory -Path $Parent -Force|Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Html -Encoding UTF8 -ErrorAction Stop
    return $Path
}

# GUNLUK DASHBOARD HTML'I (Rapor sekmesindeki "HTML" butonu).
function Write-RemoteOpsDailyDashboardHtml {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)]$Report)
    $Style=Get-RemoteOpsHtmlStyle
    $DateText=([datetime]$Report.Date).ToString('dd MMMM yyyy, dddd',$script:RemoteOpsTr)
    $Created=(Get-Date).ToString('dd MMMM yyyy HH:mm:ss',$script:RemoteOpsTr)
    $Cancelled=[int](Get-RemoteOpsRowValue $Report @('Cancelled'))
    $Indeterminate=[int](Get-RemoteOpsRowValue $Report @('Indeterminate'))
    $RebootRequired=[int](Get-RemoteOpsRowValue $Report @('RebootRequired'))
    $Problem=[int]$Report.Error+$Indeterminate+$RebootRequired
    $Cards=@(
        @('',('Tamamlanan '+[char]0x0130+[char]0x015F+'lem'),$Report.Total,([string]$Report.Runs+' '+[char]0x00E7+'al'+[char]0x0131+[char]0x015F+'t'+[char]0x0131+'rma')),
        @('','Benzersiz Bilgisayar',$Report.UniqueComputers,''),
        @('ok',('Ba'+[char]0x015F+'ar'+[char]0x0131+'l'+[char]0x0131),$Report.Success,(Format-RemoteOpsPercent $Report.SuccessPercent)),
        @('warn','Atlanan / Yok / Erişilemedi',$Report.Neutral,(Format-RemoteOpsPercent $Report.NeutralPercent)),
        @('bad','Hata / Dikkat',$Problem,(Format-RemoteOpsPercent (Get-RemoteOpsPercent $Problem $Report.Total)))
    )
    $CardHtml=@(foreach($Card in $Cards){'<div class="card '+$Card[0]+'"><span>'+$Card[1]+'</span><strong>'+$Card[2]+'</strong><em>'+$(if($Card[3]){ConvertTo-RemoteOpsHtml $Card[3]}else{'&nbsp;'})+'</em></div>'}) -join ''
    $Bar=Get-RemoteOpsOutcomeBar -Success ([int]$Report.Success) -Skipped ([int]$Report.Neutral) -Problem $Problem -Other $Cancelled
    $AttentionHtml='<section class="panel"><h2>Kesilen ve dikkat gerektiren hedefler</h2><div class="cards">'+(@(foreach($Key in @('Cancelled','Indeterminate','RebootRequired')){
        '<div class="card"><span>'+(ConvertTo-RemoteOpsHtml $script:RemoteOpsOutcomeTitles[$Key])+'</span><strong data-outcome="'+$Key+'">'+([int](Get-RemoteOpsRowValue $Report @($Key)))+'</strong></div>'
    }) -join '')+'</div></section>'
    $CategoryHtml=if(@($Report.Categories).Count -eq 0){'<div class="empty">Se'+[char]0x00E7+'ilen g'+[char]0x00FC+'nde kay'+[char]0x0131+'tl'+[char]0x0131+' i'+[char]0x015F+'lem yok.</div>'}else{
        @(foreach($Category in $Report.Categories){
            $OperationHtml=@(foreach($Operation in $Category.Operations){'<div>'+(ConvertTo-RemoteOpsHtml $Operation.Title)+'<span>'+$Operation.Count+' &middot; '+(Format-RemoteOpsPercent $Operation.Percent)+'</span></div>'}) -join ''
            '<div class="cat"><div class="cat-head"><b>'+(ConvertTo-RemoteOpsHtml $Category.Title)+'</b><span>'+$Category.Count+' i'+[char]0x015F+'lem &middot; '+(Format-RemoteOpsPercent $Category.Percent)+' &middot; '+$Category.Computers+' bilgisayar</span></div><div class="bar"><i style="width:'+([double]$Category.Percent).ToString('0.##',$script:RemoteOpsInv)+'%"></i></div>'+(Get-RemoteOpsOutcomeBar -Success $Category.Success -Skipped $Category.Neutral -Problem ([int]$Category.Error))+'<div class="ops">'+$OperationHtml+'</div></div>'
        }) -join ''
    }
    $PackageHtml=''
    if($null -ne $Report.PSObject.Properties['Packages'] -and @($Report.Packages).Count -gt 0){
        $PackageHtml='<section class="panel"><h2>Paket ve eylem baz&#305;nda hedef sonu&#231;lar&#305;</h2><div class="table-wrap"><table class="mini"><thead><tr><th>Paket</th><th>Eylem</th><th>Hedef denemesi</th><th>Ba&#351;ar&#305;l&#305;</th><th>Atland&#305;</th><th>Dikkat</th><th>&#304;ptal</th></tr></thead><tbody>'+(@(foreach($Package in $Report.Packages){
            '<tr data-package="'+(ConvertTo-RemoteOpsHtml $Package.Id)+'" data-action="'+(ConvertTo-RemoteOpsHtml $Package.Action)+'"><td>'+(ConvertTo-RemoteOpsHtml $Package.Name)+'</td><td>'+(ConvertTo-RemoteOpsHtml $Package.ActionTitle)+' <small>('+(ConvertTo-RemoteOpsHtml $Package.Action)+')</small></td><td>'+$Package.Count+'</td><td>'+$Package.Success+'</td><td>'+$Package.Skipped+'</td><td>'+$Package.Problems+'</td><td>'+$Package.Cancelled+'</td></tr>'
        }) -join '')+'</tbody></table></div></section>'
    }
    $MaxHour=[Math]::Max(1,(@($Report.Hours)|Measure-Object -Maximum).Maximum)
    $HourBars=@(for($Hour=0;$Hour -lt 24;$Hour++){'<div style="height:'+[math]::Round(100.0*$Report.Hours[$Hour]/$MaxHour).ToString($script:RemoteOpsInv)+'%" title="'+('{0:00}:00 - {1} i'+[char]0x015F+'lem' -f $Hour,$Report.Hours[$Hour])+'"></div>'}) -join ''
    $HourLabels=@(for($Hour=0;$Hour -lt 24;$Hour++){'<span>'+$(if($Hour%3 -eq 0){'{0:00}' -f $Hour}else{''})+'</span>'}) -join ''
    $ComputerRows=if(@($Report.TopComputers).Count -eq 0){'<tr><td colspan="3" class="empty">Kay'+[char]0x0131+'t yok.</td></tr>'}else{@(foreach($Computer in $Report.TopComputers){'<tr><td>'+(ConvertTo-RemoteOpsHtml $Computer.ComputerName)+'</td><td>'+$Computer.Count+'</td><td>'+$Computer.Problems+'</td></tr>'}) -join ''}
    $Html=@"
<!doctype html>
<html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="color-scheme" content="light dark"><title>G&uuml;nl&uuml;k Rapor $DateText | Remote Ops</title>
<style>
$Style
</style></head><body>
<div class="top"><div class="brand">REMOTE OPS &middot; G&Uuml;NL&Uuml;K RAPOR</div><h1>$DateText</h1><div class="chips"><span class="chip">Olu&#351;turulma: $Created</span></div></div>
<main><section class="cards" aria-label="G&uuml;nl&uuml;k &ouml;zet">$CardHtml</section>
<section class="panel"><h2>Sonu&ccedil; da&#287;&#305;l&#305;m&#305;</h2>$Bar</section>
$AttentionHtml
$PackageHtml
<div class="grid2"><section class="panel"><h2>&#304;&#351;lem yap&#305;lan kategoriler</h2>$CategoryHtml</section>
<div><section class="panel"><h2>Saatlik yo&#287;unluk</h2><div class="hours">$HourBars</div><div class="hours-x">$HourLabels</div></section>
<section class="panel"><h2>En fazla i&#351;lem yap&#305;lan bilgisayarlar</h2><table class="mini"><thead><tr><th>Bilgisayar</th><th>&#304;&#351;lem</th><th>Sorunlu</th></tr></thead><tbody>$ComputerRows</tbody></table></section></div></div></main>
<footer>&#304;&#351;lem say&#305;s&#305; bilgisayar ba&#351;&#305;na tamamlanan her deneme anlam&#305;na gelir; ba&#351;ar&#305;l&#305; olmas&#305; gerekmez.</footer>
</body></html>
"@
    $Parent=Split-Path -Parent $Path
    if(-not(Test-Path -LiteralPath $Parent -PathType Container)){
        New-Item -ItemType Directory -Path $Parent -Force|Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Html -Encoding UTF8 -ErrorAction Stop
    return $Path
}

# Raporu varsayilan tarayicida acar (cmdlet tam adiyla: Runner'daki Start-Process golgesine takilmaz).
function Open-RemoteOpsHtmlFile {
    param([Parameter(Mandatory=$true)][string]$Path)
    Microsoft.PowerShell.Management\Start-Process -FilePath $Path -ErrorAction Stop
}

# CALISMA RAPORLARINI TAMAMLAR (Runner sonunda cagrilir):
#   - Her kaynak (Result.ResultCsv + yakalanan CSV/HTML) icin calisma klasorune
#     CSV kopyasi ve sonuc HTML'i yazilir (sadece bu OperationID'nin satirlari)
#   - Tum Write-Host mesajlari Activity.csv/html olarak yazilir
#   - Health gibi bir ana rapor varsa sadece o acilir, yoksa yazilan HTML'ler acilir
function Complete-RemoteOpsReports {
    [CmdletBinding()]
    param($Result,[string]$Title,[string]$OperationID,[string]$ReportRoot,[string[]]$Candidates=@(),[object[]]$Messages=@(),[string]$PrimaryReport='')
    try{
        if(-not(Test-Path -LiteralPath $ReportRoot -PathType Container)){
            New-Item -ItemType Directory -Path $ReportRoot -Force -ErrorAction Stop|Out-Null
        }
    }
    catch{Write-Warning "Result report folder could not be created: $($_.Exception.Message)";return}
    $Sources=@($Candidates)
    if($null -ne $Result -and $null -ne $Result.PSObject.Properties['ResultCsv'] -and -not [string]::IsNullOrWhiteSpace([string]$Result.ResultCsv)){
        $Sources+=[string]$Result.ResultCsv
    }
    $Sources=@($Sources|Select-Object -Unique)
    $Written=@()
    # Her sonuc kaynagi icin: satirlari al (nesne > CSV > dosyayi aynen kopyala) ve raporla.
    foreach($Source in $Sources){
        try{
            $CsvSource=if([System.IO.Path]::GetExtension($Source) -ieq '.html'){[System.IO.Path]::ChangeExtension($Source,'.csv')}else{$Source}
            $HasRows=$null -ne $Result -and $null -ne $Result.PSObject.Properties['Rows'] -and $null -ne $Result.PSObject.Properties['ResultCsv'] -and [string]$Result.ResultCsv -eq $Source
            if($HasRows){
                $Rows=@($Result.Rows)
            }elseif(Test-Path -LiteralPath $CsvSource -PathType Leaf){
                $Rows=@(Import-Csv -LiteralPath $CsvSource -Delimiter ';' -ErrorAction Stop)
            }else{
                if(Test-Path -LiteralPath $Source -PathType Leaf){
                    $Destination=Join-Path $ReportRoot ([System.IO.Path]::GetFileName($Source))
                    Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
                    if([System.IO.Path]::GetExtension($Source) -ieq '.html'){
                        $Written+=$Destination
                    }
                }
                continue
            }
            if($Rows.Count -gt 0 -and $null -ne $Rows[0].PSObject.Properties['OperationID']){
                $Rows=@($Rows|Where-Object{$null -eq $_.PSObject.Properties['OperationID'] -or $_.OperationID -eq $OperationID})
            }
            if($Title -notin @('ApplicationCheck','PackageTrigger')){
                $IssueCount=@($Rows|Where-Object{(Get-RemoteOpsRowCategory $_) -eq 'issue'}).Count
                $SuccessCount=@($Rows|Where-Object{(Get-RemoteOpsRowCategory $_) -eq 'success'}).Count
                $SkippedCount=@($Rows|Where-Object{(Get-RemoteOpsRowCategory $_) -eq 'neutral'}).Count
                Write-Host ("{0} summary | Records: {1} | Success: {2} | Skipped/Missing/Unreachable: {3} | Error: {4}" -f $Title,$Rows.Count,$SuccessCount,$SkippedCount,$IssueCount)
            }
            $Stem=[System.IO.Path]::GetFileNameWithoutExtension($CsvSource)
            $CsvPath=Join-Path $ReportRoot ($Stem+'.csv')
            $Headers=@($Rows|ForEach-Object{$_.PSObject.Properties.Name}|Select-Object -Unique)
            if($Rows.Count -gt 0){
                $Rows|Select-Object $Headers|Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8 -Delimiter ';' -ErrorAction Stop
            }
            elseif(Test-Path -LiteralPath $CsvSource -PathType Leaf){
                $Header=Get-Content -LiteralPath $CsvSource -TotalCount 1
                Set-Content -LiteralPath $CsvPath -Value $Header -Encoding UTF8
            }
            $Written+=Write-RemoteOpsResultHtml -Path (Join-Path $ReportRoot ($Stem+'.html')) -Title $Title -OperationID $OperationID -Rows $Rows -CsvPath $CsvPath
        }
        catch{Write-Warning "Result report generation failed for '$Source': $($_.Exception.Message)"}
    }
    try{
            # Activity raporu: operasyon sirasinda yazilan tum mesajlar.
            $CsvPath=Join-Path $ReportRoot 'Activity.csv'
            if($Messages.Count -gt 0){
                $Messages|Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
            }else{
                Set-Content -LiteralPath $CsvPath -Value 'Message' -Encoding UTF8
            }
            $ActivityReport=Write-RemoteOpsResultHtml -Path (Join-Path $ReportRoot 'Activity.html') -Title ((Get-RemoteOpsOperationTitle -Name $Title)+' / Etkinlik') -OperationID $OperationID -Rows $Messages -CsvPath $CsvPath
            if($Written.Count -eq 0){$Written+=$ActivityReport}
    }
    catch{Write-Warning "Activity report generation failed: $($_.Exception.Message)"}
    if(-not [string]::IsNullOrWhiteSpace($PrimaryReport) -and (Test-Path -LiteralPath $PrimaryReport -PathType Leaf)){
        $Written=@($PrimaryReport)
    }
    foreach($Path in @($Written|Select-Object -Unique)){
        try{Open-RemoteOpsHtmlFile -Path $Path}
        catch{Write-Warning "Report saved but could not be opened: $Path | $($_.Exception.Message)"}
    }
}

# PAKET SONUCU: her satira Outcome (Completed/Skipped/Error) ve OutcomeDetail ekler.
#   Skipped   : karar asamasinda atlanan hedef (zaten kurulu/yok vb.)
#   Completed : paket basarili + son kontrol gecti (kontrolsuz modda sadece exit code)
#   Error     : diger tum durumlar (erisilemedi, paket hatasi, son kontrol basarisiz)
# Versiyon kontrollu kurulumda son kontrol versiyonu hedefe esit/yeni olmali.
function Set-RemoteOpsPackageOutcome {
    param([object[]]$Rows,[ValidateSet('INSTALL','UNINSTALL')][string]$Action,[string]$CheckMode,[string]$TargetVersion='',[scriptblock]$VersionComparer,[ValidateSet('AtLeast','Exact')][string]$VersionMatchPolicy='AtLeast')
    foreach($Row in $Rows){
        $Execution=Get-RemoteOpsRowValue -Row $Row -Names @('ExecutionStatus')
        $Decision=Get-RemoteOpsRowValue -Row $Row -Names @('Decision')
        $Outcome='Error'
        $Description='error/unreachable'
        if($Execution -eq 'NotRun' -and $Decision -eq 'Unreachable'){$Outcome='Unreachable';$Description='Atlandi - Erisilemedi; islem calistirilmadi.'}
        elseif($Execution -eq 'Skipped'){
            $Outcome='Skipped'
            $Description=switch($Decision){'AlreadyPresent'{'already installed'}'AlreadyAtTarget'{'already installed (target version)'}'NewerVersionPresent'{'already installed (newer version)'}'AlreadyAbsent'{'already uninstalled'}default{"skipped ($Decision)"}}
        }
        elseif($Execution -like 'Success*'){
            $PostStatus=Get-RemoteOpsRowValue -Row $Row -Names @('PostCheckStatus')
            $PostError=Get-RemoteOpsRowValue -Row $Row -Names @('PostCheckErrorDetail')
            $PostPassed=$false
            if($CheckMode -eq 'SadeceTetikle'){$PostPassed=$true}
            elseif([string]::IsNullOrWhiteSpace($PostError)){
                if($Action -eq 'INSTALL'){$PostPassed=$PostStatus -eq 'Var'}
                elseif($Action -eq 'UNINSTALL'){$PostPassed=$PostStatus -eq 'Yok'}
            }
            if($PostPassed -and $Action -eq 'INSTALL' -and $CheckMode -eq 'VersiyonKontrollu'){
                $PostVersion=Get-RemoteOpsRowValue -Row $Row -Names @('PostCheckDisplayVersion')
                $PostPassed=$false
                if($null -ne $VersionComparer){
                    $Comparison=& $VersionComparer -CurrentVersion $PostVersion -TargetVersion $TargetVersion
                    $PostPassed=[bool]$Comparison.Comparable -and $(if($VersionMatchPolicy -eq 'Exact'){[int]$Comparison.Result -eq 0}else{[int]$Comparison.Result -ge 0})
                }
            }
            if($PostPassed){
                $Outcome='Completed'
                $Description=if($CheckMode -eq 'SadeceTetikle'){'package execution success (application not verified)'}elseif($Action -eq 'INSTALL'){'installation success'}else{'uninstallation success'}
            }
            else{$Description='execution completed, application verification failed'}
        }
        $Row|Add-Member -NotePropertyName Outcome -NotePropertyValue $Outcome -Force
        $Row|Add-Member -NotePropertyName OutcomeDetail -NotePropertyValue $Description -Force
    }
}

# Paket calismasinin hedef bazli ve toplam ozetini Activity'ye yazar.
function Write-RemoteOpsPackageSummary {
    param([object[]]$Rows,[ValidateSet('INSTALL','UNINSTALL')][string]$Action,[string]$CheckMode)
    if(@($Rows|Where-Object{$null -eq $_.PSObject.Properties['Outcome']}).Count -gt 0){
        Set-RemoteOpsPackageOutcome -Rows $Rows -Action $Action -CheckMode $CheckMode
    }
    $Completed=0
    $Skipped=0
    $Errors=0
    foreach($Row in $Rows){
        $Client=Get-RemoteOpsRowValue -Row $Row -Names @('ComputerName','IstemciAdi')
        if($Row.Outcome -eq 'Completed'){$Completed++}elseif($Row.Outcome -in @('Skipped','Unreachable')){$Skipped++}else{$Errors++}
        $ErrorDetail=if($Row.Outcome -eq 'Error'){Get-RemoteOpsRowValue -Row $Row -Names @('ErrorDetail','PostCheckErrorDetail')}else{''}
        Write-Host ("{0} - {1} {2}" -f $Client,$Row.OutcomeDetail,$ErrorDetail).Trim()
    }
    $Label=if($Action -eq 'INSTALL'){'Installed'}else{'Uninstalled'}
    Write-Host ("{0} : {1}" -f $Label,$Completed)
    Write-Host ("Skipped : {0}" -f $Skipped)
    Write-Host ("Error : {0}" -f $Errors)
}

$script:RemoteOpsOutcomeTitles.Completed='Tamamlandı'
$script:RemoteOpsCategoryTitles.Recipes='Reçeteler'
