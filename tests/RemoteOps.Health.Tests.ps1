param([string]$PreviewPath='')
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
$Tokens=$null;$Errors=$null
foreach($File in @('Modules\HealthOperations.ps1','RemoteOps.App\RemoteOps.Reports.ps1')){
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root $File),[ref]$Tokens,[ref]$Errors)
    if($Errors.Count){throw ($Errors|Out-String)}
}
. (Join-Path $Root 'Modules\HealthOperations.ps1')
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
$Temp=Join-Path $env:TEMP ('RemoteOpsHealth-'+[guid]::NewGuid().ToString('N'))
try{
    # ---- date parsing
    if((ConvertTo-AOHealthDate '20260115').Day -ne 15){throw 'yyyyMMdd parse failed'}
    if($null -eq (ConvertTo-AOHealthDate '1/15/2026') -or $null -ne (ConvertTo-AOHealthDate 'not a date') -or $null -ne (ConvertTo-AOHealthDate '')){throw 'locale/invalid date parse failed'}
    if((ConvertTo-AOHealthDate ('0x'+([datetime]'2026-02-03').ToFileTime().ToString('X')) ).Year -ne 2026){throw 'hex filetime parse failed'}

    $Now=Get-Date
    function New-Snapshot {
        param([string]$Name,[double]$DiskUsed=40,[string]$Sccm='Running',[bool]$Reboot=$false,[double]$BootDays=3,[double]$LogDays=1,[double]$PatchDays=10)
        [PSCustomObject]@{
            ComputerName=$Name;CollectedAt=$Now;Manufacturer='Dell';Model='Latitude 5540';Serial='SN-'+$Name;BiosVersion='1.2.3';BiosDate=$Now.AddDays(-200)
            OsCaption='Microsoft Windows 11 Enterprise';OsVersion='10.0.26100';OsBuild='26100.2314';OsDisplayVersion='24H2';OsArch='64-bit';Domain='corp.local';LoggedOnUser='CORP\user1'
            CpuName='Intel i7';CpuCores=12;InstallDate=$Now.AddDays(-400);LastBoot=$Now.AddDays(-$BootDays);RebootPending=$Reboot;RebootReasons=$(if($Reboot){@('Windows Update')}else{@()})
            Adapters=@([PSCustomObject]@{Name='Intel Ethernet';Mac='AA:BB:CC:DD:EE:FF';IPv4=@('10.1.2.3');Subnet=@('255.255.255.0');Gateway=@('10.1.2.1');Dns=@('10.1.0.10');Dhcp=$true})
            CpuLoad=12;MemTotalMB=16384;MemFreeMB=8192
            Disks=@([PSCustomObject]@{Drive='C:';Label='OS';FileSystem='NTFS';SizeGB=476.0;FreeGB=[math]::Round(476*(100-$DiskUsed)/100,1);UsedPercent=$DiskUsed})
            Services=@([PSCustomObject]@{Name='CcmExec';DisplayName='SMS Agent Host';State=$Sccm;StartMode='Auto'})
            SccmVersion='5.00.9128.1000';SccmServiceState=$Sccm;SccmStartMode='Auto'
            CcmCacheExists=$true;CcmCacheLastWrite=$Now.AddDays(-5);CcmCacheItems=14;CcmCacheNewestItem='ABC00123.1.S-1-5-21'
            SccmLogName='SCCMUpdates.log';SccmLogLastWrite=$Now.AddDays(-$LogDays);SccmLogCount=3;CcmExecLogLastWrite=$Now.AddHours(-1)
            Patches=@([PSCustomObject]@{Id='KB5044284';Description='Security Update';InstalledOn=$Now.AddDays(-$PatchDays);InstalledBy='NT AUTHORITY\SYSTEM'})
            Apps=@([PSCustomObject]@{Name='Webex <b>test</b>';Version='46.7';InstalledOn=$Now.AddDays(-2)})
            Errors=@()
        }
    }
    $Healthy=ConvertTo-AOHealthEvaluation -Snapshot (New-Snapshot 'PC-OK') -Now $Now
    if($Healthy.Health -ne 'Healthy' -or $Healthy.Warnings.Count -ne 0){throw "Healthy PC flagged: $($Healthy.Warnings|Out-String)"}
    $Bad=ConvertTo-AOHealthEvaluation -Snapshot (New-Snapshot 'PC-BAD' -DiskUsed 97 -Sccm 'Stopped' -Reboot $true -BootDays 45 -LogDays 30 -PatchDays 90) -Now $Now
    if($Bad.Health -ne 'Critical' -or $Bad.Warnings.Count -lt 6){throw "Bad PC under-reported: $($Bad.Warnings|Out-String)"}
    $Warn=ConvertTo-AOHealthEvaluation -Snapshot (New-Snapshot 'PC-WARN' -Reboot $true) -Now $Now
    if($Warn.Health -ne 'Warning' -or $Warn.Summary.PendingReboot -ne 'Yes'){throw 'Reboot-only PC must be Warning.'}
    $NoSccm=ConvertTo-AOHealthEvaluation -Snapshot (New-Snapshot 'PC-NOSCCM' -Sccm 'Not installed') -Now $Now
    if($NoSccm.Health -ne 'Critical'){throw 'Missing SCCM service must be Critical.'}
    if($Healthy.Summary.IPv4 -ne '10.1.2.3' -or $Healthy.Summary.Subnet -ne '255.255.255.0' -or $Healthy.Summary.LastPatch -ne 'KB5044284' -or $Healthy.Summary.WinBuild -ne '26100.2314'){throw 'Summary row is missing fields.'}

    # ---- operation with mocked collector: batch semantics, CSV, details, single HTML
    $script:AOHealthDetails.Clear()
    function Get-AOHealthSnapshot {
        param([string]$ComputerName,[switch]$SkipApps)
        if($ComputerName -eq 'PC-FAIL'){throw 'RPC server is unavailable'}
        $Snapshot=switch($ComputerName){'PC-BAD'{New-Snapshot $ComputerName -DiskUsed 97 -Sccm 'Stopped' -Reboot $true}'<script>x</script>'{New-Snapshot $ComputerName}default{New-Snapshot $ComputerName}}
        if($SkipApps){$Snapshot.Apps=@()}
        return $Snapshot
    }
    $Logs=New-Object System.Collections.ArrayList
    $Writer={param($Level,$Message)[void]$Logs.Add($Message)}
    $Systems=@('PC-OK','PC-BAD','PC-FAIL','PC-OFF','<script>x</script>')
    $Result=Invoke-AOHealthCheck -BasePath $Temp -Systems $Systems -ReachableSystems @('PC-OK','PC-BAD','PC-FAIL','<script>x</script>') -UnreachableSystems @('PC-OFF') -OperationID 'HEALTH-1' -OperationDate 'd' -OperationTime 't' -TechnicalLogWriter $Writer 6>$null
    if($Result.Rows.Count -ne 5 -or -not(Test-Path -LiteralPath $Result.ResultCsv)){throw 'Health rows/CSV missing.'}
    $Csv=@(Import-Csv -LiteralPath $Result.ResultCsv -Delimiter ';')
    if($Csv.Count -ne 5 -or @($Csv|Where-Object{$_.ComputerName -eq 'PC-FAIL' -and $_.Status -eq 'Failed'}).Count -ne 1 -or @($Csv|Where-Object{$_.ComputerName -eq 'PC-OFF' -and $_.Status -eq 'Unreachable'}).Count -ne 1){throw 'Failure/unreachable rows lost.'}
    if(-not [string]::IsNullOrEmpty(@($Csv|Where-Object ComputerName -eq 'PC-BAD')[0].Findings) -eq $false){throw 'Findings column empty for a bad PC.'}
    if((Get-RemoteOpsRowCategory $Csv[0]) -ne 'success' -or (Get-RemoteOpsRowCategory @($Csv|Where-Object ComputerName -eq 'PC-FAIL')[0]) -ne 'issue'){throw 'Health rows are not classified correctly by the report layer.'}
    if($script:AOHealthDetails.Count -ne 5){throw 'Detail records missing.'}
    $Html=Write-AOHealthHtmlReport -Path (Join-Path $Temp 'Health.html') -Details @($script:AOHealthDetails) -OperationID 'HEALTH-1'
    $Text=Get-Content -LiteralPath $Html -Raw
    if($Text -match '<script>x</script>' -or $Text -notmatch 'application/json'){throw 'Computer name must not appear as raw markup inside the report.'}
    $Json=[regex]::Match($Text,'(?s)<script id="data" type="application/json">(.*?)</script>').Groups[1].Value
    $Parsed=@(ConvertFrom-Json -InputObject $Json|ForEach-Object{$_})
    if($Parsed.Count -ne 5 -or @($Parsed|Where-Object{$_.computer -eq '<script>x</script>'}).Count -ne 1){throw 'Embedded JSON does not round-trip.'}
    $One=@($Parsed|Where-Object computer -eq 'PC-BAD')[0]
    if($One.health -ne 'Critical' -or $One.disks[0].usedPercent -ne 97 -or $One.sccm.service -ne 'Stopped' -or $One.apps.Count -ne 1){throw 'Detail JSON content is wrong.'}
    # single detail must still serialize as an array
    $SingleHtml=Write-AOHealthHtmlReport -Path (Join-Path $Temp 'Single.html') -Details @($script:AOHealthDetails[0]) -OperationID 'ONE'
    $SingleJson=[regex]::Match((Get-Content -LiteralPath $SingleHtml -Raw),'(?s)<script id="data" type="application/json">(.*?)</script>').Groups[1].Value
    if(-not $SingleJson.StartsWith('[')){throw 'Single-computer payload must be a JSON array.'}
    $EmptyHtml=Write-AOHealthHtmlReport -Path (Join-Path $Temp 'Empty.html') -Details @() -OperationID 'NONE'
    if(-not(Test-Path $EmptyHtml)){throw 'Empty report missing.'}
    # JS syntax check with Node when available
    $Node=Get-Command node -ErrorAction SilentlyContinue
    if($null -ne $Node){
        $Script=[regex]::Match($Text,'(?s)<script>\s*(\(function.*?)</script>').Groups[1].Value
        $JsPath=Join-Path $Temp 'check.js';Set-Content -LiteralPath $JsPath -Value $Script -Encoding UTF8
        & $Node.Source --check $JsPath 2>&1|Out-Null
        if($LASTEXITCODE -ne 0){throw 'Report JavaScript has a syntax error.'}
    }
    if($PreviewPath){Copy-Item -LiteralPath $Html -Destination $PreviewPath -Force}
    Write-Output 'PASS: health evaluation rules, date parsing, batch rows/CSV, failure/unreachable handling, JSON-safe single HTML report.'
}
finally{if(Test-Path -LiteralPath $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue}}
