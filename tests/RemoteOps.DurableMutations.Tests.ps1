$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
function Register-AOModule{param($Name,$Version,$MinimumHostApiVersion,$SourcePath,$Initializer)}
function Register-AOModuleOperation{param($ModuleName,$Name,$DisplayName,$EntryPointName,$Handler)}
foreach($Name in @('RegistryOperations','ServiceTaskOperations')){. (Join-Path $Root ('Modules\'+$Name+'.ps1'))}
function New-CimSession{param($ComputerName,$SessionOption,$OperationTimeoutSec)'FAKE'}
function New-CimSessionOption{param($Protocol)$null}
function Remove-CimSession{param($CimSession)}
function Get-CimInstance{param($CimSession,$ClassName,$Filter)[PSCustomObject]@{Name='DemoSvc';State='Running';StartMode='Auto'}}
function Invoke-CimMethod{
    param($CimSession,$Namespace,$ClassName,$InputObject,$MethodName,$Arguments)
    if($MethodName -eq 'GetStringValue'){return [PSCustomObject]@{ReturnValue=0;sValue='original'}}
    $script:Calls+=@($MethodName);$script:Backups+=@(Test-Path -LiteralPath $script:ExpectedManifest -PathType Leaf)
    if(Test-Path -LiteralPath $script:ExpectedManifest){$script:SavedBeforeChange=@(Import-Csv $script:ExpectedManifest -Delimiter ';')}
    [PSCustomObject]@{ReturnValue=0}
}
function Write-Host{param([Parameter(Position=0)][object[]]$Object,$ForegroundColor)}
function Start-Process{param($FilePath)}
function Read-Host{param($Prompt)$script:Answers.Dequeue()}
$Temp=Join-Path $env:TEMP ('RemoteOpsDurable-'+[guid]::NewGuid().ToString('N'))
$ErrorsFound=New-Object 'System.Collections.Generic.List[string]'
try{
    foreach($Case in @(@('REGEDIT','Registry','2','SOFTWARE\Demo','V','new','EDIT','0'),@('REGDELETE','Registry','3','SOFTWARE\Demo','V','DELETE','0'),@('SVCSTOP','Service','2','DemoSvc','stop','STOP','0'),@('SVCMODE','Service','3','DemoSvc','demand','EDIT','0'))){
        $script:Calls=@();$script:Backups=@();$script:SavedBeforeChange=@();$script:Answers=New-Object 'System.Collections.Generic.Queue[string]'
        foreach($Answer in $Case[2..($Case.Count-1)]){$script:Answers.Enqueue($Answer)}
        $script:ExpectedManifest=Join-Path $Temp $(if($Case[1] -eq 'Registry'){'RegistryRollback\'+$Case[0]+'_'+$(if($Case[2] -eq '2'){'Edit'}else{'Delete'})+'.csv'}else{'ServiceTaskRollbacks\'+$Case[0]+'_Services.csv'})
        $Params=@{BasePath=$Temp;Systems=@('PC1');ReachableSystems=@('PC1');UnreachableSystems=@();OperationID=$Case[0];OperationDate='d';OperationTime='t';TechnicalLogWriter={param($Level,$Message)};OperationHistoryWriter={param($OperationID,$OperationDate,$OperationTime,$IstemciAdi,$Modul,$Operasyon,$Sonuc,$Aciklama)}}
        if($Case[1] -eq 'Registry'){[void](Invoke-RegistryOperationsMenu @Params)}else{[void](Invoke-ServiceTaskOperationsMenu @Params)}
        if($script:Calls.Count -ne 1 -or $script:Backups.Count -ne 1 -or -not $script:Backups[0]){$ErrorsFound.Add($Case[0]+': remote mutation occurred before durable backup')}
        elseif($Case[1] -eq 'Registry' -and $script:SavedBeforeChange[0].OldValue -ne 'original'){$ErrorsFound.Add($Case[0]+': old registry value absent from pre-change manifest')}
    }
    # Simulate a read-only/full backup volume: no remote write is permitted.
    function Write-RegistryOperationsManifest{param($Path,$Rows)throw 'Simulated backup write failure'}
    function Write-ServiceTaskManifest{param($Path,$Rows)throw 'Simulated backup write failure'}
    foreach($Type in @('Registry','Service')){
        $script:Calls=@();$script:Backups=@();$script:Answers.Clear()
        $InputAnswers=if($Type -eq 'Registry'){@('2','SOFTWARE\Demo','V','new','EDIT','0')}else{@('2','DemoSvc','stop','STOP','0')}
        foreach($Answer in $InputAnswers){$script:Answers.Enqueue($Answer)}
        $Params.OperationID='FAIL-'+$Type
        try{if($Type -eq 'Registry'){[void](Invoke-RegistryOperationsMenu @Params)}else{[void](Invoke-ServiceTaskOperationsMenu @Params)}}catch{}
        if($script:Calls.Count){$ErrorsFound.Add($Type+': backup failure did not block remote mutation')}
    }
}finally{if(Test-Path -LiteralPath $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force}}
if($ErrorsFound.Count){throw ($ErrorsFound -join "`n")}
Write-Output 'PASS: registry edit/delete and service stop/startup persist prior state before mutation; backup failures change nothing.'
