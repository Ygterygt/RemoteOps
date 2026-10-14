####################################################################
# REMOTE OPS - RUNNER (is yapan katman)  -  RemoteOps.Runner.ps1
#
# GUI (RemoteOps.App.ps1) her operasyon icin bu dosyayi AYRI bir powershell.exe
# sureci olarak, secili hesabin kimligiyle calistirir. Calisma modlari:
#   -RequestBase64      : normal operasyon (JSON istek Base64 olarak gelir)
#   -PreflightBase64    : sadece erisim testi (dosya okuma/yazma), 'ACCESS_PREFLIGHT_OK' yazar
#   -ListOperations     : yuklu modul/plugin operasyonlarini listeler (tani amacli)
#   -ValidateHostWorkers: Modules\ApplicationWorkers.ps1 icindeki worker'lari parse eder (tani)
#
# Onemli tasarim noktalari:
# 1) Uygulama/paket worker'lari Modules\ApplicationWorkers.ps1 dosyasindadir. Dosya AST
#    olarak parse edilir ve icinden worker scriptblock'lari ($RegistryCheckScript,
#    $PackageScript, $InstalledApplicationInventoryScript) ve bazi fonksiyonlar ADIYLA
#    cekilir. MD_Script.ps1'e (konsol araci) HIC bagimlilik yoktur.
# 2) Modules\*.ps1 dosyalari dot-source edilir. Bu moduller aslinda konsol menusu
#    (Read-Host) ile calisir; Runner, Read-Host'u kendi fonksiyonuyla degistirip
#    GUI'den gelen degerleri sirayla "cevap" olarak verir (PromptAnswers kuyrugu).
# 3) Write-Host ve Start-Process de golgelenir: menu yazilari gizlenir, modullerin
#    actigi HTML/CSV raporlar yakalanip tek bir calisma raporunda birlestirilir.
# 4) Hedefler varsayilan olarak SIRAYLA islenir (Invoke-TargetBatch). Paralel-guvenli
#    operasyonlarda, istenirse her hedef icin ayri worker surec acilir (Invoke-ParallelTargets).
# 5) Sonuc: Logs\Operations\<Operasyon>\<OperationID>\ altinda Results.csv/html,
#    Activity.csv/html, RemoteOps.log ve Detail klasoru + gunluk rapor icin Ledger kaydi.
####################################################################
[CmdletBinding()]
param([string]$RequestBase64,[string]$PreflightBase64,[switch]$ListOperations,[switch]$ValidateHostWorkers)

# Strict mode + hata olursa dur. Request degiskeni catch blogunda da okunabilsin diye en basta tanimlanir.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$Request = $null
try {
    # Rapor/sonuc siniflandirma fonksiyonlari (Get-RemoteOpsRowCategory, Complete-RemoteOpsReports ...).
    . (Join-Path $PSScriptRoot 'RemoteOps.Reports.ps1')
    . (Join-Path $PSScriptRoot 'RemoteOps.Packages.ps1')
    . (Join-Path $PSScriptRoot 'RemoteOps.Deployment.ps1')
    . (Join-Path $PSScriptRoot 'RemoteOps.RunState.ps1')
    # ReportCandidates : modullerin Start-Process ile acmaya calistigi .html/.csv dosyalari (sonuc kaynagi)
    # OperationMessages: Write-Host ile yazilan tum mesajlar (Activity raporu + sonuc tahmini icin)
    $script:ReportCandidates=@()
    $script:OperationMessages=@()
    # ====================================================================
    # KONSOL DAVRANISINI GUI'YE UYARLAYAN GOLGE (override) FONKSIYONLAR
    # ====================================================================
    #
    # Modullerin konsol menu satirlarini (=====, "1 - ...", menu basliklari) tanir;
    # bunlar GUI Activity paneline yazilmaz.
    function Test-ConsoleMenuText {
        param([string]$Text)
        return ($Text -match '^\s*$|^\s*[=\-]{3,}\s*$|^\s*\d+\s*-\s+' -or $Text.Trim() -in @('SERVICE AND TASK OPERATIONS','REGISTRY OPERATIONS','DOSYA OPERASYONLARI'))
    }
    # Start-Process golgesi: .html/.csv acma istekleri tarayici acmak yerine
    # ReportCandidates listesine eklenir (raporlar sonradan birlestirilir).
    # Diger tum Start-Process cagrilari (PsExec vb.) gercek cmdlet'e aynen iletilir.
    function Start-Process {
        [CmdletBinding()]
        param([Parameter(Mandatory=$true,Position=0)][string]$FilePath,[string[]]$ArgumentList,[string]$WorkingDirectory,[switch]$Wait,[switch]$PassThru,[string]$RedirectStandardOutput,[string]$RedirectStandardError,[string]$WindowStyle)
        if([System.IO.Path]::GetExtension($FilePath) -in @('.html','.csv')){$script:ReportCandidates+=$FilePath;return}
        Microsoft.PowerShell.Management\Start-Process @PSBoundParameters
    }
    # Write-Host golgesi: menu metinlerini atlar, mesaji OperationMessages'a kaydeder.
    # Hedef islenirken (TargetOutputQuiet=$true) mesaj ekrana degil teknik loga yazilir;
    # boylece Activity'de hedef basina tek satir (PC - Success/Error...) gorunur.
    function Write-Host {
        [CmdletBinding()]
        param([Parameter(Position=0)][object[]]$Object,[string]$Separator=' ',[switch]$NoNewline,[ConsoleColor]$ForegroundColor,[ConsoleColor]$BackgroundColor)
        $Text=@($Object|ForEach-Object{[string]$_}) -join $Separator
        if(Test-ConsoleMenuText -Text $Text){return}
        if(-not [string]::IsNullOrWhiteSpace($Text)){$script:OperationMessages+=[PSCustomObject]@{Message=$Text}}
        $QuietState=Get-Variable -Name TargetOutputQuiet -Scope Script -ErrorAction SilentlyContinue
        if($null -ne $QuietState -and [bool]$QuietState.Value){
            try{Write-RemoteOpsLog -Level INFO -Message $Text}catch{ }
            return
        }
        Microsoft.PowerShell.Utility\Write-Host @PSBoundParameters
    }
    # ====================================================================
    # YOLLAR VE WORKER DOSYASI (Modules\ApplicationWorkers.ps1) AST'SI
    # Modules klasoru (icinde ApplicationWorkers.ps1 ile), RemoteOps.App klasorunun
    # bir ust dizininde (veya kardes MD_script klasorunde) aranir.
    # ====================================================================
    $AppParent = Split-Path -Parent $PSScriptRoot
    $ProjectCandidates = @($AppParent,(Join-Path $AppParent 'MD_script'),(Join-Path $AppParent 'MD_Script'))
    $ProjectRoot = $ProjectCandidates | Where-Object { (Test-Path -LiteralPath (Join-Path $_ 'Modules\ApplicationWorkers.ps1') -PathType Leaf) } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace([string]$ProjectRoot)) {
        throw "Could not locate Modules\ApplicationWorkers.ps1 next to the app folder or in a sibling MD_script project folder. App='$PSScriptRoot'"
    }
    $WorkspaceRoot = [string]$ProjectRoot
    $ModulesRoot = Join-Path $WorkspaceRoot 'Modules'
    $WorkersPath = Join-Path $ModulesRoot 'ApplicationWorkers.ps1'
    $BasePath = 'C:\Temp\YD_RemoteOps.App'
    # Modullerin Register-AOModule ile kendini tanittigi listeler ve Read-Host cevap kuyrugu.
    $script:AOModules = @()
    $script:AOModuleOperations = @()
    $script:PromptAnswers = New-Object 'System.Collections.Generic.Queue[string]'
    # Worker dosyasi calistirilmadan sadece parse edilir; worker'lar bu AST'den cekilir.
    # (Degisken adi HostAst testlerle uyum icin korunmustur.)
    $HostTokens = $null
    $HostParseErrors = $null
    $script:HostAst = [System.Management.Automation.Language.Parser]::ParseFile($WorkersPath,[ref]$HostTokens,[ref]$HostParseErrors)
    if ($HostParseErrors.Count -gt 0) {
        Write-Host "Worker file has $($HostParseErrors.Count) parser issue(s); checking only the requested reusable worker." -ForegroundColor Yellow
    }

    # Modul kayit fonksiyonlarinin hafif kopyalari: modul dosyalari dot-source edildiginde
    # kendilerini buraya kaydeder (MD_Script.ps1'deki asil versiyonun yerine).
    function Register-AOModule {
        param([string]$Name,[string]$Version,[string]$MinimumHostApiVersion,[string]$SourcePath,[scriptblock]$Initializer)
        $script:AOModules += [PSCustomObject]@{Name=$Name;Version=$Version;Initializer=$Initializer}
    }
    function Register-AOModuleOperation {
        param([string]$ModuleName,[string]$Name,[string]$DisplayName,[string]$EntryPointName,[scriptblock]$Handler)
        $script:AOModuleOperations += [PSCustomObject]@{ModuleName=$ModuleName;Name=$Name;DisplayName=$DisplayName;EntryPointName=$EntryPointName;Handler=$Handler}
    }
    # Read-Host golgesi: modulun sordugu her soruya PromptAnswers kuyrugundan sirayla
    # cevap verir. Kuyruk biterse hata firlatir (GUI'den eksik deger gelmis demektir).
    function Read-Host {
        param([string]$Prompt,[switch]$AsSecureString)
        if ($script:PromptAnswers.Count -eq 0) { throw "No GUI value was supplied for prompt: $Prompt" }
        $Answer = $script:PromptAnswers.Dequeue()
        if ($AsSecureString) { return ConvertTo-SecureString -String $Answer -AsPlainText -Force }
        return $Answer
    }
    # ====================================================================
    # LOG / ILERLEME / SONUC SINIFLANDIRMA
    # ====================================================================
    #
    # Teknik log: Logs\Operations\<Operasyon>\<RunID>\RemoteOps.log
    # Paralel worker'lar ayni dosyaya yazabildigi icin 8 denemeye kadar tekrar edilir.
    function Write-RemoteOpsLog {
        param([string]$Level,[string]$Message)
        $LogRoot = Join-Path $BasePath 'Logs\RemoteOps'
        $LogRunID=Get-Variable RunLogID -Scope Script -ErrorAction SilentlyContinue
        if($null -ne $LogRunID -and -not [string]::IsNullOrWhiteSpace([string]$LogRunID.Value) -and $null -ne (Get-Variable OperationName -ErrorAction SilentlyContinue)){
            $LogRoot=Join-Path (Join-Path (Join-Path $BasePath 'Logs\Operations') $OperationName) ([string]$LogRunID.Value)
        }
        elseif($null -ne (Get-Variable OperationName -ErrorAction SilentlyContinue) -and $null -ne (Get-Variable OperationID -ErrorAction SilentlyContinue)){
            $LogRoot=Join-Path (Join-Path (Join-Path $BasePath 'Logs\Operations') $OperationName) $OperationID
        }
        if (-not (Test-Path -LiteralPath $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null }
        $LogLine=('{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message)
        for($Attempt=1;$Attempt -le 8;$Attempt++){
            $LogStream=$null
            try{
                # PS 5.1 Add-Content probes encoding while parallel writers hold the file.
                # A write-only append stream avoids intermittent "stream not readable" errors.
                $LogStream=[IO.File]::Open((Join-Path $LogRoot 'RemoteOps.log'),[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::Read)
                $LogBytes=[Text.Encoding]::UTF8.GetBytes($LogLine+"`r`n")
                $LogStream.Write($LogBytes,0,$LogBytes.Length)
                break
            }
            catch{if($Attempt -eq 8){throw};Start-Sleep -Milliseconds (40*$Attempt)}
            finally{if($null -ne $LogStream){$LogStream.Dispose()}}
        }
    }
    # Modullerin OperationHistoryWriter cagrilarini teknik loga yonlendirir.
    function Write-RemoteOpsHistory {
        param($OperationID,$OperationDate,$OperationTime,$IstemciAdi,$Modul,$Operasyon,$Sonuc,$Aciklama)
        Write-RemoteOpsLog -Level $Sonuc -Message ("{0} | {1} | {2} | {3}" -f $IstemciAdi,$Modul,$Operasyon,$Aciklama)
    }
    # GUI degerlerini Read-Host cevap kuyruguna ekler (menu secim numarasi dahil).
    function Add-Answers {
        param([string[]]$Answers)
        foreach ($Answer in $Answers) {
            $script:PromptAnswers.Enqueue([string]$Answer)
        }
    }
    # GUI'nin okudugu progress.json dosyasini yazar (Total/Completed/CurrentTarget/Stage).
    # Once gecici dosyaya yazilir, sonra atomik olarak degistirilir (GUI yarim dosya okumasin).
    function Write-TargetProgress {
        param([string]$Path,[int]$Total,[int]$Completed,[string]$CurrentTarget,[string]$Stage,[object[]]$Targets)
        if([string]::IsNullOrWhiteSpace($Path)){return}
        if($null -eq (Get-Variable RemoteOpsTargetProgress -Scope Script -ErrorAction SilentlyContinue)){$script:RemoteOpsTargetProgress=@{}}
        if($PSBoundParameters.ContainsKey('Targets')){$script:RemoteOpsTargetProgress[$Path]=@($Targets)}
        $LiveTargets=if($script:RemoteOpsTargetProgress.ContainsKey($Path)){@($script:RemoteOpsTargetProgress[$Path])}else{@()}
        $State=[PSCustomObject]@{Total=$Total;Completed=$Completed;Pending=($Total-$Completed);CurrentTarget=$CurrentTarget;Stage=$Stage;Targets=@($LiveTargets);UpdatedAt=(Get-Date).ToString('o')}
        $Temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
        try{
            $Json=$State|ConvertTo-Json -Depth 8 -Compress
            [System.IO.File]::WriteAllText($Temporary,$Json,[System.Text.Encoding]::UTF8)
            if([System.IO.File]::Exists($Path)){
                [System.IO.File]::Replace($Temporary,$Path,[System.Management.Automation.Language.NullString]::Value)
            }
            else{
                try{[System.IO.File]::Move($Temporary,$Path)}
                catch [System.IO.IOException]{
                    if(-not [System.IO.File]::Exists($Path)){throw}
                    [System.IO.File]::Replace($Temporary,$Path,[System.Management.Automation.Language.NullString]::Value)
                }
            }
        }
        catch{Write-Warning "Progress update failed: $($_.Exception.Message)"}
        finally{
            if([System.IO.File]::Exists($Temporary)){
                Remove-Item -LiteralPath $Temporary -Force -ErrorAction SilentlyContinue
            }
        }
    }
    # Bir hedefin sonuc satirlarindan tek bir sonuc uretir: Error > Unreachable > Success > Skipped.
    # Hic yapisal satir yoksa o hedefe ait mesajlardaki HATA/OK kelimelerine bakilir.
    function Get-TargetOutcome {
        param([object[]]$Rows,[object[]]$Messages=@(),[string]$Target='')
        if(@($Rows|Where-Object{(Get-RemoteOpsRowValue $_ @('Step')) -eq 'Result'}).Count -gt 0){return Get-RemoteOpsComputerOutcome $Rows}
        $HasError=$false
        $HasUnreachable=$false
        $HasSuccess=$false
        $HasSkipped=$false
        foreach($Row in $Rows){
            $Status=Get-RemoteOpsRowValue -Row $Row -Names @('ExecutionStatus','Status','Durum','CollectionStatus','OperasyonSonucu')
            $Decision=Get-RemoteOpsRowValue -Row $Row -Names @('Decision')
            if($Status -match '^(?i:Unreachable|Erisilemedi)$' -or $Decision -eq 'Unreachable'){
                $HasUnreachable=$true
                continue
            }
            switch(Get-RemoteOpsRowCategory $Row){'issue'{$HasError=$true}'success'{$HasSuccess=$true}'neutral'{$HasSkipped=$true}}
        }
        if(-not $HasError -and -not $HasUnreachable -and -not $HasSuccess -and -not $HasSkipped){
            $TargetPrefix='^'+[regex]::Escape($Target)+'\s*:'
            foreach($Entry in $Messages){
                $Text=[string]$Entry.Message
                if($Text -notmatch $TargetPrefix){continue}
                if($Text -match '\b(HATA|FAILED|ERROR)\b'){$HasError=$true}
                elseif($Text -match '\bOK\b'){$HasSuccess=$true}
            }
        }
        if($HasError){return 'Error'}
        if($HasUnreachable){return 'Unreachable'}
        if($HasSuccess){return 'Success'}
        if($HasSkipped){return 'Skipped'}
        return 'Error'
    }
    # ====================================================================
    # SIRALI CALISMA DONGUSU (varsayilan yol)
    # Her hedef icin:
    #   - $Systems/$Common tek hedefe daraltilir, alt OperationID verilir (<RunID>-0001 ...)
    #   - $InvokeTarget (operasyon switch'i) calistirilir
    #   - Donen Rows veya yakalanan CSV/HTML'den sonuc satirlari toplanir
    #   - Hedef sonucu (Success/Error/...) Activity'ye tek satir yazilir, progress guncellenir
    # ====================================================================
    function Invoke-TargetBatch {
        param([string[]]$InputTargets,[string]$RunOperationID,[string]$ProgressPath,[scriptblock]$InvokeTarget,[int]$IndexOffset=0)
        $BatchRows=New-Object 'System.Collections.Generic.List[object]'
        $BatchOutcomes=New-Object 'System.Collections.Generic.List[object]'
        $LiveTargets=@(foreach($Computer in $InputTargets){[PSCustomObject]@{ComputerName=$Computer;Stage='Pending';Outcome=''}})
        $Completed=0
        Write-TargetProgress -Path $ProgressPath -Total $InputTargets.Count -Completed 0 -CurrentTarget '' -Stage 'Running' -Targets $LiveTargets
        foreach($Target in $InputTargets){
            $Systems=[string[]]@($Target)
            $ReachableSystems=$Systems
            $UnreachableSystems=[string[]]@()
            # Hedef basina alt ID: modullerin ara dosyalari bu ID ile adlanir (sonra Detail'e tasinir).
            $OperationID='{0}-{1:D4}' -f $RunOperationID,($IndexOffset+$Completed+1)
            $Common=$Common.Clone()
            $Common.Systems=$Systems
            $Common.ReachableSystems=$Systems
            $Common.UnreachableSystems=$UnreachableSystems
            $Common.OperationID=$OperationID
            if($null -ne (Get-Variable Request -ErrorAction SilentlyContinue) -and $null -ne $Request){
                $Request=$Request|Select-Object *
                $Request.Targets=$Systems
            }
            $script:ReportCandidates=@()
            $script:PromptAnswers.Clear()
            $MessageStart=$script:OperationMessages.Count
            $TargetRows=@()
            $TargetResult=$null
            $script:TargetOutputQuiet=$true
            $LiveTargets[$Completed].Stage='Running'
            Write-TargetProgress -Path $ProgressPath -Total $InputTargets.Count -Completed $Completed -CurrentTarget $Target -Stage 'Running' -Targets $LiveTargets
            try{
                # Operasyonu bu tek hedef icin calistir.
                $Access=Test-RemoteOpsOperationAccess -ComputerName $Target -Operation $OperationName -InputValues $Values
                if($Access.Status -ne 'Success'){
                    $AccessOutcome=if($Access.Status -eq 'Unreachable'){'Unreachable'}else{'Error'}
                    $Reason=if($AccessOutcome -eq 'Unreachable'){'Atlandi - Erisilemedi; islem calistirilmadi.'}else{'Erisim kontrolu hatasi; islem calistirilmadi.'}
                    $AccessRow=[PSCustomObject]@{ComputerName=$Target;OperationID=$OperationID;Step='Result';Status=$AccessOutcome;ErrorDetail=($Reason+' '+$Access.Detail)}
                    $TargetResult=[PSCustomObject]@{ResultCsv=(Join-Path $RunReportRoot ($OperationID+'-access.csv'));Rows=@($AccessRow)}
                    if($OperationName -eq 'PackageDeployment'){
                        $Definition=$Values.PackageDefinition
                        foreach($Field in @('PackageName','PackageId','PackageRevision','Action')){
                            $Value=switch($Field){'PackageName'{$Definition.Name}'PackageId'{$Definition.Id}'PackageRevision'{$Definition.Revision}'Action'{$Values.Action}}
                            Add-Member -InputObject $AccessRow -NotePropertyName $Field -NotePropertyValue $Value
                        }
                        $BlockedOutcome=[PSCustomObject]@{ComputerName=$Target;Outcome=$AccessOutcome;CompletedAt=(Get-Date);Detail=$AccessRow.ErrorDetail;PackageName=$Definition.Name;PackageId=$Definition.Id;PackageRevision=$Definition.Revision;Action=$Values.Action}
                        Add-Member -InputObject $TargetResult -NotePropertyName Outcomes -NotePropertyValue @($BlockedOutcome)
                    }

                }else{$TargetResult=& $InvokeTarget}
                $Sources=@($script:ReportCandidates)
                if($null -ne $TargetResult -and $null -ne $TargetResult.PSObject.Properties['ResultCsv'] -and -not [string]::IsNullOrWhiteSpace([string]$TargetResult.ResultCsv)){
                    $Sources+=[string]$TargetResult.ResultCsv
                }
                $TargetRows=@()
                # Sonuc satirlarini topla: nesnede Rows varsa onu, yoksa CSV dosyasini (HTML ise yanindaki CSV) oku.
                # Sadece bu hedefin alt OperationID'sine ait satirlar alinir ve calisma ID'sine cevrilir.
                foreach($Source in @($Sources|Select-Object -Unique)){
                    $HasRows=$null -ne $TargetResult -and $null -ne $TargetResult.PSObject.Properties['Rows'] -and [string]$TargetResult.ResultCsv -eq $Source
                    if($HasRows){$SourceRows=@($TargetResult.Rows)}else{
                        $CsvSource=if([System.IO.Path]::GetExtension($Source) -ieq '.html'){[System.IO.Path]::ChangeExtension($Source,'.csv')}else{$Source}
                        $SourceRows=if(Test-Path -LiteralPath $CsvSource -PathType Leaf){@(Import-Csv -LiteralPath $CsvSource -Delimiter ';' -ErrorAction Stop)}else{@()}
                    }
                    foreach($Row in $SourceRows){
                        if($null -ne $Row.PSObject.Properties['OperationID']){
                            if([string]$Row.OperationID -ne $OperationID){continue}
                            $Row.OperationID=$RunOperationID
                        }
                        $TargetRows+=$Row
                    }
                }
                # Sadece BU hedefe ait satirlar kalir. Bazi kaynaklar (orn. coklu bilgisayar iceren bir silme
                # yedeginden Restore) diger bilgisayarlar icin de satir uretir; bunlar bu hedefin sonucunu
                # (orn. 'Erisilemedi' satiri yuzunden Unreachable) bozmamali ve raporda tekrar etmemeli.
                # Bilgisayar kolonu olmayan satirlar (genel bilgi satirlari) oldugu gibi korunur.
                $ScopedTargetRows=@($TargetRows|Where-Object{
                    $RowComputer=Get-RemoteOpsRowValue -Row $_ -Names @('ComputerName','IstemciAdi','ClientName')
                    [string]::IsNullOrWhiteSpace($RowComputer) -or [string]::Equals($RowComputer,$Target,[System.StringComparison]::OrdinalIgnoreCase)
                })
                if($TargetRows.Count -gt 0 -and $ScopedTargetRows.Count -eq 0){
                    $ScopedTargetRows=@([PSCustomObject]@{ComputerName=$Target;Status='Skipped';ErrorDetail='Secilen kaynakta bu bilgisayara ait kayit yok; islem yapilmadi.'})
                }
                $TargetRows=$ScopedTargetRows
                if($TargetRows.Count -eq 0){
                    $TargetRows=@([PSCustomObject]@{ComputerName=$Target;Status='NoData';ErrorDetail='No structured result rows returned. See Activity for details.'})
                }
                foreach($Row in $TargetRows){$BatchRows.Add($Row)}
            }
            catch{
                $TargetRows=@([PSCustomObject]@{ComputerName=$Target;Status='Failed';ErrorDetail=$_.Exception.Message})
                try{Write-RemoteOpsLog -Level ERROR -Message ($_.Exception.Message+' | '+$_.ScriptStackTrace)}catch{ }
                $BatchRows.Add($TargetRows[0])
                Write-Host "$Target : OPERATION FAILED | $($_.Exception.Message)" -ForegroundColor Red
            }
            finally{
                # Hedef bitti: sonucu hesapla, Activity'ye "PC - Sonuc" yaz, ilerlemeyi bir arttir.
                $script:TargetOutputQuiet=$false
                $TargetMessages=@($script:OperationMessages|Select-Object -Skip $MessageStart)
                $Outcome=Get-TargetOutcome -Rows $TargetRows -Messages $TargetMessages -Target $Target
                $Color=switch($Outcome){'Success'{'Green'}'Skipped'{'Yellow'}'Unreachable'{'Yellow'}default{'Red'}}
                Write-Host ("{0} - {1}" -f $Target,$Outcome) -ForegroundColor $Color
                if($null -ne $TargetResult -and $null -ne $TargetResult.PSObject.Properties['Outcomes'] -and @($TargetResult.Outcomes).Count -gt 0){$BatchOutcomes.Add(@($TargetResult.Outcomes)[0])}
                else{$BatchOutcomes.Add([PSCustomObject]@{ComputerName=$Target;Outcome=$Outcome;CompletedAt=(Get-Date)})}
                if($null -ne (Get-Variable OperationName -ErrorAction SilentlyContinue) -and $OperationName -eq 'PackageDeployment'){
                    Write-RemoteOpsDeploymentTerminalCheckpoint $CheckpointRoot $TargetRows $BatchOutcomes[$BatchOutcomes.Count-1] $Values.PackageDefinition ([string]$Values.Action) $RunOperationID
                }
                $LiveTargets[$Completed].Stage='Completed';$LiveTargets[$Completed].Outcome=[string]$BatchOutcomes[$BatchOutcomes.Count-1].Outcome
                $LogStatus=@($TargetRows|ForEach-Object{Get-RemoteOpsRowValue $_ @('LogCollectionStatus')}|Where-Object{$_}|Select-Object -Last 1)
                Add-Member -InputObject $LiveTargets[$Completed] -NotePropertyName LogCollectionStatus -NotePropertyValue ($LogStatus -join '') -Force
                $Completed++
                Write-TargetProgress -Path $ProgressPath -Total $InputTargets.Count -Completed $Completed -CurrentTarget $Target -Stage 'Running'
            }
        }
        $script:ReportCandidates=@()
        Write-TargetProgress -Path $ProgressPath -Total $InputTargets.Count -Completed $Completed -CurrentTarget '' -Stage 'Reporting'
        return [PSCustomObject]@{Completed=$true;ResultCsv=(Join-Path $RunReportRoot 'Results.csv');Rows=@($BatchRows.ToArray());Outcomes=@($BatchOutcomes.ToArray())}
    }
    # ====================================================================
    # ROLLBACK YARDIMCILARI
    # ====================================================================
    #
    # Rollback manifest'ini (CSV) secili hedeflere gore filtreleyip gecici bir kopya uretir.
    # ManifestPath bossa ilgili klasordeki en yeni ve secili hedefleri iceren manifest kullanilir.
    function New-TargetScopedManifest {
        param([string]$ManifestPath,[string]$ManifestRoot,[string]$Label,[string[]]$AllowedObjectTypes=@())
        if(-not [string]::IsNullOrWhiteSpace($ManifestPath)){
            if(-not(Test-Path -LiteralPath $ManifestPath -PathType Leaf)){
                throw "$Label rollback manifest not found: $ManifestPath"
            }
            $Candidates=@(Get-Item -LiteralPath $ManifestPath -ErrorAction Stop)
        }
        else{
            $Candidates=@(Get-ChildItem -LiteralPath $ManifestRoot -Filter '*.csv' -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending)
        }
        $Rows=@()
        $SourceManifest=''
        foreach($Candidate in $Candidates){
            $CandidateRows=@(Import-Csv -LiteralPath $Candidate.FullName -Delimiter ';' -ErrorAction Stop|Where-Object{$Systems -contains [string]$_.ComputerName})
            if($AllowedObjectTypes.Count -gt 0){
                $CandidateRows=@($CandidateRows|Where-Object{$AllowedObjectTypes -contains [string]$_.ObjectType})
            }
            if($CandidateRows.Count -gt 0){$Rows=$CandidateRows;$SourceManifest=$Candidate.FullName;break}
        }
        if($Rows.Count -eq 0){
            throw "$Label rollback manifest not found for selected targets and supported object types."
        }
        $ScopedRoot=Join-Path $BasePath 'Logs\RemoteOps'
        if(-not(Test-Path -LiteralPath $ScopedRoot)){
            New-Item -ItemType Directory -Path $ScopedRoot -Force|Out-Null
        }
        $SafeLabel=$Label -creplace '[^A-Za-z0-9_-]','_'
        $ScopedPath=Join-Path $ScopedRoot ('{0}_{1}_{2}.csv' -f $OperationID,$SafeLabel,[guid]::NewGuid().ToString('N'))
        $Rows|Export-Csv -LiteralPath $ScopedPath -NoTypeInformation -Encoding UTF8 -Delimiter ';' -ErrorAction Stop
        return [PSCustomObject]@{Path=$ScopedPath;SourcePath=$SourceManifest;Rows=$Rows}
    }
    # Registry rollback: manifest'teki eski degeri geri yazar (eski deger yoksa degeri siler).
    # Uzak registry erisimi: CIM/DCOM uzerinden StdRegProv (HKLM = 2147483650).
    function Invoke-RegistryRollbackRequest {
        param($InputValues)
        $ScopedManifestInfo=New-TargetScopedManifest -ManifestPath ([string]$InputValues.ManifestPath) -ManifestRoot (Join-Path $BasePath 'RegistryRollback') -Label 'Registry'
        $ScopedManifest=[string]$ScopedManifestInfo.Path
        $Rows=@()
        try{
            foreach($Entry in Import-Csv -LiteralPath $ScopedManifest -Delimiter ';'){
                $Session=$null
                try{
                    $Session=New-CimSession -ComputerName $Entry.ComputerName -SessionOption (New-CimSessionOption -Protocol Dcom) -OperationTimeoutSec 10 -ErrorAction Stop
                    $Arguments=@{hDefKey=[uint32]2147483650;sSubKeyName=[string]$Entry.RegistryKey;sValueName=[string]$Entry.ValueName}
                    if([string]$Entry.OldExists -eq 'True'){
                        $Arguments.sValue=[string]$Entry.OldValue
                        $Restore=Invoke-CimMethod -CimSession $Session -Namespace 'root\default' -ClassName StdRegProv -MethodName SetStringValue -Arguments $Arguments -ErrorAction Stop
                    }
                    else{
                        $Restore=Invoke-CimMethod -CimSession $Session -Namespace 'root\default' -ClassName StdRegProv -MethodName DeleteValue -Arguments $Arguments -ErrorAction Stop
                    }
                    if([uint32]$Restore.ReturnValue -ne 0){
                        throw "Registry rollback failed with ReturnValue=$($Restore.ReturnValue)."
                    }
                    $Rows += [PSCustomObject]@{ComputerName=$Entry.ComputerName;RegistryKey=$Entry.RegistryKey;ValueName=$Entry.ValueName;Status='Success';ReturnValue=$Restore.ReturnValue;ErrorDetail=''}
                    Write-Host "$($Entry.ComputerName) : REGISTRY ROLLBACK OK | $($Entry.RegistryKey)\$($Entry.ValueName)" -ForegroundColor Green
                }
                catch{
                    $Rows += [PSCustomObject]@{ComputerName=$Entry.ComputerName;RegistryKey=$Entry.RegistryKey;ValueName=$Entry.ValueName;Status='Failed';ReturnValue='';ErrorDetail=$_.Exception.Message}
                    Write-Host "$($Entry.ComputerName) : REGISTRY ROLLBACK FAILED | $($_.Exception.Message)" -ForegroundColor Red
                }
                finally{if($null -ne $Session){Remove-CimSession -CimSession $Session -ErrorAction SilentlyContinue}}
            }
        }
        finally{Remove-Item -LiteralPath $ScopedManifest -Force -ErrorAction SilentlyContinue}
        return Write-ApplicationRows -Name 'RegistryRollback' -Rows $Rows
    }
    # Servis/task rollback: servis durumu/baslangic tipi, task enable/disable ve silinen
    # task'in XML yedeginden yeniden olusturulmasi. Var olan task'in uzerine YAZILMAZ.
    function Invoke-ServiceTaskRollbackRequest {
        param($InputValues)
        $ScopedManifestInfo=New-TargetScopedManifest -ManifestPath ([string]$InputValues.ManifestPath) -ManifestRoot (Join-Path $BasePath 'ServiceTaskRollbacks') -Label 'Service/task' -AllowedObjectTypes @('Service','ScheduledTask')
        $ScopedManifest=[string]$ScopedManifestInfo.Path
        $Rows=@()
        try{
            foreach($Entry in Import-Csv -LiteralPath $ScopedManifest -Delimiter ';'){
                $Session=$null
                try{
                    $Session=Get-ServiceTaskSession $Entry.ComputerName
                    if($Entry.ObjectType -eq 'Service'){
                        $Service=Get-CimInstance -CimSession $Session -ClassName Win32_Service -Filter ("Name='{0}'" -f ([string]$Entry.ObjectName -replace "'","''")) -ErrorAction Stop
                        if($null -eq $Service){throw "Service not found: $($Entry.ObjectName)"}
                        if($Entry.Action -eq 'StartStop'){
                            $Method=if($Entry.OldState -eq 'Running'){'StartService'}else{'StopService'}
                            $Restore=Invoke-CimMethod -CimSession $Session -InputObject $Service -MethodName $Method -Arguments @{} -ErrorAction Stop
                            if([uint32]$Restore.ReturnValue -ne 0){
                                throw "$Method returned $($Restore.ReturnValue)."
                            }
                        }
                        elseif($Entry.Action -eq 'StartupType'){
                            [void](Set-ServiceTaskStartMode -Session $Session -Service $Service -Mode $Entry.OldStartMode)
                        }
                        else{throw "Unsupported service rollback action: $($Entry.Action)"}
                    }
                    elseif($Entry.ObjectType -eq 'ScheduledTask' -and $Entry.Action -eq 'EnableDisable'){
                        if([string]$Entry.OldEnabled -eq 'True'){
                            Enable-ScheduledTask -CimSession $Session -TaskName $Entry.TaskName -TaskPath $Entry.TaskPath -ErrorAction Stop|Out-Null
                        }else{
                            Disable-ScheduledTask -CimSession $Session -TaskName $Entry.TaskName -TaskPath $Entry.TaskPath -ErrorAction Stop|Out-Null
                        }
                    }
                    elseif($Entry.ObjectType -eq 'ScheduledTask' -and $Entry.Action -eq 'Delete'){
                        $BackupXml=Get-Content -LiteralPath $Entry.BackupXml -Raw -Encoding UTF8 -ErrorAction Stop
                        [void][xml]$BackupXml
                        $Existing=@(Get-CimInstance -CimSession $Session -Namespace 'root\Microsoft\Windows\TaskScheduler' -ClassName MSFT_ScheduledTask -ErrorAction Stop|Where-Object{$_.TaskName -eq $Entry.TaskName -and $_.TaskPath -eq $Entry.TaskPath})
                        if($Existing.Count -gt 0){
                            throw "Task already exists; rollback will not overwrite it: $($Entry.TaskPath)$($Entry.TaskName)"
                        }
                        Register-ScheduledTask -CimSession $Session -TaskName $Entry.TaskName -TaskPath $Entry.TaskPath -Xml $BackupXml -ErrorAction Stop|Out-Null
                    }
                    else{throw "Rollback is not supported for $($Entry.ObjectType) / $($Entry.Action)."}
                    $Rows += [PSCustomObject]@{ComputerName=$Entry.ComputerName;ObjectName=$Entry.ObjectName;ObjectType=$Entry.ObjectType;Action=$Entry.Action;Status='Success';ErrorDetail=''}
                    Write-Host "$($Entry.ComputerName) : SERVICE/TASK ROLLBACK OK | $($Entry.ObjectName)" -ForegroundColor Green
                }
                catch{
                    $Rows += [PSCustomObject]@{ComputerName=$Entry.ComputerName;ObjectName=$Entry.ObjectName;ObjectType=$Entry.ObjectType;Action=$Entry.Action;Status='Failed';ErrorDetail=$_.Exception.Message}
                    Write-Host "$($Entry.ComputerName) : SERVICE/TASK ROLLBACK FAILED | $($_.Exception.Message)" -ForegroundColor Red
                }
                finally{if($null -ne $Session){Remove-CimSession -CimSession $Session -ErrorAction SilentlyContinue}}
            }
        }
        finally{Remove-Item -LiteralPath $ScopedManifest -Force -ErrorAction SilentlyContinue}
        $ReportPath=Join-Path (Join-Path $BasePath 'Logs\RemoteOps') ("{0}_ServiceTaskRollback.csv" -f $OperationID)
        $Rows|Export-Csv -LiteralPath $ReportPath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
        return $ReportPath
    }
    # Paralel calismaya izin verilen yerlesik operasyonlar (GUI'deki listeyle ayni olmali).
    $script:ParallelSafeOperations=@('ApplicationCheck','ApplicationInventory','PackageTrigger','PackageDeployment','EndpointInventory','HealthCheck','RegistryRead','ServiceList','ProcessQuery','ScheduledTaskList')
    # ====================================================================
    # PARALEL CALISMA (koordinator)
    # Ayni runner'i her hedef icin "worker" olarak baslatir (Request.Worker dolu).
    # En fazla $Parallelism worker ayni anda calisir. Her worker sonucunu
    # Workers\NNNN.result.xml dosyasina yazar; koordinator hepsini sirayla birlestirir.
    # Worker sonucsuz biterse o hedef 'Error' sayilir ve nedeni rapora yazilir.
    # ====================================================================
    function Invoke-ParallelTargets {
        # Coordinator: runs this same runner once per target (worker process) with at most $Parallelism workers alive,
        # then merges rows, outcomes, messages and health details into the usual single run-level result.
        param([string[]]$InputTargets,[string]$RunOperationID,[string]$ProgressPath,[int]$Parallelism)
        $WorkerRoot=Join-Path $RunReportRoot 'Workers'
        New-Item -ItemType Directory -Path $WorkerRoot -Force|Out-Null
        $Total=$InputTargets.Count
        $LiveTargets=@(foreach($Computer in $InputTargets){[PSCustomObject]@{ComputerName=$Computer;Stage='Pending';Outcome=''}})
        $Queue=New-Object 'System.Collections.Generic.Queue[object]'
        for($Index=0;$Index -lt $Total;$Index++){
            $Queue.Enqueue([PSCustomObject]@{Index=$Index;Target=$InputTargets[$Index]})
        }
        $Running=New-Object System.Collections.ArrayList
        $Collected=@{}
        $Completed=0
        $EnginePath=Join-Path $PSHOME 'powershell.exe'
        Write-RemoteOpsLog -Level 'INFO' -Message ("PARALLEL | Workers={0} | Targets={1}" -f $Parallelism,$Total)
        Write-TargetProgress -Path $ProgressPath -Total $Total -Completed 0 -CurrentTarget '' -Stage 'Running' -Targets $LiveTargets
        # Kuyrukta hedef veya calisan worker kaldikca: bos slot varsa yeni worker baslat,
        # biten worker'larin sonuc dosyasini oku.
        while($Queue.Count -gt 0 -or $Running.Count -gt 0){
            while($Queue.Count -gt 0 -and $Running.Count -lt $Parallelism){
                if($OperationName -eq 'PackageDeployment' -and (Test-RemoteOpsRunCancellation $CancelPath)){
                    $Item=$Queue.Dequeue()
                    $Partial=Get-RemoteOpsPartialDeploymentResult @($Item.Target) @() $Values.PackageDefinition ([string]$Values.Action) $RunOperationID
                    Write-RemoteOpsDeploymentTerminalCheckpoint $CheckpointRoot $Partial.Rows $Partial.Outcomes[0] $Values.PackageDefinition ([string]$Values.Action) $RunOperationID
                    $LiveTargets[$Item.Index].Stage='Completed';$LiveTargets[$Item.Index].Outcome=[string]$Partial.Outcomes[0].Outcome
                    $Collected[$Item.Index]=[PSCustomObject]@{Rows=$Partial.Rows;Outcomes=$Partial.Outcomes;Messages=@();Health=@()};$Completed++;continue
                }
                $Item=$Queue.Dequeue()
                $LiveTargets[$Item.Index].Stage='Running'
                $Stem=Join-Path $WorkerRoot ('{0:D4}' -f ($Item.Index+1))
                $WorkerRequest=$Request|Select-Object *
                $WorkerRequest.Targets=@($Item.Target)
                Add-Member -InputObject $WorkerRequest -NotePropertyName ProgressPath -NotePropertyValue '' -Force
                Add-Member -InputObject $WorkerRequest -NotePropertyName Worker -NotePropertyValue ([PSCustomObject]@{RunID=$RunOperationID;IndexOffset=$Item.Index;ResultPath=($Stem+'.result.xml')}) -Force
                $WorkerBase64=[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $WorkerRequest -Depth 8 -Compress)))
                $WorkerArguments='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -RequestBase64 {1}' -f $PSCommandPath,$WorkerBase64
                $WorkerProcess=$null
                $StartError=''
                try{
                    $WorkerProcess=Start-Process -FilePath $EnginePath -ArgumentList $WorkerArguments -WorkingDirectory $PSScriptRoot -RedirectStandardOutput ($Stem+'.out.log') -RedirectStandardError ($Stem+'.err.log') -WindowStyle Hidden -PassThru
                    [void]$WorkerProcess.Handle
                }
                catch{$StartError=$_.Exception.Message}
                [void]$Running.Add([PSCustomObject]@{Item=$Item;Process=$WorkerProcess;Stem=$Stem;StartError=$StartError})
            }
            $Current=@($Running|ForEach-Object{$_.Item.Target})
            Write-TargetProgress -Path $ProgressPath -Total $Total -Completed $Completed -CurrentTarget ((@($Current|Select-Object -First 3) -join ', ')+$(if($Current.Count -gt 3){' (+'+($Current.Count-3)+')'}else{''})) -Stage 'Running'
            Start-Sleep -Milliseconds 250
            # Biten worker'lari topla (stdout'unu Activity'ye aktar, result.xml'i oku).
            foreach($Worker in @($Running)){
                if($null -ne $Worker.Process -and -not $Worker.Process.HasExited){continue}
                [void]$Running.Remove($Worker)
                $ExitCode=$null
                if($null -ne $Worker.Process){
                    try{
                        $Worker.Process.WaitForExit()
                        $ExitCode=$Worker.Process.ExitCode
                    }catch{ }
                }
                $Payload=$null
                $ResultPath=$Worker.Stem+'.result.xml'
                if(Test-Path -LiteralPath $ResultPath -PathType Leaf){
                    try{
                        $Payload=Import-Clixml -LiteralPath $ResultPath -ErrorAction Stop
                    }catch{
                        $Payload=$null
                    }
                }
                $OutLog=$Worker.Stem+'.out.log'
                if(Test-Path -LiteralPath $OutLog -PathType Leaf){
                    foreach($Line in @(Get-Content -LiteralPath $OutLog -Encoding Default -ErrorAction SilentlyContinue)){
                        if(-not [string]::IsNullOrWhiteSpace([string]$Line)){
                            Microsoft.PowerShell.Utility\Write-Host ([string]$Line)
                        }
                    }
                }
                if($null -eq $Payload){
                    $ErrText=''
                    $ErrLog=$Worker.Stem+'.err.log'
                    if(Test-Path -LiteralPath $ErrLog -PathType Leaf){
                        $ErrText=(@(Get-Content -LiteralPath $ErrLog -Encoding Default -ErrorAction SilentlyContinue)-join ' ').Trim()
                    }
                    $Detail=if($Worker.StartError){"Worker could not be started: $($Worker.StartError)"}else{"Worker process ended without a result (exit code $ExitCode). $ErrText"}
                    $Payload=[PSCustomObject]@{
                        Rows=@([PSCustomObject]@{ComputerName=$Worker.Item.Target;Status='Failed';ErrorDetail=$Detail.Trim()})
                        Outcomes=@([PSCustomObject]@{ComputerName=$Worker.Item.Target;Outcome='Error';CompletedAt=(Get-Date)})
                        Messages=@([PSCustomObject]@{Message=("{0} : WORKER FAILED | {1}" -f $Worker.Item.Target,$Detail.Trim())})
                        Health=@()
                    }
                    if($OperationName -eq 'PackageDeployment'){
                        $Partial=Get-RemoteOpsPartialDeploymentResult @($Worker.Item.Target) @(Get-RemoteOpsRunCheckpoints $CheckpointRoot) $Values.PackageDefinition ([string]$Values.Action) $RunOperationID -MissingOutcome Error -MissingDetail $Detail.Trim()
                        $Payload.Rows=$Partial.Rows;$Payload.Outcomes=$Partial.Outcomes
                    }
                    Microsoft.PowerShell.Utility\Write-Host ("{0} - Error" -f $Worker.Item.Target)
                }
                if($OperationName -eq 'PackageDeployment'){
                    Write-RemoteOpsDeploymentTerminalCheckpoint $CheckpointRoot $Payload.Rows $Payload.Outcomes[0] $Values.PackageDefinition ([string]$Values.Action) $RunOperationID
                }
                $Collected[$Worker.Item.Index]=$Payload
                $LiveTargets[$Worker.Item.Index].Stage='Completed';$LiveTargets[$Worker.Item.Index].Outcome=[string]$Payload.Outcomes[0].Outcome
                $LogStatus=@($Payload.Rows|ForEach-Object{Get-RemoteOpsRowValue $_ @('LogCollectionStatus')}|Where-Object{$_}|Select-Object -Last 1)
                Add-Member -InputObject $LiveTargets[$Worker.Item.Index] -NotePropertyName LogCollectionStatus -NotePropertyValue ($LogStatus -join '') -Force
                $Completed++
                Write-TargetProgress -Path $ProgressPath -Total $Total -Completed $Completed -CurrentTarget '' -Stage 'Running'
            }
        }
        # Tum worker sonuclarini hedef sirasina gore birlestir.
        $MergedRows=New-Object 'System.Collections.Generic.List[object]'
        $MergedOutcomes=New-Object 'System.Collections.Generic.List[object]'
        for($Index=0;$Index -lt $Total;$Index++){
            $Payload=$Collected[$Index]
            foreach($Row in @($Payload.Rows)){if($null -ne $Row){$MergedRows.Add($Row)}}
            foreach($Outcome in @($Payload.Outcomes)){if($null -ne $Outcome){$MergedOutcomes.Add($Outcome)}}
            foreach($Message in @($Payload.Messages)){if($null -ne $Message){$script:OperationMessages+=$Message}}
            foreach($Detail in @($Payload.Health)){
                if($null -ne $Detail -and (Get-Variable AOHealthDetails -Scope Script -ErrorAction SilentlyContinue)){
                    [void]$script:AOHealthDetails.Add($Detail)
                }
            }
        }
        Write-TargetProgress -Path $ProgressPath -Total $Total -Completed $Total -CurrentTarget '' -Stage 'Reporting'
        return [PSCustomObject]@{Completed=$true;ResultCsv=(Join-Path $RunReportRoot 'Results.csv');Rows=@($MergedRows.ToArray());Outcomes=@($MergedOutcomes.ToArray())}
    }
    # Plugin script'ini runner scope zincirinde calistirir (dot-source).
    function Invoke-PluginScript {
        # Dot-sourced inside this function so the plugin runs in the runner's scope chain: the Write-Host / Start-Process /
        # Read-Host replacements above keep finding the runner's $script: state. Running it with & made $script: resolve to
        # the plugin's own script scope, which broke every plugin that wrote output.
        param([string]$PluginScriptPath,$PluginRequest,$PluginContext)
        . $PluginScriptPath -Request $PluginRequest -Context $PluginContext
    }
    # PREFLIGHT: secili hesap runner/worker/modul dosyalarini okuyabiliyor mu,
    # veri klasorune dosya olusturup silebiliyor mu, operasyonun kaynak dosyalarina
    # (paket, PsExec, push kaynagi, plugin) erisebiliyor mu kontrol eder.
    function Test-RemoteOpsAccess {
        param([Parameter(Mandatory=$true)]$Preflight)
        foreach($Path in @($Preflight.RunnerPath,$Preflight.WorkersPath)){
            if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){
                throw "Selected account cannot read required file: $Path"
            }
            $Stream=[System.IO.File]::OpenRead($Path)
            $Stream.Dispose()
        }
        foreach($ModuleFile in Get-ChildItem -LiteralPath $Preflight.ModulesRoot -Filter '*.ps1' -File -ErrorAction Stop){
            $Stream=[System.IO.File]::OpenRead($ModuleFile.FullName)
            $Stream.Dispose()
        }
        if(-not(Test-Path -LiteralPath $Preflight.BasePath -PathType Container)){
            throw "Data directory is missing or inaccessible: $($Preflight.BasePath)"
        }
        foreach($WritableRoot in @($Preflight.BasePath,$Preflight.LogRoot)){
            $ProbePath=Join-Path $WritableRoot ('.remoteops-access-{0}.tmp' -f [guid]::NewGuid().ToString('N'))
            try{
                [System.IO.File]::WriteAllText($ProbePath,'access-check')
                Remove-Item -LiteralPath $ProbePath -Force -ErrorAction Stop
            }
            catch{throw "Selected account cannot create/remove files under '$WritableRoot': $($_.Exception.Message)"}
        }
        $Values=$Preflight.Values
        $PathsToRead=@()
        if($Preflight.Operation -in @('FilePush','FileCompare')){$PathsToRead+= [string]$Values.LocalPath}
        if($Preflight.Operation -eq 'FileBrowser' -and $Values.Action -eq 'Replace'){
            $PathsToRead+=[string]$Values.ReplaceSource
        }
        if($Preflight.Operation -eq 'PackageTrigger'){
            $PathsToRead+= (Join-Path ([string]$Values.PackagePath) ([string]$Values.PackageFile))
            $PathsToRead+=[string]$Preflight.PsExecPath
        }
        if($Preflight.Operation -eq 'PackageDeployment'){
            $Definition=Copy-RemoteOpsPackageDefinition $Values.PackageDefinition
            Assert-RemoteOpsPackageDefinition $Definition ([string]$Values.Action)
            $Actions=if($Values.Action -eq 'Downgrade'){@('Uninstall','Downgrade')}else{@([string]$Values.Action)}
            foreach($Action in $Actions){$PathsToRead+=(Join-Path $Definition.$Action.PackagePath $Definition.$Action.PackageFile)}
            $PathsToRead+=[string]$Preflight.PsExecPath
        }
        if($Preflight.PluginScript){$PathsToRead+=[string]$Preflight.PluginScript}
        foreach($Path in $PathsToRead){
            if(-not(Test-Path -LiteralPath $Path)){throw "Selected account cannot read operation source: $Path"}
            $Item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
            if($Item.PSIsContainer){
                [void](Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop|Select-Object -First 1)
            }else{
                $Stream=[System.IO.File]::OpenRead($Path)
                $Stream.Dispose()
            }
        }
        return $true
    }
    # ====================================================================
    # RUNNER'IN KENDI UYGULADIGI OPERASYONLAR
    # (Modul menusu yerine dogrudan burada yazilmis olanlar)
    # ====================================================================
    #
    # Scheduled task Run / Enable / Disable / Delete.
    # Delete: once task XML'i yedeklenir + rollback manifest'i yazilir, sonra silinir.
    # Parola gerektiren task'lar silinmez (XML parolayi saklayamaz). Ayni isimde birden
    # fazla klasorde task varsa islem reddedilir (TaskPath verilmeli).
    function Invoke-ScheduledTaskActionRequest {
        param($InputValues)
        if([string]$InputValues.Action -notin @('Run','Enable','Disable','Delete')){
            throw 'Unsupported scheduled task action.'
        }
        $Rows=@()
        $ManifestRows=@()
        $ManifestPath=Join-Path (Join-Path $BasePath 'ServiceTaskRollbacks') ("{0}_ScheduledTasks.csv" -f $OperationID)
        foreach($ComputerName in $Systems){
            if($ReachableSystems -notcontains $ComputerName){
                $Rows+=[PSCustomObject]@{ComputerName=$ComputerName;TaskName=$InputValues.TaskName;Action=$InputValues.Action;Status='Unreachable';ErrorDetail='Ping failed.'}
                continue
            }
            $Session=$null
            try{
                $Session=Get-ServiceTaskSession $ComputerName
                $Matches=@(Get-CimInstance -CimSession $Session -Namespace 'root\Microsoft\Windows\TaskScheduler' -ClassName MSFT_ScheduledTask -ErrorAction Stop|Where-Object{$_.TaskName -eq [string]$InputValues.TaskName})
                if($InputValues.PSObject.Properties['TaskPath'] -or $InputValues -is [hashtable]){
                    if(-not [string]::IsNullOrWhiteSpace([string]$InputValues.TaskPath)){
                        $Matches=@($Matches|Where-Object{$_.TaskPath -eq [string]$InputValues.TaskPath})
                    }
                }
                if($Matches.Count -eq 0){throw "Task not found: $($InputValues.TaskName)"}
                if($Matches.Count -gt 1){
                    throw "Task name is ambiguous; multiple task paths match '$($InputValues.TaskName)'."
                }
                $Task=$Matches[0]
                if($InputValues.Action -eq 'Run'){
                    Start-ScheduledTask -CimSession $Session -TaskName $Task.TaskName -TaskPath $Task.TaskPath -ErrorAction Stop
                }
                elseif($InputValues.Action -eq 'Delete'){
                    $TaskXml=[string](Export-ScheduledTask -CimSession $Session -TaskName $Task.TaskName -TaskPath $Task.TaskPath -ErrorAction Stop)
                    $Definition=[xml]$TaskXml
                    if($null -eq $Definition.DocumentElement -or $Definition.DocumentElement.LocalName -ne 'Task'){
                        throw 'Task export did not contain a valid task definition.'
                    }
                    $PasswordPrincipals=@($Definition.SelectNodes("//*[local-name()='LogonType']")|Where-Object{$_.InnerText -in @('Password','InteractiveTokenOrPassword')})
                    if($PasswordPrincipals.Count -gt 0){
                        throw 'Delete refused: this task requires an account password that is not included in its XML backup.'
                    }
                    $BackupRoot=Join-Path (Join-Path $BasePath 'ServiceTaskRollbacks') $OperationID
                    New-Item -ItemType Directory -Path $BackupRoot -Force -ErrorAction Stop|Out-Null
                    $BackupPath=Join-Path $BackupRoot (([guid]::NewGuid().ToString('N'))+'.xml')
                    Set-Content -LiteralPath $BackupPath -Value $TaskXml -Encoding UTF8 -ErrorAction Stop
                    $ManifestRows += [PSCustomObject]@{ComputerName=$ComputerName;ObjectType='ScheduledTask';ObjectName=$Task.TaskName;TaskName=$Task.TaskName;TaskPath=$Task.TaskPath;Action='Delete';OldEnabled=[bool]$Task.Settings.Enabled;BackupXml=$BackupPath;OperationID=$OperationID}
                    Write-ServiceTaskManifest -Path $ManifestPath -Rows $ManifestRows
                    # DCOM sessions reject an explicitly bound -Confirm, even when false.
                    # UI confirmation and durable backup have already completed.
                    & { $ConfirmPreference='None';Unregister-ScheduledTask -CimSession $Session -TaskName $Task.TaskName -TaskPath $Task.TaskPath -ErrorAction Stop }
                }
                else{
                    $ManifestRows += [PSCustomObject]@{ComputerName=$ComputerName;ObjectType='ScheduledTask';ObjectName=$Task.TaskName;TaskName=$Task.TaskName;TaskPath=$Task.TaskPath;Action='EnableDisable';OldEnabled=[bool]$Task.Settings.Enabled;OperationID=$OperationID}
                    Write-ServiceTaskManifest -Path $ManifestPath -Rows $ManifestRows
                    if($InputValues.Action -eq 'Enable'){
                        Enable-ScheduledTask -CimSession $Session -TaskName $Task.TaskName -TaskPath $Task.TaskPath -ErrorAction Stop|Out-Null
                    }
                    else{
                        Disable-ScheduledTask -CimSession $Session -TaskName $Task.TaskName -TaskPath $Task.TaskPath -ErrorAction Stop|Out-Null
                    }
                }
                $Rows += [PSCustomObject]@{ComputerName=$ComputerName;TaskName=$Task.TaskName;TaskPath=$Task.TaskPath;Action=$InputValues.Action;Status='Success';ErrorDetail=''}
                Write-Host "$ComputerName : TASK $($InputValues.Action.ToUpperInvariant()) OK | $($Task.TaskPath)$($Task.TaskName)" -ForegroundColor Green
            }
            catch{
                $Rows += [PSCustomObject]@{ComputerName=$ComputerName;TaskName=$InputValues.TaskName;TaskPath='';Action=$InputValues.Action;Status='Failed';ErrorDetail=$_.Exception.Message}
                Write-Host "$ComputerName : TASK FAILED | $($_.Exception.Message)" -ForegroundColor Red
            }
            finally{if($null -ne $Session){Remove-CimSession -CimSession $Session -ErrorAction SilentlyContinue}}
        }
        if(Test-Path -LiteralPath $ManifestPath -PathType Leaf){
            Write-Host "Scheduled-task rollback manifest: $ManifestPath" -ForegroundColor Cyan
        }
        $ReportRoot=Join-Path $BasePath 'Logs\RemoteOps'
        if(-not(Test-Path -LiteralPath $ReportRoot)){
            New-Item -ItemType Directory -Path $ReportRoot -Force|Out-Null
        }
        $ReportPath=Join-Path $ReportRoot ("{0}_ScheduledTaskAction.csv" -f $OperationID)
        $Rows|Export-Csv -LiteralPath $ReportPath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
        return [PSCustomObject]@{Completed=$true;ResultCsv=$ReportPath;Rows=$Rows}
    }
    # ApplicationWorkers.ps1 AST'sinde "$<Ad> = { ... }" atamasini bulur ve scriptblock'u dondurur.
    # (Ad tarihsel; testler bu fonksiyonu sahte worker vermek icin taklit eder.)
    # Ornek: Get-HostScriptBlock -VariableName 'PackageScript'
    function Get-HostScriptBlock {
        param([Parameter(Mandatory=$true)][string]$VariableName)
        $Assignment = $script:HostAst.Find({ param($Node) $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $Node.Left.Extent.Text -eq ('$' + $VariableName) },$true)
        if ($null -eq $Assignment) {
            throw "Worker '$VariableName' was not found in '$WorkersPath'. Parse issues=$($HostParseErrors.Count)."
        }
        $Block = $Assignment.Right.Find({ param($Node) $Node -is [System.Management.Automation.Language.ScriptBlockExpressionAst] },$true)
        if ($null -eq $Block) { throw "Worker assignment is not a scriptblock: $VariableName" }
        $WorkerTokens = $null
        $WorkerErrors = $null
        [System.Management.Automation.Language.Parser]::ParseInput($Block.Extent.Text,[ref]$WorkerTokens,[ref]$WorkerErrors) | Out-Null
        if ($WorkerErrors.Count -gt 0) {
            throw "Reusable worker '$VariableName' in '$WorkersPath' has syntax errors: $(($WorkerErrors | ForEach-Object { 'line {0}: {1}' -f $_.Extent.StartLineNumber,$_.Message }) -join '; ')"
        }
        return $Block.ScriptBlock.GetScriptBlock()
    }
    # ApplicationWorkers.ps1'deki $RegistryCheckScript worker'ini cagirir ve Status alani olan son nesneyi dondurur.
    function Invoke-RegistryCheckWorker {
        param([Parameter(Mandatory=$true)][scriptblock]$Worker,[string]$ComputerName,[string]$SearchMode,[string]$SearchValue,[int]$TimeoutSeconds,$SelectedApplication=$null,[string]$PackageOperation='')
        $WorkerOutput=@(& $Worker $ComputerName $SearchMode $SearchValue $TimeoutSeconds $SelectedApplication $PackageOperation)
        $Result=@($WorkerOutput|Where-Object{$null -ne $_ -and $null -ne $_.PSObject.Properties['Status']}|Select-Object -Last 1)
        if($Result.Count -eq 0){
            $OutputTypes=@($WorkerOutput|ForEach-Object{if($null -eq $_){'<null>'}else{$_.GetType().FullName}})-join ', '
            throw "Registry worker returned no result object with a Status property for '$ComputerName'. Output types: $OutputTypes"
        }
        return $Result[0]
    }
    # FileBrowser icin FileOperations menusunun soracagi cevaplari hazirlar
    # (listelenen dosyalar arasinda secilen dosyanin sira numarasi bulunur).
    function New-FileBrowserPromptAnswers {
        param([string]$BrowsePath,[string]$SelectedPath,[string]$Action,[string[]]$ComputerNames,[string]$MoveTarget,[string]$ReplaceSource,[string]$Confirm)
        $ActionNumber=switch($Action){'Pull'{'1'}'Move'{'2'}'Replace'{'4'}default{throw 'Unsupported browse action. Use the protected Delete operation for deletion.'}}
        $Answers=New-Object 'System.Collections.Generic.List[string]'
        [void]$Answers.Add($BrowsePath)
        foreach($ComputerName in $ComputerNames){
            $RemoteRoot=ConvertTo-AORemoteAdminPath -ComputerName $ComputerName -LocalPath $BrowsePath
            $RemoteSelected=ConvertTo-AORemoteAdminPath -ComputerName $ComputerName -LocalPath $SelectedPath
            $Files=@(Get-ChildItem -LiteralPath $RemoteRoot -File -Recurse -Force -ErrorAction Stop|Sort-Object FullName)
            $MatchIndex=-1
            for($Index=0;$Index -lt $Files.Count;$Index++){
                if([string]::Equals([string]$Files[$Index].FullName,$RemoteSelected,[System.StringComparison]::OrdinalIgnoreCase)){
                    $MatchIndex=$Index
                    break
                }
            }
            if($MatchIndex -lt 0){
                throw "Selected file is not under the browse folder on ${ComputerName}: $SelectedPath"
            }
            [void]$Answers.Add([string]($MatchIndex+1))
            [void]$Answers.Add($ActionNumber)
            if($Action -eq 'Move'){[void]$Answers.Add($MoveTarget);[void]$Answers.Add($Confirm)}
            elseif($Action -eq 'Replace'){[void]$Answers.Add($ReplaceSource);[void]$Answers.Add($Confirm)}
        }
        [void]$Answers.Add('0')
        return $Answers.ToArray()
    }
    # ApplicationWorkers.ps1 icindeki bir fonksiyonu AST'den alip bu scope'ta tanimlar.
    function Import-HostFunction {
        param([Parameter(Mandatory=$true)][string]$FunctionName)
        $Definition = $script:HostAst.Find({ param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq $FunctionName },$true)
        if ($null -eq $Definition) { throw "Function was not found in ApplicationWorkers.ps1: $FunctionName" }
        Set-Item -Path ("Function:script:{0}" -f $FunctionName) -Value $Definition.Body.GetScriptBlock()
    }
    # GUI arama tipi -> worker'in bekledigi SearchMode degeri.
    function Convert-ApplicationSearchMode {
        param([string]$Value)
        switch ($Value) { 'DisplayName exact' { 'DisplayNameExact' } 'DisplayName contains' { 'DisplayName' } 'ProductID' { 'ProductID' } default { throw "Invalid application search type: $Value" } }
    }
    # Uygulama operasyonlarinin satirlarini Logs\Application\<ID>_<Ad>.csv olarak yazar.
    function Write-ApplicationRows {
        param([string]$Name,[object[]]$Rows)
        $LogRoot=Join-Path (Join-Path $BasePath 'Logs') 'Application'
        if(-not(Test-Path -LiteralPath $LogRoot)){New-Item -ItemType Directory -Path $LogRoot -Force|Out-Null}
        $Path=Join-Path $LogRoot ("{0}_{1}.csv" -f $OperationID,$Name)
        $Headers=@($Rows|ForEach-Object{$_.PSObject.Properties.Name}|Select-Object -Unique)
        if($Rows.Count -gt 0){
            $Rows|Select-Object $Headers|Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8 -Delimiter ';'
        }else{
            Set-Content -LiteralPath $Path -Value '' -Encoding UTF8
        }
        return $Path
    }
    # UYGULAMA VARLIK KONTROLU: her hedefte uninstall registry anahtarlari taranir.
    # Birden fazla eslesme varsa (CokluEslesme) tum adaylar listelenir; RegistryKey
    # girilmisse o anahtar secilir.
    function Invoke-ApplicationCheckRequest {
        param($InputValues)
        $RegistryWorker=Get-HostScriptBlock -VariableName 'RegistryCheckScript'
        $Mode=Convert-ApplicationSearchMode -Value ([string]$InputValues.SearchType)
        $Rows=@()
        foreach($ComputerName in $Systems){
            if($ReachableSystems -notcontains $ComputerName){
                $Rows+=[PSCustomObject]@{ComputerName=$ComputerName;Status='Unreachable';DisplayName='';DisplayVersion='';ProductID='';ProductIDSource='';RegistryKey='';ErrorDetail='Ping failed.'}
                continue
            }
            try{
                $Check=Invoke-RegistryCheckWorker -Worker $RegistryWorker -ComputerName $ComputerName -SearchMode $Mode -SearchValue ([string]$InputValues.SearchValue) -TimeoutSeconds 6
                if($Check.Status -eq 'CokluEslesme'){
                    $Selected=@(@($Check.Applications|Where-Object{[string]::Equals([string]$_.RegistryKey,[string]$InputValues.RegistryKey,[System.StringComparison]::OrdinalIgnoreCase)})|Select-Object -First 1)
                    if($Selected.Count -eq 0){
                        # List every match so the operator can see them and pick one registry key; a key that was typed but matches nothing stays an error.
                        $KeyTyped=-not [string]::IsNullOrWhiteSpace([string]$InputValues.RegistryKey)
                        $MatchCount=@($Check.Applications).Count
                        foreach($Match in @($Check.Applications)){
                            $Rows+=[PSCustomObject]@{ComputerName=$ComputerName;Status=$(if($KeyTyped){'Ambiguous'}else{'Var'});DisplayName=[string]$Match.DisplayName;DisplayVersion=[string]$Match.DisplayVersion;ProductID=[string]$Match.ProductID;ProductIDSource=[string]$Match.ProductIDSource;RegistryKey=[string]$Match.RegistryKey;ErrorDetail=$(if($KeyTyped){"Registry key '$($InputValues.RegistryKey)' is not among the $MatchCount matches."}else{"$MatchCount matches found; enter one exact registry key to select a single application."})}
                        }
                        continue
                    }
                    $Check=[PSCustomObject]@{ComputerName=$ComputerName;Status='Var';DisplayName=$Selected[0].DisplayName;DisplayVersion=$Selected[0].DisplayVersion;ProductID=$Selected[0].ProductID;ProductIDSource=$Selected[0].ProductIDSource;RegistryKey=$Selected[0].RegistryKey;ErrorDetail=''}
                }
                else{
                    $Application=if($null -ne $Check.PSObject.Properties['Applications']){@($Check.Applications)|Select-Object -First 1}else{$null}
                    $RegistryKey=if($null -ne $Application){$Application.RegistryKey}else{''}
                    $Check|Add-Member -NotePropertyName RegistryKey -NotePropertyValue $RegistryKey -Force
                }
                $Rows += [PSCustomObject]@{ComputerName=$ComputerName;Status=[string]$Check.Status;DisplayName=[string]$Check.DisplayName;DisplayVersion=[string]$Check.DisplayVersion;ProductID=[string]$Check.ProductID;ProductIDSource=[string]$Check.ProductIDSource;RegistryKey=[string]$Check.RegistryKey;ErrorDetail=[string]$Check.ErrorDetail}
            }
            catch{
                $Rows+=[PSCustomObject]@{ComputerName=$ComputerName;Status='Failed';DisplayName='';DisplayVersion='';ProductID='';ProductIDSource='';RegistryKey='';ErrorDetail=$_.Exception.Message}
            }
        }
        $Report=Write-ApplicationRows -Name 'ApplicationCheck' -Rows $Rows
        $FoundCount=@($Rows|Where-Object{$_.Status -eq 'Var'}).Count
        $MissingCount=@($Rows|Where-Object{$_.Status -eq 'Yok'}).Count
        $IssueCount=$Rows.Count-$FoundCount-$MissingCount
        foreach($Row in $Rows){
            if($Row.Status -eq 'Var'){
                Write-Host ("{0} - Found - {1} | Version: {2} | Product ID: {3}" -f $Row.ComputerName,$Row.DisplayName,$Row.DisplayVersion,$Row.ProductID)
            }elseif($Row.Status -eq 'Yok'){
                Write-Host "$($Row.ComputerName) - Not found"
            }else{
                Write-Host "$($Row.ComputerName) - Error/Unreachable - $($Row.ErrorDetail)"
            }
        }
        Write-Host ("Application check complete | Targets={0} Found={1} Missing={2} Issues={3}" -f $Rows.Count,$FoundCount,$MissingCount,$IssueCount) -ForegroundColor Cyan
        Write-RemoteOpsLog -Level 'INFO' -Message "APPLICATION-CHECK | ID=$OperationID | Targets=$($Rows.Count) | Found=$FoundCount | Missing=$MissingCount | Issues=$IssueCount"
        return [PSCustomObject]@{Completed=$true;ResultCsv=$Report;Rows=$Rows}
    }
    # KURULU UYGULAMA ENVANTERI: ApplicationWorkers.ps1'deki inventory worker'i + HTML rapor fonksiyonlari kullanilir.
    function Invoke-ApplicationInventoryRequest {
        $InventoryWorker=Get-HostScriptBlock -VariableName 'InstalledApplicationInventoryScript'
        Import-HostFunction -FunctionName 'ConvertTo-AOInstalledApplicationHtml'
        Import-HostFunction -FunctionName 'Write-AOInstalledApplicationHtmlReport'
        $Results=@()
        $Rows=@()
        $Successful=@()
        foreach($ComputerName in $Systems){
            if($ReachableSystems -notcontains $ComputerName){
                $Rows+=[PSCustomObject]@{IstemciAdi=$ComputerName;DisplayName='';DisplayVersion='';Publisher='';ProductID='';ProductIDKaynak='';RegistryPath='';RegistryKey='';Durum='Unreachable';HataDetayi='Client is unavailable.'}
                continue
            }
            $Result=& $InventoryWorker $ComputerName 6
            $Results+=$Result
            if($Result.Status -eq 'Success'){
                $Successful+=$ComputerName
                $Rows+=@($Result.Applications)
                if(@($Result.Applications).Count -eq 0){
                    $Rows+=[PSCustomObject]@{IstemciAdi=$ComputerName;DisplayName='';DisplayVersion='';Publisher='';ProductID='';ProductIDKaynak='';RegistryPath='';RegistryKey='';Durum='Success';HataDetayi='No installed applications returned.'}
                }
            }else{
                $Rows+=[PSCustomObject]@{IstemciAdi=$ComputerName;DisplayName='';DisplayVersion='';Publisher='';ProductID='';ProductIDKaynak='';RegistryPath='';RegistryKey='';Durum='Failed';HataDetayi=$Result.ErrorDetail}
            }
        }
        $Report=Write-AOInstalledApplicationHtmlReport -BasePath $BasePath -OperationID $OperationID -Rows $Rows -ClientNames $Systems -SuccessfulClients $Successful
        Write-RemoteOpsLog -Level 'INFO' -Message "APPLICATION-INVENTORY | ID=$OperationID | Rows=$($Rows.Count)"
        return [PSCustomObject]@{Completed=$true;ResultCsv=$Report;Rows=$Rows}
    }
    # ====================================================================
    # PAKET TETIKLEME (Install / Uninstall)
    # 1) Girdi dogrulama: UNC paket klasoru, .bat/.cmd/.ps1/.vbs dosya adi, PsExec yolu
    # 2) Kontrol modu: Versiyon kontrollu / Sadece varlik / Kontrolsuz (Application bossa kontrolsuz)
    # 3) Her hedef icin on kontrol ($RegistryCheckScript) -> karar (Decision)
    # 4) Uygun hedeflerde ApplicationWorkers.ps1'deki $PackageScript worker'i calisir:
    #    PsExec -s ile hedefte SYSTEM olarak paket -> exit code -> (opsiyonel) log toplama
    #    -> (opsiyonel) log temizleme -> son kontrol
    # 5) Sonuclar Set-RemoteOpsPackageOutcome ile Completed/Skipped/Error'a cevrilir
    # ====================================================================
    function Invoke-PackageRequest {
        param($InputValues)
        $PackagePath=[string]$InputValues.PackagePath
        $PackageFile=[string]$InputValues.PackageFile
        if($PackagePath -notmatch '^\\\\[^\\]+\\[^\\]+') { throw 'Package folder must be a UNC path.' }
        if([string]::IsNullOrWhiteSpace($PackageFile) -or [System.IO.Path]::GetFileName($PackageFile) -cne $PackageFile -or $PackageFile -notmatch '(?i)\.(bat|cmd|ps1|vbs)$'){
            throw 'Enter a package file name ending in .bat, .cmd, .ps1, or .vbs.'
        }
        $PsExecCommand=Get-Command 'PsExec.exe' -ErrorAction SilentlyContinue
        $PsExecPath=if($null -ne $PsExecCommand){$PsExecCommand.Source}else{Join-Path $WorkspaceRoot 'PsExec.exe'}
        if(-not(Test-Path -LiteralPath $PsExecPath -PathType Leaf)){
            throw 'PsExec.exe was not found on PATH or next to the project.'
        }
        $Operation=([string]$InputValues.Action).ToUpperInvariant()
        # GUI kontrol modu -> worker'larin ic mod adlari.
        $Mode=switch([string]$InputValues.CheckMode){'Version controlled'{'VersiyonKontrollu'}'Presence only'{'VarlikKontrollu'}'Trigger without checks'{'SadeceTetikle'}default{throw 'Invalid package check mode.'}}
        $SearchMode=Convert-ApplicationSearchMode -Value ([string]$InputValues.SearchType)
        $SearchValue=[string]$InputValues.Application
        if([string]::IsNullOrWhiteSpace($SearchValue)){$Mode='SadeceTetikle'}
        if($Operation -eq 'INSTALL' -and $Mode -eq 'VersiyonKontrollu' -and [string]::IsNullOrWhiteSpace([string]$InputValues.Version)){
            throw 'Target version is required for version-controlled installation.'
        }
        # ApplicationWorkers.ps1'den worker'lar ve versiyon karsilastirma fonksiyonu cekilir.
        $RegistryWorker=Get-HostScriptBlock -VariableName 'RegistryCheckScript'
        $PackageWorker=Get-HostScriptBlock -VariableName 'PackageScript'
        $VersionDefinition=$script:HostAst.Find({param($Node)$Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq 'Compare-ApplicationVersion'},$true)
        if($null -eq $VersionDefinition){throw 'Version comparison function not found in ApplicationWorkers.ps1.'}
        . ([scriptblock]::Create($VersionDefinition.Extent.Text))
        # Optional cleanup of the collected package logs that contain the saved user name (Settings tab). Only with log
        # collection ticked and only with a specific, validated user name; the worker re-checks everything per file.
        # Log temizleme kullanici adi tekrar dogrulanir; gecersizse temizlik bu calismada atlanir.
        $CleanupLogsUser=''
        if($null -ne $Request.PSObject.Properties['CleanupPackageLogs'] -and [bool]$Request.CleanupPackageLogs -and [bool]$InputValues.CollectLogs){
            $RequestedCleanupUser=if($null -ne $Request.PSObject.Properties['CleanupUserName']){[string]$Request.CleanupUserName}else{''}
            $CleanupCheck=Test-AOLogCleanupUserName -UserName $RequestedCleanupUser
            if($CleanupCheck.Valid){$CleanupLogsUser=$RequestedCleanupUser.Trim()}
            else{Write-Host ('Log temizleme atlandi: '+$CleanupCheck.Reason)}
        }
        $Rows=@()
        # KARAR ASAMASI: her hedef icin paketin tetiklenip tetiklenmeyecegi belirlenir.
        #   Install : yoksa kur; varsa (versiyon modunda) eskiyse kur, esit/yeniyse atla
        #   Uninstall: varsa kaldir, yoksa atla
        foreach($ComputerName in $Systems){
            if($ReachableSystems -notcontains $ComputerName){
                $Rows+=[PSCustomObject]@{ComputerName=$ComputerName;Decision='Unreachable';ExecutionStatus='NotRun';ErrorDetail='Ping failed.'}
                continue
            }
            $SelectedApplication=$null
            $Eligible=$false
            $Decision=''
            if($Mode -eq 'SadeceTetikle'){$Eligible=$true;$Decision='UnconditionalTrigger'}
            else{
                $Check=Invoke-RegistryCheckWorker -Worker $RegistryWorker -ComputerName $ComputerName -SearchMode $SearchMode -SearchValue $SearchValue -TimeoutSeconds 6
                if($Check.Status -eq 'CokluEslesme'){
                    $Selected=@(@($Check.Applications|Where-Object{[string]::Equals([string]$_.RegistryKey,[string]$InputValues.RegistryKey,[System.StringComparison]::OrdinalIgnoreCase)})|Select-Object -First 1)
                    if($Selected.Count -eq 0){
                        $Rows+=[PSCustomObject]@{ComputerName=$ComputerName;Decision='Ambiguous';ExecutionStatus='NotRun';ErrorDetail='Multiple matches. Supply an exact registry key.'}
                        continue
                    }
                    $Check=[PSCustomObject]@{Status='Var';Applications=@($Selected);DisplayName=$Selected[0].DisplayName;DisplayVersion=$Selected[0].DisplayVersion}
                }
                if($Check.Status -eq 'Var'){$SelectedApplication=@($Check.Applications)|Select-Object -First 1}
                if($Check.Status -eq 'Hata'){
                    $Rows+=[PSCustomObject]@{ComputerName=$ComputerName;Decision='CheckFailed';ExecutionStatus='NotRun';ErrorDetail=$Check.ErrorDetail}
                    continue
                }
                if($Operation -eq 'INSTALL'){
                    if($Check.Status -eq 'Yok'){$Eligible=$true;$Decision='InstallMissing'}
                    elseif($Mode -eq 'VarlikKontrollu'){$Decision='AlreadyPresent'}
                    else{
                        $Comparison=Compare-ApplicationVersion -CurrentVersion ([string]$SelectedApplication.DisplayVersion) -TargetVersion ([string]$InputValues.Version)
                        if(-not $Comparison.Comparable){
                            $Decision='VersionNotComparable'
                        }elseif([int]$Comparison.Result -lt 0){
                            $Eligible=$true
                            $Decision='OlderVersion'
                        }else{
                            $Decision=if([int]$Comparison.Result -eq 0){'AlreadyAtTarget'}else{'NewerVersionPresent'}
                        }
                    }
                }
                elseif($Check.Status -eq 'Var'){
                    $Eligible=$true
                    $Decision='UninstallPresent'
                }else{
                    $Decision='AlreadyAbsent'
                }
            }
            if(-not $Eligible){
                $Rows+=[PSCustomObject]@{ComputerName=$ComputerName;Decision=$Decision;ExecutionStatus='Skipped';ErrorDetail='Eligibility checks did not select this endpoint.'}
                continue
            }
            try{
                # Uygun hedef: paket worker'ini parametreleriyle cagir (timeout 2700 sn = 45 dk).
                $Arguments=@{ComputerName=$ComputerName;PackagePath=$PackagePath;BatFile=$PackageFile;PsExecPath=$PsExecPath;PsExecConnectTimeoutSeconds=10;PackageTimeoutSeconds=2700;CollectPackageLogs=[bool]$InputValues.CollectLogs;LogCollectionGroup=([IO.Path]::GetFileName($RunReportRoot));FileOperationsModulePath=(Join-Path $ModulesRoot 'FileOperations.ps1');BasePath=$BasePath;PackageOperation=$Operation;OperationID=$OperationID;LogLookbackMinutes=10;RegistryCheckScriptText=$RegistryWorker.ToString();SearchMode=$SearchMode;SearchValue=$SearchValue;WMITimeoutSeconds=6;TargetInstallVersion=[string]$InputValues.Version;PostCheckInitialDelaySec=3;PostCheckRetryCount=6;PostCheckRetryIntervalSec=10;SkipPostCheck=($Mode -eq 'SadeceTetikle');InstallRequiresVersionMatch=($Mode -eq 'VersiyonKontrollu');SelectedApplication=$SelectedApplication}
                if($CleanupLogsUser){$Arguments.CleanupLogsUserName=$CleanupLogsUser}
                $PackageResult=& $PackageWorker @Arguments
                $CleanupProperty=$PackageResult.PSObject.Properties['LogCleanupStatus']
                if($null -ne $CleanupProperty -and [string]$CleanupProperty.Value -notin @('','NotRequested')){
                    $CleanupDetailProperty=$PackageResult.PSObject.Properties['LogCleanupDetail']
                    $CleanupLine=('{0} : LOG-CLEANUP | User={1} | Status={2} | {3}' -f $ComputerName,$CleanupLogsUser,$CleanupProperty.Value,$(if($null -ne $CleanupDetailProperty){$CleanupDetailProperty.Value}else{''}))
                    Write-RemoteOpsLog -Level 'INFO' -Message $CleanupLine
                    Write-Host ('{0} - log temizleme: {1}' -f $ComputerName,$CleanupProperty.Value)
                }
                $Rows += $PackageResult | Select-Object *,@{Name='Decision';Expression={$Decision}}
            }
            catch{
                $Rows+=[PSCustomObject]@{ComputerName=$ComputerName;Decision=$Decision;ExecutionStatus='Failed';ErrorDetail=$_.Exception.Message}
            }
        }
        # Paket satirlarina nihai Outcome/OutcomeDetail ekle ve ozet yaz.
        Set-RemoteOpsPackageOutcome -Rows $Rows -Action $Operation -CheckMode $Mode -TargetVersion ([string]$InputValues.Version) -VersionComparer ${function:Compare-ApplicationVersion}
        $Report=Write-ApplicationRows -Name 'PackageOperations' -Rows $Rows
        Write-RemoteOpsPackageSummary -Rows $Rows -Action $Operation -CheckMode $Mode
        Write-RemoteOpsLog -Level 'INFO' -Message "PACKAGE-RUN | ID=$OperationID | Rows=$($Rows.Count)"
        return [PSCustomObject]@{Completed=$true;ResultCsv=$Report;Rows=$Rows}
    }

    function Invoke-SavedPackageDeploymentRequest {
        param($InputValues)
        $Definition=Copy-RemoteOpsPackageDefinition $InputValues.PackageDefinition;$Action=[string]$InputValues.Action
        Assert-RemoteOpsPackageDefinition $Definition $Action
        $RegistryWorker=Get-HostScriptBlock -VariableName 'RegistryCheckScript'
        $PackageWorker=Get-HostScriptBlock -VariableName 'PackageScript'
        Import-HostFunction 'Compare-ApplicationVersion'
        $PsExecPath=Join-Path $WorkspaceRoot 'PsExec.exe'
        if(-not(Test-Path -LiteralPath $PsExecPath -PathType Leaf)){
            $Command=Get-Command PsExec.exe -ErrorAction SilentlyContinue
            if($null -eq $Command){throw 'PsExec.exe was not found.'};$PsExecPath=$Command.Source
        }
        $ComputerName=[string]$Systems[0]
        $Detect={param($Identity,$Target)
            $Mode=Convert-ApplicationSearchMode ([string]$Identity.SearchType)
            $Detected=Invoke-RegistryCheckWorker -Worker $RegistryWorker -ComputerName $Target -SearchMode $Mode -SearchValue ([string]$Identity.Application) -TimeoutSeconds 6
            if($Detected.Status -in @('Var','CokluEslesme') -and -not[string]::IsNullOrWhiteSpace([string]$Identity.RegistryKey)){
                $Matches=@($Detected.Applications|Where-Object{[string]::Equals([string]$_.RegistryKey,[string]$Identity.RegistryKey,[StringComparison]::OrdinalIgnoreCase)})
                if($Matches.Count -eq 1){return [PSCustomObject]@{Status='Var';DisplayVersion=$Matches[0].DisplayVersion;DisplayName=$Matches[0].DisplayName;Applications=@($Matches[0]);ErrorDetail=''}}
                return [PSCustomObject]@{Status='Hata';DisplayVersion='';ErrorDetail='The exact registry key does not match the detected application.';Applications=@()}
            }
            return $Detected
        }
        $CleanupUser=''
        if((Get-RemoteOpsPackageValue $Request CleanupPackageLogs $false) -eq $true -and $Definition.CollectLogs){
            $Check=Test-AOLogCleanupUserName ([string](Get-RemoteOpsPackageValue $Request CleanupUserName ''))
            if($Check.Valid){$CleanupUser=[string]$Request.CleanupUserName}
        }
        $Execute={param($Part,$StepAction,$Policy,$StepId)
            $Arguments=@{ComputerName=$ComputerName;PackagePath=$Part.PackagePath;BatFile=$Part.PackageFile;PsExecPath=$PsExecPath;PsExecConnectTimeoutSeconds=10;PackageTimeoutSeconds=2700;CollectPackageLogs=[bool]$Definition.CollectLogs;LogCollectionGroup=([IO.Path]::GetFileName($RunReportRoot));FileOperationsModulePath=(Join-Path $ModulesRoot 'FileOperations.ps1');BasePath=$BasePath;PackageOperation=$StepAction.ToUpperInvariant();OperationID=$StepId;LogLookbackMinutes=10;RegistryCheckScriptText=$RegistryWorker.ToString();SearchMode=(Convert-ApplicationSearchMode $Part.SearchType);SearchValue=$Part.Application;WMITimeoutSeconds=6;TargetInstallVersion=$(if($Action -eq 'Downgrade'){$Definition.DowngradeVersion}else{$Definition.TargetVersion});PostCheckInitialDelaySec=3;PostCheckRetryCount=6;PostCheckRetryIntervalSec=10;SkipPostCheck=($Part.CheckMode -eq 'Trigger without checks');InstallRequiresVersionMatch=($Policy -eq 'Exact' -or $Part.CheckMode -eq 'Version controlled');SelectedApplication=$null;CleanupLogsUserName=$CleanupUser;VersionMatchPolicy=$Policy}
            & $PackageWorker @Arguments
        }
        $ValidateSource={param($Part,$Target)Invoke-RemoteOpsPackageProbe $Part $Target $PsExecPath}
        $IsCancelled={Test-RemoteOpsRunCancellation $CancelPath}
        $Checkpoint={param($State)Write-RemoteOpsRunCheckpoint $CheckpointRoot $State;Write-RemoteOpsLog -Level 'INFO' -Message ("DEPLOYMENT | $ComputerName | $($State.Step) | terminal=$($State.Terminal)")}
        $Lock=$null
        try{
            $Lock=Enter-RemoteOpsDeploymentLock (Join-Path $BasePath 'DeploymentLocks') $ComputerName $Definition.ApplicationKey $OperationID
            $Deployment=Invoke-RemoteOpsPackageDeployment -Definition $Definition -Action $Action -ComputerName $ComputerName -OperationID $OperationID -Detect $Detect -Execute $Execute -ValidateSource $ValidateSource -VersionComparer ${function:Compare-ApplicationVersion} -IsCancelled $IsCancelled -Checkpoint $Checkpoint 
        }finally{Exit-RemoteOpsDeploymentLock $Lock}
        return [PSCustomObject]@{Completed=$true;ResultCsv=(Write-ApplicationRows 'PackageDeployment' $Deployment.Rows);Rows=@($Deployment.Rows);Outcomes=@($Deployment.Outcome)}
    }

    # GIRDI ON KONTROLU (Assert-RemoteOpsRequestValues)
    # Operasyon baslamadan, modul menulerinin yanlis yorumlayacagi girdileri yakalar:
    #   FileDelete : yol bicimi (mutlak yol, '..' yok, joker sadece son segmentte)
    #   FilePush   : yerel/UNC kaynak var mi
    #   FileCompare: referans dosya var mi
    #   FileRestore: silme yedegi var mi, yedek numarasi gecerli mi, manifest var mi
    function Assert-RemoteOpsRequestValues {
        param([string]$OperationName,$InputValues)
        switch($OperationName){
            'PackageDeployment' {
                if([string]$InputValues.Action -notin @('Install','Uninstall','Downgrade')){throw 'Unsupported saved package action.'}
                Assert-RemoteOpsPackageDefinition $InputValues.PackageDefinition ([string]$InputValues.Action)
            }
            'FileDelete' {
                # Modulun kendi normalize fonksiyonu; gecersiz yolda aciklayici hata firlatir.
                [void](ConvertTo-AODeleteTargetPath -Path ([string]$InputValues.Path))
            }
            'FilePush' {
                if(-not(Test-Path -Path ([string]$InputValues.LocalPath))){throw "Push kaynagi bulunamadi veya erisilemiyor: $($InputValues.LocalPath)"}
            }
            'FileCompare' {
                if(-not(Test-Path -LiteralPath ([string]$InputValues.LocalPath) -PathType Leaf)){throw "Referans dosyasi bulunamadi: $($InputValues.LocalPath)"}
            }
            'FileRestore' {
                # Restore-AODeleteBackup ile ayni siralama: en yeni yedek = 1
                $BackupRuns=@(Get-ChildItem -LiteralPath (Join-Path $BasePath 'DeleteBackups') -Directory -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending)
                if($BackupRuns.Count -eq 0){throw 'Restore edilebilir silme yedegi bulunamadi.'}
                $Number=if([string]::IsNullOrWhiteSpace([string]$InputValues.BackupPath)){1}else{0}
                if($Number -eq 0 -and -not [int]::TryParse(([string]$InputValues.BackupPath).Trim(),[ref]$Number)){throw "Yedek numarasi sayi olmali: $($InputValues.BackupPath)"}
                if($Number -lt 1 -or $Number -gt $BackupRuns.Count){throw "Yedek numarasi gecersiz: $Number (mevcut yedek sayisi: $($BackupRuns.Count))."}
                if(-not(Test-Path -LiteralPath (Join-Path $BackupRuns[$Number-1].FullName 'manifest.csv') -PathType Leaf)){throw "Secilen yedekte manifest.csv yok: $($BackupRuns[$Number-1].Name)"}
            }
        }
    }

    ####################################################################
    # ANA AKIS
    ####################################################################
    #
    # Mod 1: PREFLIGHT - sadece erisim testi yap ve cik.
    if (-not [string]::IsNullOrWhiteSpace($PreflightBase64)) {
        $PreflightJson=[System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($PreflightBase64))
        $Preflight=ConvertFrom-Json -InputObject $PreflightJson -ErrorAction Stop
        [void](Test-RemoteOpsAccess -Preflight $Preflight)
        Write-Output 'ACCESS_PREFLIGHT_OK'
        return
    }
    # Mod 2: worker scriptblock'larinin parse edilebildigini dogrula ve cik.
    if ($ValidateHostWorkers) {
        foreach ($WorkerName in @('RegistryCheckScript','InstalledApplicationInventoryScript','PackageScript')) {
            $Worker = Get-HostScriptBlock -VariableName $WorkerName
            $WorkerTokens = $null
            $WorkerErrors = $null
            [System.Management.Automation.Language.Parser]::ParseInput($Worker.ToString(),[ref]$WorkerTokens,[ref]$WorkerErrors) | Out-Null
            if ($WorkerErrors.Count -gt 0) { throw "Extracted worker '$WorkerName' has parser errors." }
            Write-Output ("WorkerOK: {0}" -f $WorkerName)
        }
        return
    }

    # Modules\*.ps1 dosyalarini bu scope'a yukle (fonksiyonlar + Register-* kayitlari).
    # ApplicationWorkers.ps1 bir menu modulu degildir; yukarida AST ile okunur, burada atlanir.
    foreach ($ModuleFile in @(Get-ChildItem -LiteralPath $ModulesRoot -Filter '*.ps1' -File | Where-Object { $_.Name -ne 'ApplicationWorkers.ps1' } | Sort-Object Name)) {
        . $ModuleFile.FullName
    }

    # Mod 3: operasyon listesini yaz ve cik.
    if ($ListOperations) {
        foreach ($Operation in $script:AOModuleOperations | Sort-Object ModuleName,DisplayName) {
            '{0} | {1} | {2}' -f $Operation.ModuleName,$Operation.Name,$Operation.DisplayName
        }
        foreach ($ManifestFile in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Plugins') -Filter 'manifest.json' -File -Recurse -ErrorAction SilentlyContinue) {
            $Manifest = Get-Content -LiteralPath $ManifestFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($PluginOperation in $Manifest.Operations) {
                '{0} | {1} | {2}' -f $Manifest.Name,$PluginOperation.Name,$PluginOperation.Title
            }
        }
        return
    }
    # Mod 4 (normal): istegi coz ve calisma ortamini hazirla.
    if ([string]::IsNullOrWhiteSpace($RequestBase64)) { throw 'Provide -RequestBase64 or use -ListOperations.' }
    $RequestJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($RequestBase64))
    $Request = ConvertFrom-Json -InputObject $RequestJson -ErrorAction Stop
    if (@($Request.Targets).Count -eq 0) { throw 'Request has no target computers.' }
    if (-not (Test-Path -LiteralPath $BasePath -PathType Container)) {
        New-Item -ItemType Directory -Path $BasePath -Force | Out-Null
    }
    # Request.Worker doluysa bu surec paralel calismada tek hedefi isleyen bir worker'dir.
    $WorkerInfo=if($null -ne $Request.PSObject.Properties['Worker']){$Request.Worker}else{$null}
    $IsWorker=($null -ne $WorkerInfo)
    # Calisma ID'si: GUI-yyyyMMdd-HHmmss-XXXXXX (worker'lar koordinatorun ID'sini kullanir).
    $OperationID = if($IsWorker){[string]$WorkerInfo.RunID}else{'GUI-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),([Guid]::NewGuid().ToString('N').Substring(0,6).ToUpperInvariant())}
    $OperationDate = Get-Date -Format 'dd.MM.yyyy'
    $OperationTime = Get-Date -Format 'HH:mm:ss'
    $OperationName=[string]$Request.Operation
    # Bu calismanin tum ciktilari bu klasorde toplanir.
    $RunReportRoot=Join-Path (Join-Path (Join-Path $BasePath 'Logs\Operations') $OperationName) $OperationID
    New-Item -ItemType Directory -Path $RunReportRoot -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $BasePath 'PulledLogs') -Force|Out-Null

    # Hedefler: bosluklar temizlenir, buyuk/kucuk harf duyarsiz tekillestirilir.
    # Hedef basina ortak SMB/DCOM on kontrolu Invoke-TargetBatch icinde yapilir; ping kosulu yoktur.
    $SeenTargets = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $Systems = @($Request.Targets | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $SeenTargets.Add($_) })
    $ReachableSystems = @()
    $UnreachableSystems = @()
    $ReachableSystems=[string[]]$Systems
    $UnreachableSystems=[string[]]@()
    # Guvenlik: progress dosyasi sadece Logs\Operations altina yazilabilir.
    $ProgressPath=if($null -ne $Request.PSObject.Properties['ProgressPath']){[string]$Request.ProgressPath}else{''}
    $CancelPath=[string](Get-RemoteOpsPackageValue $Request CancelPath '')
    $CheckpointRoot=[string](Get-RemoteOpsPackageValue $Request CheckpointRoot '')
    if($OperationName -eq 'PackageDeployment'){
        if(-not $CheckpointRoot){$CheckpointRoot=Join-Path $RunReportRoot 'Checkpoints'}
        $AllowedDataRoot=[IO.Path]::GetFullPath((Join-Path $BasePath 'Logs\Operations')).TrimEnd('\')+'\'
        foreach($RuntimePath in @($CancelPath,$CheckpointRoot)){
            if($RuntimePath -and -not[IO.Path]::GetFullPath($RuntimePath).StartsWith($AllowedDataRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Deployment runtime path is outside the operation directory.'}
        }
    }
    if($ProgressPath){
        $AllowedProgressRoot=[System.IO.Path]::GetFullPath((Join-Path $BasePath 'Logs\Operations')).TrimEnd('\')+'\'
        if(-not [System.IO.Path]::GetFullPath($ProgressPath).StartsWith($AllowedProgressRoot,[System.StringComparison]::OrdinalIgnoreCase)){
            throw 'Progress path is outside the operation data directory.'
        }
    }
    if(-not $IsWorker -and $ProgressPath){[IO.File]::WriteAllText(($ProgressPath+'.reportroot'),$RunReportRoot,[Text.Encoding]::UTF8)}
    if(-not $IsWorker){
        Write-RemoteOpsLog -Level 'INFO' -Message ("TARGETS | Operation={0} | Count={1}; operation-specific access will be checked before each target; ping is not required." -f $Request.Operation,$Systems.Count)
        $CurrentIdentity=[System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        Write-RemoteOpsLog -Level 'INFO' -Message ("START | ID={0} | Operation={1} | User={2} | Targets={3}" -f $OperationID,$Request.Operation,$CurrentIdentity,$Systems.Count)
    }

    # Modullerin entrypoint fonksiyonlarina verilen ortak parametreler (splat).
    $Common = @{
        BasePath=$BasePath; Systems=[string[]]$Systems; ReachableSystems=[string[]]$ReachableSystems; UnreachableSystems=[string[]]$UnreachableSystems
        OperationID=$OperationID; OperationDate=$OperationDate; OperationTime=$OperationTime
        TechnicalLogWriter=${function:Write-RemoteOpsLog}; OperationHistoryWriter=${function:Write-RemoteOpsHistory}
    }
    $Values = $Request.Values
    $OperationName = [string]$Request.Operation
    $Result = $null
    # Degisiklik yapan operasyonlarda onay kelimesi burada TEKRAR kontrol edilir.
    $RequiredConfirmation=switch($OperationName){
        'PackageTrigger' {'TRIGGER'} 'FileDelete' {'DELETE'} 'FileRestore' {'RESTORE'} 'FileRollback' {'ROLLBACK'}
        'PackageDeployment' {if([string]$Values.Action -eq 'Downgrade'){'DOWNGRADE'}else{'TRIGGER'}}
        'RegistryEdit' {'EDIT'} 'RegistryDelete' {'DELETE'} 'RegistryRollback' {'ROLLBACK'}
        'ServiceStartup' {'EDIT'} 'ServiceTaskRollback' {'ROLLBACK'} 'ProcessKill' {'KILL'}
        'ServiceControl' {([string]$Values.Action).ToUpperInvariant()}
        'ScheduledTaskAction' {([string]$Values.Action).ToUpperInvariant()}
        'ScheduledTaskDelete' {'DELETE'}
        'FileBrowser' {if($Values.Action -in @('Move','Replace')){([string]$Values.Action).ToUpperInvariant()}}
        default {''}
    }
    if(-not [string]::IsNullOrWhiteSpace([string]$RequiredConfirmation) -and [string]$Values.Confirm -cne $RequiredConfirmation){
        throw "Confirmation mismatch for $OperationName. Expected $RequiredConfirmation."
    }
    # GIRDI ON KONTROLU: modul menuleri hatali girdide menuye geri doner ve sonraki cevabi menu secimi
    # sanir (anlamsiz hata veya yanlis islem). Bu yuzden belirgin girdi hatalari islem baslamadan,
    # anlasilir bir mesajla burada durdurulur. Hicbir hedefe dokunulmaz.
    Assert-RemoteOpsRequestValues -OperationName $OperationName -InputValues $Values
    if(-not $script:RemoteOpsOperationMeta.ContainsKey($OperationName)){
            # PLUGIN: klasor/manifest/script yolu Plugins klasoru disina cikamaz; operasyon manifest'te tanimli olmali.
            if ([string]::IsNullOrWhiteSpace([string]$Request.PluginName) -or [string]::IsNullOrWhiteSpace([string]$Request.PluginScript)) {
                throw "Operation is not connected to a runner yet: $OperationName"
            }
            $PluginsRoot=[System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'Plugins'))
            if([string]::IsNullOrWhiteSpace([string]$Request.PluginRoot)){
                throw 'Plugin root was not included in the request.'
            }
            $PluginRoot=[System.IO.Path]::GetFullPath([string]$Request.PluginRoot)
            if(-not $PluginRoot.StartsWith(($PluginsRoot.TrimEnd('\')+'\'),[System.StringComparison]::OrdinalIgnoreCase)){
                throw 'Plugin folder path escapes Plugins root.'
            }
            $ManifestPath = Join-Path $PluginRoot 'manifest.json'
            if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
                throw "Plugin manifest is missing: $ManifestPath"
            }
            $PluginManifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $PluginDefinition = @($PluginManifest.Operations | Where-Object { $_.Name -ceq $OperationName }) | Select-Object -First 1
            if ($null -eq $PluginDefinition) {
                throw "Operation '$OperationName' is not declared by plugin '$($Request.PluginName)'."
            }
            $PluginScript = [System.IO.Path]::GetFullPath((Join-Path $PluginRoot ([string]$PluginManifest.Script)))
            if (-not $PluginScript.StartsWith(($PluginRoot.TrimEnd('\') + '\'),[System.StringComparison]::OrdinalIgnoreCase)) {
                throw 'Plugin script path escapes its plugin folder.'
            }
            if (-not (Test-Path -LiteralPath $PluginScript -PathType Leaf)) {
                throw "Plugin script is missing: $PluginScript"
            }
    }
    if($OperationName -eq 'PackageDeployment'){
        $Values.PackageDefinition=Copy-RemoteOpsPackageDefinition $Values.PackageDefinition
        if(-not $IsWorker){
            Write-RemoteOpsAtomicJson (Join-Path $RunReportRoot 'PackageDefinition.json') $Values.PackageDefinition
            Write-RemoteOpsAtomicJson (Join-Path $CheckpointRoot 'run.json') ([PSCustomObject]@{OperationID=$OperationID;ReportRoot=$RunReportRoot;Targets=@($Systems);Definition=$Values.PackageDefinition;Action=$Values.Action;Identity=$CurrentIdentity})
        }
    }

    $RunOperationID=$OperationID
    $script:RunLogID=$RunOperationID
    $InputTargets=[string[]]$Systems
    # ====================================================================
    # OPERASYON YONLENDIRME (dispatch)
    # Her hedef icin calisan scriptblock. Operasyon adina gore:
    #   ApplicationCheck/Inventory/PackageTrigger -> bu dosyadaki Invoke-*Request (ApplicationWorkers.ps1)
    #   EndpointInventory  -> Modules\InventoryOperations.ps1
    #   HealthCheck        -> Modules\HealthOperations.ps1
    #   File*              -> Modules\FileOperations.ps1 menusu (cevaplar Add-Answers ile)
    #   Registry*          -> Modules\RegistryOperations.ps1 menusu (rollback burada)
    #   Service*/Process*  -> Modules\ServiceTaskOperations.ps1 menusu
    #   ScheduledTask*     -> liste modulde, aksiyon/silme bu dosyada
    #   diger              -> Plugins\<Ad>\manifest.json ile tanimli plugin
    # Menu cevap dizilerindeki '1','2'... modul menusundeki secim numaralaridir; sonda '0' = menuden cik.
    # ====================================================================
    $InvokeTarget={
    $Result=$null
    switch -Regex ($OperationName) {
        '^PackageDeployment$' {
            $Result=Invoke-SavedPackageDeploymentRequest -InputValues $Values
            break
        }
        '^ApplicationCheck$' {
            $Result=Invoke-ApplicationCheckRequest -InputValues $Values
            break
        }
        '^ApplicationInventory$' {
            $Result=Invoke-ApplicationInventoryRequest
            break
        }
        '^PackageTrigger$' {
            if([string]$Values.Confirm -cne 'TRIGGER'){throw 'Package trigger confirmation is required.'}
            $Result=Invoke-PackageRequest -InputValues $Values
            break
        }
        '^EndpointInventory$' {
            $Result = Invoke-AOInventoryOperations @Common
            break
        }
        '^HealthCheck$' {
            $Result = Invoke-AOHealthCheck @Common -SkipApps:([bool]$Values.SkipApps)
            break
        }
        '^FileBrowser$' {
            $BrowseAction=[string]$Values.Action
            if($BrowseAction -eq 'Move' -and [string]$Values.Confirm -cne 'MOVE'){
                throw 'Move confirmation is required.'
            }
            if($BrowseAction -eq 'Replace' -and [string]$Values.Confirm -cne 'REPLACE'){
                throw 'Replace confirmation is required.'
            }
            $Answers=New-FileBrowserPromptAnswers -BrowsePath ([string]$Values.BrowsePath) -SelectedPath ([string]$Values.SelectedPath) -Action $BrowseAction -ComputerNames $ReachableSystems -MoveTarget ([string]$Values.MoveTarget) -ReplaceSource ([string]$Values.ReplaceSource) -Confirm ([string]$Values.Confirm)
            Add-Answers -Answers $Answers
            $Result=Invoke-AORemoteFileBrowseOperations -BasePath $BasePath -Systems $Systems -ReachableSystems $ReachableSystems -OperationID $OperationID -PullGroup ([IO.Path]::GetFileName($RunReportRoot))
            break
        }
        # FileOperations menusu: 1=Pull 2=Delete 3=Push 4=Compare 5=Restore 7=Rollback
        '^File(Pull|Delete|Push|Compare|Restore|Rollback)$' {
            $Answers = switch ($OperationName) {
                'FilePull' { @('1',[string]$Values.Path,'0') }
                'FileDelete' { @('2',[string]$Values.Path,'DELETE','0') }
                'FilePush' { @('3',[string]$Values.LocalPath,[string]$Values.Path,$(if($Values.Overwrite){'E'}else{'H'}),'0') }
                'FileCompare' { @('4',[string]$Values.LocalPath,[string]$Values.Path,'0') }
                'FileRestore' { @('5',$(if([string]::IsNullOrWhiteSpace([string]$Values.BackupPath)){'1'}else{[string]$Values.BackupPath}),[string]$Values.Confirm) }
                'FileRollback' { @('7','1',[string]$Values.Confirm,'0') }
            }
            Add-Answers $Answers
            # File rollback: secilen calismanin manifest'i hedeflere gore daraltilip gecici bir klasore yazilir.
            if($OperationName -eq 'FileRollback'){
                $RollbackRoot=Join-Path $BasePath 'FileRollbacks'
                $Runs=@(Get-ChildItem -LiteralPath $RollbackRoot -Directory -ErrorAction SilentlyContinue|Where-Object{Test-Path -LiteralPath (Join-Path $_.FullName 'manifest.csv') -PathType Leaf}|Where-Object{$Rows=@(Import-Csv -LiteralPath (Join-Path $_.FullName 'manifest.csv') -Delimiter ';' -ErrorAction SilentlyContinue|Where-Object{$Systems -contains [string]$_.ComputerName});$Rows.Count -gt 0}|Sort-Object LastWriteTime -Descending)
                if($Runs.Count -eq 0){throw 'File rollback run was not found.'}
                $RunIndex=if([string]::IsNullOrWhiteSpace([string]$Values.BackupPath)){1}else{[int]$Values.BackupPath}
                if($RunIndex -lt 1 -or $RunIndex -gt $Runs.Count){throw 'File rollback run number is invalid.'}
                $SourceManifest=Join-Path $Runs[$RunIndex-1].FullName 'manifest.csv'
                $ScopedRows=@(Import-Csv -LiteralPath $SourceManifest -Delimiter ';' -ErrorAction Stop|Where-Object{$Systems -contains [string]$_.ComputerName})
                if($ScopedRows.Count -eq 0){throw 'Selected file rollback has no entries for the target list.'}
                $ScopedRun=Join-Path $RollbackRoot ('GUI_{0}' -f [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $ScopedRun -Force|Out-Null
                $ScopedRows|Export-Csv -LiteralPath (Join-Path $ScopedRun 'manifest.csv') -NoTypeInformation -Encoding UTF8 -Delimiter ';'
                try{
                    $Result=Invoke-AOFileOperationsMenu @Common
                }finally{
                    Remove-Item -LiteralPath $ScopedRun -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            else{$Result = Invoke-AOFileOperationsMenu @Common -PullGroup ([IO.Path]::GetFileName($RunReportRoot))}
            # Modul bazi durumlarda (koruma engeli, uygun hedef yok) satirlari CSV'ye yazip menuye geri
            # doner ve ResultCsv'yi BOS dondurur. Bu durumda sonuc o calismanin CSV kopyasindan okunur.
            # Add-AOFileOperationRows her cagrida bu calismaya ait '<OperationID>_File<Islem>.csv' kopyasini yazar.
            $FileCsvName=if($OperationName -in @('FilePull','FileDelete','FilePush','FileCompare','FileRestore')){'{0}_{1}.csv' -f ($OperationID -creplace '[^A-Za-z0-9_-]','_'),$OperationName}else{''}
            if($FileCsvName -and ($null -eq $Result -or $null -eq $Result.PSObject.Properties['ResultCsv'] -or [string]::IsNullOrWhiteSpace([string]$Result.ResultCsv))){
                $Result=[PSCustomObject]@{Completed=$true;ResultCsv=(Join-Path (Join-Path (Join-Path $BasePath 'Logs') 'FileOperations') $FileCsvName)}
            }
            break
        }
        # RegistryOperations menusu: 1=Read 2=Edit 3=Delete 4=Rollback
        '^Registry(Read|Edit|Delete|Rollback)$' {
            if($OperationName -eq 'RegistryRollback'){
                $Result=[PSCustomObject]@{Completed=$true;ResultCsv=(Invoke-RegistryRollbackRequest -InputValues $Values)}
                break
            }
            $Answers = switch ($OperationName) {
                'RegistryRead' { @('1',[string]$Values.RegistryPath,[string]$Values.ValueName,'0') }
                'RegistryEdit' { @('2',[string]$Values.RegistryPath,[string]$Values.ValueName,[string]$Values.Value,[string]$Values.Confirm,'0') }
                'RegistryDelete' { @('3',[string]$Values.RegistryPath,[string]$Values.ValueName,[string]$Values.Confirm,'0') }
                'RegistryRollback' { @('4','ROLLBACK','0') }
            }
            if($OperationName -eq 'RegistryRollback'){
                $ScopedManifestInfo=New-TargetScopedManifest -ManifestPath ([string]$Values.ManifestPath) -ManifestRoot (Join-Path $BasePath 'RegistryRollback') -Label 'Registry'
                $ScopedManifest=[string]$ScopedManifestInfo.Path
                $Answers=@('4',$ScopedManifest,[string]$Values.Confirm,'0')
            }
            Add-Answers $Answers
            try{
                $Result = Invoke-RegistryOperationsMenu @Common
            }finally{
                if($OperationName -eq 'RegistryRollback' -and $ScopedManifest){
                    Remove-Item -LiteralPath $ScopedManifest -Force -ErrorAction SilentlyContinue
                }
            }
            break
        }
        # ServiceTaskOperations menusu: 1=Liste 2=Start/Stop/Restart 3=Startup type
        '^Service(List|Control|Startup)$' {
            $Answers = switch ($OperationName) {
                'ServiceList' { @('1',[string]$Values.Filter,'0') }
                'ServiceControl' { @('2',[string]$Values.ServiceName,([string]$Values.Action).ToLowerInvariant(),[string]$Values.Confirm,'0') }
                'ServiceStartup' { @('3',[string]$Values.ServiceName,$(switch ([string]$Values.StartupType) {'Automatic' {'auto'} 'Manual' {'demand'} 'Disabled' {'disabled'}}),[string]$Values.Confirm,'0') }
            }
            Add-Answers $Answers
            $Result = Invoke-ServiceTaskOperationsMenu @Common
            break
        }
        '^ServiceTaskRollback$' {
            $Result=[PSCustomObject]@{Completed=$true;ResultCsv=(Invoke-ServiceTaskRollbackRequest -InputValues $Values)}
            break
        }
        # Task listeleme modulde (menu 4); Run/Enable/Disable/Delete Invoke-ScheduledTaskActionRequest ile.
        '^ScheduledTask(List|Action|Delete)$' {
            if ($OperationName -eq 'ScheduledTaskList') { $Answers=@('4',[string]$Values.TaskFilter,'0') }
            else {
                if($OperationName -eq 'ScheduledTaskDelete'){
                    $Values|Add-Member -NotePropertyName Action -NotePropertyValue 'Delete' -Force
                }
                $Result=Invoke-ScheduledTaskActionRequest -InputValues $Values
                break
            }
            Add-Answers $Answers
            $Result = Invoke-ServiceTaskOperationsMenu @Common
            break
        }
        # Process: menu 9 = sorgula, 10 = kill (korumali sistem surecleri atlanir).
        '^Process(Query|Kill)$' {
            if ($OperationName -eq 'ProcessQuery') { $Answers=@('9',[string]$Values.ProcessFilter,'0') }
            else { $Answers=@('10',[string]$Values.ProcessFilter,'KILL','0') }
            Add-Answers $Answers
            $Result = Invoke-ServiceTaskOperationsMenu @Common
            break
        }
        default {
            # Plugin dispatch was validated before any target access.
            $PluginContext = [PSCustomObject]@{ BasePath=$BasePath; Systems=$Systems; ReachableSystems=$ReachableSystems; UnreachableSystems=$UnreachableSystems; OperationID=$OperationID; OperationDate=$OperationDate; OperationTime=$OperationTime; TechnicalLogWriter=${function:Write-RemoteOpsLog}; OperationHistoryWriter=${function:Write-RemoteOpsHistory} }
            $Result = Invoke-PluginScript -PluginScriptPath $PluginScript -PluginRequest $Request -PluginContext $PluginContext
        }
    }
    return $Result
    }
    # ====================================================================
    # CALISTIRMA: worker / paralel / sirali
    # ====================================================================
    #
    # Istenen paralellik 1-10 arasina sikistirilir; operasyon paralel-guvenli degilse sirali calisir.
    $RequestedParallelism=1
    if($null -ne $Request.PSObject.Properties['Parallelism']){
        try{
            $RequestedParallelism=[int]$Request.Parallelism
        }catch{
            $RequestedParallelism=1
        }
    }
    $RequestedParallelism=[Math]::Max(1,[Math]::Min(10,$RequestedParallelism))
    $PluginParallelSafe=($null -ne $Request.PSObject.Properties['PluginParallelSafe'] -and [bool]$Request.PluginParallelSafe)
    $ParallelAllowed=($script:ParallelSafeOperations -contains $OperationName) -or $PluginParallelSafe
    # Worker modu: tek hedefi isle, sonucu result.xml olarak yaz ve cik (rapor koordinatorde uretilir).
    if($IsWorker){
        $Result=Invoke-TargetBatch -InputTargets $InputTargets -RunOperationID $RunOperationID -ProgressPath '' -InvokeTarget $InvokeTarget -IndexOffset ([int]$WorkerInfo.IndexOffset)
        $Payload=[PSCustomObject]@{Rows=@($Result.Rows);Outcomes=@($Result.Outcomes);Messages=@($script:OperationMessages);Health=@($(if(Get-Variable AOHealthDetails -Scope Script -ErrorAction SilentlyContinue){$script:AOHealthDetails}))}
        $TemporaryResult=[string]$WorkerInfo.ResultPath+'.tmp'
        Export-Clixml -InputObject $Payload -LiteralPath $TemporaryResult -Depth 8
        Move-Item -LiteralPath $TemporaryResult -Destination ([string]$WorkerInfo.ResultPath) -Force
        return
    }
    # Koordinator: paralel calistir; aksi halde sirali dongu.
    if($RequestedParallelism -gt 1 -and $InputTargets.Count -gt 1 -and $ParallelAllowed){
        $Workers=[Math]::Min($RequestedParallelism,$InputTargets.Count)
        $Result=Invoke-ParallelTargets -InputTargets $InputTargets -RunOperationID $RunOperationID -ProgressPath $ProgressPath -Parallelism $Workers
    }
    else{
        if($RequestedParallelism -gt 1 -and $InputTargets.Count -gt 1){
            Write-Host 'Bu operasyon paralel calismayi desteklemiyor; bilgisayarlar sirayla islenecek.'
        }
        $Result=Invoke-TargetBatch -InputTargets $InputTargets -RunOperationID $RunOperationID -ProgressPath $ProgressPath -InvokeTarget $InvokeTarget
    }
    # ====================================================================
    # RAPORLAMA
    # - Hedef basina ara dosyalar (<RunID>-NNNN_*) Detail klasorune tasinir
    # - Ledger kaydi yazilir (Rapor sekmesinin veri kaynagi)
    # - HealthCheck icin tek Health.html uretilir
    # - Complete-RemoteOpsReports: Results.csv/html + Activity.csv/html
    # - progress.json 'Completed' olarak isaretlenir
    # ====================================================================
    $OperationID=$RunOperationID
    # Modules name their intermediate CSV/HTML files per target (<RunID>-NNNN_*); keep one run-level report and tuck those into Detail.
    try{
        $DetailRoot=Join-Path $RunReportRoot 'Detail'
        $TargetFilePattern='^'+[regex]::Escape($RunOperationID)+'-\d{4}_'
        foreach($SubFolder in @('Application','FileOperations','Inventory','ServiceTask','RemoteOps','Health')){
            $SourceFolder=Join-Path (Join-Path $BasePath 'Logs') $SubFolder
            if(-not(Test-Path -LiteralPath $SourceFolder -PathType Container)){continue}
            $TargetFiles=@(Get-ChildItem -LiteralPath $SourceFolder -File -ErrorAction SilentlyContinue|Where-Object{$_.Name -match $TargetFilePattern -and $_.Extension -in @('.csv','.html')})
            if($TargetFiles.Count -eq 0){continue}
            New-Item -ItemType Directory -Path $DetailRoot -Force -ErrorAction Stop|Out-Null
            foreach($TargetFile in $TargetFiles){
                Move-Item -LiteralPath $TargetFile.FullName -Destination (Join-Path $DetailRoot ($SubFolder+'_'+$TargetFile.Name)) -Force -ErrorAction Stop
            }
        }
    }
    catch{Write-Warning "Per-target detail files could not be consolidated: $($_.Exception.Message)"}
    if($null -ne $Result.PSObject.Properties['Outcomes']){
        [void](Write-RemoteOpsLedger -BasePath $BasePath -OperationID $OperationID -Operation $OperationName -Category ([string]$Request.Category) -Identity ('{0}\{1}' -f $Request.Domain,$Request.UserName) -Outcomes @($Result.Outcomes))
    }

    Write-RemoteOpsLog -Level 'INFO' -Message ("END | ID={0} | Operation={1}" -f $OperationID,$OperationName)
    $PrimaryReport=''
    if($OperationName -eq 'HealthCheck'){
        try{
            $PrimaryReport=Write-AOHealthHtmlReport -Path (Join-Path $RunReportRoot 'Health.html') -Details @($script:AOHealthDetails) -OperationID $OperationID
        }
        catch{Write-Warning "Health report could not be written: $($_.Exception.Message)"}
    }
    $ReportTitle=if($OperationName -eq 'PackageDeployment'){$Values.PackageDefinition.Name+' / '+$Values.Action}else{$OperationName}
    Complete-RemoteOpsReports -Result $Result -Title $ReportTitle -OperationID $OperationID -ReportRoot $RunReportRoot -Candidates $script:ReportCandidates -Messages $script:OperationMessages -PrimaryReport $PrimaryReport
    Write-TargetProgress -Path $ProgressPath -Total $InputTargets.Count -Completed $InputTargets.Count -CurrentTarget '' -Stage 'Completed'
    # Moduller sonuc uretince menuden kendisi cikabilir; bu durumda kuyrukta kalan '0' (menuden cik)
    # cevabi normaldir. Sadece gercekten kullanilmayan GUI degerleri uyari olarak yazilir.
    $UnusedAnswers=@($script:PromptAnswers|Where-Object{$_ -ne '0'})
    if ($UnusedAnswers.Count -gt 0) {
        Write-Host "Unused UI answers: $($UnusedAnswers.Count)" -ForegroundColor Yellow
    }
}
####################################################################
# HATA YAKALAMA
# Worker ise: hatayi yazip exit 1. Degilse: progress 'Failed' yapilir,
# hata loglanir ve (mumkunse) Error.csv/html raporu uretilir; exit 1.
####################################################################
catch {
    if($null -ne (Get-Variable IsWorker -ErrorAction SilentlyContinue) -and $IsWorker){
        Write-Host "WORKER FAILED: $($_.Exception.Message)"
        try{
            Write-RemoteOpsLog -Level 'ERROR' -Message $_.Exception.Message
        }catch{ }
        exit 1
    }
    Write-Host "REMOTE OPS FAILED: $($_.Exception.Message)" -ForegroundColor Red
    if($null -ne (Get-Variable ProgressPath -ErrorAction SilentlyContinue) -and $null -ne (Get-Variable InputTargets -ErrorAction SilentlyContinue)){
        Write-TargetProgress -Path $ProgressPath -Total $InputTargets.Count -Completed 0 -CurrentTarget '' -Stage 'Failed'
    }
    try { Write-RemoteOpsLog -Level 'ERROR' -Message $_.Exception.Message } catch { }
    $OriginalError=$_.Exception.Message
    if($null -ne (Get-Variable RunReportRoot -ErrorAction SilentlyContinue)){
        try{
            $Failure=[PSCustomObject]@{ResultCsv=(Join-Path $RunReportRoot 'Error.csv');Rows=@([PSCustomObject]@{Operation=$OperationName;Status='Failed';ErrorDetail=$OriginalError})}
            Complete-RemoteOpsReports -Result $Failure -Title $OperationName -OperationID $OperationID -ReportRoot $RunReportRoot -Messages $script:OperationMessages
        }
        catch{Write-Warning "Failure report could not be written: $($_.Exception.Message)"}
    }
    exit 1
}
finally { }
