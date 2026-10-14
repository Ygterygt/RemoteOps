####################################################################
# AO - File Operations Module - v10.7
#
# Fonksiyonlar:
# - Hedef bilgisayardan dosya/klasor/wildcard icerigi cekme
# - Hedef bilgisayarda guvenli dosya/klasor silme (preflight + Robocopy backup + verification + DELETE onayi)
# - Lokal veya UNC kaynaktan hedef bilgisayarlara dosya/klasor kopyalama
# - Lokal referans dosyasi ile hedef dosyayi SHA256/Size/Modified bazinda karsilastirma
# - Son 7 gunde alinmis silme yedeklerini geri yukleme
# - Paket operasyonu sonrasinda C:\Windows\Temp altindaki son N dakikada
#   olusan/guncellenen .log ve .txt dosyalarini toplama
#
# Hedef Uyumluluk: Windows PowerShell 5.1+
# v10.7: Generic List + @() binder hatasi icin ToArray() uyumluluk duzeltmeleri eklendi.
####################################################################

# ====================================================================
# NASIL CALISIR (ozet)
# - Uzak dosya erisimi icin WinRM/PSRemoting KULLANILMAZ; hedefin yonetim paylasimi
#   (\\PC\C$\...) uzerinden dogrudan dosya islemi yapilir (ConvertTo-AORemoteAdminPath).
# - Konsol menusu (Read-Host) ile calisir; GUI'den Runner cevaplari sirayla verir:
#     1=Pull 2=Delete 3=Push 4=Compare 5=Restore 6=Dosya gezgini 7=Dosya rollback 0=Bitir
# - Silme her zaman: preflight (hash'li snapshot) -> Robocopy yedek -> yedek dogrulama ->
#   kaynak degismedi mi kontrolu -> silme -> silme sonrasi dogrulama zinciriyle yapilir.
# - Bu dosya paket worker'i icinde de dot-source edilir (Get-AORecentLogs ve
#   Remove-AOCollectedUserLogs icin); o durumda modul kaydi yapilmaz.
# - Klasorler (BasePath altinda): PulledFiles, PulledLogs, DeleteBackups (7 gun saklanir),
#   FileRollbacks, Logs\FileOperations\MD_File*.csv
# ====================================================================
#
# Modul ayarlari: yedek saklama suresi, Robocopy tekrar/bekleme degerleri.
Set-StrictMode -Version 2.0

$script:AOFileOpsBackupRetentionDays = 7
$script:AOFileOpsDefaultThrottle     = 5
$script:AOFileOpsRobocopyRetryCount  = 1
$script:AOFileOpsRobocopyWaitSeconds = 1
$script:AOFileOperationsSourcePath   = $PSCommandPath

# Modulu host'a kaydeder (sadece Register-AOModule fonksiyonu mevcutsa).
function Register-AOFileOperationsModule {
    # Bu dosya iki farkli durumda dot-source edilebilir:
    # 1) Ana script scope'unda: Modul + menu operation register edilir.
    # 2) Package worker runspace'inde: Register-AOModule fonksiyonlari yoktur;
    #    sadece Get-AORecentLogs gibi helper fonksiyonlar yuklenir.
    if (-not (Get-Command -Name Register-AOModule -ErrorAction SilentlyContinue)) { return }
    if (-not (Get-Command -Name Register-AOModuleOperation -ErrorAction SilentlyContinue)) { return }

    Register-AOModule `
        -Name 'FileOperations' `
        -Version '10.7' `
        -MinimumHostApiVersion '1.0' `
        -SourcePath $script:AOFileOperationsSourcePath `
        -Initializer ${function:Initialize-AOFileOperations}

    Register-AOModuleOperation `
        -ModuleName 'FileOperations' `
        -Name 'FileOperations' `
        -DisplayName 'Dosya Operasyonlari' `
        -EntryPointName 'Invoke-AOFileOperationsMenu' `
        -Handler ${function:Invoke-AOFileOperationsMenu}
}

# --- YOL YARDIMCILARI ---
# "C:\Klasor\dosya" -> "\\PC\C$\Klasor\dosya" (hedefin yonetim paylasimi yolu).
function ConvertTo-AORemoteAdminPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][string]$LocalPath
    )

    $Value = $LocalPath.Trim()
    if ($Value -notmatch '^(?<Drive>[A-Za-z]):\\(?<Rest>.*)$') {
        throw "Hedef path mutlak Windows drive path olmalidir (Orn: C:\\Temp\\Test). Girilen='$LocalPath'"
    }

    $Drive = $Matches['Drive'].ToUpperInvariant()
    $Rest  = $Matches['Rest']

    if ([string]::IsNullOrEmpty($Rest)) {
        return ('\\{0}\{1}$' -f $ComputerName, $Drive)
    }

    return ('\\{0}\{1}$\{2}' -f $ComputerName, $Drive, $Rest)
}

# Mutlak yolu surucu harfi ve geri kalan kisim olarak ayirir.
function Get-AOLocalPathParts {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $Value = $Path.Trim()
    if ($Value -notmatch '^(?<Drive>[A-Za-z]):\\(?<Rest>.*)$') {
        throw "Path mutlak Windows drive path olmalidir. Girilen='$Path'"
    }

    [PSCustomObject]@{
        Drive = $Matches['Drive'].ToUpperInvariant()
        Rest  = $Matches['Rest']
    }
}

# Yolda * ? [ joker karakteri var mi?
function Test-AOContainsWildcard {
    param([string]$Path)
    return ($Path.IndexOfAny([char[]]'*?[') -ge 0)
}

# Joker karakter iceren ilk segmentten onceki sabit kok yolu dondurur.
function Get-AOWildcardBasePath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $Normalized = $Path.TrimEnd('\')
    $Segments = $Normalized -split '\\'
    $SafeSegments = New-Object System.Collections.Generic.List[string]

    foreach ($Segment in $Segments) {
        if ($Segment.IndexOfAny([char[]]'*?[') -ge 0) { break }
        [void]$SafeSegments.Add($Segment)
    }

    if ($SafeSegments.Count -eq 0) { return '' }
    return ($SafeSegments -join '\')
}

# Pull isleminde yerelde olusturulacak klasor adini belirler.
function Get-AOSourceContainerName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $Normalized = $Path.TrimEnd('\')
    $HasWildcard = Test-AOContainsWildcard -Path $Normalized

    if ($HasWildcard) {
        $Base = Get-AOWildcardBasePath -Path $Normalized
        if ([string]::IsNullOrWhiteSpace($Base)) { return 'PulledData' }
        $Leaf = Split-Path -Path $Base -Leaf
        if ([string]::IsNullOrWhiteSpace($Leaf) -or $Leaf -match '^[A-Za-z]:$') { return 'Root' }
        return $Leaf
    }

    $Leaf = Split-Path -Path $Normalized -Leaf
    $Ext  = [System.IO.Path]::GetExtension($Leaf)
    if (-not [string]::IsNullOrWhiteSpace($Ext)) {
        $Parent = Split-Path -Path $Normalized -Parent
        $ParentLeaf = Split-Path -Path $Parent -Leaf
        if (-not [string]::IsNullOrWhiteSpace($ParentLeaf)) { return $ParentLeaf }
    }

    if (-not [string]::IsNullOrWhiteSpace($Leaf)) { return $Leaf }
    return 'PulledData'
}

# Tam yolun, verilen koke gore goreli kismini dondurur.
function Get-AORelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$FullPath
    )

    $Base = $BasePath.TrimEnd('\')
    if ($FullPath.StartsWith($Base, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $FullPath.Substring($Base.Length).TrimStart('\')
    }
    return (Split-Path -Path $FullPath -Leaf)
}

# Hedefte yola/joker desene uyan dosya ve klasorleri dondurur (yonetim paylasimi uzerinden).
function Get-AORemoteMatches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [switch]$RecursiveWildcard
    )

    $RemotePattern = ConvertTo-AORemoteAdminPath -ComputerName $ComputerName -LocalPath $TargetPath
    $HasWildcard   = Test-AOContainsWildcard -Path $TargetPath

    if (-not $HasWildcard) {
        if (-not (Test-Path -LiteralPath $RemotePattern)) { return @() }
        return @(Get-Item -LiteralPath $RemotePattern -Force -ErrorAction Stop)
    }

    $LocalBase = Get-AOWildcardBasePath -Path $TargetPath
    if ([string]::IsNullOrWhiteSpace($LocalBase)) { throw "Wildcard base path belirlenemedi: $TargetPath" }
    $RemoteBase = ConvertTo-AORemoteAdminPath -ComputerName $ComputerName -LocalPath $LocalBase
    if (-not (Test-Path -LiteralPath $RemoteBase -PathType Container)) { return @() }

    $RelativePattern = $TargetPath.Substring($LocalBase.Length).TrimStart('\')
    if ([string]::IsNullOrWhiteSpace($RelativePattern)) { $RelativePattern = '*' }

    if ($RelativePattern -eq '*') {
        # C:\Path\* -> Path altindaki top-level ogeleri dondur. Kopyalama/silme
        # sırasında klasorler recurse edileceginden duplicate dosya uretilmez.
        return @(Get-ChildItem -LiteralPath $RemoteBase -Force -ErrorAction Stop)
    }

    if ($RecursiveWildcard) {
        $LeafPattern = Split-Path -Path $RelativePattern -Leaf
        $RelativeParent = Split-Path -Path $RelativePattern -Parent
        $SearchRoot = $RemoteBase
        if (-not [string]::IsNullOrWhiteSpace($RelativeParent)) {
            $SearchRoot = Join-Path $RemoteBase $RelativeParent
        }
        if (-not (Test-Path -LiteralPath $SearchRoot -PathType Container)) { return @() }

        return @(
            Get-ChildItem -LiteralPath $SearchRoot -Force -Recurse -ErrorAction Stop |
                Where-Object { $_.Name -like $LeafPattern }
        )
    }

    return @(Get-ChildItem -Path $RemotePattern -Force -ErrorAction Stop)
}

# --- SILME GUVENLIGI ---
# Silme yolunu normalize eder; '.'/'..', ADS (':'), ve son segment disinda joker karakteri reddeder.
function ConvertTo-AODeleteTargetPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $Value = $Path.Trim().Trim([char]34).Replace('/', '\')
    if ($Value -notmatch '^[A-Za-z]:\\') {
        throw "Delete hedefi mutlak Windows drive path olmalidir (Orn: C:\\Temp\\Test). Girilen='$Path'"
    }

    # Relative traversal veya ADS gibi belirsiz/destructive path semantiklerini kabul etme.
    if ($Value -match '(^|\\)\.{1,2}(\\|$)') {
        throw "Delete path '.' veya '..' segmenti iceremez. Girilen='$Path'"
    }
    if ($Value.Substring(2).Contains(':')) {
        throw "Delete path drive haricinde ':' iceremez (ADS/path belirsizligi). Girilen='$Path'"
    }

    $HasWildcard = Test-AOContainsWildcard -Path $Value
    if ($HasWildcard) {
        $Parent = Split-Path -Path $Value -Parent
        $Leaf   = Split-Path -Path $Value -Leaf
        if ([string]::IsNullOrWhiteSpace($Parent) -or [string]::IsNullOrWhiteSpace($Leaf)) {
            throw "Wildcard delete path ayristirilamadi: $Path"
        }
        if (Test-AOContainsWildcard -Path $Parent) {
            throw "Guvenlik nedeniyle wildcard yalnizca son path segmentinde kullanilabilir. Girilen='$Path'"
        }

        $CanonicalParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\')
        if ($CanonicalParent -match '^[A-Za-z]:$') {
            return ($CanonicalParent + '\' + $Leaf)
        }
        return ($CanonicalParent + '\' + $Leaf)
    }

    $Canonical = [System.IO.Path]::GetFullPath($Value)
    if ($Canonical -match '^[A-Za-z]:\\$') { return $Canonical }
    return $Canonical.TrimEnd('\')
}

# Hedef, bu scriptin calistigi bilgisayarin kendisi mi?
function Test-AOLocalComputerTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ComputerName)

    $Candidate = $ComputerName.Trim().TrimStart('\').Split('.')[0]
    $LocalNames = @(
        $env:COMPUTERNAME,
        [System.Net.Dns]::GetHostName(),
        'localhost',
        '.',
        '127.0.0.1',
        '::1'
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    foreach ($LocalName in $LocalNames) {
        $Short = ([string]$LocalName).Trim().TrimStart('\').Split('.')[0]
        if ([string]::Equals($Candidate, $Short, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

# Iki yol ayni mi veya biri digerinin altinda mi?
function Test-AOPathOverlap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PathA,
        [Parameter(Mandatory = $true)][string]$PathB
    )

    $A = [System.IO.Path]::GetFullPath($PathA).TrimEnd('\')
    $B = [System.IO.Path]::GetFullPath($PathB).TrimEnd('\')

    if ([string]::Equals($A, $B, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($A.StartsWith(($B + '\'), [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($B.StartsWith(($A + '\'), [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $false
}

# Silinmesi yasak hedefler icin neden metni dondurur (bos = izin var):
#   - surucu koku ve koke joker, kritik sistem klasorleri (C:\Windows, Program Files...)
#   - kendi bilgisayarinda calisma/yedek klasorunu (BasePath) etkileyen yollar
function Get-AODeleteProtectionReason {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$BasePath = '',
        [string]$ComputerName = ''
    )

    try {
        $Normalized = ConvertTo-AODeleteTargetPath -Path $Path
    }
    catch {
        return $_.Exception.Message
    }

    $Candidate = $Normalized.TrimEnd('\')

    # Herhangi bir drive root veya drive root icerigi wildcard ile silinemez.
    if ($Candidate -match '^[A-Za-z]:$' -or $Candidate -match '^[A-Za-z]:\\\*([.]\*)?$') {
        return 'Drive root veya drive root icerigi toplu silmeye kapali.'
    }

    # Köklerin kendisi ve dogrudan tum-icerik wildcard'i korunur.
    # Altindaki spesifik dosya/klasor hedefleri ise kontrollu olarak kullanilabilir.
    $ProtectedRoots = @(
        'C:\Windows',
        'C:\Windows\Temp',
        'C:\Windows\System32',
        'C:\Windows\SysWOW64',
        'C:\Windows\Installer',
        'C:\Program Files',
        'C:\Program Files (x86)',
        'C:\ProgramData',
        'C:\Users',
        'C:\Temp',
        'C:\Recovery',
        'C:\System Volume Information',
        'C:\$Recycle.Bin',
        'C:\PerfLogs'
    )

    foreach ($Root in $ProtectedRoots) {
        foreach ($ProtectedForm in @($Root, ($Root + '\*'), ($Root + '\*.*'))) {
            if ([string]::Equals($Candidate, $ProtectedForm, [System.StringComparison]::OrdinalIgnoreCase)) {
                return "Kritik root korunuyor: $Root"
            }
        }
    }

    # Script kendi bilgisayarini hedefliyorsa AOFiles agacini veya onun bir atasini
    # silmeye izin verme. Aksi halde DeleteBackups kendisini yedeklemeye calisabilir.
    if (-not [string]::IsNullOrWhiteSpace($ComputerName) -and
        -not [string]::IsNullOrWhiteSpace($BasePath) -and
        (Test-AOLocalComputerTarget -ComputerName $ComputerName)) {

        $ComparablePath = if (Test-AOContainsWildcard -Path $Normalized) {
            Get-AOWildcardBasePath -Path $Normalized
        }
        else {
            $Normalized
        }

        if (-not [string]::IsNullOrWhiteSpace($ComparablePath) -and
            (Test-AOPathOverlap -PathA $ComparablePath -PathB $BasePath)) {
            return "Ayni bilgisayarda AOFiles calisma/yedek agaci ile cakisan path silinemez. BasePath='$BasePath'"
        }
    }

    return ''
}

function Test-AOProtectedDeletePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$BasePath = '',
        [string]$ComputerName = ''
    )

    return (-not [string]::IsNullOrWhiteSpace((Get-AODeleteProtectionReason -Path $Path -BasePath $BasePath -ComputerName $ComputerName)))
}

# Snapshot satirlarindan SHA256 ozet uretir (yapi veya yapi+zaman damgasi).
function Get-AOSnapshotHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows,
        [switch]$IncludeTimestamp
    )

    $Builder = New-Object System.Text.StringBuilder
    foreach ($Row in @($Rows | Sort-Object Key, Type)) {
        $Line = '{0}|{1}|{2}' -f ([string]$Row.Key), ([string]$Row.Type), ([Int64]$Row.Length)
        if ($IncludeTimestamp) { $Line += ('|{0}' -f ([Int64]$Row.LastWriteTimeUtcTicks)) }
        [void]$Builder.AppendLine($Line)
    }

    $Sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Builder.ToString())
        return ([System.BitConverter]::ToString($Sha.ComputeHash($Bytes))).Replace('-', '')
    }
    finally {
        $Sha.Dispose()
    }
}

# Dosya/klasor kumesinin tam envanteri: dosya/klasor sayisi, toplam boyut, reparse point'ler,
# StructureHash (yapi) ve StateHash (yapi + son yazma zamani). Silme oncesi/sonrasi karsilastirma icin.
function Get-AOItemSetSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Items,
        [ValidateSet('Name','FullName')][string]$KeyMode = 'Name'
    )

    $Rows = New-Object System.Collections.Generic.List[object]
    $ReparsePoints = New-Object System.Collections.Generic.List[string]
    [Int64]$TotalBytes = 0
    [int]$FileCount = 0
    [int]$DirectoryCount = 0

    foreach ($RootItem in @($Items)) {
        if ($null -eq $RootItem) { continue }
        $RootKey = $(if ($KeyMode -eq 'FullName') { [string]$RootItem.FullName } else { [string]$RootItem.Name })
        $IsRootReparse = (($RootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
        if ($IsRootReparse) {
            [void]$ReparsePoints.Add([string]$RootItem.FullName)
            [void]$Rows.Add([PSCustomObject]@{ Key=$RootKey; Type='ReparsePoint'; Length=0; LastWriteTimeUtcTicks=[Int64]$RootItem.LastWriteTimeUtc.Ticks })
            continue
        }

        if (-not $RootItem.PSIsContainer) {
            $FileCount++
            $TotalBytes += [Int64]$RootItem.Length
            [void]$Rows.Add([PSCustomObject]@{ Key=$RootKey; Type='File'; Length=[Int64]$RootItem.Length; LastWriteTimeUtcTicks=[Int64]$RootItem.LastWriteTimeUtc.Ticks })
            continue
        }

        $DirectoryCount++
        [void]$Rows.Add([PSCustomObject]@{ Key=$RootKey; Type='Directory'; Length=0; LastWriteTimeUtcTicks=[Int64]$RootItem.LastWriteTimeUtc.Ticks })

        $Stack = New-Object System.Collections.Stack
        $Stack.Push([PSCustomObject]@{ Directory=$RootItem; Relative='' })

        while ($Stack.Count -gt 0) {
            $Current = $Stack.Pop()
            $Children = @(Get-ChildItem -LiteralPath $Current.Directory.FullName -Force -ErrorAction Stop)

            foreach ($Child in $Children) {
                $Relative = if ([string]::IsNullOrWhiteSpace([string]$Current.Relative)) {
                    [string]$Child.Name
                }
                else {
                    ([string]$Current.Relative + '\' + [string]$Child.Name)
                }
                $Key = $RootKey + '\' + $Relative
                $IsReparse = (($Child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)

                if ($IsReparse) {
                    [void]$ReparsePoints.Add([string]$Child.FullName)
                    [void]$Rows.Add([PSCustomObject]@{ Key=$Key; Type='ReparsePoint'; Length=0; LastWriteTimeUtcTicks=[Int64]$Child.LastWriteTimeUtc.Ticks })
                    continue
                }

                if ($Child.PSIsContainer) {
                    $DirectoryCount++
                    [void]$Rows.Add([PSCustomObject]@{ Key=$Key; Type='Directory'; Length=0; LastWriteTimeUtcTicks=[Int64]$Child.LastWriteTimeUtc.Ticks })
                    $Stack.Push([PSCustomObject]@{ Directory=$Child; Relative=$Relative })
                }
                else {
                    $FileCount++
                    $TotalBytes += [Int64]$Child.Length
                    [void]$Rows.Add([PSCustomObject]@{ Key=$Key; Type='File'; Length=[Int64]$Child.Length; LastWriteTimeUtcTicks=[Int64]$Child.LastWriteTimeUtc.Ticks })
                }
            }
        }
    }

    # Windows PowerShell 5.1 compatibility: @($genericList) can throw
    # System.ArgumentException: Argument types do not match. Use ToArray() explicitly.
    $RowsArray = $Rows.ToArray()
    return [PSCustomObject]@{
        Rows               = $RowsArray
        FileCount          = $FileCount
        DirectoryCount     = $DirectoryCount
        TotalBytes         = $TotalBytes
        ReparsePointCount  = $ReparsePoints.Count
        ReparsePoints      = $ReparsePoints.ToArray()
        StructureHash      = Get-AOSnapshotHash -Rows $RowsArray
        StateHash          = Get-AOSnapshotHash -Rows $RowsArray -IncludeTimestamp
    }
}

# Silme oncesi on kontrol: eslesenleri bul, snapshot al. Reparse point/junction varsa silme engellenir.
function Get-AODeletePreflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $Stage = 'ResolveMatches'
    try {
        $Items = @(Get-AORemoteMatches -ComputerName $ComputerName -TargetPath $TargetPath -RecursiveWildcard)
        if ($Items.Count -eq 0) {
            return [PSCustomObject]@{
                Success=$false; Eligible=$false; Status='NotFound'; Items=@(); MatchedItemCount=0;
                FileCount=0; DirectoryCount=0; TotalBytes=[Int64]0; ReparsePointCount=0;
                StructureHash=''; StateHash=''; ErrorDetail='Silinecek kaynak bulunamadi.'
            }
        }

        $Stage = 'Snapshot'
        $Snapshot = Get-AOItemSetSnapshot -Items $Items -KeyMode 'FullName'
        if ($Snapshot.ReparsePointCount -gt 0) {
            return [PSCustomObject]@{
                Success=$true; Eligible=$false; Status='BlockedReparsePoint'; Items=$Items; MatchedItemCount=$Items.Count;
                FileCount=$Snapshot.FileCount; DirectoryCount=$Snapshot.DirectoryCount; TotalBytes=$Snapshot.TotalBytes;
                ReparsePointCount=$Snapshot.ReparsePointCount; StructureHash=$Snapshot.StructureHash; StateHash=$Snapshot.StateHash;
                ErrorDetail=("Delete scope icinde reparse point/junction bulundu. Guvenlik nedeniyle silme engellendi. IlkOrnek='{0}'" -f $Snapshot.ReparsePoints[0])
            }
        }

        return [PSCustomObject]@{
            Success=$true; Eligible=$true; Status='Ready'; Items=$Items; MatchedItemCount=$Items.Count;
            FileCount=$Snapshot.FileCount; DirectoryCount=$Snapshot.DirectoryCount; TotalBytes=$Snapshot.TotalBytes;
            ReparsePointCount=0; StructureHash=$Snapshot.StructureHash; StateHash=$Snapshot.StateHash; ErrorDetail=''
        }
    }
    catch {
        $ExceptionType = $_.Exception.GetType().FullName
        return [PSCustomObject]@{
            Success=$false; Eligible=$false; Status='PreflightError'; Items=@(); MatchedItemCount=0;
            FileCount=0; DirectoryCount=0; TotalBytes=[Int64]0; ReparsePointCount=0;
            StructureHash=''; StateHash=''; ErrorDetail=("Stage={0} | {1}: {2}" -f $Stage, $ExceptionType, $_.Exception.Message)
        }
    }
}

# Byte degerini okunur birime (KB/MB/GB/TB) cevirir.
function Format-AOByteSize {
    param([Int64]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N2} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    return ("$Bytes B")
}

# Calisma klasorlerini olusturur ve saklama suresini asan silme yedeklerini temizler.
function Initialize-AOFileOperations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [scriptblock]$TechnicalLogWriter
    )

    $Directories = @(
        (Join-Path $BasePath 'Modules'),
        (Join-Path $BasePath 'Logs'),
        (Join-Path (Join-Path $BasePath 'Logs') 'FileOperations'),
        (Join-Path $BasePath 'PulledFiles'),
        (Join-Path $BasePath 'PulledLogs'),
        (Join-Path $BasePath 'DeleteBackups')
    )

    foreach ($Directory in $Directories) {
        if (-not (Test-Path -LiteralPath $Directory)) {
            New-Item -ItemType Directory -Path $Directory -Force | Out-Null
        }
    }

    $BackupRoot = Join-Path $BasePath 'DeleteBackups'
    $Cutoff = (Get-Date).AddDays(-1 * $script:AOFileOpsBackupRetentionDays)

    try {
        $OldBackups = @(
            Get-ChildItem -LiteralPath $BackupRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $Cutoff }
        )

        foreach ($Backup in $OldBackups) {
            try {
                Remove-Item -LiteralPath $Backup.FullName -Recurse -Force -ErrorAction Stop
                if ($null -ne $TechnicalLogWriter) {
                    & $TechnicalLogWriter -Level 'INFO' -Message "FILEOPS-BACKUP-CLEANUP | Silindi='$($Backup.FullName)' | RetentionDays=$script:AOFileOpsBackupRetentionDays"
                }
            }
            catch {
                if ($null -ne $TechnicalLogWriter) {
                    & $TechnicalLogWriter -Level 'WARN' -Message "FILEOPS-BACKUP-CLEANUP | Silinemedi='$($Backup.FullName)' | $($_.Exception.Message)"
                }
            }
        }
    }
    catch {
        if ($null -ne $TechnicalLogWriter) {
            & $TechnicalLogWriter -Level 'WARN' -Message "FILEOPS-BACKUP-CLEANUP | Kontrol hatasi | $($_.Exception.Message)"
        }
    }
}

# Konsol menusundeki 'H' (yardim) metni.
function Show-AOFileOperationsHelp {
    Write-Host ''
    Write-Host '================ DOSYA OPERASYONLARI YARDIM ================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Hedef path her zaman hedef PC uzerindeki lokal path formatinda girilir:'
    Write-Host '  C:\Temp\Test\abc.txt              -> tek dosya'
    Write-Host '  C:\Temp\Test                      -> klasor'
    Write-Host '  C:\Temp\Test\*                    -> klasor altindaki tum icerik'
    Write-Host '  C:\Windows\Temp\*.log             -> .log wildcard'
    Write-Host '  C:\Windows\Temp\*.txt             -> .txt wildcard'
    Write-Host ''
    Write-Host 'Pull:' -ForegroundColor Yellow
    Write-Host '  Hedef dosya/klasorleri AOFiles\PulledFiles\<PC> altina ceker.'
    Write-Host ''
    Write-Host 'Delete:' -ForegroundColor Yellow
    Write-Host '  Once AOFiles\DeleteBackups altina zorunlu yedek alir; yedek basarisizsa silmez.'
    Write-Host '  Kritik root pathler (C:\Windows, C:\Temp, ProgramData vb.) ve root wildcardlari silinemez.'
    Write-Host '  Wildcard guvenlik nedeniyle yalnizca son segmentte kullanilabilir (Orn: C:\Temp\Test\*.log).'
    Write-Host '  Once preflight ile oge/dosya/klasor/byte sayisi hesaplanir; reparse point varsa silme engellenir.'
    Write-Host '  Backup Robocopy ile alinir, kaynak-backup yapisi dogrulanir ve kaynak degismediyse delete yapilir.'
    Write-Host '  Operasyon icin DELETE yazilmasi gerekir. 7 gunden eski yedekler otomatik temizlenir.'
    Write-Host ''
    Write-Host 'Push:' -ForegroundColor Yellow
    Write-Host '  Lokal veya UNC dosya/klasoru hedef PC uzerindeki hedef klasore kopyalar.'
    Write-Host '  Ornek lokal dosya   : C:\Temp\config.ini'
    Write-Host '  Ornek lokal klasor : C:\Temp\AOFiles'
    Write-Host '  Ornek UNC klasor   : \\gbnas02\Share\Paketler\AOFiles'
    Write-Host '  Ornek UNC icerik   : \\gbnas02\Share\Paketler\AOFiles\*'
    Write-Host '  Ornek UNC wildcard : \\gbnas02\Share\Paketler\AOFiles\*.ps1'
    Write-Host '  Hedefte ayni isim varsa Overwrite Evet/Hayir secimine gore davranir.'
    Write-Host ''
    Write-Host 'Compare:' -ForegroundColor Yellow
    Write-Host '  Lokal referans dosyasi ile hedefteki dosyayi SHA256, Size ve LastWriteTime ile karsilastirir.'
    Write-Host '  Ornek lokal:  C:\Temp\AOFiles\Master\config.ini'
    Write-Host '  Ornek hedef:  C:\ProgramData\MyApp\config.ini'
    Write-Host ''
    Write-Host 'Paket log toplama:' -ForegroundColor Yellow
    Write-Host '  C:\Windows\Temp altinda son 10 dakikada olusan VEYA guncellenen .log/.txt dosyalari cekilir.'
    Write-Host '  PulledLogs\<PC>\<OperationID_Operasyon> altina kaydedilir.'
    Write-Host ''
}

# ====================================================================
# DOSYA GEZGINI (menu 6) - GUI'deki "FileBrowser"
# Hedef klasordeki dosyalar listelenir, secilen dosya icin:
#   1 = Pull (yerele kopyala)  2 = Move  3 = Delete  4 = Replace
# Move/Delete/Replace oncesi dosya FileRollbacks\<ID>\<PC>\ altina yedeklenir ve
# manifest.csv'ye yazilir (menu 7 ile geri alinabilir).
# NOT: GUI'de Delete bu yoldan degil, korumali "Backup and delete" ile yapilir.
# ====================================================================
function Get-AOFilePullRoot {
    param([string]$BasePath,[string]$PullGroup='')
    $Root=Join-Path $BasePath 'PulledFiles'
    if($PullGroup){if($PullGroup -cnotmatch '^[A-Za-z0-9_-]+$'){throw 'Invalid file pull group.'};$Root=Join-Path $Root $PullGroup}
    return $Root
}
function Invoke-AORemoteFileBrowseOperations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string[]]$Systems,
        [Parameter(Mandatory = $true)][string[]]$ReachableSystems,
        [Parameter(Mandatory = $true)][string]$OperationID,
        [string]$PullGroup=''
    )

    $Rows=New-Object 'System.Collections.Generic.List[object]'
    $PullRoot=Get-AOFilePullRoot $BasePath $PullGroup
    $BrowsePath = (Read-Host 'Dosyalarin listelenecegi hedef path (Orn: C:\Windows\Temp)').Trim().TrimEnd('\')
    $RollbackRoot = Join-Path (Join-Path $BasePath 'FileRollbacks') $OperationID
    New-Item -ItemType Directory -Path $RollbackRoot -Force | Out-Null
    if ([string]::IsNullOrWhiteSpace($BrowsePath)) { return }

    foreach ($ComputerName in $ReachableSystems) {
        try {
            $RemoteRoot = ConvertTo-AORemoteAdminPath -ComputerName $ComputerName -LocalPath $BrowsePath
            if (-not (Test-Path -LiteralPath $RemoteRoot -PathType Container)) {
                Write-Host "$ComputerName : Path bulunamadi: $BrowsePath" -ForegroundColor Yellow
                continue
            }
            $Files = @(Get-ChildItem -LiteralPath $RemoteRoot -File -Recurse -Force -ErrorAction Stop | Sort-Object FullName)
            Write-Host "$ComputerName : $BrowsePath altindaki dosyalar ($($Files.Count))" -ForegroundColor Cyan
            for ($Index = 0; $Index -lt $Files.Count; $Index++) {
                $File=$Files[$Index]
                Write-Host ('{0} - {1} | Size={2} bytes | Created={3} | Modified={4}' -f ($Index+1),$File.FullName,$File.Length,$File.CreationTime.ToString('yyyy-MM-dd HH:mm:ss'),$File.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
            }
            if ($Files.Count -eq 0) { continue }
            $Choice=(Read-Host 'Islem yapilacak dosya numarasi (0=atla)').Trim()
            if ($Choice -eq '0') { continue }
            if ($Choice -notmatch '^\d+$' -or [int]$Choice -lt 1 -or [int]$Choice -gt $Files.Count) {
                Write-Host 'Gecersiz dosya secimi.' -ForegroundColor Yellow
                continue
            }
            $SelectedFile=$Files[[int]$Choice-1]
            Write-Host '1 - Pull'
            Write-Host '2 - Move'
            Write-Host '3 - Delete'
            Write-Host '4 - Replace'
            $Action=(Read-Host 'Dosya islemi').Trim()
            if ($Action -eq '1') {
                $PullDestination=Join-Path $PullRoot $ComputerName
                New-Item -ItemType Directory -Path $PullDestination -Force|Out-Null
                Copy-Item -LiteralPath $SelectedFile.FullName -Destination $PullDestination -Force -ErrorAction Stop
                $Rows.Add([PSCustomObject]@{ComputerName=$ComputerName;OperationID=$OperationID;Action='Pull';Status='Success';LokalHedefPath=(Join-Path $PullDestination $SelectedFile.Name);ErrorDetail=''})
                Write-Host "$ComputerName : PULL OK: $PullDestination" -ForegroundColor Green
                continue
            }
            if ($Action -notin @('2','3','4')) { Write-Host 'Gecersiz dosya islemi.' -ForegroundColor Yellow;continue }

            # Degisiklik oncesi rollback yedegi al.
            $BackupComputerRoot=Join-Path $RollbackRoot $ComputerName
            New-Item -ItemType Directory -Path $BackupComputerRoot -Force|Out-Null
            $BackupPath=Join-Path $BackupComputerRoot $SelectedFile.Name
            Copy-Item -LiteralPath $SelectedFile.FullName -Destination $BackupPath -Force -ErrorAction Stop
            $ChangedPath=[string]$SelectedFile.FullName
            $ActionName=if($Action -eq '2'){'Move'}elseif($Action -eq '3'){'Delete'}else{'Replace'}
            if($Action -eq '2'){
                $MoveTarget=(Read-Host 'Hedef klasor path').Trim()
                if((Read-Host 'Move icin MOVE yazin').Trim().ToUpperInvariant() -ne 'MOVE'){
                    continue
                }
                $RemoteTarget=ConvertTo-AORemoteAdminPath $ComputerName $MoveTarget
                New-Item -ItemType Directory -Path $RemoteTarget -Force|Out-Null
                Move-Item -LiteralPath $SelectedFile.FullName -Destination $RemoteTarget -Force -ErrorAction Stop
                $ChangedPath=Join-Path $RemoteTarget $SelectedFile.Name
            }
            elseif($Action -eq '3'){
                if((Read-Host 'Delete icin DELETE yazin').Trim().ToUpperInvariant() -ne 'DELETE'){
                    continue
                }
                Remove-Item -LiteralPath $SelectedFile.FullName -Force -ErrorAction Stop
            }
            else{
                $ReplaceSource=(Read-Host 'Lokal replace kaynak dosyasi').Trim()
                if(-not(Test-Path -LiteralPath $ReplaceSource -PathType Leaf)){
                    throw "Replace kaynak dosyasi bulunamadi: $ReplaceSource"
                }
                if((Read-Host 'Replace icin REPLACE yazin').Trim().ToUpperInvariant() -ne 'REPLACE'){
                    continue
                }
                Copy-Item -LiteralPath $ReplaceSource -Destination $SelectedFile.FullName -Force -ErrorAction Stop
            }
            [PSCustomObject]@{ComputerName=$ComputerName;Action=$ActionName;OriginalPath=$SelectedFile.FullName;ChangedPath=$ChangedPath;BackupPath=$BackupPath}|Export-Csv -LiteralPath (Join-Path $RollbackRoot 'manifest.csv') -NoTypeInformation -Encoding UTF8 -Delimiter ';' -Append -ErrorAction SilentlyContinue
            $Rows.Add([PSCustomObject]@{ComputerName=$ComputerName;OperationID=$OperationID;Action=$ActionName;Status='Success';LokalHedefPath='';ErrorDetail=''})
            Write-Host "$ComputerName : $ActionName OK | Rollback yedegi: $BackupPath" -ForegroundColor Green
        } catch { $Rows.Add([PSCustomObject]@{ComputerName=$ComputerName;OperationID=$OperationID;Action='Browse';Status='Failed';LokalHedefPath='';ErrorDetail=$_.Exception.Message});Write-Host "$ComputerName : DOSYA ISLEM HATASI | $($_.Exception.Message)" -ForegroundColor Red }
    }
    if($Rows.Count){
        $ReportRoot=Join-Path $BasePath 'Logs\FileOperations';New-Item -ItemType Directory -Path $ReportRoot -Force|Out-Null
        $Csv=Join-Path $ReportRoot ($OperationID+'_FileBrowser.csv')
        $Rows.ToArray()|Export-Csv -LiteralPath $Csv -NoTypeInformation -Encoding UTF8 -Delimiter ';' -ErrorAction Stop
        return [PSCustomObject]@{Completed=$true;ResultCsv=$Csv;Rows=@($Rows.ToArray())}
    }

}

# DOSYA ROLLBACK (menu 7): secilen FileRollbacks calismasinin manifest'ine gore
# tasinan dosyayi geri tasir, silinen/degistirilen dosyayi yedekten geri kopyalar.
function Invoke-AORemoteFileRollback {
    param([string]$BasePath)
    $Runs = @(Get-ChildItem -LiteralPath (Join-Path $BasePath 'FileRollbacks') -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($Runs.Count -eq 0) { Write-Host 'File rollback yedegi bulunamadi.' -ForegroundColor Yellow; return }
    for ($Index=0;$Index -lt $Runs.Count;$Index++) { Write-Host ("{0} - {1}" -f ($Index+1),$Runs[$Index].Name) }
    $Choice=(Read-Host 'Rollback numarasi (0=iptal)').Trim()
    if($Choice -eq '0'){
        return
    }
    if($Choice -notmatch '^\d+$' -or [int]$Choice -lt 1 -or [int]$Choice -gt $Runs.Count){
        Write-Host 'Gecersiz secim.' -ForegroundColor Yellow
        return
    }
    $Manifest=Join-Path $Runs[[int]$Choice-1].FullName 'manifest.csv'
    if(-not(Test-Path -LiteralPath $Manifest -PathType Leaf)){
        Write-Host 'Manifest bulunamadi.' -ForegroundColor Red
        return
    }
    if((Read-Host 'Rollback icin ROLLBACK yazin').Trim().ToUpperInvariant() -ne 'ROLLBACK'){
        return
    }
    foreach($Row in @(Import-Csv -LiteralPath $Manifest -Delimiter ';')){
        try{
            if($Row.Action -eq 'Move'){
                if(-not(Test-Path -LiteralPath $Row.ChangedPath -PathType Leaf)){
                    throw "Moved file is missing: $($Row.ChangedPath)"
                }
                $OriginalParent=Split-Path -Parent $Row.OriginalPath
                if(-not(Test-Path -LiteralPath $OriginalParent -PathType Container)){
                    New-Item -ItemType Directory -Path $OriginalParent -Force -ErrorAction Stop|Out-Null
                }
                Move-Item -LiteralPath $Row.ChangedPath -Destination $Row.OriginalPath -Force -ErrorAction Stop
            }else{
                if(-not(Test-Path -LiteralPath $Row.BackupPath -PathType Leaf)){
                    throw "Rollback backup is missing: $($Row.BackupPath)"
                }
                Copy-Item -LiteralPath $Row.BackupPath -Destination $Row.OriginalPath -Force -ErrorAction Stop
            }
            Write-Host "$($Row.ComputerName) : ROLLBACK OK" -ForegroundColor Green
        }catch{
            Write-Host "$($Row.ComputerName) : ROLLBACK HATA | $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# ====================================================================
# PULL / BACKUP / DELETE / PUSH / COMPARE CEKIRDEK FONKSIYONLARI
# ====================================================================
#
# PULL: hedefteki dosya/klasor/joker eslesmelerini PulledFiles\<PC>\<Klasor>\ altina kopyalar.
function Copy-AORemoteItemToLocal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    $Matches = @(Get-AORemoteMatches -ComputerName $ComputerName -TargetPath $SourcePath -RecursiveWildcard)
    if ($Matches.Count -eq 0) {
        return [PSCustomObject]@{ Success = $false; ItemCount = 0; Destination = ''; ErrorDetail = 'Kaynak bulunamadi.' }
    }

    $HasWildcard = Test-AOContainsWildcard -Path $SourcePath
    if (-not $HasWildcard -and $Matches.Count -eq 1 -and $Matches[0].PSIsContainer) {
        $ContainerName = [string]$Matches[0].Name
    }
    else {
        $ContainerName = Get-AOSourceContainerName -Path $SourcePath
    }
    $ComputerRoot = Join-Path $DestinationRoot $ComputerName
    $ContainerRoot = Join-Path $ComputerRoot $ContainerName
    New-Item -ItemType Directory -Path $ContainerRoot -Force | Out-Null

    # Klasor direkt verildiyse PulledFiles\PC\Klasor\... yapisini koru;
    # PulledFiles\PC\Klasor\Klasor gibi duplicate klasor olusturma.
    if (-not $HasWildcard -and $Matches.Count -eq 1 -and $Matches[0].PSIsContainer) {
        $RemoteBase = $Matches[0].FullName
        $Matches = @(Get-ChildItem -LiteralPath $RemoteBase -Force -ErrorAction Stop)
        if ($Matches.Count -eq 0) {
            return [PSCustomObject]@{ Success = $true; ItemCount = 0; Destination = $ContainerRoot; ErrorDetail = '' }
        }
    }
    else {
        $LocalBase = if ($HasWildcard) { Get-AOWildcardBasePath -Path $SourcePath } else { Split-Path -Path $SourcePath -Parent }
        if ([string]::IsNullOrWhiteSpace($LocalBase)) { $LocalBase = $SourcePath }
        $RemoteBase = ConvertTo-AORemoteAdminPath -ComputerName $ComputerName -LocalPath $LocalBase
    }

    $Copied = 0
    foreach ($Item in $Matches) {
        try {
            $Relative = Get-AORelativePath -BasePath $RemoteBase -FullPath $Item.FullName
            if ([string]::IsNullOrWhiteSpace($Relative)) { $Relative = $Item.Name }
            $Destination = Join-Path $ContainerRoot $Relative
            $DestinationParent = Split-Path -Path $Destination -Parent
            if (-not (Test-Path -LiteralPath $DestinationParent)) {
                New-Item -ItemType Directory -Path $DestinationParent -Force | Out-Null
            }

            if ($Item.PSIsContainer) {
                Copy-Item -LiteralPath $Item.FullName -Destination $Destination -Recurse -Force -ErrorAction Stop
                $Copied += @(Get-ChildItem -LiteralPath $Item.FullName -File -Recurse -ErrorAction SilentlyContinue).Count
            }
            else {
                Copy-Item -LiteralPath $Item.FullName -Destination $Destination -Force -ErrorAction Stop
                $Copied++
            }
        }
        catch {
            return [PSCustomObject]@{ Success = $false; ItemCount = $Copied; Destination = $ContainerRoot; ErrorDetail = $_.Exception.Message }
        }
    }

    return [PSCustomObject]@{ Success = $true; ItemCount = $Copied; Destination = $ContainerRoot; ErrorDetail = '' }
}

# SILME YEDEGI: her eslesen oge Robocopy ile DeleteBackups\<ID>_Delete\<PC>\<Surucu>\... altina kopyalanir.
# Sonra kaynak ve yedek snapshot'lari karsilastirilir; yedek sonrasi kaynak degistiyse
# silme IPTAL edilir ve eksik yedek temizlenir.
function Backup-AORemoteItemsForDelete {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$BackupRunRoot,
        [Parameter(Mandatory = $true)]$Preflight
    )

    $ClientBackupRoot = Join-Path $BackupRunRoot $ComputerName
    $Entries = @()

    if (-not [bool]$Preflight.Eligible) {
        return [PSCustomObject]@{
            Success=$false; ItemCount=0; Entries=@(); BackupPath=$ClientBackupRoot; Verified=$false;
            SourceStable=$false; RobocopyExitCodes=''; Status='PreflightNotEligible'; ErrorDetail=[string]$Preflight.ErrorDetail
        }
    }

    $Robocopy = Get-Command -Name 'robocopy.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $Robocopy) {
        return [PSCustomObject]@{
            Success=$false; ItemCount=0; Entries=@(); BackupPath=$ClientBackupRoot; Verified=$false;
            SourceStable=$false; RobocopyExitCodes=''; Status='RobocopyMissing'; ErrorDetail='robocopy.exe bulunamadi; guvenli delete backup yapilmayacak.'
        }
    }

    try {
        if (-not (Test-Path -LiteralPath $ClientBackupRoot)) {
            New-Item -ItemType Directory -Path $ClientBackupRoot -Force -ErrorAction Stop | Out-Null
        }

        $ExitCodes = New-Object System.Collections.Generic.List[int]

        foreach ($Item in @($Preflight.Items)) {
            $OriginalLocal = $Item.FullName -replace ('^\\\\' + [regex]::Escape($ComputerName) + '\\([A-Za-z])\$\\'), '$1:\'
            $Parts = Get-AOLocalPathParts -Path $OriginalLocal
            $BackupPath = Join-Path $ClientBackupRoot (Join-Path $Parts.Drive $Parts.Rest)
            $BackupParent = Split-Path -Path $BackupPath -Parent
            if (-not (Test-Path -LiteralPath $BackupParent)) {
                New-Item -ItemType Directory -Path $BackupParent -Force -ErrorAction Stop | Out-Null
            }

            if ($Item.PSIsContainer) {
                if (-not (Test-Path -LiteralPath $BackupPath)) {
                    New-Item -ItemType Directory -Path $BackupPath -Force -ErrorAction Stop | Out-Null
                }
                $RoboArgs = @(
                    [string]$Item.FullName,
                    [string]$BackupPath,
                    '/E', '/COPY:DAT', '/DCOPY:DAT',
                    ("/R:{0}" -f $script:AOFileOpsRobocopyRetryCount),
                    ("/W:{0}" -f $script:AOFileOpsRobocopyWaitSeconds),
                    '/XJ', '/NP', '/NFL', '/NDL', '/NJH', '/NJS'
                )
            }
            else {
                $SourceParent = Split-Path -Path $Item.FullName -Parent
                $RoboArgs = @(
                    [string]$SourceParent,
                    [string]$BackupParent,
                    [string]$Item.Name,
                    '/COPY:DAT',
                    ("/R:{0}" -f $script:AOFileOpsRobocopyRetryCount),
                    ("/W:{0}" -f $script:AOFileOpsRobocopyWaitSeconds),
                    '/NP', '/NFL', '/NDL', '/NJH', '/NJS'
                )
            }

            $null = & $Robocopy.Source @RoboArgs 2>&1
            [int]$RoboExitCode = $LASTEXITCODE
            [void]$ExitCodes.Add($RoboExitCode)

            # Robocopy 0-7 basari/uyari; 8+ gercek failure'dir.
            if ($RoboExitCode -ge 8) {
                throw "Robocopy backup basarisiz. Source='$($Item.FullName)' Destination='$BackupPath' ExitCode=$RoboExitCode"
            }

            if (-not (Test-Path -LiteralPath $BackupPath)) {
                throw "Backup hedefi olusmadi: $BackupPath"
            }

            $Entries += [PSCustomObject]@{
                ComputerName      = $ComputerName
                OriginalPath      = $OriginalLocal
                BackupPath        = $BackupPath
                ItemType          = $(if ($Item.PSIsContainer) { 'Directory' } else { 'File' })
                BackupStatus      = 'Success'
                BackupMethod      = 'Robocopy'
                RobocopyExitCode  = $RoboExitCode
                VerificationStatus = 'Pending'
                ErrorDetail       = ''
            }
        }

        # Her top-level kaynak ayri dogrulanir. Bu yapi recursive wildcard ile farkli
        # klasorlerde ayni isimli dosyalar olsa bile path-collision riskini engeller.
        foreach ($Entry in $Entries) {
            $RemoteOriginal = ConvertTo-AORemoteAdminPath -ComputerName $ComputerName -LocalPath ([string]$Entry.OriginalPath)
            $SourceVerifyItem = Get-Item -LiteralPath $RemoteOriginal -Force -ErrorAction Stop
            $BackupVerifyItem = Get-Item -LiteralPath ([string]$Entry.BackupPath) -Force -ErrorAction Stop

            $SourceVerifySnapshot = Get-AOItemSetSnapshot -Items @($SourceVerifyItem) -KeyMode 'Name'
            $BackupVerifySnapshot = Get-AOItemSetSnapshot -Items @($BackupVerifyItem) -KeyMode 'Name'

            if ($SourceVerifySnapshot.ReparsePointCount -gt 0 -or $BackupVerifySnapshot.ReparsePointCount -gt 0) {
                throw "Backup dogrulamasinda reparse point bulundu. Source='$($Entry.OriginalPath)'"
            }
            if (-not [string]::Equals([string]$SourceVerifySnapshot.StructureHash, [string]$BackupVerifySnapshot.StructureHash, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Backup dogrulamasi basarisiz. Source='$($Entry.OriginalPath)' SourceFile=$($SourceVerifySnapshot.FileCount) SourceDir=$($SourceVerifySnapshot.DirectoryCount) SourceByte=$($SourceVerifySnapshot.TotalBytes) BackupFile=$($BackupVerifySnapshot.FileCount) BackupDir=$($BackupVerifySnapshot.DirectoryCount) BackupByte=$($BackupVerifySnapshot.TotalBytes)"
            }
            $Entry.VerificationStatus = 'Verified'
        }

        # Backup bittikten sonra kaynak yeniden taranir. Kaynak degistiyse backup artik
        # delete icin guvenilir snapshot degildir; silme kesinlikle yapilmaz.
        $SourceAfterBackup = Get-AODeletePreflight -ComputerName $ComputerName -TargetPath $TargetPath
        if (-not [bool]$SourceAfterBackup.Eligible) {
            throw "Backup sonrasi kaynak tekrar dogrulanamadi: $($SourceAfterBackup.Status) | $($SourceAfterBackup.ErrorDetail)"
        }
        if (-not [string]::Equals([string]$SourceAfterBackup.StateHash, [string]$Preflight.StateHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Kaynak backup sirasinda degisti. Guvenlik nedeniyle delete iptal edildi.'
        }

        return [PSCustomObject]@{
            Success=$true; ItemCount=$Entries.Count; Entries=$Entries; BackupPath=$ClientBackupRoot; Verified=$true;
            SourceStable=$true; RobocopyExitCodes=($ExitCodes.ToArray() -join ','); Status='Verified'; ErrorDetail=''
        }
    }
    catch {
        $ErrorText = $_.Exception.Message
        # Delete yapilmadigi icin eksik/guvenilmez backup'i restore listesinde birakma.
        try {
            if (Test-Path -LiteralPath $ClientBackupRoot) {
                Remove-Item -LiteralPath $ClientBackupRoot -Recurse -Force -ErrorAction Stop
            }
        }
        catch {
            $ErrorText += " | Eksik backup temizlenemedi: $($_.Exception.Message)"
        }

        return [PSCustomObject]@{
            Success=$false; ItemCount=$Entries.Count; Entries=@(); BackupPath=$ClientBackupRoot; Verified=$false;
            SourceStable=$false; RobocopyExitCodes=''; Status='BackupFailed'; ErrorDetail=$ErrorText
        }
    }
}

# SILME: hemen oncesinde ikinci kez kontrol (StateHash ayni olmali), sonra en derinden
# baslayarak silinir ve desen tekrar taranarak hicbir sey kalmadigi dogrulanir.
function Remove-AORemoteItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)]$Preflight
    )

    # Delete'den hemen once ikinci stability check. Wildcard'i yeniden resolve edip yeni
    # eklenen bir ogeyi yedeksiz silmemek icin state hash ayni olmak zorundadir.
    $Current = Get-AODeletePreflight -ComputerName $ComputerName -TargetPath $TargetPath
    if (-not [bool]$Current.Eligible) {
        return [PSCustomObject]@{ Success=$false; Status='PreDeleteValidationFailed'; ItemCount=0; RemainingCount=0; Verified=$false; ErrorDetail=("Delete oncesi kaynak dogrulanamadi: {0} | {1}" -f $Current.Status, $Current.ErrorDetail) }
    }
    if (-not [string]::Equals([string]$Current.StateHash, [string]$Preflight.StateHash, [System.StringComparison]::OrdinalIgnoreCase)) {
        return [PSCustomObject]@{ Success=$false; Status='SourceChangedBeforeDelete'; ItemCount=0; RemainingCount=$Current.MatchedItemCount; Verified=$false; ErrorDetail='Kaynak backup sonrasi degisti; yedeksiz veri silmemek icin delete iptal edildi.' }
    }

    $Deleted = 0
    foreach ($Item in @($Current.Items | Sort-Object { $_.FullName.Length } -Descending)) {
        try {
            # Fresh FileSystemInfo kullan; stale preflight object'i ile delete yapma.
            $FreshItem = Get-Item -LiteralPath $Item.FullName -Force -ErrorAction Stop
            Remove-Item -LiteralPath $FreshItem.FullName -Recurse -Force -ErrorAction Stop
            $Deleted++
        }
        catch {
            $Remaining = @(Get-AORemoteMatches -ComputerName $ComputerName -TargetPath $TargetPath -RecursiveWildcard)
            return [PSCustomObject]@{
                Success=$false; Status=$(if ($Deleted -gt 0) { 'PartialFailure' } else { 'Failed' });
                ItemCount=$Deleted; RemainingCount=$Remaining.Count; Verified=$false; ErrorDetail=$_.Exception.Message
            }
        }
    }

    $RemainingItems = @(Get-AORemoteMatches -ComputerName $ComputerName -TargetPath $TargetPath -RecursiveWildcard)
    if ($RemainingItems.Count -gt 0) {
        return [PSCustomObject]@{
            Success=$false; Status='PostDeleteVerificationFailed'; ItemCount=$Deleted; RemainingCount=$RemainingItems.Count;
            Verified=$false; ErrorDetail="Delete sonrasi hedef pattern halen $($RemainingItems.Count) oge donduruyor."
        }
    }

    return [PSCustomObject]@{ Success=$true; Status='Success'; ItemCount=$Deleted; RemainingCount=0; Verified=$true; ErrorDetail='' }
}

# PUSH: yerel/UNC dosya-klasor-joker kaynagini hedef klasore kopyalar.
# Overwrite kapaliysa hedefte ayni adli oge atlanir (Skipped).
function Copy-AOLocalItemToRemote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$TargetDirectory,
        [Parameter(Mandatory = $true)][bool]$Overwrite
    )

    $Sources = @()
    if (Test-AOContainsWildcard -Path $SourcePath) {
        $Sources = @(Get-ChildItem -Path $SourcePath -Force -ErrorAction Stop)
    }
    elseif (Test-Path -LiteralPath $SourcePath) {
        $Sources = @(Get-Item -LiteralPath $SourcePath -Force -ErrorAction Stop)
    }
    else {
        return [PSCustomObject]@{ Success = $false; Copied = 0; Skipped = 0; ErrorDetail = 'Lokal kaynak bulunamadi.' }
    }

    $RemoteTarget = ConvertTo-AORemoteAdminPath -ComputerName $ComputerName -LocalPath $TargetDirectory
    if (-not (Test-Path -LiteralPath $RemoteTarget -PathType Container)) {
        New-Item -ItemType Directory -Path $RemoteTarget -Force -ErrorAction Stop | Out-Null
    }

    $Copied = 0
    $Skipped = 0
    foreach ($Source in $Sources) {
        $Destination = Join-Path $RemoteTarget $Source.Name
        if ((Test-Path -LiteralPath $Destination) -and -not $Overwrite) {
            $Skipped++
            continue
        }

        if ($Source.PSIsContainer) {
            if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
                New-Item -ItemType Directory -Path $Destination -Force | Out-Null
            }
            $Children = @(Get-ChildItem -LiteralPath $Source.FullName -Force -ErrorAction Stop)
            foreach ($Child in $Children) {
                $ChildDestination = Join-Path $Destination $Child.Name
                if ((Test-Path -LiteralPath $ChildDestination) -and -not $Overwrite) {
                    $Skipped++
                    continue
                }
                Copy-Item -LiteralPath $Child.FullName -Destination $ChildDestination -Recurse -Force:$Overwrite -ErrorAction Stop
                $Copied++
            }
        }
        else {
            Copy-Item -LiteralPath $Source.FullName -Destination $Destination -Force:$Overwrite -ErrorAction Stop
            $Copied++
        }
    }

    return [PSCustomObject]@{ Success = $true; Copied = $Copied; Skipped = $Skipped; ErrorDetail = '' }
}

# COMPARE: referans dosya ile hedef dosyayi SHA256, boyut ve son yazma zamanina gore karsilastirir.
function Compare-AORemoteFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][string]$ReferenceFile,
        [Parameter(Mandatory = $true)][string]$TargetFile
    )

    if (-not (Test-Path -LiteralPath $ReferenceFile -PathType Leaf)) {
        throw "Referans dosyasi bulunamadi: $ReferenceFile"
    }
    if (Test-AOContainsWildcard -Path $TargetFile) {
        throw 'Compare operasyonunda hedef path wildcard iceremez; tek dosya verilmelidir.'
    }

    $ReferenceItem = Get-Item -LiteralPath $ReferenceFile -Force -ErrorAction Stop
    $ReferenceHash = (Get-FileHash -LiteralPath $ReferenceFile -Algorithm SHA256 -ErrorAction Stop).Hash
    $RemoteFile = ConvertTo-AORemoteAdminPath -ComputerName $ComputerName -LocalPath $TargetFile

    if (-not (Test-Path -LiteralPath $RemoteFile -PathType Leaf)) {
        return [PSCustomObject]@{
            Status='Bulunamadi'; ReferenceHash=$ReferenceHash; RemoteHash=''; HashEsit=$false;
            ReferenceSize=$ReferenceItem.Length; RemoteSize=''; SizeEsit=$false;
            ReferenceModified=$ReferenceItem.LastWriteTime; RemoteModified=''; ModifiedEsit=$false; ErrorDetail='Hedef dosya bulunamadi.'
        }
    }

    $RemoteItem = Get-Item -LiteralPath $RemoteFile -Force -ErrorAction Stop
    $RemoteHash = (Get-FileHash -LiteralPath $RemoteFile -Algorithm SHA256 -ErrorAction Stop).Hash
    $HashEqual = [string]::Equals($ReferenceHash, $RemoteHash, [System.StringComparison]::OrdinalIgnoreCase)
    $SizeEqual = ([Int64]$ReferenceItem.Length -eq [Int64]$RemoteItem.Length)
    $ModifiedEqual = ($ReferenceItem.LastWriteTimeUtc.Ticks -eq $RemoteItem.LastWriteTimeUtc.Ticks)

    return [PSCustomObject]@{
        Status            = $(if ($HashEqual -and $SizeEqual -and $ModifiedEqual) { 'Esit' } else { 'Farkli' })
        ReferenceHash     = $ReferenceHash
        RemoteHash        = $RemoteHash
        HashEsit          = $HashEqual
        ReferenceSize     = $ReferenceItem.Length
        RemoteSize        = $RemoteItem.Length
        SizeEsit          = $SizeEqual
        ReferenceModified = $ReferenceItem.LastWriteTime
        RemoteModified    = $RemoteItem.LastWriteTime
        ModifiedEsit      = $ModifiedEqual
        ErrorDetail       = ''
    }
}

# ====================================================================
# PAKET LOG TOPLAMA / TEMIZLEME (MD_Script $PackageScript worker'i cagirir)
# ====================================================================
#
# Hedefin C:\Windows\Temp klasorunde son N dakikada olusan/degisen .log/.txt dosyalarini
# PulledLogs\<PC>\<OperationID_Operasyon>\ altina kopyalar. Sonuc: Success / NoRecentLogs / Failed.
function Get-AORecentLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$OperationName,
        [Parameter(Mandatory = $true)][string]$OperationID,
        [int]$LookbackMinutes = 10,
        [string]$CollectionGroup = ''
    )

    $Result = [ordered]@{
        ComputerName = $ComputerName
        Success      = $false
        Status       = 'Failed'
        FileCount    = 0
        Destination  = ''
        ErrorDetail  = ''
    }

    try {
        $RemoteTemp = ConvertTo-AORemoteAdminPath -ComputerName $ComputerName -LocalPath 'C:\Windows\Temp'
        if (-not (Test-Path -LiteralPath $RemoteTemp -PathType Container)) {
            throw 'C:\Windows\Temp admin-share uzerinden erisilebilir degil.'
        }

        $SafeLookbackMinutes = [int]$LookbackMinutes
        if ($SafeLookbackMinutes -lt 0) {
            $SafeLookbackMinutes = -$SafeLookbackMinutes
        }

        $Cutoff = (Get-Date).AddMinutes(-1 * $SafeLookbackMinutes)
        $Files = @(
            Get-ChildItem -LiteralPath $RemoteTemp -File -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object {
                    ($_.Extension -ieq '.log' -or $_.Extension -ieq '.txt') -and
                    ($_.CreationTime -ge $Cutoff -or $_.LastWriteTime -ge $Cutoff)
                }
        )

        $SafeOperation = ($OperationName -creplace '[^A-Za-z0-9._-]', '_')
        $CollectionRoot=Join-Path $BasePath 'PulledLogs'
        if($CollectionGroup){
            if($CollectionGroup -cnotmatch '^[A-Za-z0-9_-]+$'){throw 'Invalid log collection group.'}
            $CollectionRoot=Join-Path $CollectionRoot $CollectionGroup
        }
        $Destination = Join-Path (Join-Path $CollectionRoot $ComputerName) ("{0}_{1}" -f $OperationID, $SafeOperation)
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null

        foreach ($File in $Files) {
            $Relative = Get-AORelativePath -BasePath $RemoteTemp -FullPath $File.FullName
            $Target = Join-Path $Destination $Relative
            $Parent = Split-Path -Path $Target -Parent
            if (-not (Test-Path -LiteralPath $Parent)) { New-Item -ItemType Directory -Path $Parent -Force | Out-Null }
            Copy-Item -LiteralPath $File.FullName -Destination $Target -Force -ErrorAction Stop
        }

        $Result.Success     = $true
        $Result.Status      = $(if ($Files.Count -gt 0) { 'Success' } else { 'NoRecentLogs' })
        $Result.FileCount   = $Files.Count
        $Result.Destination = $Destination
    }
    catch {
        $Result.ErrorDetail = $_.Exception.Message
    }

    return [PSCustomObject]$Result
}

# Log temizleme guvenlik listeleri: genel kullanici adlari reddedilir, sistem log adlari korunur,
# tek seferde en fazla 50 dosya silinebilir.
$script:AOLogCleanupBlockedUserNames = @(
    'system','admin','administrator','administrators','user','users','test','temp','tmp','windows','default','public','guest','service','services',
    'network','local','localadmin','setup','install','installer','installers','logs','log','domain','root','backup','sccm','ccm','microsoft','program',
    'files','data','owner','support','helpdesk','operator','sysadmin','everyone','nobody','client','server','package','packages','update','updates'
)
$script:AOLogCleanupProtectedNamePattern = '^(CBS|DISM|MpCmdRun|MpSigStub|WindowsUpdate|ReportingEvents|CCM|setupapi|netsetup|PSEXESVC)'
$script:AOLogCleanupMaxFiles = 50

# Kullanici adi dosya adi filtresi olarak kullanilacagi icin yeterince ozgul olmali.
function Test-AOLogCleanupUserName {
    # The user name becomes a file-name filter, so it has to be specific. Anything generic, short or containing
    # wildcard/path characters is refused (a filter like *admin* could match unrelated files).
    [CmdletBinding()]
    param([string]$UserName)

    $Name = ([string]$UserName).Trim()
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return [PSCustomObject]@{ Valid = $false; Reason = 'Kullanici adi bos.' }
    }
    if ($Name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{3,62}$') {
        return [PSCustomObject]@{ Valid = $false; Reason = "Kullanici adi guvenli bir desen degil (en az 4 karakter; yalnizca harf, rakam, nokta, tire, alt cizgi): '$Name'" }
    }
    if ($Name -match '\.\.') {
        return [PSCustomObject]@{ Valid = $false; Reason = "Kullanici adi '..' iceremez: '$Name'" }
    }
    if ($Name -notmatch '[A-Za-z]') {
        return [PSCustomObject]@{ Valid = $false; Reason = "Kullanici adi en az bir harf icermeli: '$Name'" }
    }
    if ($script:AOLogCleanupBlockedUserNames -contains $Name.ToLowerInvariant()) {
        return [PSCustomObject]@{ Valid = $false; Reason = "Kullanici adi cok genel oldugu icin (yanlis dosyalari eslestirebilir) kullanilmaz: '$Name'" }
    }
    return [PSCustomObject]@{ Valid = $true; Reason = '' }
}

# Toplanan loglardan kullanici adini iceren dosyalari HEDEFTE siler (cok katmanli guvenlik ile).
function Remove-AOCollectedUserLogs {
    # Deletes, on the target, ONLY files that (a) were just collected into $CollectedRoot, (b) sit directly in
    # C:\Windows\Temp (never subfolders), (c) are .log/.txt files whose name contains the user name, (d) are not on the
    # protected list, (e) are byte-identical to the collected copy, and (f) are plain files (no folders, no reparse points).
    # Nothing is deleted when the user name is not specific enough or more than $script:AOLogCleanupMaxFiles files match.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$CollectedRoot
    )

    $Result = [ordered]@{ Status = 'NotRun'; DeletedCount = 0; SkippedCount = 0; Detail = '' }
    try {
        $Check = Test-AOLogCleanupUserName -UserName $UserName
        if (-not $Check.Valid) {
            $Result.Status = 'Skipped'
            $Result.Detail = $Check.Reason
            return [PSCustomObject]$Result
        }
        $Name = $UserName.Trim()

        if ([string]::IsNullOrWhiteSpace($CollectedRoot) -or -not (Test-Path -LiteralPath $CollectedRoot -PathType Container)) {
            $Result.Status = 'Skipped'
            $Result.Detail = 'Toplanan log klasoru bulunamadi; hicbir sey silinmedi.'
            return [PSCustomObject]$Result
        }

        # The user name must appear as a separate word: 'yigitery0' must not match the logs of 'yigitery01' or 'xyigitery0'.
        $NamePattern = '(?<![A-Za-z0-9])' + [regex]::Escape($Name) + '(?![A-Za-z0-9])'
        $Candidates = @(
            Get-ChildItem -LiteralPath $CollectedRoot -File -Force -ErrorAction Stop | Where-Object {
                ($_.Extension -ieq '.log' -or $_.Extension -ieq '.txt') -and
                [regex]::IsMatch($_.Name, $NamePattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant) -and
                $_.Name -notmatch $script:AOLogCleanupProtectedNamePattern -and
                [System.IO.Path]::GetFileName($_.Name) -ceq $_.Name
            } | Sort-Object Name
        )
        if ($Candidates.Count -eq 0) {
            $Result.Status = 'NothingToClean'
            $Result.Detail = "Kullanici adini ('$Name') iceren, toplanmis log yok."
            return [PSCustomObject]$Result
        }
        if ($Candidates.Count -gt $script:AOLogCleanupMaxFiles) {
            $Result.Status = 'Skipped'
            $Result.SkippedCount = $Candidates.Count
            $Result.Detail = "Eslesen dosya sayisi ($($Candidates.Count)) guvenlik sinirini ($($script:AOLogCleanupMaxFiles)) asiyor; hicbir sey silinmedi."
            return [PSCustomObject]$Result
        }

        $RemoteTemp = ConvertTo-AORemoteAdminPath -ComputerName $ComputerName -LocalPath 'C:\Windows\Temp'
        if (-not (Test-Path -LiteralPath $RemoteTemp -PathType Container)) {
            $Result.Status = 'Failed'
            $Result.Detail = 'C:\Windows\Temp admin-share uzerinden erisilebilir degil.'
            return [PSCustomObject]$Result
        }

        $Deleted = New-Object System.Collections.Generic.List[string]
        $Skipped = New-Object System.Collections.Generic.List[string]
        # Her aday icin: hedefte var mi, duz dosya mi, boyut ve SHA256 toplanan kopyayla ayni mi -> sil.
        foreach ($Local in $Candidates) {
            $Remote = Join-Path $RemoteTemp $Local.Name
            try {
                if (-not (Test-Path -LiteralPath $Remote -PathType Leaf)) {
                    $Skipped.Add("$($Local.Name) (hedefte yok)")
                    continue
                }
                $Item = Get-Item -LiteralPath $Remote -Force -ErrorAction Stop
                if ($Item.PSIsContainer -or ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                    $Skipped.Add("$($Local.Name) (dosya degil/reparse point)")
                    continue
                }
                if ([int64]$Item.Length -ne [int64]$Local.Length) {
                    $Skipped.Add("$($Local.Name) (toplamadan sonra degismis)")
                    continue
                }
                if ((Get-FileHash -LiteralPath $Remote -Algorithm SHA256 -ErrorAction Stop).Hash -ne (Get-FileHash -LiteralPath $Local.FullName -Algorithm SHA256 -ErrorAction Stop).Hash) {
                    $Skipped.Add("$($Local.Name) (icerik toplanan kopyadan farkli)")
                    continue
                }
                Remove-Item -LiteralPath $Remote -Force -ErrorAction Stop
                if (Test-Path -LiteralPath $Remote) { $Skipped.Add("$($Local.Name) (silinemedi)"); continue }
                $Deleted.Add($Local.Name)
            }
            catch { $Skipped.Add("$($Local.Name) ($($_.Exception.Message))") }
        }
        $Result.DeletedCount = $Deleted.Count
        $Result.SkippedCount = $Skipped.Count
        $Result.Status = if ($Deleted.Count -gt 0 -and $Skipped.Count -eq 0) { 'Success' } elseif ($Deleted.Count -gt 0) { 'Partial' } else { 'Failed' }
        $Parts = @()
        if ($Deleted.Count -gt 0) { $Parts += ('Silindi: ' + ($Deleted -join ', ')) }
        if ($Skipped.Count -gt 0) { $Parts += ('Silinmedi: ' + ($Skipped -join ', ')) }
        $Result.Detail = $Parts -join ' | '
    }
    catch { $Result.Status = 'Failed'; $Result.Detail = $_.Exception.Message }
    return [PSCustomObject]$Result
}

# --- CSV YARDIMCILARI ---
# CSV dosyasinin baslik satirindaki kolon adlari.
function Get-AOCsvHeaderNames {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $HeaderLine = Get-Content -LiteralPath $Path -TotalCount 1 -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace([string]$HeaderLine)) { return @() }

    return @(
        ([string]$HeaderLine -split ';') |
            ForEach-Object { ([string]$_).Trim().Trim([char]34).Replace('""', '"') }
    )
}

# CSV'ye satir ekler; kolonlar degistiyse eski kayitlari kaybetmeden kolon birlesimiyle yeniden yazar.
function Add-AOSchemaSafeCsvRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows
    )

    $Rows = @($Rows)
    if ($Rows.Count -eq 0) { return [PSCustomObject]@{ SchemaMigrated=$false; RowCount=0 } }

    $NewHeaders = @($Rows[0].PSObject.Properties.Name)
    if (-not (Test-Path -LiteralPath $Path) -or (Get-Item -LiteralPath $Path).Length -eq 0) {
        $Rows | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8 -Delimiter ';' -ErrorAction Stop
        return [PSCustomObject]@{ SchemaMigrated=$false; RowCount=$Rows.Count }
    }

    $ExistingHeaders = @(Get-AOCsvHeaderNames -Path $Path)
    $SameSchema = ($ExistingHeaders.Count -eq $NewHeaders.Count)
    if ($SameSchema) {
        for ($i = 0; $i -lt $ExistingHeaders.Count; $i++) {
            if (-not [string]::Equals($ExistingHeaders[$i], $NewHeaders[$i], [System.StringComparison]::Ordinal)) {
                $SameSchema = $false
                break
            }
        }
    }

    if ($SameSchema) {
        $Rows | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8 -Delimiter ';' -Append -ErrorAction Stop
        return [PSCustomObject]@{ SchemaMigrated=$false; RowCount=$Rows.Count }
    }

    # Schema degistiginde eski kayitlari kaybetmeden kolonlarin union'ini olustur.
    $AllHeaders = New-Object System.Collections.Generic.List[string]
    foreach ($Header in $ExistingHeaders) { if (-not $AllHeaders.Contains($Header)) { [void]$AllHeaders.Add($Header) } }
    foreach ($Header in $NewHeaders) { if (-not $AllHeaders.Contains($Header)) { [void]$AllHeaders.Add($Header) } }

    $ExistingRows = @(Import-Csv -LiteralPath $Path -Delimiter ';' -ErrorAction Stop)
    $CombinedRows = New-Object System.Collections.Generic.List[object]

    $RowsToNormalize = @($ExistingRows) + @($Rows)
    foreach ($SourceRow in $RowsToNormalize) {
        $Data = [ordered]@{}
        foreach ($Header in $AllHeaders) {
            $Property = $SourceRow.PSObject.Properties[$Header]
            $Data[$Header] = $(if ($null -ne $Property) { $Property.Value } else { '' })
        }
        [void]$CombinedRows.Add([PSCustomObject]$Data)
    }

    $TempPath = $Path + '.schema.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $CombinedRows.ToArray() | Export-Csv -LiteralPath $TempPath -NoTypeInformation -Encoding UTF8 -Delimiter ';' -ErrorAction Stop
        Move-Item -LiteralPath $TempPath -Destination $Path -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $TempPath) {
            Remove-Item -LiteralPath $TempPath -Force -ErrorAction SilentlyContinue
        }
    }

    return [PSCustomObject]@{ SchemaMigrated=$true; RowCount=$Rows.Count }
}

# Islem sonuclarini Logs\FileOperations\MD_File<Islem>.csv'ye ekler ve operasyon gecmisine yazar.
# Donus: yazilan CSV yolu (Runner sonuc satirlarini buradan okur).
function Add-AOFileOperationRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$OperationName,
        [Parameter(Mandatory = $true)][string]$OperationID,
        [Parameter(Mandatory = $true)][string]$OperationDate,
        [Parameter(Mandatory = $true)][string]$OperationTime,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows,
        [scriptblock]$TechnicalLogWriter,
        [scriptblock]$OperationHistoryWriter
    )

    $Rows = @($Rows)
    if ($Rows.Count -eq 0) { return '' }

    $FileOpsLogsPath = Join-Path (Join-Path $BasePath 'Logs') 'FileOperations'
    if (-not (Test-Path -LiteralPath $FileOpsLogsPath)) {
        New-Item -ItemType Directory -Path $FileOpsLogsPath -Force | Out-Null
    }

    $FileNameMap = @{
        Pull    = 'MD_FilePull.csv'
        Delete  = 'MD_FileDelete.csv'
        Push    = 'MD_FilePush.csv'
        Compare = 'MD_FileCompare.csv'
        Restore = 'MD_FileRestore.csv'
    }
    if (-not $FileNameMap.ContainsKey($OperationName)) { throw "Bilinmeyen file operation: $OperationName" }

    $ResultCsv = Join-Path $FileOpsLogsPath $FileNameMap[$OperationName]
    $ExportRows = @()
    foreach ($Row in $Rows) {
        $Data = [ordered]@{
            OperasyonTarihi = $OperationDate
            OperasyonSaati  = $OperationTime
            OperationID     = $OperationID
        }
        foreach ($Property in $Row.PSObject.Properties) {
            $Data[$Property.Name] = $Property.Value
        }
        $ExportRows += [PSCustomObject]$Data
    }

    $CsvWriteResult = Add-AOSchemaSafeCsvRows -Path $ResultCsv -Rows @($ExportRows | Sort-Object IstemciAdi)
    # Kumulatif gecmise (MD_File*.csv) ek olarak bu operasyona ait kucuk bir kopya da yazilir ve
    # DONUS DEGERI olarak o kullanilir. Boylece sonucu okuyan taraf (GUI Runner) her seferinde zamanla
    # buyuyen kumulatif dosyanin tamamini okumak zorunda kalmaz. Kumulatif dosya aynen korunur.
    $RunCsv = Join-Path $FileOpsLogsPath ('{0}_File{1}.csv' -f ($OperationID -creplace '[^A-Za-z0-9_-]', '_'), $OperationName)
    [void](Add-AOSchemaSafeCsvRows -Path $RunCsv -Rows @($ExportRows | Sort-Object IstemciAdi))
    if ($CsvWriteResult.SchemaMigrated -and $null -ne $TechnicalLogWriter) {
        & $TechnicalLogWriter -Level 'INFO' -Message "FILEOPS-SCHEMA-MIGRATION | Operation='$OperationName' | Csv='$ResultCsv'"
    }

    foreach ($Row in $Rows) {
        if ($null -eq $OperationHistoryWriter) { continue }

        $Description = switch ($OperationName) {
            'Pull'    { "Kaynak='$($Row.KaynakPath)' | LokalHedef='$($Row.LokalHedefPath)' | DosyaAdedi=$($Row.DosyaAdedi)" }
            'Delete'  { "Hedef='$($Row.HedefPath)' | Preflight=$($Row.PreflightDurumu) | File=$($Row.DosyaAdedi) | Dir=$($Row.KlasorAdedi) | Byte=$($Row.ToplamBoyutByte) | Backup=$($Row.BackupDurumu) | Verified=$($Row.BackupDogrulandi) | SourceStable=$($Row.KaynakStabil) | Silinen=$($Row.SilinenAdet) | DeleteVerify=$($Row.SilmeSonKontrol)" }
            'Push'    { "Kaynak='$($Row.KaynakPath)' | Hedef='$($Row.HedefPath)' | Overwrite=$($Row.Overwrite) | Kopyalanan=$($Row.KopyalananAdet) | Atlanan=$($Row.AtlananAdet)" }
            'Compare' { "Referans='$($Row.ReferansPath)' | Hedef='$($Row.HedefPath)' | HashEsit=$($Row.HashEsit) | SizeEsit=$($Row.SizeEsit) | ModifiedEsit=$($Row.ModifiedEsit)" }
            'Restore' { "Backup='$($Row.BackupPath)' | Hedef='$($Row.HedefPath)' | KaynakOperationID='$($Row.KaynakOperationID)'" }
            default   { '' }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$Row.HataDetayi)) { $Description += " | Hata=$($Row.HataDetayi)" }

        & $OperationHistoryWriter `
            -OperationID $OperationID `
            -OperationDate $OperationDate `
            -OperationTime $OperationTime `
            -IstemciAdi ([string]$Row.IstemciAdi) `
            -Modul 'FileOperations' `
            -Operasyon ("File{0}" -f $OperationName) `
            -Sonuc ([string]$Row.Durum) `
            -Aciklama $Description
    }

    if ($null -ne $TechnicalLogWriter) {
        & $TechnicalLogWriter -Level 'INFO' -Message "FILEOPS | OperationID='$OperationID' | Operation='$OperationName' | ResultCsv='$ResultCsv' | Entries=$($Rows.Count)"
    }

    return $RunCsv
}

# RESTORE (menu 5): DeleteBackups altindaki yedeklerden biri secilir (en yeni = 1),
# RESTORE onayi alinir ve manifest'teki her oge hedefteki asil yerine geri kopyalanir.
function Restore-AODeleteBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [string[]]$ReachableSystems,
        [Parameter(Mandatory = $true)][string]$OperationID,
        [Parameter(Mandatory = $true)][string]$OperationDate,
        [Parameter(Mandatory = $true)][string]$OperationTime,
        [scriptblock]$TechnicalLogWriter,
        [scriptblock]$OperationHistoryWriter
    )

    $BackupRoot = Join-Path $BasePath 'DeleteBackups'
    $Runs = @(Get-ChildItem -LiteralPath $BackupRoot -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($Runs.Count -eq 0) {
        Write-Host 'Restore edilebilir delete yedegi bulunamadi.' -ForegroundColor Yellow
        return
    }

    Write-Host ''
    Write-Host 'Mevcut delete yedekleri:' -ForegroundColor Cyan
    for ($i = 0; $i -lt $Runs.Count; $i++) {
        Write-Host ('{0} - {1} ({2})' -f ($i + 1), $Runs[$i].Name, $Runs[$i].LastWriteTime)
    }
    Write-Host ''

    $SelectedRun = $null
    while ($null -eq $SelectedRun) {
        $Raw = (Read-Host 'Restore edilecek yedek numarasi (iptal icin 0)').Trim()
        [int]$Index = -1
        if ([int]::TryParse($Raw, [ref]$Index)) {
            if ($Index -eq 0) { return }
            if ($Index -ge 1 -and $Index -le $Runs.Count) { $SelectedRun = $Runs[$Index - 1] }
        }
        if ($null -eq $SelectedRun) { Write-Host 'Gecersiz secim.' -ForegroundColor Yellow }
    }

    $Manifest = Join-Path $SelectedRun.FullName 'manifest.csv'
    if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) {
        Write-Host "Manifest bulunamadi: $Manifest" -ForegroundColor Red
        return
    }

    $Entries = @(Import-Csv -LiteralPath $Manifest -Delimiter ';')
    Write-Host "Restore kaydi: $($Entries.Count)" -ForegroundColor Cyan
    $Confirm = (Read-Host 'Restore islemi hedefte mevcut dosyalari overwrite edebilir. Devam etmek icin RESTORE yazin').Trim()
    if ($Confirm -ne 'RESTORE') {
        Write-Host 'Restore iptal edildi.' -ForegroundColor Yellow
        return $null
    }

    $SourceOperationID = $SelectedRun.Name -replace '_Delete$',''
    $Rows = @()

    foreach ($Entry in $Entries) {
        $ComputerName = [string]$Entry.ComputerName
        if ($ReachableSystems -notcontains $ComputerName) {
            Write-Host "$ComputerName : ERISILEMEDI/PCList disi - restore atlandi." -ForegroundColor Yellow
            $Rows += [PSCustomObject]@{ IstemciAdi=$ComputerName; KaynakOperationID=$SourceOperationID; BackupPath=[string]$Entry.BackupPath; HedefPath=[string]$Entry.OriginalPath; Overwrite='Evet'; Durum='Erisilemedi'; DosyaAdedi=0; HataDetayi='Istemci erisilebilir listesinde degil.' }
            continue
        }

        try {
            $RemoteTarget = ConvertTo-AORemoteAdminPath -ComputerName $ComputerName -LocalPath ([string]$Entry.OriginalPath)
            $BackupPath = [string]$Entry.BackupPath
            if (-not (Test-Path -LiteralPath $BackupPath)) { throw "Backup verisi bulunamadi: $BackupPath" }

            $Parent = Split-Path -Path $RemoteTarget -Parent
            if (-not (Test-Path -LiteralPath $Parent)) { New-Item -ItemType Directory -Path $Parent -Force | Out-Null }

            if ([string]$Entry.ItemType -eq 'Directory') {
                if (-not (Test-Path -LiteralPath $RemoteTarget -PathType Container)) {
                    New-Item -ItemType Directory -Path $RemoteTarget -Force | Out-Null
                }
                foreach ($Child in @(Get-ChildItem -LiteralPath $BackupPath -Force -ErrorAction Stop)) {
                    $ChildTarget = Join-Path $RemoteTarget $Child.Name
                    Copy-Item -LiteralPath $Child.FullName -Destination $ChildTarget -Recurse -Force -ErrorAction Stop
                }
            }
            else {
                Copy-Item -LiteralPath $BackupPath -Destination $RemoteTarget -Force -ErrorAction Stop
            }
            Write-Host "$ComputerName : RESTORE SUCCESS | $($Entry.OriginalPath)" -ForegroundColor Green
            $Rows += [PSCustomObject]@{ IstemciAdi=$ComputerName; KaynakOperationID=$SourceOperationID; BackupPath=$BackupPath; HedefPath=[string]$Entry.OriginalPath; Overwrite='Evet'; Durum='Success'; DosyaAdedi=1; HataDetayi='' }
        }
        catch {
            Write-Host "$ComputerName : RESTORE FAILED | $($Entry.OriginalPath) | $($_.Exception.Message)" -ForegroundColor Red
            $Rows += [PSCustomObject]@{ IstemciAdi=$ComputerName; KaynakOperationID=$SourceOperationID; BackupPath=[string]$Entry.BackupPath; HedefPath=[string]$Entry.OriginalPath; Overwrite='Evet'; Durum='Failed'; DosyaAdedi=0; HataDetayi=$_.Exception.Message }
            if ($null -ne $TechnicalLogWriter) {
                & $TechnicalLogWriter -Level 'ERROR' -Message "FILEOPS-RESTORE | OperationID='$OperationID' | $ComputerName | '$($Entry.OriginalPath)' | $($_.Exception.Message)"
            }
        }
    }

    $ResultCsv = ''
    if ($Rows.Count -gt 0) {
        $ResultCsv = Add-AOFileOperationRows -BasePath $BasePath -OperationName 'Restore' -OperationID $OperationID -OperationDate $OperationDate -OperationTime $OperationTime -Rows $Rows -TechnicalLogWriter $TechnicalLogWriter -OperationHistoryWriter $OperationHistoryWriter
        Write-Host "Restore sonucu CSV: $ResultCsv" -ForegroundColor Cyan
    }

    return [PSCustomObject]@{ Completed=$true; ResultCsv=$ResultCsv; Message='Restore tamamlandi.' }
}

# ====================================================================
# MENU GIRIS NOKTASI (Runner / MD_Script modul menusu cagirir)
# Secim 1-4 bir sonuc listesi ($Rows) uretir ve dongu sonunda CSV'ye yazilip donulur.
# Secim 5 (restore) kendi sonucunu dondurur; 6/7 islem sonrasi menuye geri doner.
# ====================================================================
function Invoke-AOFileOperationsMenu {
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
        [string]$PullGroup=''
    )

    Write-Host ''
    Write-Host 'FileOperations modulu baslatildi.' -ForegroundColor DarkCyan
    if ($null -ne $TechnicalLogWriter) {
        & $TechnicalLogWriter -Level 'INFO' -Message "FILEOPS-MENU-START | OperationID='$OperationID' | Systems=$($Systems.Count) | Reachable=$($ReachableSystems.Count)"
    }

    Initialize-AOFileOperations -BasePath $BasePath -TechnicalLogWriter $TechnicalLogWriter

    while ($true) {
        Write-Host ''
        Write-Host '============================================================' -ForegroundColor Cyan
        Write-Host ' DOSYA OPERASYONLARI' -ForegroundColor Cyan
        Write-Host '============================================================' -ForegroundColor Cyan
        Write-Host " Operation ID: $OperationID" -ForegroundColor DarkGray
        Write-Host '1 - Hedef bilgisayardan dosya/klasor cek (Pull)'
        Write-Host '2 - Hedef bilgisayarda dosya/klasor sil (Backup + Delete)'
        Write-Host '3 - Hedef bilgisayara dosya/klasor kopyala (Push)'
        Write-Host '4 - Hedef dosyayi referans dosya ile karsilastir (Hash/Size/Modified)'
        Write-Host '5 - Silme yedegini geri yukle (Restore)'
        Write-Host '6 - Path altindaki dosyalari listele ve islem yap (Pull/Move/Delete/Replace)'
        Write-Host '7 - File Operations rollback uygula'
        Write-Host 'H - Yardim / Path ornekleri'
        Write-Host '0 - Islemi bitir'
        Write-Host ''

        $Selection = (Read-Host 'Seciminiz').Trim().ToUpperInvariant()
        if ($Selection -eq 'H') { Show-AOFileOperationsHelp; continue }
        if ($Selection -eq '0') {
            return [PSCustomObject]@{ Completed=$true; ResultCsv=''; Message='Dosya operasyonlari sonlandirildi.' }
        }
        if ($Selection -eq '5') {
            $RestoreResult = Restore-AODeleteBackup -BasePath $BasePath -ReachableSystems $ReachableSystems -OperationID $OperationID -OperationDate $OperationDate -OperationTime $OperationTime -TechnicalLogWriter $TechnicalLogWriter -OperationHistoryWriter $OperationHistoryWriter
            if ($null -ne $RestoreResult) { return $RestoreResult }
            continue
        }
        if ($Selection -eq '6') {
            Invoke-AORemoteFileBrowseOperations -BasePath $BasePath -Systems $Systems -ReachableSystems $ReachableSystems -OperationID $OperationID
            continue
        }
        if ($Selection -eq '7') {
            Invoke-AORemoteFileRollback -BasePath $BasePath
            continue
        }
        if ($Selection -notin @('1','2','3','4')) { Write-Host 'Gecersiz secim.' -ForegroundColor Yellow; continue }

        $OperationName = ''
        $Rows = @()

        # 1 = PULL
        if ($Selection -eq '1') {
            $OperationName = 'Pull'
            Write-Host ''
            Write-Host 'Ornekler: C:\Temp\Test | C:\Temp\Test\* | C:\Windows\Temp\*.log | C:\Temp\abc.txt' -ForegroundColor DarkGray
            do {
                $TargetPath = (Read-Host 'Hedef PC kaynak path').Trim()
            } while ([string]::IsNullOrWhiteSpace($TargetPath))
            $DestinationRoot = Get-AOFilePullRoot $BasePath $PullGroup

            foreach ($ComputerName in $Systems) {
                if ($ReachableSystems -notcontains $ComputerName) {
                    $Rows += [PSCustomObject]@{ IstemciAdi=$ComputerName; KaynakPath=$TargetPath; LokalHedefPath=''; Durum='Erisilemedi'; DosyaAdedi=0; HataDetayi='Ping basarisiz.' }
                    continue
                }
                try {
                    $R = Copy-AORemoteItemToLocal -ComputerName $ComputerName -SourcePath $TargetPath -DestinationRoot $DestinationRoot
                    $Status = $(if ($R.Success) { 'Success' } else { 'Failed' })
                    Write-Host "$ComputerName : $Status | $($R.ItemCount) oge | $($R.Destination)" -ForegroundColor $(if ($R.Success) { 'Green' } else { 'Red' })
                    $Rows += [PSCustomObject]@{ IstemciAdi=$ComputerName; KaynakPath=$TargetPath; LokalHedefPath=$R.Destination; Durum=$Status; DosyaAdedi=$R.ItemCount; HataDetayi=$R.ErrorDetail }
                }
                catch {
                    Write-Host "$ComputerName : FAILED | $($_.Exception.Message)" -ForegroundColor Red
                    $Rows += [PSCustomObject]@{ IstemciAdi=$ComputerName; KaynakPath=$TargetPath; LokalHedefPath=''; Durum='Failed'; DosyaAdedi=0; HataDetayi=$_.Exception.Message }
                }
            }
        }
        # 2 = DELETE (korumali silme). Adimlar:
        #   a) yol normalize + genel koruma kontrolu
        #   b) her hedef icin koruma + preflight (snapshot)
        #   c) toplam ozet + DELETE onayi
        #   d) her uygun hedef icin: yedek -> manifest -> silme
        elseif ($Selection -eq '2') {
            $OperationName = 'Delete'
            Write-Host ''
            Write-Host 'Ornekler: C:\Temp\Test\abc.txt | C:\Temp\Test\* | C:\Temp\Test\*.log' -ForegroundColor DarkGray
            Write-Host 'Kritik rootlar (Orn: C:\Temp, C:\Windows, C:\ProgramData) dogrudan veya \* ile silinemez.' -ForegroundColor DarkYellow

            $TargetPath = ''
            while ([string]::IsNullOrWhiteSpace($TargetPath)) {
                $RawTargetPath = (Read-Host 'Hedef PC silinecek path').Trim()
                if ([string]::IsNullOrWhiteSpace($RawTargetPath)) { continue }
                try {
                    $TargetPath = ConvertTo-AODeleteTargetPath -Path $RawTargetPath
                }
                catch {
                    Write-Host "Gecersiz/guvensiz path: $($_.Exception.Message)" -ForegroundColor Red
                    $TargetPath = ''
                }
            }

            $GlobalProtectionReason = Get-AODeleteProtectionReason -Path $TargetPath
            if (-not [string]::IsNullOrWhiteSpace($GlobalProtectionReason)) {
                Write-Host "KRITIK PATH KORUMASI: '$TargetPath' silme operasyonuna kapali. $GlobalProtectionReason" -ForegroundColor Red
                $Rows = @()
                foreach ($ComputerName in $Systems) {
                    $Rows += [PSCustomObject]@{
                        IstemciAdi=$ComputerName; HedefPath=$TargetPath; PreflightDurumu='Blocked'; EslesenOge=0;
                        DosyaAdedi=0; KlasorAdedi=0; ToplamBoyutByte=0; ReparsePointAdedi=0;
                        BackupPath=''; BackupAdedi=0; BackupDurumu='NotStarted'; BackupDogrulandi='Hayir'; KaynakStabil='Hayir';
                        SilinenAdet=0; SilmeSonKontrol='NotStarted'; Durum='Blocked'; HataDetayi=$GlobalProtectionReason
                    }
                }
                $ResultCsv = Add-AOFileOperationRows -BasePath $BasePath -OperationName 'Delete' -OperationID $OperationID -OperationDate $OperationDate -OperationTime $OperationTime -Rows $Rows -TechnicalLogWriter $TechnicalLogWriter -OperationHistoryWriter $OperationHistoryWriter
                Write-Host "Blocked denemesi loglandi: $ResultCsv" -ForegroundColor DarkYellow
                continue
            }

            Write-Host ''
            Write-Host 'DELETE PREFLIGHT BASLADI - bu asamada hicbir veri silinmez veya degistirilmez.' -ForegroundColor Cyan

            # Hedef bazli koruma ve preflight.
            $PreflightMap = @{}
            $Rows = @()
            foreach ($ComputerName in $Systems) {
                if ($ReachableSystems -notcontains $ComputerName) {
                    Write-Host "$ComputerName : PREFLIGHT ATLANDI | ERISILEMEDI" -ForegroundColor Red
                    $Rows += [PSCustomObject]@{
                        IstemciAdi=$ComputerName; HedefPath=$TargetPath; PreflightDurumu='Erisilemedi'; EslesenOge=0;
                        DosyaAdedi=0; KlasorAdedi=0; ToplamBoyutByte=0; ReparsePointAdedi=0;
                        BackupPath=''; BackupAdedi=0; BackupDurumu='NotStarted'; BackupDogrulandi='Hayir'; KaynakStabil='Hayir';
                        SilinenAdet=0; SilmeSonKontrol='NotStarted'; Durum='Erisilemedi'; HataDetayi='Ping basarisiz.'
                    }
                    continue
                }

                $ClientProtectionReason = Get-AODeleteProtectionReason -Path $TargetPath -BasePath $BasePath -ComputerName $ComputerName
                if (-not [string]::IsNullOrWhiteSpace($ClientProtectionReason)) {
                    Write-Host "$ComputerName : PREFLIGHT BLOCKED | $ClientProtectionReason" -ForegroundColor Red
                    $Rows += [PSCustomObject]@{
                        IstemciAdi=$ComputerName; HedefPath=$TargetPath; PreflightDurumu='Blocked'; EslesenOge=0;
                        DosyaAdedi=0; KlasorAdedi=0; ToplamBoyutByte=0; ReparsePointAdedi=0;
                        BackupPath=''; BackupAdedi=0; BackupDurumu='NotStarted'; BackupDogrulandi='Hayir'; KaynakStabil='Hayir';
                        SilinenAdet=0; SilmeSonKontrol='NotStarted'; Durum='Blocked'; HataDetayi=$ClientProtectionReason
                    }
                    continue
                }

                Write-Host "$ComputerName : PREFLIGHT TARANIYOR..." -ForegroundColor DarkCyan
                $Preflight = Get-AODeletePreflight -ComputerName $ComputerName -TargetPath $TargetPath
                $PreflightMap[$ComputerName] = $Preflight
                $SizeText = Format-AOByteSize -Bytes ([Int64]$Preflight.TotalBytes)

                if ($Preflight.Eligible) {
                    Write-Host "$ComputerName : PREFLIGHT OK | Eslesen=$($Preflight.MatchedItemCount) File=$($Preflight.FileCount) Dir=$($Preflight.DirectoryCount) Boyut=$SizeText" -ForegroundColor Green
                }
                else {
                    Write-Host "$ComputerName : PREFLIGHT $($Preflight.Status) | $($Preflight.ErrorDetail)" -ForegroundColor Yellow
                    if ($null -ne $TechnicalLogWriter) {
                        & $TechnicalLogWriter -Level 'WARN' -Message "FILEOPS-DELETE-PREFLIGHT | OperationID='$OperationID' | PC='$ComputerName' | Path='$TargetPath' | Status='$($Preflight.Status)' | $($Preflight.ErrorDetail)"
                    }
                    $Rows += [PSCustomObject]@{
                        IstemciAdi=$ComputerName; HedefPath=$TargetPath; PreflightDurumu=$Preflight.Status; EslesenOge=$Preflight.MatchedItemCount;
                        DosyaAdedi=$Preflight.FileCount; KlasorAdedi=$Preflight.DirectoryCount; ToplamBoyutByte=$Preflight.TotalBytes; ReparsePointAdedi=$Preflight.ReparsePointCount;
                        BackupPath=''; BackupAdedi=0; BackupDurumu='NotStarted'; BackupDogrulandi='Hayir'; KaynakStabil='Hayir';
                        SilinenAdet=0; SilmeSonKontrol='NotStarted'; Durum=$Preflight.Status; HataDetayi=$Preflight.ErrorDetail
                    }
                }
            }

            $EligibleNames = @($Systems | Where-Object { $PreflightMap.ContainsKey($_) -and [bool]$PreflightMap[$_].Eligible })
            if ($EligibleNames.Count -eq 0) {
                Write-Host 'Silme icin uygun istemci bulunamadi. DELETE yapilmadi.' -ForegroundColor Yellow
                if ($Rows.Count -gt 0) {
                    # Hicbir hedef uygun degilse sadece preflight sonuclari kaydedilir.
                    $ResultCsv = Add-AOFileOperationRows -BasePath $BasePath -OperationName 'Delete' -OperationID $OperationID -OperationDate $OperationDate -OperationTime $OperationTime -Rows $Rows -TechnicalLogWriter $TechnicalLogWriter -OperationHistoryWriter $OperationHistoryWriter
                    Write-Host "Operasyon sonucu CSV: $ResultCsv" -ForegroundColor Cyan
                }
                continue
            }

            # Uygun hedeflerin toplam dosya/klasor/boyut ozeti ve son onay.
            $TotalFiles = [int](@($EligibleNames | ForEach-Object { [int]$PreflightMap[$_].FileCount } | Measure-Object -Sum).Sum)
            $TotalDirs  = [int](@($EligibleNames | ForEach-Object { [int]$PreflightMap[$_].DirectoryCount } | Measure-Object -Sum).Sum)
            [Int64]$TotalBytes = [Int64](@($EligibleNames | ForEach-Object { [Int64]$PreflightMap[$_].TotalBytes } | Measure-Object -Sum).Sum)

            Write-Host ''
            Write-Host 'DELETE ONAY OZETI' -ForegroundColor Yellow
            Write-Host "Hedef path            : $TargetPath"
            Write-Host "Silme adayi istemci   : $($EligibleNames.Count)"
            Write-Host "Toplam dosya          : $TotalFiles"
            Write-Host "Toplam klasor         : $TotalDirs"
            Write-Host "Toplam veri           : $(Format-AOByteSize -Bytes $TotalBytes)"
            Write-Host 'Silme oncesinde her istemci icin zorunlu backup + backup verification + source stability kontrolu yapilacaktir.' -ForegroundColor Yellow
            Write-Host 'Herhangi bir kontrol basarisizsa ilgili istemcide DELETE YAPILMAZ.' -ForegroundColor Yellow
            Write-Host ''
            $Confirm = (Read-Host 'Bu operasyon geri alinamaz olabilir. Devam etmek icin DELETE yazin').Trim()
            if ($Confirm -ne 'DELETE') {
                Write-Host 'Delete operasyonu iptal edildi. Hicbir istemcide veri silinmedi.' -ForegroundColor Yellow
                continue
            }

            # Yedek + silme dongusu. Manifest her hedeften sonra guncellenir (restore icin).
            $BackupRunRoot = Join-Path (Join-Path $BasePath 'DeleteBackups') ("{0}_Delete" -f $OperationID)
            New-Item -ItemType Directory -Path $BackupRunRoot -Force -ErrorAction Stop | Out-Null
            $ManifestRows = @()

            foreach ($ComputerName in $EligibleNames) {
                $Preflight = $PreflightMap[$ComputerName]
                try {
                    Write-Host "$ComputerName : BACKUP BASLADI | File=$($Preflight.FileCount) Dir=$($Preflight.DirectoryCount) Boyut=$(Format-AOByteSize -Bytes ([Int64]$Preflight.TotalBytes))" -ForegroundColor Cyan
                    $Backup = Backup-AORemoteItemsForDelete -ComputerName $ComputerName -TargetPath $TargetPath -BackupRunRoot $BackupRunRoot -Preflight $Preflight

                    if (-not $Backup.Success) {
                        Write-Host "$ComputerName : BACKUP/VERIFY FAILED - DELETE YAPILMADI | $($Backup.ErrorDetail)" -ForegroundColor Red
                        $Rows += [PSCustomObject]@{
                            IstemciAdi=$ComputerName; HedefPath=$TargetPath; PreflightDurumu='Ready'; EslesenOge=$Preflight.MatchedItemCount;
                            DosyaAdedi=$Preflight.FileCount; KlasorAdedi=$Preflight.DirectoryCount; ToplamBoyutByte=$Preflight.TotalBytes; ReparsePointAdedi=$Preflight.ReparsePointCount;
                            BackupPath=$Backup.BackupPath; BackupAdedi=$Backup.ItemCount; BackupDurumu=$Backup.Status; BackupDogrulandi='Hayir'; KaynakStabil='Hayir';
                            SilinenAdet=0; SilmeSonKontrol='NotStarted'; Durum='BackupFailed'; HataDetayi=$Backup.ErrorDetail
                        }
                        continue
                    }

                    Write-Host "$ComputerName : BACKUP OK + VERIFIED | RobocopyExit=$($Backup.RobocopyExitCodes)" -ForegroundColor Green
                    $ManifestRows += @($Backup.Entries)
                    $ManifestRows | Export-Csv -LiteralPath (Join-Path $BackupRunRoot 'manifest.csv') -NoTypeInformation -Encoding UTF8 -Delimiter ';' -ErrorAction Stop

                    Write-Host "$ComputerName : DELETE BASLADI..." -ForegroundColor Cyan
                    $Delete = Remove-AORemoteItems -ComputerName $ComputerName -TargetPath $TargetPath -Preflight $Preflight
                    if ($Delete.Success) {
                        Write-Host "$ComputerName : DELETE SUCCESS + VERIFIED | Silinen=$($Delete.ItemCount)" -ForegroundColor Green
                    }
                    else {
                        Write-Host "$ComputerName : DELETE $($Delete.Status) | Silinen=$($Delete.ItemCount) Kalan=$($Delete.RemainingCount) | Backup restore icin korunuyor." -ForegroundColor Red
                    }

                    $Rows += [PSCustomObject]@{
                        IstemciAdi=$ComputerName; HedefPath=$TargetPath; PreflightDurumu='Ready'; EslesenOge=$Preflight.MatchedItemCount;
                        DosyaAdedi=$Preflight.FileCount; KlasorAdedi=$Preflight.DirectoryCount; ToplamBoyutByte=$Preflight.TotalBytes; ReparsePointAdedi=$Preflight.ReparsePointCount;
                        BackupPath=$Backup.BackupPath; BackupAdedi=$Backup.ItemCount; BackupDurumu='Verified'; BackupDogrulandi='Evet'; KaynakStabil='Evet';
                        SilinenAdet=$Delete.ItemCount; SilmeSonKontrol=$(if($Delete.Verified){'Verified'}else{$Delete.Status});
                        Durum=$(if($Delete.Success){'Success'}else{$Delete.Status}); HataDetayi=$Delete.ErrorDetail
                    }
                }
                catch {
                    Write-Host "$ComputerName : DELETE PIPELINE HATASI | $($_.Exception.Message)" -ForegroundColor Red
                    $Rows += [PSCustomObject]@{
                        IstemciAdi=$ComputerName; HedefPath=$TargetPath; PreflightDurumu='Ready'; EslesenOge=$Preflight.MatchedItemCount;
                        DosyaAdedi=$Preflight.FileCount; KlasorAdedi=$Preflight.DirectoryCount; ToplamBoyutByte=$Preflight.TotalBytes; ReparsePointAdedi=$Preflight.ReparsePointCount;
                        BackupPath=$BackupRunRoot; BackupAdedi=0; BackupDurumu='Unknown'; BackupDogrulandi='Hayir'; KaynakStabil='Hayir';
                        SilinenAdet=0; SilmeSonKontrol='Unknown'; Durum='Failed'; HataDetayi=$_.Exception.Message
                    }
                }
            }

            if ($ManifestRows.Count -gt 0) {
                $ManifestRows | Export-Csv -LiteralPath (Join-Path $BackupRunRoot 'manifest.csv') -NoTypeInformation -Encoding UTF8 -Delimiter ';' -ErrorAction Stop
            }
        }
        # 3 = PUSH
        elseif ($Selection -eq '3') {
            $OperationName = 'Push'
            Write-Host 'Kaynak lokal path veya UNC path olabilir. H ile yardim/orneklere bakabilirsiniz.' -ForegroundColor DarkGray
            do {
                $SourcePath = (Read-Host 'Kaynak dosya/klasor/wildcard path (Lokal veya UNC)').Trim()
            } while ([string]::IsNullOrWhiteSpace($SourcePath))
            if (-not (Test-Path -Path $SourcePath)) {
                Write-Host 'Kaynak bulunamadi veya erisilemiyor.' -ForegroundColor Red
                continue
            }
            Write-Host 'Hedef path bir KLASOR olmalidir. Ornek: C:\ProgramData\MyApp' -ForegroundColor DarkGray
            do {
                $TargetDirectory = (Read-Host 'Hedef PC klasor path').Trim()
            } while ([string]::IsNullOrWhiteSpace($TargetDirectory))
            $OverwriteInput = (Read-Host 'Hedefte ayni isim varsa overwrite yapilsin mi? (E/H)').Trim().ToUpperInvariant()
            $Overwrite = ($OverwriteInput -eq 'E' -or $OverwriteInput -eq 'EVET')

            foreach ($ComputerName in $Systems) {
                if ($ReachableSystems -notcontains $ComputerName) {
                    $Rows += [PSCustomObject]@{ IstemciAdi=$ComputerName; KaynakPath=$SourcePath; HedefPath=$TargetDirectory; Overwrite=$(if($Overwrite){'Evet'}else{'Hayir'}); KopyalananAdet=0; AtlananAdet=0; Durum='Erisilemedi'; HataDetayi='Ping basarisiz.' }
                    continue
                }
                try {
                    $R = Copy-AOLocalItemToRemote -ComputerName $ComputerName -SourcePath $SourcePath -TargetDirectory $TargetDirectory -Overwrite $Overwrite
                    $Status = $(if ($R.Success) { 'Success' } else { 'Failed' })
                    Write-Host "$ComputerName : $Status | Copied=$($R.Copied) Skipped=$($R.Skipped)" -ForegroundColor $(if ($R.Success) { 'Green' } else { 'Red' })
                    $Rows += [PSCustomObject]@{ IstemciAdi=$ComputerName; KaynakPath=$SourcePath; HedefPath=$TargetDirectory; Overwrite=$(if($Overwrite){'Evet'}else{'Hayir'}); KopyalananAdet=$R.Copied; AtlananAdet=$R.Skipped; Durum=$Status; HataDetayi=$R.ErrorDetail }
                }
                catch {
                    Write-Host "$ComputerName : FAILED | $($_.Exception.Message)" -ForegroundColor Red
                    $Rows += [PSCustomObject]@{ IstemciAdi=$ComputerName; KaynakPath=$SourcePath; HedefPath=$TargetDirectory; Overwrite=$(if($Overwrite){'Evet'}else{'Hayir'}); KopyalananAdet=0; AtlananAdet=0; Durum='Failed'; HataDetayi=$_.Exception.Message }
                }
            }
        }
        # 4 = COMPARE
        elseif ($Selection -eq '4') {
            $OperationName = 'Compare'
            do {
                $ReferenceFile = (Read-Host 'Lokal referans dosyasi').Trim()
            } while ([string]::IsNullOrWhiteSpace($ReferenceFile))
            if (-not (Test-Path -LiteralPath $ReferenceFile -PathType Leaf)) {
                Write-Host 'Referans dosyasi bulunamadi.' -ForegroundColor Red
                continue
            }
            Write-Host 'Ornek hedef: C:\ProgramData\MyApp\config.ini' -ForegroundColor DarkGray
            do {
                $TargetFile = (Read-Host 'Hedef PC dosya path').Trim()
            } while ([string]::IsNullOrWhiteSpace($TargetFile))

            foreach ($ComputerName in $Systems) {
                if ($ReachableSystems -notcontains $ComputerName) {
                    $Rows += [PSCustomObject]@{ IstemciAdi=$ComputerName; ReferansPath=$ReferenceFile; HedefPath=$TargetFile; ReferansHash=''; HedefHash=''; ReferansSize=''; HedefSize=''; ReferansModified=''; HedefModified=''; HashEsit=''; SizeEsit=''; ModifiedEsit=''; Durum='Erisilemedi'; HataDetayi='Ping basarisiz.' }
                    continue
                }
                try {
                    $R = Compare-AORemoteFile -ComputerName $ComputerName -ReferenceFile $ReferenceFile -TargetFile $TargetFile
                    $Color = if ($R.Status -eq 'Esit') { 'Green' } elseif ($R.Status -eq 'Farkli') { 'Yellow' } else { 'Red' }
                    Write-Host "$ComputerName : $($R.Status) | Hash=$($R.HashEsit) Size=$($R.SizeEsit) Modified=$($R.ModifiedEsit)" -ForegroundColor $Color
                    $Rows += [PSCustomObject]@{ IstemciAdi=$ComputerName; ReferansPath=$ReferenceFile; HedefPath=$TargetFile; ReferansHash=$R.ReferenceHash; HedefHash=$R.RemoteHash; ReferansSize=$R.ReferenceSize; HedefSize=$R.RemoteSize; ReferansModified=$R.ReferenceModified; HedefModified=$R.RemoteModified; HashEsit=$R.HashEsit; SizeEsit=$R.SizeEsit; ModifiedEsit=$R.ModifiedEsit; Durum=$R.Status; HataDetayi=$R.ErrorDetail }
                }
                catch {
                    Write-Host "$ComputerName : HATA | $($_.Exception.Message)" -ForegroundColor Red
                    $Rows += [PSCustomObject]@{ IstemciAdi=$ComputerName; ReferansPath=$ReferenceFile; HedefPath=$TargetFile; ReferansHash=''; HedefHash=''; ReferansSize=''; HedefSize=''; ReferansModified=''; HedefModified=''; HashEsit=''; SizeEsit=''; ModifiedEsit=''; Durum='Hata'; HataDetayi=$_.Exception.Message }
                }
            }
        }

        if ($Rows.Count -gt 0) {
            # Secim 1-4 sonuclarini CSV'ye yaz, ozet goster ve sonucu dondur.
            $ResultCsv = Add-AOFileOperationRows -BasePath $BasePath -OperationName $OperationName -OperationID $OperationID -OperationDate $OperationDate -OperationTime $OperationTime -Rows $Rows -TechnicalLogWriter $TechnicalLogWriter -OperationHistoryWriter $OperationHistoryWriter
            Write-Host ''
            if ($OperationName -eq 'Compare') {
                Write-Host "Esit        : $(@($Rows | Where-Object { $_.Durum -eq 'Esit' }).Count)" -ForegroundColor Green
                Write-Host "Farkli      : $(@($Rows | Where-Object { $_.Durum -eq 'Farkli' }).Count)" -ForegroundColor Yellow
                Write-Host "Bulunamadi  : $(@($Rows | Where-Object { $_.Durum -eq 'Bulunamadi' }).Count)" -ForegroundColor Red
                Write-Host "Hata        : $(@($Rows | Where-Object { $_.Durum -eq 'Hata' -or $_.Durum -eq 'Erisilemedi' }).Count)" -ForegroundColor Red
            }
            else {
                Write-Host "Success     : $(@($Rows | Where-Object { $_.Durum -eq 'Success' }).Count)" -ForegroundColor Green
                Write-Host "Failed/Hata : $(@($Rows | Where-Object { $_.Durum -ne 'Success' }).Count)" -ForegroundColor Yellow
            }
            Write-Host "Operasyon sonucu CSV: $ResultCsv" -ForegroundColor Cyan
            return [PSCustomObject]@{ Completed=$true; ResultCsv=$ResultCsv; Message="$OperationName tamamlandi." }
        }
    }
}

# Dosya yuklendiginde modul kaydini dene (host yoksa sessizce atlanir).
Register-AOFileOperationsModule
