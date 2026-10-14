$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
# Mock-only tests for state-changing registry/service/process operations: wrong confirmation words must change nothing,
# non-string registry values must never be overwritten/deleted (no backup possible), and delete + rollback must round-trip.
. (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
function Register-AOModule {param($Name,$Version,$MinimumHostApiVersion,$SourcePath,$Initializer)}
function Register-AOModuleOperation {param($ModuleName,$Name,$DisplayName,$EntryPointName,$Handler)}
foreach($Module in 'RegistryOperations','ServiceTaskOperations'){. (Join-Path $Root "Modules\$Module.ps1")}
$script:Answers=New-Object 'System.Collections.Generic.Queue[string]'
function Read-Host {param([string]$Prompt)if($script:Answers.Count -eq 0){throw "No answer for: $Prompt"};return $script:Answers.Dequeue()}
function Write-Host {param([Parameter(Position=0)][object[]]$Object,[object]$ForegroundColor)}
function Start-Process {param($FilePath)}
function New-CimSession {param($ComputerName,$SessionOption,$OperationTimeoutSec)return "SESSION:$ComputerName"}
function New-CimSessionOption {param($Protocol)return $null}
function Remove-CimSession {param($CimSession)}
$script:Calls=@();$script:RegMode='string';$script:RegValue='old'
function Invoke-CimMethod {
    param($CimSession,$Namespace,$ClassName,$InputObject,$MethodName,$Arguments)
    if($MethodName -eq 'GetStringValue'){
        if($script:RegMode -eq 'dword'){return [PSCustomObject]@{ReturnValue=[uint32]2147749893;sValue=$null}}
        if($script:RegMode -eq 'missing'){return [PSCustomObject]@{ReturnValue=[uint32]2;sValue=$null}}
        if($script:RegMode -eq 'error1'){return [PSCustomObject]@{ReturnValue=[uint32]1;sValue=$null}}
        if($script:RegMode -eq 'denied'){return [PSCustomObject]@{ReturnValue=[uint32]5;sValue=$null}}
        return [PSCustomObject]@{ReturnValue=[uint32]0;sValue=$script:RegValue}
    }
    $script:Calls+=$MethodName
    return [PSCustomObject]@{ReturnValue=[uint32]0}
}
function Get-CimInstance {
    param($CimSession,$ClassName,$Filter,$Namespace)
    switch($ClassName){
        'Win32_Service'{return [PSCustomObject]@{Name='Svc1';State='Running';StartMode='Auto';DisplayName='Svc1'}}
        'Win32_Process'{return @([PSCustomObject]@{Name='mysvc.exe';ProcessId=13;CreationDate=(Get-Date);ExecutablePath='C:\x\mysvc.exe'})}
        default{return @()}
    }
}
$Temp=Join-Path $env:TEMP ('RemoteOpsMut-'+[guid]::NewGuid().ToString('N'))
function Common {param([string]$OpId='OP-1')@{BasePath=$Temp;Systems=[string[]]@('PC1');ReachableSystems=[string[]]@('PC1');UnreachableSystems=[string[]]@();OperationID=$OpId;OperationDate='d';OperationTime='t';TechnicalLogWriter={param($Level,$Message)};OperationHistoryWriter={param($OperationID,$OperationDate,$OperationTime,$IstemciAdi,$Modul,$Operasyon,$Sonuc,$Aciklama)}}}
function Add-Answers {param([string[]]$Values)foreach($V in $Values){$script:Answers.Enqueue($V)}}
function Assert-NoWrite($Case){if(@($script:Calls).Count -ne 0){throw "$Case changed state: $(@($script:Calls) -join ',')"}}
try{
    # --- wrong confirmation words change nothing
    foreach($Case in @(
        @('registry edit','2','SOFTWARE\T','V','new','edit-me'),
        @('registry delete','3','SOFTWARE\T','V','nope')
    )){
        $script:Calls=@();$script:Answers.Clear()
        Add-Answers ($Case[1..($Case.Count-1)]+'0')
        [void](&{$C=Common;Invoke-RegistryOperationsMenu @C})
        Assert-NoWrite $Case[0]
    }
    # --- registry delete round trip: manifest keeps the old string, rollback restores it
    $script:Calls=@();$script:RegMode='string';$script:RegValue='keep-me'
    Add-Answers '3','SOFTWARE\T','V','DELETE','0'
    $R=&{$C=Common 'DEL-1';Invoke-RegistryOperationsMenu @C}
    $Rows=@(Import-Csv -LiteralPath $R.ResultCsv -Delimiter ';')
    if($Rows.Count -ne 1 -or $Rows[0].Status -ne 'Success' -or @($script:Calls) -join ',' -ne 'DeleteValue'){throw 'Registry delete must call DeleteValue once and report Success.'}
    $Manifest=@(Get-ChildItem (Join-Path $Temp 'RegistryRollback') -Filter 'DEL-1_Delete.csv')
    if($Manifest.Count -ne 1){throw 'Registry delete must write a rollback manifest.'}
    $M=@(Import-Csv -LiteralPath $Manifest[0].FullName -Delimiter ';')
    if($M[0].OldValue -ne 'keep-me' -or $M[0].OldExists -ne 'True'){throw 'Rollback manifest must keep the previous value.'}
    $script:Calls=@()
    Add-Answers '4',$Manifest[0].FullName,'ROLLBACK','0'
    [void](&{$C=Common 'RB-1';Invoke-RegistryOperationsMenu @C})
    if(@($script:Calls) -join ',' -ne 'SetStringValue'){throw "Registry rollback must restore the old string (calls: $(@($script:Calls) -join ','))."}
    $script:Calls=@()
    Add-Answers '4',$Manifest[0].FullName,'NO','0'
    [void](&{$C=Common 'RB-2';Invoke-RegistryOperationsMenu @C})
    Assert-NoWrite 'registry rollback with wrong confirmation'
    # --- non-REG_SZ value (e.g. DWORD): GetStringValue returns a type-mismatch code; edit/delete must be refused
    $script:RegMode='dword'
    foreach($Case in @(@('edit','2','SOFTWARE\T','V','new','EDIT'),@('delete','3','SOFTWARE\T','V','DELETE'))){
        $script:Calls=@()
        Add-Answers ($Case[1..($Case.Count-1)]+'0')
        $R=&{$C=Common ('DW-'+$Case[0]);Invoke-RegistryOperationsMenu @C}
        Assert-NoWrite "registry $($Case[0]) of a non-string value"
        $Rows=@(Import-Csv -LiteralPath $R.ResultCsv -Delimiter ';')
        if($Rows.Count -ne 1 -or $Rows[0].Status -ne 'Failed' -or $Rows[0].ErrorDetail -notmatch 'Nothing was changed'){throw "Registry $($Case[0]) of a non-string value must be a Failed row."}
        if(@(Get-ChildItem (Join-Path $Temp 'RegistryRollback') -Filter ('DW-'+$Case[0]+'*') -ErrorAction SilentlyContinue).Count -ne 0){throw 'A refused change must not write a rollback manifest.'}
    }
    foreach($Mode in 'error1','denied'){
        $script:RegMode=$Mode
        foreach($Case in @(@('edit','2','SOFTWARE\T','V','new','EDIT'),@('delete','3','SOFTWARE\T','V','DELETE'),@('read','1','SOFTWARE\T','V'))){
            $script:Calls=@()
            Add-Answers ($Case[1..($Case.Count-1)]+'0')
            $R=&{$C=Common ($Mode+'-'+$Case[0]);Invoke-RegistryOperationsMenu @C}
            Assert-NoWrite ($Mode+' '+$Case[0])
            $Rows=@(Import-Csv -LiteralPath $R.ResultCsv -Delimiter ';')
            if($Rows.Count -ne 1 -or $Rows[0].Status -ne 'Failed'){throw 'An unreadable registry value must report Failed.'}
        }
    }
    # --- value that does not exist yet: edit may create it (rollback deletes it), delete reports Failed from the API
    $script:RegMode='missing';$script:Calls=@()
    Add-Answers '2','SOFTWARE\T','V','new','EDIT','0'
    [void](&{$C=Common 'NEW-1';Invoke-RegistryOperationsMenu @C})
    if(@($script:Calls) -join ',' -ne 'SetStringValue'){throw 'Edit of a missing string value must create it.'}
    $M=@(Import-Csv -LiteralPath (Join-Path $Temp 'RegistryRollback\NEW-1_Edit.csv') -Delimiter ';')
    if($M[0].OldExists -ne 'False'){throw 'Manifest of a created value must record OldExists=False.'}
    # --- services / processes: wrong confirmation words change nothing
    $script:Calls=@();$script:RegMode='string'
    foreach($Case in @(@('service control','2','Svc1','stop','nope'),@('service startup','3','Svc1','demand','nope'),@('process kill','10','mysvc','nope'))){
        $script:Answers.Clear()
        Add-Answers ($Case[1..($Case.Count-1)]+'0')
        [void](&{$C=Common;Invoke-ServiceTaskOperationsMenu @C})
        Assert-NoWrite $Case[0]
    }
    Write-Output 'PASS: wrong confirmation changes nothing (registry/service/process), registry delete+rollback round trip, non-string registry values are never overwritten or deleted.'
}
finally{if(Test-Path -LiteralPath $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue}}
