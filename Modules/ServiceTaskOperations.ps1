<#
AO Service and Scheduled Task Operations module.
Provides CLM-compatible service/task inventory, control, edit and rollback.
The module only defines functions and registers its operation when loaded.
#>

# ====================================================================
# NASIL CALISIR (ozet)
# - Konsol menusu (Read-Host) ile yazilmistir; GUI'den calisirken Runner cevaplari
#   sirayla verir (ornek ServiceControl: '2', <servis>, 'restart', 'RESTART', '0').
# - Menu: 1=Servis listele 2=Start/Stop/Restart 3=Startup type 4=Task listele
#         5=Task calistir 6=Task enable/disable 7=Rollback 8/9=Process listele/sorgula
#         10=Process kill 0=Bitir
# - Tum uzak islemler CIM/DCOM oturumu ile yapilir (Get-ServiceTaskSession).
# - Degisiklik yapan islemler once eski durumu ServiceTaskRollbacks\<ID>_*.csv
#   manifest'ine yazar (rollback icin).
# - Sonuc raporu: Write-ServiceTaskReport HTML+CSV yazar ve HTML'i Start-Process ile
#   acar; GUI'de Runner bu acma istegini yakalayip yanindaki CSV'yi sonuc olarak okur.
#   (Bu yuzden menu 0 ile donerken ResultCsv bos olabilir.)
# ====================================================================
Set-StrictMode -Version 2.0

# Hashtable'dan nesne uretir (CLM uyumlu yazim).
function New-ServiceTaskObject {
    param([hashtable]$Properties)
    return [PSCustomObject]$Properties
}

# Rollback manifest'ini (';' ayracli CSV) yazar.
function Write-ServiceTaskManifest {
    param([string]$Path, [object[]]$Rows)
    $Parent = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $Parent -PathType Container)) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }
    $Temporary=Join-Path $Parent ('.'+[guid]::NewGuid().ToString('N')+'.tmp')
    try{
        @($Rows)|Export-Csv -LiteralPath $Temporary -NoTypeInformation -Encoding UTF8 -Delimiter ';' -ErrorAction Stop
        if([IO.File]::Exists($Path)){[IO.File]::Replace($Temporary,$Path,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($Temporary,$Path)}
    }finally{if([IO.File]::Exists($Temporary)){[IO.File]::Delete($Temporary)}}
}

# HTML kacis yardimcisi.
function ConvertTo-ServiceTaskHtmlValue {
    param($Value)
    if ($null -eq $Value) { return '' }
    return ([System.Net.WebUtility]::HtmlEncode([string]$Value))
}

# Logs\ServiceTask\<ID>_<RaporAdi>.csv + .html yazar ve HTML'i acar.
# Basarili / basarisiz istemci sayilarini ozet kartlarinda gosterir.
function Write-ServiceTaskReport {
    param([string]$BasePath, [string]$OperationID, [string]$ReportName, [object[]]$Rows, [string[]]$ClientNames, [string[]]$SuccessfulClients)
    $ReportRoot = Join-Path (Join-Path $BasePath 'Logs') 'ServiceTask'
    New-Item -ItemType Directory -Path $ReportRoot -Force | Out-Null
    $SafeName = $ReportName -creplace '[^A-Za-z0-9_-]', '_'
    $Stem = '{0}_{1}' -f $OperationID, $SafeName
    $CsvPath = Join-Path $ReportRoot ($Stem + '.csv')
    $HtmlPath = Join-Path $ReportRoot ($Stem + '.html')
    $ReportRows = @($Rows)
    if ($ReportRows.Count -gt 0) {
        $ReportRows | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    }
    else { Set-Content -LiteralPath $CsvPath -Value '' -Encoding UTF8 }
    $Headers = @($ReportRows | ForEach-Object { $_.PSObject.Properties.Name } | Select-Object -Unique)
    $HeaderHtml = '<tr>' + (($Headers | ForEach-Object { '<th>' + (ConvertTo-ServiceTaskHtmlValue $_) + '</th>' }) -join '') + '</tr>'
    $BodyHtml = @($ReportRows | Sort-Object ComputerName, ObjectName, ProcessName, TaskName | ForEach-Object {
        $Row = $_
        '<tr>' + (($Headers | ForEach-Object { $Property = $Row.PSObject.Properties[$_]; $Value = if ($null -ne $Property) { $Property.Value } else { '' }; '<td>' + (ConvertTo-ServiceTaskHtmlValue $Value) + '</td>' }) -join '') + '</tr>'
    }) -join "`n"
    $ReportClients = @($ClientNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    if ($ReportClients.Count -eq 0) {
        $ReportClients = @($ReportRows | ForEach-Object ComputerName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    }
    $SuccessfulReportClients = @($SuccessfulClients | Where-Object { $ReportClients -contains $_ } | Sort-Object -Unique)
    $TotalClientCount = $ReportClients.Count
    $SuccessClientCount = $SuccessfulReportClients.Count
    $FailedClientCount = $TotalClientCount - $SuccessClientCount
    $ClientOptions = '<option value="">Tum bilgisayarlar</option>' + (($ReportClients | ForEach-Object { '<option value="' + (ConvertTo-ServiceTaskHtmlValue $_) + '">' + (ConvertTo-ServiceTaskHtmlValue $_) + '</option>' }) -join '')
    $Style = '<style>body{font-family:Segoe UI,Arial;background:#f4f6f8;color:#20252b;margin:24px}h1{color:#163a5f}.meta{color:#667085}.summary{display:flex;gap:12px;margin:18px 0}.card{background:white;border:1px solid #d9e1e8;border-radius:6px;padding:12px 18px}.label{display:block;color:#667085;font-size:12px}.value{font-size:24px;font-weight:600}.filter{width:320px;max-width:100%;padding:9px;border:1px solid #b8c2cc;border-radius:4px;margin-bottom:12px}table{border-collapse:collapse;background:white;width:100%;font-size:12px}th{background:#163a5f;color:white;text-align:left;padding:8px;position:sticky;top:0}td{border:1px solid #d9e1e8;padding:7px;vertical-align:top}tr:nth-child(even){background:#f8fafc}</style>'
    $Summary = "<div class='summary'><div class='card'><span class='label'>Toplam istemci</span><span class='value'>$TotalClientCount</span></div><div class='card'><span class='label'>Basarili istemci</span><span class='value'>$SuccessClientCount</span></div><div class='card'><span class='label'>Hatali istemci</span><span class='value'>$FailedClientCount</span></div><div class='card'><span class='label'>Toplam kayit</span><span class='value'>$($ReportRows.Count)</span></div></div>"
    $Script = '<script>function filterRows(){var q=document.getElementById("reportFilter").value.toLowerCase();var client=document.getElementById("clientFilter").value.toLowerCase();document.querySelectorAll("#reportTable tbody tr").forEach(function(row){var matchesText=row.textContent.toLowerCase().indexOf(q)>=0;var matchesClient=!client||row.cells[0].textContent.toLowerCase()===client;row.style.display=matchesText&&matchesClient?"":"none";});}</script>'
    $Html = "<!DOCTYPE html><html><head><meta charset='utf-8'><title>$SafeName</title>$Style</head><body><h1>$SafeName</h1><div class='meta'>OperationID: $(ConvertTo-ServiceTaskHtmlValue $OperationID) | Olusturulma: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>$Summary<select id='clientFilter' class='filter' onchange='filterRows()'>$ClientOptions</select><input id='reportFilter' class='filter' type='search' placeholder='Tabloda ara...' oninput='filterRows()' /><table id='reportTable'><thead>$HeaderHtml</thead><tbody>$BodyHtml</tbody></table>$Script</body></html>"
    Set-Content -LiteralPath $HtmlPath -Value $Html -Encoding UTF8 -ErrorAction Stop
    Start-Process -FilePath $HtmlPath
    Write-Host "HTML rapor: $HtmlPath" -ForegroundColor Cyan
    Write-Host "CSV rapor : $CsvPath" -ForegroundColor Cyan
    return $HtmlPath
}

# Hedefe CIM oturumu (DCOM protokolu, 15 sn zaman asimi). Cagiran taraf Remove-CimSession ile kapatir.
function Get-ServiceTaskSession {
    param([string]$ComputerName)
    return New-CimSession -ComputerName $ComputerName -SessionOption (New-CimSessionOption -Protocol Dcom) -OperationTimeoutSec 15 -ErrorAction Stop
}

# Kullanici girdisi (auto/demand/disabled...) -> Win32_Service.ChangeStartMode degeri.
function Convert-ServiceStartMode {
    param([string]$Mode)
    switch ($Mode.Trim().ToLowerInvariant()) {
        'auto' { return 'Automatic' }
        'automatic' { return 'Automatic' }
        'demand' { return 'Manual' }
        'manual' { return 'Manual' }
        'disabled' { return 'Disabled' }
        'boot' { return 'Boot' }
        'system' { return 'System' }
        default { throw "Gecersiz startup type: $Mode" }
    }
}

# Servisin baslangic tipini degistirir; ReturnValue 0 degilse hata firlatir.
function Set-ServiceTaskStartMode {
    param($Session, $Service, [string]$Mode)
    $WmiMode = Convert-ServiceStartMode $Mode
    $Result = Invoke-CimMethod -CimSession $Session -InputObject $Service -MethodName ChangeStartMode -Arguments @{ StartMode=$WmiMode } -ErrorAction Stop
    if ($Result.ReturnValue -ne 0) {
        throw "ChangeStartMode basarisiz: ReturnValue=$($Result.ReturnValue), Mode=$WmiMode"
    }
    return $Result
}

# Win32_Service metodunu cagirir; kabul edilen donus kodlari disinda hata firlatir
# (orn. StartService icin 10 = zaten calisiyor, StopService icin 6 = zaten durmus).
function Invoke-ServiceTaskMethodChecked {
    # Win32_Service methods return a status code instead of throwing; a non-accepted code must fail the target.
    param($Session, $Service, [string]$Method, [int[]]$Accepted = @(0))
    $Result = Invoke-CimMethod -CimSession $Session -InputObject $Service -MethodName $Method -Arguments @{} -ErrorAction Stop
    if ($Accepted -notcontains [int]$Result.ReturnValue) { throw "$Method returned $($Result.ReturnValue)." }
    return $Result
}

# Servis istenen duruma (orn. Stopped) gelene kadar bekler; sure dolarsa hata.
function Wait-ServiceTaskState {
    param($Session, [string]$ServiceName, [string]$State, [int]$TimeoutSeconds = 30)
    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $Current = Get-CimInstance -CimSession $Session -ClassName Win32_Service -Filter ("Name='{0}'" -f ($ServiceName -replace "'", "''")) -ErrorAction Stop
        if ($null -eq $Current -or [string]$Current.State -eq $State) { return $Current }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $Deadline)
    throw "Service did not reach state '$State' within $TimeoutSeconds seconds."
}

# MENU GIRIS NOKTASI (Runner / MD_Script modul menusu cagirir).
function Invoke-ServiceTaskOperationsMenu {
    [CmdletBinding()]
    param(
        [string]$BasePath, [string[]]$Systems, [string[]]$ReachableSystems,
        [string[]]$UnreachableSystems, [string]$OperationID,
        [string]$OperationDate, [string]$OperationTime,
        [scriptblock]$TechnicalLogWriter, [scriptblock]$OperationHistoryWriter
    )

    $RollbackRoot = Join-Path $BasePath 'ServiceTaskRollbacks'
    New-Item -ItemType Directory -Path $RollbackRoot -Force | Out-Null

    while ($true) {
        Write-Host ''
        Write-Host '============================================================' -ForegroundColor Cyan
        Write-Host ' SERVICE AND TASK OPERATIONS' -ForegroundColor Cyan
        Write-Host '============================================================' -ForegroundColor Cyan
        Write-Host '1 - Servisleri listele'
        Write-Host '2 - Servis baslat/durdur/restart'
        Write-Host '3 - Servis startup type duzenle'
        Write-Host '4 - Scheduled task listele'
        Write-Host '5 - Scheduled task calistir'
        Write-Host '6 - Scheduled task enable/disable'
        Write-Host '7 - Rollback uygula'
        Write-Host '8 - Tum processleri listele'
        Write-Host '9 - Process sorgula'
        Write-Host '10 - Process kill'
        Write-Host '0 - Bitir'
        # Menu secimi (GUI'de ilk cevap).
        $Selection = (Read-Host 'Seciminiz').Trim()
        if ($Selection -eq '0') {
            return New-ServiceTaskObject @{ Completed=$true; ResultCsv=''; Message='Service/Task Operations tamamlandi.' }
        }

        # 7 = ROLLBACK: manifest satirlarina gore servis durumu/baslangic tipi ve task
        # enable/disable eski haline getirilir. (GUI rollback'i Runner'daki kendi fonksiyonunu kullanir.)
        if ($Selection -eq '7') {
            $Manifest = (Read-Host 'Rollback manifest path (bos=son manifest)').Trim()
            if ([string]::IsNullOrWhiteSpace($Manifest)) {
                $Manifest = Get-ChildItem -LiteralPath $RollbackRoot -Filter '*.csv' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
            }
            if ([string]::IsNullOrWhiteSpace($Manifest) -or -not (Test-Path -LiteralPath $Manifest -PathType Leaf)) {
                Write-Host 'Rollback manifest bulunamadi.' -ForegroundColor Yellow
                continue
            }
            if ((Read-Host 'Rollback icin ROLLBACK yazin').Trim().ToUpperInvariant() -ne 'ROLLBACK') { continue }
            foreach ($Row in @(Import-Csv -LiteralPath $Manifest -Delimiter ';')) {
                try {
                    $Session = Get-ServiceTaskSession $Row.ComputerName
                    try {
                        if ($Row.ObjectType -eq 'Service') {
                            if ($Row.Action -eq 'StartStop') {
                                if ($Row.OldState -eq 'Running') {
                                    Invoke-CimMethod -CimSession $Session -ClassName Win32_Service -MethodName StartService -Arguments @{} -ErrorAction Stop | Out-Null
                                } else {
                                    Invoke-CimMethod -CimSession $Session -ClassName Win32_Service -MethodName StopService -Arguments @{} -ErrorAction Stop | Out-Null
                                }
                            }
                            elseif ($Row.Action -eq 'StartupType') {
                                Set-ServiceTaskStartMode -Session $Session -Service (Get-CimInstance -CimSession $Session -ClassName Win32_Service -Filter "Name='$($Row.ObjectName)'" -ErrorAction Stop) -Mode $Row.OldStartMode | Out-Null
                            }
                        }
                        else {
                            $Task = Get-CimInstance -CimSession $Session -Namespace 'root\Microsoft\Windows\TaskScheduler' -ClassName MSFT_ScheduledTask -Filter "TaskName='$($Row.TaskName)'" -ErrorAction Stop
                            if ($Row.Action -eq 'EnableDisable') {
                                if ($Row.OldEnabled -eq 'True') {
                                    Enable-ScheduledTask -CimSession $Session -TaskName $Row.TaskName -TaskPath $Row.TaskPath -ErrorAction Stop
                                } else {
                                    Disable-ScheduledTask -CimSession $Session -TaskName $Row.TaskName -TaskPath $Row.TaskPath -ErrorAction Stop
                                }
                            }
                        }
                        Write-Host "$($Row.ComputerName) : ROLLBACK OK | $($Row.ObjectName)" -ForegroundColor Green
                    } finally { Remove-CimSession -CimSession $Session -ErrorAction SilentlyContinue }
                } catch {
                    Write-Host "$($Row.ComputerName) : ROLLBACK HATA | $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            continue
        }

        # 8/9/10 = PROCESS: listele / ad-PID ile sorgula / sonlandir.
        # Kill'de ad tam eslesmeli (veya PID); korumali sistem surecleri (lsass, csrss, svchost...) atlanir.
        if ($Selection -in @('8','9','10')) {
            $ProcessFilter = if ($Selection -eq '8') { '' } else { (Read-Host 'Process adi veya PID').Trim() }
            if ($Selection -eq '10' -and [string]::IsNullOrWhiteSpace($ProcessFilter)) {
                Write-Host 'Process adi veya PID bos olamaz.' -ForegroundColor Yellow
                continue
            }
            if ($Selection -eq '10' -and (Read-Host 'Kill islemi icin KILL yazin').Trim().ToUpperInvariant() -ne 'KILL') {
                continue
            }
            $ManifestRows=@()
            $ReportRows=@()
            $SuccessfulClients=@()
            $ProtectedProcessNames=@('system','registry','smss.exe','csrss.exe','wininit.exe','winlogon.exe','services.exe','lsass.exe','svchost.exe','memory compression')
            foreach($ComputerName in $ReachableSystems){
                try{
                    $Session=Get-ServiceTaskSession $ComputerName
                    try{
                        # Filtre: rakamsa PID; kill'de tam ad (".exe" eki opsiyonel); sorguda ad icinde gecen.
                        $Processes=@(Get-CimInstance -CimSession $Session -ClassName Win32_Process -ErrorAction Stop)
                        $SuccessfulClients+=$ComputerName
                        if(-not [string]::IsNullOrWhiteSpace($ProcessFilter)){
                            $Processes=@($Processes|Where-Object{if($ProcessFilter -match '^\d+$'){[int64]$_.ProcessId -eq [int64]$ProcessFilter}elseif($Selection -eq '10'){$_.Name -ieq $ProcessFilter -or $_.Name -ieq ($ProcessFilter+'.exe')}else{$_.Name.IndexOf($ProcessFilter,[System.StringComparison]::OrdinalIgnoreCase)-ge 0}})
                        }
                        if(@($Processes).Count -eq 0){
                            $ReportRows += [PSCustomObject]@{ComputerName=$ComputerName;ProcessName='';ProcessId='';Path='';Status='NotFound';ErrorDetail='No matching process.'}
                        }
                        foreach($Process in $Processes){
                            if($Selection -eq '10' -and $ProtectedProcessNames -contains $Process.Name.ToLowerInvariant()){
                                $ReportRows += [PSCustomObject]@{ComputerName=$ComputerName;ProcessName=$Process.Name;ProcessId=$Process.ProcessId;Path=$Process.ExecutablePath;Status='Skipped';ErrorDetail='Protected system process; not terminated.'}
                                Write-Host "$ComputerName : KILL ATLANDI (korumali) | $($Process.Name)"
                                continue
                            }
                            if($Selection -eq '10'){
                                $ManifestRows+=New-ServiceTaskObject @{ComputerName=$ComputerName;ObjectType='Process';ObjectName=$Process.Name;Action='Kill';ProcessId=$Process.ProcessId;CreationDate=$Process.CreationDate;OperationID=$OperationID}
                                $TerminateResult=Invoke-CimMethod -CimSession $Session -InputObject $Process -MethodName Terminate -Arguments @{Reason=1} -ErrorAction Stop
                                if([int]$TerminateResult.ReturnValue -ne 0){
                                    throw "Terminate returned $($TerminateResult.ReturnValue) for $($Process.Name) (PID $($Process.ProcessId))."
                                }
                                $ReportRows += [PSCustomObject]@{ComputerName=$ComputerName;ProcessName=$Process.Name;ProcessId=$Process.ProcessId;Path=$Process.ExecutablePath;Status='Success';ErrorDetail='Terminated'}
                                Write-Host "$ComputerName : KILL OK | $($Process.Name) | PID=$($Process.ProcessId)" -ForegroundColor Green
                            }else{
                                $ReportRows += [PSCustomObject]@{ComputerName=$ComputerName;ProcessName=$Process.Name;ProcessId=$Process.ProcessId;Path=$Process.ExecutablePath;Status='Success';ErrorDetail=''}
                                Write-Host "$ComputerName : $($Process.Name) | PID=$($Process.ProcessId) | Path=$($Process.ExecutablePath)"
                            }
                        }
                    }finally{
                        Remove-CimSession -CimSession $Session -ErrorAction SilentlyContinue
                    }
                }catch{
                    $ReportRows += [PSCustomObject]@{ComputerName=$ComputerName;ProcessName='';ProcessId='';Path='';Status='Failed';ErrorDetail=$_.Exception.Message}
                    Write-Host "$ComputerName : PROCESS HATA | $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            # Kill yapildiysa kayit manifest'i yazilir (process geri alinamaz, sadece iz amacli).
            if($Selection -eq '10' -and $ManifestRows.Count -gt 0){
                $ManifestPath=Join-Path $RollbackRoot ("{0}_Processes.csv" -f $OperationID)
                Write-ServiceTaskManifest -Path $ManifestPath -Rows $ManifestRows
                Write-Host "Process kill manifest: $ManifestPath" -ForegroundColor Cyan
            }
            [void](Write-ServiceTaskReport -BasePath $BasePath -OperationID $OperationID -ReportName $(if($Selection -eq '10'){'ProcessKill'}else{'ProcessQuery'}) -Rows $ReportRows -ClientNames $Systems -SuccessfulClients $SuccessfulClients)
            continue
        }

        # 1 = SERVIS LISTELE (ad veya gorunen ada gore filtre; bos/'*' = tumu).
        if ($Selection -eq '1') {
            $NameFilter = (Read-Host 'Servis adi/display name filtresi (bos=tumu)').Trim()
            $ReportRows = @()
            $SuccessfulClients = @()
            foreach ($ComputerName in $ReachableSystems) {
                try {
                    $Session = Get-ServiceTaskSession $ComputerName
                    try {
                        $Services = @(Get-CimInstance -CimSession $Session -ClassName Win32_Service -ErrorAction Stop)
                        $SuccessfulClients += $ComputerName
                        if (-not [string]::IsNullOrWhiteSpace($NameFilter) -and $NameFilter -ne '*') {
                            $Services = @($Services | Where-Object {
                                $_.Name.IndexOf($NameFilter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                                $_.DisplayName.IndexOf($NameFilter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
                            })
                        }
                        if (@($Services).Count -eq 0) {
                            $ReportRows += [PSCustomObject]@{ ComputerName=$ComputerName; ServiceName=''; DisplayName=''; State=''; StartMode=''; Status='NotFound'; ErrorDetail='No matching service.' }
                        }
                        foreach ($Service in $Services) {
                            $ReportRows += [PSCustomObject]@{ ComputerName=$ComputerName; ServiceName=$Service.Name; DisplayName=$Service.DisplayName; State=$Service.State; StartMode=$Service.StartMode; Status='Success'; ErrorDetail='' }
                            Write-Host "$ComputerName : $($Service.Name) | $($Service.State) | $($Service.StartMode) | $($Service.DisplayName)"
                        }
                    } finally {
                        Remove-CimSession -CimSession $Session -ErrorAction SilentlyContinue
                    }
                } catch {
                    $ReportRows += [PSCustomObject]@{ ComputerName=$ComputerName; ServiceName=''; DisplayName=''; State=''; StartMode=''; Status='Failed'; ErrorDetail=$_.Exception.Message }
                    Write-Host "$ComputerName : HATA | $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            [void](Write-ServiceTaskReport -BasePath $BasePath -OperationID $OperationID -ReportName 'ServiceList' -Rows $ReportRows -ClientNames $Systems -SuccessfulClients $SuccessfulClients)
            continue
        }

        # 2 = START/STOP/RESTART, 3 = STARTUP TYPE degistir.
        # Islem oncesi eski durum ve baslangic tipi manifest'e eklenir. Restart = Stop -> bekle -> Start.
        if ($Selection -eq '2' -or $Selection -eq '3') {
            $ServiceName=(Read-Host 'Servis Name').Trim()
            if([string]::IsNullOrWhiteSpace($ServiceName)){continue}
            $Action=if($Selection -eq '2'){(Read-Host 'Start/Stop/Restart').Trim().ToLowerInvariant()}else{'StartupType'}
            $NewStartMode=if($Selection -eq '3'){(Read-Host 'auto/demand/disabled').Trim().ToLowerInvariant()}else{''}
            if ($Selection -eq '3' -and $NewStartMode -notin @('auto','demand','disabled')) {
                Write-Host 'Gecersiz startup type.' -ForegroundColor Yellow
                continue
            }
            if($Action -notin @('start','stop','restart','startuptype') -and $Selection -eq '2'){
                Write-Host 'Gecersiz servis islemi.' -ForegroundColor Yellow
                continue
            }
            if((Read-Host "Devam etmek icin $(if($Selection -eq '2'){$Action.ToUpperInvariant()}else{'EDIT'}) yazin").Trim().ToUpperInvariant() -notin @($Action.ToUpperInvariant(),'EDIT')){
                continue
            }
            $ManifestRows=@()
            $ReportRows=@()
            $SuccessfulClients=@()
            $ReportAction=if($Selection -eq '3'){'StartupType'}else{$Action}
            foreach($ComputerName in $ReachableSystems){
                $Session=$null
                $OldState=''
                $OldStartMode=''
                try{
                    $Session=Get-ServiceTaskSession $ComputerName
                    $Service=Get-CimInstance -CimSession $Session -ClassName Win32_Service -Filter ("Name='{0}'" -f ($ServiceName -replace "'","''")) -ErrorAction Stop
                    if($null -eq $Service){throw "Servis bulunamadi: $ServiceName"}
                    $OldState=[string]$Service.State
                    $OldStartMode=[string]$Service.StartMode
                    $ManifestEntry=New-ServiceTaskObject @{ComputerName=$ComputerName;ObjectType='Service';ObjectName=$ServiceName;Action=$(if($Selection -eq '2'){'StartStop'}else{'StartupType'});OldState=$Service.State;OldStartMode=$Service.StartMode;NewStartMode=$NewStartMode;OperationID=$OperationID}
                    $CandidateRows=@($ManifestRows)+@($ManifestEntry)
                    $ManifestPath=Join-Path $RollbackRoot ("{0}_Services.csv" -f $OperationID)
                    Write-ServiceTaskManifest -Path $ManifestPath -Rows $CandidateRows
                    $ManifestRows=$CandidateRows
                    if($Selection -eq '3'){
                        Set-ServiceTaskStartMode -Session $Session -Service $Service -Mode $NewStartMode|Out-Null
                    }
                    elseif($Action -eq 'start'){
                        [void](Invoke-ServiceTaskMethodChecked -Session $Session -Service $Service -Method StartService -Accepted @(0,10))
                    }
                    elseif($Action -eq 'stop'){
                        [void](Invoke-ServiceTaskMethodChecked -Session $Session -Service $Service -Method StopService -Accepted @(0,6))
                    }
                    else{
                        [void](Invoke-ServiceTaskMethodChecked -Session $Session -Service $Service -Method StopService -Accepted @(0,6))
                        $Stopped=Wait-ServiceTaskState -Session $Session -ServiceName $ServiceName -State 'Stopped'
                        [void](Invoke-ServiceTaskMethodChecked -Session $Session -Service $Stopped -Method StartService -Accepted @(0,10))
                    }
                    $SuccessfulClients+=$ComputerName
                    $ReportRows+=[PSCustomObject]@{ComputerName=$ComputerName;ServiceName=$ServiceName;Action=$ReportAction;OldState=$OldState;OldStartMode=$OldStartMode;NewStartMode=$NewStartMode;Status='Success';ErrorDetail=''}
                    Write-Host "$ComputerName : SERVIS OK | $ServiceName" -ForegroundColor Green
                }
                catch{
                    $ReportRows+=[PSCustomObject]@{ComputerName=$ComputerName;ServiceName=$ServiceName;Action=$ReportAction;OldState=$OldState;OldStartMode=$OldStartMode;NewStartMode=$NewStartMode;Status='Failed';ErrorDetail=$_.Exception.Message}
                    Write-Host "$ComputerName : HATA | $($_.Exception.Message)" -ForegroundColor Red
                }
                finally{if($null -ne $Session){Remove-CimSession -CimSession $Session -ErrorAction SilentlyContinue}}
            }
            if($ManifestRows.Count -gt 0){
                $ManifestPath=Join-Path $RollbackRoot ("{0}_Services.csv" -f $OperationID)
                Write-Host "Rollback manifest: $ManifestPath" -ForegroundColor Cyan
            }
            [void](Write-ServiceTaskReport -BasePath $BasePath -OperationID $OperationID -ReportName $(if($Selection -eq '3'){'ServiceStartup'}else{'ServiceControl'}) -Rows $ReportRows -ClientNames $Systems -SuccessfulClients $SuccessfulClients)
            continue
        }

        # 4 = SCHEDULED TASK LISTELE (ad filtresi; bos = tumu).
        if ($Selection -eq '4') {
            $TaskNameFilter=(Read-Host 'Task adi filtresi (bos=tumu)').Trim()
            $ReportRows = @()
            $SuccessfulClients = @()
            foreach($ComputerName in $ReachableSystems){
                try{
                    $Session=Get-ServiceTaskSession $ComputerName
                    try{
                        $Tasks=@(Get-CimInstance -CimSession $Session -Namespace 'root\Microsoft\Windows\TaskScheduler' -ClassName MSFT_ScheduledTask -ErrorAction Stop)
                        $SuccessfulClients += $ComputerName
                        if(-not [string]::IsNullOrWhiteSpace($TaskNameFilter)){
                            $Tasks=@($Tasks|Where-Object{$_.TaskName.IndexOf($TaskNameFilter,[System.StringComparison]::OrdinalIgnoreCase)-ge 0})
                        }
                        if(@($Tasks).Count -eq 0){
                            $ReportRows += [PSCustomObject]@{ComputerName=$ComputerName;TaskName='';TaskPath='';State='';Enabled='';Status='NotFound';ErrorDetail='No matching task.'}
                        }
                        foreach($Task in $Tasks){
                            $ReportRows += [PSCustomObject]@{ComputerName=$ComputerName;TaskName=$Task.TaskName;TaskPath=$Task.TaskPath;State=$Task.State;Enabled=$Task.Settings.Enabled;Status='Success';ErrorDetail=''}
                            Write-Host "$ComputerName : $($Task.TaskPath)$($Task.TaskName) | State=$($Task.State) | Enabled=$($Task.Settings.Enabled)"
                        }
                    }finally{
                        Remove-CimSession -CimSession $Session -ErrorAction SilentlyContinue
                    }
                }catch{
                    $ReportRows += [PSCustomObject]@{ComputerName=$ComputerName;TaskName='';TaskPath='';State='';Enabled='';Status='Failed';ErrorDetail=$_.Exception.Message}
                    Write-Host "$ComputerName : HATA | $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            [void](Write-ServiceTaskReport -BasePath $BasePath -OperationID $OperationID -ReportName 'ScheduledTaskList' -Rows $ReportRows -ClientNames $Systems -SuccessfulClients $SuccessfulClients)
            continue
        }

        # 5 = TASK CALISTIR, 6 = ENABLE/DISABLE (konsol yolu). Ayni adla birden fazla klasorde task varsa reddedilir.
        if ($Selection -eq '5' -or $Selection -eq '6') {
            $TaskName=(Read-Host 'Task name').Trim()
            if([string]::IsNullOrWhiteSpace($TaskName)){
                Write-Host 'Task name bos olamaz.' -ForegroundColor Yellow
                continue
            }
            $Action=if($Selection -eq '5'){'Run'}else{(Read-Host 'Enable/Disable').Trim().ToLowerInvariant()}
            if($Action -notin @('run','enable','disable')){
                Write-Host 'Gecersiz task islemi.' -ForegroundColor Yellow
                continue
            }
            if((Read-Host "Devam etmek icin $($Action.ToUpperInvariant()) yazin").Trim().ToUpperInvariant() -ne $Action.ToUpperInvariant()){
                continue
            }
            foreach($ComputerName in $ReachableSystems){
                try{
                    $Session=Get-ServiceTaskSession $ComputerName
                    try{
                        $MatchingTasks=@(Get-CimInstance -CimSession $Session -Namespace 'root\Microsoft\Windows\TaskScheduler' -ClassName MSFT_ScheduledTask -ErrorAction Stop|Where-Object{$_.TaskName -eq $TaskName})
                        if($MatchingTasks.Count -eq 0){
                            throw "Task bulunamadi: $TaskName"
                        }
                        if($MatchingTasks.Count -gt 1){
                            $Paths=($MatchingTasks|ForEach-Object{$_.TaskPath})-join ', '
                            throw "Ayni isimde birden fazla task bulundu: $TaskName ($Paths)"
                        }
                        $TaskPath=$MatchingTasks[0].TaskPath
                        if($Action -eq 'run'){
                            Start-ScheduledTask -CimSession $Session -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop
                        }else{
                            if($Action -eq 'enable'){
                                Enable-ScheduledTask -CimSession $Session -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop
                            }else{
                                Disable-ScheduledTask -CimSession $Session -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop
                            }
                        }
                        Write-Host "$ComputerName : TASK OK | $TaskPath$TaskName" -ForegroundColor Green
                    }finally{
                        Remove-CimSession -CimSession $Session -ErrorAction SilentlyContinue
                    }
                }catch{
                    Write-Host "$ComputerName : HATA | $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            continue
        }
        Write-Host 'Gecersiz secim.' -ForegroundColor Yellow
    }
}

# Modul kaydi: dosya dot-source edildiginde kendini host'a tanitir.
Register-AOModule `
    -Name 'ServiceTaskOperations' `
    -Version '1.0' `
    -MinimumHostApiVersion '1.0' `
    -SourcePath $PSCommandPath

Register-AOModuleOperation `
    -ModuleName 'ServiceTaskOperations' `
    -Name 'ServiceTaskOperations' `
    -DisplayName 'Service ve Task Operations' `
    -EntryPointName 'Invoke-ServiceTaskOperationsMenu' `
    -Handler ${function:Invoke-ServiceTaskOperationsMenu}
