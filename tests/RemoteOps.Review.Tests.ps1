$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$OperationName='Fixture';$Values=[pscustomobject]@{}
function Test-RemoteOpsOperationAccess {param($ComputerName,$Operation,$InputValues)[pscustomobject]@{Status='Success';Detail='isolated fixture'}}
$Root=Split-Path -Parent $PSScriptRoot
# Regression checks for the 2026-10 review findings:
#  1) per-target row scoping (a multi-computer Restore must not mark a restored target Unreachable)
#  2) FileOperations paths that return to the menu still produce result rows (no generic NoData)
#  3) FileBrowser success messages carry the computer prefix, so the outcome is Success (not Error)
#  4) FileCompare 'Farkli' is a neutral result, not an error
#  5) input pre-validation stops bad Push/Compare/Restore input with a clear message
#  6) file operations return a small per-run CSV instead of the ever-growing history file
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
$Tokens=$null;$Errors=$null
$Ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'RemoteOps.App\RemoteOps.Runner.ps1'),[ref]$Tokens,[ref]$Errors)
if($Errors.Count){throw ($Errors|Out-String)}
foreach($Name in @('Register-AOModule','Register-AOModuleOperation','Test-ConsoleMenuText','Write-Host','Read-Host','Add-Answers','Write-TargetProgress','Invoke-TargetBatch','Get-TargetOutcome','Assert-RemoteOpsRequestValues')){
    $Definition=$Ast.Find({param($Node)$Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq $Name},$true)
    if($null -eq $Definition){throw "Runner function not found: $Name"}
    Set-Item ('Function:\'+$Name) -Value $Definition.Body.GetScriptBlock()
}
$script:AOModules=@();$script:AOModuleOperations=@();$script:OperationMessages=@();$script:ReportCandidates=@();$script:PromptAnswers=New-Object 'System.Collections.Generic.Queue[string]'
. (Join-Path $Root 'Modules\FileOperations.ps1')
function Start-Process { param($FilePath) $script:ReportCandidates+=[string]$FilePath }
function Write-RemoteOpsLog { param($Level,$Message) }
function Write-RemoteOpsHistory { param($OperationID,$OperationDate,$OperationTime,$IstemciAdi,$Modul,$Operasyon,$Sonuc,$Aciklama) }
$TempRoot=if($env:TEMP){$env:TEMP}else{[System.IO.Path]::GetTempPath()}
$Temporary=Join-Path $TempRoot ('RemoteOpsReview-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Temporary|Out-Null
try{
    $BasePath=$Temporary;$RunReportRoot=$Temporary;$OperationDate='2026-10-12';$OperationTime='10:00:00'

    # 1) row scoping: target PC-A gets its own Success row plus an 'Erisilemedi' row for PC-B (multi-PC backup)
    $Common=@{BasePath=$BasePath;Systems=@('PC-A');ReachableSystems=@('PC-A');UnreachableSystems=@();OperationID='SCOPE';OperationDate=$OperationDate;OperationTime=$OperationTime;TechnicalLogWriter=${function:Write-RemoteOpsLog};OperationHistoryWriter=${function:Write-RemoteOpsHistory}}
    $Captured=@(& {
        Invoke-TargetBatch -InputTargets @('PC-A','PC-C') -RunOperationID 'SCOPE' -ProgressPath '' -InvokeTarget {
            $Rows=@()
            if($Systems[0] -eq 'PC-A'){$Rows+=[PSCustomObject]@{IstemciAdi='PC-A';Durum='Success'}}
            $Rows+=[PSCustomObject]@{IstemciAdi='PC-B';Durum='Erisilemedi'}
            return [PSCustomObject]@{ResultCsv=(Join-Path $Temporary ($Systems[0]+'.csv'));Rows=$Rows}
        }
    } 6>&1)
    $HostLines=@($Captured|Where-Object{$_ -is [System.Management.Automation.InformationRecord]}|ForEach-Object{$_.MessageData.ToString()})
    if(($HostLines -join '|') -ne 'PC-A - Success|PC-C - Skipped'){throw "Row scoping failed: $($HostLines -join '|')"}
    $Batch=@($Captured|Where-Object{$null -ne $_.PSObject.Properties['Rows']})[0]
    if(@($Batch.Rows|Where-Object{(Get-RemoteOpsRowValue -Row $_ -Names @('ComputerName','IstemciAdi')) -eq 'PC-B'}).Count -ne 0){throw 'Rows of another computer leaked into the run report.'}

    # 4) FileCompare 'Farkli' is neutral
    if((Get-RemoteOpsRowCategory ([PSCustomObject]@{Durum='Farkli'})) -ne 'neutral'){throw "'Farkli' must be neutral."}
    if((Get-RemoteOpsRowCategory ([PSCustomObject]@{Durum='Esit'})) -ne 'success'){throw "'Esit' must stay success."}

    # 3) FileBrowser Pull: message prefix -> Success
    $RemoteRoot=Join-Path $Temporary 'remote';New-Item -ItemType Directory -Path $RemoteRoot -Force|Out-Null
    Set-Content -LiteralPath (Join-Path $RemoteRoot 'a.log') -Value 'x'
    $script:MockRemote=$RemoteRoot
    function ConvertTo-AORemoteAdminPath { param($ComputerName,$LocalPath) return $script:MockRemote }
    $script:OperationMessages=@()
    Add-Answers @('C:\Browse','1','1','0')
    $script:TargetOutputQuiet=$true
    Invoke-AORemoteFileBrowseOperations -BasePath $BasePath -Systems @('PC-A') -ReachableSystems @('PC-A') -OperationID 'BROWSE'
    $script:TargetOutputQuiet=$false
    $Outcome=Get-TargetOutcome -Rows @() -Messages $script:OperationMessages -Target 'PC-A'
    if($Outcome -ne 'Success'){throw "FileBrowser pull was reported as $Outcome. Messages: $(($script:OperationMessages|ForEach-Object Message) -join ' / ')"}
    Remove-Item Function:\ConvertTo-AORemoteAdminPath
    $script:PromptAnswers.Clear()

    # 2) FileDelete that never reaches DELETE (not found / blocked) still yields a result row, not NoData
    $OperationName='FileDelete'
    $Values=[PSCustomObject]@{Path='C:\RemoteOpsReview\does-not-exist.txt';Confirm='DELETE'}
    $Request=[PSCustomObject]@{Operation=$OperationName;Targets=@('PC-D');Values=$Values}
    $Common=@{BasePath=$BasePath;Systems=@('PC-D');ReachableSystems=@('PC-D');UnreachableSystems=@();OperationID='DELROW';OperationDate=$OperationDate;OperationTime=$OperationTime;TechnicalLogWriter=${function:Write-RemoteOpsLog};OperationHistoryWriter=${function:Write-RemoteOpsHistory}}
    $Assignment=$Ast.Find({param($Node)$Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $Node.Left.Extent.Text -eq '$InvokeTarget'},$true)
    Invoke-Expression $Assignment.Extent.Text
    $Captured=@(& { Invoke-TargetBatch -InputTargets @('PC-D') -RunOperationID 'DELROW' -ProgressPath '' -InvokeTarget $InvokeTarget } 6>&1)
    $Batch=@($Captured|Where-Object{$null -ne $_.PSObject.Properties['Rows']})[0]
    if($Batch.Rows.Count -lt 1 -or [string](Get-RemoteOpsRowValue -Row $Batch.Rows[0] -Names @('Status','Durum')) -eq 'NoData'){throw 'FileDelete without DELETE lost its result row (NoData).'}
    if([string]$Batch.Rows[0].HedefPath -eq ''){throw 'FileDelete result row has no target path.'}
    # result comes from the small per-run copy; the cumulative history file is still written
    $FileLogs=Join-Path (Join-Path $BasePath 'Logs') 'FileOperations'
    if(-not(Test-Path -LiteralPath (Join-Path $FileLogs 'DELROW-0001_FileDelete.csv'))){throw 'Per-run FileDelete CSV was not written.'}
    if(-not(Test-Path -LiteralPath (Join-Path $FileLogs 'MD_FileDelete.csv'))){throw 'Cumulative FileDelete history was not written.'}

    # 5) input pre-validation
    $Threw='';try{Assert-RemoteOpsRequestValues -OperationName 'FilePush' -InputValues ([PSCustomObject]@{LocalPath=(Join-Path $Temporary 'missing-src')})}catch{$Threw=$_.Exception.Message}
    if($Threw -notmatch 'Push kaynagi bulunamadi'){throw "Push pre-validation missing: $Threw"}
    $Threw='';try{Assert-RemoteOpsRequestValues -OperationName 'FileCompare' -InputValues ([PSCustomObject]@{LocalPath=(Join-Path $Temporary 'missing.ini')})}catch{$Threw=$_.Exception.Message}
    if($Threw -notmatch 'Referans dosyasi bulunamadi'){throw "Compare pre-validation missing: $Threw"}
    $Threw='';try{Assert-RemoteOpsRequestValues -OperationName 'FileRestore' -InputValues ([PSCustomObject]@{BackupPath=''})}catch{$Threw=$_.Exception.Message}
    if($Threw -notmatch 'silme yedegi bulunamadi'){throw "Restore pre-validation (no backups) missing: $Threw"}
    $Run=Join-Path (Join-Path $BasePath 'DeleteBackups') 'OP-1_Delete';New-Item -ItemType Directory -Path $Run -Force|Out-Null;Set-Content -LiteralPath (Join-Path $Run 'manifest.csv') -Value 'x'
    $Threw='';try{Assert-RemoteOpsRequestValues -OperationName 'FileRestore' -InputValues ([PSCustomObject]@{BackupPath='3'})}catch{$Threw=$_.Exception.Message}
    if($Threw -notmatch 'Yedek numarasi gecersiz'){throw "Restore pre-validation (bad index) missing: $Threw"}
    Assert-RemoteOpsRequestValues -OperationName 'FileRestore' -InputValues ([PSCustomObject]@{BackupPath=''})
    Assert-RemoteOpsRequestValues -OperationName 'ServiceList' -InputValues ([PSCustomObject]@{Filter=''})

    Write-Output 'PASS: review regressions (per-target row scoping, FileDelete rows without DELETE, FileBrowser success outcome, Compare Farkli neutral, input pre-validation).'
}
finally{Remove-Item -LiteralPath $Temporary -Recurse -Force -ErrorAction SilentlyContinue}
