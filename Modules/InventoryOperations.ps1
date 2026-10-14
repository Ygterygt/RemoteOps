<#
AO Inventory Operations module.
Collects deployment-oriented endpoint inventory through CIM/DCOM.
This module only defines functions and registers its operation when loaded.
#>

# ====================================================================
# NASIL CALISIR (ozet)
# - GUI -> Runner -> Invoke-AOInventoryOperations @Common (hedef basina bir kez)
# - Her hedefe CIM/DCOM oturumu acilir; WMI siniflarindan OS, donanim, disk,
#   ag ve registry'den reboot-bekliyor / imaj tarihi bilgisi okunur.
# - Cikti: Logs\Inventory\<ID>_EndpointInventory.html + ayni adli .csv
#   (Runner sonuc satirlarini bu CSV'den okur).
# ====================================================================
Set-StrictMode -Version 2.0

# CIM tarih degerini 'yyyy-MM-dd HH:mm:ss' metnine cevirir; cevrilemezse oldugu gibi dondurur.
function ConvertTo-AOInventoryDate {
    param($Value)
    if ($null -eq $Value) { return '' }
    try { return ([datetime]$Value).ToString('yyyy-MM-dd HH:mm:ss') } catch { return [string]$Value }
}

# --- Uzak registry yardimcilari (StdRegProv, HKLM = 2147483650) ---
# HKLM altindan string deger okur; yoksa/okunamazsa bos metin.
function Get-AOInventoryRegistryValue {
    param($Session, [string]$SubKeyName, [string]$ValueName)
    try {
        $Result = Invoke-CimMethod -CimSession $Session -Namespace 'root\default' -ClassName StdRegProv -MethodName GetStringValue -Arguments @{
            hDefKey = [uint32]2147483650
            sSubKeyName = $SubKeyName
            sValueName = $ValueName
        } -ErrorAction Stop
        if ([uint32]$Result.ReturnValue -eq 0) { return [string]$Result.sValue }
    } catch { }
    return ''
}

# Anahtar var mi? (EnumKey ReturnValue 0 ise var)
function Test-AOInventoryRegistryKey {
    param($Session, [string]$SubKeyName)
    try {
        $Result = Invoke-CimMethod -CimSession $Session -Namespace 'root\default' -ClassName StdRegProv -MethodName EnumKey -Arguments @{
            hDefKey = [uint32]2147483650
            sSubKeyName = $SubKeyName
        } -ErrorAction Stop
        return ([uint32]$Result.ReturnValue -eq 0)
    } catch { return $false }
}

# HKLM altindan DWORD deger okur; yoksa $null.
function Get-AOInventoryRegistryDword {
    param($Session, [string]$SubKeyName, [string]$ValueName)
    try {
        $Result = Invoke-CimMethod -CimSession $Session -Namespace 'root\default' -ClassName StdRegProv -MethodName GetDWORDValue -Arguments @{
            hDefKey = [uint32]2147483650
            sSubKeyName = $SubKeyName
            sValueName = $ValueName
        } -ErrorAction Stop
        if ([uint32]$Result.ReturnValue -eq 0) { return [uint32]$Result.uValue }
    } catch { }
    return $null
}

# Toplanan satirlari basit, filtrelenebilir bir HTML tablo olarak yazar.
function Write-AOInventoryHtmlReport {
    param([string]$Path, [object[]]$Rows, [string]$OperationID)
    $SuccessCount = @($Rows | Where-Object { $_.CollectionStatus -eq 'Success' }).Count
    $FailedCount = @($Rows | Where-Object { $_.CollectionStatus -eq 'Failed' }).Count
    $UnreachableCount = @($Rows | Where-Object { $_.CollectionStatus -eq 'Unreachable' }).Count
    $Headers = @($Rows | ForEach-Object { $_.PSObject.Properties.Name } | Select-Object -Unique)
    $HeaderHtml = '<tr>' + (($Headers | ForEach-Object { '<th>' + $_ + '</th>' }) -join '') + '</tr>'
    $BodyHtml = @($Rows | Sort-Object ComputerName | ForEach-Object {
        $Row = $_
        '<tr>' + (($Headers | ForEach-Object { $Property = $Row.PSObject.Properties[$_]; $Value = if ($null -ne $Property) { [string]$Property.Value } else { '' }; '<td>' + $Value.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;') + '</td>' }) -join '') + '</tr>'
    }) -join "`n"
    $Style = '<style>body{font-family:Segoe UI,Arial;background:#f4f6f8;color:#20252b;margin:24px}h1{color:#163a5f}.meta{color:#667085}.summary{display:flex;gap:12px;margin:18px 0}.card{background:white;border:1px solid #d9e1e8;border-radius:6px;padding:12px 18px}.label{display:block;color:#667085;font-size:12px}.value{font-size:24px;font-weight:600}table{border-collapse:collapse;background:white;width:100%;font-size:12px}th{background:#163a5f;color:white;text-align:left;padding:8px}td{border:1px solid #d9e1e8;padding:7px;vertical-align:top}tr:nth-child(even){background:#f8fafc}</style>'
    $Summary = "<div class='summary'><div class='card'><span class='label'>Toplam</span><span class='value'>$(@($Rows).Count)</span></div><div class='card'><span class='label'>Basarili</span><span class='value'>$SuccessCount</span></div><div class='card'><span class='label'>Basarisiz</span><span class='value'>$FailedCount</span></div><div class='card'><span class='label'>Erisilemedi</span><span class='value'>$UnreachableCount</span></div></div>"
    $Html = "<!DOCTYPE html><html><head><meta charset='utf-8'><title>Endpoint Inventory</title>$Style</head><body><h1>Endpoint Inventory</h1><div class='meta'>OperationID: $OperationID | Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>$Summary<table><thead>$HeaderHtml</thead><tbody>$BodyHtml</tbody></table></body></html>"
    Set-Content -LiteralPath $Path -Value $Html -Encoding UTF8 -ErrorAction Stop
}

# ====================================================================
# OPERASYON GIRIS NOKTASI (Runner ve MD_Script modul menusu bunu cagirir)
# Parametreler tum modullerde ortaktir: BasePath, Systems, Reachable/UnreachableSystems,
# OperationID, OperationDate/Time, TechnicalLogWriter, OperationHistoryWriter.
# ====================================================================
function Invoke-AOInventoryOperations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string[]]$Systems,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$ReachableSystems,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$UnreachableSystems,
        [Parameter(Mandatory = $true)][string]$OperationID,
        [Parameter(Mandatory = $true)][string]$OperationDate,
        [Parameter(Mandatory = $true)][string]$OperationTime,
        [scriptblock]$TechnicalLogWriter,
        [scriptblock]$OperationHistoryWriter
    )

    $InventoryPath = Join-Path (Join-Path $BasePath 'Logs') 'Inventory'
    New-Item -ItemType Directory -Path $InventoryPath -Force | Out-Null
    $ResultHtml = Join-Path $InventoryPath ('{0}_EndpointInventory.html' -f $OperationID)
    $Rows = @()

    # Erisilemeyen hedef icin 'Unreachable' satiri; digerlerinde CIM ile veri toplanir.
    foreach ($ComputerName in $Systems) {
        if ($ReachableSystems -notcontains $ComputerName) {
            $Rows += [PSCustomObject]@{
                OperationID=$OperationID; OperationDate=$OperationDate; OperationTime=$OperationTime
                ComputerName=$ComputerName; CollectionStatus='Unreachable'; ErrorDetail='Ping basarisiz.'
            }
            continue
        }

        $Session = $null
        try {
            & $TechnicalLogWriter -Level 'INFO' -Message "INVENTORY-START | OperationID='$OperationID' | PC='$ComputerName'"
            $Session = New-CimSession -ComputerName $ComputerName -SessionOption (New-CimSessionOption -Protocol Dcom) -OperationTimeoutSec 15 -ErrorAction Stop

            # WMI siniflari: OS zorunlu (hata = Failed), digerleri okunamazsa bos gecer.
            $OS = Get-CimInstance -CimSession $Session -ClassName Win32_OperatingSystem -ErrorAction Stop
            $Computer = Get-CimInstance -CimSession $Session -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
            $BIOS = Get-CimInstance -CimSession $Session -ClassName Win32_BIOS -ErrorAction SilentlyContinue
            $BaseBoard = Get-CimInstance -CimSession $Session -ClassName Win32_BaseBoard -ErrorAction SilentlyContinue | Select-Object -First 1
            $CPU = Get-CimInstance -CimSession $Session -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
            $MemoryModules = @(Get-CimInstance -CimSession $Session -ClassName Win32_PhysicalMemory -ErrorAction SilentlyContinue)
            $LogicalDisks = @(Get-CimInstance -CimSession $Session -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue)
            $Network = @(Get-CimInstance -CimSession $Session -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction SilentlyContinue)

            # Ozet alanlar: toplam RAM, disk bos/toplam, IPv4 ve MAC listeleri.
            $MemoryBytes = [int64]0
            foreach ($MemoryModule in $MemoryModules) { $MemoryBytes += [int64]$MemoryModule.Capacity }
            $DiskSummary = @($LogicalDisks | ForEach-Object { "{0}: {1}/{2} GB" -f $_.DeviceID, [math]::Round(([double]$_.FreeSpace / 1GB), 1), [math]::Round(([double]$_.Size / 1GB), 1) }) -join ' | '
            $IPSummary = @($Network | ForEach-Object { @($_.IPAddress) | Where-Object { $_ -notmatch ':' } }) -join ', '
            $MACSummary = @($Network | ForEach-Object { $_.MACAddress }) -join ', '

            # Reboot bekliyor mu? (CBS RebootPending veya WindowsUpdate RebootRequired anahtari)
            # Imaj tarihi: InstallDate (Unix epoch saniye) degerinden hesaplanir.
            $PendingReboot = @(
                'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
                'SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
            ) | Where-Object { Test-AOInventoryRegistryKey -Session $Session -SubKeyName $_ } | Select-Object -First 1
            $ImageInstallSeconds = Get-AOInventoryRegistryDword -Session $Session -SubKeyName 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ValueName 'InstallDate'
            $ImageDate = if ($null -ne $ImageInstallSeconds) { ([datetime]'1970-01-01').AddSeconds([double]$ImageInstallSeconds).ToString('yyyy-MM-dd HH:mm:ss') } else { '' }

            # Basarili hedef icin envanter satiri.
            $Rows += [PSCustomObject]@{
                OperationID=$OperationID; OperationDate=$OperationDate; OperationTime=$OperationTime
                ComputerName=$ComputerName; CollectionStatus='Success'; ErrorDetail=''
                HostName=[string]$OS.CSName; Caption=[string]$OS.Caption; Version=[string]$OS.Version; BuildNumber=[string]$OS.BuildNumber
                Architecture=[string]$OS.OSArchitecture; SerialNumber=[string]$BIOS.SerialNumber
                Manufacturer=[string]$Computer.Manufacturer; Model=[string]$Computer.Model
                Domain=[string]$Computer.Domain; LoggedOnUser=[string]$Computer.UserName
                BIOSVersion=(@($BIOS.SMBIOSBIOSVersion) -join ', '); BIOSReleaseDate=(ConvertTo-AOInventoryDate $BIOS.ReleaseDate)
                BaseBoardManufacturer=[string]$BaseBoard.Manufacturer; BaseBoardProduct=[string]$BaseBoard.Product
                Processor=[string]$CPU.Name; LogicalProcessors=[int]$Computer.NumberOfLogicalProcessors
                PhysicalMemoryGB=[math]::Round(([double]$MemoryBytes / 1GB), 2)
                LastBootTime=(ConvertTo-AOInventoryDate $OS.LastBootUpTime); WindowsInstallDate=(ConvertTo-AOInventoryDate $OS.InstallDate)
                WindowsImageDate=$ImageDate
                PendingReboot=$(if ([string]::IsNullOrWhiteSpace([string]$PendingReboot)) { 'No' } else { 'Yes' })
                IPAddresses=$IPSummary; MACAddresses=$MACSummary; DiskSummary=$DiskSummary
                CollectionTime=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            }
            & $TechnicalLogWriter -Level 'INFO' -Message "INVENTORY-END | OperationID='$OperationID' | PC='$ComputerName' | Status=Success"
        }
        catch {
            $Rows += [PSCustomObject]@{
                OperationID=$OperationID; OperationDate=$OperationDate; OperationTime=$OperationTime
                ComputerName=$ComputerName; CollectionStatus='Failed'; ErrorDetail=$_.Exception.Message
            }
            & $TechnicalLogWriter -Level 'ERROR' -Message "INVENTORY-ERROR | OperationID='$OperationID' | PC='$ComputerName' | $($_.Exception.Message)"
        }
        finally {
            if ($null -ne $Session) { Remove-CimSession -CimSession $Session -ErrorAction SilentlyContinue }
        }
    }

    # Rapor + CSV yaz, her hedef icin operasyon gecmisine kayit at.
    Write-AOInventoryHtmlReport -Path $ResultHtml -Rows $Rows -OperationID $OperationID
    # structured copy next to the HTML so callers (GUI runner, reports) can read per-computer results
    $ResultCsv = [System.IO.Path]::ChangeExtension($ResultHtml, '.csv')
    $CsvHeaders = @($Rows | ForEach-Object { $_.PSObject.Properties.Name } | Select-Object -Unique)
    if ($Rows.Count -gt 0) {
        $Rows | Select-Object $CsvHeaders | Export-Csv -LiteralPath $ResultCsv -NoTypeInformation -Encoding UTF8 -Delimiter ';' -ErrorAction Stop
    }
    foreach ($Row in $Rows) {
        if ($null -ne $OperationHistoryWriter) {
            & $OperationHistoryWriter -OperationID $OperationID -OperationDate $OperationDate -OperationTime $OperationTime -IstemciAdi $Row.ComputerName -Modul 'Inventory' -Operasyon 'EndpointInventory' -Sonuc $Row.CollectionStatus -Aciklama $Row.ErrorDetail
        }
    }

    return [PSCustomObject]@{ Completed=$true; ResultCsv=$ResultHtml; Message="Inventory HTML tamamlandi. Kayit=$($Rows.Count)" }
}

# Modul kaydi: dosya dot-source edildiginde kendini host'a (MD_Script veya Runner) tanitir.
Register-AOModule `
    -Name 'InventoryOperations' `
    -Version '1.0' `
    -MinimumHostApiVersion '1.0' `
    -SourcePath $PSCommandPath

Register-AOModuleOperation `
    -ModuleName 'InventoryOperations' `
    -Name 'EndpointInventory' `
    -DisplayName 'Endpoint Inventory / Donanim ve OS Bilgileri' `
    -EntryPointName 'Invoke-AOInventoryOperations' `
    -Handler ${function:Invoke-AOInventoryOperations}
