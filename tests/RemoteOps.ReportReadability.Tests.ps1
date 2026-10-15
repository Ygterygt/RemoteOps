param([string]$PreviewDirectory='')
$ErrorActionPreference='Stop';$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1');. (Join-Path $Root 'RemoteOps.App\RemoteOps.RecipeResults.ps1')
function Assert($C,$M){if(-not $C){throw $M}}
$Expected='Ad'+[char]0x131+'m sonucu do'+[char]0x11F+'rulanamad'+[char]0x131+'.'
$Actual=(Get-RemoteOpsRecipeStepDecision ServiceControl @{} @([pscustomobject]@{Status='Failed'}) @()).Reason
Assert ($Actual -ceq $Expected) 'Turkish result text is not preserved in Windows PowerShell5.1'
foreach($File in Get-ChildItem (Join-Path $Root 'RemoteOps.App') -Filter '*.ps1' -File){$Text=[IO.File]::ReadAllText($File.FullName);if($Text -cmatch '[^\x00-\x7F]'){$Bytes=[IO.File]::ReadAllBytes($File.FullName);Assert ($Bytes[0] -eq 239 -and $Bytes[1] -eq 187 -and $Bytes[2] -eq 191) ('Missing UTF8 BOM: '+$File.Name)}}
$Temp=Join-Path $env:TEMP ('ReportReadability_'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $Temp -Force|Out-Null
try{
 $Rows=@([pscustomobject]@{ComputerName='PC-IST-001';Operation='ServiceControl';StepIndex=1;Status='Failed';ErrorDetail=$Expected;OperationID='GUI-20261015-120000-ABCDEF';ParentRunId='GUI-20261015-120000-ABCDEF';OriginalOperationID='GUI-20261015-120000-ABCDEF-0001-S01';StepOperationID='GUI-20261015-120000-ABCDEF-0001-S01';StepId='97a270b1-0219-496f-8bde-249b20000000';RecipeId='11223344-5566-7788-9900-aabbccddeeff';RecipeRevision=2;SnapshotHash=('A'*64)},[pscustomobject]@{ComputerName='PC-IST-001';Operation='ServiceControl';StepIndex=2;Status='NotRun';ErrorDetail=$Expected;OperationID='GUI-20261015-120000-ABCDEF';ParentRunId='GUI-20261015-120000-ABCDEF';OriginalOperationID='';StepOperationID='GUI-20261015-120000-ABCDEF-0001-S02';StepId='<script>alert(1)</script>';RecipeId='11223344-5566-7788-9900-aabbccddeeff';RecipeRevision=2;SnapshotHash=('A'*64)})
 $Csv=Join-Path $Temp 'Results.csv';$Rows|Export-Csv $Csv -NoTypeInformation -Delimiter ';' -Encoding UTF8;$Hash=(Get-FileHash $Csv).Hash
 $Path=Join-Path $Temp 'Results.html';Write-RemoteOpsResultHtml -Path $Path -Title 'Reçete sonucu · örnek veri' -OperationID 'GUI-20261015-120000-ABCDEF' -Rows $Rows -CsvPath $Csv
 $Html=[IO.File]::ReadAllText($Path);$Header=[regex]::Match($Html,'(?s)<table id="results"[^>]*>\s*<thead>(.*?)</thead>').Groups[1].Value
 Assert ($Header -and $Header -notmatch 'OperationID|StepId|ParentRunId|SnapshotHash|RecipeId|RecipeRevision') 'Technical IDs still crowd main header'
 Assert ($Html -match '<details class="technical-details"' -and $Html -match '97a270b1-0219-496f-8bde-249b20000000') 'Technical IDs lost from detail'
 Assert ($Html -notmatch '<script>alert\(1\)</script>' -and $Html -match '&lt;script&gt;alert\(1\)&lt;/script&gt;') 'Detail HTML escaping lost'
 Assert ($Html.Contains($Expected) -and $Html -notmatch 'AdÄ|doÄ') 'Generated report mojibake'
 Assert ($Html -match 'min-width:140px' -and $Html -match 'width:max-content' -and $Html -match 'word-break:normal') 'Readable widths/scroll absent'
 Assert ((Get-FileHash $Csv).Hash -eq $Hash) 'Raw CSV was altered'
 Assert ($Html -notmatch '>NotRun<') 'NotRun not translated for display'
 if($PreviewDirectory){New-Item -ItemType Directory $PreviewDirectory -Force|Out-Null;Copy-Item $Csv (Join-Path $PreviewDirectory 'Results.csv');Write-RemoteOpsResultHtml -Path (Join-Path $PreviewDirectory 'Results.html') -Title 'Reçete sonucu · örnek veri' -OperationID 'GUI-20261015-120000-ABCDEF' -Rows $Rows -CsvPath (Join-Path $PreviewDirectory 'Results.csv')}
 Write-Host 'PASS PS5.1 Turkish text/BOM, readable HTML, technical details, escaping and untouched CSV'
}finally{Remove-Item -LiteralPath $Temp -Recurse -Force}
