$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
foreach($Row in @(
 [pscustomobject]@{Status='Unreachable';ErrorDetail='RPC unavailable'},
 [pscustomobject]@{Outcome='Unreachable';Status='Unreachable'},
 [pscustomobject]@{ExecutionStatus='NotRun';Decision='Unreachable'},
 [pscustomobject]@{Durum='Erisilemedi'}
)) {if((Get-RemoteOpsRowCategory $Row) -ne 'neutral'){throw 'Unavailable target must be yellow/neutral'}}
foreach($Row in @([pscustomobject]@{Status='AccessDenied'},[pscustomobject]@{Status='Failed'},[pscustomobject]@{ExecutionStatus='NotRun';Decision='CheckFailed'})){
 if((Get-RemoteOpsRowCategory $Row) -ne 'issue'){throw 'Real failure lost its error category'}
}
$Temp=Join-Path $env:TEMP ('RemoteOpsYellow-'+[guid]::NewGuid().ToString('N'))
try{
 $Outcomes=@(foreach($Status in @('Success','Skipped','Unreachable','Error')){[pscustomobject]@{ComputerName=$Status;Outcome=$Status;CompletedAt=(Get-Date)}})
 Write-RemoteOpsLedger -BasePath $Temp -OperationID TEST -Operation FilePull -Category Files -Identity TEST -Outcomes $Outcomes|Out-Null
 $Report=Get-RemoteOpsDailyReport -BasePath $Temp
 if($Report.Skipped -ne 1 -or $Report.Unreachable -ne 1 -or $Report.Error -ne 1 -or $Report.Neutral -ne 2 -or $Report.Problems -ne 1){throw 'Daily counts must preserve raw outcomes and combine neutral only for display'}
 $Dashboard=Write-RemoteOpsDailyDashboardHtml -Path (Join-Path $Temp 'daily.html') -Report $Report
 $DailyText=[Net.WebUtility]::HtmlDecode((Get-Content -LiteralPath $Dashboard -Raw -Encoding UTF8))
 if($DailyText -match 'Hata / Erişilemedi' -or $DailyText -notmatch 'Atlandı / Yok / Erişilemedi <b>2</b>'){throw 'Daily dashboard graph must share the neutral group and updated labels'}
 $Html=Write-RemoteOpsResultHtml -Path (Join-Path $Temp 'result.html') -Title Test -OperationID TEST -Rows @([pscustomobject]@{ComputerName='OFF';Status='Unreachable'})
 $Text=Get-Content $Html -Raw -Encoding UTF8
 if($Text -notmatch 'data-status="neutral"'){throw 'HTML unreachable row must be yellow'}
 $Decoded=[Net.WebUtility]::HtmlDecode($Text)
 if($Decoded -notmatch 'Atlandı / Yok / Erişilemedi <b>1</b>' -or $Decoded -match 'Hata / Erişilemedi' -or $Text -notmatch '<i class="c-warn" style="width:100%' -or $Text -match '<i class="c-bad"'){throw 'Result distribution must show one yellow unreachable target and no red error segment'}
}finally{if(Test-Path -LiteralPath $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force}}
Write-Output 'PASS: unreachable is neutral; real failures remain red; daily raw outcomes preserved.'
