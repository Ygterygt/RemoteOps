$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
# Report layer edge cases: hostile/odd cell content, mixed schemas, rows without OperationID, and the daily report on empty,
# midnight-crossing, repeated-computer and corrupt-ledger inputs.
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
function Open-RemoteOpsHtmlFile {param([string]$Path)}
$Temp=Join-Path $env:TEMP ('RemoteOpsRep-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $Temp -Force|Out-Null
try{
    # ---- hostile content is encoded; CSV keeps ';' and line breaks intact
    $Hostile='<script>alert(1)</script> & "q" ; next'+"`r`n"+'line2 <img src=x onerror=alert(2)>'
    $Rows=@(
        [pscustomobject]@{OperationID='RUN-1';ComputerName='PC<1>';Status='Failed';ErrorDetail=$Hostile},
        [pscustomobject]@{OperationID='RUN-1';ComputerName='PC2';Status='Success';ErrorDetail=''},
        [pscustomobject]@{ComputerName='PC3';Status='Success';Extra='only here'},
        [pscustomobject]@{OperationID='OTHER';ComputerName='PCX';Status='Success';ErrorDetail=''}
    )
    $Csv=Join-Path $Temp 'src.csv'
    $Result=[pscustomobject]@{ResultCsv=$Csv;Rows=$Rows}
    $ReportRoot=Join-Path $Temp 'run'
    Complete-RemoteOpsReports -Result $Result -Title 'ServiceList' -OperationID 'RUN-1' -ReportRoot $ReportRoot -Messages @([pscustomobject]@{Message='a <b> & c'})
    $Html=Get-Content -LiteralPath (Join-Path $ReportRoot 'src.html') -Raw -Encoding UTF8
    if($Html -match '<script>alert|<img src=x'){throw 'Cell content must be HTML-encoded.'}
    if($Html -notmatch '&lt;script&gt;alert\(1\)&lt;/script&gt;'){throw 'Encoded script text must be visible.'}
    if($Html -notmatch 'PC&lt;1&gt;'){throw 'data-client / cell must encode angle brackets.'}
    if($Html -match 'data-client="PC<'){throw 'Attribute value must be encoded.'}
    $Back=@(Import-Csv -LiteralPath (Join-Path $ReportRoot 'src.csv') -Delimiter ';' -Encoding UTF8)
    if($Back.Count -ne 3){throw "Rows of another run must be dropped, rows without OperationID kept (got $($Back.Count))."}
    $First=$Back|Where-Object ComputerName -eq 'PC<1>'
    if($First.ErrorDetail -ne $Hostile){throw 'CSV must round-trip text containing ; quotes and a line break.'}
    foreach($Name in 'OperationID','ComputerName','Status','ErrorDetail','Extra'){if(@($Back[0].PSObject.Properties.Name) -notcontains $Name){throw "CSV schema union lacks $Name."}}
    $Act=Get-Content -LiteralPath (Join-Path $ReportRoot 'Activity.html') -Raw -Encoding UTF8
    if($Act -match 'a <b> &' -or $Act -notmatch 'a &lt;b&gt; &amp; c'){throw 'Activity messages must be encoded.'}
    # empty result
    $Empty=[pscustomobject]@{ResultCsv=(Join-Path $Temp 'e.csv');Rows=@()}
    Complete-RemoteOpsReports -Result $Empty -Title 'ServiceList' -OperationID 'RUN-2' -ReportRoot (Join-Path $Temp 'run2') -Messages @()
    if(-not(Test-Path (Join-Path $Temp 'run2\e.html'))){throw 'Empty result must still give a report.'}

    # ---- daily report
    $Base=Join-Path $Temp 'base'
    $Day=[datetime]'2026-03-10'
    $R0=Get-RemoteOpsDailyReport -BasePath $Base -Date $Day
    if($R0.Total -ne 0 -or $R0.Categories.Count -ne 0 -or $R0.TopComputers.Count -ne 0 -or $R0.SuccessPercent -ne 0 -or @($R0.Hours).Count -ne 24){throw 'Empty day must give zero totals without errors.'}
    $Ledger=Join-Path $Base 'Logs\Reports\Ledger';New-Item -ItemType Directory -Path $Ledger -Force|Out-Null
    # a run that crossed midnight: rows are attributed to the day they completed
    @('"CompletedAt";"OperationID";"Operation";"Category";"ComputerName";"Outcome";"Identity"'
      '"2026-03-10 23:59:58";"GUI-20260310-235950-AAAAAA";"HealthCheck";"Inventory";"PC1";"Success";"D\u"'
      '"2026-03-11 00:00:03";"GUI-20260310-235950-AAAAAA";"HealthCheck";"Inventory";"PC2";"Success";"D\u"'
      '"2026-03-10 08:00:00";"GUI-20260310-080000-BBBBBB";"ServiceList";"Services";"PC1";"Error";"D\u"'
      '"2026-03-10 09:00:00";"GUI-20260310-090000-CCCCCC";"ServiceList";"Services";"pc1";"Unreachable";"D\u"'
      '"2026-03-10 09:30:00";"GUI-20260310-093000-DDDDDD";"ServiceList";"Services";"PC1";"Weird";"D\u"')|Set-Content -LiteralPath (Join-Path $Ledger 'run1.csv') -Encoding UTF8
    $R1=Get-RemoteOpsDailyReport -BasePath $Base -Date $Day
    if($R1.Total -ne 5-1){throw "Day 10 must hold 4 rows (midnight row excluded), got $($R1.Total)."}
    if($R1.UniqueComputers -ne 1){throw 'PC1/pc1 are one computer (PC2 completed on the next day).'}
    if($R1.Runs -ne 4){throw 'Four distinct runs on the day.'}
    if($R1.Error -ne 2 -or $R1.Unreachable -ne 1 -or $R1.Success -ne 1){throw "Unknown outcome must count as Error (E=$($R1.Error) U=$($R1.Unreachable) S=$($R1.Success))."}
    # (an unknown outcome counts as Error in the totals but not as a 'problem' in the top list: only Error/Unreachable are problems)
    $Top=@($R1.TopComputers)[0]
    if($Top.ComputerName -ne 'PC1' -or $Top.Count -ne 4 -or $Top.Problems -ne 1){throw 'Repeated computer must be aggregated case-insensitively.'}
    if(@($R1.Hours)[23] -ne 1 -or @($R1.Hours)[8] -ne 1){throw 'Hour histogram wrong.'}
    $R2=Get-RemoteOpsDailyReport -BasePath $Base -Date ([datetime]'2026-03-11')
    if($R2.Total -ne 1){throw 'Midnight-crossing row belongs to the next day.'}
    # corrupt ledger files must not break the report
    Set-Content -LiteralPath (Join-Path $Ledger 'bad1.csv') -Value 'garbage without header' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $Ledger 'bad2.csv') -Value '' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $Ledger 'bad3.csv') -Value ('"Foo";"Bar"'+"`r`n"+'"1";"2"') -Encoding UTF8
    [IO.File]::WriteAllBytes((Join-Path $Ledger 'bad4.csv'),[byte[]](0,255,1,2,3,0,254))
    $R3=Get-RemoteOpsDailyReport -BasePath $Base -Date $Day -WarningAction SilentlyContinue
    if($R3.Total -ne 4){throw "Corrupt ledger files must be skipped (got $($R3.Total))."}
    $Dash=Join-Path $Temp 'dash.html';[void](Write-RemoteOpsDailyDashboardHtml -Path $Dash -Report $R3)
    if((Get-Item $Dash).Length -lt 500){throw 'Dashboard HTML missing.'}
    $RE=Get-RemoteOpsDailyReport -BasePath $Base -Date ([datetime]'2025-01-01');[void](Write-RemoteOpsDailyDashboardHtml -Path (Join-Path $Temp 'dash0.html') -Report $RE)
    Write-Output 'PASS: report layer edge cases (HTML/CSV injection and round trip, mixed schemas, missing OperationID, empty report) and daily report (empty day, midnight, repeated computer, unknown outcome, corrupt ledger files).'
}
finally{Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue}
