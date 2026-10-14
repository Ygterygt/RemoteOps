####################################################################
# ApplicationWorkers.ps1 - UYGULAMA / PAKET WORKER'LARI (ortak kod)
#
# Bu dosya bir menu modulu DEGILDIR; kendini Register-AOModule ile kaydetmez.
# Icinde sadece uygulama kontrolu, kurulu uygulama envanteri ve paket
# tetikleme icin kullanilan worker scriptblock'lari ve yardimci fonksiyonlar var.
#
# Kim kullanir?
#   - RemoteOps.App\RemoteOps.Runner.ps1 : dosyayi AST olarak okur ve parcalari
#     ADIYLA ceker (Get-HostScriptBlock / Import-HostFunction). Runner'in
#     Modules\*.ps1 otomatik yuklemesi bu dosyayi bilerek atlar.
#   - MD_Script.ps1 (konsol araci): modulleri yukledikten sonra bu dosyayi
#     dot-source eder.
#
# Tanimlananlar (ADLARI DEGISTIRMEYIN - Runner ve testler bu adlarla arar):
#   Compare-ApplicationVersion                 -> surum karsilastirma
#   ConvertTo-AOInstalledApplicationHtml        -> HTML kacis yardimcisi
#   Write-AOInstalledApplicationHtmlReport      -> kurulu uygulama raporu (CSV + HTML)
#   $InstalledApplicationInventoryScript        -> kurulu uygulama envanteri worker'i
#   $RegistryCheckScript                        -> uygulama varlik/surum kontrolu worker'i
#   $PackageScript                              -> PsExec ile paket tetikleme worker'i
#
# Worker'lar runspace icinde .ToString() ile de calistirildigi icin fonksiyon
# DEGIL scriptblock olarak tutulur ve dis scope'taki degiskenlere dayanmaz.
# Worker parametre sirasi da korunmalidir (konumsal cagriliyorlar).
# Bu kod daha once MD_Script.ps1 icindeydi; davranisi degistirilmeden tasindi.
####################################################################

Set-StrictMode -Version 2.0

# Mevcut ve hedef DisplayVersion degerlerini sayisal segmentlere ayirip
# karsilastirir. Sayisal olmayan/karisik formatlarda karar vermez (Comparable=false).
function Compare-ApplicationVersion {
    param(
        [string]$CurrentVersion,
        [string]$TargetVersion
    )

    if ([string]::IsNullOrWhiteSpace($CurrentVersion) -or [string]::IsNullOrWhiteSpace($TargetVersion)) {
        return [PSCustomObject]@{
            Comparable = $false
            Result     = $null
            Reason     = 'Mevcut veya hedef versiyon bos.'
        }
    }

    $CurrentNormalized = $CurrentVersion.Trim()
    $TargetNormalized  = $TargetVersion.Trim()

    if ([string]::Equals($CurrentNormalized, $TargetNormalized, [System.StringComparison]::OrdinalIgnoreCase)) {
        return [PSCustomObject]@{
            Comparable = $true
            Result     = 0
            Reason     = 'Versiyon metinleri ayni.'
        }
    }

    # Kurumsal uygulama DisplayVersion degerlerinde yaygin olan tamamen
    # sayisal segmentli formatlari karsilastirir: 14.3, 14.3.0.60473 vb.
    # v14.3.0 gibi baslangictaki v/V de kabul edilir. Harfli/sonekli belirsiz
    # formatlarda downgrade riski almamak icin otomatik karar verilmez.
    $NumericVersionPattern = '^[vV]?\d+(?:[._-]\d+)*$'

    if ($CurrentNormalized -notmatch $NumericVersionPattern -or $TargetNormalized -notmatch $NumericVersionPattern) {
        return [PSCustomObject]@{
            Comparable = $false
            Result     = $null
            Reason     = "Sayisal olmayan versiyon formati. Mevcut='$CurrentVersion' Hedef='$TargetVersion'"
        }
    }

    $CurrentNormalized = $CurrentNormalized.TrimStart([char[]]'vV')
    $TargetNormalized  = $TargetNormalized.TrimStart([char[]]'vV')

    $CurrentParts = @($CurrentNormalized -split '[._-]')
    $TargetParts  = @($TargetNormalized -split '[._-]')
    $MaxParts     = [Math]::Max($CurrentParts.Count, $TargetParts.Count)

    for ($Index = 0; $Index -lt $MaxParts; $Index++) {
        [Int64]$CurrentPart = 0
        [Int64]$TargetPart  = 0

        if ($Index -lt $CurrentParts.Count) {
            if (-not [Int64]::TryParse($CurrentParts[$Index], [ref]$CurrentPart)) {
                return [PSCustomObject]@{
                    Comparable = $false
                    Result     = $null
                    Reason     = "Mevcut versiyon segmenti sayiya cevrilemedi: $($CurrentParts[$Index])"
                }
            }
        }

        if ($Index -lt $TargetParts.Count) {
            if (-not [Int64]::TryParse($TargetParts[$Index], [ref]$TargetPart)) {
                return [PSCustomObject]@{
                    Comparable = $false
                    Result     = $null
                    Reason     = "Hedef versiyon segmenti sayiya cevrilemedi: $($TargetParts[$Index])"
                }
            }
        }

        if ($CurrentPart -lt $TargetPart) {
            return [PSCustomObject]@{ Comparable = $true; Result = -1; Reason = 'Mevcut versiyon hedef versiyondan eski.' }
        }
        if ($CurrentPart -gt $TargetPart) {
            return [PSCustomObject]@{ Comparable = $true; Result = 1; Reason = 'Mevcut versiyon hedef versiyondan yeni.' }
        }
    }

    return [PSCustomObject]@{
        Comparable = $true
        Result     = 0
        Reason     = 'Sayisal versiyon segmentleri esdeger.'
    }
}

# [GUI KULLANIR] HTML kacis yardimcisi (Runner Import-HostFunction ile ceker).
function ConvertTo-AOInstalledApplicationHtml {
    param($Value)
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

# [GUI KULLANIR] Kurulu uygulama envanterini Logs\Application\<ID>_InstalledApplications.csv/.html
# olarak yazar ve HTML'i acar (GUI'de Runner bu acma istegini yakalar).
function Write-AOInstalledApplicationHtmlReport {
    param([string]$BasePath, [string]$OperationID, [object[]]$Rows, [string[]]$ClientNames, [string[]]$SuccessfulClients)

    $ReportRoot = Join-Path (Join-Path $BasePath 'Logs') 'Application'
    New-Item -ItemType Directory -Path $ReportRoot -Force | Out-Null
    $Stem = '{0}_InstalledApplications' -f $OperationID
    $HtmlPath = Join-Path $ReportRoot ($Stem + '.html')
    $CsvPath = Join-Path $ReportRoot ($Stem + '.csv')
    $ReportRows = @($Rows)
    $Headers = @('IstemciAdi','DisplayName','DisplayVersion','Publisher','ProductID','ProductIDKaynak','RegistryPath','RegistryKey','Durum','HataDetayi')
    if ($ReportRows.Count -gt 0) {
        $ReportRows | Select-Object $Headers | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8 -Delimiter ';' -ErrorAction Stop
    }
    else {
        Set-Content -LiteralPath $CsvPath -Value (($Headers -join ';') + [Environment]::NewLine) -Encoding UTF8 -ErrorAction Stop
    }
    $HeaderHtml = '<tr>' + (($Headers | ForEach-Object { '<th>' + (ConvertTo-AOInstalledApplicationHtml $_) + '</th>' }) -join '') + '</tr>'
    $BodyHtml = @($ReportRows | Sort-Object IstemciAdi, DisplayName, DisplayVersion | ForEach-Object {
        $Row = $_
        '<tr>' + (($Headers | ForEach-Object { $Property = $Row.PSObject.Properties[$_]; $Value = if ($null -ne $Property) { $Property.Value } else { '' }; '<td>' + (ConvertTo-AOInstalledApplicationHtml $Value) + '</td>' }) -join '') + '</tr>'
    }) -join "`n"
    $Clients = @($ClientNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $Successful = @($SuccessfulClients | Where-Object { $Clients -contains $_ } | Sort-Object -Unique)
    $ClientOptions = '<option value="">Tum istemciler</option>' + (($Clients | ForEach-Object { '<option value="' + (ConvertTo-AOInstalledApplicationHtml $_) + '">' + (ConvertTo-AOInstalledApplicationHtml $_) + '</option>' }) -join '')
    $Style = '<style>body{font-family:Segoe UI,Arial;background:#f4f6f8;color:#20252b;margin:24px}h1{color:#163a5f}.meta{color:#667085}.summary{display:flex;gap:12px;margin:18px 0;flex-wrap:wrap}.card{background:white;border:1px solid #d9e1e8;border-radius:6px;padding:12px 18px}.label{display:block;color:#667085;font-size:12px}.value{font-size:24px;font-weight:600}.filter{width:320px;max-width:100%;padding:9px;border:1px solid #b8c2cc;border-radius:4px;margin:0 8px 12px 0}table{border-collapse:collapse;background:white;width:100%;font-size:12px}th{background:#163a5f;color:white;text-align:left;padding:8px;position:sticky;top:0}td{border:1px solid #d9e1e8;padding:7px;vertical-align:top}tr:nth-child(even){background:#f8fafc}</style>'
    $Summary = "<div class='summary'><div class='card'><span class='label'>Toplam istemci</span><span class='value'>$($Clients.Count)</span></div><div class='card'><span class='label'>Basarili istemci</span><span class='value'>$($Successful.Count)</span></div><div class='card'><span class='label'>Hatali istemci</span><span class='value'>$($Clients.Count - $Successful.Count)</span></div><div class='card'><span class='label'>Toplam uygulama</span><span class='value'>$($ReportRows.Count)</span></div></div>"
    $Script = '<script>function filterRows(){var q=document.getElementById("reportFilter").value.toLowerCase();var c=document.getElementById("clientFilter").value.toLowerCase();document.querySelectorAll("#reportTable tbody tr").forEach(function(row){var text=row.textContent.toLowerCase();var client=!c||row.cells[0].textContent.toLowerCase()===c;row.style.display=client&&text.indexOf(q)>=0?"":"none";});}</script>'
    $Html = "<!DOCTYPE html><html><head><meta charset='utf-8'><title>Yuklu Uygulamalar</title>$Style</head><body><h1>Yuklu Uygulamalar</h1><div class='meta'>OperationID: $(ConvertTo-AOInstalledApplicationHtml $OperationID) | Olusturulma: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>$Summary<select id='clientFilter' class='filter' onchange='filterRows()'>$ClientOptions</select><input id='reportFilter' class='filter' type='search' placeholder='Tabloda ara...' oninput='filterRows()' /><table id='reportTable'><thead>$HeaderHtml</thead><tbody>$BodyHtml</tbody></table>$Script</body></html>"
    Set-Content -LiteralPath $HtmlPath -Value $Html -Encoding UTF8 -ErrorAction Stop
    Start-Process -FilePath $HtmlPath
    Write-Host "Yuklu uygulama HTML raporu: $HtmlPath" -ForegroundColor Cyan
    Write-Host "Yuklu uygulama CSV raporu : $CsvPath" -ForegroundColor Cyan
    return $HtmlPath
}

# [GUI KULLANIR] KURULU UYGULAMA ENVANTERI WORKER'I
# Parametre: ComputerName, TimeoutSeconds. Uzak registry'ye (StdRegProv) WMI ile baglanir,
# 32/64 bit Uninstall anahtarlarindaki DisplayName'i olan tum kayitlari dondurur.
# Donus: @{ComputerName; Status=Success|Failed; Applications; ErrorDetail}
$InstalledApplicationInventoryScript = {
    param([string]$ComputerName, [int]$TimeoutSeconds)
    Set-StrictMode -Version 2.0
    $ErrorActionPreference = 'Stop'
    try {
        $HKLM = [uint32]2147483650
        $RegistryPaths = @('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
        $ConnectionOptions = [System.Management.ConnectionOptions]::new()
        $ConnectionOptions.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
        $ConnectionOptions.Impersonation = [System.Management.ImpersonationLevel]::Impersonate
        $Scope = [System.Management.ManagementScope]::new("\\$ComputerName\root\default", $ConnectionOptions)
        [void]$Scope.Connect()
        $RegClass = [System.Management.ManagementClass]::new($Scope, [System.Management.ManagementPath]::new('StdRegProv'), $null)
        $MethodOptions = [System.Management.InvokeMethodOptions]::new()
        $MethodOptions.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)

        function Get-RegistryString {
            param([string]$Key, [string]$ValueName)
            $InParams = $RegClass.GetMethodParameters('GetStringValue')
            $InParams['hDefKey'] = $HKLM
            $InParams['sSubKeyName'] = $Key
            $InParams['sValueName'] = $ValueName
            $OutParams = $RegClass.InvokeMethod('GetStringValue', $InParams, $MethodOptions)
            if ($null -eq $OutParams) { return '' }
            $ReturnValue = [uint32]$OutParams['ReturnValue']
            if ($ReturnValue -eq 0 -and $null -ne $OutParams['sValue']) { return [string]$OutParams['sValue'] }
            if ($ReturnValue -eq 1) {
                $Expanded = $RegClass.GetMethodParameters('GetExpandedStringValue')
                $Expanded['hDefKey'] = $HKLM
                $Expanded['sSubKeyName'] = $Key
                $Expanded['sValueName'] = $ValueName
                $ExpandedResult = $RegClass.InvokeMethod('GetExpandedStringValue', $Expanded, $MethodOptions)
                if ($null -ne $ExpandedResult -and [uint32]$ExpandedResult['ReturnValue'] -eq 0) {
                    return [string]$ExpandedResult['sValue']
                }
            }
            return ''
        }

        $Rows = @()
        foreach ($RegistryPath in $RegistryPaths) {
            $EnumParams = $RegClass.GetMethodParameters('EnumKey')
            $EnumParams['hDefKey'] = $HKLM
            $EnumParams['sSubKeyName'] = $RegistryPath
            $EnumResult = $RegClass.InvokeMethod('EnumKey', $EnumParams, $MethodOptions)
            if ($null -eq $EnumResult -or [uint32]$EnumResult['ReturnValue'] -eq 2) { continue }
            if ([uint32]$EnumResult['ReturnValue'] -ne 0) {
                throw "EnumKey hatasi. Path=$RegistryPath ReturnValue=$([uint32]$EnumResult['ReturnValue'])"
            }
            foreach ($SubKey in @($EnumResult['sNames'])) {
                if ([string]::IsNullOrWhiteSpace([string]$SubKey)) { continue }
                $FullKey = "$RegistryPath\$SubKey"
                $DisplayName = Get-RegistryString -Key $FullKey -ValueName 'DisplayName'
                if ([string]::IsNullOrWhiteSpace($DisplayName)) { continue }
                $ProductID = Get-RegistryString -Key $FullKey -ValueName 'ProductID'
                $ProductSource = 'RegistryProductID'
                if ([string]::IsNullOrWhiteSpace($ProductID) -and [string]$SubKey -match '^\{[0-9A-Fa-f-]{36}\}$') {
                    $ProductID = [string]$SubKey
                    $ProductSource = 'MSIProductCode(SubKey)'
                }
                $Rows += [PSCustomObject]@{ IstemciAdi=$ComputerName; DisplayName=$DisplayName; DisplayVersion=(Get-RegistryString -Key $FullKey -ValueName 'DisplayVersion'); Publisher=(Get-RegistryString -Key $FullKey -ValueName 'Publisher'); ProductID=$ProductID; ProductIDKaynak=$ProductSource; RegistryPath=$RegistryPath; RegistryKey=$FullKey; Durum='Basarili'; HataDetayi='' }
            }
        }
        return [PSCustomObject]@{ ComputerName=$ComputerName; Status='Success'; Applications=$Rows; ErrorDetail='' }
    }
    catch {
        return [PSCustomObject]@{ ComputerName=$ComputerName; Status='Failed'; Applications=@(); ErrorDetail=$_.Exception.Message }
    }
}

# ====================================================================
# [GUI KULLANIR] UYGULAMA VARLIK KONTROL WORKER'I
# Paket oncesi ilk kontrol ve paket sonrasi son kontrol AYNI kodu kullanir.
# Parametreler (sira onemli): ComputerName, SearchMode (DisplayName | DisplayNameExact |
#   ProductID), SearchValue, TimeoutSeconds, SelectedApplication, PackageOperation
# Donus Status: Var | Yok | CokluEslesme (Applications listesi ile) | Hata
# SelectedApplication verilirse (son kontrol) ayni uygulama kimligi aranir:
#   Uninstall -> ayni RegistryKey, Install -> ayni DisplayName + Publisher + RegistryPath
# ====================================================================
$RegistryCheckScript = {
    param(
        [string]$ComputerName,
        [string]$SearchMode,
        [string]$SearchValue,
        [int]$TimeoutSeconds,
        $SelectedApplication = $null,
        [string]$PackageOperation = ''
    )

    Set-StrictMode -Version 2.0
    $ErrorActionPreference = 'Stop'

    $HKLM = [uint32]2147483650
    $RegistryPaths = @(
        'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    function Invoke-StdRegEnumKey {
        param(
            [System.Management.ManagementClass]$RegClass,
            [uint32]$Hive,
            [string]$SubKeyName,
            [System.Management.InvokeMethodOptions]$MethodOptions
        )

        $InParams = $RegClass.GetMethodParameters('EnumKey')
        $InParams['hDefKey'] = $Hive
        $InParams['sSubKeyName'] = $SubKeyName
        $OutParams = $RegClass.InvokeMethod('EnumKey', $InParams, $MethodOptions)

        if ($null -eq $OutParams) { throw "StdRegProv.EnumKey bos sonuc dondurdu. Path=$SubKeyName" }

        $ReturnValue = [uint32]$OutParams['ReturnValue']
        if ($ReturnValue -eq 0) {
            $Names = @()
            if ($null -ne $OutParams['sNames']) { $Names = @($OutParams['sNames']) }
            return [PSCustomObject]@{ Exists = $true; SubKeys = $Names }
        }
        if ($ReturnValue -eq 2) { return [PSCustomObject]@{ Exists = $false; SubKeys = @() } }

        throw "StdRegProv.EnumKey hatasi. Path=$SubKeyName ReturnValue=$ReturnValue"
    }

    function Invoke-StdRegGetString {
        param(
            [System.Management.ManagementClass]$RegClass,
            [uint32]$Hive,
            [string]$SubKeyName,
            [string]$ValueName,
            [System.Management.InvokeMethodOptions]$MethodOptions
        )

        $InParams = $RegClass.GetMethodParameters('GetStringValue')
        $InParams['hDefKey'] = $Hive
        $InParams['sSubKeyName'] = $SubKeyName
        $InParams['sValueName'] = $ValueName
        $OutParams = $RegClass.InvokeMethod('GetStringValue', $InParams, $MethodOptions)

        if ($null -eq $OutParams) {
            throw "StdRegProv.GetStringValue bos sonuc dondurdu. Path=$SubKeyName Value=$ValueName"
        }

        $ReturnValue = [uint32]$OutParams['ReturnValue']
        if ($ReturnValue -eq 0) {
            if ($null -eq $OutParams['sValue']) { return $null }
            return [string]$OutParams['sValue']
        }
        if ($ReturnValue -eq 2) { return $null }

        # REG_EXPAND_SZ fallback. ReturnValue=1 gibi tip uyumsuzluklarinda
        # tek bir kayit tum taramayi Hata durumuna dusurmez.
        if ($ReturnValue -eq 1) {
            $ExpandedInParams = $RegClass.GetMethodParameters('GetExpandedStringValue')
            $ExpandedInParams['hDefKey'] = $Hive
            $ExpandedInParams['sSubKeyName'] = $SubKeyName
            $ExpandedInParams['sValueName'] = $ValueName
            $ExpandedOutParams = $RegClass.InvokeMethod('GetExpandedStringValue', $ExpandedInParams, $MethodOptions)

            if ($null -eq $ExpandedOutParams) { return $null }
            $ExpandedReturnValue = [uint32]$ExpandedOutParams['ReturnValue']

            if ($ExpandedReturnValue -eq 0) {
                if ($null -eq $ExpandedOutParams['sValue']) { return $null }
                return [string]$ExpandedOutParams['sValue']
            }
            if ($ExpandedReturnValue -eq 1 -or $ExpandedReturnValue -eq 2) { return $null }

            throw "StdRegProv.GetExpandedStringValue hatasi. Path=$SubKeyName Value=$ValueName ReturnValue=$ExpandedReturnValue"
        }

        throw "StdRegProv.GetStringValue hatasi. Path=$SubKeyName Value=$ValueName ReturnValue=$ReturnValue"
    }

    function Normalize-ProductID {
        param([string]$Value)

        if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
        $Normalized = $Value.Trim()
        if ($Normalized.Length -ge 2 -and $Normalized.StartsWith('{') -and $Normalized.EndsWith('}')) {
            $Normalized = $Normalized.Substring(1, $Normalized.Length - 2)
        }
        return $Normalized.ToUpperInvariant()
    }

    try {
        $NormalizedSearchProductID = ''
        if ($SearchMode -eq 'ProductID') { $NormalizedSearchProductID = Normalize-ProductID -Value $SearchValue }

        $ConnectionOptions = [System.Management.ConnectionOptions]::new()
        $ConnectionOptions.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
        $ConnectionOptions.Impersonation = [System.Management.ImpersonationLevel]::Impersonate

        $Scope = [System.Management.ManagementScope]::new("\\$ComputerName\root\default", $ConnectionOptions)
        [void]$Scope.Connect()

        $RegClass = [System.Management.ManagementClass]::new($Scope, [System.Management.ManagementPath]::new('StdRegProv'), $null)
        $MethodOptions = [System.Management.InvokeMethodOptions]::new()
        $MethodOptions.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)

        $FoundDisplayName    = ''
        $FoundDisplayVersion = ''
        $FoundProductID      = ''
        $FoundProductSource  = ''
        $SoftwareFound       = $false
        $ScannedPathCount    = 0
        $Applications        = @()

        foreach ($RegistryPath in $RegistryPaths) {

            $EnumInfo = Invoke-StdRegEnumKey -RegClass $RegClass -Hive $HKLM -SubKeyName $RegistryPath -MethodOptions $MethodOptions
            if (-not $EnumInfo.Exists) { continue }

            $ScannedPathCount++

            foreach ($SubKey in @($EnumInfo.SubKeys)) {
                if ([string]::IsNullOrWhiteSpace([string]$SubKey)) { continue }

                $FullKey = "$RegistryPath\$SubKey"
                $IsMatch = $false
                $DisplayName = $null
                $RegistryProductID = $null
                $SubKeyProductID = ''

                if ([string]$SubKey -match '^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$') {
                    $SubKeyProductID = [string]$SubKey
                }

                if ($SearchMode -eq 'DisplayName' -or $SearchMode -eq 'DisplayNameExact') {
                    $DisplayName = Invoke-StdRegGetString -RegClass $RegClass -Hive $HKLM -SubKeyName $FullKey -ValueName 'DisplayName' -MethodOptions $MethodOptions
                    if ($null -ne $SelectedApplication -and $PackageOperation -eq 'Uninstall') {
                        $IsMatch = [string]::Equals($FullKey, [string]$SelectedApplication.RegistryKey, [System.StringComparison]::OrdinalIgnoreCase)
                    }
                    elseif (-not [string]::IsNullOrWhiteSpace($DisplayName)) {
                        if ($null -ne $SelectedApplication) {
                            $IsMatch = [string]::Equals($DisplayName, [string]$SelectedApplication.DisplayName, [System.StringComparison]::OrdinalIgnoreCase)
                        }
                        elseif ($SearchMode -eq 'DisplayNameExact') {
                            $IsMatch = [string]::Equals($DisplayName, $SearchValue, [System.StringComparison]::OrdinalIgnoreCase)
                        }
                        else {
                            $IsMatch = $DisplayName.IndexOf($SearchValue, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
                        }
                    }
                }
                elseif ($SearchMode -eq 'ProductID') {
                    $RegistryProductID = Invoke-StdRegGetString -RegClass $RegClass -Hive $HKLM -SubKeyName $FullKey -ValueName 'ProductID' -MethodOptions $MethodOptions

                    $RegistryProductIDMatch = (
                        -not [string]::IsNullOrWhiteSpace($RegistryProductID) -and
                        (Normalize-ProductID -Value $RegistryProductID) -eq $NormalizedSearchProductID
                    )
                    $SubKeyProductIDMatch = (
                        -not [string]::IsNullOrWhiteSpace($SubKeyProductID) -and
                        (Normalize-ProductID -Value $SubKeyProductID) -eq $NormalizedSearchProductID
                    )

                    if ($RegistryProductIDMatch -or $SubKeyProductIDMatch) {
                        $IsMatch = $true
                        if ($RegistryProductIDMatch) {
                            $FoundProductID = $RegistryProductID
                            $FoundProductSource = 'RegistryProductID'
                        }
                        else {
                            $FoundProductID = $SubKeyProductID
                            $FoundProductSource = 'MSIProductCode(SubKey)'
                        }
                    }
                }
                else {
                    throw "Gecersiz arama tipi: $SearchMode"
                }

                if ($IsMatch) {
                    $Publisher = ''
                    if ($SearchMode -ne 'ProductID') {
                        $Publisher = [string](Invoke-StdRegGetString -RegClass $RegClass -Hive $HKLM -SubKeyName $FullKey -ValueName 'Publisher' -MethodOptions $MethodOptions)
                        if ($null -ne $SelectedApplication -and $PackageOperation -ne 'Uninstall' -and
                            (-not [string]::Equals($Publisher, [string]$SelectedApplication.Publisher, [System.StringComparison]::OrdinalIgnoreCase) -or
                             -not [string]::Equals($RegistryPath, [string]$SelectedApplication.RegistryPath, [System.StringComparison]::OrdinalIgnoreCase))) {
                                 continue
                             }
                        $FoundProductID = ''
                        $FoundProductSource = ''
                    }
                    $FoundDisplayName = ''
                    $FoundDisplayVersion = ''
                    $SoftwareFound = $true

                    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
                        $DisplayName = Invoke-StdRegGetString -RegClass $RegClass -Hive $HKLM -SubKeyName $FullKey -ValueName 'DisplayName' -MethodOptions $MethodOptions
                    }
                    if (-not [string]::IsNullOrWhiteSpace($DisplayName)) { $FoundDisplayName = $DisplayName }

                    $Version = Invoke-StdRegGetString -RegClass $RegClass -Hive $HKLM -SubKeyName $FullKey -ValueName 'DisplayVersion' -MethodOptions $MethodOptions
                    if (-not [string]::IsNullOrWhiteSpace($Version)) { $FoundDisplayVersion = $Version }

                    if ($SearchMode -eq 'DisplayName' -or $SearchMode -eq 'DisplayNameExact') {
                        $RegistryProductID = Invoke-StdRegGetString -RegClass $RegClass -Hive $HKLM -SubKeyName $FullKey -ValueName 'ProductID' -MethodOptions $MethodOptions
                        if (-not [string]::IsNullOrWhiteSpace($RegistryProductID)) {
                            $FoundProductID = $RegistryProductID
                            $FoundProductSource = 'RegistryProductID'
                        }
                        elseif (-not [string]::IsNullOrWhiteSpace($SubKeyProductID)) {
                            $FoundProductID = $SubKeyProductID
                            $FoundProductSource = 'MSIProductCode(SubKey)'
                        }
                    }

                    $Applications += [PSCustomObject]@{
                        DisplayName = $FoundDisplayName
                        DisplayVersion = $FoundDisplayVersion
                        ProductID = $FoundProductID
                        ProductIDSource = $FoundProductSource
                        Publisher = $Publisher
                        RegistryPath = $RegistryPath
                        RegistryKey = $FullKey
                    }
                }
            }
        }

        if (-not $SoftwareFound -and $ScannedPathCount -eq 0) {
            throw 'Uninstall registry yollari okunamadi veya hedef sistemde bulunamadi.'
        }

        if ($null -ne $SelectedApplication -and $PackageOperation -eq 'Install' -and $Applications.Count -eq 0) {
            throw 'Secilen uygulamanin kimligi kurulum sonrasi dogrulanamadi; DisplayName, Publisher veya mimari degismis olabilir.'
        }

        if ($Applications.Count -gt 1) {
            return [PSCustomObject]@{
                ComputerName = $ComputerName
                Status = 'CokluEslesme'
                DisplayName = ''; ProductID = ''; ProductIDSource = ''; DisplayVersion = ''
                ErrorDetail = 'Birden fazla uygulama eslesti; secim gerekiyor.'
                Applications = $Applications
            }
        }

        if ($SoftwareFound) {
            [PSCustomObject]@{
                ComputerName    = $ComputerName
                Status          = 'Var'
                DisplayName     = $FoundDisplayName
                ProductID       = $FoundProductID
                ProductIDSource = $FoundProductSource
                DisplayVersion  = $FoundDisplayVersion
                ErrorDetail     = ''
                Applications    = $Applications
            }
        }
        else {
            [PSCustomObject]@{
                ComputerName    = $ComputerName
                Status          = 'Yok'
                DisplayName     = ''
                ProductID       = ''
                ProductIDSource = ''
                DisplayVersion  = ''
                ErrorDetail     = ''
            }
        }
    }
    catch {
        [PSCustomObject]@{
            ComputerName    = $ComputerName
            Status          = 'Hata'
            DisplayName     = ''
            ProductID       = ''
            ProductIDSource = ''
            DisplayVersion  = ''
            ErrorDetail     = $_.Exception.Message
        }
    }
}

# ====================================================================
# [GUI KULLANIR] PAKET TETIKLEME WORKER'I (her hedef icin ayri runspace / GUI'de dogrudan)
# Akis:
#   1) PsExec \\PC -s -accepteula -n <sn> powershell.exe -EncodedCommand <wrapper>
#      Wrapper hedefte SYSTEM olarak UNC paketi kontrol eder ve dosya turune gore calistirir
#      (.bat/.cmd: cmd /c, .ps1: powershell -File, .vbs: cscript //B) - pencere ACILMAZ.
#   2) PsExec exit code = paket exit code (0, 1641, 3010 basari; digerleri hata)
#   3) Zaman asimi: yerel PsExec sonlandirilir, sonuc 'Timeout' (uzak islem devam edebilir)
#   4) Istenirse loglar toplanir (Get-AORecentLogs), basariliysa opsiyonel log temizligi
#   5) Son kontrol: $RegistryCheckScript ile uygulama durumu tekrar kontrol edilir
# Donus: ExecutionStatus, ExitCode, PsExecOutput, Log*, LogCleanup*, PostCheck* alanlari olan nesne
# ====================================================================
$PackageScript = {
    param(
        [string]$ComputerName,
        [string]$PackagePath,
        [string]$BatFile,
        [string]$PsExecPath,
        [int]$PsExecConnectTimeoutSeconds,
        [int]$PackageTimeoutSeconds,
        [bool]$CollectPackageLogs,
        [string]$FileOperationsModulePath,
        [string]$BasePath,
        [string]$PackageOperation,
        [string]$OperationID,
        [int]$LogLookbackMinutes,
        [string]$RegistryCheckScriptText,
        [string]$SearchMode,
        [string]$SearchValue,
        [int]$WMITimeoutSeconds,
        [string]$TargetInstallVersion,
        [int]$PostCheckInitialDelaySec,
        [int]$PostCheckRetryCount,
        [int]$PostCheckRetryIntervalSec,
        [bool]$SkipPostCheck,
        [bool]$InstallRequiresVersionMatch,
        $SelectedApplication = $null,
        [string]$CleanupLogsUserName = '',
        [ValidateSet('AtLeast','Exact')][string]$VersionMatchPolicy = 'AtLeast',
        [string]$LogCollectionGroup = ''
    )

    Set-StrictMode -Version 2.0
    $ErrorActionPreference = 'Stop'

    $PsExecProcess = $null
    $PsExecProcessId = $null
    # Varsayilan "log temizligi yapilmadi" sonucu ve PsExec cikti dosyalari (yerel %TEMP%).
    $CleanupNotRun = [PSCustomObject]@{ Status = $(if ([string]::IsNullOrWhiteSpace($CleanupLogsUserName)) { 'NotRequested' } else { 'NotRun' }); DeletedCount = 0; Detail = $(if ([string]::IsNullOrWhiteSpace($CleanupLogsUserName)) { '' } else { 'Paket normal tamamlanmadigi icin log temizleme yapilmadi.' }) }
    $StdOutFile = Join-Path ([System.IO.Path]::GetTempPath()) (('MD_PsExec_{0}_{1}_out.log' -f $ComputerName, [Guid]::NewGuid().ToString('N')))
    $StdErrFile = Join-Path ([System.IO.Path]::GetTempPath()) (('MD_PsExec_{0}_{1}_err.log' -f $ComputerName, [Guid]::NewGuid().ToString('N')))

    # PsExec stdout/stderr ciktisini birlestirir; PsExec banner satirlarini atar, 3000 karakterle sinirlar.
    function Get-PsExecOutput {
        param([string]$OutFile, [string]$ErrFile)

        $Lines = @()
        foreach ($File in @($OutFile, $ErrFile)) {
            if (Test-Path -LiteralPath $File -PathType Leaf) {
                try {
                    $Lines += @(Get-Content -LiteralPath $File -ErrorAction SilentlyContinue)
                }
                catch { }
            }
        }

        $Filtered = @(
            $Lines |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -notmatch '^(Connecting with|Starting|PsExec|Copyright|Sysinternals)' }
        )

        $Text = ($Filtered -join ' | ')
        if ($Text.Length -gt 3000) {
            $Text = $Text.Substring(0, 3000) + ' ...[truncated]'
        }
        return $Text
    }

    # Log toplama: sadece istendiyse ve paket gercekten baslatildiysa.
    function Invoke-PackageLogCollection {
        if (-not $CollectPackageLogs) {
            return [PSCustomObject]@{ Status='NotRequested'; FileCount=0; Destination=''; ErrorDetail='' }
        }

        # Paket prosesi gercekten baslatilmadiysa log toplama yapma.
        if ($null -eq $PsExecProcess) {
            return [PSCustomObject]@{ Status='PackageNotTriggered'; FileCount=0; Destination=''; ErrorDetail='' }
        }

        try {
            if (-not (Test-Path -LiteralPath $FileOperationsModulePath -PathType Leaf)) {
                throw "FileOperations module bulunamadi: $FileOperationsModulePath"
            }

            # Package worker ayri bir Runspace'te calistigi icin ana script scope'undaki
            # fonksiyonlari miras almaz. FileOperations bu worker scope'una yardimci
            # kutuphane olarak dot-source edilir. Modul registration fonksiyonlari
            # bu scope'ta yoksa FileOperations registration yapmadan sadece helper
            # fonksiyonlarini yukler.
            . $FileOperationsModulePath
            if (-not (Get-Command -Name Get-AORecentLogs -ErrorAction SilentlyContinue)) {
                throw 'Get-AORecentLogs fonksiyonu module icinde bulunamadi.'
            }

            $LogResult = Get-AORecentLogs `
                        -ComputerName $ComputerName `
                        -BasePath $BasePath `
                        -OperationName ("Package_{0}" -f $PackageOperation) `
                        -OperationID $OperationID `
                        -LookbackMinutes $LogLookbackMinutes `
                        -CollectionGroup $LogCollectionGroup

            return [PSCustomObject]@{
                Status      = [string]$LogResult.Status
                FileCount   = [int]$LogResult.FileCount
                Destination = [string]$LogResult.Destination
                ErrorDetail = [string]$LogResult.ErrorDetail
            }
        }
        catch {
            return [PSCustomObject]@{ Status='Failed'; FileCount=0; Destination=''; ErrorDetail=$_.Exception.Message }
        }
    }

    # Optional, opt-in cleanup of the collected logs that carry the saved user name. Runs ONLY after the package
    # finished normally (never after a timeout/error, when the package may still be writing) and only for files
    # that were collected and are byte-identical on the target. See Remove-AOCollectedUserLogs (FileOperations).
    function Invoke-PackageLogCleanup {
        param($LogResult)
        if ([string]::IsNullOrWhiteSpace($CleanupLogsUserName)) { return $CleanupNotRun }
        if (-not $CollectPackageLogs -or [string]$LogResult.Status -ne 'Success') {
            return [PSCustomObject]@{ Status = 'Skipped'; DeletedCount = 0; Detail = 'Loglar basariyla toplanmadigi icin hedefte hicbir sey silinmedi.' }
        }
        try {
            # The module is dot-sourced inside Invoke-PackageLogCollection's own scope, so its functions are not visible here: load it in this scope too.
            if (-not (Get-Command -Name Remove-AOCollectedUserLogs -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $FileOperationsModulePath -PathType Leaf)) {
                . $FileOperationsModulePath
            }
            if (-not (Get-Command -Name Remove-AOCollectedUserLogs -ErrorAction SilentlyContinue)) {
                throw 'Remove-AOCollectedUserLogs fonksiyonu module icinde bulunamadi.'
            }
            $Cleanup = Remove-AOCollectedUserLogs -ComputerName $ComputerName -UserName $CleanupLogsUserName -CollectedRoot ([string]$LogResult.Destination)
            return [PSCustomObject]@{ Status = [string]$Cleanup.Status; DeletedCount = [int]$Cleanup.DeletedCount; Detail = [string]$Cleanup.Detail }
        }
        catch { return [PSCustomObject]@{ Status = 'Failed'; DeletedCount = 0; Detail = $_.Exception.Message } }
    }

    # Paket bu istemcide bitip loglar toplandiktan HEMEN SONRA son kontrol burada
    # yapilir. Boylece cok sayida istemci oldugunda tum paket asamasinin bitmesini
    # beklemeyiz; erken biten istemci kapanmadan/erisilemez olmadan kontrol edilmis olur.
    function Invoke-PostCheck {
        $RegistryCheckBlock = [scriptblock]::Create($RegistryCheckScriptText)

        # Compare-ApplicationVersion'in ayri runspace'te calisan bu worker icin
        # kucuk/bagimsiz kopyasi (ana script scope'undaki fonksiyonlar miras alinmaz).
        function Test-AOVersionSatisfied {
            param([string]$CurrentVersion, [string]$TargetVersion)

            if ([string]::IsNullOrWhiteSpace($CurrentVersion) -or [string]::IsNullOrWhiteSpace($TargetVersion)) {
                return $false
            }

            $Cur = $CurrentVersion.Trim()
            $Tgt = $TargetVersion.Trim()
            if ([string]::Equals($Cur, $Tgt, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }

            $Pattern = '^[vV]?\d+(?:[._-]\d+)*$'
            if ($Cur -notmatch $Pattern -or $Tgt -notmatch $Pattern) { return $false }

            $Cur = $Cur.TrimStart([char[]]'vV')
            $Tgt = $Tgt.TrimStart([char[]]'vV')
            $CurParts = @($Cur -split '[._-]')
            $TgtParts = @($Tgt -split '[._-]')
            $MaxParts = [Math]::Max($CurParts.Count, $TgtParts.Count)

            for ($Index = 0; $Index -lt $MaxParts; $Index++) {
                [Int64]$CurPart = 0
                [Int64]$TgtPart = 0
                if ($Index -lt $CurParts.Count -and -not [Int64]::TryParse($CurParts[$Index], [ref]$CurPart)) { return $false }
                if ($Index -lt $TgtParts.Count -and -not [Int64]::TryParse($TgtParts[$Index], [ref]$TgtPart)) { return $false }
                if ($CurPart -lt $TgtPart) { return $false }
                if ($CurPart -gt $TgtPart) { return $VersionMatchPolicy -eq 'AtLeast' }
            }
            return $true
        }

        if ($PostCheckInitialDelaySec -gt 0) { Start-Sleep -Seconds $PostCheckInitialDelaySec }

        $CheckResult = & $RegistryCheckBlock $ComputerName $SearchMode $SearchValue $WMITimeoutSeconds $SelectedApplication $PackageOperation

        for ($Retry = 1; $Retry -le $PostCheckRetryCount; $Retry++) {
            $Desired = $false
            if ($PackageOperation -eq 'Install' -and $CheckResult.Status -eq 'Var') {
                if ($InstallRequiresVersionMatch) {
                    if (Test-AOVersionSatisfied -CurrentVersion ([string]$CheckResult.DisplayVersion) -TargetVersion $TargetInstallVersion) {
                        $Desired = $true
                    }
                }
                else {
                    # Sadece Varlik Kontrollu modda versiyona bakilmaksizin varlik yeterlidir.
                    $Desired = $true
                }
            }
            if ($PackageOperation -eq 'Uninstall' -and $CheckResult.Status -eq 'Yok') { $Desired = $true }

            if ($Desired) { break }

            Start-Sleep -Seconds $PostCheckRetryIntervalSec
            $CheckResult = & $RegistryCheckBlock $ComputerName $SearchMode $SearchValue $WMITimeoutSeconds $SelectedApplication $PackageOperation
        }

        if ($CheckResult.Status -eq 'CokluEslesme') {
            $CheckResult.Status = 'Hata'
            $CheckResult.ErrorDetail = 'Son kontrolde birden fazla uygulama eslesti; otomatik sonuc secilmedi. Adaylar: ' + (ConvertTo-Json -InputObject $CheckResult.Applications -Depth 4 -Compress)
        }
        return $CheckResult
    }

    try {
        # Ana worker akisi.
        if (-not (Test-Path -LiteralPath $PsExecPath -PathType Leaf)) {
            throw "PSEXEC.EXE bulunamadi: $PsExecPath"
        }

        # PsExec hedefte SYSTEM hesabinda Encoded PowerShell wrapper baslatir.
        # Wrapper UNC paket path'ini ve hedef dosyayi hedef SYSTEM hesabi ile kontrol eder,
        # dosya turune gore uygun calistiriciyi kullanir ve PowerShell process exit
        # code'unu paket exit code'una baglar. Boylece PsExec beklediginde aldigimiz
        # ExitCode gercek paket exit code'udur.
        #
        # -d BILEREK KULLANILMAZ: -d kullanilirsa PsExec remote prosesi beklemez ve
        # gercek paket exit code'u elde edilemez.
        $EscPackagePath = $PackagePath.Replace("'", "''")
        $EscBatFile = $BatFile.Replace("'", "''")

        $RemoteScript = @"
`$ErrorActionPreference = 'Stop'
`$PackagePath = '$EscPackagePath'
`$ScriptFile = '$EscBatFile'

try {
    if (-not (Test-Path -LiteralPath `$PackagePath -PathType Container)) {
        Write-Output ('MDPKG_ERROR: Paket path SYSTEM hesabindan erisilemiyor: ' + `$PackagePath)
        exit 9001
    }

    `$TargetFullPath = Join-Path `$PackagePath `$ScriptFile
    if (-not (Test-Path -LiteralPath `$TargetFullPath -PathType Leaf)) {
        Write-Output ('MDPKG_ERROR: Paket dosyasi SYSTEM hesabindan bulunamadi: ' + `$TargetFullPath)
        exit 9002
    }

    `$DotIndex = `$ScriptFile.LastIndexOf('.')
    `$Extension = if (`$DotIndex -ge 0) { `$ScriptFile.Substring(`$DotIndex).ToLowerInvariant() } else { '' }

    switch (`$Extension) {
        '.bat' { & `$env:ComSpec /d /v:off /c ('pushd "{0}" && call "{1}"' -f `$PackagePath, `$ScriptFile); break }
        '.cmd' { & `$env:ComSpec /d /v:off /c ('pushd "{0}" && call "{1}"' -f `$PackagePath, `$ScriptFile); break }
        '.ps1' { & 'powershell.exe' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `$TargetFullPath; break }
        '.vbs' { & 'cscript.exe' //NoLogo //B `$TargetFullPath; break }
        default { Write-Output ('MDPKG_ERROR: Desteklenmeyen dosya turu: ' + `$ScriptFile); exit 9004 }
    }

    `$PackageExitCode = [int]`$LASTEXITCODE
    exit `$PackageExitCode
}
catch {
    Write-Output ('MDPKG_ERROR: ' + [string]`$_.Exception.Message)
    exit 9003
}
"@

        # Wrapper'i UTF-16 Base64 olarak PsExec'e ver (-s = SYSTEM, -n = baglanti zaman asimi).
        $EncodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($RemoteScript))
        $Arguments = ('\\{0} -s -accepteula -n {1} powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand {2}' -f $ComputerName, $PsExecConnectTimeoutSeconds, $EncodedCommand)

        $PsExecProcess = Start-Process `
                    -FilePath $PsExecPath `
                    -ArgumentList $Arguments `
                    -RedirectStandardOutput $StdOutFile `
                    -RedirectStandardError $StdErrFile `
                    -WindowStyle Hidden `
                    -PassThru `
                    -ErrorAction Stop

        $PsExecProcessId = [int]$PsExecProcess.Id
        # Cache the process handle now: without it Windows PowerShell 5.1 returns an empty ExitCode for a
        # Start-Process -PassThru object, which [int] would turn into a false "package exit code 0".
        try { [void]$PsExecProcess.Handle } catch { }
        $WaitMilliseconds = [int]([Math]::Min(([int64]$PackageTimeoutSeconds * 1000), [int]::MaxValue))
        # Paketin bitmesini PackageTimeoutSeconds kadar bekle.
        $Completed = $PsExecProcess.WaitForExit($WaitMilliseconds)

        # ZAMAN ASIMI: yerel PsExec'i sonlandir; loglari topla, (modda varsa) son kontrolu yap, Timeout dondur.
        # Log temizligi zaman asiminda ASLA yapilmaz (paket hala yaziyor olabilir).
        if (-not $Completed) {
            try { $PsExecProcess.Kill() } catch { }
            try { [void]$PsExecProcess.WaitForExit(5000) } catch { }

            $OutputText = Get-PsExecOutput -OutFile $StdOutFile -ErrFile $StdErrFile
            $LogResult = Invoke-PackageLogCollection
            $PostCheckResult = if ($SkipPostCheck) { [PSCustomObject]@{ Status='Atlandi'; DisplayName=''; ProductID=''; ProductIDSource=''; DisplayVersion=''; ErrorDetail='Kontrolsuz mod: son kontrol yapilmadi.' } } else { Invoke-PostCheck }

            return [PSCustomObject]@{
                ComputerName   = $ComputerName
                Triggered      = $true
                PsExecProcessId = $PsExecProcessId
                ExitCode       = $null
                ExecutionStatus = 'Timeout'
                PsExecOutput        = $OutputText
                LogCollectionStatus = $LogResult.Status
                LogFileCount         = $LogResult.FileCount
                LogDestination       = $LogResult.Destination
                LogErrorDetail       = $LogResult.ErrorDetail
                LogCleanupStatus     = $CleanupNotRun.Status
                LogCleanupCount      = $CleanupNotRun.DeletedCount
                LogCleanupDetail     = $CleanupNotRun.Detail
                ErrorDetail         = "PsExec/BAT $PackageTimeoutSeconds saniye icinde tamamlanmadi. Yerel PsExec prosesi sonlandirildi; uzak proses devam ediyor olabilir."
                PostCheckStatus          = $PostCheckResult.Status
                PostCheckDisplayName     = $PostCheckResult.DisplayName
                PostCheckProductID       = $PostCheckResult.ProductID
                PostCheckProductIDSource = $PostCheckResult.ProductIDSource
                PostCheckDisplayVersion  = $PostCheckResult.DisplayVersion
                PostCheckErrorDetail     = $PostCheckResult.ErrorDetail
            }
        }

        # Redirect edilen ciktilarin tamamen flush olmasini sagla.
        $PsExecProcess.WaitForExit()
        $ExitCode = [int]$PsExecProcess.ExitCode
        $OutputText = Get-PsExecOutput -OutFile $StdOutFile -ErrFile $StdErrFile

        $ExecutionStatus = 'Failed'
        # Exit code -> calisma durumu. 1641/3010 = basarili ama yeniden baslatma gerekiyor/baslatildi.
        switch ($ExitCode) {
            0    { $ExecutionStatus = 'Success' }
            1641 { $ExecutionStatus = 'SuccessRebootInitiated' }
            3010 { $ExecutionStatus = 'SuccessRebootRequired' }
            default { $ExecutionStatus = 'Failed' }
        }

        $ErrorDetail = ''
        if ($ExecutionStatus -eq 'Failed') {
            $ErrorDetail = "PsExec/remote BAT ExitCode=$ExitCode"
            if (-not [string]::IsNullOrWhiteSpace($OutputText)) {
                $ErrorDetail += " | Output=$OutputText"
            }
        }

        $LogResult = Invoke-PackageLogCollection
        # Only a package that finished with a success exit code (0/1641/3010) is cleaned up; a failed package keeps its logs on the target for diagnosis.
        $CleanupResult = if ($ExecutionStatus -like 'Success*') { Invoke-PackageLogCleanup -LogResult $LogResult } else { $CleanupNotRun }
        $PostCheckResult = if ($SkipPostCheck) { [PSCustomObject]@{ Status='Atlandi'; DisplayName=''; ProductID=''; ProductIDSource=''; DisplayVersion=''; ErrorDetail='Kontrolsuz mod: son kontrol yapilmadi.' } } else { Invoke-PostCheck }

        return [PSCustomObject]@{
            ComputerName    = $ComputerName
            Triggered       = $true
            PsExecProcessId = $PsExecProcessId
            ExitCode        = $ExitCode
            ExecutionStatus     = $ExecutionStatus
            PsExecOutput        = $OutputText
            LogCollectionStatus = $LogResult.Status
            LogFileCount         = $LogResult.FileCount
            LogDestination       = $LogResult.Destination
            LogErrorDetail       = $LogResult.ErrorDetail
            LogCleanupStatus     = $CleanupResult.Status
            LogCleanupCount      = $CleanupResult.DeletedCount
            LogCleanupDetail     = $CleanupResult.Detail
            ErrorDetail          = $ErrorDetail
            PostCheckStatus          = $PostCheckResult.Status
            PostCheckDisplayName     = $PostCheckResult.DisplayName
            PostCheckProductID       = $PostCheckResult.ProductID
            PostCheckProductIDSource = $PostCheckResult.ProductIDSource
            PostCheckDisplayVersion  = $PostCheckResult.DisplayVersion
            PostCheckErrorDetail     = $PostCheckResult.ErrorDetail
        }
    }
    catch {
        $OutputText = Get-PsExecOutput -OutFile $StdOutFile -ErrFile $StdErrFile
        $Detail = [string]$_.Exception.Message
        if (-not [string]::IsNullOrWhiteSpace($OutputText)) {
            $Detail += " | Output=$OutputText"
        }

        $LogResult = if ($null -ne $PsExecProcess) { Invoke-PackageLogCollection } else { [PSCustomObject]@{ Status='NotCollected'; FileCount=0; Destination=''; ErrorDetail='' } }
        $PostCheckResult = if ($SkipPostCheck) { [PSCustomObject]@{ Status='Atlandi'; DisplayName=''; ProductID=''; ProductIDSource=''; DisplayVersion=''; ErrorDetail='Kontrolsuz mod: son kontrol yapilmadi.' } } elseif ($null -ne $PsExecProcess) { Invoke-PostCheck } else { [PSCustomObject]@{ Status='Hata'; DisplayName=''; ProductID=''; ProductIDSource=''; DisplayVersion=''; ErrorDetail='Paket tetiklenemedigi icin son kontrol yapilmadi.' } }

        return [PSCustomObject]@{
            ComputerName    = $ComputerName
            Triggered       = ($null -ne $PsExecProcess)
            PsExecProcessId = $PsExecProcessId
            ExitCode        = $null
            ExecutionStatus     = 'Hata'
            PsExecOutput        = $OutputText
            LogCollectionStatus = $LogResult.Status
            LogFileCount         = $LogResult.FileCount
            LogDestination       = $LogResult.Destination
            LogErrorDetail       = $LogResult.ErrorDetail
            LogCleanupStatus     = $CleanupNotRun.Status
            LogCleanupCount      = $CleanupNotRun.DeletedCount
            LogCleanupDetail     = $CleanupNotRun.Detail
            ErrorDetail          = $Detail
            PostCheckStatus          = $PostCheckResult.Status
            PostCheckDisplayName     = $PostCheckResult.DisplayName
            PostCheckProductID       = $PostCheckResult.ProductID
            PostCheckProductIDSource = $PostCheckResult.ProductIDSource
            PostCheckDisplayVersion  = $PostCheckResult.DisplayVersion
            PostCheckErrorDetail     = $PostCheckResult.ErrorDetail
        }
    }
    finally {
        foreach ($TempFile in @($StdOutFile, $StdErrFile)) {
            try {
                if (Test-Path -LiteralPath $TempFile -PathType Leaf) {
                    Remove-Item -LiteralPath $TempFile -Force -ErrorAction SilentlyContinue
                }
            }
            catch { }
        }
    }
}
