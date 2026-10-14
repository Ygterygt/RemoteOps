<#
Registry Operations module for AO.
Supports CLM-safe string value read, edit, delete, and rollback.
The module is loaded by the host and performs no operation during load.
#>

# ====================================================================
# NASIL CALISIR (ozet)
# - Konsol menusu mantigiyla yazilmistir (Read-Host). GUI'den calisirken Runner
#   Read-Host'u golgeleyip cevaplari sirayla verir, ornek RegistryEdit icin:
#   '2', <key>, <value adi>, <yeni deger>, 'EDIT', '0'
# - Menu: 1=Oku  2=Duzenle (REG_SZ)  3=Sil  4=Rollback  0=Bitir
# - Sadece HKLM ve sadece string (REG_SZ) degerler. Uzak erisim: CIM/DCOM + StdRegProv.
# - Duzenle/Sil oncesi eski deger okunur ve RegistryRollback\<ID>_Edit|Delete.csv
#   manifest'ine yazilir; rollback bu manifest'ten eski degeri geri koyar.
# - Menuden cikista (0) sonuc satirlari Logs\RemoteOps\<ID>_RegistryOperations.csv'ye yazilir.
# ====================================================================
Set-StrictMode -Version 2.0

# Hashtable'dan nesne uretir (CLM uyumlu yazim).
function New-RegistryOperationsObject {
    param([hashtable]$Properties)
    return [PSCustomObject]$Properties
}

# "HKLM\..." veya "HKEY_LOCAL_MACHINE\..." on ekini atip sadece alt anahtar yolunu dondurur.
function Get-RegistryOperationsRemotePath {
    param([string]$ComputerName, [string]$RegistryKey)
    $Value = $RegistryKey.Trim().Trim('\')
    $Value = $Value -replace '(?i)^(HKEY_LOCAL_MACHINE|HKLM):?\\?', ''
    if ([string]::IsNullOrWhiteSpace($Value)) { throw 'Registry key alt yolu bos olamaz.' }
    return $Value.Trim('\')
}

# Mevcut string degeri okur. Exists=$false ise ReturnValue nedeni gosterir
# Yalnizca 2 (ERROR_FILE_NOT_FOUND) bulunamadi sayilir; diger kodlar okuma hatasidir.
function Get-RegistryOperationsValue {
    param($Session, [string]$RegistryKey, [string]$ValueName)

    $Result = Invoke-CimMethod -CimSession $Session -Namespace 'root\default' -ClassName StdRegProv -MethodName GetStringValue -Arguments @{
        hDefKey = [uint32]2147483650
        sSubKeyName = $RegistryKey
        sValueName = $ValueName
    } -ErrorAction Stop

    if ([uint32]$Result.ReturnValue -eq 0) {
        return New-RegistryOperationsObject @{ Exists=$true; Value=[string]$Result.sValue; ReturnValue=0 }
    }

    return New-RegistryOperationsObject @{ Exists=$false; Value=''; ReturnValue=[uint32]$Result.ReturnValue }
}

# Rollback manifest'ini (';' ayracli CSV) yazar.
function Write-RegistryOperationsManifest {
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

# MENU GIRIS NOKTASI (Runner / MD_Script modul menusu cagirir).
function Invoke-RegistryOperationsMenu {
    param(
        [string]$BasePath,
        [string[]]$Systems,
        [string[]]$ReachableSystems,
        [string[]]$UnreachableSystems,
        [string]$OperationID,
        [string]$OperationDate,
        [string]$OperationTime,
        [scriptblock]$TechnicalLogWriter,
        [scriptblock]$OperationHistoryWriter
    )

    $RollbackRoot = Join-Path $BasePath 'RegistryRollback'
    New-Item -ItemType Directory -Path $RollbackRoot -Force | Out-Null
    $ReportRows = @()

    while ($true) {
        Write-Host ''
        Write-Host '============================================================' -ForegroundColor Cyan
        Write-Host ' REGISTRY OPERATIONS' -ForegroundColor Cyan
        Write-Host '============================================================' -ForegroundColor Cyan
        Write-Host '1 - Registry value oku'
        Write-Host '2 - Registry value duzenle'
        Write-Host '3 - Registry value sil'
        Write-Host '4 - Rollback uygula'
        Write-Host '0 - Bitir'
        # Menu secimi (GUI'de ilk cevap). 0 = sonuc CSV'sini yaz ve don.
        $Selection = (Read-Host 'Seciminiz').Trim()

        if ($Selection -eq '0') {
            $ResultCsv = ''
            if ($ReportRows.Count -gt 0) {
                $ReportRoot = Join-Path (Join-Path $BasePath 'Logs') 'RemoteOps'
                New-Item -ItemType Directory -Path $ReportRoot -Force | Out-Null
                $ResultCsv = Join-Path $ReportRoot ('{0}_RegistryOperations.csv' -f $OperationID)
                $ReportRows | Export-Csv -LiteralPath $ResultCsv -NoTypeInformation -Encoding UTF8 -Delimiter ';' -ErrorAction Stop
            }
            return New-RegistryOperationsObject @{ Completed=$true; ResultCsv=$ResultCsv; Rows=@($ReportRows); Message='Registry Operations tamamlandi.' }
        }

        # 4 = ROLLBACK: manifest (bos ise en yenisi) okunur; eski deger varsa geri yazilir,
        # eskiden yoksa deger silinir. ROLLBACK yazilarak onaylanmalidir.
        if ($Selection -eq '4') {
            $ManifestPath = (Read-Host 'Rollback manifest CSV path (bos=son manifest)').Trim()
            if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
                $ManifestPath = Get-ChildItem -LiteralPath $RollbackRoot -Filter '*.csv' -File -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
            }
            if ([string]::IsNullOrWhiteSpace($ManifestPath) -or -not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
                Write-Host 'Rollback manifest bulunamadi.' -ForegroundColor Yellow
                continue
            }
            if ((Read-Host 'Rollback icin ROLLBACK yazin').Trim().ToUpperInvariant() -ne 'ROLLBACK') {
                Write-Host 'Rollback iptal edildi.' -ForegroundColor Yellow
                continue
            }

            $RollbackRows = @(Import-Csv -LiteralPath $ManifestPath -Delimiter ';' -ErrorAction Stop)
            foreach ($Row in $RollbackRows) {
                try {
                    $Session = New-CimSession -ComputerName $Row.ComputerName -SessionOption (New-CimSessionOption -Protocol Dcom) -OperationTimeoutSec 10 -ErrorAction Stop
                    try {
                        $Arguments = @{ hDefKey=[uint32]2147483650; sSubKeyName=$Row.RegistryKey; sValueName=$Row.ValueName }
                        if ([string]$Row.OldExists -eq 'True') {
                            $Arguments['sValue'] = [string]$Row.OldValue
                            $Restore = Invoke-CimMethod -CimSession $Session -Namespace 'root\default' -ClassName StdRegProv -MethodName SetStringValue -Arguments $Arguments -ErrorAction Stop
                        }
                        else {
                            $Restore = Invoke-CimMethod -CimSession $Session -Namespace 'root\default' -ClassName StdRegProv -MethodName DeleteValue -Arguments $Arguments -ErrorAction Stop
                        }
                        Write-Host "$($Row.ComputerName) : ROLLBACK ReturnValue=$($Restore.ReturnValue)" -ForegroundColor Green
                    }
                    finally { Remove-CimSession -CimSession $Session -ErrorAction SilentlyContinue }
                }
                catch {
                    Write-Host "$($Row.ComputerName) : ROLLBACK HATA | $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            continue
        }

        if ($Selection -notin @('1','2','3')) {
            Write-Host 'Gecersiz secim.' -ForegroundColor Yellow
            continue
        }

        # 1/2/3 icin ortak girdiler: anahtar, deger adi, (2 ise) yeni deger ve onay kelimesi.
        $RegistryKey = Get-RegistryOperationsRemotePath -ComputerName '' -RegistryKey (Read-Host 'Registry key (HKLM veya HKEY_LOCAL_MACHINE tam yolu)')
        $ValueName = (Read-Host 'Value adi').Trim()
        if ([string]::IsNullOrWhiteSpace($RegistryKey) -or [string]::IsNullOrWhiteSpace($ValueName)) {
            Write-Host 'Registry key ve value adi bos olamaz.' -ForegroundColor Red
            continue
        }

        $NewValue = ''
        if ($Selection -eq '2') { $NewValue = Read-Host 'Yeni string deger' }
        if ($Selection -in @('2','3')) {
            $ConfirmWord = if ($Selection -eq '2') { 'EDIT' } else { 'DELETE' }
            if ((Read-Host "Devam etmek icin $ConfirmWord yazin").Trim().ToUpperInvariant() -ne $ConfirmWord) {
                Write-Host 'Islem iptal edildi.' -ForegroundColor Yellow
                continue
            }
        }

        $ManifestRows = @()
        # Her hedefte: CIM oturumu ac -> eski degeri oku -> (1) raporla veya (2/3) degistir/sil.
        foreach ($ComputerName in $ReachableSystems) {
            try {
                $Session = New-CimSession -ComputerName $ComputerName -SessionOption (New-CimSessionOption -Protocol Dcom) -OperationTimeoutSec 10 -ErrorAction Stop
                try {
                    $Old = Get-RegistryOperationsValue -Session $Session -RegistryKey $RegistryKey -ValueName $ValueName
                    if ($Selection -eq '1') {
                        if ($Old.Exists) {
                            Write-Host "$ComputerName : $RegistryKey\$ValueName = $($Old.Value)" -ForegroundColor Green
                        }
                        elseif ([uint32]$Old.ReturnValue -eq 2) {
                            Write-Host "$ComputerName : VALUE YOK | ReturnValue=$($Old.ReturnValue)" -ForegroundColor Yellow
                        }
                        else { Write-Host "$ComputerName : READ FAILED | ReturnValue=$($Old.ReturnValue)" -ForegroundColor Red }
                        $ReportRows += New-RegistryOperationsObject @{ OperationID=$OperationID; ComputerName=$ComputerName; RegistryKey=$RegistryKey; ValueName=$ValueName; Action='Read'; Status=$(if ($Old.Exists) { 'Success' } elseif ([uint32]$Old.ReturnValue -eq 2) { 'NotFound' } else { 'Failed' }); Value=$Old.Value; NewValue=''; ReturnValue=$Old.ReturnValue; ErrorDetail=$(if ($Old.Exists) { '' } elseif ([uint32]$Old.ReturnValue -eq 2) { 'Value not found.' } else { "Registry read failed (ReturnValue=$($Old.ReturnValue))." }) }
                        continue
                    }

                    # A value that exists but is not REG_SZ (e.g. DWORD) cannot be read as a string, so it could neither be backed up nor rolled back: never overwrite or delete it.
                    if (-not $Old.Exists -and [uint32]$Old.ReturnValue -ne 2) {
                        $BlockedAction = if ($Selection -eq '2') { 'Edit' } else { 'Delete' }
                        $BlockedDetail = "Current value could not be read as a string (ReturnValue=$($Old.ReturnValue); not a REG_SZ value or access denied). Nothing was changed."
                        Write-Host "$ComputerName : $BlockedAction BLOCKED | $BlockedDetail" -ForegroundColor Red
                        $ReportRows += New-RegistryOperationsObject @{ OperationID=$OperationID; ComputerName=$ComputerName; RegistryKey=$RegistryKey; ValueName=$ValueName; Action=$BlockedAction; Status='Failed'; Value=''; NewValue=$NewValue; ReturnValue=[uint32]$Old.ReturnValue; ErrorDetail=$BlockedDetail }
                        continue
                    }

                    # Degisiklik: SetStringValue (Edit) veya DeleteValue (Delete); eski deger manifest satirina eklenir.
                    $Arguments = @{ hDefKey=[uint32]2147483650; sSubKeyName=$RegistryKey; sValueName=$ValueName }
                    $Action=if($Selection -eq '2'){'Edit'}else{'Delete'}
                    $ManifestPath=Join-Path $RollbackRoot ("{0}_{1}.csv" -f $OperationID,$Action)
                    $ManifestEntry=New-RegistryOperationsObject @{
                        ComputerName=$ComputerName;RegistryKey=$RegistryKey;ValueName=$ValueName;OldExists=$Old.Exists;OldValue=$Old.Value;NewValue=$NewValue
                        Action=$Action;ReturnValue='Pending';OperationID=$OperationID;OperationDate=$OperationDate;OperationTime=$OperationTime
                    }
                    $CandidateRows=@($ManifestRows)+@($ManifestEntry)
                    Write-RegistryOperationsManifest -Path $ManifestPath -Rows $CandidateRows
                    $ManifestRows=$CandidateRows
                    if ($Selection -eq '2') {
                        $Arguments['sValue'] = [string]$NewValue
                        $Action = 'Edit'
                        $OperationResult = Invoke-CimMethod -CimSession $Session -Namespace 'root\default' -ClassName StdRegProv -MethodName SetStringValue -Arguments $Arguments -ErrorAction Stop
                    }
                    else {
                        $Action = 'Delete'
                        $OperationResult = Invoke-CimMethod -CimSession $Session -Namespace 'root\default' -ClassName StdRegProv -MethodName DeleteValue -Arguments $Arguments -ErrorAction Stop
                    }

                    $ManifestEntry.ReturnValue=[uint32]$OperationResult.ReturnValue
                    Write-RegistryOperationsManifest -Path $ManifestPath -Rows $ManifestRows
                    Write-Host "$ComputerName : $Action ReturnValue=$($OperationResult.ReturnValue)" -ForegroundColor $(if ([uint32]$OperationResult.ReturnValue -eq 0) { 'Green' } else { 'Red' })
                    $ReportRows += New-RegistryOperationsObject @{ OperationID=$OperationID; ComputerName=$ComputerName; RegistryKey=$RegistryKey; ValueName=$ValueName; Action=$Action; Status=$(if ([uint32]$OperationResult.ReturnValue -eq 0) { 'Success' } else { 'Failed' }); Value=$Old.Value; NewValue=$NewValue; ReturnValue=[uint32]$OperationResult.ReturnValue; ErrorDetail=$(if ([uint32]$OperationResult.ReturnValue -eq 0) { '' } else { "Registry call returned $($OperationResult.ReturnValue)." }) }
                }
                finally { Remove-CimSession -CimSession $Session -ErrorAction SilentlyContinue }
            }
            catch {
                Write-Host "$ComputerName : HATA | $($_.Exception.Message)" -ForegroundColor Red
                $ReportRows += New-RegistryOperationsObject @{ OperationID=$OperationID; ComputerName=$ComputerName; RegistryKey=$RegistryKey; ValueName=$ValueName; Action=$(switch ($Selection) { '1' { 'Read' } '2' { 'Edit' } default { 'Delete' } }); Status='Failed'; Value=''; NewValue=$NewValue; ReturnValue=''; ErrorDetail=$_.Exception.Message }
            }
        }

        # Bu turdaki degisiklikler icin rollback manifest'ini kaydet.
        if ($ManifestRows.Count -gt 0) {
            $ManifestPath = Join-Path $RollbackRoot ("{0}_{1}.csv" -f $OperationID, $(if ($Selection -eq '2') { 'Edit' } else { 'Delete' }))
            Write-Host "Rollback manifest: $ManifestPath" -ForegroundColor Cyan
        }
    }
}

# Modul kaydi: dosya dot-source edildiginde kendini host'a tanitir.
Register-AOModule `
    -Name 'RegistryOperations' `
    -Version '1.0' `
    -MinimumHostApiVersion '1.0' `
    -SourcePath $PSCommandPath

Register-AOModuleOperation `
    -ModuleName 'RegistryOperations' `
    -Name 'RegistryOperations' `
    -DisplayName 'Registry Operations' `
    -EntryPointName 'Invoke-RegistryOperationsMenu' `
    -Handler ${function:Invoke-RegistryOperationsMenu}
