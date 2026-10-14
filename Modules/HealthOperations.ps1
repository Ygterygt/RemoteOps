<#
AO Health Operations module.
Collects a detailed per-computer health snapshot through CIM/DCOM and the administrative C$ share,
and writes ONE interactive HTML report for the whole target list.
The module only defines functions and registers its operation when loaded.
#>

# ====================================================================
# NASIL CALISIR (ozet)
# 1) Invoke-AOHealthCheck (giris noktasi) her hedef icin:
#    Get-AOHealthSnapshot     -> uzak veri toplama (CIM/DCOM + uzak registry + C$ paylasimi)
#    ConvertTo-AOHealthEvaluation -> esik degerlerine gore uyari/kritik bulgu (uzak cagri YOK)
#    ConvertTo-AOHealthDetail -> HTML rapor icin JSON dostu kayit ($script:AOHealthDetails'e eklenir)
# 2) Hedef basina ozet satir Logs\Health\<ID>_HealthCheck.csv'ye yazilir.
# 3) Runner calisma sonunda Write-AOHealthHtmlReport ile TUM liste icin tek Health.html uretir.
# Bir alt kalem (BIOS, disk, yama...) okunamazsa tum hedef basarisiz sayilmaz;
# hata "Toplama notlari" olarak rapora eklenir.
# ====================================================================
#
# AOHealthDetails : HTML rapor icin biriken hedef detaylari (paralel calismada worker'lardan birlestirilir)
# AOHealthThresholds: uyari/kritik esikleri (disk %, RAM %, CPU %, gun sayilari) - gerekirse buradan ayarlanir
Set-StrictMode -Version 2.0

$script:AOHealthDetails = New-Object System.Collections.ArrayList
$script:AOHealthThresholds = @{ DiskWarnPercent = 90; DiskCriticalPercent = 95; RamWarnPercent = 90; CpuWarnPercent = 90; UptimeWarnDays = 30; SccmLogWarnDays = 14; PatchWarnDays = 60; CcmCacheWarnDays = 180 }

# Tarihi kulturden bagimsiz metne cevirir; gecersizse bos metin.
function Format-AOHealthDate {
    param($Value, [string]$Format = 'yyyy-MM-dd HH:mm')
    if ($null -eq $Value) { return '' }
    try {
        return ([datetime]$Value).ToString($Format, [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        return ''
    }
}

# Farkli kaynaklardan gelen tarih metinlerini [datetime]'a cevirir; cevrilemezse $null.
function ConvertTo-AOHealthDate {
    # Tolerates CIM datetimes, yyyyMMdd, locale dates and the hex FILETIME that Win32_QuickFixEngineering sometimes returns.
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value }
    $Text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $Parsed = [datetime]::MinValue
    if ($Text -match '^\d{8}$' -and [datetime]::TryParseExact($Text, 'yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$Parsed)) {
        return $Parsed
    }
    if ($Text -match '^0x[0-9A-Fa-f]+$') {
        try {
            return [datetime]::FromFileTime([Convert]::ToInt64($Text.Substring(2), 16))
        } catch {
            return $null
        }
    }
    if ([datetime]::TryParse($Text, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$Parsed)) {
        return $Parsed
    }
    if ([datetime]::TryParse($Text, [System.Globalization.CultureInfo]::GetCultureInfo('tr-TR'), [System.Globalization.DateTimeStyles]::None, [ref]$Parsed)) {
        return $Parsed
    }
    return $null
}

# C:\... yolunu \\PC\C$\... yonetim paylasimi yoluna cevirir.
function ConvertTo-AOHealthAdminPath {
    param([Parameter(Mandatory = $true)][string]$ComputerName, [Parameter(Mandatory = $true)][string]$LocalPath)
    if ($LocalPath -notmatch '^(?<Drive>[A-Za-z]):\\(?<Rest>.*)$') { throw "Absolute drive path required: $LocalPath" }
    return ('\\{0}\{1}$\{2}' -f $ComputerName, $Matches['Drive'].ToUpperInvariant(), $Matches['Rest'])
}

# ---------------------------------------------------------------- registry access (System.Management, one scope per computer)
# Uzak registry baglantisi (System.Management + StdRegProv), hedef basina bir kez acilir.
function New-AOHealthRegistry {
    param([string]$ComputerName, [int]$TimeoutSeconds = 15)
    $Options = [System.Management.ConnectionOptions]::new()
    $Options.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    $Options.Impersonation = [System.Management.ImpersonationLevel]::Impersonate
    $Scope = [System.Management.ManagementScope]::new("\\$ComputerName\root\default", $Options)
    [void]$Scope.Connect()
    $Class = [System.Management.ManagementClass]::new($Scope, [System.Management.ManagementPath]::new('StdRegProv'), $null)
    $Method = [System.Management.InvokeMethodOptions]::new()
    $Method.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    return [PSCustomObject]@{ Class = $Class; Options = $Method }
}

# StdRegProv metodunu HKLM uzerinde cagirir (EnumKey/EnumValues deger adi almaz).
function Invoke-AOHealthRegistryMethod {
    param($Registry, [string]$Method, [string]$Key, [string]$ValueName = '')
    $In = $Registry.Class.GetMethodParameters($Method)
    $In['hDefKey'] = [uint32]2147483650
    $In['sSubKeyName'] = $Key
    if ($Method -ne 'EnumKey' -and $Method -ne 'EnumValues') { $In['sValueName'] = $ValueName }
    return $Registry.Class.InvokeMethod($Method, $In, $Registry.Options)
}

# Okuma yardimcilari: hata durumunda bos/varsayilan deger dondururler, istisna firlatmazlar.
function Get-AOHealthRegString {
    param($Registry, [string]$Key, [string]$ValueName)
    try {
        $Out = Invoke-AOHealthRegistryMethod -Registry $Registry -Method 'GetStringValue' -Key $Key -ValueName $ValueName
        if ($null -ne $Out -and [uint32]$Out['ReturnValue'] -eq 0 -and $null -ne $Out['sValue']) {
            return [string]$Out['sValue']
        }
    } catch { }
    return ''
}

function Get-AOHealthRegDword {
    param($Registry, [string]$Key, [string]$ValueName)
    try {
        $Out = Invoke-AOHealthRegistryMethod -Registry $Registry -Method 'GetDWORDValue' -Key $Key -ValueName $ValueName
        if ($null -ne $Out -and [uint32]$Out['ReturnValue'] -eq 0 -and $null -ne $Out['uValue']) {
            return [uint32]$Out['uValue']
        }
    } catch { }
    return $null
}

function Test-AOHealthRegKey {
    param($Registry, [string]$Key)
    try {
        $Out = Invoke-AOHealthRegistryMethod -Registry $Registry -Method 'EnumKey' -Key $Key
        return ($null -ne $Out -and [uint32]$Out['ReturnValue'] -eq 0)
    } catch { return $false }
}

function Get-AOHealthRegSubKeys {
    param($Registry, [string]$Key)
    try {
        $Out = Invoke-AOHealthRegistryMethod -Registry $Registry -Method 'EnumKey' -Key $Key
        if ($null -ne $Out -and [uint32]$Out['ReturnValue'] -eq 0 -and $null -ne $Out['sNames']) {
            return @($Out['sNames'])
        }
    } catch { }
    return @()
}

function Test-AOHealthRegValueExists {
    param($Registry, [string]$Key, [string]$ValueName)
    try {
        $Out = Invoke-AOHealthRegistryMethod -Registry $Registry -Method 'EnumValues' -Key $Key
        if ($null -ne $Out -and [uint32]$Out['ReturnValue'] -eq 0 -and $null -ne $Out['sNames']) {
            return (@($Out['sNames']) -contains $ValueName)
        }
    } catch { }
    return $false
}

# ---------------------------------------------------------------- collection
# ====================================================================
# VERI TOPLAMA (tek hedef)
# CIM oturumu acilir; OS bilgisi zorunludur (alinamazsa hedef 'Failed').
# Diger her kalem kendi try/catch'i icinde okunur ve hatalari $Errors listesine yazilir.
# ====================================================================
function Get-AOHealthSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ComputerName, [switch]$SkipApps, [int]$TimeoutSeconds = 20)

    $Errors = New-Object System.Collections.Generic.List[string]
    $Session = $null
    try {
        $Session = New-CimSession -ComputerName $ComputerName -SessionOption (New-CimSessionOption -Protocol Dcom) -OperationTimeoutSec $TimeoutSeconds -ErrorAction Stop
        $OS = Get-CimInstance -CimSession $Session -ClassName Win32_OperatingSystem -ErrorAction Stop

        # Toplanacak tum alanlarin varsayilan degerleri (rapor her zaman ayni sekle sahip olsun).
        $Snapshot = [ordered]@{
            ComputerName = $ComputerName; CollectedAt = (Get-Date)
            Manufacturer = ''; Model = ''; Serial = ''; BiosVersion = ''; BiosDate = $null
            OsCaption = [string]$OS.Caption; OsVersion = [string]$OS.Version; OsBuild = [string]$OS.BuildNumber; OsDisplayVersion = ''; OsArch = [string]$OS.OSArchitecture
            Domain = ''; LoggedOnUser = ''; CpuName = ''; CpuCores = 0
            InstallDate = $OS.InstallDate; LastBoot = $OS.LastBootUpTime
            RebootPending = $false; RebootReasons = @()
            Adapters = @(); CpuLoad = $null; MemTotalMB = 0; MemFreeMB = 0; Disks = @(); Services = @()
            SccmVersion = ''; SccmServiceState = 'Not installed'; SccmStartMode = ''
            CcmCacheExists = $false; CcmCacheLastWrite = $null; CcmCacheItems = 0; CcmCacheNewestItem = ''
            SccmLogName = ''; SccmLogLastWrite = $null; SccmLogCount = 0; CcmExecLogLastWrite = $null
            Patches = @(); Apps = @(); Errors = @()
        }
        $Snapshot.MemTotalMB = [math]::Round([double]$OS.TotalVisibleMemorySize / 1024, 0)
        $Snapshot.MemFreeMB = [math]::Round([double]$OS.FreePhysicalMemory / 1024, 0)

        try {
            $Computer = Get-CimInstance -CimSession $Session -ClassName Win32_ComputerSystem -ErrorAction Stop
            $Snapshot.Manufacturer = [string]$Computer.Manufacturer
            $Snapshot.Model = [string]$Computer.Model
            $Snapshot.Domain = [string]$Computer.Domain
            $Snapshot.LoggedOnUser = [string]$Computer.UserName
            $Snapshot.CpuCores = [int]$Computer.NumberOfLogicalProcessors
        } catch { $Errors.Add("ComputerSystem: $($_.Exception.Message)") }
        try {
            $BIOS = Get-CimInstance -CimSession $Session -ClassName Win32_BIOS -ErrorAction Stop | Select-Object -First 1
            $Snapshot.Serial = [string]$BIOS.SerialNumber
            $Snapshot.BiosVersion = [string]$BIOS.SMBIOSBIOSVersion
            $Snapshot.BiosDate = $BIOS.ReleaseDate
        } catch { $Errors.Add("BIOS: $($_.Exception.Message)") }
        try {
            $Processors = @(Get-CimInstance -CimSession $Session -ClassName Win32_Processor -ErrorAction Stop)
            if ($Processors.Count -gt 0) {
                $Snapshot.CpuName = [string]$Processors[0].Name
                $Loads = @($Processors | Where-Object { $null -ne $_.LoadPercentage } | ForEach-Object { [double]$_.LoadPercentage })
                if ($Loads.Count -gt 0) {
                    $Snapshot.CpuLoad = [math]::Round(($Loads | Measure-Object -Average).Average, 0)
                }
            }
        } catch { $Errors.Add("Processor: $($_.Exception.Message)") }
        try {
            # Yerel diskler: boyut, bos alan ve kullanim yuzdesi.
            $Snapshot.Disks = @(Get-CimInstance -CimSession $Session -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop | ForEach-Object {
                $Size = [double]$_.Size; $Free = [double]$_.FreeSpace
                [PSCustomObject]@{ Drive = [string]$_.DeviceID; Label = [string]$_.VolumeName; FileSystem = [string]$_.FileSystem; SizeGB = [math]::Round($Size / 1GB, 1); FreeGB = [math]::Round($Free / 1GB, 1); UsedPercent = $(if ($Size -gt 0) { [math]::Round(100 * ($Size - $Free) / $Size, 0) } else { 0 }) }
            })
        } catch { $Errors.Add("Disk: $($_.Exception.Message)") }
        try {
            # IP etkin ag adaptorleri: sadece IPv4 adresleri ve karsilik gelen subnet'ler alinir.
            $Snapshot.Adapters = @(Get-CimInstance -CimSession $Session -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' -ErrorAction Stop | ForEach-Object {
                $Addresses = @($_.IPAddress | Where-Object { $_ })
                $Subnets = @($_.IPSubnet | Where-Object { $_ })
                $V4 = @()
                $V4Subnets = @()
                for ($Index = 0; $Index -lt $Addresses.Count; $Index++) {
                    if ($Addresses[$Index] -notmatch ':') {
                        $V4 += [string]$Addresses[$Index]
                        if ($Index -lt $Subnets.Count) {
                            $V4Subnets += [string]$Subnets[$Index]
                        }
                    }
                }
                [PSCustomObject]@{ Name = [string]$_.Description; Mac = [string]$_.MACAddress; IPv4 = $V4; Subnet = $V4Subnets; Gateway = @($_.DefaultIPGateway | Where-Object { $_ }); Dns = @($_.DNSServerSearchOrder | Where-Object { $_ }); Dhcp = [bool]$_.DHCPEnabled }
            })
        } catch { $Errors.Add("Network: $($_.Exception.Message)") }
        try {
            # Izlenen kritik servisler; CcmExec durumu SCCM istemci sagligi icin ayrica tutulur.
            $ServiceNames = @('CcmExec', 'wuauserv', 'BITS', 'WinRM', 'WinDefend', 'mpssvc')
            $Services = @(Get-CimInstance -CimSession $Session -ClassName Win32_Service -ErrorAction Stop | Where-Object { $ServiceNames -contains $_.Name })
            $Snapshot.Services = @($Services | Sort-Object Name | ForEach-Object { [PSCustomObject]@{ Name = [string]$_.Name; DisplayName = [string]$_.DisplayName; State = [string]$_.State; StartMode = [string]$_.StartMode } })
            $Ccm = @($Services | Where-Object { $_.Name -eq 'CcmExec' } | Select-Object -First 1)
            if ($Ccm.Count -gt 0) {
                $Snapshot.SccmServiceState = [string]$Ccm[0].State
                $Snapshot.SccmStartMode = [string]$Ccm[0].StartMode
            }
        } catch { $Errors.Add("Services: $($_.Exception.Message)") }
        try {
            # Yuklu yamalar (en yeni kurulan basta).
            $Snapshot.Patches = @(Get-CimInstance -CimSession $Session -ClassName Win32_QuickFixEngineering -ErrorAction Stop | ForEach-Object {
                [PSCustomObject]@{ Id = [string]$_.HotFixID; Description = [string]$_.Description; InstalledOn = (ConvertTo-AOHealthDate $_.InstalledOn); InstalledBy = [string]$_.InstalledBy }
            } | Sort-Object @{ Expression = { if ($null -eq $_.InstalledOn) { [datetime]::MinValue } else { $_.InstalledOn } }; Descending = $true } | Select-Object -First 15)
        } catch { $Errors.Add("Patches: $($_.Exception.Message)") }

        # registry based items
        $Registry = $null
        try {
            $Registry = New-AOHealthRegistry -ComputerName $ComputerName -TimeoutSeconds $TimeoutSeconds
        } catch {
            $Errors.Add("Registry: $($_.Exception.Message)")
        }
        if ($null -ne $Registry) {
            # Reboot bekliyor mu? Kontrol edilen kaynaklar: CBS, Windows Update, bekleyen dosya
            # yeniden adlandirma, bilgisayar adi degisikligi ve SCCM ClientSDK.
            $Reasons = New-Object System.Collections.Generic.List[string]
            if (Test-AOHealthRegKey -Registry $Registry -Key 'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
                $Reasons.Add('Component Based Servicing')
            }
            if (Test-AOHealthRegKey -Registry $Registry -Key 'SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
                $Reasons.Add('Windows Update')
            }
            if (Test-AOHealthRegValueExists -Registry $Registry -Key 'SYSTEM\CurrentControlSet\Control\Session Manager' -ValueName 'PendingFileRenameOperations') {
                $Reasons.Add('Pending file rename')
            }
            $ActiveName = Get-AOHealthRegString -Registry $Registry -Key 'SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -ValueName 'ComputerName'
            $PendingName = Get-AOHealthRegString -Registry $Registry -Key 'SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -ValueName 'ComputerName'
            if ($ActiveName -and $PendingName -and $ActiveName -ne $PendingName) { $Reasons.Add('Computer rename') }
            try {
                $Sdk = Invoke-CimMethod -CimSession $Session -Namespace 'root\ccm\ClientSDK' -ClassName CCM_ClientUtilities -MethodName DetermineIfRebootPending -ErrorAction Stop
                if ([bool]$Sdk.RebootPending -or [bool]$Sdk.IsHardRebootPending) { $Reasons.Add('SCCM client') }
            } catch { }
            $Snapshot.RebootReasons = @($Reasons.ToArray())
            $Snapshot.RebootPending = ($Reasons.Count -gt 0)
            $Current = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion'
            # Windows build (UBR ile tam surum), surum adi (22H2 vb.) ve SCCM istemci surumu.
            $Ubr = Get-AOHealthRegDword -Registry $Registry -Key $Current -ValueName 'UBR'
            if ($null -ne $Ubr) { $Snapshot.OsBuild = '{0}.{1}' -f $OS.BuildNumber, $Ubr }
            $DisplayVersion = Get-AOHealthRegString -Registry $Registry -Key $Current -ValueName 'DisplayVersion'
            if (-not $DisplayVersion) {
                $DisplayVersion = Get-AOHealthRegString -Registry $Registry -Key $Current -ValueName 'ReleaseId'
            }
            $Snapshot.OsDisplayVersion = $DisplayVersion
            $Snapshot.SccmVersion = Get-AOHealthRegString -Registry $Registry -Key 'SOFTWARE\Microsoft\SMS\Mobile Client' -ValueName 'ProductVersion'

            # Son kurulan uygulamalar (InstallDate'i olanlar, en yeni 15). En fazla 90 sn taranir.
            # "Skip application scan" secilirse bu adim atlanir (hizli mod).
            if (-not $SkipApps) {
                try {
                    $Watch = [System.Diagnostics.Stopwatch]::StartNew()
                    $Found = New-Object System.Collections.Generic.List[object]
                    foreach ($Root in @('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
                        foreach ($SubKey in (Get-AOHealthRegSubKeys -Registry $Registry -Key $Root)) {
                            if ($Watch.Elapsed.TotalSeconds -gt 90) {
                                $Errors.Add('Applications: scan stopped after 90 seconds, list may be incomplete.')
                                break
                            }
                            $Key = "$Root\$SubKey"
                            $InstallDate = ConvertTo-AOHealthDate (Get-AOHealthRegString -Registry $Registry -Key $Key -ValueName 'InstallDate')
                            if ($null -eq $InstallDate) { continue }
                            $Name = Get-AOHealthRegString -Registry $Registry -Key $Key -ValueName 'DisplayName'
                            if ([string]::IsNullOrWhiteSpace($Name)) { continue }
                            $Found.Add([PSCustomObject]@{ Name = $Name; Version = (Get-AOHealthRegString -Registry $Registry -Key $Key -ValueName 'DisplayVersion'); InstalledOn = $InstallDate })
                        }
                    }
                    $Snapshot.Apps = @($Found.ToArray() | Sort-Object InstalledOn -Descending | Select-Object -First 15)
                } catch { $Errors.Add("Applications: $($_.Exception.Message)") }
            }
        }

        # file system items through the administrative share
        try {
            # ccmcache klasoru: var mi, son degisiklik zamani, oge sayisi.
            $CachePath = ConvertTo-AOHealthAdminPath -ComputerName $ComputerName -LocalPath 'C:\Windows\ccmcache'
            if (Test-Path -LiteralPath $CachePath -PathType Container) {
                $Snapshot.CcmCacheExists = $true
                $Snapshot.CcmCacheLastWrite = (Get-Item -LiteralPath $CachePath -Force).LastWriteTime
                $Items = @(Get-ChildItem -LiteralPath $CachePath -Force -ErrorAction SilentlyContinue)
                $Snapshot.CcmCacheItems = $Items.Count
                $Newest = @($Items | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
                if ($Newest.Count -gt 0) {
                    $Snapshot.CcmCacheNewestItem = [string]$Newest[0].Name
                    if ($Newest[0].LastWriteTime -gt $Snapshot.CcmCacheLastWrite) {
                        $Snapshot.CcmCacheLastWrite = $Newest[0].LastWriteTime
                    }
                }
            }
        } catch { $Errors.Add("ccmcache: $($_.Exception.Message)") }
        try {
            # C:\Windows\Temp\SCCM* paket loglari: en yenisinin adi ve zamani.
            $TempPath = ConvertTo-AOHealthAdminPath -ComputerName $ComputerName -LocalPath 'C:\Windows\Temp'
            $Logs = @(Get-ChildItem -LiteralPath $TempPath -File -Filter 'SCCM*' -Force -ErrorAction Stop | Sort-Object LastWriteTime -Descending)
            $Snapshot.SccmLogCount = $Logs.Count
            if ($Logs.Count -gt 0) {
                $Snapshot.SccmLogName = [string]$Logs[0].Name
                $Snapshot.SccmLogLastWrite = $Logs[0].LastWriteTime
            }
        } catch { $Errors.Add("Windows\Temp: $($_.Exception.Message)") }
        try {
            $CcmLog = ConvertTo-AOHealthAdminPath -ComputerName $ComputerName -LocalPath 'C:\Windows\CCM\Logs\CcmExec.log'
            if (Test-Path -LiteralPath $CcmLog -PathType Leaf) {
                $Snapshot.CcmExecLogLastWrite = (Get-Item -LiteralPath $CcmLog -Force).LastWriteTime
            }
        } catch { }

        $Snapshot.Errors = @($Errors.ToArray())
        return [PSCustomObject]$Snapshot
    }
    finally { if ($null -ne $Session) { Remove-CimSession -CimSession $Session -ErrorAction SilentlyContinue } }
}

# ---------------------------------------------------------------- evaluation (pure, no remote calls)
# ====================================================================
# DEGERLENDIRME (saf fonksiyon - uzak cagri yapmaz, test edilebilir)
# Esiklere gore Warning/Critical/Info bulgulari uretir ve genel durumu belirler:
#   herhangi bir Critical -> Critical, herhangi bir Warning -> Warning, aksi halde Healthy.
# Ayrica CSV'ye yazilacak hedef ozet satirini (Summary) hazirlar.
# ====================================================================
function ConvertTo-AOHealthEvaluation {
    param([Parameter(Mandatory = $true)]$Snapshot, [datetime]$Now = (Get-Date))
    $Limits = $script:AOHealthThresholds
    $Warnings = New-Object System.Collections.Generic.List[object]
    function Add-Finding {
        param([string]$Level, [string]$Text)
        $Warnings.Add([PSCustomObject]@{ Level = $Level; Text = $Text })
    }

    $UptimeDays = $null
    if ($null -ne $Snapshot.LastBoot) {
        $UptimeDays = [math]::Round(($Now - [datetime]$Snapshot.LastBoot).TotalDays, 1)
    }
    if ($Snapshot.RebootPending) {
        Add-Finding 'Warning' ('Reboot pending: ' + (@($Snapshot.RebootReasons) -join ', '))
    }
    if ($null -ne $UptimeDays -and $UptimeDays -gt $Limits.UptimeWarnDays) {
        Add-Finding 'Warning' ("No reboot for $([math]::Floor($UptimeDays)) days")
    }

    foreach ($Disk in @($Snapshot.Disks)) {
        if ($Disk.UsedPercent -ge $Limits.DiskCriticalPercent) {
            Add-Finding 'Critical' ("Disk $($Disk.Drive) is $($Disk.UsedPercent)% full ($($Disk.FreeGB) GB free)")
        }
        elseif ($Disk.UsedPercent -ge $Limits.DiskWarnPercent) {
            Add-Finding 'Warning' ("Disk $($Disk.Drive) is $($Disk.UsedPercent)% full ($($Disk.FreeGB) GB free)")
        }
    }
    $RamPercent = $null
    if ([double]$Snapshot.MemTotalMB -gt 0) {
        $RamPercent = [math]::Round(100 * ([double]$Snapshot.MemTotalMB - [double]$Snapshot.MemFreeMB) / [double]$Snapshot.MemTotalMB, 0)
    }
    if ($null -ne $RamPercent -and $RamPercent -ge $Limits.RamWarnPercent) {
        Add-Finding 'Warning' "Memory usage is $RamPercent%"
    }
    if ($null -ne $Snapshot.CpuLoad -and [double]$Snapshot.CpuLoad -ge $Limits.CpuWarnPercent) {
        Add-Finding 'Warning' "CPU load is $($Snapshot.CpuLoad)%"
    }

    if ($Snapshot.SccmServiceState -eq 'Not installed') {
        Add-Finding 'Critical' 'SCCM client service (CcmExec) not found'
    }
    elseif ($Snapshot.SccmServiceState -ne 'Running') {
        Add-Finding 'Critical' "SCCM client service (CcmExec) is $($Snapshot.SccmServiceState)"
    }
    if ($Snapshot.SccmServiceState -ne 'Not installed') {
        if (-not $Snapshot.CcmCacheExists) { Add-Finding 'Warning' 'C:\Windows\ccmcache folder not found' }
        elseif ($null -ne $Snapshot.CcmCacheLastWrite -and ($Now - [datetime]$Snapshot.CcmCacheLastWrite).TotalDays -gt $Limits.CcmCacheWarnDays) {
            Add-Finding 'Info' "ccmcache unchanged for $([math]::Floor(($Now - [datetime]$Snapshot.CcmCacheLastWrite).TotalDays)) days"
        }
        if ($null -eq $Snapshot.SccmLogLastWrite) { Add-Finding 'Warning' 'No SCCM* log found in C:\Windows\Temp' }
        elseif (($Now - [datetime]$Snapshot.SccmLogLastWrite).TotalDays -gt $Limits.SccmLogWarnDays) {
            Add-Finding 'Warning' "Newest SCCM log in Windows\Temp is $([math]::Floor(($Now - [datetime]$Snapshot.SccmLogLastWrite).TotalDays)) days old"
        }
    }
    $Patches = @($Snapshot.Patches | Where-Object { $null -ne $_.InstalledOn })
    $LastPatch = $null
    if ($Patches.Count -gt 0) {
        $LastPatch = $Patches | Sort-Object InstalledOn -Descending | Select-Object -First 1
        if (($Now - [datetime]$LastPatch.InstalledOn).TotalDays -gt $Limits.PatchWarnDays) {
            Add-Finding 'Warning' "Last patch installed $([math]::Floor(($Now - [datetime]$LastPatch.InstalledOn).TotalDays)) days ago"
        }
    }
    elseif (@($Snapshot.Patches).Count -eq 0) { Add-Finding 'Info' 'No patch information returned' }

    # Genel durum ve CSV ozet satiri.
    $Health = if (@($Warnings | Where-Object Level -eq 'Critical').Count -gt 0) { 'Critical' } elseif (@($Warnings | Where-Object Level -eq 'Warning').Count -gt 0) { 'Warning' } else { 'Healthy' }
    $LastApp = @($Snapshot.Apps | Select-Object -First 1)
    $V4 = @($Snapshot.Adapters | ForEach-Object { $_.IPv4 }) -join ', '
    $Subnets = @($Snapshot.Adapters | ForEach-Object { $_.Subnet }) -join ', '
    $DiskSummary = @($Snapshot.Disks | ForEach-Object { '{0} {1}% ({2}/{3} GB free)' -f $_.Drive, $_.UsedPercent, $_.FreeGB, $_.SizeGB }) -join ' | '
    $Summary = [PSCustomObject]@{
        ComputerName = [string]$Snapshot.ComputerName; Status = 'Success'; Health = $Health; WarningCount = $Warnings.Count
        Findings = (@($Warnings | ForEach-Object { '[{0}] {1}' -f $_.Level, $_.Text }) -join '; ')
        PendingReboot = $(if ($Snapshot.RebootPending) { 'Yes' } else { 'No' }); PendingRebootReason = (@($Snapshot.RebootReasons) -join ', ')
        LastBoot = (Format-AOHealthDate $Snapshot.LastBoot); UptimeDays = $UptimeDays; ImageDate = (Format-AOHealthDate $Snapshot.InstallDate 'yyyy-MM-dd')
        OS = ([string]$Snapshot.OsCaption + ' ' + [string]$Snapshot.OsDisplayVersion).Trim(); WinBuild = [string]$Snapshot.OsBuild
        Manufacturer = [string]$Snapshot.Manufacturer; Model = [string]$Snapshot.Model; Serial = [string]$Snapshot.Serial
        IPv4 = $V4; Subnet = $Subnets
        SccmService = [string]$Snapshot.SccmServiceState; SccmStartMode = [string]$Snapshot.SccmStartMode; SccmClientVersion = [string]$Snapshot.SccmVersion
        CcmCacheLastChange = (Format-AOHealthDate $Snapshot.CcmCacheLastWrite); SccmTempLog = [string]$Snapshot.SccmLogName; SccmTempLogDate = (Format-AOHealthDate $Snapshot.SccmLogLastWrite)
        LastPatch = $(if ($null -ne $LastPatch) { [string]$LastPatch.Id } else { '' }); LastPatchDate = $(if ($null -ne $LastPatch) { Format-AOHealthDate $LastPatch.InstalledOn 'yyyy-MM-dd' } else { '' })
        LastApp = $(if ($LastApp.Count -gt 0) { [string]$LastApp[0].Name } else { '' }); LastAppDate = $(if ($LastApp.Count -gt 0) { Format-AOHealthDate $LastApp[0].InstalledOn 'yyyy-MM-dd' } else { '' })
        CpuPercent = $(if ($null -ne $Snapshot.CpuLoad) { [double]$Snapshot.CpuLoad } else { '' }); RamPercent = $(if ($null -ne $RamPercent) { $RamPercent } else { '' })
        Disks = $DiskSummary; LoggedOnUser = [string]$Snapshot.LoggedOnUser; CollectedAt = (Format-AOHealthDate $Snapshot.CollectedAt 'yyyy-MM-dd HH:mm:ss')
        ErrorDetail = (@($Snapshot.Errors) -join ' | ')
    }
    return [PSCustomObject]@{ Health = $Health; Warnings = @($Warnings.ToArray()); RamPercent = $RamPercent; UptimeDays = $UptimeDays; Summary = $Summary }
}

# HTML rapordaki detay sayfasi icin kayit (anahtar adlari JS koduyla uyumlu olmali).
function ConvertTo-AOHealthDetail {
    # JSON friendly (all dates are strings) detail record used by the HTML report.
    param($Snapshot, $Evaluation)
    $F = { param($Value, $Format) Format-AOHealthDate $Value $Format }
    return [ordered]@{
        computer = [string]$Snapshot.ComputerName; status = 'Success'; health = $Evaluation.Health; error = ''
        warnings = @($Evaluation.Warnings | ForEach-Object { [ordered]@{ level = $_.Level; text = $_.Text } })
        system = [ordered]@{ manufacturer = $Snapshot.Manufacturer; model = $Snapshot.Model; serial = $Snapshot.Serial; biosVersion = $Snapshot.BiosVersion; biosDate = (& $F $Snapshot.BiosDate 'yyyy-MM-dd'); os = $Snapshot.OsCaption; osVersion = $Snapshot.OsDisplayVersion; build = $Snapshot.OsBuild; arch = $Snapshot.OsArch; domain = $Snapshot.Domain; user = $Snapshot.LoggedOnUser; cpu = $Snapshot.CpuName; cores = $Snapshot.CpuCores }
        boot = [ordered]@{ lastBoot = (& $F $Snapshot.LastBoot 'yyyy-MM-dd HH:mm'); uptimeDays = $Evaluation.UptimeDays; imageDate = (& $F $Snapshot.InstallDate 'yyyy-MM-dd'); rebootPending = [bool]$Snapshot.RebootPending; rebootReasons = @($Snapshot.RebootReasons) }
        network = @($Snapshot.Adapters | ForEach-Object { [ordered]@{ name = $_.Name; mac = $_.Mac; ipv4 = @($_.IPv4); subnet = @($_.Subnet); gateway = @($_.Gateway); dns = @($_.Dns); dhcp = $_.Dhcp } })
        sccm = [ordered]@{ service = $Snapshot.SccmServiceState; startMode = $Snapshot.SccmStartMode; version = $Snapshot.SccmVersion; cacheExists = [bool]$Snapshot.CcmCacheExists; cacheLastChange = (& $F $Snapshot.CcmCacheLastWrite 'yyyy-MM-dd HH:mm'); cacheItems = $Snapshot.CcmCacheItems; cacheNewest = $Snapshot.CcmCacheNewestItem; tempLog = $Snapshot.SccmLogName; tempLogDate = (& $F $Snapshot.SccmLogLastWrite 'yyyy-MM-dd HH:mm'); tempLogCount = $Snapshot.SccmLogCount; ccmExecLogDate = (& $F $Snapshot.CcmExecLogLastWrite 'yyyy-MM-dd HH:mm') }
        resources = [ordered]@{ cpu = $Snapshot.CpuLoad; ramPercent = $Evaluation.RamPercent; ramTotalMB = $Snapshot.MemTotalMB; ramFreeMB = $Snapshot.MemFreeMB }
        disks = @($Snapshot.Disks | ForEach-Object { [ordered]@{ drive = $_.Drive; label = $_.Label; fs = $_.FileSystem; sizeGB = $_.SizeGB; freeGB = $_.FreeGB; usedPercent = $_.UsedPercent } })
        services = @($Snapshot.Services | ForEach-Object { [ordered]@{ name = $_.Name; display = $_.DisplayName; state = $_.State; startMode = $_.StartMode } })
        patches = @($Snapshot.Patches | ForEach-Object { [ordered]@{ id = $_.Id; description = $_.Description; installedOn = (& $F $_.InstalledOn 'yyyy-MM-dd'); by = $_.InstalledBy } })
        apps = @($Snapshot.Apps | ForEach-Object { [ordered]@{ name = $_.Name; version = $_.Version; installedOn = (& $F $_.InstalledOn 'yyyy-MM-dd') } })
        notes = @($Snapshot.Errors)
        collectedAt = (& $F $Snapshot.CollectedAt 'yyyy-MM-dd HH:mm:ss')
    }
}

# ---------------------------------------------------------------- HTML
# Detaylari JSON'a cevirir ve <script> icinde guvenli kalacak sekilde kacislar.
function ConvertTo-AOHealthJson {
    param($Details)
    $Json = ConvertTo-Json -InputObject @($Details) -Depth 8 -Compress
    if ([string]::IsNullOrWhiteSpace($Json)) { $Json = '[]' }
    # keep the payload inert inside <script type="application/json">
    return $Json.Replace('<', '\u003c').Replace('>', '\u003e').Replace('&', '\u0026').Replace([string][char]0x2028, '\u2028').Replace([string][char]0x2029, '\u2029')
}

# TEK HTML RAPOR: asagidaki sablondaki __DATA__/__OP__/__DATE__ yer tutuculari doldurulur.
# Sol tarafta bilgisayar listesi, sagda genel tablo / secilen bilgisayarin detayi.
function Write-AOHealthHtmlReport {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [AllowEmptyCollection()][object[]]$Details = @(), [string]$OperationID = '')
    $Template = @'
<!doctype html>
<html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="color-scheme" content="light dark"><title>PC Sa&#287;l&#305;k Kontrol&uuml; | Remote Ops</title>
<style>
:root{--bg:#f2f5f9;--card:#fff;--ink:#1a2a36;--muted:#5f7280;--line:#dbe3ea;--head:#e9eff5;--brand:#0b64a8;--ok:#17855a;--warn:#b7791f;--bad:#c53a3a;--oth:#6b7b89;--ok-bg:#e3f5ec;--warn-bg:#fbf0d9;--bad-bg:#fbe5e5;--oth-bg:#e9edf1;--shadow:0 1px 2px rgba(16,40,60,.06),0 6px 18px rgba(16,40,60,.07)}
@media(prefers-color-scheme:dark){:root{--bg:#0e1820;--card:#15242e;--ink:#e5edf2;--muted:#93a6b3;--line:#27394a;--head:#1c303d;--brand:#5aaee8;--ok:#4cc590;--warn:#e0b04f;--bad:#ef7c7c;--oth:#93a6b3;--ok-bg:#16382d;--warn-bg:#3b3015;--bad-bg:#401f20;--oth-bg:#22343f;--shadow:0 1px 2px rgba(0,0,0,.3),0 6px 18px rgba(0,0,0,.28)}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.45 'Segoe UI',system-ui,sans-serif}
.top{background:linear-gradient(120deg,#073f73,#0b64a8 55%,#0a8c83);color:#fff;padding:18px 28px}.top .brand{font-size:12px;letter-spacing:.14em;font-weight:600;opacity:.85}.top h1{margin:4px 0 6px;font-size:23px;font-weight:600}.chip{display:inline-block;background:rgba(255,255,255,.16);border-radius:999px;padding:2px 12px;font-size:12px;margin-right:8px}
.layout{display:grid;grid-template-columns:300px 1fr;gap:16px;padding:16px 28px 36px;max-width:1700px;margin:0 auto;align-items:start}
@media(max-width:900px){.layout{grid-template-columns:1fr;padding:12px}.side{position:static!important;max-height:40vh}}
.side{background:var(--card);border:1px solid var(--line);border-radius:12px;box-shadow:var(--shadow);position:sticky;top:12px;max-height:calc(100vh - 24px);display:flex;flex-direction:column;overflow:hidden}
.side .tools{padding:12px;border-bottom:1px solid var(--line);display:grid;gap:8px}
input,select{font:inherit;color:var(--ink);background:var(--card);border:1px solid var(--line);border-radius:8px;padding:8px 10px;width:100%}input:focus,select:focus,button:focus-visible{outline:2px solid var(--brand);outline-offset:1px}
.list{overflow:auto;flex:1}.item{display:flex;align-items:center;gap:8px;padding:9px 12px;border-bottom:1px solid var(--line);cursor:pointer;border-left:4px solid transparent;width:100%;background:none;border-top:0;border-right:0;text-align:left;color:inherit;font:inherit}
.item:hover{background:var(--head)}.item.sel{background:var(--head);border-left-color:var(--brand)}.item .n{flex:1;font-weight:600;overflow:hidden;text-overflow:ellipsis}
.dot{width:10px;height:10px;border-radius:50%;flex:none}.Healthy .dot,.dot.Healthy{background:var(--ok)}.Warning .dot,.dot.Warning{background:var(--warn)}.Critical .dot,.dot.Critical{background:var(--bad)}.Failed .dot,.Unreachable .dot,.dot.Failed,.dot.Unreachable{background:var(--oth)}
.pill{display:inline-block;padding:2px 10px;border-radius:999px;font-size:11.5px;font-weight:600;white-space:nowrap}.pill.Healthy{background:var(--ok-bg);color:var(--ok)}.pill.Warning{background:var(--warn-bg);color:var(--warn)}.pill.Critical,.pill.Error{background:var(--bad-bg);color:var(--bad)}.pill.Failed,.pill.Unreachable,.pill.Info{background:var(--oth-bg);color:var(--oth)}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px}.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:12px 14px;box-shadow:var(--shadow);border-top:4px solid var(--brand)}.card.ok{border-top-color:var(--ok)}.card.warn{border-top-color:var(--warn)}.card.bad{border-top-color:var(--bad)}.card.oth{border-top-color:var(--oth)}
.card span{display:block;color:var(--muted);font-size:12px}.card strong{display:block;font-size:28px;line-height:1.15;font-variant-numeric:tabular-nums}
.panel{background:var(--card);border:1px solid var(--line);border-radius:12px;box-shadow:var(--shadow);padding:14px 16px;margin-top:14px}.panel h2{margin:0 0 10px;font-size:15px}
.kv{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:8px 22px}.kv div{border-bottom:1px dashed var(--line);padding:3px 0;display:flex;justify-content:space-between;gap:12px}.kv span{color:var(--muted)}.kv b{font-weight:600;text-align:right;overflow-wrap:anywhere}
.grid2{display:grid;grid-template-columns:repeat(auto-fit,minmax(380px,1fr));gap:14px}
table{width:100%;border-collapse:collapse;font-size:12.5px}th{background:var(--head);text-align:left;padding:7px 10px;white-space:nowrap}td{border-top:1px solid var(--line);padding:6px 10px;vertical-align:top;overflow-wrap:anywhere}th.s{cursor:pointer}tbody tr.row{cursor:pointer}tbody tr.row td{white-space:nowrap}tbody tr.row td:last-child{white-space:normal}tbody tr.row:hover{background:var(--head)}
.wrap{overflow:auto;max-height:60vh;border:1px solid var(--line);border-radius:10px}
.bar{height:10px;border-radius:5px;background:var(--oth-bg);overflow:hidden;margin-top:4px}.bar i{display:block;height:100%;background:var(--ok)}.bar i.w{background:var(--warn)}.bar i.c{background:var(--bad)}
.warnrow{display:flex;gap:10px;align-items:baseline;padding:4px 0}.ok-note{color:var(--ok);font-weight:600}.muted{color:var(--muted)}
.btn{font:inherit;padding:7px 12px;border-radius:8px;border:1px solid var(--brand);background:transparent;color:var(--brand);cursor:pointer}.btn.p{background:var(--brand);color:#fff}
.back{margin-bottom:6px}.hidden{display:none!important}
@media print{.side,.noprint{display:none!important}.layout{display:block}.top{background:#fff;color:#000;border-bottom:3px solid #0b64a8}body{background:#fff}}
</style></head><body>
<div class="top"><div class="brand">REMOTE OPS &middot; B&#304;LG&#304;SAYAR SA&#286;LIK KONTROL&Uuml;</div><h1 id="title">PC sa&#287;l&#305;k kontrol&uuml;</h1><div><span class="chip" id="chipOp"></span><span class="chip" id="chipDate"></span></div></div>
<div class="layout">
<aside class="side"><div class="tools"><input id="q" type="search" placeholder="Bilgisayar ara..." aria-label="Bilgisayar ara"><select id="f" aria-label="Duruma g&ouml;re filtrele"><option value="">T&uuml;m durumlar</option><option>Critical</option><option>Warning</option><option>Healthy</option><option>Failed</option><option>Unreachable</option></select><button class="btn noprint" id="overviewBtn" type="button">Genel g&ouml;r&uuml;n&uuml;m</button></div><div class="list" id="list" role="listbox"></div></aside>
<main id="main"></main>
</div>
<script id="data" type="application/json">__DATA__</script>
<script>
(function(){
var D=JSON.parse(document.getElementById('data').textContent);
var META={op:__OP__,date:__DATE__};
document.getElementById('chipOp').textContent='\u0130\u015flem kodu: '+META.op;document.getElementById('chipDate').textContent=META.date;
var TR={Healthy:'Sa\u011fl\u0131kl\u0131',Warning:'Uyar\u0131',Critical:'Kritik',Failed:'Ba\u015far\u0131s\u0131z',Unreachable:'Eri\u015filemedi',Info:'Bilgi',Error:'Hata'};
function el(t,c,x){var e=document.createElement(t);if(c)e.className=c;if(x!==undefined&&x!==null)e.textContent=x;return e}
function add(p){for(var i=1;i<arguments.length;i++)if(arguments[i])p.appendChild(arguments[i]);return p}
function pill(s){return el('span','pill '+s,TR[s]||s)}
function val(v){return(v===null||v===undefined||v==='')?'-':String(v)}
var main=document.getElementById('main'),list=document.getElementById('list'),current=null;
D.sort(function(a,b){var r={Critical:0,Failed:1,Unreachable:1,Warning:2,Healthy:3};return(r[a.health]-r[b.health])||a.computer.localeCompare(b.computer,undefined,{numeric:true})});
function kv(obj){var g=el('div','kv');obj.forEach(function(p){var d=el('div');add(d,el('span','',p[0]),el('b','',val(p[1])));g.appendChild(d)});return g}
function panel(title,body){var p=el('div','panel');add(p,el('h2','',title),body);return p}
function table(heads,rows){var w=el('div','wrap'),t=el('table'),th=el('thead'),tr=el('tr');heads.forEach(function(h){tr.appendChild(el('th','',h))});th.appendChild(tr);var tb=el('tbody');rows.forEach(function(r){var x=el('tr');r.forEach(function(c){x.appendChild(el('td','',val(c)))});tb.appendChild(x)});if(!rows.length){var e=el('tr'),c=el('td','muted','Kay\u0131t yok');c.colSpan=heads.length;e.appendChild(c);tb.appendChild(e)}add(t,th,tb);w.appendChild(t);return w}
function meter(label,pct,extra){var d=el('div');add(d,el('div','',label+': '+(pct===null||pct===''?'-':pct+'%')+(extra?'  ('+extra+')':'')));var b=el('div','bar'),i=el('i',pct>=95?'c':(pct>=85?'w':''));i.style.width=Math.max(0,Math.min(100,pct||0))+'%';b.appendChild(i);d.appendChild(b);return d}
function renderList(){var q=document.getElementById('q').value.toLowerCase(),f=document.getElementById('f').value;list.textContent='';D.forEach(function(d){if(f&&d.health!==f)return;if(q&&d.computer.toLowerCase().indexOf(q)<0)return;var b=el('button','item '+d.health+(current===d.computer?' sel':''));b.type='button';b.setAttribute('role','option');add(b,el('span','dot '+d.health),el('span','n',d.computer),pill(d.health));b.onclick=function(){show(d.computer)};list.appendChild(b)});if(!list.children.length)list.appendChild(el('div','muted','E\u015fle\u015fen bilgisayar yok')).style.padding='12px'}
function overview(){current=null;location.hash='';renderList();main.textContent='';var c={Healthy:0,Warning:0,Critical:0,Bad:0,Reboot:0};D.forEach(function(d){if(d.health==='Failed'||d.health==='Unreachable')c.Bad++;else c[d.health]++;if(d.boot&&d.boot.rebootPending)c.Reboot++});
var cards=el('div','cards');[['Bilgisayar',D.length,''],['Sa\u011fl\u0131kl\u0131',c.Healthy,'ok'],['Uyar\u0131',c.Warning,'warn'],['Kritik',c.Critical,'bad'],['Eri\u015filemedi / Hata',c.Bad,'oth'],['Reboot bekleyen',c.Reboot,'warn']].forEach(function(x){var k=el('div','card '+x[2]);add(k,el('span','',x[0]),el('strong','',x[1]));cards.appendChild(k)});main.appendChild(cards);
var heads=['Bilgisayar','Durum','Reboot','Son a\u00e7\u0131l\u0131\u015f','\u0130maj tarihi','Build','IPv4','SCCM','Disk (en y\u00fcksek)','CPU %','RAM %','Son yama','Uyar\u0131'];
var rows=D.map(function(d){if(d.status!=='Success')return[d.computer,TR[d.health],'','','','','','','','','','',d.error];var s=d.sccm||{},mx=0,dk='';(d.disks||[]).forEach(function(k){if(k.usedPercent>=mx){mx=k.usedPercent;dk=k.drive+' %'+k.usedPercent}});var p=(d.patches||[])[0];return[d.computer,TR[d.health],d.boot.rebootPending?'Evet':'Hay\u0131r',d.boot.lastBoot,d.boot.imageDate,d.system.build,(d.network||[]).map(function(n){return n.ipv4.join(', ')}).join(', '),s.service,dk,d.resources.cpu,d.resources.ramPercent,p?p.id+' ('+p.installedOn+')':'',(d.warnings||[]).length]});
var w=el('div','wrap'),t=el('table'),th=el('thead'),tr=el('tr');heads.forEach(function(h,i){var x=el('th','s',h);x.title='S\u0131rala';x.onclick=function(){var asc=x.dataset.asc!=='1';x.dataset.asc=asc?'1':'0';var tb=t.tBodies[0],rs=[].slice.call(tb.rows);rs.sort(function(a,b){return a.cells[i].textContent.localeCompare(b.cells[i].textContent,undefined,{numeric:true})*(asc?1:-1)});rs.forEach(function(r){tb.appendChild(r)})};tr.appendChild(x)});th.appendChild(tr);var tb=el('tbody');rows.forEach(function(r){var x=el('tr','row');r.forEach(function(c){x.appendChild(el('td','',val(c)))});x.onclick=function(){show(r[0])};tb.appendChild(x)});add(t,th,tb);w.appendChild(t);
var p=panel('T\u00fcm bilgisayarlar (sat\u0131ra t\u0131klay\u0131n veya soldan se\u00e7in)',w);main.appendChild(p)}
function show(name){var d=D.filter(function(x){return x.computer===name})[0];if(!d)return;current=name;location.hash=encodeURIComponent(name);renderList();main.textContent='';
var back=el('button','btn back noprint','\u2190 Genel g\u00f6r\u00fcn\u00fcm');back.type='button';back.onclick=overview;main.appendChild(back);
var head=el('div','panel');head.style.marginTop='0';add(head,add(el('h2'),el('span','',d.computer+'  '),pill(d.health)));
if(d.status!=='Success'){add(head,el('div','',d.error||'Veri al\u0131namad\u0131.'));main.appendChild(head);return}
var wr=el('div');if(!d.warnings.length)wr.appendChild(el('div','ok-note','Uyar\u0131 yok - t\u00fcm kontroller normal.'));d.warnings.forEach(function(w){var r=el('div','warnrow');add(r,pill(w.level),el('span','',w.text));wr.appendChild(r)});head.appendChild(wr);main.appendChild(head);
var s=d.system,b=d.boot,c=d.sccm,r=d.resources;
var g=el('div','grid2');
g.appendChild(panel('Sistem',kv([['\u00dcretici',s.manufacturer],['Model',s.model],['Seri no',s.serial],['BIOS',s.biosVersion+(s.biosDate?' ('+s.biosDate+')':'')],['\u0130\u015fletim sistemi',s.os],['S\u00fcr\u00fcm',s.osVersion],['Windows build',s.build],['Mimari',s.arch],['Domain',s.domain],['Oturum a\u00e7an',s.user],['\u0130\u015flemci',s.cpu],['Mant\u0131ksal \u00e7ekirdek',s.cores]])));
g.appendChild(panel('A\u00e7\u0131l\u0131\u015f ve imaj',kv([['Reboot bekliyor',b.rebootPending?'EVET':'Hay\u0131r'],['Neden',(b.rebootReasons||[]).join(', ')],['Son a\u00e7\u0131l\u0131\u015f',b.lastBoot],['Kesintisiz s\u00fcre (g\u00fcn)',b.uptimeDays],['\u0130maj / kurulum tarihi',b.imageDate],['Toplanma zaman\u0131',d.collectedAt]])));
main.appendChild(g);
var res=el('div');res.appendChild(meter('CPU',r.cpu===null?'':r.cpu));res.appendChild(meter('RAM',r.ramPercent===null?'':r.ramPercent,Math.round((r.ramTotalMB-r.ramFreeMB)/1024*10)/10+' / '+Math.round(r.ramTotalMB/1024*10)/10+' GB'));d.disks.forEach(function(k){res.appendChild(meter('Disk '+k.drive+(k.label?' '+k.label:''),k.usedPercent,k.freeGB+' GB bo\u015f / '+k.sizeGB+' GB'))});
var g2=el('div','grid2');g2.appendChild(panel('Kaynak kullan\u0131m\u0131 (anl\u0131k)',res));
g2.appendChild(panel('SCCM istemcisi',kv([['CcmExec servisi',c.service+(c.startMode?' / '+c.startMode:'')],['\u0130stemci s\u00fcr\u00fcm\u00fc',c.version],['ccmcache son de\u011fi\u015fiklik',c.cacheExists?c.cacheLastChange:'Klas\u00f6r yok'],['ccmcache \u00f6\u011fe say\u0131s\u0131',c.cacheItems],['ccmcache en yeni \u00f6\u011fe',c.cacheNewest],['Windows\\Temp son SCCM* log',c.tempLog],['Son SCCM* log tarihi',c.tempLogDate],['SCCM* log say\u0131s\u0131',c.tempLogCount],['CcmExec.log son yazma',c.ccmExecLogDate]])));
main.appendChild(g2);
var nrows=(d.network||[]).map(function(n){return[n.name,n.mac,n.ipv4.join(', '),n.subnet.join(', '),n.gateway.join(', '),n.dns.join(', '),n.dhcp?'DHCP':'Statik']});
main.appendChild(panel('A\u011f',table(['Adapt\u00f6r','MAC','IPv4','Subnet','Gateway','DNS','Tip'],nrows)));
main.appendChild(panel('Servisler',table(['Servis','G\u00f6r\u00fcnen ad','Durum','Ba\u015flang\u0131\u00e7'],d.services.map(function(x){return[x.name,x.display,x.state,x.startMode]}))));
main.appendChild(panel('Son kurulan yamalar',table(['KB','A\u00e7\u0131klama','Kurulum tarihi','Kuran'],d.patches.map(function(x){return[x.id,x.description,x.installedOn,x.by]}))));
main.appendChild(panel('Son kurulan uygulamalar',table(['Uygulama','S\u00fcr\u00fcm','Kurulum tarihi'],d.apps.map(function(x){return[x.name,x.version,x.installedOn]}))));
if(d.notes&&d.notes.length){var n=el('div');d.notes.forEach(function(x){n.appendChild(el('div','muted',x))});main.appendChild(panel('Toplama notlar\u0131 (k\u0131smi hatalar)',n))}
window.scrollTo(0,0)}
document.getElementById('q').addEventListener('input',renderList);document.getElementById('f').addEventListener('input',renderList);document.getElementById('overviewBtn').onclick=overview;
var h=decodeURIComponent((location.hash||'').replace(/^#/,''));if(h&&D.some(function(x){return x.computer===h}))show(h);else overview();
})();
</script></body></html>
'@
    # Sablonu doldur ve dosyaya yaz.
    $Json = ConvertTo-AOHealthJson -Details $Details
    $OpJson = (ConvertTo-Json -InputObject ([string]$OperationID) -Compress).Replace('<', '\u003c')
    $DateJson = (ConvertTo-Json -InputObject (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Compress)
    $Html = $Template.Replace('__DATA__', $Json).Replace('__OP__', $OpJson).Replace('__DATE__', $DateJson)
    $Parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $Parent -PathType Container)) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Html -Encoding UTF8 -ErrorAction Stop
    return $Path
}

# ---------------------------------------------------------------- operation entry point
# ====================================================================
# OPERASYON GIRIS NOKTASI (Runner: Invoke-AOHealthCheck @Common -SkipApps:...)
# ====================================================================
function Invoke-AOHealthCheck {
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
        [scriptblock]$OperationHistoryWriter,
        [switch]$SkipApps
    )
    $ReportRoot = Join-Path (Join-Path $BasePath 'Logs') 'Health'
    New-Item -ItemType Directory -Path $ReportRoot -Force | Out-Null
    $CsvPath = Join-Path $ReportRoot ('{0}_HealthCheck.csv' -f $OperationID)
    $Rows = @()
    # Her hedef: snapshot -> degerlendirme -> CSV ozet satiri + HTML detay kaydi.
    foreach ($ComputerName in $Systems) {
        if ($ReachableSystems -notcontains $ComputerName) {
            $Rows += [PSCustomObject]@{ OperationID = $OperationID; ComputerName = $ComputerName; Status = 'Unreachable'; Health = ''; ErrorDetail = 'Ping failed.' }
            [void]$script:AOHealthDetails.Add([ordered]@{ computer = $ComputerName; status = 'Unreachable'; health = 'Unreachable'; error = 'Ping failed.'; warnings = @() })
            continue
        }
        try {
            if ($null -ne $TechnicalLogWriter) {
                & $TechnicalLogWriter -Level 'INFO' -Message "HEALTH-START | OperationID='$OperationID' | PC='$ComputerName'"
            }
            $Snapshot = Get-AOHealthSnapshot -ComputerName $ComputerName -SkipApps:$SkipApps
            $Evaluation = ConvertTo-AOHealthEvaluation -Snapshot $Snapshot
            $Summary = $Evaluation.Summary
            $Summary | Add-Member -NotePropertyName OperationID -NotePropertyValue $OperationID -Force
            $Rows += $Summary
            [void]$script:AOHealthDetails.Add((ConvertTo-AOHealthDetail -Snapshot $Snapshot -Evaluation $Evaluation))
            Write-Host ("{0} : HEALTH OK | {1} | warnings={2}" -f $ComputerName, $Evaluation.Health, $Evaluation.Warnings.Count)
            if ($null -ne $TechnicalLogWriter) {
                & $TechnicalLogWriter -Level 'INFO' -Message "HEALTH-END | OperationID='$OperationID' | PC='$ComputerName' | Health=$($Evaluation.Health)"
            }
        }
        catch {
            $Message = $_.Exception.Message
            $Rows += [PSCustomObject]@{ OperationID = $OperationID; ComputerName = $ComputerName; Status = 'Failed'; Health = ''; ErrorDetail = $Message }
            [void]$script:AOHealthDetails.Add([ordered]@{ computer = $ComputerName; status = 'Failed'; health = 'Failed'; error = $Message; warnings = @() })
            Write-Host "$ComputerName : HEALTH HATA | $Message" -ForegroundColor Red
            if ($null -ne $TechnicalLogWriter) {
                & $TechnicalLogWriter -Level 'ERROR' -Message "HEALTH-ERROR | OperationID='$OperationID' | PC='$ComputerName' | $Message"
            }
        }
    }
    # Tum hedeflerin ozet satirlarini CSV'ye yaz (Runner sonuclari Rows ile de alir).
    $Headers = @($Rows | ForEach-Object { $_.PSObject.Properties.Name } | Select-Object -Unique)
    $Rows | Select-Object $Headers | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8 -Delimiter ';' -ErrorAction Stop
    return [PSCustomObject]@{ Completed = $true; ResultCsv = $CsvPath; Rows = $Rows; Message = "Health check tamamlandi. Kayit=$($Rows.Count)" }
}

# Modul kaydi sadece host kayit fonksiyonlari mevcutsa yapilir (testlerde dot-source edilebilsin diye).
if ((Get-Command -Name Register-AOModule -ErrorAction SilentlyContinue) -and (Get-Command -Name Register-AOModuleOperation -ErrorAction SilentlyContinue)) {
    Register-AOModule -Name 'HealthOperations' -Version '1.0' -MinimumHostApiVersion '1.0' -SourcePath $PSCommandPath
    Register-AOModuleOperation -ModuleName 'HealthOperations' -Name 'HealthCheck' -DisplayName 'PC Health Check / Detayli Kontrol' -EntryPointName 'Invoke-AOHealthCheck' -Handler ${function:Invoke-AOHealthCheck}
}
