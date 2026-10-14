$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot;$Library=Join-Path $Root 'RemoteOps.App\RemoteOps.Packages.ps1';. $Library
$Temp=Join-Path $env:TEMP ('RemoteOpsConcurrent-'+[guid]::NewGuid().ToString('N'));$Processes=New-Object Collections.ArrayList
try{
    $Catalog=Join-Path $Temp 'catalog';$P=New-RemoteOpsPackageDefinition 'Concurrency';$P.Install.Enabled=$true;$P.Install.PackagePath='\\server\share';$P.Install.PackageFile='install.cmd';$P.Install.Application='Example';$P.TargetVersion='2.0'
    $Saved=Save-RemoteOpsPackageDefinition $Catalog $P 0
    $Child=Join-Path $Temp 'writer.ps1'
    @'
param($Library,$Catalog,$Id,$Gate,[int]$Index)
$ErrorActionPreference='Stop';. $Library
$Deadline=(Get-Date).AddSeconds(20)
while(-not(Test-Path -LiteralPath $Gate)){if((Get-Date) -gt $Deadline){exit 9};Start-Sleep -Milliseconds 20}
try{
    $P=Get-Content -LiteralPath (Get-RemoteOpsPackageRecordPath $Catalog $Id) -Raw -Encoding UTF8|ConvertFrom-Json
    $P.Description='Writer '+$Index
    Save-RemoteOpsPackageDefinition $Catalog $P 1|Out-Null
    exit 0
}catch{exit 2}
'@|Set-Content -LiteralPath $Child -Encoding UTF8
    $Gate=Join-Path $Temp 'go.signal'
    foreach($Index in 1..8){
        $Arguments='-NoProfile -ExecutionPolicy Bypass -File "{0}" -Library "{1}" -Catalog "{2}" -Id {3} -Gate "{4}" -Index {5}' -f $Child,$Library,$Catalog,$Saved.Id,$Gate,$Index
        $Process=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $Arguments -WindowStyle Hidden -PassThru
        [void]$Process.Handle;[void]$Processes.Add($Process)
    }
    Set-Content -LiteralPath $Gate -Value 'go'
    $Codes=@(foreach($Process in $Processes){if(-not $Process.WaitForExit(30000)){throw 'Concurrent writer timed out'};$Process.ExitCode})
    if(@($Codes|Where-Object{$_ -eq 0}).Count -ne 1 -or @($Codes|Where-Object{$_ -eq 2}).Count -ne 7){throw ('Expected one committed edit and seven conflicts, got '+($Codes -join ','))}
    $Reloaded=Get-RemoteOpsPackageCatalog $Catalog
    if($Reloaded.Errors.Count -or $Reloaded.Packages.Count -ne 1 -or $Reloaded.Packages[0].Revision -ne 2){throw 'Concurrent catalog write corrupted the record or silently lost revision protection'}
    if(@(Get-ChildItem -LiteralPath $Catalog -Filter '*.tmp' -File).Count){throw 'Concurrent write leaked temporary files'}
    Write-Output 'PASS: eight actual PowerShell writers; one commit, seven safe conflicts, valid revision and no temporary-file leak.'
}finally{
    foreach($Process in $Processes){if(-not $Process.HasExited){Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue};$Process.Dispose()}
    if(Test-Path -LiteralPath $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force}
}
